/**
 * The model calls of Vera through the dealer harness (libdealer.so, github.com/arkts-dev/dealer), on with
 * `--ps dealer 1` (SettingsStore.useDealer): every request DeepSeekEngine makes (the plan, the sections, the blocks'
 * text and holes, the small side calls, Generate with its tools), the chat (VeraChat) and Jev (VeraCompose.askJev).
 *
 * Dealer builds each request, parses the SSE stream, runs the tool loop and keeps every turn in its own database
 * ({filesDir}/vera/dealer.db). The network and the tools stay here: dealer hands each HTTP request to send() below,
 * which answers through @kit.NetworkKit (so USB network keeps working), and each tool call to the handler of the turn
 * that asked for it. The request body is the one DeepSeekEngine.buildBody sends (model, thinking, reasoning_effort,
 * temperature, max_tokens, tools, tool_choice), and a reply cut at the token limit comes back with finish reason
 * "length", as the agent's repairs expect.
 */

import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import {
  dealerAvailable, dealerInit, dealerRegisterProvider, dealerHead, dealerChunk, dealerFinish, dealerCancelled,
  dealerRun, dealerCancel, dealerDecide, dealerRegisterTool, dealerToolFinish, dealerToolCancelled, dealerSteer
} from 'libdealer.so'
import { settings } from './SettingsStore'
import { OperationCancellation, throwIfCancelled } from './OperationCancellation'
import { TurnTiming, logStep, logTurn, traceTurn } from './VeraTiming'

const TAG: string = 'VERA-DEALER'
const API_PATH: string = 'chat/completions'
const EVENT_STREAM: string = 'text/event-stream'

/** A turn's reply: the last step's text and why it ended ("stop", "length", ...), and what the whole turn cost. */
export class DealerReply {
  text: string = ''
  finishReason: string = ''
  inputTokens: number = 0
  outputTokens: number = 0
  /** Prompt tokens read from the provider's cache, over every step. */
  cachedTokens: number = 0
  /** The last step's cached prompt tokens. */
  lastCachedTokens: number = 0
  steps: number = 0
  /** Steps that ended asking for tools. */
  toolSteps: number = 0
  /** From the start of the turn to its first text; 0 when there was none. */
  firstTextMs: number = 0
}

/** One message of what the model sees before the turn's input: role 'user', 'assistant' or 'system'. */
export class DealerMessage {
  role: string
  text: string
  constructor(role: string, text: string) { this.role = role; this.text = text }
}

/** How one step asks: the request fields DeepSeekEngine.buildBody sets beside the messages. */
export class DealerStep {
  maxTokens: number = 4096
  thinking: boolean = false
  temperature: number = 0
  /** The tools offered by name; [] with toolCalls offers none. */
  tools: string[] = []
  /** Whether the tools are sent at all. */
  toolCalls: boolean = false
  /** "none": the tools are shown but cannot be called. */
  toolChoice: string = ''
}

/** A tool's definition, in the request's own form: {type: 'function', function: {name, description, parameters}}. */
export type DealerToolSchema = Record<string, Object>
/** Replaces how the turn's coming steps ask, from the next one on (the last for every step after). */
export type DealerSteer = (steps: DealerStep[]) => void
/**
 * Runs a tool call of a turn: (tool name, its arguments, the step it was asked in from 1, how to change the steps
 * after this one) -> the result text. The calls of one step run at the same time.
 */
export type DealerToolHandler = (name: string, args: Record<string, Object>, step: number, steer: DealerSteer) => Promise<string>

/** What a turn says as it goes, all optional. */
export class DealerWatch {
  onText: (piece: string) => void = (_piece: string): void => {}
  onReasoning: (piece: string) => void = (_piece: string): void => {}
  onToolStarted: (name: string, args: Record<string, Object>) => void = (_n: string, _a: Record<string, Object>): void => {}
  /** A step ended: why, and its text. */
  onStep: (finishReason: string, text: string) => void = (_reason: string, _text: string): void => {}
}

