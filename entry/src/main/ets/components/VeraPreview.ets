/**
 * Runs one compiled VERA-L program and renders its UI tree as native ArkUI.
 *
 * Extracted from RunnerPage so the same renderer serves both surfaces: the
 * full-screen run from the project library, and the inline preview on the
 * Generate page that follows a program as it is refined.
 *
 * Feeding it a different vbc2 restarts the program: a fresh VM, fresh init()
 * state, fresh view. That is what makes a refined program replace the previous
 * one in place.
 */

import { VirtualMachine, deserializeVbc2, RuntimeValue, VeraIntValue, VeraStringValue,
  VeraBooleanValue, encodeRuntimeValue, decodeRuntimeValue } from '../vera/VeraInterpreter'
import { UiHostEnvironment, HostEffect, VeraUiNode, decodeVeraUi } from '../vera/VeraUi'
import { runIntent, runRawIntent } from '../vera/VeraIntents'
import { addCalendarEvent, clearCalendarEvents } from '../vera/VeraCalendar'
import { LengthMetrics } from '@ohos.arkui.node'
import mediaquery from '@ohos.mediaquery'

import { catalogKinds } from '../vera/VeraUiCatalog'
import { iconPath, ICON_STROKE, ICON_VIEWPORT, ICON_ORIGIN } from '../vera/VeraIcons'
import { ResolvedTheme, resolveTheme, containerFill, toneFill, toneEdge, toneInk,
  textSize, textWeight, textInk, buttonFill, buttonInk, pathFill, densityPad,
  densityGap, spacerSize } from '../vera/VeraTheme'
import { store } from '../vera/ProjectStore'
import { consent } from '../vera/VeraConsentStore'
import { LiveNode, toLive, reconcile } from './VeraLiveTree'

/**
 * The rotation of every spinning shape on screen.
 *
 * Observed rather than @State: a nested @Builder is not re-invoked when plain
 * component state changes, but it is re-invoked when a @Trace field it reads is
 * mutated. Advancing this from a timer therefore redraws the shapes without the
 * VM, the program or its state being involved at all.
 */
@ObservedV2
class SpinAngle {
  @Trace angle: number = 0
}

/**
 * The look the running program asked for.
 *
 * Observed for the same reason SpinAngle is: the branches of renderNode are
 * built once and retained, so a plain field they read would never redraw them
 * if a program switched preset from its own state.
 *
 * One traced field, holding the whole table, replaced whole. That is the same
 * move reconcile makes on `children`: @Trace notices a field being *written*,
 * so swapping the object in is one notification for the one fact that matters
 * -- the theme changed -- rather than the fifty a traced field per value would
 * need to say it. The two strings beside it are plain: they exist only so an
 * unchanged frame can tell it has nothing to write.
 */
@ObservedV2
class LiveTheme {
  @Trace resolved: ResolvedTheme = resolveTheme('clean', '', false)
  preset: string = 'clean'
  primary: string = ''
  dark: boolean = false
}

/**
 * Whether a call is shown to the person before it runs.
 *
 * Off by request: a program that blinks the torch every two seconds cannot ask
 * about every flash, and a demo that stops on a dialog is not a demo. On, it
 * asks once per program and per call and remembers the answer.
 */
const ASK_BEFORE_CALLS: boolean = false

@Component
export struct VeraPreview {
  @Prop @Watch('onProgramChanged') vbc2: string = ''
  /**
   * Where to keep this program's state, as 'projectId/versionId'. Empty means
   * ephemeral: the Generate screen's preview is a scratch pad and must not
   * accumulate a record, while a program opened from the library is the real
   * thing and has to remember.
   */
  @Prop persistKey: string = ''
  // The live tree is mutated in place, so it is not @State: its own @Trace
  // fields are what drive the re-render. See VeraLiveTree.
  @State hasRoot: boolean = false
  private liveRoot: LiveNode | null = null
  /**
   * A frame counter for the logs, and nothing more -- build() does not read it,
   * so writing it triggers no re-render. It is not @State for that reason: it
   * used to key a ForEach that recreated the whole tree on every action, and
   * leaving it looking like state invited the assumption that the safety net is
   * still there. It is not; correctness now rests entirely on reconcile keeping
   * node identity.
   */
  private revision: number = 0
  @State error: string = ''
  private vm: VirtualMachine | null = null
  private host: UiHostEnvironment | null = null
  private currentState: RuntimeValue | null = null
  /**
   * Set when the screen goes away. An intent answers long after the tap, and
   * without this a late answer would re-enter a VM that is no longer there.
   */
  private disposed: boolean = false
  // Live tickers, keyed by the program's own id for each: handle, interval and
  // the moment of the last fire, so a handler can be told how long really passed.
  private timers: Map<string, number> = new Map<string, number>()
  private timerIntervals: Map<string, number> = new Map<string, number>()
  private timerLastFire: Map<string, number> = new Map<string, number>()
  private ticking: boolean = false
  private spin: SpinAngle = new SpinAngle()
  private theme: LiveTheme = new LiveTheme()
  /**
   * Whether the phone is in dark mode.
   *
   * The program is not asked and cannot say. A generated app holding a white
   * screen up at someone whose phone is dark is the app being wrong, and it is
   * not a judgement the program is in a position to make -- view() is a pure
   * function of state and has no way to see the phone. So the renderer follows
   * the system, and the preset supplies the dark palette that keeps the app
   * looking like itself.
   */
  private dark: boolean = false
  private darkListener: mediaquery.MediaQueryListener | null = null
  /**
   * How wide this renderer actually is, in vp.
   *
   * Measured from the box it is drawn in, not from the display. The two are not
   * the same and the difference showed: this component serves both the
   * full-screen run and the Generate page's inline preview, and sizing columns
   * by the display width put three metrics in a preview box wide enough for
   * two, so "1020 kg" wrapped onto a second line.
   *
   * @State because it arrives after the first frame: the first layout uses what
   * the program asked for, the measurement comes back, and the count is
   * corrected.
   */
  @State viewportWidth: number = 0
  /**
   * The call waiting for the person to allow it, and the calls queued behind it.
   *
   * A generated program may ask the phone to do things it cannot undo, and
   * neither the program nor the model knows which of them matter -- an intent
   * that changes the volume and one that sends a message look alike from here.
   * So anything that changes something is shown to the person first, and this
   * is the one thing on the screen the program did not draw: it cannot style
   * it, word it, or press its buttons.
   *
   * @State because the dialog is part of the frame; the queue is not, because
   * nothing draws it.
   */
  @State pending: HostEffect | null = null
  private heldEffects: HostEffect[] = []
  private spinTimer: number = -1
  private spinPeriod: number = 0

  // Kinds renderNode has a branch for. Checked against the catalogue on mount so
  // a component that compiles but cannot be drawn is reported here rather than
  // discovered as a blank space in someone's generated app.
  private static RENDERED: string[] = ['column', 'scroll', 'row', 'card', 'text',
    'button', 'cell', 'spacer', 'path', 'image', 'field', 'toggle', 'checkbox',
    'slider', 'select', 'divider', 'progress', 'ticker', 'grid', 'listitem', 'canvas',
    'apptheme', 'header', 'section', 'sectionheader', 'listgroup', 'banner',
    'emptystate', 'stat', 'metricgroup',
    'inttext', 'intstat', 'intfield', 'timefield', 'intlistitem', 'actionbar',
    'kvgroup', 'kvitem', 'icon', 'iconbutton', 'badge', 'clocktext',
    'timeline', 'timelineitem']

  aboutToAppear(): void {
    let missing: string[] = []
    for (let kind of catalogKinds()) {
      if (VeraPreview.RENDERED.indexOf(kind) < 0) { missing.push(kind) }
    }
    if (missing.length > 0) {
      console.error('VERA-RENDER catalogue kinds with no render branch: ' + missing.join(','))
      this.error = 'Renderer is missing: ' + missing.join(', ')
    }
    this.watchDarkMode()
    this.load()
  }

  onProgramChanged(): void {
    this.load()
  }

  /**
   * Follow the system's light/dark setting, and keep following it.
   *
   * A listener rather than a one-off read, so the app turns over while it is on
   * screen instead of only at launch. Wrapped because a media query is not
   * worth failing to draw over: if it is unavailable the app stays light, which
   * is what it has always been.
   */
  private watchDarkMode(): void {
    try {
      let listener = mediaquery.matchMediaSync('(dark-mode: true)')
      this.dark = listener.matches
      listener.on('change', (result: mediaquery.MediaQueryResult) => {
        if (this.disposed || result.matches === this.dark) { return }
        this.dark = result.matches
        // The palette is chosen in reconcileTheme, off the frame, so the way to
        // repaint is to ask for a frame.
        this.renderView()
      })
      this.darkListener = listener
    } catch (e) {
      this.dark = false
      console.info('VERA-RENDER dark mode unavailable: ' + (e as Error).message)
    }
  }

  private load(): void {
    this.stopAllTimers()
    this.vm = null
    this.currentState = null
    this.liveRoot = null
    this.hasRoot = false
    this.error = ''
    if (this.vbc2.length === 0) { return }
    try {
      this.host = new UiHostEnvironment()
      let module = deserializeVbc2(this.vbc2)
      this.vm = new VirtualMachine(module, this.host)
      this.currentState = this.restoreState()
      if (this.currentState === null) { this.currentState = this.vm!.execute('init') }
      this.renderView()
    } catch (e) {
      this.error = 'Init error: ' + (e as Error).message
    }
  }

  /**
   * Start, stop and re-time the program's tickers to match the frame just
   * produced.
   *
   * Identity comes from the id the program chose, not from a node position: a
   * conditional subtree shifts every later node, and a ticker that changed
   * identity every frame would be cancelled and restarted forever.
   *
   * A running ticker is left strictly alone unless its interval changed --
   * restarting it on each state change would reset its phase, so a one-second
   * ticker under a stream of taps would never reach a full second.
   */
  private reconcileTimers(root: VeraUiNode | null): void {
    let wanted = new Map<string, number>()
    let actions = new Map<string, string>()
    if (root !== null) { this.collectTickers(root!, wanted, actions) }

    let live = Array.from(this.timers.keys())
    for (let id of live) {
      let want = wanted.get(id)
      let current = this.timerIntervals.get(id)
      if (want === undefined || want !== current) { this.stopTimer(id) }
    }
    let ids = Array.from(wanted.keys())
    for (let id of ids) {
      if (this.timers.has(id)) { continue }
      let interval = wanted.get(id) as number
      let action = actions.get(id) as string
      this.startTimer(id, interval, action)
    }
  }

