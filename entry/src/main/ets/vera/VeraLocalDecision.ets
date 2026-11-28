/**
 * The local decision route's split/merge helpers and the on-device backend
 * interface.
 *
 * The hybrid replaces cloud Jev for the easy/standard decisions and keeps the
 * hard tier on the cloud. The two are told apart by the question key alone:
 * verify and claims (`AgentCustom.verifyRequest`, used by both step 8 and step
 * 9) ask every question under "does.<i>", and no other call site uses that
 * prefix, so a question whose key starts with "does." is the hard tier. The
 * formula and anatomy picks ("expr.N"/"show.N") are hard-tiered too: the
 * measured agreement (docs/local-jev/cpu-vs-cloud.md) is 1/13 and 7/13 against
 * the cloud — the sharp disagreement types a small model cannot carry. The
 * rest — theme, widget, steps, section, live, align, edit, ... — is
 * easy/standard and can be answered by a small on-device System-one model
 * where its calibration is confident; the cloud covers what it is not.
 *
 * Nothing here calls a model. `splitJevBody`, `unansweredJevBody` and
 * `mergeJevAnswers` are pure, so the routing is host-testable without any
 * model; the backend is an interface whose default reports unavailable, so the
 * route falls back to the cloud until an on-device decision model (a NAPI
 * module wrapping the System-one encoder) is registered with
 * `setLocalDecisionModel`.
 *
 * Why the split is safe: both halves carry the same `state` and `model`, so each
 * is a valid Jev body on its own; answers are keyed, so merging is just a union.
 */

import { OperationCancellation } from './OperationCancellation'
import { settings } from './SettingsStore'
import { requestWithCancellation } from './VeraWebSearch'
import { http } from '@kit.NetworkKit'

/** The question-key prefix only the hard tier (verify/claims, code reading) uses. */
export const HARD_QUESTION_PREFIX: string = 'does.'

/**
 * Cloud-tier key prefixes: the decisions the calibration data keeps off the
 * local model even when a calibration is loaded -- the formula (`expr`) and
 * how a value is shown (`show`), both measured at/below coin-flip agreement
 * against the cloud (1/13 and 7/13, docs/local-jev/cpu-vs-cloud.md).
 */
export const CLOUD_TIER_PREFIXES: string[] = ['expr.', 'show.']

/** Whether a question is the hard tier: code reading, which stays on the cloud. */
export function isHardQuestion(key: string): boolean {
  if (key.indexOf(HARD_QUESTION_PREFIX) === 0) { return true }
  for (let prefix of CLOUD_TIER_PREFIXES) {
    if (key.indexOf(prefix) === 0) { return true }
  }
  return false
}

/** A Jev body split into its hard and easy/standard questions ('' when a side is empty). */
export class SplitBody {
  hard: string = ''
  easy: string = ''
  hardCount: number = 0
  easyCount: number = 0
}

function parseObject(text: string): Record<string, Object> | null {
  try {
    return JSON.parse(text) as Record<string, Object>
  } catch (_e) {
    return null
  }
}

function bodyFor(model: Object, state: Object, questions: Record<string, Object>): string {
  let body: Record<string, Object> = {}
  body['model'] = model
  body['state'] = state
  body['questions'] = questions
  return JSON.stringify(body)
}

/**
 * Split a Jev body into a hard-tier body and an easy/standard body, each
 * carrying the same state. A body that cannot be parsed, or that carries no
 * questions, comes back whole on the easy side so it is still answered.
 */
export function splitJevBody(body: string): SplitBody {
  let out = new SplitBody()
  let root = parseObject(body)
  let questionsRaw: Object | null = root === null ? null : root['questions']
  if (root === null || questionsRaw === null || questionsRaw === undefined) {
    out.easy = body
    out.easyCount = 1
    return out
  }
  let questions = questionsRaw as Record<string, Object>
  let hard: Record<string, Object> = {}
  let easy: Record<string, Object> = {}
  for (let key of Object.keys(questions)) {
    if (isHardQuestion(key)) {
      hard[key] = questions[key]
      out.hardCount++
    } else {
      easy[key] = questions[key]
      out.easyCount++
    }
  }
  let model: Object = root['model'] !== undefined ? root['model'] : 'jev-latest'
  let state: Object = root['state'] !== undefined ? root['state'] : ''
  if (out.hardCount > 0) { out.hard = bodyFor(model, state, hard) }
  if (out.easyCount > 0) { out.easy = bodyFor(model, state, easy) }
  return out
}

/**
 * The Jev body of the questions a reply did NOT answer -- the local model's
 * reply answers only what its calibration is confident about, and this is the
 * part the cloud then covers. '' when the reply is unparseable (nothing was
 * answered) or when it answered everything.
 */
export function unansweredJevBody(body: string, reply: string): string {
  let root = parseObject(body)
  let questionsRaw: Object | null = root === null ? null : root['questions']
  if (root === null || questionsRaw === null || questionsRaw === undefined) {
    return body
  }
  let answered: Record<string, Object> = {}
  if (reply.length > 0) {
    let replyRoot = parseObject(reply)
    let answers: Object | null = replyRoot === null ? null : replyRoot['answers']
    if (answers !== null && answers !== undefined) {
      answered = answers as Record<string, Object>
    }
  }
  let questions = questionsRaw as Record<string, Object>
  let rest: Record<string, Object> = {}
  for (let key of Object.keys(questions)) {
    if (answered[key] === undefined) { rest[key] = questions[key] }
  }
  if (Object.keys(rest).length === 0) { return '' }
  let model: Object = root['model'] !== undefined ? root['model'] : 'jev-latest'
  let state: Object = root['state'] !== undefined ? root['state'] : ''
  return bodyFor(model, state, rest)
}

