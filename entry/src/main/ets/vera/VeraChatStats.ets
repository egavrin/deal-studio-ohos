/**
 * The numbers behind a chat turn, shaped like the ones the Generate screen
 * shows for a program: time, estimated cost, model wall time against compile
 * time on the phone, input / cached / fresh / output tokens, and for each build
 * attempt the wait, think, write and compile phases.
 *
 * Kept here, apart from ChatPage, so the store can save them and the rates sit
 * in one place. The Generate screen keeps its own copy of the same formulas.
 */

/** One attempt at building a widget, from the first request to the compiler's verdict. */
export class AttemptStat {
  attempt: number = 0
  /** Until the model said anything: the prompt being read. */
  ttftMs: number = 0
  thinkMs: number = 0
  genMs: number = 0
  compileMs: number = 0
  inputTokens: number = 0
  cachedTokens: number = 0
  outputTokens: number = 0
  success: boolean = false
  /** Why it failed, from the compiler's first diagnostic; empty on success. */
  verdict: string = ''
}

/** The chat reply itself, summed over its requests (a search makes two). */
export class ReplyStats {
  ms: number = 0
  ttftMs: number = 0
  inputTokens: number = 0
  cachedTokens: number = 0
  outputTokens: number = 0
  searches: number = 0
  searchMs: number = 0
}

/**
 * DeepSeek's published rates for deepseek-flash, per million tokens. Peak is
 * 01:00-04:00 and 06:00-10:00 UTC on weekdays and costs twice as much. The
 * price list lives on their side, so every figure is an estimate.
 */
function ratePerMillion(kind: string): number {
  let now = new Date()
  let day = now.getUTCDay()
  let hour = now.getUTCHours()
  let peak = day >= 1 && day <= 5 && ((hour >= 1 && hour < 4) || (hour >= 6 && hour < 10))
  if (kind === 'cache') { return peak ? 0.006 : 0.003 }
  if (kind === 'fresh') { return peak ? 0.30 : 0.15 }
  return peak ? 1.20 : 0.60
}

export function costOf(input: number, cached: number, output: number): number {
  let fresh = input - cached
  if (fresh < 0) { fresh = 0 }
  return (cached * ratePerMillion('cache') + fresh * ratePerMillion('fresh') +
    output * ratePerMillion('output')) / 1000000
}

export function formatUsd(value: number): string {
  if (value <= 0) { return '$0' }
  if (value < 0.01) { return '$' + value.toFixed(4) }
  return '$' + value.toFixed(3)
}

export function formatMs(ms: number): string {
  if (ms < 1000) { return Math.round(ms).toString() + 'ms' }
  return (ms / 1000).toFixed(1) + 's'
}

/** The compiler groups diagnostics by layer: E1 is the parser, E2 names and types. */
export function failureVerdict(errors: string): string {
  let m = errors.match(/E\d{4}/)
  if (m === null) { return 'compile' }
  let code = m[0]
  let layer = code.substring(1, 2)
  let name = layer === '1' ? 'parser' : (layer === '2' ? 'names & types' : 'layer E' + layer)
  return name + ' ' + code
}

export function speedOf(a: AttemptStat): string {
  let workMs = a.genMs - a.ttftMs
  if (workMs <= 0 || a.outputTokens === 0) { return '—' }
  return Math.round(a.outputTokens * 1000 / workMs).toString() + ' tok/s'
}