class Bridge {
  /** Whether dealerInit has opened the instance. */
  private opened: boolean = false
  /** The provider id the runs use, and the base URL and key it was registered with. */
  private provider: string = ''
  private registeredBase: string = ''
  private registeredKey: string = ''
  private registrations: number = 0
  /** The tools registered with dealer, by name. */
  private registeredTools: Set<string> = new Set<string>()
  /** Turns going now: dealer takes no registration while one is. */
  private active: number = 0
  private runs: number = 0
  private schemas: DealerToolSchema[] = []
  /** The tool handler of each running turn, by its session id. */
  private handlers: Map<string, DealerToolHandler> = new Map<string, DealerToolHandler>()
  /** How each running turn's steps are changed, by its session id. */
  private steers: Map<string, DealerSteer> = new Map<string, DealerSteer>()

  /** The tools any turn may offer; registered with dealer when it opens, so give them before the first turn. */
  defineTools(schemas: DealerToolSchema[]): void {
    for (let schema of schemas) {
      let name = (schema['function'] as Record<string, Object>)['name'] as string
      if (!this.schemas.some((s: DealerToolSchema): boolean => (s['function'] as Record<string, Object>)['name'] === name)) {
        this.schemas.push(schema)
      }
    }
  }

  /**
   * '' when dealer is ready, else why not. Opens the database and registers the tools once, and the provider again
   * whenever the base URL or the key has changed since. Nothing that failed is remembered: the next call tries again.
   */
  ready(): string {
    if (!dealerAvailable()) { return 'this build has no dealer library' }
    if (!this.opened) {
      let failure = dealerInit(settings.dir() + '/dealer.db', (id: number, request: string): void => this.send(id, request))
      if (failure.length > 0) {
        console.warn(TAG + ' not ready: ' + failure)
        return failure
      }
      this.opened = true
    }
    for (let schema of this.schemas) {
      let name = (schema['function'] as Record<string, Object>)['name'] as string
      if (this.registeredTools.has(name)) { continue }
      let failure = this.registerTool(schema)
      if (failure.length > 0) {
        console.warn(TAG + ' tool ' + name + ' not registered: ' + failure)
        return failure
      }
      this.registeredTools.add(name)
    }
    let base = settings.getBaseUrl()
    let key = settings.getApiKey()
    if (base === this.registeredBase && key === this.registeredKey) { return '' }
    if (this.active > 0 && this.provider.length > 0) {
      // Dealer registers nothing while a turn is going; this one keeps the provider the others use.
      console.warn(TAG + ' provider change waits for ' + this.active.toString() + ' running turn(s)')
      return ''
    }
    let failure = this.register(base, key)
    console.info(TAG + ' ready: ' + (failure.length > 0 ? failure : 'yes, provider ' + this.provider + ', ' +
      this.registeredTools.size.toString() + ' tools'))
    return failure
  }

  private register(base: string, key: string): string {
    let deepseek = settings.isDeepSeek()
    // A provider id keeps its base URL for good in dealer's database, and its dialect holds the key: another URL or
    // key takes another id.
    let id = (deepseek ? 'deepseek-' : 'cloud-') + hash(base) + '-' + (++this.registrations).toString()
    let provider: Record<string, Object> = {}
    provider['id'] = id
    provider['base_url'] = base.endsWith('/') ? base : base + '/'
    provider['path'] = API_PATH
    provider['dialect'] = deepseek ? 'deepseek' : 'bearer'
    provider['key'] = key
    let failure = dealerRegisterProvider(JSON.stringify(provider))
    if (failure.length === 0) {
      this.provider = id
      this.registeredBase = base
      this.registeredKey = key
    }
    return failure
  }

