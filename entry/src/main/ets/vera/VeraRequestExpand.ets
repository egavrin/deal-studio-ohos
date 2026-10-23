/**
 * A short or question-shaped request ("tip calc", "what is the weather today") gives Jev nothing to hold on to, so it
 * answers "none" and the request is generated from scratch, the most expensive route. This rewrites the request as one
 * or two plain sentences ("a phone app screen that ...") for a second Jev attempt.
 *
 * It is started together with the first Jev call and only used when Jev picked nothing; when Jev picked blocks the
 * answer is never read. Hence its own plain HTTP request, not DeepSeekEngine's: the engine keeps one set of mutable
 * state (buffer, client, flags) and a second call beside the content fill would overwrite it.
 *
 * Plain text, no JSON: Jev reads text, and nothing downstream needs fields. Never throws; any failure is "no rewrite".
 */

import http from '@ohos.net.http'
import hilog from '@ohos.hilog'
import { settings } from './SettingsStore'

const DOMAIN = 0x0000

let enabled: boolean = true

/** On by default; `--ps veraExpand 0` at launch switches it off for the session, so a run can be compared without it. */
export function setExpandRequests(on: boolean): void { enabled = on }

/** Whether a request Jev cannot place is rewritten for a second try; off means it goes to generation as before. */
export function expandRequestsEnabled(): boolean { return enabled }

/** A longer answer is a short essay, not a rewrite; the original request is kept. */
export const EXPAND_MAX_CHARS: number = 300

const REFUSALS: string[] = ["i can't", 'i cannot', "i'm sorry", 'i am sorry', 'sorry', 'as an ai', 'i am unable', "i'm unable"]

export const EXPAND_SYSTEM: string = 'Rewrite a short or vague request for a small phone app as one or two plain sentences that begin ' +
  '"A phone app screen that". Say what the screen shows and what the person does on it. If the request is a question, ' +
  'make it a screen that answers it. Name no screen components or layouts. Add no feature the request does not imply. ' +
  'If it needs the camera, the microphone, another app or live data from the internet, keep saying so. ' +
  'Answer with the rewritten request only, no quotes, no explanation.'

export class ExpandResult {
  /** The rewritten request, '' when there is none. */
  text: string = ''
  ms: number = 0
}

/** The rewrite when it is usable, else '': trimmed, one paragraph, not empty, not long, not a refusal, not the original. */
export function cleanExpanded(raw: string, original: string): string {
  let text = raw.trim()
  if (text.startsWith('```')) { text = text.split('```').join('').trim() }
  let paragraph = text.indexOf('\n\n')
  if (paragraph > 0) { text = text.substring(0, paragraph).trim() }
  while (text.length > 1 && (text.startsWith('"') || text.startsWith("'")) && text.charAt(text.length - 1) === text.charAt(0)) {
    text = text.substring(1, text.length - 1).trim()
  }
  if (text.length === 0 || text.length > EXPAND_MAX_CHARS) { return '' }
  let lower = text.toLowerCase()
  for (let refusal of REFUSALS) { if (lower.startsWith(refusal)) { return '' } }
  if (lower === original.trim().toLowerCase()) { return '' }
  return text
}

/** One non-streaming call. Never throws. */
export async function expandRequest(prompt: string): Promise<ExpandResult> {
  let out = new ExpandResult()
  let started = Date.now()
  if (prompt.trim().length === 0 || !settings.hasApiKey()) { return out }
  let client = http.createHttp()
  try {
    let messages: Record<string, Object>[] = []
    let system: Record<string, Object> = {}
    system['role'] = 'system'
    system['content'] = EXPAND_SYSTEM
    messages.push(system)
    let user: Record<string, Object> = {}
    user['role'] = 'user'
    user['content'] = prompt
    messages.push(user)
    let thinking: Record<string, Object> = {}
    thinking['type'] = 'disabled'
    let payload: Record<string, Object> = {}
    payload['model'] = settings.getModel()
    payload['messages'] = messages
    payload['stream'] = false
    payload['thinking'] = thinking
    payload['temperature'] = 0
    payload['max_tokens'] = 120
    let headers: Record<string, string> = {}
    headers['Content-Type'] = 'application/json'
    headers['Authorization'] = 'Bearer ' + settings.getApiKey()
    let response = await client.request(settings.getBaseUrl() + '/chat/completions', {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: JSON.stringify(payload),
      connectTimeout: 5000,
      readTimeout: 8000
    })
    if ((response.responseCode as number) === 200) {
      let parsed = JSON.parse(response.result as string) as Record<string, Object>
      let choices = parsed['choices'] as Object[]
      let first = choices[0] as Record<string, Object>
      let message = first['message'] as Record<string, Object>
      let content = message['content']
      if (typeof content === 'string') { out.text = cleanExpanded(content as string, prompt) }
    }
  } catch (_e) {
    out.text = ''
  } finally {
    client.destroy()
  }
  out.ms = Date.now() - started
  hilog.info(DOMAIN, 'VERA', 'VERA-EXPAND ms=' + out.ms.toString() + ' words=' + prompt.trim().split(' ').length.toString() +
    ' rewrote=' + (out.text.length > 0).toString())
  return out
}