/**
 * Why a local reply answered nothing, from its `local.reason` ('' when the reply
 * is not shaped like a local reply). The route reads it to tell a declined
 * calibration apart from a body the engine could not accept at all.
 */
export function jevLocalReason(reply: string): string {
  let root = parseObject(reply)
  if (root === null) { return '' }
  let local: Object | null = root['local']
  if (local === null || local === undefined) { return '' }
  let reason = (local as Record<string, Object>)['reason']
  return typeof reason === 'string' ? reason : ''
}

/**
 * Split a Jev body's questions into two halves, each keeping the state and the
 * model. '' list when there is nothing to split (one question, or a body that
 * cannot be parsed): a body the engine rejects for its size is then served, or
 * declined, as it is. The halves are balanced by key order, which is the order
 * the sketch asked them in.
 */
export function splitJevBodyHalf(body: string): string[] {
  let root = parseObject(body)
  let questionsRaw: Object | null = root === null ? null : root['questions']
  if (root === null || questionsRaw === null || questionsRaw === undefined) { return [] }
  let questions = questionsRaw as Record<string, Object>
  let keys = Object.keys(questions)
  if (keys.length < 2) { return [] }
  let model: Object = root['model'] !== undefined ? root['model'] : 'jev-latest'
  let state: Object = root['state'] !== undefined ? root['state'] : ''
  let cut = Math.ceil(keys.length / 2)
  let first: Record<string, Object> = {}
  let second: Record<string, Object> = {}
  for (let i = 0; i < keys.length; i++) {
    if (i < cut) { first[keys[i]] = questions[keys[i]] } else { second[keys[i]] = questions[keys[i]] }
  }
  return [bodyFor(model, state, first), bodyFor(model, state, second)]
}

/**
 * Merge two Jev replies (`{"answers":{...}}`) into one. A reply that is '' or
 * cannot be parsed contributes no answers; the caller keeps its own defaults for
 * the questions it left unanswered.
 */
export function mergeJevAnswers(hardReply: string, easyReply: string): string {
  let answers: Record<string, Object> = {}
  let scores: Record<string, Object> = {}
  let replies: string[] = [hardReply, easyReply]
  for (let reply of replies) {
    if (reply.length === 0) { continue }
    let root = parseObject(reply)
    if (root === null) { continue }
    let a: Object | null = root['answers']
    if (a !== null && a !== undefined) {
      let obj = a as Record<string, Object>
      for (let key of Object.keys(obj)) { answers[key] = obj[key] }
    }
    // The raw per-option logits ride along when a run is recorded, so a merged
    // reply is still one calibration-refit datum.
    let sc: Object | null = root['scores']
    if (sc !== null && sc !== undefined) {
      let obj = sc as Record<string, Object>
      for (let key of Object.keys(obj)) { scores[key] = obj[key] }
    }
  }
  let wrapper: Record<string, Object> = {}
  wrapper['answers'] = answers
  if (Object.keys(scores).length > 0) { wrapper['scores'] = scores }
  return JSON.stringify(wrapper)
}

/**
 * A local decision model: answers a whole Jev body in one forward pass and
 * returns the `{"answers":...}` reply, or '' when it cannot. The on-device
 * backend implements this; the default below reports unavailable so the route
 * falls back to the cloud (and the app behaves exactly as if it were off).
 */
export interface LocalDecisionModel {
  available(): boolean
  answer(body: string, cancellation?: OperationCancellation): Promise<string>
}

class UnavailableLocalDecision implements LocalDecisionModel {
  available(): boolean { return false }
  answer(_body: string, _cancellation?: OperationCancellation): Promise<string> {
    return Promise.resolve('')
  }
}

let current: LocalDecisionModel = new UnavailableLocalDecision()

/** Register the on-device backend (called once the model is loaded). */
export function setLocalDecisionModel(model: LocalDecisionModel): void {
  current = model
}

/**
 * The local Jev service: POSTs the Jev body to an HTTP endpoint and returns its
 * {"answers":...} reply. Used when `--ps jevLocal` is set to a URL -- e.g. the
 * dev-machine Laya service reached over the USB path (`hdc rport`). The service
 * runs the local model off-phone; the app still applies its own thresholds.
 *
 * DEBUGGING ONLY -- never a production path. The production local backend is the
 * on-device NAPI (VeraLocalNapi.ets); this exists to exercise the hybrid route
 * before/without on-device weights.
 */
class HttpLocalDecision implements LocalDecisionModel {
  private endpoint: string = ''
  constructor(endpoint: string) { this.endpoint = endpoint }
  available(): boolean { return this.endpoint.length > 0 }
  async answer(body: string, cancellation?: OperationCancellation): Promise<string> {
    let headers: Record<string, string> = {}
    headers['Content-Type'] = 'application/json'
    let response = await requestWithCancellation(this.endpoint, {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: body,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 180000,
      readTimeout: 180000
    }, cancellation)
    if ((response.responseCode as number) !== 200) {
      console.warn('VERA-JEVLOCAL service http ' + (response.responseCode as number).toString())
      return ''
    }
    return String(response.result)
  }
}

/**
 * The backend the hybrid route should use. A URL set as `--ps jevLocal` means a
 * remote local-Jev service (debugging only -- never a production path); otherwise
 * the registered on-device backend, or the unavailable default (which makes the
 * route fall back to the cloud).
 */
export function localDecisionModel(): LocalDecisionModel {
  let endpoint = settings.getJevLocal().trim()
  if (endpoint.indexOf('http://') === 0 || endpoint.indexOf('https://') === 0) {
    return new HttpLocalDecision(endpoint)
  }
  return current
}