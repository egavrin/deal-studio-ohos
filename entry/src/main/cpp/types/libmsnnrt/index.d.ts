/**
 * The MindSpore Lite / HiAI spike surface. Every call answers a JSON string,
 * pending it on a worker thread except the trivial file read.
 */
export const run: (path: string) => Promise<string>
export const hiaiProbe: () => Promise<string>
export const hiaiE2E: () => Promise<string>
export const hiaiOps: () => Promise<string>
export const fileReadTest: () => Promise<string>
export const hiaiModelTest: (modelPath: string, inputPath: string) => Promise<string>
export const hiaiModelBuffer: (model: ArrayBuffer, input: ArrayBuffer) => Promise<string>
