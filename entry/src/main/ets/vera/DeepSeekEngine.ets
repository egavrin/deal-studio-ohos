/**
 * DeepSeek chat-completions client.
 *
 * Same shape as LlamaEngine, so GeneratePage.runAttempt drives either provider:
 * generate() takes a GenerateRequest and streams tokens through a callback. The
 * difference is that the model is remote, so the call is a Promise. Everything
 * downstream -- compiling with VeraCompiler, feeding diagnostics back, retrying
 * -- still happens on the device.
 *
 * The API is OpenAI-compatible: POST {baseUrl}/chat/completions with a Bearer
 * key. Responses stream as Server-Sent Events, one 'data: {...}' line per
 * chunk, terminated by 'data: [DONE]'.
 *
 * Unlike llama.cpp there is no GBNF grammar to constrain decoding, so vera.gbnf
 * is unused here and the output goes through extractVeraSource() in case the
 * model wraps the program in a markdown fence anyway.
 */

import http from '@ohos.net.http'
import util from '@ohos.util'
import { GenerateRequest, GenerateResult, TokenCallback } from './LlamaEngine'
import { settings } from './SettingsStore'

class ChatMessage {
  role: string = ''
  content: string = ''
  constructor(role: string, content: string) {
    this.role = role
    this.content = content
  }
}

/**
 * Pull the program out of a model reply. A well-behaved reply is already bare
 * source; this only earns its keep when the model adds a markdown fence.
 */
export function extractVeraSource(text: string): string {
  let trimmed = text.trim()
  let fence = trimmed.indexOf('```')
  if (fence < 0) { return trimmed }
  let afterOpen = trimmed.indexOf('\n', fence)
  if (afterOpen < 0) { return trimmed }
  let rest = trimmed.substring(afterOpen + 1)
  let close = rest.indexOf('```')
  if (close < 0) { return rest.trim() }
  return rest.substring(0, close).trim()
}

function httpErrorMessage(code: number, body: string): string {
  let detail = ''
  try {
    let obj = JSON.parse(body) as Record<string, Object>
    let err = obj['error'] as Record<string, Object>
    if (err !== null && err !== undefined) {
      let msg = err['message']
      if (typeof msg === 'string') { detail = msg as string }
    }
  } catch (_e) {
    detail = body.substring(0, 200)
  }
  let prefix = ''
  if (code === 401) {
    prefix = 'API key rejected (401). Re-send it with: aa start -a EntryAbility -b com.vera.probe.dyn --ps deepseekKey <key>'
  } else if (code === 402) {
    prefix = 'DeepSeek account out of balance (402)'
  } else if (code === 429) {
    prefix = 'Rate limited (429), retry in a moment'
  } else if (code === 400) {
    prefix = 'Request rejected (400)'
  } else if (code >= 500) {
    prefix = 'DeepSeek server error (' + code + ')'
  } else {
    prefix = 'HTTP ' + code
  }
  return detail.length > 0 ? prefix + ' -- ' + detail : prefix
}

export class DeepSeekEngine {
  private client: http.HttpRequest | null = null
  private generating: boolean = false
  private cancelled: boolean = false
  private buffer: string = ''
  private rawBody: string = ''
  private text: string = ''
  private inputTokens: number = 0
  private outputTokens: number = 0
  private cacheHitTokens: number = 0
  private finishReason: string = ''
  private thinking: boolean = false
  // Reasoning arrives as its own delta field and is billed as output, so a
  // thinking model looks like a long silence followed by an impossibly fast
  // stream unless the two are timed apart.
  private startedAt: number = 0
  private firstAnyAt: number = 0
  private firstContentAt: number = 0

  /**
   * Thinking is on by default for this model and is billed and capped as
   * output tokens, so a modest max_tokens gets spent reasoning and the program
   * is cut off mid-statement. Callers turn it on only when it is worth paying
   * for.
   */
  setThinking(enabled: boolean): void { this.thinking = enabled }

  isGenerating(): boolean { return this.generating }
  isReady(): boolean { return settings.hasApiKey() }
  lastCacheHitTokens(): number { return this.cacheHitTokens }
  /** Time until the model said anything at all -- reading the prompt. */
  lastPrefillMs(): number {
    return this.firstAnyAt > 0 ? this.firstAnyAt - this.startedAt : 0
  }
  /** Time spent reasoning before the first line of the program appeared. */
  lastThinkMs(): number {
    if (this.firstContentAt === 0 || this.firstAnyAt === 0) { return 0 }
    return this.firstContentAt - this.firstAnyAt
  }
  lastFinishReason(): string { return this.finishReason }

