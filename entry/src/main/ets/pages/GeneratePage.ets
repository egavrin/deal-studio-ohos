import router from '@ohos.router'
import { KeyboardAvoidMode } from '@ohos.arkui.UIContext'
import fs from '@ohos.file.fs'
import http from '@ohos.net.http'
import request from '@ohos.request'
import { store } from '../vera/ProjectStore'
import { refreshForms } from '../vera/FormUpdater'
import { engine, LlamaEngine, GenerateRequest, GenerateResult, loadRawfileText } from '../vera/LlamaEngine'
import { compileVeraSource, CompileError } from '../vera/VeraCompiler'
import { deepseek } from '../vera/DeepSeekEngine'
import { VeraPreview } from '../components/VeraPreview'
import { settings } from '../vera/SettingsStore'
import { consent } from '../vera/VeraConsentStore'
import { describeCatalogForPrompt } from '../vera/VeraUiCatalog'
import { describeIntentsForPrompt } from '../vera/VeraIntentCatalog'
import { selectDomains, selectTargets, Selection, TargetChoice, everything } from '../vera/JevSelector'
import { loadRegistry, describeTargetsForPrompt, registrySize } from '../vera/VeraIntentRegistry'
import { loadCatalogFile } from '../vera/VeraCatalogFile'
import { describeCalendarForPrompt } from '../vera/VeraCalendarCatalog'

const MAX_RETRIES: number = 3
// vera-server's address is not written down here. It lives in settings, given
// the same way as the API key -- `--ps veraServer http://host:port` -- because
// one person's machine address has no business in a shared repository.
function serverUrl(): string { return settings.getServerUrl() }

// DeepSeek and Local both run the agent loop on the device and differ only in
// which model writes the code; Server hands the whole job to vera-server.
const MODE_DEEPSEEK: string = 'deepseek'
const MODE_SERVER: string = 'server'
const MODE_LOCAL: string = 'local'

// The lower half of the screen is one pane at a time: the running program,
// its source, or the numbers behind the run.
const TAB_PREVIEW: string = 'preview'
const TAB_CODE: string = 'code'
const TAB_METRICS: string = 'metrics'

class ServerDecodedResponse {
  source: string = ''
  bytecode: string = ''
}

class RefineRequest {
  prompt: string = ''
  previousSource: string = ''
}

class AttemptMetrics {
  attempt: number = 0
  // Waiting for the first token and streaming the rest have different causes:
  // a long wait is the prompt being read, a slow stream is the model writing.
  ttftMs: number = 0
  genMs: number = 0
  compileMs: number = 0
  inputTokens: number = 0
  outputTokens: number = 0
  cacheHitTokens: number = 0
  thinking: boolean = false
  thinkMs: number = 0
  finishReason: string = ''
  // Which layer rejected the program, taken from the leading digit of the
  // first diagnostic: E1 is the parser, E2 is names and types. Dying in the
  // parser means the model missed the syntax; dying later means it wrote
  // readable VERA-L that means the wrong thing.
  failLayer: string = ''
  failCode: string = ''
  success: boolean = false
}

/** One generation or refinement, kept after the next one starts. */
class RunRecord {
  request: string = ''
  attempts: AttemptMetrics[] = []
  compiled: boolean = false
  delta: SourceDelta = new SourceDelta()
}

/** Everything spent since the last fresh generation, refinements included. */
class RunTotals {
  runs: number = 0
  attempts: number = 0
  ms: number = 0
  llmMs: number = 0
  compileMs: number = 0
  inputTokens: number = 0
  cacheHitTokens: number = 0
  outputTokens: number = 0
}

/** How far a refinement moved the program it started from. */
class SourceDelta {
  added: number = 0
  removed: number = 0
  keptPercent: number = 0
  measured: boolean = false
}

/**
 * The compiler groups diagnostics by the layer that raises them, and the
 * leading digit says which: E1 comes from the parser, E2 from names and types.
 * The distinction is the useful one -- a program rejected by the parser missed
 * the syntax, one rejected later reads fine and means the wrong thing.
 */
function codeOf(errors: string): string {
  let m = errors.match(/E\d{4}/)
  return m === null ? '' : m[0]
}

function layerOf(errors: string): string {
  let code = codeOf(errors)
  if (code.length === 0) { return 'compile' }
  let layer = code.substring(1, 2)
  if (layer === '1') { return 'parser' }
  if (layer === '2') { return 'names & types' }
  return 'layer E' + layer
}

function diffLines(before: string, after: string): SourceDelta {
  let delta = new SourceDelta()
  if (before.length === 0) { return delta }
  let oldLines: string[] = []
  for (let line of before.split('\n')) {
    let t = line.trim()
    if (t.length > 0) { oldLines.push(t) }
  }
  let newLines: string[] = []
  for (let line of after.split('\n')) {
    let t = line.trim()
    if (t.length > 0) { newLines.push(t) }
  }
  // Line multisets rather than a real diff: this answers "how much of the old
  // program survived" without running a diff algorithm on the phone.
  let counts = new Map<string, number>()
  for (let line of oldLines) {
    let n = counts.get(line)
    counts.set(line, (n === undefined ? 0 : n) + 1)
  }
  let kept = 0
  for (let line of newLines) {
    let n = counts.get(line)
    if (n !== undefined && n > 0) {
      kept += 1
      counts.set(line, n - 1)
    } else {
      delta.added += 1
    }
  }
  delta.removed = oldLines.length - kept
  delta.keptPercent = oldLines.length > 0 ? Math.round(kept * 100 / oldLines.length) : 0
  delta.measured = true
  return delta
}

function decodeServerResponse(body: string): ServerDecodedResponse {
  let lines = body.split('\n')
  let sourceLines: string[] = []
  let bytecodeLines: string[] = []
  let inSource = false
  let foundSource = false
  for (let line of lines) {
    if (line === ';vera-source-begin') {
      inSource = true
      foundSource = true
      continue
    }
    if (line === ';vera-source-end' && inSource) {
      inSource = false
      continue
    }
    if (inSource) {
      if (line.startsWith(';|')) {
        sourceLines.push(line.substring(2))
      }
      continue
    }
    bytecodeLines.push(line)
  }
  let result = new ServerDecodedResponse()
  result.source = foundSource ? sourceLines.join('\n') : ''
  result.bytecode = bytecodeLines.join('\n')
  return result
}

