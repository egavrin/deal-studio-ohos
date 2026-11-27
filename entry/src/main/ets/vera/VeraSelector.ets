// Shared transport boundary for generation and structural edits.
import { http } from '@kit.NetworkKit'
import { OperationCancellation, throwIfCancelled } from './OperationCancellation'
import { requestWithCancellation } from './VeraWebSearch'
import { noteService, httpFailure } from './ServiceHealth'
import { settings } from './SettingsStore'
import { askJevViaCloud } from './JevProxy'
import { localJev } from './LocalJev'
import { trace } from './VeraTiming'
import { dealer } from './DealerBridge'
import { SelectorCall, beginSelectorCall, finishSelectorCall, selectorUsage, selectorLabel } from './SelectorMetrics'

const JEV_ENDPOINT: string = 'https://api.typesafe.ai/v1/systemone'
/** How napi_dealer.cpp begins a failure of status DEALER_INVALID_ARGUMENT: dealer did not take the request. */
const DEALER_REFUSED: string = 'dealer status 1:'

export async function askSelector(body: string, apiKey: string, cancellation?: OperationCancellation): Promise<string> {
  throwIfCancelled(cancellation)
  let backend = settings.useLocalSelector() ? 'local-experimental' : (settings.useJevProxy() ? 'llm' : 'typesafe')
  let call = beginSelectorCall(backend, backend === 'llm' ? settings.getModel() :
    (backend === 'typesafe' ? 'jev-latest' : localJev.identity()), body, cancellation)
  let started = Date.now()
  try {
    let reply = await sendSelector(body, apiKey, call, cancellation)
    throwIfCancelled(cancellation)
    finishSelectorCall(call, reply)
    return reply
  } catch (e) {
    call.cancelled = cancellation !== undefined && cancellation.isCancelled()
    if (call.requests > 0) { call.partial = true }
    call.error = call.cancelled ? 'cancelled' : (e as Error).message
    throw (e as Error)
  } finally {
    call.ms = Math.max(0, Date.now() - started)
    call.finished = true
    if (!call.cancelled) { noteService(selectorLabel(backend), call.ok, call.error) }
  }
}

async function sendSelector(body: string, apiKey: string, call: SelectorCall,
    cancellation?: OperationCancellation): Promise<string> {
  if (call.backend === 'local-experimental') {
    let started = Date.now()
    let reply = await localJev.ask(body, cancellation)
    throwIfCancelled(cancellation)
    let fields: Record<string, Object> = {}
    fields['backend'] = 'local-experimental'
    fields['body'] = body
    fields['response'] = reply
    fields['source'] = localJev.identity()
    fields['ms'] = Date.now() - started
    trace('selector', fields)
    return reply
  }
  if (call.backend === 'llm') { return askJevViaCloud(body, cancellation, call) }
  if (apiKey.length === 0) { return '' }
  // Through the dealer harness (DealerBridge.ets) when it is on: the same endpoint, key and body, and the same time
  // as the request below (5 s to connect, 15 s to read). A body dealer cannot read (DEALER_INVALID_ARGUMENT, say a
  // field it does not know) goes the direct way instead of losing the decision.
  if (settings.useDealer()) {
    try {
      call.requests++
      let answer = await dealer.decide(JEV_ENDPOINT, apiKey, body, cancellation, 20000)
      throwIfCancelled(cancellation)
      selectorUsage(call, answer, 200)
      return answer
    } catch (e) {
      throwIfCancelled(cancellation)
      let message = (e as Error).message
      console.warn('VERA-DEALER jev failed: ' + message + ' questions=' + questionShapes(body))
      if (message.indexOf(DEALER_REFUSED) < 0) {
        call.error = message
        call.partial = true
        return ''
      }
    }
  }
  try {
    let headers: Record<string, string> = {}
    headers['Content-Type'] = 'application/json'
    headers['Authorization'] = 'Bearer ' + apiKey
    call.requests++
    let response = await requestWithCancellation(JEV_ENDPOINT, {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: body,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 5000,
      readTimeout: 15000
    }, cancellation)
    selectorUsage(call, String(response.result), response.responseCode as number)
    throwIfCancelled(cancellation)
    if ((response.responseCode as number) !== 200) {
      console.warn('VERA-JEV http ' + (response.responseCode as number).toString() + ' bytes=' + body.length.toString() + ' ' +
        String(response.result).substring(0, 300))
      call.error = httpFailure(response.responseCode as number, String(response.result))
      return ''
    }
    return response.result as string
  } catch (e) {
    throwIfCancelled(cancellation)
    if ((e as Error).name === 'OperationCancelledError') { throw (e as Error) }
    console.warn('VERA-JEV failed bytes=' + body.length.toString() + ': ' + (e as Error).message)
    call.error = (e as Error).message
    call.partial = true
    return ''
  }
}

/** "name:type/options, ..." of a Jev request, for a log line. */
function questionShapes(body: string): string {
  try {
    let questions = (JSON.parse(body) as Record<string, Object>)['questions'] as Record<string, Object>
    return Object.keys(questions).map((name: string): string => {
      let question = questions[name] as Record<string, Object>
      let criteria = question['criteria']
      let count = criteria === undefined || criteria === null ? 0 :
        Array.isArray(criteria) ? (criteria as Object[]).length : Object.keys(criteria as Record<string, Object>).length
      return name + ':' + String(question['type']) + '/' + count.toString()
    }).join(', ')
  } catch (_e) {
    return '?'
  }
}