  /**
   * Keep the shared rotation running for as long as any shape asks to spin.
   *
   * The angle is advanced here rather than by the program: rotation is
   * decoration, and routing it through the VM would make every frame a state
   * transition and a saved snapshot.
   */
  private reconcileSpin(root: VeraUiNode | null): void {
    let period = root !== null ? this.findSpinPeriod(root!) : 0
    if (period === this.spinPeriod) { return }
    this.spinPeriod = period
    if (this.spinTimer >= 0) { clearInterval(this.spinTimer); this.spinTimer = -1 }
    if (period <= 0) { this.spin.angle = 0; return }
    let step = 360 * 50 / period
    this.spinTimer = setInterval(() => {
      this.spin.angle = (this.spin.angle + step) % 360
    }, 50)
  }

  /** First spinning shape wins; one shared angle is enough. */
  private findSpinPeriod(node: VeraUiNode): number {
    if (node.kind === 'path' && node.spinPeriodMs > 0) { return node.spinPeriodMs }
    for (let child of node.children) {
      let found = this.findSpinPeriod(child)
      if (found > 0) { return found }
    }
    return 0
  }

  private collectTickers(node: VeraUiNode, wanted: Map<string, number>,
      actions: Map<string, string>): void {
    if (node.kind === 'ticker' && node.checked && node.minimum > 0 &&
        node.tickerId.length > 0 && node.action.length > 0) {
      wanted.set(node.tickerId, node.minimum)
      actions.set(node.tickerId, node.action)
    }
    for (let child of node.children) { this.collectTickers(child, wanted, actions) }
  }

  private startTimer(id: string, intervalMs: number, action: string): void {
    let safe = intervalMs < 16 ? 16 : intervalMs
    this.timerLastFire.set(id, Date.now())
    let handle = setInterval(() => {
      // A tick that arrives while the previous one is still running would
      // re-enter the VM with a half-applied state.
      if (this.ticking) { return }
      let last = this.timerLastFire.get(id)
      let now = Date.now()
      let elapsed = last !== undefined ? now - (last as number) : safe
      this.timerLastFire.set(id, now)
      this.ticking = true
      this.dispatch(action, new VeraIntValue(Math.round(elapsed)))
      this.ticking = false
    }, safe)
    this.timers.set(id, handle)
    this.timerIntervals.set(id, intervalMs)
  }

  private stopTimer(id: string): void {
    let handle = this.timers.get(id)
    if (handle !== undefined) { clearInterval(handle as number) }
    this.timers.delete(id)
    this.timerIntervals.delete(id)
    this.timerLastFire.delete(id)
  }

  private stopAllTimers(): void {
    for (let id of Array.from(this.timers.keys())) { this.stopTimer(id) }
    if (this.spinTimer >= 0) { clearInterval(this.spinTimer); this.spinTimer = -1 }
    this.spinPeriod = 0
  }

  aboutToDisappear(): void {
    // Without this the tickers -- and the VM they drive -- outlive the screen.
    this.disposed = true
    this.stopAllTimers()
    // The same applies to the dark-mode listener: it holds this component, and
    // its callback re-enters the VM.
    if (this.darkListener !== null) {
      try {
        this.darkListener!.off('change')
      } catch (e) {
        console.info('VERA-RENDER dark listener off failed: ' + (e as Error).message)
      }
      this.darkListener = null
    }
  }

  private stateKeys(): string[] {
    let slash = this.persistKey.indexOf('/')
    if (this.persistKey.length === 0 || slash <= 0) { return [] }
    return [this.persistKey.substring(0, slash), this.persistKey.substring(slash + 1)]
  }

  /** The bytecode itself is the stamp: a refined program gets a different one. */
  private stamp(): string {
    return this.vbc2.length.toString() + ':' + this.vbc2.substring(0, 64)
  }

  private restoreState(): RuntimeValue | null {
    let keys = this.stateKeys()
    if (keys.length === 0) { return null }
    let encoded = store.loadState(keys[0], keys[1], this.stamp())
    if (encoded.length === 0) { return null }
    try {
      return decodeRuntimeValue(JSON.parse(encoded) as Object)
    } catch (e) {
      console.error('VERA-STATE restore failed, starting clean: ' + (e as Error).message)
      return null
    }
  }

  private persistState(): void {
    let keys = this.stateKeys()
    if (keys.length === 0 || this.currentState === null) { return }
    try {
      store.saveState(keys[0], keys[1], this.stamp(),
        JSON.stringify(encodeRuntimeValue(this.currentState!)))
    } catch (e) {
      // A program holding something unsaveable should still run; it just will
      // not remember. Saying so beats a silent half-working save.
      console.error('VERA-STATE save failed: ' + (e as Error).message)
    }
  }

  private renderView(): void {
    if (this.vm === null || this.currentState === null) { return }
    try {
      // view is re-run on every change, so an intent call from there would
      // start navigation on every repaint. The host refuses one while this is
      // false; only dispatch lifts it, and only around the handler itself.
      if (this.host !== null) { this.host!.effectsAllowed = false }
      let viewTree = this.vm!.execute('view', [this.currentState!])
      let nodes = decodeVeraUi(viewTree)
      let root = nodes.length > 0 ? nodes[0] : null
      console.info('VERA-VIEW rev=' + (this.revision + 1).toString() +
        ' root=' + (root !== null ? root!.kind : 'null') +
        ' children=' + (root !== null ? root!.children.length.toString() : '0'))
      this.reconcileTheme(root)
      if (root === null) {
        this.liveRoot = null
        this.hasRoot = false
      } else if (this.liveRoot === null) {
        this.liveRoot = toLive(root!)
        this.hasRoot = true
      } else {
        reconcile(this.liveRoot!, root!)
      }
      this.revision += 1
      this.reconcileTimers(root)
      this.reconcileSpin(root)
    } catch (e) {
      this.error = 'View error: ' + (e as Error).message
    }
  }

  /**
   * Take the look from the root of the frame, if the program named one.
   *
   * A program that does not use ui.AppTheme -- which is every program written
   * before it existed, and both benchmark artifacts -- resolves to 'clean',
   * whose values are the ones the renderer used when they were hardcoded. So
   * those programs draw exactly what they always drew.
   */
  private reconcileTheme(root: VeraUiNode | null): void {
    let preset = 'clean'
    let primary = ''
    if (root !== null && root!.kind === 'apptheme') {
      preset = root!.style
      primary = root!.value
    }
    if (this.theme.preset === preset && this.theme.primary === primary &&
        this.theme.dark === this.dark) { return }
    this.theme.preset = preset
    this.theme.primary = primary
    this.theme.dark = this.dark
    // Written last, because writing it is what triggers the redraw.
    this.theme.resolved = resolveTheme(preset, primary, this.dark)
  }

  /**
   * The theme, for a render branch.
   *
   * Every branch reaches the table through here, so every branch reads the
   * traced field and is therefore rebuilt when the table is replaced. A branch
   * that cached it instead would stay at the look it was first built with.
   */
  private t(): ResolvedTheme {
    return this.theme.resolved
  }

  private handleAction(action: string, value: number): void {
    this.dispatch(action, new VeraIntValue(value))
  }

  private handleStringAction(action: string, value: string): void {
    this.dispatch(action, new VeraStringValue(value))
  }

  private handleBoolAction(action: string, value: boolean): void {
    this.dispatch(action, new VeraBooleanValue(value))
  }

  /**
   * The single way a person's input reaches a program. Until now the payload was
   * always an int the program had chosen itself, so nothing typed or toggled
   * could get in; the value is now whatever the component produces.
   */
  private dispatch(action: string, payload: RuntimeValue, persist: boolean = true): void {
    console.info('VERA-CLICK action=' + action + ' rev=' + this.revision.toString())
    if (this.vm === null || this.currentState === null) { return }
    let t0 = Date.now()
    try {
      if (this.host !== null) { this.host!.effectsAllowed = true }
      this.currentState = this.vm!.execute(action, [this.currentState!, payload])
      if (this.host !== null) { this.host!.effectsAllowed = false }
      console.info('VERA-ACTION ' + action + ' steps=' + this.vm!.stepsExecuted().toString() +
        ' ms=' + (Date.now() - t0).toString())
      this.renderView()
      if (persist) { this.persistState() }
      this.drainEffects()
    } catch (e) {
      if (this.host !== null) {
        this.host!.effectsAllowed = false
        // A handler that trapped half-way may have queued an intent it would
        // never have reached. Asking the platform for it would act on a state
        // the program never committed to.
        this.host!.pendingEffects = []
      }
      console.error('VERA-ACTION ' + action + ' TRAP steps=' + this.vm!.stepsExecuted().toString() +
        ' ms=' + (Date.now() - t0).toString() + ' err=' + (e as Error).message)
      this.error = 'Action error: ' + (e as Error).message
      // A ticker whose handler traps would otherwise trap again every interval.
      this.stopAllTimers()
    }
  }

  /**
   * Runs the intents the handler asked for, and brings each answer back the way
   * every other event arrives -- as a dispatch to a named handler.
   *
   * The queue is taken and cleared first: delivering an answer runs a handler,
   * and that handler may queue intents of its own.
   *
   * A late answer to a screen that has gone is dropped rather than pushed into
   * a VM that is no longer running.
   */
  private drainEffects(): void {
    if (this.host === null) { return }
    let effects: HostEffect[] = this.host!.pendingEffects
    if (effects.length === 0) { return }
    this.host!.pendingEffects = []
    for (let effect of effects) { this.heldEffects.push(effect) }
    this.runQueued()
  }