  private registerTool(schema: DealerToolSchema): string {
    let fn = schema['function'] as Record<string, Object>
    let name = fn['name'] as string
    let definition: Record<string, Object> = {}
    definition['name'] = name
    definition['description'] = fn['description']
    definition['input_schema'] = fn['parameters']
    // Every tool here only looks things up, so the calls of one step run at the same time, as DeepSeekEngine runs them.
    definition['concurrent'] = true
    return dealerRegisterTool(JSON.stringify(definition), (callId: number, argsJson: string, contextJson: string): void => {
      this.execute(name, callId, argsJson, contextJson)
    })
  }

  private execute(name: string, callId: number, argsJson: string, contextJson: string): void {
    let context = JSON.parse(contextJson) as Record<string, Object>
    let handler = this.handlers.get(context['session_id'] as string)
    let finish = (text: string, isError: boolean): void => {
      let part: Record<string, Object> = {}
      part['type'] = 'text'
      part['text'] = text
      let outcome: Record<string, Object> = {}
      outcome['content'] = [part] as Object[]
      outcome['is_error'] = isError
      let failure = dealerToolFinish(callId, true, JSON.stringify(outcome))
      if (failure.length > 0) { console.warn(TAG + ' tool ' + name + ' answer refused: ' + failure) }
    }
    if (handler === undefined) {
      finish('This tool is not available here.', true)
      return
    }
    let sessionId = context['session_id'] as string
    let steer = this.steers.get(sessionId)
    let running: Promise<string>
    try {
      let args = JSON.parse(argsJson) as Record<string, Object>
      running = handler(name, args, context['step_id'] as number, steer !== undefined ? steer : (_steps: DealerStep[]): void => {})
    } catch (e) {
      // Thrown before the handler had a promise to give: unanswered, the call would hold its turn for good.
      finish(name + ' failed: ' + (e as Error).message, true)
      return
    }
    running.then((text: string): void => {
      if (!dealerToolCancelled(callId)) { finish(text, false) } else { dealerToolFinish(callId, false, 'cancelled') }
    }).catch((e: Error): void => {
      finish(name + ' failed: ' + e.message, true)
    })
  }

  /** What DeepSeekEngine.buildBody puts beside the messages, for dealer to send as is. */
  private generation(step: DealerStep): string {
    let options: Record<string, Object> = {}
    if (settings.isDeepSeek()) {
      let mode: Record<string, Object> = {}
      mode['type'] = step.thinking ? 'enabled' : 'disabled'
      options['thinking'] = mode
      if (step.thinking) { options['reasoning_effort'] = settings.getReasoningEffort() }
    } else if (step.thinking) {
      options['reasoning_effort'] = settings.getReasoningEffort()
    } else {
      options['enable_thinking'] = false
    }
    options['temperature'] = step.temperature
    if (step.toolChoice.length > 0) { options['tool_choice'] = step.toolChoice }
    let generation: Record<string, Object> = {}
    generation['provider'] = this.provider
    generation['model'] = settings.getModel()
    generation['reasoning'] = true
    generation['tool_calls'] = step.toolCalls
    generation['tools'] = step.tools as Object[]
    generation['max_output_tokens'] = step.maxTokens
    generation['options'] = options
    return JSON.stringify(generation)
  }