@Entry
@Component
struct GeneratePage {
  @State projectId: string = ''
  @State baseVersionId: string = ''
  @State prompt: string = ''
  @State generatedSource: string = ''
  @State status: string = ''
  @State generating: boolean = false
  @State modelReady: boolean = false
  @State mode: string = MODE_DEEPSEEK
  @State attempt: number = 0
  @State compiled: boolean = false
  @State compileErrors: string = ''
  @State compiledVbc2: string = ''
  @State compiledSource: string = ''
  @State refinePrompt: string = ''
  @State program: RunTotals = new RunTotals()
  @State delta: SourceDelta = new SourceDelta()
  // Every run of this program, oldest first. A refinement used to wipe the
  // numbers of the generation it was refining, which is exactly the comparison
  // worth having.
  @State runs: RunRecord[] = []
  @State composerOpen: boolean = false
  @State tab: string = TAB_PREVIEW
  @State attempts: AttemptMetrics[] = []
  @State totalMs: number = 0
  private systemPrompt: string = ''
  /** The skill with every catalogue but the intents spliced in. */
  private promptTemplate: string = ''
  /** What the selection step decided, shown while generating. */
  @State selectionNote: string = ''
  private grammar: string = ''
  private previousSource: string = ''
  private genStartTime: number = 0
  private cancelRequested: boolean = false
  private lastRequest: string = ''
  private failedSource: string = ''
  private serverBytecode: string = ''

