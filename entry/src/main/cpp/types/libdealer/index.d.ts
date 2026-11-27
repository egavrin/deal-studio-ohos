// The dealer agent harness behind NAPI (napi_dealer.cpp); DealerBridge.ets is its one user.
// Functions returning a string give '' on success and the reason otherwise.

/** False in a build without the dealer library (tools/build-dealer.sh); nothing else is defined then but dealerInit. */
export const dealerAvailable: () => boolean
/**
 * Opens the session database, emptied first, once; may be called again after a failure. `onSend(id, requestJson)`
 * is asked to do each HTTP request.
 */
export const dealerInit: (dbPath: string, onSend: (id: number, requestJson: string) => void) => string
/** `{"id", "base_url", "path", "dialect": "deepseek" | "bearer", "key"}`, while no run is going. */
export const dealerRegisterProvider: (json: string) => string
/** The answer to request `id`: head once, chunks, then finish exactly once. */
export const dealerHead: (id: number, status: number, headersJson: string) => string
export const dealerChunk: (id: number, chunk: ArrayBuffer) => string
export const dealerFinish: (id: number, ok: boolean, message: string) => void
/** Whether dealer no longer wants request `id`'s answer. */
export const dealerCancelled: (id: number) => boolean
/**
 * One turn in a new session, on a thread of its own, deleted from the database when it ends. Step i runs with
 * generations[i], the last one for every step after; resolves with the last step's `{"finish_reason", "usage", "text"}`.
 */
export const dealerRun: (runId: number, sessionId: string, generations: string[], contextJson: string,
  inputJson: string, onEvent: (eventJson: string) => void) => Promise<string>
/** Stops run or decision `runId`; its promise rejects. */
export const dealerCancel: (runId: number) => void
/** A Jev decision through the same transport, stopped by dealerCancel(runId); resolves with Jev's answer body. */
export const dealerDecide: (runId: number, endpoint: string, key: string, requestJson: string) => Promise<string>
/** `{"name", "description", "input_schema"}`, before any run; `onExecute` is asked each call, answered by dealerToolFinish. */
export const dealerRegisterTool: (definitionJson: string,
  onExecute: (callId: number, argumentsJson: string, contextJson: string) => void) => string
/** `{"content": [{"type": "text", "text"}], "is_error"?}` when ok, else the failure's message; exactly once per call. */
export const dealerToolFinish: (callId: number, ok: boolean, outcomeJson: string) => string
/** Whether dealer no longer wants call `callId`'s answer. */
export const dealerToolCancelled: (callId: number) => boolean
/** From run `runId`'s next step on, step next+i runs with generations[i], the last one for every step after. */
export const dealerSteer: (runId: number, generations: string[]) => void