  async generate(request: GenerateRequest, onToken: TokenCallback): Promise<GenerateResult> {
    let key = settings.getApiKey()
    if (key.length === 0) {
      throw new Error('No DeepSeek API key. Send one with: aa start -a EntryAbility -b com.vera.probe.dyn --ps deepseekKey <key>')
    }

    this.buffer = ''
    this.rawBody = ''
    this.text = ''
    this.inputTokens = 0
    this.outputTokens = 0
    this.cacheHitTokens = 0
    this.finishReason = ''
    this.cancelled = false
    this.generating = true
    this.startedAt = Date.now()
    this.firstAnyAt = 0
    this.firstContentAt = 0

    let client = http.createHttp()
    this.client = client
    let decoder = util.TextDecoder.create('utf-8')

    client.on('dataReceive', (chunk: ArrayBuffer): void => {
      let piece = ''
      try {
        piece = decoder.decodeToString(new Uint8Array(chunk), { stream: true })
      } catch (e) {
        console.error('DeepSeek decode failed: ' + (e as Error).message)
        return
      }
      this.rawBody += piece
      this.feed(piece, onToken)
    })

    let code = 0
    try {
      let header: Record<string, string> = {}
      header['Content-Type'] = 'application/json'
      header['Accept'] = 'text/event-stream'
      header['Authorization'] = 'Bearer ' + key
      code = await client.requestInStream(settings.getBaseUrl() + '/chat/completions', {
        method: http.RequestMethod.POST,
        header: header,
        extraData: this.buildBody(request),
        connectTimeout: 15000,
        readTimeout: 300000
      })
    } catch (e) {
      if (this.cancelled) {
        // stop() destroyed the client mid-flight; keep whatever streamed in.
        code = 200
      } else {
        this.cleanup(client)
        throw new Error('DeepSeek request failed: ' + (e as Error).message)
      }
    }

    this.cleanup(client)

    if (code !== 200) {
      throw new Error(httpErrorMessage(code, this.rawBody))
    }

    let result = new GenerateResult()
    result.text = extractVeraSource(this.text)
    result.inputTokens = this.inputTokens
    result.outputTokens = this.outputTokens
    return result
  }

  stop(): void {
    if (!this.generating) { return }
    this.cancelled = true
    let client = this.client
    if (client !== null) {
      try { client!.destroy() } catch (_e) {}
    }
    this.generating = false
  }

  private cleanup(client: http.HttpRequest): void {
    try { client.off('dataReceive') } catch (_e) {}
    try { client.destroy() } catch (_e) {}
    this.client = null
    this.generating = false
  }

  private buildBody(request: GenerateRequest): string {
    let messages: ChatMessage[] = []
    if (request.systemPrompt.length > 0) {
      messages.push(new ChatMessage('system', request.systemPrompt))
    }
    // Mirrors LlamaEngine.buildPrompt: an existing program is replayed as the
    // assistant's own last turn, so the model edits it instead of restarting.
    if (request.previousSource.length > 0) {
      messages.push(new ChatMessage('assistant', request.previousSource))
      messages.push(new ChatMessage('user', 'Refine the program above: ' + request.userPrompt))
    } else {
      messages.push(new ChatMessage('user', request.userPrompt))
    }

    let payload: Record<string, Object> = {}
    payload['model'] = settings.getModel()
    payload['messages'] = messages
    payload['stream'] = true
    // Without this the streamed response carries no token counts at all.
    let streamOptions: Record<string, Object> = {}
    streamOptions['include_usage'] = true
    payload['stream_options'] = streamOptions
    let thinking: Record<string, Object> = {}
    thinking['type'] = this.thinking ? 'enabled' : 'disabled'
    payload['thinking'] = thinking
    payload['temperature'] = request.temperature
    payload['max_tokens'] = request.maxTokens
    return JSON.stringify(payload)
  }

  /**
   * Accumulate stream text and hand over every complete line. A chunk can end
   * mid-line, so the tail stays in the buffer until the next chunk arrives.
   */
  private feed(piece: string, onToken: TokenCallback): void {
    this.buffer += piece
    let nl = this.buffer.indexOf('\n')
    while (nl >= 0) {
      let line = this.buffer.substring(0, nl)
      this.buffer = this.buffer.substring(nl + 1)
      this.handleLine(line.trim(), onToken)
      nl = this.buffer.indexOf('\n')
    }
  }

  private handleLine(line: string, onToken: TokenCallback): void {
    if (line.length === 0 || !line.startsWith('data:')) { return }
    let payload = line.substring(5).trim()
    if (payload.length === 0 || payload === '[DONE]') { return }
    let obj: Record<string, Object>
    try {
      obj = JSON.parse(payload) as Record<string, Object>
    } catch (_e) {
      // A non-SSE body (an error JSON) also arrives here; rawBody keeps it.
      return
    }

    let choices = obj['choices'] as Object[]
    if (choices !== null && choices !== undefined && choices.length > 0) {
      let choice = choices[0] as Record<string, Object>
      let delta = choice['delta'] as Record<string, Object>
      if (delta !== null && delta !== undefined) {
        let reasoning = delta['reasoning_content']
        if (typeof reasoning === 'string' && (reasoning as string).length > 0) {
          if (this.firstAnyAt === 0) { this.firstAnyAt = Date.now() }
        }
        let content = delta['content']
        if (typeof content === 'string') {
          let token = content as string
          if (token.length > 0) {
            if (this.firstAnyAt === 0) { this.firstAnyAt = Date.now() }
            if (this.firstContentAt === 0) { this.firstContentAt = Date.now() }
            this.text += token
            onToken(token)
          }
        }
      }
      let reason = choice['finish_reason']
      if (typeof reason === 'string') { this.finishReason = reason as string }
    }

    let usage = obj['usage'] as Record<string, Object>
    if (usage !== null && usage !== undefined) {
      let input = usage['prompt_tokens']
      if (typeof input === 'number') { this.inputTokens = input as number }
      let output = usage['completion_tokens']
      if (typeof output === 'number') { this.outputTokens = output as number }
      let cached = usage['prompt_cache_hit_tokens']
      if (typeof cached === 'number') { this.cacheHitTokens = cached as number }
    }
  }
}

export const deepseek: DeepSeekEngine = new DeepSeekEngine()