  /**
   * One turn: `system` and `messages` first, then `input` (its parts in order; none answers the messages as they are).
   * Step i (from 0) asks as steps[i], the last one for every step after, until the tool handler steers it otherwise;
   * the tool calls go to `tools`. Each step is logged and traced as DeepSeekEngine traces its requests (VeraTiming).
   * A turn longer than `timeoutMs` (0: no limit) is stopped and throws.
   */
  async turn(purpose: string, system: string, messages: DealerMessage[], input: string[], steps: DealerStep[],
      watch: DealerWatch, tools?: DealerToolHandler, cancellation?: OperationCancellation,
      timeoutMs: number = 0): Promise<DealerReply> {
    let failure = this.ready()
    if (failure.length > 0) { throw new Error('dealer: ' + failure) }
    throwIfCancelled(cancellation)
    let runId = ++this.runs
    let started = Date.now()
    let sessionId = 'vera-' + purpose + '-' + started.toString() + '-' + runId.toString()
    let context: Record<string, Object> = {}
    context['system'] = system
    context['messages'] = messages.map((m: DealerMessage): Object => message(m)) as Object[]
    let parts: Object[] = input.map((text: string): Object => textPart(text))
    let reply = new DealerReply()
    let offered = (at: number): boolean => {
      let step = steps[Math.min(at, steps.length - 1)]
      return step.toolCalls && step.tools.length > 0
    }
    // One step's trace: the request goes when the turn starts or the last step's tools end, its response ends at its
    // first tool call or, without one, when the step completes.
    let timing = new TurnTiming()
    timing.sentAt = started
    let stepText = ''
    let stepReasoning = ''
    let calls: Object[] = []
    let toolsAt = 0
    if (tools !== undefined) { this.handlers.set(sessionId, tools) }
    this.steers.set(sessionId, (next: DealerStep[]): void => {
      dealerSteer(runId, next.map((s: DealerStep): string => this.generation(s)))
    })
    let timedOut = false
    let timer = timeoutMs > 0 ? setTimeout((): void => {
      timedOut = true
      dealerCancel(runId)
    }, timeoutMs) : -1
    let stop = cancellation !== undefined ? cancellation.onCancel((): void => dealerCancel(runId)) : (): void => {}
    this.active++
    try {
      let result = await dealerRun(runId, sessionId, steps.map((s: DealerStep): string => this.generation(s)),
        JSON.stringify(context), JSON.stringify(parts), (event: string): void => {
          let parsed = JSON.parse(event) as Record<string, Object>
          let type = parsed['type'] as string
          if (type === 'text') {
            if (reply.firstTextMs === 0) { reply.firstTextMs = Date.now() - started }
            timing.saw('content')
            stepText += parsed['text'] as string
            watch.onText(parsed['text'] as string)
          } else if (type === 'reasoning') {
            timing.saw('reasoning')
            stepReasoning += parsed['text'] as string
            watch.onReasoning(parsed['text'] as string)
          } else if (type === 'tool_started') {
            let call = parsed['call'] as Record<string, Object>
            if (toolsAt === 0) {
              timing.saw('tool')
              timing.endAt = Date.now()
              toolsAt = timing.endAt
            }
            let traced: Record<string, Object> = {}
            traced['name'] = call['name']
            traced['arguments'] = JSON.stringify(call['arguments'])
            calls.push(traced)
            watch.onToolStarted(call['name'] as string, call['arguments'] as Record<string, Object>)
          } else if (type === 'step_completed') {
            let reason = (parsed['finish_reason'] as string) || ''
            let usage = parsed['usage'] as Record<string, Object>
            addUsage(reply, usage)
            reply.steps++
            if (reason === 'tool_calls') { reply.toolSteps++ }
            if (timing.endAt === 0) { timing.endAt = Date.now() }
            timing.finishReason = reason
            timing.toolCalls = calls.length
            timing.inputTokens = countOf(usage, 'input_tokens')
            timing.outputTokens = countOf(usage, 'output_tokens')
            timing.cachedTokens = countOf(usage, 'cache_read_tokens')
            logTurn(purpose, reply.steps, timing)
            traceTurn(purpose, reply.steps, timing, stepReasoning, stepText, calls, offered(reply.steps - 1))
            if (toolsAt > 0) {
              logStep('tools', toolsAt, 'src=' + purpose + ' round=' + reply.steps.toString() + ' calls=' +
                calls.map((c: Object): string => (c as Record<string, Object>)['name'] as string).join(','))
            }
            watch.onStep(reason, stepText)
            timing = new TurnTiming()
            timing.sentAt = Date.now()
            stepText = ''
            stepReasoning = ''
            calls = []
            toolsAt = 0
          }
        })
      let answer = JSON.parse(result) as Record<string, Object>
      reply.text = answer['text'] as string
      reply.finishReason = (answer['finish_reason'] as string) || ''
      console.info(TAG + ' ' + purpose + ' ms=' + (Date.now() - started).toString() + ' steps=' + reply.steps.toString() +
        ' finish=' + reply.finishReason + ' chars=' + reply.text.length.toString() + ' in=' + reply.inputTokens.toString() +
        ' cached=' + reply.cachedTokens.toString() + ' out=' + reply.outputTokens.toString())
      return reply
    } catch (e) {
      if (timedOut) { throw new Error('no answer within ' + timeoutMs.toString() + ' ms') }
      throw (e as Error)
    } finally {
      this.active--
      if (timer !== -1) { clearTimeout(timer) }
      stop()
      this.handlers.delete(sessionId)
      this.steers.delete(sessionId)
    }
  }