  /**
   * Works through the queue until it is empty or something needs asking.
   *
   * One dialog at a time, and everything behind it waits: two dialogs at once
   * is a person clicking through whichever is on top, which is the failure this
   * whole mechanism exists to prevent.
   */
  private runQueued(): void {
    while (this.heldEffects.length > 0) {
      if (this.pending !== null) { return }
      let effect = this.heldEffects.shift() as HostEffect
      console.info('VERA-EFFECT id=' + effect.id.toString() + ' ' + effect.kind + '.' + effect.fn +
        ' -> ' + effect.resultHandler)
      if (this.needsConsent(effect)) {
        console.info('VERA-CONSENT asking for ' + this.consentTitle(effect))
        this.pending = effect
        return
      }
      this.runEffect(effect)
    }
  }

  /**
   * Whether this call is shown to the person before it runs.
   *
   * Reading something, opening a page or launching an app is not worth
   * interrupting for -- the person asked for the app and can see what it did.
   * Anything that changes something is, and an intent the catalogue never
   * described always is: nobody has established what it does, so nobody can say
   * it is safe. The calendar goes through Calendar Kit rather than an intent
   * and writes to a calendar the person can inspect and the program can wipe,
   * so it stays as it was.
   */
  private needsConsent(effect: HostEffect): boolean {
    // Asking is off. Turn ASK_BEFORE_CALLS back on and every state-changing
    // call, and every intent.call, is shown to the person again -- the sheet,
    // the queue and the remembered grants are all still here and still work.
    //
    // What is lost while it is off is the only thing standing between a
    // generated program and an intent nobody has checked: the phone accepts
    // Pay and SendTextMessage as readily as OpenFlashlight, and the person
    // sees neither. The log keeps the record -- VERA-INTENT and
    // VERA-INTENT-RAW carry the target and the payload of every call.
    if (!ASK_BEFORE_CALLS) { return false }
    if (effect.kind !== 'intent') { return false }
    // Already allowed, for this program and this call. The grant died with the
    // previous version of the program: stamp() is the bytecode.
    if (consent.has(this.stamp(), this.consentKey(effect))) { return false }
    if (effect.spec === null) { return true }
    let risk = effect.spec!.risk
    return risk === 'act' || risk === 'critical'
  }

  /**
   * What a grant is about: the address for a raw call, the row's name for a
   * catalogue row.
   *
   * The row's name rather than its address, because two rows can share an
   * address and mean opposite things -- setBluetooth and readBluetooth are both
   * SetSettingSwitch's neighbours in the settings app -- and allowing a reading
   * must not quietly allow a change.
   */
  private consentKey(effect: HostEffect): string {
    return effect.spec === null ? effect.rawTarget : 'row:' + effect.spec!.name
  }

  /** What the dialog says this call is, in the person's words where there are any. */
  private consentTitle(effect: HostEffect): string {
    if (effect.spec === null) { return 'Run ' + effect.rawTarget.split('/')[3] }
    let spec = effect.spec!
    return spec.titleForUser.length > 0 ? spec.titleForUser : spec.summary
  }

  /** The app the call goes to, by bundle name -- the one thing that is never in doubt. */
  private consentTarget(effect: HostEffect): string {
    if (effect.spec === null) { return effect.rawTarget }
    return effect.spec!.bundle + ' / ' + effect.spec!.intentName
  }

  /**
   * Every value that will be sent, after translation, one per line.
   *
   * After translation because that is what the phone will receive: showing the
   * program's own words would be showing something other than what happens.
   */
  private consentValues(effect: HostEffect): string {
    if (effect.spec === null) {
      let lines: string[] = []
      effect.values.forEach((value: string, key: string) => { lines.push(key + ': ' + value) })
      return lines.length > 0 ? lines.join('\n') : '(no parameters)'
    }
    let lines: string[] = []
    let spec = effect.spec!
    spec.fixed.forEach((value: string, key: string) => { lines.push(key + ': ' + value) })
    for (let p of spec.params) {
      let raw = effect.values.get(p.name)
      let text = raw === undefined ? '' : raw as string
      if (text.length === 0) { text = p.defaultValue }
      if (text.length === 0) { continue }
      let mapped = p.valueMap.get(text)
      lines.push(p.platformName + ': ' + (mapped !== undefined ? mapped as string : text))
    }
    return lines.length > 0 ? lines.join('\n') : '(no parameters)'
  }

  /** The person allowed it: run it, then carry on with whatever was behind it. */
  private allowPending(): void {
    let effect = this.pending
    this.pending = null
    if (effect !== null) {
      console.info('VERA-CONSENT allowed ' + this.consentTarget(effect!))
      // Remembered, so the same program asking the same thing again is not a
      // question the person has to answer twice.
      consent.remember(this.stamp(), this.consentKey(effect!))
      this.runEffect(effect!)
    }
    this.runQueued()
  }

  /**
   * The person refused: the program is told so through its own handler.
   *
   * Told, rather than left waiting -- a program that asked to send something
   * and hears nothing back will show the person a screen that is quietly wrong.
   */
  private refusePending(): void {
    let effect = this.pending
    this.pending = null
    if (effect !== null) {
      console.info('VERA-CONSENT refused ' + this.consentTarget(effect!))
      this.dispatch(effect!.resultHandler, new VeraStringValue('declined by the person'))
    }
    this.runQueued()
  }

  /** One effect, whichever host it belongs to, answered through its handler. */
  private runEffect(effect: HostEffect): void {
    let answer: Promise<string>
    if (effect.kind === 'calendar' && effect.fn === 'clearEvents') {
      answer = clearCalendarEvents()
    } else if (effect.kind === 'calendar') {
      answer = addCalendarEvent(
        this.effectText(effect, 'title'),
        this.effectInt(effect, 'hour', 9),
        this.effectInt(effect, 'minute', 0),
        this.effectInt(effect, 'durationMinutes', 15),
        this.effectInt(effect, 'remindBefore', 0),
        this.effectText(effect, 'repeat'))
    } else if (effect.spec === null) {
      answer = runRawIntent(effect.rawTarget, effect.values, effect.rawMode)
    } else {
      answer = runIntent(effect.spec!, effect.values)
    }
    answer.then((text: string) => {
      if (this.disposed) { return }
      this.dispatch(effect.resultHandler, new VeraStringValue(text))
    }).catch((e: Error) => {
      if (this.disposed) { return }
      this.dispatch(effect.resultHandler, new VeraStringValue('error: ' + e.message))
    })
  }

  private effectText(effect: HostEffect, field: string): string {
    let v = effect.values.get(field)
    return v !== undefined ? v as string : ''
  }

  private effectInt(effect: HostEffect, field: string, fallback: number): number {
    let v = effect.values.get(field)
    if (v === undefined) { return fallback }
    let n = Number.parseInt(v as string, 10)
    return Number.isNaN(n) ? fallback : n
  }

  build() {
    Stack() {
      this.programFrame()
      // Drawn over the program, by the renderer, from the row the host is about
      // to send. The program supplies no text here and cannot dismiss it.
      if (this.pending !== null) {
        this.consentSheet(this.pending!)
      }
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Bottom)
  }

  @Builder
  consentSheet(effect: HostEffect) {
    Column() {
      Column() {
        Text(this.consentTitle(effect))
          .fontSize(19).fontWeight(FontWeight.Bold)
          .fontColor(this.t().ink)
          .width('100%')
        Text(this.consentTarget(effect))
          .fontSize(12).fontFamily('monospace')
          .fontColor(this.t().inkMuted)
          .width('100%')
          .margin({ top: 4 })
        Text(this.consentValues(effect))
          .fontSize(13).fontFamily('monospace')
          .fontColor(this.t().inkStrong)
          .width('100%')
          .padding(10)
          .margin({ top: 12 })
          .backgroundColor(this.t().surface)
          .borderRadius(8)
        // Said plainly, because it is the part a person cannot check for
        // themselves: this call was written by a program, not by them.
        Text((effect.spec === null
          ? 'This app wrote this call itself. Nothing has checked what it does.'
          : 'This app is asking to change something on your phone.') +
          ' Allow it and this app stops asking for this one.')
          .fontSize(12)
          .fontColor(this.t().inkSoft)
          .width('100%')
          .margin({ top: 10 })
        Row() {
          Button('Not now')
            .fontSize(15)
            .layoutWeight(1)
            .backgroundColor(this.t().surface)
            .fontColor(this.t().ink)
            .onClick(() => { this.refusePending() })
          Button('Allow')
            .fontSize(15)
            .layoutWeight(1)
            .margin({ left: 10 })
            .backgroundColor(this.t().primary)
            .fontColor(this.t().onPrimary)
            .onClick(() => { this.allowPending() })
        }
        .width('100%')
        .margin({ top: 16 })
      }
      .width('100%')
      .padding(18)
      .backgroundColor(this.t().background)
      .borderRadius({ topLeft: 16, topRight: 16 })
    }
    .width('100%')
  }

  @Builder
  programFrame() {
    Column() {
      if (this.error.length > 0) {
        Text(this.error)
          .fontSize(14)
          .fontColor('#CC0000')
          .padding(16)
          .width('100%')
          .backgroundColor('#FFECEC')
      }
      if (this.hasRoot && this.liveRoot !== null) {
        Scroll() {
          Column() {
            this.renderNode(this.liveRoot!, 'root')
          }.width('100%')
        }
        .width('100%')
        .layoutWeight(1)
        // Scroll centres its content by default, which leaves a generated
        // program floating in the middle of the box instead of starting where
        // a real app would.
        .align(Alignment.Top)
      }
    }
    .width('100%')
    .height('100%')
    // Writing this back is what makes the column counts adapt. Guarded by a
    // whole vp: the write triggers a re-layout, and a re-layout that reports a
    // width a fraction different would write again, and so on.
    .onAreaChange((_old: Area, now: Area) => {
      let w = now.width as number
      if (Math.abs(w - this.viewportWidth) >= 1) { this.viewportWidth = w }
    })
    // The page behind the program, so a theme whose background is not white
    // reaches past the tree to the edges of the screen. Reading the theme here
    // also subscribes build() itself, so a program that changes its own preset
    // repaints the page and not only its contents.
    .backgroundColor(this.t().background)
  }

  /**
   * Whether this row shares its width by weight instead of wrapping. Cells and
   * cards are laid out proportionally -- a tic-tac-toe row, a pair of stat
   * cards -- and wrapping would collapse them.
   */
  private rowDistributes(node: LiveNode): boolean {
    for (let child of node.children) {
      if (child.kind === 'cell' || child.kind === 'card') { return true }
    }
    return false
  }