  aboutToAppear(): void {
    let params = router.getParams() as Record<string, string>
    if (params !== null && params !== undefined) {
      this.projectId = params['projectId'] || ''
      this.baseVersionId = params['baseVersionId'] || ''
    }
    if (this.baseVersionId.length > 0) {
      let v = store.getVersion(this.projectId, this.baseVersionId)
      if (v !== null) { this.previousSource = v!.source }
    }
    settings.init(getContext(this).filesDir)
    // Shrink the page for the keyboard instead of panning it: panning slides
    // the preview up under the title bar, and with the refine field pinned at
    // the bottom the page has to give up height, not move.
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)
    this.loadResources()
  }

  // The key can arrive from a launch parameter while this page sits in the
  // foreground, so re-read it whenever the page comes back into view.
  onPageShow(): void {
    if (this.mode === MODE_DEEPSEEK && !this.generating) {
      this.checkDeepSeek()
    }
  }

  private async loadResources(): Promise<void> {
    try {
      let mgr = getContext(this).resourceManager
      // Both catalogues are generated rather than written out in the rawfile,
      // so the prompt cannot describe a component the compiler rejects or the
      // renderer cannot draw, nor an intent the compiler will not accept and
      // the host will not send.
      // Loaded here as well as in EntryAbility: this page can be reached in a
      // process that started somewhere else, and a prompt built without the
      // file would offer fewer intents than the device actually has.
      consent.init(getContext(this).filesDir)
      let extra = loadCatalogFile(getContext(this).filesDir)
      if (extra.problems.length > 0) {
        console.warn('VERA-CATALOG rejected ' + extra.rejected.toString() + ' rows: ' +
          extra.problems.join('; '))
      }
      let skill = await loadRawfileText(mgr, 'vera-skill.txt')
      // The UI and calendar catalogues are the same for every request, so they
      // are spliced in once. The intent catalogue is not: which rows a request
      // needs depends on what the person asked for, and that is decided per
      // generation, in startGenerate below. {{INTENT_CATALOG}} therefore stays
      // in the template until then.
      this.promptTemplate = skill
        .replace('{{UI_CATALOG}}', describeCatalogForPrompt())
        .replace('{{CALENDAR_CATALOG}}', describeCalendarForPrompt())
      // The phone's own list of intents, read once. It is what makes
      // intent.call usable: without an address the model would have to invent
      // one, and an invented address fails silently.
      loadRegistry().then((count: number) => {
        console.info('VERA-REGISTRY ' + count.toString() + ' intents available to intent.call')
      })
      this.systemPrompt = this.promptTemplate
        .replace('{{INTENT_CATALOG}}', describeIntentsForPrompt())
        .replace('{{DEVICE_INTENTS}}', '  (the list is read from the phone when you generate)')
      this.grammar = await loadRawfileText(mgr, 'vera.gbnf')
      this.status = 'Resources loaded'
    } catch (e) {
      this.status = 'Failed to load resources: ' + (e as Error).message
    }
    this.checkProvider()
  }

  private checkProvider(): void {
    if (this.mode === MODE_DEEPSEEK) {
      this.checkDeepSeek()
    } else if (this.mode === MODE_SERVER) {
      this.checkServer()
    } else {
      this.checkModel()
    }
  }

  private checkDeepSeek(): void {
    if (settings.hasApiKey()) {
      this.status = 'DeepSeek ready (' + settings.getModel() + ', key ' + settings.maskedKey() + ')'
    } else {
      this.status = 'No API key. Send one with: aa start -a EntryAbility -b com.vera.probe.dyn --ps deepseekKey <key>'
    }
  }

  private async checkServer(): Promise<void> {
    if (!settings.hasServerUrl()) {
      // Said in full, because the address is not written down anywhere in the
      // app and the person has no other way to learn what is missing.
      this.status = 'No server address. Pass one at launch: ' +
        'hdc shell aa start -a EntryAbility -b com.vera.probe.dyn ' +
        '--ps veraServer http://host:port'
      return
    }
    this.status = 'Checking server...'
    let client = http.createHttp()
    try {
      let resp = await client.request(serverUrl() + '/health', {
        method: http.RequestMethod.GET,
        connectTimeout: 5000,
        readTimeout: 5000
      })
      if (resp.responseCode === 200) {
        let body = resp.result as string
        let health = JSON.parse(body) as Record<string, Object>
        this.status = 'Server ready (' + (health['model'] as string) + ')'
      } else {
        this.status = 'Server error: HTTP ' + resp.responseCode
      }
    } catch (e) {
      this.status = 'Server unreachable: ' + (e as Error).message
    } finally {
      client.destroy()
    }
  }

  private async checkModel(): Promise<void> {
    let filesDir = getContext(this).filesDir
    let modelPath = LlamaEngine.defaultModelPath(filesDir)
    if (!LlamaEngine.modelExists(filesDir)) {
      // hdc file send is blocked on release-provisioned installs, so the
      // model is fetched from the vera-server /models endpoint instead.
      await this.downloadModel(modelPath)
    }
    this.modelReady = LlamaEngine.modelExists(filesDir)
    if (!this.modelReady) {
      this.status = 'Model not found'
      return
    }
    this.status = 'Model ready'
    if (!engine.isReady()) {
      this.status = 'Loading model...'
      let ok = engine.init({
        modelPath: modelPath,
        nCtx: 4096,
        nThreads: 4,
        nGpuLayers: 0
      })
      this.status = ok ? 'Model loaded' : 'Model load failed'
      this.modelReady = ok
    }
  }

  private async downloadModel(modelPath: string): Promise<void> {
    let filesDir = getContext(this).filesDir
    try {
      fs.mkdirSync(filesDir + '/models', true)
    } catch (_e) {}
    this.status = 'Downloading model (one-time, ~1.9GB)...'
    try {
      let task = await request.downloadFile(getContext(this), {
        url: serverUrl() + '/models/qwen2.5-coder-3b-instruct-q4_k_m.gguf',
        filePath: modelPath
      })
      task.on('progress', (received: number, total: number): void => {
        if (total > 0) {
          this.status = 'Downloading model ' + Math.floor(received * 100 / total).toString() + '%'
        }
      })
      await new Promise<void>((resolve, reject) => {
        task.on('complete', (): void => { resolve() })
        task.on('fail', (err: number): void => { reject(new Error('download failed, code ' + err.toString())) })
      })
      this.status = 'Model downloaded'
    } catch (e) {
      this.status = 'Model download failed: ' + (e as Error).message
    }
  }

  private doGenerate(): void {
    if (this.prompt.trim().length === 0) { return }
    if (this.mode === MODE_SERVER) {
      if (!settings.hasServerUrl()) { this.checkServer(); return }
      this.doServerGenerate()
      return
    }
    if (this.mode === MODE_DEEPSEEK && !settings.hasApiKey()) {
      this.checkDeepSeek()
      return
    }
    if (this.mode === MODE_LOCAL && !this.modelReady) { return }
    this.generating = true
    this.generatedSource = ''
    this.compiled = false
    this.compileErrors = ''
    this.attempt = 1
    this.attempts = []
    this.totalMs = 0
    this.serverBytecode = ''
    this.compiledVbc2 = ''
    this.compiledSource = ''
    this.cancelRequested = false
    this.failedSource = ''
    this.program = new RunTotals()
    this.delta = new SourceDelta()
    this.runs = []
    this.startRun(this.prompt.trim())
    this.genStartTime = Date.now()
    this.lastRequest = this.prompt.trim()
    this.status = 'Choosing which intents this needs...'
    this.applySelection(this.prompt.trim()).then(() => {
      this.status = 'Generating (attempt 1/' + MAX_RETRIES + ')... ' + this.selectionNote
      this.runAttempt(this.prompt.trim(), '')
    })
  }

  /**
   * Picks the intent rows this request needs and splices them into the prompt.
   *
   * Runs once per generation rather than once per attempt: the request does not
   * change between retries, and a retry is already the slow path.
   *
   * The chosen domains go into the status line because a selection that dropped
   * something is otherwise invisible -- the app would simply come back without
   * the feature, a minute later, with nothing to point at.
   */
  private async applySelection(userPrompt: string): Promise<void> {
    if (this.promptTemplate.length === 0) { return }
    let selection: Selection = everything('all intents')
    try {
      selection = await selectDomains(userPrompt, settings.getSelectorKey())
    } catch (_e) {
      // selectDomains does not throw, but a generation must not depend on that.
      selection = everything('all intents (selector failed)')
    }
    // Two questions, two jobs. The domains decide which catalogue rows are
    // described, and they are good at that: a row belongs to one part of the
    // phone and says so. The addresses are picked intent by intent, because a
    // domain cannot tell a torch from a camera and the registry has no words
    // to match on beyond the intent's own name.
    let picked: TargetChoice = new TargetChoice([], 'no pick')
    try {
      picked = await selectTargets(userPrompt, settings.getSelectorKey())
    } catch (_e) {
    }
    let registry = describeTargetsForPrompt(picked.targets, userPrompt)
    this.systemPrompt = this.promptTemplate
      .replace('{{INTENT_CATALOG}}', describeIntentsForPrompt(selection.domains))
      .replace('{{DEVICE_INTENTS}}', registry.length > 0
        ? registry
        : '  (none found on this phone -- use the checked list above)')
    this.selectionNote = selection.note + ' | ' + picked.note +
      (registry.length > 0 ? ' | ' + registry.length.toString() + ' chars of addresses' : '')
  }

  private async doServerGenerate(): Promise<void> {
    this.generating = true
    this.generatedSource = ''
    this.compiled = false
    this.compileErrors = ''
    this.attempts = []
    this.totalMs = 0
    this.serverBytecode = ''
    this.compiledVbc2 = ''
    this.compiledSource = ''
    this.program = new RunTotals()
    this.delta = new SourceDelta()
    this.runs = []
    this.startRun(this.prompt.trim())
    this.genStartTime = Date.now()
    this.lastRequest = this.prompt.trim()
    this.status = this.previousSource.length > 0 ? 'Server refining...' : 'Server generating...'

    let metrics = new AttemptMetrics()
    metrics.attempt = 1
    let client = http.createHttp()
    try {
      let genStart = Date.now()
      // Refinement: send the base version's source so the server can edit it
      // instead of regenerating from scratch.
      let requestBody: string = this.prompt.trim()
      let contentType: string = 'text/plain; charset=utf-8'
      if (this.previousSource.length > 0) {
        let refine = new RefineRequest()
        refine.prompt = this.prompt.trim()
        refine.previousSource = this.previousSource
        requestBody = JSON.stringify(refine)
        contentType = 'application/json'
      }
      let resp = await client.request(serverUrl() + '/compile', {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': contentType },
        extraData: requestBody,
        connectTimeout: 10000,
        readTimeout: 180000
      })
      metrics.genMs = Date.now() - genStart

      if (resp.responseCode === 200) {
        let body = resp.result as string
        let decoded = decodeServerResponse(body)
        this.generatedSource = decoded.source
        this.serverBytecode = decoded.bytecode
        this.compiledVbc2 = decoded.bytecode
        this.compiledSource = decoded.source
        this.composerOpen = false
        this.tab = TAB_PREVIEW
        this.compiled = true
        this.compileErrors = ''
        metrics.success = true
        this.status = 'Server compiled successfully'
      } else {
        let body = resp.result as string
        try {
          let errObj = JSON.parse(body) as Record<string, Object>
          let diags = errObj['diagnostics'] as Object[]
          if (diags !== null && diags !== undefined && diags.length > 0) {
            let firstDiag = diags[0] as Record<string, Object>
            let msg = (firstDiag['message'] as string) || ''
            let generatedSrc = (firstDiag['generatedSource'] as string) || ''
            if (generatedSrc.length > 0) {
              this.generatedSource = generatedSrc
            }
            this.compileErrors = msg
          } else {
            this.compileErrors = 'Server error: HTTP ' + resp.responseCode
          }
        } catch (_e) {
          this.compileErrors = 'Server error: HTTP ' + resp.responseCode + ' — ' + body.substring(0, 200)
        }
        this.status = 'Server generation failed'
      }
    } catch (e) {
      this.compileErrors = 'Request failed: ' + (e as Error).message
      this.status = 'Server unreachable'
    } finally {
      client.destroy()
    }

    this.attempts = [metrics]
    this.totalMs = Date.now() - this.genStartTime
    this.generating = false
  }

  /**
   * The one place that knows which model is behind the loop. Everything after
   * it -- compile, collect diagnostics, retry -- is identical for both.
   */
  private callModel(request: GenerateRequest, onToken: (token: string) => void): Promise<GenerateResult> {
    if (this.mode === MODE_DEEPSEEK) {
      // deepseek-flash thinks by default, and the reasoning comes out of the
      // same token budget as the program: an 8K cap was being spent thinking
      // and the program arrived truncated. A first attempt does not need it --
      // the output format is fixed and the programs are short. A retry has
      // compiler diagnostics to work through, so it gets both.
      let retry = this.attempt > 1
      deepseek.setThinking(retry)
      request.maxTokens = retry ? 32768 : 8192
      return deepseek.generate(request, onToken)
    }
    return Promise.resolve(engine.generate(request, onToken))
  }

  private async runAttempt(userPrompt: string, errorFeedback: string): Promise<void> {
    this.generatedSource = ''
    let metrics = new AttemptMetrics()
    metrics.attempt = this.attempt

    let request = new GenerateRequest()
    request.systemPrompt = this.systemPrompt
    request.grammar = this.grammar
    request.maxTokens = 2048
    request.temperature = 0.2

    if (errorFeedback.length > 0) {
      // Hand back the program that failed, not the last one that worked: the
      // diagnostics carry line and column numbers, and they only mean
      // something against the text they were produced from. Sending the last
      // good program instead made every retry a blind rewrite -- which is how
      // three attempts in a row used to trip over the same operator.
      request.previousSource = this.failedSource
      request.userPrompt = userPrompt +
        '\n\nThe program above is your previous attempt and it failed to compile:\n' + errorFeedback +
        '\n\nFix these errors and return the complete program.'
    } else if (this.previousSource.length > 0) {
      request.previousSource = this.previousSource
      request.userPrompt = userPrompt
    } else {
      request.userPrompt = userPrompt
    }

    let genStart = Date.now()
    let firstTokenAt = 0
    let genResult: GenerateResult
    try {
      genResult = await this.callModel(request, (token: string) => {
        if (firstTokenAt === 0) { firstTokenAt = Date.now() }
        this.generatedSource += token
      })
      if (genResult.text.length > 0) {
        this.generatedSource = genResult.text
      }
    } catch (e) {
      metrics.genMs = Date.now() - genStart
      metrics.failLayer = 'request'
      this.attempts = [...this.attempts, metrics]
      this.totalMs = Date.now() - this.genStartTime
      this.addToProgram(metrics)
      this.status = 'Generation failed: ' + (e as Error).message
      this.generating = false
      return
    }
    metrics.genMs = Date.now() - genStart
    metrics.ttftMs = firstTokenAt > 0 ? firstTokenAt - genStart : 0
    if (this.cancelRequested) {
      this.attempts = [...this.attempts, metrics]
      this.totalMs = Date.now() - this.genStartTime
      this.status = 'Stopped'
      this.generating = false
      return
    }
    metrics.inputTokens = genResult.inputTokens
    metrics.outputTokens = genResult.outputTokens
    if (this.mode === MODE_DEEPSEEK) {
      metrics.cacheHitTokens = deepseek.lastCacheHitTokens()
      metrics.finishReason = deepseek.lastFinishReason()
      metrics.thinking = this.attempt > 1
      // Prefill from the engine rather than the token callback: the callback
      // only fires on visible content, so with reasoning on it would report
      // the thinking time as waiting.
      let prefill = deepseek.lastPrefillMs()
      if (prefill > 0) { metrics.ttftMs = prefill }
      metrics.thinkMs = deepseek.lastThinkMs()
    }

    if (this.generatedSource.trim().length === 0) {
      metrics.failLayer = 'empty'
      this.status = 'Generation produced empty output'
      this.generating = false
      this.attempts = [...this.attempts, metrics]
      this.totalMs = Date.now() - this.genStartTime
      this.addToProgram(metrics)
      return
    }

    this.status = 'Compiling (attempt ' + this.attempt + '/' + MAX_RETRIES + ')...'
    let vbc2 = ''
    let errors = ''
    let compileStart = Date.now()
    try {
      let result = compileVeraSource(this.generatedSource.trim())
      vbc2 = result.vbc2
    } catch (e) {
      if (e instanceof CompileError) {
        errors = e.message
      } else {
        errors = (e as Error).message
      }
    }
    metrics.compileMs = Date.now() - compileStart

    // A program cut off at the token ceiling fails to parse somewhere near its
    // end. Saying so is worth more to the next attempt than the parse error,
    // which describes the cut rather than the mistake.
    if (errors.length > 0 && this.mode === MODE_DEEPSEEK && deepseek.lastFinishReason() === 'length') {
      errors = 'The previous attempt was cut off at the output token limit before the program ended, so it did not parse. Write a shorter program.\n' + errors
    }

    if (errors.length === 0 && vbc2.length > 0) {
      let hadProgram = this.compiledVbc2.length > 0
      metrics.success = true
      this.attempts = [...this.attempts, metrics]
      this.addToProgram(metrics)
      this.totalMs = Date.now() - this.genStartTime
      // Source and bytecode are kept as a pair: the next failed attempt
      // overwrites generatedSource, and Save must not pair that broken text
      // with the bytecode of the program still on screen.
      this.delta = diffLines(this.previousSource, this.generatedSource.trim())
      let current = this.currentRun()
      if (current !== null) { current!.delta = this.delta }
      this.compiledVbc2 = vbc2
      this.compiledSource = this.generatedSource.trim()
      this.refinePrompt = ''
      this.composerOpen = false
      // Only when the program first appears: yanking the pane away from
      // someone reading the source or the numbers is worse than leaving it.
      if (!hadProgram) { this.tab = TAB_PREVIEW }
      this.compiled = true
      this.compileErrors = ''
      this.status = 'Compiled successfully on attempt ' + this.attempt
      this.generating = false
      return
    }

    metrics.failLayer = layerOf(errors)
    metrics.failCode = codeOf(errors)
    this.attempts = [...this.attempts, metrics]
    this.addToProgram(metrics)
    this.compileErrors = errors
    if (this.attempt < MAX_RETRIES) {
      // runAttempt clears generatedSource on entry, so the broken text has to
      // be kept now if the next attempt is to see it.
      this.failedSource = this.generatedSource.trim()
      this.attempt++
      this.status = 'Compile failed, retrying (attempt ' + this.attempt + '/' + MAX_RETRIES + ')...'
      await this.runAttempt(userPrompt, errors)
    } else {
      this.totalMs = Date.now() - this.genStartTime
      this.status = 'Compilation failed after ' + MAX_RETRIES + ' attempts'
      this.generating = false
    }
  }

  private addToProgram(metrics: AttemptMetrics): void {
    let record = this.currentRun()
    if (record !== null) {
      record!.attempts = [...record!.attempts, metrics]
      record!.compiled = metrics.success
      this.runs = [...this.runs]
    }
    let totals = new RunTotals()
    totals.runs = this.program.runs
    totals.attempts = this.program.attempts + 1
    totals.ms = this.program.ms + metrics.genMs + metrics.compileMs
    totals.llmMs = this.program.llmMs + metrics.genMs
    totals.compileMs = this.program.compileMs + metrics.compileMs
    totals.inputTokens = this.program.inputTokens + metrics.inputTokens
    totals.cacheHitTokens = this.program.cacheHitTokens + metrics.cacheHitTokens
    totals.outputTokens = this.program.outputTokens + metrics.outputTokens
    this.program = totals
  }

  private startRun(request: string): void {
    let record = new RunRecord()
    record.request = request
    this.runs = [...this.runs, record]
    this.startRunTotals()
  }

  private currentRun(): RunRecord | null {
    return this.runs.length > 0 ? this.runs[this.runs.length - 1] : null
  }

  private startRunTotals(): void {
    let totals = new RunTotals()
    totals.runs = this.program.runs + 1
    totals.attempts = this.program.attempts
    totals.ms = this.program.ms
    totals.llmMs = this.program.llmMs
    totals.compileMs = this.program.compileMs
    totals.inputTokens = this.program.inputTokens
    totals.cacheHitTokens = this.program.cacheHitTokens
    totals.outputTokens = this.program.outputTokens
    this.program = totals
  }

  /**
   * DeepSeek's published rates for deepseek-flash, per million tokens. Peak is
   * 01:00-04:00 and 06:00-10:00 UTC on weekdays and costs twice as much. The
   * price list lives on their side, so every figure here is an estimate.
   */
  private ratePerMillion(kind: string): number {
    let now = new Date()
    let day = now.getUTCDay()
    let hour = now.getUTCHours()
    let peak = day >= 1 && day <= 5 && ((hour >= 1 && hour < 4) || (hour >= 6 && hour < 10))
    if (kind === 'cache') { return peak ? 0.006 : 0.003 }
    if (kind === 'fresh') { return peak ? 0.30 : 0.15 }
    return peak ? 1.20 : 0.60
  }

  private costOf(input: number, cached: number, output: number): number {
    let fresh = input - cached
    if (fresh < 0) { fresh = 0 }
    return (cached * this.ratePerMillion('cache') +
      fresh * this.ratePerMillion('fresh') +
      output * this.ratePerMillion('output')) / 1000000
  }

  private runCost(): number {
    return this.costOf(this.totalInputTokens(), this.totalCacheHitTokens(), this.totalOutputTokens())
  }

  private formatUsd(value: number): string {
    if (value <= 0) { return '$0' }
    if (value < 0.01) { return '$' + value.toFixed(4) }
    return '$' + value.toFixed(3)
  }

  /**
   * Output tokens over everything after the prompt was read. Reasoning tokens
   * are billed as output and take real time, so dividing by the visible
   * stream alone would report rates the model never reached.
   */
  private formatRate(metrics: AttemptMetrics): string {
    let workMs = metrics.genMs - metrics.ttftMs
    if (workMs <= 0 || metrics.outputTokens === 0) { return '' }
    return ' (' + Math.round(metrics.outputTokens * 1000 / workMs) + ' tok/s)'
  }

  private attemptVerdict(a: AttemptMetrics): string {
    if (a.success) { return a.thinking ? '✓ think' : '✓' }
    if (a.failLayer === 'request') { return '✗ request failed' }
    if (a.failLayer === 'empty') { return '✗ empty answer' }
    let verdict = '✗ ' + a.failLayer
    if (a.failCode.length > 0) { verdict += ' ' + a.failCode }
    if (a.finishReason === 'length') { verdict += ' · cut off at the token limit' }
    return verdict
  }

  private freshInputTokens(): number {
    let fresh = this.totalInputTokens() - this.totalCacheHitTokens()
    return fresh > 0 ? fresh : 0
  }

  private cacheLabel(): string {
    let cached = this.totalCacheHitTokens()
    if (cached === 0) { return '' }
    let percent = Math.round(cached * 100 / this.totalInputTokens())
    return ' (cached ' + cached + ' · ' + percent + '%)'
  }

  // Money only where it is actually spent and known: llama runs on the phone,
  // and what the server pays for a generation is not ours to guess.
  private programCostLabel(): string {
    if (this.mode !== MODE_DEEPSEEK) { return '' }
    return ' · ~' + this.formatUsd(
      this.costOf(this.program.inputTokens, this.program.cacheHitTokens, this.program.outputTokens))
  }

  private runVerdict(): string {
    if (this.generating) { return 'running attempt ' + this.attempt }
    if (this.compiled) { return 'compiled on attempt ' + this.attempt }
    return 'failed after ' + this.attempts.length + ' attempts'
  }

  private cachePercentNote(): string {
    let cached = this.totalCacheHitTokens()
    if (cached === 0 || this.totalInputTokens() === 0) { return 'nothing reused' }
    return 'reused by DeepSeek, ' + Math.round(cached * 100 / this.totalInputTokens()) + '%'
  }

  private rateNote(a: AttemptMetrics): string {
    let workMs = a.genMs - a.ttftMs
    if (workMs <= 0 || a.outputTokens === 0) { return 'model time' }
    return Math.round(a.outputTokens * 1000 / workMs) + ' tok/s'
  }

  /** Everything except the run on screen, newest first. */
  private pastRuns(): RunRecord[] {
    let past: RunRecord[] = []
    for (let i = this.runs.length - 2; i >= 0; i--) { past.push(this.runs[i]) }
    return past
  }

  private indexOfRun(record: RunRecord): number {
    for (let i = 0; i < this.runs.length; i++) {
      if (this.runs[i] === record) { return i }
    }
    return 0
  }

  private runMs(record: RunRecord): number {
    let ms = 0
    for (let a of record.attempts) { ms += a.genMs + a.compileMs }
    return ms
  }

  private pastRunSummary(record: RunRecord): string {
    let summary = record.attempts.length + (record.attempts.length === 1 ? ' attempt · ' : ' attempts · ')
    summary += this.formatMs(this.runMs(record))
    if (this.mode === MODE_DEEPSEEK) {
      let input = 0
      let cached = 0
      let output = 0
      for (let a of record.attempts) {
        input += a.inputTokens
        cached += a.cacheHitTokens
        output += a.outputTokens
      }
      summary += ' · ~' + this.formatUsd(this.costOf(input, cached, output))
    }
    if (record.delta.measured) {
      summary += ' · +' + record.delta.added + ' −' + record.delta.removed + ' lines'
    }
    return summary
  }

  private programSpentLabel(): string {
    if (this.mode !== MODE_DEEPSEEK) { return this.formatMs(this.program.ms) }
    return '~' + this.formatUsd(
      this.costOf(this.program.inputTokens, this.program.cacheHitTokens, this.program.outputTokens))
  }

  private runHeadline(): string {
    let head = this.compiled
      ? 'compiled on attempt ' + this.attempt
      : (this.generating ? 'running' : 'failed after ' + this.attempts.length + ' attempts')
    head += ' · ' + this.formatMs(this.totalMs)
    if (this.mode === MODE_DEEPSEEK) { head += ' · ~' + this.formatUsd(this.runCost()) }
    return head
  }

  /** Wall time inside the model across this run, retries included. */
  private runLlmMs(): number {
    let ms = 0
    for (let a of this.attempts) { ms += a.genMs }
    return ms
  }

  private runCompileMs(): number {
    let ms = 0
    for (let a of this.attempts) { ms += a.compileMs }
    return ms
  }

  private writeMs(a: AttemptMetrics): number {
    let ms = a.genMs - a.ttftMs - a.thinkMs
    return ms > 0 ? ms : 0
  }

  /**
   * Over everything after the prompt was read. Reasoning tokens are billed as
   * output and take real time, so dividing by the writing phase alone would
   * report a speed the model never reached.
   */
  private speedLabel(a: AttemptMetrics): string {
    let workMs = a.genMs - a.ttftMs
    if (workMs <= 0 || a.outputTokens === 0) { return '—' }
    return Math.round(a.outputTokens * 1000 / workMs) + ' tok/s'
  }

  private attemptTiming(a: AttemptMetrics): string {
    let parts = a.ttftMs > 0 ? 'wait ' + this.formatMs(a.ttftMs) + ' · ' : ''
    if (a.thinkMs > 0) { parts += 'think ' + this.formatMs(a.thinkMs) + ' · ' }
    parts += 'gen ' + this.formatMs(a.genMs) + this.formatRate(a)
    if (a.compileMs > 0) { parts += ' · compile ' + this.formatMs(a.compileMs) }
    if (a.inputTokens > 0 || a.outputTokens > 0) {
      parts += ' · ' + a.inputTokens + '→' + a.outputTokens
    }
    return parts
  }

  private hasResult(): boolean {
    return this.compiledVbc2.length > 0
  }

  /**
   * Sends the change request together with the program currently on screen.
   * The existing refine path does the rest: previousSource goes over as the
   * assistant's own last turn, so the model edits that program instead of
   * writing a new one, and a failed attempt still gets the three compiler
   * retries.
   */
  private doRefine(): void {
    let ask = this.refinePrompt.trim()
    if (ask.length === 0 || this.compiledSource.length === 0) { return }
    // Refine from the last program that compiled, not from generatedSource --
    // a failed attempt leaves its broken text in there.
    this.previousSource = this.compiledSource
    this.generating = true
    this.compiled = false
    this.compileErrors = ''
    this.attempt = 1
    this.attempts = []
    this.totalMs = 0
    this.serverBytecode = ''
    this.cancelRequested = false
    this.failedSource = ''
    this.delta = new SourceDelta()
    this.startRun(ask)
    this.genStartTime = Date.now()
    this.lastRequest = ask
    this.status = 'Refining (attempt 1/' + MAX_RETRIES + ')...'
    this.runAttempt(ask, '')
  }

  private stopGeneration(): void {
    this.cancelRequested = true
    if (this.mode === MODE_LOCAL) { engine.stop() }
    if (this.mode === MODE_DEEPSEEK) { deepseek.stop() }
    this.generating = false
    this.totalMs = Date.now() - this.genStartTime
    this.status = 'Stopped'
  }

  private doSave(): void {
    let source = this.compiledSource.length > 0 ? this.compiledSource : this.generatedSource.trim()
    if (source.length === 0) { return }
    let fullPrompt = this.lastRequest.length > 0 ? this.lastRequest : this.prompt.trim()
    let note = fullPrompt
    if (note.length > 100) { note = note.substring(0, 100) + '...' }
    let vbc2 = this.compiledVbc2
    if (vbc2.length === 0 && this.compiled) {
      try {
        let result = compileVeraSource(source)
        vbc2 = result.vbc2
      } catch (_e) {}
    }
    store.createVersion(this.projectId, source, vbc2, note, fullPrompt)
    this.status = vbc2.length > 0 ? 'Saved with compiled bytecode' : 'Saved (source only — compile errors)'
    refreshForms()
    router.back()
  }

  private formatMs(ms: number): string {
    if (ms < 1000) return ms + 'ms'
    let secs = (ms / 1000).toFixed(1)
    return secs + 's'
  }

  private modeLabel(): string {
    if (this.mode === MODE_DEEPSEEK) { return 'DeepSeek' }
    if (this.mode === MODE_SERVER) { return 'Server' }
    return 'Local'
  }

  private modeSubtitle(): string {
    if (this.mode === MODE_DEEPSEEK) { return settings.getModel() + ' - agent loop on device' }
    if (this.mode === MODE_SERVER) { return serverUrl() }
    return 'On-device Qwen3-Coder-3B'
  }

  private modeTint(): string {
    if (this.mode === MODE_DEEPSEEK) { return '#E8F5E9' }
    if (this.mode === MODE_SERVER) { return '#E3F2FD' }
    return '#FFF3E0'
  }

  private modeInk(): string {
    if (this.mode === MODE_DEEPSEEK) { return '#2E7D32' }
    if (this.mode === MODE_SERVER) { return '#1565C0' }
    return '#E65100'
  }

  private nextMode(): string {
    if (this.mode === MODE_DEEPSEEK) { return MODE_SERVER }
    if (this.mode === MODE_SERVER) { return MODE_LOCAL }
    return MODE_DEEPSEEK
  }

  private tabTint(name: string): string {
    return this.tab === name ? '#007DFF' : '#F0F0F0'
  }

  private tabInk(name: string): string {
    return this.tab === name ? '#FFFFFF' : '#666666'
  }

  private canGenerate(): boolean {
    if (this.mode === MODE_SERVER) { return settings.hasServerUrl() }
    if (this.mode === MODE_DEEPSEEK) { return settings.hasApiKey() }
    return this.modelReady
  }

  private totalCacheHitTokens(): number {
    let total = 0
    for (let a of this.attempts) total += a.cacheHitTokens
    return total
  }

  private totalInputTokens(): number {
    let total = 0
    for (let a of this.attempts) total += a.inputTokens
    return total
  }

  private totalOutputTokens(): number {
    let total = 0
    for (let a of this.attempts) total += a.outputTokens
    return total
  }

  /**
   * One fact per tile: a label, the number, and a line saying what it means.
   * Values stay short by construction, which is also what keeps the pane from
   * running off the side of a phone.
   */
  @Builder
  cell(label: string, value: string, note: string) {
    // Two nodes on purpose: in ArkUI width() sizes the content and padding is
    // added outside it, so a padded node that is also given a width or a
    // layout weight ends up wider than its parent. The outer node owns the
    // width, the inner one owns the padding.
    Column() {
      Column({ space: 2 }) {
        Text(label).fontSize(10).fontColor('#888888').maxLines(1)
        Text(value).fontSize(17).fontWeight(FontWeight.Bold).fontColor('#222222')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(note).fontSize(10).fontColor('#999999').maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .padding(10)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
  }

  @Builder
  pastRun(record: RunRecord, index: number) {
    Column() {
      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text('#' + (index + 1) + (index === 0 ? ' generated' : ' refined'))
            .fontSize(11).fontColor('#888888')
          Text(record.compiled ? '✓' : '✗')
            .fontSize(11)
            .fontColor(record.compiled ? '#2E7D32' : '#C62828')
        }
        Text(record.request.length > 0 ? record.request : '(no request)')
          .fontSize(12).fontColor('#333333')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.pastRunSummary(record))
          .fontSize(11).fontColor('#888888')
      }
      .alignItems(HorizontalAlign.Start)
      .padding(10)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
  }

  build() {
    Navigation() {
      Column() {
        if (this.previousSource.length > 0 && !this.hasResult()) {
          Text('Refining existing version')
            .fontSize(13).fontColor('#007DFF').padding({ left: 16, top: 8 })
        }

        Row({ space: 8 }) {
          Button(this.modeLabel())
            .type(ButtonType.Normal)
            .fontSize(12)
            .height(30)
            .backgroundColor(this.modeTint())
            .fontColor(this.modeInk())
            .enabled(!this.generating)
            .onClick(() => {
              this.mode = this.nextMode()
              this.checkProvider()
            })
          Text(this.modeSubtitle())
            .fontSize(11).fontColor('#999999').layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8 })

        // With a running program on screen the original request collapses to a
        // single line, leaving the height to the preview. Tapping it reopens
        // the composer to start over from a new request.
        if (this.hasResult() && !this.composerOpen) {
          Row({ space: 8 }) {
            Text(this.lastRequest.length > 0 ? this.lastRequest : this.prompt)
              .fontSize(12)
              .fontColor('#666666')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .onClick(() => { this.composerOpen = true })
            Button('New')
              .type(ButtonType.Normal)
              .fontSize(11)
              .height(28)
              .backgroundColor('#F0F0F0')
              .fontColor('#666666')
              .enabled(!this.generating)
              .onClick(() => { this.composerOpen = true })
            Button('Save')
              .type(ButtonType.Normal)
              .fontSize(11)
              .height(28)
              .enabled(!this.generating)
              .onClick(() => { this.doSave() })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8 })
        } else {
          TextArea({ placeholder: 'Describe the app you want...', text: this.prompt })
            .onChange((value: string) => { this.prompt = value })
            .width('100%')
            .height(100)
            .margin(16)

          Row({ space: 10 }) {
            Button(this.generating ? 'Stop' : 'Generate')
              .type(ButtonType.Normal)
              .layoutWeight(1)
              .enabled(this.canGenerate() || this.generating)
              .onClick(() => {
                if (this.generating) {
                  this.stopGeneration()
                } else {
                  this.doGenerate()
                }
              })
            Button('Save')
              .type(ButtonType.Normal)
              .layoutWeight(1)
              .enabled(this.generatedSource.trim().length > 0 && !this.generating)
              .onClick(() => { this.doSave() })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
        }

        Row({ space: 8 }) {
          Text(this.status)
            .fontSize(12)
            .fontColor(this.compiled ? '#34C759' : '#999999')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 4 })

        Row({ space: 6 }) {
          Button('Preview')
            .type(ButtonType.Normal)
            .fontSize(12)
            .height(30)
            .layoutWeight(1)
            .backgroundColor(this.tabTint(TAB_PREVIEW))
            .fontColor(this.tabInk(TAB_PREVIEW))
            .onClick(() => { this.tab = TAB_PREVIEW })
          Button('Code')
            .type(ButtonType.Normal)
            .fontSize(12)
            .height(30)
            .layoutWeight(1)
            .backgroundColor(this.tabTint(TAB_CODE))
            .fontColor(this.tabInk(TAB_CODE))
            .onClick(() => { this.tab = TAB_CODE })
          Button('Metrics')
            .type(ButtonType.Normal)
            .fontSize(12)
            .height(30)
            .layoutWeight(1)
            .backgroundColor(this.tabTint(TAB_METRICS))
            .fontColor(this.tabInk(TAB_METRICS))
            .onClick(() => { this.tab = TAB_METRICS })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 6 })

        // Compile errors belong to no single pane -- they explain what the
        // status line says, so they stay above all three.
        if (this.compileErrors.length > 0) {
          Scroll() {
            Text(this.compileErrors)
              .fontSize(11)
              .fontFamily('monospace')
              .fontColor('#FF3B30')
              .width('100%')
              .padding(8)
          }
          .width('100%')
          .constraintSize({ maxHeight: 100 })
          .margin({ left: 16, right: 16 })
          .backgroundColor('#FFF0F0')
          .borderRadius(8)
        }

        if (this.mode === MODE_LOCAL && !this.modelReady && !this.generating) {
          Column() {
            Text('Model not downloaded').fontSize(14).fontWeight(FontWeight.Medium)
            Text('Switch to Local mode to download the model automatically (one-time, ~1.9GB over WiFi).')
              .fontSize(12).fontColor('#666666').margin({ top: 4 })
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#FFF8E0')
          .margin({ left: 16, right: 16, top: 8 })
          .borderRadius(8)
        }

        if (this.tab === TAB_PREVIEW) {
          Column() {
            if (this.hasResult()) {
              VeraPreview({ vbc2: this.compiledVbc2 })
            } else {
              Text(this.generating ? 'Building...' : 'The program will run here once it compiles')
                .fontSize(13)
                .fontColor('#BBBBBB')
                .padding(24)
            }
          }
          .width('100%')
          .layoutWeight(1)
          .margin({ left: 12, right: 12, top: 4 })
          .backgroundColor('#FFFFFF')
          .border({ width: 1, color: '#D8E1ED' })
          .borderRadius(10)
          .clip(true)
        } else if (this.tab === TAB_CODE) {
          Scroll() {
            Text(this.generatedSource.length > 0 ? this.generatedSource : '(generated source will appear here)')
              .fontSize(12)
              .fontFamily('monospace')
              .fontColor(this.generatedSource.length > 0 ? '#333333' : '#CCCCCC')
              .width('100%')
              .padding(12)
          }
          .width('100%')
          .layoutWeight(1)
          .align(Alignment.Top)
          .margin({ left: 12, right: 12, top: 4 })
          .backgroundColor('#F5F7FA')
          .borderRadius(10)
        } else {
          Scroll() {
            Column({ space: 10 }) {
              if (this.attempts.length === 0) {
                Text('No run yet').fontSize(13).fontColor('#BBBBBB').width('100%')
              } else {
                // The headline is two of the same tiles as everything else:
                // a right-aligned column inside a full-width row kept landing
                // past the edge, and this needs no special case.
                Row({ space: 8 }) {
                  this.cell('Time', this.formatMs(this.totalMs), this.runVerdict())
                  if (this.mode === MODE_DEEPSEEK) {
                    this.cell('Cost', '~' + this.formatUsd(this.runCost()), 'incl. failed attempts')
                  }
                }
                .width('100%')

                // Where the run time actually went: waiting on the model, or
                // working on the phone.
                Row({ space: 8 }) {
                  this.cell('LLM wall', this.formatMs(this.runLlmMs()), 'all calls this run')
                  this.cell('On device', this.formatMs(this.runCompileMs()), 'compiler only')
                }
                .width('100%')

                if (this.delta.measured) {
                  Row({ space: 8 }) {
                    this.cell('Changed', '+' + this.delta.added + ' −' + this.delta.removed + ' lines',
                      'against the previous version')
                    this.cell('Kept', this.delta.keptPercent + '%', 'of the previous lines')
                  }
                  .width('100%')
                }

                if (this.mode !== MODE_SERVER) {
                  Row({ space: 8 }) {
                    this.cell('Input', this.totalInputTokens() + ' toks', 'rules, request, old code')
                    this.cell('Cached', this.totalCacheHitTokens() + ' toks', this.cachePercentNote())
                  }
                  .width('100%')
                  Row({ space: 8 }) {
                    this.cell('Fresh', this.freshInputTokens() + ' toks', 'input at full price')
                    this.cell('Output', this.totalOutputTokens() + ' toks', 'program and reasoning')
                  }
                  .width('100%')
                }

                ForEach(this.attempts, (a: AttemptMetrics) => {
                  Column() {
                  Column({ space: 8 }) {
                    Row({ space: 8 }) {
                      Text('#' + a.attempt).fontSize(13).fontWeight(FontWeight.Bold)
                      Text(this.attemptVerdict(a))
                        .fontSize(11)
                        .fontColor(a.success ? '#2E7D32' : '#C62828')
                        .backgroundColor(a.success ? '#E8F8E8' : '#FFECEC')
                        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                        .borderRadius(6)
                        .maxLines(2)
                    }
                    .width('100%')
                    // Three disjoint phases of one model call, then the
                    // compiler. They add up to the run time, which the old
                    // layout implied but did not deliver.
                    Row({ space: 8 }) {
                      this.cell('Wait', a.ttftMs > 0 ? this.formatMs(a.ttftMs) : '—', 'until first token')
                      if (a.thinkMs > 0) {
                        this.cell('Think', this.formatMs(a.thinkMs), 'reasoning')
                      }
                      this.cell('Write', this.formatMs(this.writeMs(a)), 'streaming code')
                    }
                    .width('100%')
                    .alignItems(VerticalAlign.Top)
                    Row({ space: 8 }) {
                      this.cell('Compile', a.compileMs > 0 ? this.formatMs(a.compileMs) : '—', 'on device')
                      this.cell('Speed', this.speedLabel(a), 'output after the wait')
                    }
                    .width('100%')
                    .alignItems(VerticalAlign.Top)
                  }
                  .width('100%')
                  .padding(12)
                  }
                  .width('100%')
                  .backgroundColor('#FFFFFF')
                  .borderRadius(10)
                })

                if (this.program.runs > 1) {
                  Row({ space: 8 }) {
                    this.cell('Runs', this.program.runs + '', 'generation and refines')
                    this.cell('Spent', this.programSpentLabel(),
                      this.program.attempts + ' model calls in all')
                  }
                  .width('100%')

                  Row({ space: 8 }) {
                    this.cell('LLM wall', this.formatMs(this.program.llmMs), 'whole program')
                    this.cell('On device', this.formatMs(this.program.compileMs), 'whole program')
                  }
                  .width('100%')

                  Text('Earlier runs').fontSize(11).fontColor('#888888').width('100%')
                  ForEach(this.pastRuns(), (record: RunRecord) => {
                    this.pastRun(record, this.indexOfRun(record))
                  })
                }
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .layoutWeight(1)
          .align(Alignment.Top)
          // The bar is drawn over the content, and the rightmost tile in every
          // row ends up sliced by it.
          .scrollBar(BarState.Off)
          // Vertical only: a percentage width resolves against the parent's
          // whole box, so any horizontal padding here pushes every card past
          // the right edge.
          .padding({ top: 12, bottom: 12 })
          .margin({ left: 12, right: 12, top: 4 })
          .backgroundColor('#F5F7FA')
          .borderRadius(10)
        }

        // Pinned under whichever pane is open: reading the source is exactly
        // when you want to ask for a change, so the bar does not belong to the
        // preview alone.
        if (this.hasResult()) {
          Row({ space: 8 }) {
            TextInput({ placeholder: 'What to change?', text: this.refinePrompt })
              .onChange((value: string) => { this.refinePrompt = value })
              .layoutWeight(1)
              .height(44)
              .enabled(!this.generating)
            Button(this.generating ? 'Stop' : 'Update')
              .type(ButtonType.Normal)
              .width(92)
              .height(44)
              .enabled(this.generating || (this.refinePrompt.trim().length > 0 && this.canGenerate()))
              .onClick(() => {
                if (this.generating) {
                  this.stopGeneration()
                } else {
                  this.doRefine()
                }
              })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 12 })
          .backgroundColor('#F7F9FC')
        }
      }
      .width('100%')
      .height('100%')
    }
    .title('Generate')
    .titleMode(NavigationTitleMode.Mini)
  }
}
