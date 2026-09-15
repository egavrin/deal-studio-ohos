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
import { runIntent } from '../vera/VeraIntents'
import { addCalendarEvent } from '../vera/VeraCalendar'
import { LengthMetrics } from '@ohos.arkui.node'

import { catalogKinds } from '../vera/VeraUiCatalog'
import { store } from '../vera/ProjectStore'
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
  private spinTimer: number = -1
  private spinPeriod: number = 0

  // Kinds renderNode has a branch for. Checked against the catalogue on mount so
  // a component that compiles but cannot be drawn is reported here rather than
  // discovered as a blank space in someone's generated app.
  private static RENDERED: string[] = ['column', 'scroll', 'row', 'card', 'text',
    'button', 'cell', 'spacer', 'path', 'image', 'field', 'toggle', 'checkbox',
    'slider', 'select', 'divider', 'progress', 'ticker', 'grid', 'listitem', 'canvas']

  aboutToAppear(): void {
    let missing: string[] = []
    for (let kind of catalogKinds()) {
      if (VeraPreview.RENDERED.indexOf(kind) < 0) { missing.push(kind) }
    }
    if (missing.length > 0) {
      console.error('VERA-RENDER catalogue kinds with no render branch: ' + missing.join(','))
      this.error = 'Renderer is missing: ' + missing.join(', ')
    }
    this.load()
  }

  onProgramChanged(): void {
    this.load()
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
    for (let effect of effects) {
      console.info('VERA-EFFECT id=' + effect.id.toString() + ' ' + effect.kind +
        ' -> ' + effect.resultHandler)
      this.runEffect(effect)
    }
  }

  /** One effect, whichever host it belongs to, answered through its handler. */
  private runEffect(effect: HostEffect): void {
    let answer: Promise<string>
    if (effect.kind === 'calendar') {
      answer = addCalendarEvent(
        this.effectText(effect, 'title'),
        this.effectInt(effect, 'hour', 9),
        this.effectInt(effect, 'minute', 0),
        this.effectInt(effect, 'durationMinutes', 15),
        this.effectInt(effect, 'remindBefore', 0),
        this.effectText(effect, 'repeat'))
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

  @Builder
  renderNode(node: LiveNode, parentKind: string) {
    if (node.kind === 'scroll') {
      // Rendered as a plain Column until now, so a program asking for a
      // scrolling region got one that could not scroll and simply grew.
      Scroll() {
        Column() {
          this.renderChildren(node)
        }
        .width('100%')
        .alignItems(node.style === 'center' ? HorizontalAlign.Center : HorizontalAlign.Start)
        .padding(node.style === 'compact' ? 6 : node.style === 'spacious' ? 16 : 10)
      }
      .width('100%')
      .constraintSize({ maxHeight: 420 })
      .align(Alignment.Top)
      .scrollBar(BarState.Auto)
      .backgroundColor(
        node.style === 'surface' ? '#F3F6FA' :
          node.style === 'accent' ? '#EBF0FF' : '#00000000')
    } else if (node.kind === 'column') {
      Column() {
        this.renderChildren(node)
      }
      .width('100%')
      .alignItems(node.style === 'center' ? HorizontalAlign.Center : HorizontalAlign.Start)
      .padding(node.style === 'compact' ? 6 : node.style === 'spacious' ? 16 : 10)
      .backgroundColor(
        node.style === 'surface' ? '#F3F6FA' :
          node.style === 'accent' ? '#EBF0FF' : '#00000000')
    } else if (node.kind === 'row' && this.rowDistributes(node)) {
      // A row of cells or cards is a grid row: the children share the width by
      // weight, and a wrapping Flex does not distribute weight, which collapses
      // a board to nothing.
      Row({ space: node.style === 'compact' ? 4 : node.style === 'spacious' ? 12 : 8 }) {
        this.renderChildren(node)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .justifyContent(node.style === 'split' ? FlexAlign.SpaceBetween :
        node.style === 'center' ? FlexAlign.Center : FlexAlign.Start)
      .padding(6)
      .backgroundColor(
        node.style === 'surface' ? '#F3F6FA' :
          node.style === 'accent' ? '#EBF0FF' : '#00000000')
    } else if (node.kind === 'row') {
      // Everything else wraps rather than pushing children past the right edge,
      // where they cannot be tapped. Half the probes lost a control that way --
      // a "Mark taken" button, the true/false of a switch, a preset that read
      // "Call mo".
      Flex({
        wrap: FlexWrap.Wrap,
        justifyContent: node.style === 'split' ? FlexAlign.SpaceBetween :
          node.style === 'center' ? FlexAlign.Center : FlexAlign.Start,
        alignItems: ItemAlign.Center,
        space: { main: LengthMetrics.vp(node.style === 'compact' ? 4 : node.style === 'spacious' ? 12 : 8),
                 cross: LengthMetrics.vp(6) }
      }) {
        this.renderChildren(node)
      }
      .width('100%')
      .padding(6)
      .backgroundColor(
        node.style === 'surface' ? '#F3F6FA' :
          node.style === 'accent' ? '#EBF0FF' : '#00000000')
    } else if (node.kind === 'card') {
      Column() {
        this.renderChildren(node)
      }
      .width(parentKind === 'row' ? undefined : '100%')
      .layoutWeight(parentKind === 'row' ? 1 : 0)
      .alignItems(HorizontalAlign.Start)
      .padding(14)
      .backgroundColor(
        node.style === 'accent' ? '#EBF0FF' :
          node.style === 'success' ? '#E8F8E8' :
            node.style === 'warning' ? '#FFF8E0' :
              node.style === 'danger' ? '#FFECEC' : '#F3F6FA')
      .border({ width: 1, color: '#D8E1ED' })
      .borderRadius(14)
    } else if (node.kind === 'text') {
      Text(node.text)
        .fontSize(
          node.style === 'title' ? 24 :
            node.style === 'heading' ? 18 :
              node.style === 'metric' ? 32 :
                node.style === 'caption' ? 12 : 15)
        .fontWeight(
          node.style === 'title' ? FontWeight.Bold :
            node.style === 'heading' ? FontWeight.Medium :
              node.style === 'metric' ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(
          node.style === 'muted' ? '#888888' :
            node.style === 'success' ? '#2E7D32' :
              node.style === 'warning' ? '#E65100' :
                node.style === 'danger' ? '#C62828' : '#000000')
        // In a row the text takes only what it needs and shrinks rather than
        // shoving its siblings out of the window; the row wraps if it must.
        // Making it greedy instead (an earlier attempt) merely moved the problem
        // to rows that also hold a weighted card.
        .width(parentKind === 'row' ? undefined : '100%')
        .constraintSize({ maxWidth: '100%' })
        .flexShrink(1)
        .padding({ top: 2, bottom: 2 })
    } else if (node.kind === 'button') {
      Button(node.text.length === 0 ? ' ' : node.text)
        .height(44)
        .fontSize(15)
        .enabled(node.enabled)
        .type(node.style === 'secondary' ? ButtonType.Normal : ButtonType.Capsule)
        .backgroundColor(
          node.style === 'success' ? '#4CAF50' :
            node.style === 'danger' ? '#F44336' :
              node.style === 'secondary' ? '#E0E0E0' : '#007DFF')
        .fontColor(node.style === 'secondary' ? '#333333' : '#FFFFFF')
        .onClick(() => {
          if (node.action.length > 0 && node.enabled) {
            this.handleAction(node.action, node.eventValue)
          }
        })
    } else if (node.kind === 'cell') {
      Column() {
        Text(node.text).fontSize(22).fontWeight(FontWeight.Bold)
          .fontColor(node.enabled ? '#333333' : '#CCCCCC')
      }
      .layoutWeight(parentKind === 'grid' ? 0 : 1)
      .width(parentKind === 'grid' ? '100%' : undefined)
      // A board cell should be square. Outside a row a cell is a list item and
      // keeps a comfortable fixed height instead.
      .aspectRatio(parentKind === 'row' || parentKind === 'grid' ? 1 : 0)
      .height(parentKind === 'row' || parentKind === 'grid' ? undefined : 68)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(node.enabled ? '#FFFFFF' : '#F5F5F5')
      .border({
        width: node.style === 'accent' ? 2 : 1,
        color: node.style === 'accent' ? '#007DFF' :
          node.style === 'success' ? '#4CAF50' :
            node.style === 'danger' ? '#F44336' : '#CBD6E4'
      })
      .borderRadius(10)
      .onClick(() => {
        if (node.action.length > 0 && node.enabled) {
          this.handleAction(node.action, node.eventValue)
        }
      })
    } else if (node.kind === 'spacer') {
      if (node.style !== 'none') {
        Blank()
          .height(parentKind === 'row' ? 0 :
            (node.style === 'large' ? 32 : node.style === 'small' ? 8 : 18))
          .width(parentKind === 'row' ?
            (node.style === 'large' ? 32 : node.style === 'small' ? 8 : 18) : 0)
      }
    } else if (node.kind === 'field') {
      Column({ space: 4 }) {
        if (node.label.length > 0) {
          Text(node.label).fontSize(12).fontColor('#666666').width('100%')
        }
        // Commits on submit rather than on every keystroke. The tree no longer
        // rebuilds under the caret, but echoing each character back through the
        // VM and into .text() still fights whoever is typing.
        TextInput({ placeholder: node.label, text: node.value })
          .height(node.style === 'multiline' ? 88 : 44)
          .width('100%')
          .enabled(node.enabled)
          .onSubmit((_key: EnterKeyType, _event: SubmitEvent) => {})
          .onChange((v: string) => {
            if (node.action.length > 0) { this.handleStringAction(node.action, v) }
          })
      }
      .width('100%')
      .padding({ top: 4, bottom: 4 })
    } else if (node.kind === 'toggle' || node.kind === 'checkbox') {
      Row({ space: 10 }) {
        Text(node.label).fontSize(15).layoutWeight(1)
        if (node.kind === 'toggle') {
          Toggle({ type: ToggleType.Switch, isOn: node.checked })
            .enabled(node.enabled)
            .onChange((on: boolean) => {
              if (node.action.length > 0) { this.handleBoolAction(node.action, on) }
            })
        } else {
          Checkbox()
            .select(node.checked)
            .enabled(node.enabled)
            .onChange((on: boolean) => {
              if (node.action.length > 0) { this.handleBoolAction(node.action, on) }
            })
        }
      }
      .width('100%')
      .padding({ top: 6, bottom: 6 })
    } else if (node.kind === 'slider') {
      Column({ space: 2 }) {
        Row() {
          Text(node.label).fontSize(12).fontColor('#666666').layoutWeight(1)
          Text(node.eventValue.toString()).fontSize(12).fontColor('#333333')
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
      .padding({ top: 4, bottom: 4 })
    } else if (node.kind === 'select') {
      Column({ space: 4 }) {
        if (node.label.length > 0) {
          Text(node.label).fontSize(12).fontColor('#666666').width('100%')
        }
        Row({ space: 6 }) {
          ForEach(node.options, (opt: string, index: number) => {
            Button(opt)
              .height(36)
              .fontSize(13)
              .type(ButtonType.Capsule)
              .enabled(node.enabled)
              .backgroundColor(index === node.eventValue ? '#007DFF' : '#E0E0E0')
              .fontColor(index === node.eventValue ? '#FFFFFF' : '#333333')
              .onClick(() => {
                if (node.action.length > 0) { this.handleAction(node.action, index) }
              })
          }, (opt: string, index: number) => index.toString() + opt)
        }
        .width('100%')
      }
      .width('100%')
      .padding({ top: 4, bottom: 4 })
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
          .padding(node.style === 'compact' ? 2 : node.style === 'spacious' ? 6 : 4)
          // Same keying as renderChildren; see the note there.
        }, (child: LiveNode, index: number) => index.toString() + ':' + child.kind)
      }
      .width('100%')
      .padding(4)
    } else if (node.kind === 'listitem') {
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text(node.text).fontSize(16).width('100%')
          if (node.label.length > 0) {
            Text(node.label).fontSize(12).fontColor('#888888').width('100%')
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        if (node.value.length > 0) {
          Text(node.value).fontSize(14).fontColor('#666666')
        }
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 12, bottom: 12 })
      .backgroundColor(
        node.style === 'accent' ? '#EBF0FF' :
          node.style === 'success' ? '#E8F8E8' :
            node.style === 'warning' ? '#FFF8E0' :
              node.style === 'danger' ? '#FFECEC' : '#FFFFFF')
      .border({ width: 1, color: '#E4EAF2' })
      .borderRadius(10)
      .margin({ top: 3, bottom: 3 })
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
      Divider().strokeWidth(1).color('#D8E1ED').margin({ top: 6, bottom: 6 })
    } else if (node.kind === 'progress') {
      Column({ space: 3 }) {
        if (node.label.length > 0) {
          Text(node.label).fontSize(12).fontColor('#666666').width('100%')
        }
        Progress({
          value: node.eventValue,
          total: node.maximum > 0 ? node.maximum : 100,
          type: ProgressType.Linear
        })
          .width('100%')
          .color(
            node.style === 'success' ? '#4CAF50' :
              node.style === 'warning' ? '#E65100' :
                node.style === 'danger' ? '#F44336' : '#007DFF')
      }
      .width('100%')
      .padding({ top: 4, bottom: 4 })
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
        .fill(
          node.style === 'accent' ? '#007DFF' :
            node.style === 'success' ? '#4CAF50' :
              node.style === 'warning' ? '#E65100' :
                node.style === 'danger' ? '#F44336' :
                  node.style === 'muted' ? '#B0BEC5' :
                    node.style === 'light' ? '#FFFFFF' : '#37474F')
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
          .fill(
            node.style === 'accent' ? '#007DFF' :
              node.style === 'success' ? '#4CAF50' :
                node.style === 'warning' ? '#E65100' :
                  node.style === 'danger' ? '#F44336' :
                    node.style === 'muted' ? '#B0BEC5' : '#37474F')
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
          .borderRadius(10)
          .accessibilityText(node.alt)
      } else {
        Text(node.alt.length > 0 ? node.alt : 'image')
          .fontSize(13)
          .fontColor('#888888')
          .width('100%')
          .height(180)
          .textAlign(TextAlign.Center)
          .backgroundColor('#F3F6FA')
          .borderRadius(10)
      }
    } else {
      // A kind the decoder produced but no branch above renders. Saying so is
      // worth more than a blank: a silent gap looks like a model failure.
      Text('unrendered component: ' + node.kind)
        .fontSize(12)
        .fontColor('#C62828')
        .width('100%')
        .padding(8)
        .backgroundColor('#FFECEC')
        .borderRadius(8)
    }
  }
}