  @Builder
  renderChildren(node: LiveNode) {
    // Keyed by position and kind. Position, because reconcile keeps a node's
    // identity across frames, so a retained component is still reading a node
    // that is being updated and only the changed fields re-render.
    //
    // Kind as well, because renderNode picks its branch with an if/else chain
    // when the component is built, and a retained component cannot switch
    // branches later. A position that turns from a text into a listitem -- an
    // empty-state line replaced by the first real row -- would otherwise stay a
    // text forever. Including the kind makes ArkUI rebuild exactly then, and
    // never merely because some text changed.
    ForEach(node.children, (child: LiveNode) => {
      this.renderNode(child, node.kind)
    }, (child: LiveNode, index: number) => index.toString() + ':' + child.kind)
  }

  /**
   * Values the theme does not own.
   *
   * The line is: anything that makes one preset look like a different app --
   * colour, type size, radius, padding -- comes from VeraTheme. Structural
   * dimensions that are about fitting on a phone rather than about character --
   * how tall a canvas band is, how far a scroll may grow, how big an image box
   * is -- stay here as literals, because varying them per preset would change
   * what fits on the screen rather than how it looks.
   */
  private gridPad(style: string): number {
    let t = this.t()
    if (style === 'compact') { return t.padGrid - 2 }
    if (style === 'spacious') { return t.padGrid + 2 }
    return t.padGrid
  }

  /** What a Section's role fills its box with; transparent for plain content. */
  private sectionFill(style: string): string {
    let t = this.t()
    if (style === 'hero') { return t.primaryFill }
    if (style === 'summary') { return t.surface }
    if (style === 'warning') { return t.warningFill }
    return '#00000000'
  }

  private sectionFills(style: string): boolean {
    return style === 'hero' || style === 'summary' || style === 'warning'
  }

  /**
   * A role that fills its box insets its content from the fill. One that does
   * not still holds its content off the edge of the screen -- which it did not
   * at first: a plain section ran its heading and its controls flush into the
   * left margin while the Header above sat properly indented, and a
   * SectionHeader's count ran off the right edge and was cut in half.
   */
  private sectionPadX(style: string): number {
    return this.sectionFills(style) ? this.t().padCard : this.t().padBase
  }

  /** Vertical padding belongs to the fill, so an unfilled section has none. */
  private sectionPadY(style: string): number {
    return this.sectionFills(style) ? this.t().padCard : 0
  }

  /**
   * A number, as the program asked for it to be shown.
   *
   * This is the formatting the language cannot do. VERA-L has no padStart and
   * no number formatting of any kind, so a program wanting "07" had to carry a
   * pad2 function, and one wanting "$1,204" had to build the string by hand.
   * The node carries the number and the three things worth saying about it.
   */
  private formatInt(node: LiveNode): string {
    let n = node.intValue
    let negative = n < 0
    let digits = (negative ? -n : n).toString()
    // minimumDigits pads the digits, not the sign: -7 to two digits is "-07".
    while (digits.length < node.minimumDigits) { digits = '0' + digits }
    return node.prefix + (negative ? '-' : '') + digits + node.suffix
  }

  /**
   * The same minutes as a Date, because the picker wants one.
   *
   * The day part is never read back -- only hour and minute return through
   * onAccept -- so today's date is as good as any.
   */
  private minutesToDate(total: number): Date {
    let m = total < 0 ? 0 : total % 1440
    let d = new Date()
    d.setHours(Math.floor(m / 60), m % 60, 0, 0)
    return d
  }

  /**
   * The typeface, or undefined to leave the system's alone.
   *
   * Passed on every piece of text rather than only on the headings: a screen
   * where the title is serif and the list rows are not does not read as a
   * choice, it reads as a mistake. undefined rather than a default family name
   * so the five presets that do not ask for a typeface get exactly the
   * rendering they had before there was such a thing as asking.
   */
  private textFamily(): string | undefined {
    let f = this.t().fontFamily
    return f.length > 0 ? f : undefined
  }

  /** Minutes since midnight as HH:MM, which is what TimeField holds. */
  private formatMinutes(total: number): string {
    let m = total < 0 ? 0 : total % 1440
    let h = Math.floor(m / 60)
    let mm = m % 60
    return (h < 10 ? '0' : '') + h.toString() + ':' + (mm < 10 ? '0' : '') + mm.toString()
  }

  /**
   * How many columns actually fit, rather than how many were asked for.
   *
   * The requested count is a maximum. Four metrics side by side is a fine
   * layout on a tablet and four unreadable slivers on this phone, and the
   * program cannot know which it is running on -- it is a pure function of
   * state and has no way to ask. So the renderer decides, from the width it can
   * see and the narrowest a cell may usefully be.
   */
  private fittingColumns(requested: number, minimumCellWidth: number): number {
    let want = requested < 1 ? 1 : requested
    if (this.viewportWidth <= 0) { return want }
    let fits = Math.floor(this.viewportWidth / minimumCellWidth)
    if (fits < 1) { fits = 1 }
    return fits < want ? fits : want
  }

  /** Two to four; anything else is a number the model should not have picked. */
  private metricColumns(node: LiveNode): number {
    if (node.columns < 2) { return 2 }
    if (node.columns > 4) { return 4 }
    return node.columns
  }

  private sectionRadius(style: string): number {
    return this.sectionFills(style) ? this.t().radiusCard : 0
  }

  /**
   * One icon, at a size, in a colour.
   *
   * The paths are written in the same 0..100 box as ui.Path, so drawing one at
   * sixteen points is a scale of 0.16 about the centre of a box that size. They
   * are stroked rather than filled -- see VeraIcons for why -- with round caps,
   * which is what keeps a two-segment tick from ending in two blunt chisels.
   */
  @Builder
  drawIcon(name: string, size: number, colour: string) {
    // The viewport is the whole trick, and its unit is half the trick.
    //
    // ArkUI's Path has no viewBox of its own: its commands are drawn in a fixed
    // unit and its width/height only set the box they are clipped to, so
    // .scale() on the Path fights the layout rather than sizing the drawing.
    // Three rounds of that put a speck in the corner of every button.
    // Shape.viewPort is the mechanism that does exist -- it maps the 0..100 box
    // the icons are drawn in onto whatever size this component is given, and it
    // carries the stroke along with the geometry, so the weight stays even from
    // twelve points to thirty-eight.
    //
    // The unit of that box is the pixel. Stated as bare numbers the viewPort
    // and the stroke are read as vp while the commands are read as px, the
    // three disagree by the display density, and the glyph lands at a quarter
    // of its box -- measured at 0.25 where 0.78 was wanted. Hence '100px' and
    // '8px'. This was settled by drawing the candidates on the phone and
    // measuring them, after three rounds of reasoning about it got it wrong.
    //
    // Every icon is normalised to span 78 of those 100 units, so a glyph drawn
    // at `size` reads at about the cap height of text at the same size. That
    // normalisation lives in the path data, done once; nothing is scaled here.
    Shape() {
      Path({ commands: iconPath(name) })
        .fill(Color.Transparent)
        .stroke(colour)
        .strokeWidth(ICON_STROKE)
        .strokeLineCap(LineCapStyle.Round)
        .strokeLineJoin(LineJoinStyle.Round)
    }
    .viewPort({ x: ICON_ORIGIN, y: ICON_ORIGIN, width: ICON_VIEWPORT, height: ICON_VIEWPORT })
    .width(size)
    .height(size)
  }

