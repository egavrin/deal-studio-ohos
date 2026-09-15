/**
 * ArkTS interface for the llama.cpp NAPI module.
 *
 * The native module is built from entry/src/main/cpp/ and loaded as libllama.so.
 * It exposes four functions: llamaInit, llamaGenerate, llamaStop, llamaFree.
 *
 * Model: qwen2.5-coder-3b-instruct-q4_k_m.gguf (~1.9GB)
 * Place at: {filesDir}/models/qwen2.5-coder-3b-instruct-q4_k_m.gguf
 * Transfer: downloaded from the vera-server /models endpoint (hdc file send is
 * blocked on release-provisioned installs — see GeneratePage.checkModel()).
 */

import resourceManager from '@ohos.resourceManager'
import fs from '@ohos.file.fs'
import nativeLlama from 'libllama.so'

export class LlamaConfig {
  modelPath: string = ''
  nCtx: number = 4096
  nThreads: number = 4
  nGpuLayers: number = 0
}

export class GenerateRequest {
  systemPrompt: string = ''
  userPrompt: string = ''
  grammar: string = ''
  maxTokens: number = 2048
  temperature: number = 0.2
  topP: number = 0.95
  seed: number = 42
  previousSource: string = ''
}

export type TokenCallback = (token: string) => void

export class GenerateResult {
  text: string = ''
  inputTokens: number = 0
  outputTokens: number = 0
}

interface NativeGenerateResult {
  text: string
  inputTokens: number
  outputTokens: number
}

interface NativeLlama {
  llamaInit(configJson: string): boolean
  llamaGenerate(paramsJson: string, callback: (token: string) => void): NativeGenerateResult
  llamaStop(): void
  llamaFree(): void
}

let native: NativeLlama | null = null

function getNative(): NativeLlama {
  if (native === null) {
    native = nativeLlama as NativeLlama
  }
  return native!
}

export class LlamaEngine {
  private initialized: boolean = false
  private generating: boolean = false

  isReady(): boolean { return this.initialized }
  isGenerating(): boolean { return this.generating }

  init(config: LlamaConfig): boolean {
    try {
      let configObj: Record<string, Object> = {}
      configObj['model_path'] = config.modelPath
      configObj['n_ctx'] = config.nCtx
      configObj['n_threads'] = config.nThreads
      configObj['n_gpu_layers'] = config.nGpuLayers
      this.initialized = getNative().llamaInit(JSON.stringify(configObj))
      return this.initialized
    } catch (e) {
      console.error('LlamaEngine init failed: ' + (e as Error).message)
      return false
    }
  }

  generate(request: GenerateRequest, onToken: TokenCallback): GenerateResult {
    let gr = new GenerateResult()
    if (!this.initialized) { return gr }
    this.generating = true
    try {
      let prompt = this.buildPrompt(request)
      let paramsObj: Record<string, Object> = {}
      paramsObj['prompt'] = prompt
      paramsObj['grammar'] = request.grammar
      paramsObj['max_tokens'] = request.maxTokens
      paramsObj['temperature'] = request.temperature
      paramsObj['top_p'] = request.topP
      paramsObj['seed'] = request.seed
      let native = getNative().llamaGenerate(JSON.stringify(paramsObj), onToken)
      gr.text = native.text
      gr.inputTokens = native.inputTokens
      gr.outputTokens = native.outputTokens
      return gr
    } catch (e) {
      console.error('LlamaEngine generate failed: ' + (e as Error).message)
      return gr
    } finally {
      this.generating = false
    }
  }

  stop(): void {
    if (this.generating) {
      try { getNative().llamaStop() } catch (_e) {}
      this.generating = false
    }
  }

  free(): void {
    if (this.initialized) {
      try { getNative().llamaFree() } catch (_e) {}
      this.initialized = false
    }
  }

  private buildPrompt(request: GenerateRequest): string {
    // Qwen3 chat format
    let parts: string[] = []
    parts.push('<|im_start|>system\n')
    parts.push(request.systemPrompt)
    parts.push('\n<|im_end|>\n')
    if (request.previousSource.length > 0) {
      parts.push('<|im_start|>assistant\n')
      parts.push(request.previousSource)
      parts.push('\n<|im_end|>\n')
      parts.push('<|im_start|>user\n')
      parts.push('Refine the program above: ' + request.userPrompt)
      parts.push('\n<|im_end|>\n')
    } else {
      parts.push('<|im_start|>user\n')
      parts.push(request.userPrompt)
      parts.push('\n<|im_end|>\n')
    }
    parts.push('<|im_start|>assistant\n')
    return parts.join('')
  }

  static defaultModelPath(filesDir: string): string {
    return filesDir + '/models/qwen2.5-coder-3b-instruct-q4_k_m.gguf'
  }

  static modelExists(filesDir: string): boolean {
    try {
      let stat = fs.statSync(LlamaEngine.defaultModelPath(filesDir))
      return stat.size > 0
    } catch (_e) {
      return false
    }
  }
}

export async function loadRawfileText(mgr: resourceManager.ResourceManager, name: string): Promise<string> {
  let data = await mgr.getRawFileContent(name)
  let arr = new Uint8Array(data)
  let result = ''
  for (let i = 0; i < arr.length; i++) {
    result += String.fromCharCode(arr[i])
  }
  return result
}

export const engine: LlamaEngine = new LlamaEngine()