  /** One system and one user message, no tools, streamed; onText gets the reply so far. */
  async ask(purpose: string, system: string, user: string, maxTokens: number, thinking: boolean, temperature: number,
      onText: (soFar: string) => void, cancellation?: OperationCancellation, timeoutMs: number = 0): Promise<DealerReply> {
    let step = new DealerStep()
    step.maxTokens = maxTokens
    step.thinking = thinking
    step.temperature = temperature
    let soFar = ''
    let watch = new DealerWatch()
    watch.onText = (piece: string): void => {
      soFar += piece
      onText(soFar)
    }
    return this.turn(purpose, system, [], [user], [step], watch, undefined, cancellation, timeoutMs)
  }

  /**
   * Jev's systemone endpoint through dealer: the request body in, Jev's answer body out. Stopped by `cancellation`,
   * and after `timeoutMs` (0: no limit), when it throws.
   */
  async decide(endpoint: string, key: string, body: string, cancellation?: OperationCancellation,
      timeoutMs: number = 0): Promise<string> {
    let failure = this.ready()
    if (failure.length > 0) { throw new Error('dealer: ' + failure) }
    throwIfCancelled(cancellation)
    let runId = ++this.runs
    let started = Date.now()
    let timedOut = false
    let timer = timeoutMs > 0 ? setTimeout((): void => {
      timedOut = true
      dealerCancel(runId)
    }, timeoutMs) : -1
    let stop = cancellation !== undefined ? cancellation.onCancel((): void => dealerCancel(runId)) : (): void => {}
    try {
      let answer = await dealerDecide(runId, endpoint, key, body)
      console.info(TAG + ' decide ms=' + (Date.now() - started).toString() + ' chars=' + answer.length.toString())
      return answer
    } catch (e) {
      if (timedOut) { throw new Error('no answer within ' + timeoutMs.toString() + ' ms') }
      throw (e as Error)
    } finally {
      if (timer !== -1) { clearTimeout(timer) }
      stop()
    }
  }