  @Builder
  renderNode(node: LiveNode, parentKind: string) {
    if (node.kind === 'apptheme') {
      // The look itself is picked up in reconcileTheme, off the root of the
      // frame. All this branch does is paint the page and get out of the way.
      Column() {
        this.renderChildren(node)
      }
      .width('100%')
      .backgroundColor(this.t().background)
    } else if (node.kind === 'scroll') {
      // Rendered as a plain Column until now, so a program asking for a
      // scrolling region got one that could not scroll and simply grew.
      Scroll() {
        Column() {
          this.renderChildren(node)
        }
        .width('100%')
        .alignItems(node.style === 'center' ? HorizontalAlign.Center :
          node.style === 'end' ? HorizontalAlign.End : HorizontalAlign.Start)
        .padding(densityPad(this.t(), node.style))
      }
      .width('100%')
      .constraintSize({ maxHeight: 420 })
      .align(Alignment.Top)
      .scrollBar(BarState.Auto)
      .backgroundColor(containerFill(this.t(), node.style))
    } else if (node.kind === 'column') {
      Column() {
        this.renderChildren(node)
      }
      .width('100%')
      .alignItems(node.style === 'center' ? HorizontalAlign.Center :
        node.style === 'end' ? HorizontalAlign.End : HorizontalAlign.Start)
      .padding(densityPad(this.t(), node.style))
      .backgroundColor(containerFill(this.t(), node.style))
    } else if (node.kind === 'row' && this.rowDistributes(node)) {
      // A row of cells or cards is a grid row: the children share the width by
      // weight, and a wrapping Flex does not distribute weight, which collapses
      // a board to nothing.
      Row({ space: densityGap(this.t(), node.style) }) {
        this.renderChildren(node)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .justifyContent(node.style === 'split' ? FlexAlign.SpaceBetween :
        node.style === 'center' ? FlexAlign.Center :
          node.style === 'end' ? FlexAlign.End : FlexAlign.Start)
      .padding(this.t().padRow)
      .backgroundColor(containerFill(this.t(), node.style))
    } else if (node.kind === 'row') {
      // Everything else wraps rather than pushing children past the right edge,
      // where they cannot be tapped. Half the probes lost a control that way --
      // a "Mark taken" button, the true/false of a switch, a preset that read
      // "Call mo".
      Flex({
        wrap: FlexWrap.Wrap,
        justifyContent: node.style === 'split' ? FlexAlign.SpaceBetween :
          node.style === 'center' ? FlexAlign.Center :
            node.style === 'end' ? FlexAlign.End : FlexAlign.Start,
        alignItems: ItemAlign.Center,
        space: { main: LengthMetrics.vp(densityGap(this.t(), node.style)),
                 cross: LengthMetrics.vp(this.t().padRow) }
      }) {
        this.renderChildren(node)
      }
      .width('100%')
      .padding(node.style === 'joined' ? 0 : this.t().padRow)
      .backgroundColor(containerFill(this.t(), node.style))
    } else if (node.kind === 'card') {
      Column() {
        this.renderChildren(node)
      }
      .width(parentKind === 'row' ? undefined : '100%')
      .layoutWeight(parentKind === 'row' ? 1 : 0)
      .alignItems(HorizontalAlign.Start)
      .padding(this.t().padCard)
      .backgroundColor(toneFill(this.t(), node.style, this.t().surface))
      .border({ width: this.t().borderWidth, color: this.t().line })
      .borderRadius(this.t().radiusCard)
    } else if (node.kind === 'text') {
      Text(node.text)
        .fontSize(textSize(this.t(), node.style))
        .fontFamily(this.textFamily())
        .fontWeight(textWeight(this.t(), node.style))
        .fontColor(textInk(this.t(), node.style))
        .letterSpacing(node.style === 'eyebrow' ? this.t().eyebrowSpacing : 0)
        // In a row the text takes only what it needs and shrinks rather than
        // shoving its siblings out of the window; the row wraps if it must.
        // Making it greedy instead (an earlier attempt) merely moved the problem
        // to rows that also hold a weighted card.
        .width(parentKind === 'row' ? undefined : '100%')
        .constraintSize({ maxWidth: '100%' })
        .flexShrink(1)
        .padding({ top: 2, bottom: 2 })
    } else if (node.kind === 'header') {
      // The app's own title block. A generated program used to open with a bare
      // ui.Text and nothing to distinguish it from the first line of content.
      Column({ space: this.t().gapTight }) {
        if (node.label.length > 0) {
          Text(node.label)
            .fontSize(this.t().sizeEyebrow)
            .fontFamily(this.textFamily())
            .fontWeight(this.t().weightHeading)
            .fontColor(this.t().inkMuted)
            .letterSpacing(this.t().eyebrowSpacing)
            .width('100%')
            .textAlign(node.style === 'center' ? TextAlign.Center : TextAlign.Start)
        }
        Row({ space: this.t().gapBase }) {
          if (node.icon.length > 0) {
            this.drawIcon(node.icon, this.t().sizeTitle, this.t().primaryInk)
          }
          Text(node.text)
            .fontSize(this.t().sizeDisplay)
            .fontFamily(this.textFamily())
            .fontWeight(this.t().weightDisplay)
            .fontColor(this.t().ink)
            .layoutWeight(1)
            .textAlign(node.style === 'center' ? TextAlign.Center : TextAlign.Start)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        if (node.value.length > 0) {
          Text(node.value)
            .fontSize(this.t().sizeBody)
            .fontFamily(this.textFamily())
            .fontColor(this.t().inkSoft)
            .width('100%')
            .textAlign(node.style === 'center' ? TextAlign.Center : TextAlign.Start)
        }
      }
      .width('100%')
      .alignItems(node.style === 'center' ? HorizontalAlign.Center : HorizontalAlign.Start)
      .padding({ left: this.t().padBase, right: this.t().padBase,
                 top: this.t().padLoose, bottom: this.t().padBase })
    } else if (node.kind === 'section') {
      Column({ space: this.t().gapTight }) {
        if (node.text.length > 0) {
          Text(node.text)
            .fontSize(this.t().sizeHeading)
            .fontFamily(this.textFamily())
            .fontWeight(this.t().weightHeading)
            .fontColor(node.style === 'warning' ? this.t().warningInk :
              node.style === 'supporting' ? this.t().inkSoft : this.t().ink)
            .width('100%')
        }
        if (node.label.length > 0) {
          Text(node.label)
            .fontSize(this.t().sizeCaption)
            .fontFamily(this.textFamily())
            .fontColor(this.t().inkMuted)
            .width('100%')
        }
        this.renderChildren(node)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({
        left: this.sectionPadX(node.style), right: this.sectionPadX(node.style),
        top: this.sectionPadY(node.style), bottom: this.sectionPadY(node.style)
      })
      .backgroundColor(this.sectionFill(node.style))
      .borderRadius(this.sectionRadius(node.style))
      // The gap between one section and the next comes from the theme, so a
      // program does not have to punctuate itself with ui.Spacer.
      .margin({ top: this.t().gapTight, bottom: this.t().gapSection })
    } else if (node.kind === 'sectionheader') {
      Column({ space: 2 }) {
        Row() {
          Text(node.text)
            .fontSize(this.t().sizeHeading)
            .fontFamily(this.textFamily())
            .fontWeight(this.t().weightHeading)
            .fontColor(node.style === 'accent' ? this.t().primary :
              node.style === 'muted' ? this.t().inkMuted : this.t().ink)
            .layoutWeight(1)
          if (node.value.length > 0) {
            Text(node.value)
              .fontSize(this.t().sizeCaption)
              .fontFamily(this.textFamily())
              .fontColor(this.t().inkMuted)
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        if (node.label.length > 0) {
          Text(node.label)
            .fontSize(this.t().sizeCaption)
            .fontFamily(this.textFamily())
            .fontColor(this.t().inkMuted)
            .width('100%')
        }
      }
      .width('100%')
      // Indents itself only when nothing else is doing it: inside a Section the
      // section already owns the margin, and doing it twice reads as a stray
      // indent rather than as alignment.
      .padding({
        left: parentKind === 'section' ? 0 : this.t().padBase,
        right: parentKind === 'section' ? 0 : this.t().padBase,
        top: this.t().gapBase, bottom: this.t().gapTight
      })
    } else if (node.kind === 'listgroup') {
      // One frame around the whole collection, with the separators drawn here.
      // Before this, a list was a Card per row: every row had its own border,
      // its own radius and its own margin, and a list of eight read as eight
      // unrelated things.
      Column() {
        if (node.text.length > 0) {
          Text(node.text)
            .fontSize(this.t().sizeCaption)
            .fontFamily(this.textFamily())
            .fontWeight(this.t().weightHeading)
            .fontColor(this.t().inkMuted)
            .width('100%')
            .padding({ left: this.t().padListX, right: this.t().padListX,
                       top: this.t().gapBase, bottom: this.t().gapTight })
        }
        ForEach(node.children, (child: LiveNode, index: number) => {
          // A hairline between rows, never above the first. Drawn by the group
          // rather than by the row so a row does not have to know whether it is
          // last.
          // Rules go between rows. A program that puts something else in a
          // group -- an ActionBar for the row above it, most often -- was
          // getting a rule drawn across it, which read as a broken list.
          if (index > 0 && (child.kind === 'listitem' || child.kind === 'intlistitem')) {
            Divider()
              .strokeWidth(this.t().borderWidth)
              .color(this.t().lineSoft)
              .margin({ left: this.t().padListX, right: this.t().padListX })
          }
          this.renderNode(child, 'listgroup')
          // Same keying as renderChildren; see the note there.
        }, (child: LiveNode, index: number) => index.toString() + ':' + child.kind)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .backgroundColor(this.t().surfaceRaised)
      .border({ width: this.t().borderWidth, color: this.t().line })
      .borderRadius(this.t().radiusCard)
      .clip(true)
      .margin({ top: this.t().gapTight, bottom: this.t().gapTight })
    } else if (node.kind === 'banner') {
      Row({ space: this.t().gapBase }) {
        if (node.icon.length > 0) {
          this.drawIcon(node.icon, this.t().sizeHeading,
            toneEdge(this.t(), node.style, this.t().primaryInk))
        }
        Column({ space: 2 }) {
          if (node.text.length > 0) {
            Text(node.text)
              .fontSize(this.t().sizeBody)
              .fontFamily(this.textFamily())
              .fontWeight(this.t().weightHeading)
              .fontColor(toneInk(this.t(), node.style, this.t().ink))
              .width('100%')
          }
          if (node.label.length > 0) {
            Text(node.label)
              .fontSize(this.t().sizeCaption)
              .fontFamily(this.textFamily())
              .fontColor(this.t().inkSoft)
              .width('100%')
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        if (node.value.length > 0) {
          Button(node.value)
            .height(this.t().chipHeight)
            .fontSize(this.t().sizeCaption + 1)
            .fontFamily(this.textFamily())
            .type(ButtonType.Capsule)
            .backgroundColor(toneEdge(this.t(), node.style, this.t().primary))
            .fontColor(this.t().onPrimary)
            .onClick(() => {
              if (node.action.length > 0) { this.handleAction(node.action, node.eventValue) }
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding(this.t().padBase)
      .backgroundColor(toneFill(this.t(), node.style, this.t().surface))
      .borderRadius(this.t().radiusControl)
      // A rail in the tone, so the banner reads as a status at a glance rather
      // than as one more tinted box.
      .borderWidth({ left: 4 })
      .borderColor({ left: toneEdge(this.t(), node.style, this.t().primary) })
      .margin({ top: this.t().gapTight, bottom: this.t().gapTight })
    } else if (node.kind === 'emptystate') {
      // State starts empty, so for most programs this is the first thing anyone
      // sees. It used to be a blank column.
      Column({ space: this.t().gapBase }) {
        if (node.icon.length > 0) {
          this.drawIcon(node.icon, this.t().sizeDisplay, this.t().inkMuted)
        }
        Text(node.text)
          .fontSize(this.t().sizeHeading)
          .fontFamily(this.textFamily())
          .fontWeight(this.t().weightHeading)
          .fontColor(node.style === 'muted' ? this.t().inkMuted : this.t().ink)
          .textAlign(TextAlign.Center)
          .width('100%')
        if (node.label.length > 0) {
          Text(node.label)
            .fontSize(this.t().sizeBody)
            .fontFamily(this.textFamily())
            .fontColor(this.t().inkMuted)
            .textAlign(TextAlign.Center)
            .width('100%')
        }
        if (node.value.length > 0) {
          Button(node.value)
            .height(this.t().controlHeight)
            .fontSize(this.t().sizeBody)
            .fontFamily(this.textFamily())
            .type(ButtonType.Capsule)
            .backgroundColor(this.t().primary)
            .fontColor(this.t().onPrimary)
            .onClick(() => {
              if (node.action.length > 0) { this.handleAction(node.action, node.eventValue) }
            })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .padding(this.t().padLoose)
    } else if (node.kind === 'stat') {
      // Carries no surface of its own: it is meant to sit inside a MetricGroup,
      // which owns the one surface the group shares.
      Column({ space: 2 }) {
        Row({ space: this.t().gapTight }) {
          if (node.icon.length > 0) {
            this.drawIcon(node.icon, this.t().sizeCaption,
              toneInk(this.t(), node.style, this.t().inkMuted))
          }
          if (node.label.length > 0) {
            Text(node.label)
              .fontSize(this.t().sizeCaption)
              .fontFamily(this.textFamily())
              .fontColor(this.t().inkMuted)
              .layoutWeight(1)
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        Text(node.text)
          .fontSize(this.t().sizeMetric)
          .fontFamily(this.textFamily())
          .fontWeight(this.t().weightMetric)
          .fontColor(toneInk(this.t(), node.style, this.t().ink))
          .width('100%')
        if (node.value.length > 0) {
          Text(node.value)
            .fontSize(this.t().sizeCaption)
            .fontFamily(this.textFamily())
            .fontColor(this.t().inkSoft)
            .width('100%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(this.t().padBase)
    } else if (node.kind === 'metricgroup') {
      // Equal columns over one shared surface, built the same way ui.Grid is
      // and for the same reason -- see the note in the grid branch.
      Flex({
        wrap: FlexWrap.Wrap,
        justifyContent: FlexAlign.Start,
        alignItems: ItemAlign.Start
      }) {
        ForEach(node.children, (child: LiveNode) => {
          Column() {
            this.renderNode(child, 'metricgroup')
          }
          .width(Math.floor(100 / this.fittingColumns(this.metricColumns(node), 128)).toString() + '%')
          // Same keying as renderChildren; see the note there.
        }, (child: LiveNode, index: number) => index.toString() + ':' + child.kind)
      }
      .width('100%')
      .padding(densityPad(this.t(), node.style) - this.t().padTight)
      .margin({ top: this.t().gapTight, bottom: this.t().gapTight })
    } else if (node.kind === 'inttext') {
      // ui.Text's twin for a number the program holds as a number.
      Text(this.formatInt(node))
        .fontSize(textSize(this.t(), node.style))
        .fontFamily(this.textFamily())
        .fontWeight(textWeight(this.t(), node.style))
        .fontColor(textInk(this.t(), node.style))
        .width(parentKind === 'row' ? undefined : '100%')
        .constraintSize({ maxWidth: '100%' })
        .flexShrink(1)
        .padding({ top: 2, bottom: 2 })
    } else if (node.kind === 'clocktext') {
      Text(node.prefix + this.formatMinutes(node.intValue) + node.suffix)
        .fontSize(textSize(this.t(), node.style))
        .fontFamily(this.textFamily())
        .fontWeight(textWeight(this.t(), node.style))
        .fontColor(textInk(this.t(), node.style))
        .width(parentKind === 'row' ? undefined : '100%')
        .constraintSize({ maxWidth: '100%' })
        .flexShrink(1)
        .padding({ top: 2, bottom: 2 })
    } else if (node.kind === 'intstat') {
      Column({ space: 2 }) {
        Row({ space: this.t().gapTight }) {
          if (node.icon.length > 0) {
            this.drawIcon(node.icon, this.t().sizeCaption,
              toneInk(this.t(), node.style, this.t().inkMuted))
          }
          if (node.label.length > 0) {
            Text(node.label)
              .fontSize(this.t().sizeCaption)
              .fontFamily(this.textFamily())
              .fontColor(this.t().inkMuted)
              .layoutWeight(1)
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        Text(this.formatInt(node))
          .fontSize(this.t().sizeMetric)
          .fontFamily(this.textFamily())
          .fontWeight(this.t().weightMetric)
          .fontColor(toneInk(this.t(), node.style, this.t().ink))
          .width('100%')
        if (node.value.length > 0) {
          Text(node.value)
            .fontSize(this.t().sizeCaption)
            .fontFamily(this.textFamily())
            .fontColor(this.t().inkSoft)
            .width('100%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(this.t().padBase)
    } else if (node.kind === 'intfield') {
      // Stepper rather than a keyboard: the value has to come back as an int,
      // and there is no way to turn typed text into one.
      Column({ space: this.t().gapTight }) {
        if (node.label.length > 0) {
          Text(node.label).fontSize(this.t().sizeCaption).fontColor(this.t().inkSoft).width('100%')
        }
        Row({ space: this.t().gapBase }) {
          Button('-')
            .width(this.t().controlHeight)
            .height(this.t().controlHeight)
            .type(ButtonType.Circle)
            .enabled(node.enabled && node.intValue > node.minimum)
            .backgroundColor(this.t().secondaryFill)
            .fontColor(this.t().secondaryInk)
            .onClick(() => {
              if (node.action.length === 0) { return }
              let next = node.intValue - 1
              if (next >= node.minimum) { this.handleAction(node.action, next) }
            })
          Text(this.formatInt(node))
            .fontSize(this.t().sizeHeading)
            .fontFamily(this.textFamily())
            .fontWeight(this.t().weightHeading)
            .fontColor(this.t().ink)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
          Button('+')
            .width(this.t().controlHeight)
            .height(this.t().controlHeight)
            .type(ButtonType.Circle)
            .enabled(node.enabled && node.intValue < node.maximum)
            .backgroundColor(this.t().primary)
            .fontColor(this.t().onPrimary)
            .onClick(() => {
              if (node.action.length === 0) { return }
              let next = node.intValue + 1
              if (next <= node.maximum) { this.handleAction(node.action, next) }
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding({ top: this.t().gapTight, bottom: this.t().gapTight })
    } else if (node.kind === 'timefield') {
      Row({ space: this.t().gapBase }) {
        Text(node.label).fontSize(this.t().sizeBody).layoutWeight(1)
        Button(this.formatMinutes(node.intValue))
          .height(this.t().chipHeight)
          .fontSize(this.t().sizeBody)
          .fontFamily(this.textFamily())
          .type(ButtonType.Capsule)
          .enabled(node.enabled)
          .backgroundColor(this.t().secondaryFill)
          .fontColor(this.t().secondaryInk)
          .onClick(() => {
            if (node.action.length === 0) { return }
            // The phone's own picker, so the value is always a real time and
            // the program never has to validate one.
            TimePickerDialog.show({
              selected: this.minutesToDate(node.intValue),
              useMilitaryTime: true,
              onAccept: (result: TimePickerResult) => {
                let h = result.hour !== undefined ? result.hour as number : 0
                let m = result.minute !== undefined ? result.minute as number : 0
                this.handleAction(node.action, h * 60 + m)
              }
            })
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ top: this.t().padRow, bottom: this.t().padRow })
    } else if (node.kind === 'intlistitem') {
      Row({ space: this.t().gapBase + 2 }) {
        if (node.icon.length > 0) {
          this.drawIcon(node.icon, this.t().sizeHeading,
            toneInk(this.t(), node.style, this.t().inkSoft))
        }
        Column({ space: 2 }) {
          Text(node.text).fontSize(this.t().sizeBody + 1).width('100%')
          if (node.label.length > 0) {
            Text(node.label).fontSize(this.t().sizeCaption).fontColor(this.t().inkMuted).width('100%')
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Text(this.formatInt(node))
          .fontSize(this.t().sizeBody)
          .fontFamily(this.textFamily())
          .fontWeight(this.t().weightHeading)
          .fontColor(toneInk(this.t(), node.style, this.t().inkStrong))
      }
      .width('100%')
      .padding({ left: this.t().padListX, right: this.t().padListX,
                 top: this.t().padListY, bottom: this.t().padListY })
      // Identical framing rules to ui.ListItem, so the two mix inside one
      // ListGroup without the rows disagreeing about whether they have borders.
      .backgroundColor(toneFill(this.t(), node.style,
        parentKind === 'listgroup' ? '#00000000' : this.t().surfaceRaised))
      .border({
        width: parentKind === 'listgroup' ? 0 : this.t().borderWidth,
        color: this.t().lineSoft
      })
      .borderRadius(parentKind === 'listgroup' ? 0 : this.t().radiusControl)
      .margin({
        top: parentKind === 'listgroup' ? 0 : this.t().gapTight - 1,
        bottom: parentKind === 'listgroup' ? 0 : this.t().gapTight - 1
      })
      .opacity(node.enabled ? 1 : 0.5)
      .onClick(() => {
        if (node.action.length > 0 && node.enabled) {
          this.handleAction(node.action, node.eventValue)
        }
      })
    } else if (node.kind === 'actionbar' && parentKind === 'listgroup') {
      // Inside a group the bar belongs to the row above it, so it is inset to
      // the row's own margin and packs to one end instead of spreading across
      // the full width, where two buttons end up in opposite corners.
      Flex({
        wrap: FlexWrap.Wrap,
        justifyContent: FlexAlign.End,
        alignItems: ItemAlign.Center,
        space: { main: LengthMetrics.vp(this.t().gapBase),
                 cross: LengthMetrics.vp(this.t().gapTight) }
      }) {
        this.renderChildren(node)
      }
      .width('100%')
      .padding({ left: this.t().padListX, right: this.t().padListX,
                 top: 0, bottom: this.t().gapBase })
    } else if (node.kind === 'actionbar') {
      // Wraps rather than overflowing, for the reason the plain row branch
      // gives: a control past the right edge cannot be tapped.
      Flex({
        wrap: FlexWrap.Wrap,
        justifyContent: node.style === 'end' ? FlexAlign.End :
          node.style === 'center' ? FlexAlign.Center :
            node.style === 'spread' ? FlexAlign.SpaceBetween : FlexAlign.Start,
        alignItems: ItemAlign.Center,
        space: { main: LengthMetrics.vp(this.t().gapBase),
                 cross: LengthMetrics.vp(this.t().gapTight) }
      }) {
        this.renderChildren(node)
      }
      .width('100%')
      .padding({ top: this.t().gapBase, bottom: this.t().gapBase })
    } else if (node.kind === 'timeline') {
      // The rail belongs to the timeline, not to the entry.
      //
      // An entry cannot draw the line below itself, because it does not know
      // whether it is the last one, and a rail that runs on past the final
      // marker reads as an unfinished list. The parent knows, so the parent
      // draws both the marker and the line, and the entry draws only its words.
      Column() {
        if (node.text.length > 0) {
          Text(node.text)
            .fontSize(this.t().sizeCaption)
            .fontFamily(this.textFamily())
            .fontWeight(this.t().weightHeading)
            .fontColor(this.t().inkMuted)
            .width('100%')
            .padding({ bottom: this.t().gapTight })
        }
        ForEach(node.children, (child: LiveNode, index: number) => {
          // The rail is the entry's own left border.
          //
          // It has to be exactly as tall as the entry beside it, and every way
          // of asking for that height directly fails: height('100%') inside a
          // Scroll resolves against an unbounded height and stretches the first
          // entry down the whole screen, in a Row and in a Stack alike -- both
          // were tried and both did it. A border needs no height at all. It is
          // drawn down the side of the content whatever the content turns out
          // to be, which is the thing that was wanted, and the last entry
          // simply has none so the rail stops where the events do.
          //
          // The marker then sits over the line on a disc of the background
          // colour, which is what breaks the rail at each node.
          Stack({ alignContent: Alignment.TopStart }) {
            Column() {
              this.renderNode(child, 'timeline')
            }
            .width('100%')
            .padding({ left: this.t().gapLoose })
            .border({
              width: { left: index < node.children.length - 1 ? this.t().borderWidth * 2 : 0 },
              color: { left: this.t().line }
            })

            // A marker means "a moment happened here", so only an entry gets
            // one. The other things a timeline may hold -- the ActionBar that
            // belongs to the entry above it -- sit against the rail without
            // interrupting it, which is what they are: part of that moment, not
            // another one.
            Column() {
              if (child.kind === 'timelineitem' && child.icon.length > 0) {
                this.drawIcon(child.icon, this.t().sizeBody,
                  toneEdge(this.t(), child.style, this.t().primaryInk))
              } else if (child.kind === 'timelineitem') {
                Column()
                  .width(this.t().gapBase)
                  .height(this.t().gapBase)
                  .borderRadius(this.t().gapBase / 2)
                  .backgroundColor(toneEdge(this.t(), child.style, this.t().primaryInk))
              }
            }
            .width(child.kind === 'timelineitem' ? this.t().sizeBody * 1.5 : 0)
            .height(child.kind === 'timelineitem' ? this.t().sizeBody * 1.5 : 0)
            .borderRadius(this.t().sizeBody * 0.75)
            .backgroundColor(child.kind === 'timelineitem'
              ? this.t().background : '#00000000')
            .alignItems(HorizontalAlign.Center)
            .justifyContent(FlexAlign.Center)
            .offset({ x: -(this.t().sizeBody * 0.75) })
            // Same keying as renderChildren; see the note there.
          }
          .width('100%')
        }, (child: LiveNode, index: number) => index.toString() + ':' + child.kind)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({
        left: densityPad(this.t(), node.style) + this.t().sizeBody * 0.75,
        right: densityPad(this.t(), node.style),
        top: densityPad(this.t(), node.style),
        bottom: densityPad(this.t(), node.style)
      })
      .margin({ top: this.t().gapTight, bottom: this.t().gapSection })
    } else if (node.kind === 'timelineitem') {
      // Only the words: the marker and the rail beside it are the timeline's.
      Column({ space: 2 }) {
        Row({ space: this.t().gapBase }) {
          Text(node.text)
            .fontSize(this.t().sizeBody + 1)
            .fontFamily(this.textFamily())
            .fontWeight(this.t().weightHeading)
            .fontColor(toneInk(this.t(), node.style, this.t().ink))
            .layoutWeight(1)
          if (node.value.length > 0) {
            Text(node.value)
              .fontSize(this.t().sizeBody)
              .fontFamily(this.textFamily())
              .fontColor(this.t().inkSoft)
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        if (node.label.length > 0) {
          Text(node.label)
            .fontSize(this.t().sizeCaption)
            .fontFamily(this.textFamily())
            .fontColor(this.t().inkMuted)
            .width('100%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ bottom: node.style === 'compact' ? this.t().gapBase : this.t().gapLoose })
      .opacity(node.enabled ? 1 : 0.5)
      .onClick(() => {
        if (node.action.length > 0 && node.enabled) {
          this.handleAction(node.action, node.eventValue)
        }
      })
    } else if (node.kind === 'kvgroup') {
      Flex({
        wrap: FlexWrap.Wrap,
        justifyContent: FlexAlign.Start,
        alignItems: ItemAlign.Start
      }) {
        ForEach(node.children, (child: LiveNode) => {
          Column() {
            this.renderNode(child, 'kvgroup')
          }
          // A fact needs more room than a figure, so it asks for a wider cell.
          .width(Math.floor(100 / this.fittingColumns(
            node.columns > 0 ? node.columns : 2, 160)).toString() + '%')
          // Same keying as renderChildren; see the note there.
        }, (child: LiveNode, index: number) => index.toString() + ':' + child.kind)
      }
      .width('100%')
      .padding(densityPad(this.t(), node.style) - this.t().padTight)
      .margin({ top: this.t().gapTight, bottom: this.t().gapTight })
    } else if (node.kind === 'kvitem') {
      Column({ space: 2 }) {
        Text(node.label)
          .fontSize(this.t().sizeCaption)
          .fontFamily(this.textFamily())
          .fontColor(this.t().inkMuted)
          .width('100%')
        Text(node.text)
          .fontSize(this.t().sizeBody)
          .fontFamily(this.textFamily())
          .fontWeight(this.t().weightHeading)
          .fontColor(toneInk(this.t(), node.style, this.t().ink))
          .width('100%')
        if (node.value.length > 0) {
          Text(node.value)
            .fontSize(this.t().sizeCaption)
            .fontFamily(this.textFamily())
            .fontColor(this.t().inkSoft)
            .width('100%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(this.t().padBase)
    } else if (node.kind === 'icon') {
      this.drawIcon(node.icon, this.t().sizeHeading,
        toneInk(this.t(), node.style, this.t().inkStrong))
    } else if (node.kind === 'iconbutton') {
      // Sized to the same 44 as a text button, so a row of mixed actions lines
      // up and the tap target stays a tap target.
      Column() {
        this.drawIcon(node.icon, this.t().sizeHeading,
          node.style === 'quiet' || node.style === 'secondary'
            ? this.t().secondaryInk : this.t().onPrimary)
      }
      .width(this.t().controlHeight)
      .height(this.t().controlHeight)
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(node.style === 'quiet' ? '#00000000'
        : node.style === 'secondary' ? this.t().secondaryFill
          : buttonFill(this.t(), node.style))
      .borderRadius(this.t().controlHeight / 2)
      .opacity(node.enabled ? 1 : 0.4)
      .accessibilityText(node.label)
      .onClick(() => {
        if (node.action.length > 0 && node.enabled) {
          this.handleAction(node.action, node.eventValue)
        }
      })
    } else if (node.kind === 'badge') {
      Row({ space: this.t().gapTight }) {
        if (node.icon.length > 0) {
          this.drawIcon(node.icon, this.t().sizeCaption,
            toneInk(this.t(), node.style, this.t().inkSoft))
        }
        Text(node.text)
          .fontSize(this.t().sizeCaption)
          .fontFamily(this.textFamily())
          .fontWeight(this.t().weightHeading)
          .fontColor(toneInk(this.t(), node.style, this.t().inkSoft))
      }
      .padding({ left: this.t().gapBase, right: this.t().gapBase,
                 top: this.t().gapTight - 1, bottom: this.t().gapTight - 1 })
      .backgroundColor(toneFill(this.t(), node.style, this.t().surface))
      .borderRadius(this.t().radiusSmall)
    } else if (node.kind === 'button') {
      Button(node.text.length === 0 ? ' ' : node.text)
        .height(this.t().controlHeight)
        .fontSize(this.t().sizeBody)
        .fontFamily(this.textFamily())
        .enabled(node.enabled)
        .type(node.style === 'secondary' ? ButtonType.Normal : ButtonType.Capsule)
        .backgroundColor(buttonFill(this.t(), node.style))
        .fontColor(buttonInk(this.t(), node.style))
        .onClick(() => {
          if (node.action.length > 0 && node.enabled) {
            this.handleAction(node.action, node.eventValue)
          }
        })
    } else if (node.kind === 'cell') {
      Column() {
        // Two steps below the title size: a board glyph, not a heading.
        Text(node.text).fontSize(this.t().sizeTitle - 2).fontWeight(FontWeight.Bold)
          .fontColor(node.enabled ? this.t().inkStrong : this.t().inkDisabled)
      }
      .layoutWeight(parentKind === 'grid' ? 0 : 1)
      .width(parentKind === 'grid' ? '100%' : undefined)
      // A board cell should be square. Outside a row a cell is a list item and
      // keeps a comfortable fixed height instead.
      .aspectRatio(parentKind === 'row' || parentKind === 'grid' ? 1 : 0)
      .height(parentKind === 'row' || parentKind === 'grid' ? undefined : 68)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(node.enabled ? this.t().surfaceRaised : this.t().surfaceDisabled)
      .border({
        width: node.style === 'accent' ? this.t().borderWidth * 2 : this.t().borderWidth,
        color: toneEdge(this.t(), node.style, this.t().lineStrong)
      })
      .borderRadius(this.t().radiusControl)
      .onClick(() => {
        if (node.action.length > 0 && node.enabled) {
          this.handleAction(node.action, node.eventValue)
        }
      })
    } else if (node.kind === 'spacer') {
      if (node.style !== 'none') {
        Blank()
          .height(parentKind === 'row' ? 0 : spacerSize(this.t(), node.style))
          .width(parentKind === 'row' ? spacerSize(this.t(), node.style) : 0)
      }
    } else if (node.kind === 'field') {
      Column({ space: this.t().gapTight }) {
        if (node.label.length > 0) {
          Text(node.label).fontSize(this.t().sizeCaption).fontColor(this.t().inkSoft).width('100%')
        }
        // Commits on submit rather than on every keystroke. The tree no longer
        // rebuilds under the caret, but echoing each character back through the
        // VM and into .text() still fights whoever is typing.
        TextInput({ placeholder: node.label, text: node.value })
          .height(node.style === 'multiline' ? this.t().controlHeight * 2 : this.t().controlHeight)
          .width('100%')
          .enabled(node.enabled)
          .onSubmit((_key: EnterKeyType, _event: SubmitEvent) => {})
          .onChange((v: string) => {
            if (node.action.length > 0) { this.handleStringAction(node.action, v) }
          })
      }
      .width('100%')
      .padding({ top: this.t().gapTight, bottom: this.t().gapTight })
    } else if (node.kind === 'toggle' || node.kind === 'checkbox') {
      Row({ space: this.t().gapBase + 2 }) {
        Text(node.label).fontSize(this.t().sizeBody).layoutWeight(1)
        if (node.kind === 'toggle') {
          Toggle({ type: ToggleType.Switch, isOn: node.checked })
            .enabled(node.enabled)
            .selectedColor(this.t().primary)
            .onChange((on: boolean) => {
              if (node.action.length > 0) { this.handleBoolAction(node.action, on) }
            })
        } else {
          Checkbox()
            .select(node.checked)
            .enabled(node.enabled)
            .selectedColor(this.t().primary)
            .onChange((on: boolean) => {
              if (node.action.length > 0) { this.handleBoolAction(node.action, on) }
            })
        }
      }
      .width('100%')
      .padding({ top: this.t().padRow, bottom: this.t().padRow })
    } else if (node.kind === 'slider') {
      Column({ space: 2 }) {
        Row() {
          Text(node.label).fontSize(this.t().sizeCaption).fontColor(this.t().inkSoft).layoutWeight(1)
          Text(node.eventValue.toString()).fontSize(this.t().sizeCaption).fontColor(this.t().inkStrong)
        }.width('100%')
        Slider({
          value: node.eventValue,
          min: node.minimum,
          max: node.maximum,
          step: 1,
          style: SliderStyle.OutSet
        })
          .width('100%')
          .enabled(node.enabled)
          .selectedColor(this.t().primary)
          .onChange((v: number, mode: SliderChangeMode) => {
            // Every position reaches the program, so the thing being controlled
            // follows the thumb instead of jumping when the finger lifts -- a
            // slider that only answers on release reads as broken. Only the end
            // of the drag is written to disk, so a drag is one save, not fifty.
            if (node.action.length === 0) { return }
            this.dispatch(node.action, new VeraIntValue(Math.round(v)),
              mode === SliderChangeMode.End)
          })
      }
      .width('100%')
      .padding({ top: this.t().gapTight, bottom: this.t().gapTight })
    } else if (node.kind === 'select') {
      Column({ space: this.t().gapTight }) {
        if (node.label.length > 0) {
          Text(node.label).fontSize(this.t().sizeCaption).fontColor(this.t().inkSoft).width('100%')
        }
        Row({ space: this.t().padRow }) {
          ForEach(node.options, (opt: string, index: number) => {
            Button(opt)
              .height(this.t().chipHeight)
              .fontSize(this.t().sizeCaption + 1)
              .fontFamily(this.textFamily())
              .type(ButtonType.Capsule)
              .enabled(node.enabled)
              .backgroundColor(index === node.eventValue ? this.t().primary : this.t().secondaryFill)
              .fontColor(index === node.eventValue ? this.t().onPrimary : this.t().secondaryInk)
              .onClick(() => {
                if (node.action.length > 0) { this.handleAction(node.action, index) }
              })
          }, (opt: string, index: number) => index.toString() + opt)
        }
        .width('100%')
      }
      .width('100%')
      .padding({ top: this.t().gapTight, bottom: this.t().gapTight })
    } else if (node.kind === 'grid') {
      // Equal columns built from a wrapping Flex rather than ArkUI's Grid: Grid
      // wants an explicit height, while a generated tree grows to whatever the
      // program produced. Each child is boxed at its share of the width, so the
      // cells stay square and wrap onto new rows by themselves.
      Flex({
        wrap: FlexWrap.Wrap,
        justifyContent: FlexAlign.Start,
        alignItems: ItemAlign.Start
      }) {
        ForEach(node.children, (child: LiveNode) => {
          Column() {
            this.renderNode(child, 'grid')
          }
          .width(Math.floor(100 / (node.columns > 0 ? node.columns : 1)).toString() + '%')
          .padding(this.gridPad(node.style))
          // Same keying as renderChildren; see the note there.
        }, (child: LiveNode, index: number) => index.toString() + ':' + child.kind)
      }
      .width('100%')
      .padding(this.t().padGrid)
    } else if (node.kind === 'listitem') {
      Row({ space: this.t().gapBase + 2 }) {
        if (node.icon.length > 0) {
          this.drawIcon(node.icon, this.t().sizeHeading,
            toneInk(this.t(), node.style, this.t().inkSoft))
        }
        Column({ space: 2 }) {
          Text(node.text).fontSize(this.t().sizeBody + 1).width('100%')
          if (node.label.length > 0) {
            Text(node.label).fontSize(this.t().sizeCaption).fontColor(this.t().inkMuted).width('100%')
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        if (node.value.length > 0) {
          Text(node.value).fontSize(this.t().sizeBody - 1).fontColor(this.t().inkSoft)
        }
      }
      .width('100%')
      .padding({ left: this.t().padListX, right: this.t().padListX,
                 top: this.t().padListY, bottom: this.t().padListY })
      // Inside a ListGroup the row owns no frame of its own: the group draws
      // one border, one radius and the separators, which is the whole reason
      // ListGroup exists. On its own the row is still a standalone card.
      .backgroundColor(toneFill(this.t(), node.style,
        parentKind === 'listgroup' ? '#00000000' : this.t().surfaceRaised))
      .border({
        width: parentKind === 'listgroup' ? 0 : this.t().borderWidth,
        color: this.t().lineSoft
      })
      .borderRadius(parentKind === 'listgroup' ? 0 : this.t().radiusControl)
      .margin({
        top: parentKind === 'listgroup' ? 0 : this.t().gapTight - 1,
        bottom: parentKind === 'listgroup' ? 0 : this.t().gapTight - 1
      })
      .opacity(node.enabled ? 1 : 0.5)
      .onClick(() => {
        if (node.action.length > 0 && node.enabled) {
          this.handleAction(node.action, node.eventValue)
        }
      })
    } else if (node.kind === 'ticker') {
      // Draws nothing: it exists so the host will call the program on a timer.
      Blank().height(0).width(0)
    } else if (node.kind === 'divider') {
      Divider().strokeWidth(this.t().borderWidth).color(this.t().line)
        .margin({ top: this.t().padRow, bottom: this.t().padRow })
    } else if (node.kind === 'progress') {
      Column({ space: 3 }) {
        if (node.label.length > 0) {
          Text(node.label).fontSize(this.t().sizeCaption).fontColor(this.t().inkSoft).width('100%')
        }
        Progress({
          value: node.eventValue,
          total: node.maximum > 0 ? node.maximum : 100,
          type: ProgressType.Linear
        })
          .width('100%')
          .color(toneEdge(this.t(), node.style, this.t().primary))
      }
      .width('100%')
      .padding({ top: this.t().gapTight, bottom: this.t().gapTight })
    } else if (node.kind === 'canvas') {
      // One shared coordinate field. Every other container divides space between
      // its children; this one hands all of them the same 0..100 box and lets
      // them overlap, which is what a drawing made of several shapes needs. The
      // group is scaled once, as a group, so the distances the model computed
      // between the parts survive.
      Column() {
        Stack({ alignContent: Alignment.TopStart }) {
          this.renderChildren(node)
        }
        .scale({ x: node.style === 'large' ? 3.4 : node.style === 'small' ? 1.8 : 2.6,
                 y: node.style === 'large' ? 3.4 : node.style === 'small' ? 1.8 : 2.6 })
      }
      .width('100%')
      .height(node.style === 'large' ? 360 : node.style === 'small' ? 200 : 280)
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
    } else if (node.kind === 'path' && parentKind === 'canvas') {
      // Bare: no wrapper, no centring, no scale of its own. Those are right for
      // a lone shape and fatal for a composition -- centring throws away the
      // position the shape was given, and a per-shape scale throws away its size
      // relative to its neighbours.
      Path({ commands: node.commands })
        .fill(pathFill(this.t(), node.style))
        .rotate({ angle: node.spinPeriodMs > 0 ? this.spin.angle : 0 })
    } else if (node.kind === 'path') {
      Column() {
        // Drawn inline rather than through a child component. Passing a @Trace
        // field of the live tree into a custom component's constructor makes
        // that component silently fail to construct -- measured on device: the
        // same component built from constants renders, built from node fields it
        // never appears. That is the V1/V2 boundary, and the way past it is not
        // to cross it.
        //
        // No width or height on the Path: given a size it draws its commands at
        // their own units from the top-left of a larger box, and .rotate() then
        // swings the shape around a point outside itself, so it orbits instead
        // of spinning.
        Path({ commands: node.commands })
          .fill(pathFill(this.t(), node.style))
          .rotate({ angle: node.spinPeriodMs > 0 ? this.spin.angle : 0 })
          .scale({ x: 2.4, y: 2.4 })
      }
      .width('100%')
      .height(240)
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
    } else if (node.kind === 'image') {
      // std/ui has declared Image since the first version, but there was no
      // branch here, so every generated program that used one painted nothing
      // and still reported success.
      if (node.source.length > 0) {
        Image(node.source)
          .width('100%')
          .height(180)
          .objectFit(ImageFit.Contain)
          .borderRadius(this.t().radiusControl)
          .accessibilityText(node.alt)
      } else {
        Text(node.alt.length > 0 ? node.alt : 'image')
          .fontSize(this.t().sizeCaption + 1)
          .fontFamily(this.textFamily())
          .fontColor(this.t().inkMuted)
          .width('100%')
          .height(180)
          .textAlign(TextAlign.Center)
          .backgroundColor(this.t().surface)
          .borderRadius(this.t().radiusControl)
      }
    } else {
      // A kind the decoder produced but no branch above renders. Saying so is
      // worth more than a blank: a silent gap looks like a model failure.
      Text('unrendered component: ' + node.kind)
        .fontSize(this.t().sizeCaption)
        .fontFamily(this.textFamily())
        .fontColor(this.t().dangerInk)
        .width('100%')
        .padding(this.t().gapBase)
        .backgroundColor(this.t().dangerFill)
        .borderRadius(this.t().radiusSmall)
    }
  }
}
