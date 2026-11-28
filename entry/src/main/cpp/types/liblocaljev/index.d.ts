/** Local selector: bundle readiness and developer-only raw decisions. */
export const status: () => Promise<string>
export const experimentalDecisions: (request: string) => Promise<string>
/** Composition decision model: Jev-shaped answers and raw diagnostic scores. */
export const predict: (request: string) => Promise<string>
export const diagnosticScores: (request: string) => Promise<string>
export const abi: () => number
export const npuGraph: (path: string, batch: number, seq: number) => boolean