  /**
   * Does dealer's HTTP request `id`. An event stream is passed on as it arrives; anything else (an
   * error body, a JSON answer) is kept until the status is known, because dealer reads the status
   * before the body and requestInStream gives it only at the end.
   */
  private send(id: number, requestJson: string): void {
    let request = JSON.parse(requestJson) as Record<string, Object>
    let header: Record<string, string> = {}
    let given = request['headers'] as Record<string, Object>
    Object.keys(given).forEach((name: string): void => { header[name] = String(given[name]) })
    let client = http.createHttp()
    let contentType = ''
    let streamed = false
    let ended = false
    let kept: ArrayBuffer[] = []
    let decoder = util.TextDecoder.create('utf-8')
    // Once dealer no longer wants the answer (a cancel, a timeout), the request stops here at once, without waiting
    // for its next piece or its own read timeout.
    let watch = -1
    let abandon = (): boolean => {
      if (ended || !dealerCancelled(id)) { return ended }
      ended = true
      clearInterval(watch)
      dealerFinish(id, false, 'cancelled')
      try { client.destroy() } catch (_e) {}
      return true
    }
    watch = setInterval((): void => { abandon() }, 250)
    client.on('headersReceive', (headers: Object): void => { contentType = contentTypeOf(headers) })
    client.on('dataReceive', (chunk: ArrayBuffer): void => {
      if (abandon()) { return }
      // An event stream may open with a comment line (": keep-alive") before its first "data:".
      let opening = decoder.decodeToString(new Uint8Array(chunk.slice(0, 5)), { stream: false })
      if (!streamed && kept.length === 0 && (contentType.indexOf(EVENT_STREAM) >= 0 ||
        opening === 'data:' || opening.startsWith(':'))) {
        streamed = true
        dealerHead(id, 200, '{"content-type": "' + EVENT_STREAM + '"}')
      }
      if (streamed) {
        dealerChunk(id, chunk)
      } else {
        kept.push(chunk)
      }
    })
    let options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: header,
      extraData: JSON.stringify(request['body']),
      connectTimeout: 15000,
      readTimeout: 300000
    }
    client.requestInStream(request['url'] as string, options).then((code: number): void => {
      if (ended) { return }
      ended = true
      if (streamed) {
        dealerFinish(id, code === 200, code === 200 ? '' : 'HTTP ' + code.toString() + ' after the stream began')
        return
      }
      let type = contentType.length > 0 ? contentType : 'application/json'
      let failure = dealerHead(id, code, JSON.stringify(headerOf('content-type', type)))
      if (failure.length > 0) {
        dealerFinish(id, false, failure)
        return
      }
      kept.forEach((chunk: ArrayBuffer): void => { dealerChunk(id, chunk) })
      dealerFinish(id, true, '')
    }).catch((e: Error): void => {
      if (!ended) {
        ended = true
        dealerFinish(id, false, 'request failed: ' + e.message)
      }
    }).finally((): void => {
      ended = true
      clearInterval(watch)
      try { client.off('dataReceive') } catch (_e) {}
      try { client.off('headersReceive') } catch (_e) {}
      try { client.destroy() } catch (_e) {}
    })
  }
}

function headerOf(name: string, value: string): Record<string, string> {
  let header: Record<string, string> = {}
  header[name] = value
  return header
}

function contentTypeOf(headers: Object): string {
  let all = headers as Record<string, Object>
  let found = ''
  Object.keys(all).forEach((name: string): void => {
    if (name.toLowerCase() === 'content-type') { found = String(all[name]) }
  })
  return found
}

function textPart(text: string): Record<string, Object> {
  let part: Record<string, Object> = {}
  part['type'] = 'text'
  part['text'] = text
  return part
}

function message(m: DealerMessage): Record<string, Object> {
  let out: Record<string, Object> = {}
  out['role'] = m.role
  if (m.role === 'assistant' || m.role === 'system') {
    out['text'] = m.text
  } else {
    out['content'] = [textPart(m.text)] as Object[]
  }
  return out
}

function countOf(usage: Record<string, Object> | null | undefined, name: string): number {
  return usage !== null && usage !== undefined && typeof usage[name] === 'number' ? usage[name] as number : 0
}

/** Adds a step's usage ({"input_tokens", "output_tokens", "cache_read_tokens", ...}, values may be null). */
function addUsage(reply: DealerReply, usage: Record<string, Object> | null | undefined): void {
  if (usage === null || usage === undefined) { return }
  let count = (name: string): number => typeof usage[name] === 'number' ? usage[name] as number : 0
  reply.inputTokens += count('input_tokens')
  reply.outputTokens += count('output_tokens')
  reply.lastCachedTokens = count('cache_read_tokens')
  reply.cachedTokens += reply.lastCachedTokens
}

/** A short stable name for a base URL (FNV-1a). */
function hash(text: string): string {
  let h = 0x811c9dc5
  for (let i = 0; i < text.length; i++) {
    h = h ^ text.charCodeAt(i)
    h = Math.imul(h, 0x01000193) >>> 0
  }
  return h.toString(16)
}

export const dealer: Bridge = new Bridge()
