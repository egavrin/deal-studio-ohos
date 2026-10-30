import { CATALOG, describeComponents } from './VeraUiCatalog'
import { widgetRefinementError } from './VeraCompiler'
import { VirtualMachine, deserializeVbc2, decodeRuntimeValue } from './VeraInterpreter'
import { decodeVeraUi, UiHostEnvironment } from './VeraUi'
import { WidgetSession, CardNode, LIVE_MAX_DEPTH, LIVE_MAX_NODES, LIVE_MAX_TEXT, LIVE_MAX_JSON, LIVE_MAX_STEPS } from './VeraLiveWidget'

/**
 * Only Make widget receives these instructions. Fullscreen UI is not restricted.
 *
 * The person's request says what the widget shows ("The home-screen widget should show: ..."); this says what a widget is:
 * a second, small view of the same state, read at a glance, with only the few things that matter most.
 */
export function widgetRefinementPrompt(): string {
  let names = CATALOG.filter((component): boolean => component.card).map((component): string => component.name)
  return 'Add a home-screen widget to this existing program. Return the complete program.\n' +
    'The widget is a second view of the same app: function widget(state) draws the very state view(state) draws, on a small ' +
    'card on the phone\'s home screen. The person\'s request says what it should show; follow it. ' +
    'A widget is read at a glance, in a second: show only the few things that matter most -- one to three figures or short ' +
    'lines, each with a label of a word or two -- and at most two buttons, for the actions worth doing without opening the app. ' +
    'Leave out everything else: lists and history, settings, inputs, explanations, and the app\'s name or any title or ' +
    'heading -- the space is too small for them. When the request asks for more than fits, keep what matters most and drop ' +
    'the rest. If the program already has a widget, replace it with the one asked for.\n' +
    'Preserve every existing class, init, view and handler unchanged, including their signatures and bodies. ' +
    'Add or replace only function widget(state: the init return type): ui.View and new uniquely named helpers/number handlers. ' +
    'Share the existing state; do not add fields or reset data. ' +
    'Keep the import lines exactly as they are. ' +
    'If an action needs SDK/intent effects, omit it. Do not add a button that opens the app: a tap on the card outside a ' +
    'button already does. ' +
    'widget must be synchronous and side-effect free, with no ticker, scrolling, inputs, images, or networking. ' +
    'Use ONLY the card-safe constructors below in widget and its helpers; the fullscreen view keeps its full catalogue. ' +
    'AppTheme is optional and root-only; light theme only. The whole 2x2 card is the widget\'s; nothing is drawn above it. ' +
    'Prefer one Column with a summary and one Row of buttons; avoid long lists. ' +
    'Limits: depth ' + LIVE_MAX_DEPTH.toString() + ' excluding root AppTheme, ' + LIVE_MAX_NODES.toString() +
    ' nodes, ' + LIVE_MAX_TEXT.toString() + ' UTF-16 characters/text, ' + LIVE_MAX_JSON.toString() +
    ' UTF-16 units/frame including state token, ' + LIVE_MAX_STEPS.toString() + ' VM steps/entry.\n' + describeComponents(names)
}

/** A widget is read at a glance: what widgetRefinementPrompt asks for, held to. */
export const WIDGET_MAX_BUTTONS: number = 2
export const WIDGET_MAX_TEXTS: number = 8

/** Structural preservation is checked separately from runtime validation so repair gets precise feedback. */
export function validateWidgetRefinement(base: string, source: string, vbc2: string, saved: string = ''): string {
  try {
    let preservation = widgetRefinementError(base, source)
    if (preservation.length > 0) { return preservation }
    let runtime = checkWidget(vbc2, saved)
    if (runtime.length > 0) { return runtime }
    return glanceError(vbc2, saved)
  } catch (e) { return 'Widget validation: ' + (e as Error).message }
}

/**
 * More than a glance: too many buttons or lines for the few things a widget shows. Only Make widget is held to it; the card
 * itself draws any frame within its budget. Said so the model can cut the widget down on the next attempt.
 */
function glanceError(vbc2: string, saved: string): string {
  let frame = new WidgetSession(vbc2, 'validation', saved).frame('project', 'App', '')
  let buttons = 0
  let texts = 0
  let count = (nodes: CardNode[]): void => {
    for (let node of nodes) {
      if (node.kind === 'button') { buttons++ } else if (node.text.length > 0) { texts++ }
      count(node.children)
    }
  }
  count(frame.nodes)
  if (buttons > WIDGET_MAX_BUTTONS) {
    return 'The widget has ' + buttons.toString() + ' buttons; a widget has at most ' + WIDGET_MAX_BUTTONS.toString() +
      ', for the actions that matter most. Not one per item: drop the rest, they stay in the app.'
  }
  if (texts > WIDGET_MAX_TEXTS) {
    return 'The widget shows ' + texts.toString() + ' texts; a widget shows at most ' + WIDGET_MAX_TEXTS.toString() +
      ' (one to three figures with short labels). No lists or history: keep what matters most, the rest stays in the app.'
  }
  return ''
}

/** Also used by smokeRun for any program that declares widget. Never executes phone effects. */
export function checkWidget(vbc2: string, saved: string = ''): string {
  try {
    let session = new WidgetSession(vbc2, 'validation', saved)
    let frame = session.frame('project', 'App', '')
    if (!frame.live) { return 'Missing function widget(state): ui.View' }
    let state = session.encodedState()
    // Each actual visible button, twice: includes distinct repeated-row payloads and redraw validation.
    let buttons: CardNode[] = []
    let collect = (nodes: CardNode[]): void => {
      for (let node of nodes) {
        if (node.kind === 'button' && node.enabled && node.action.length > 0) { buttons.push(node) }
        collect(node.children)
      }
    }
    collect(frame.nodes)
    for (let button of buttons) {
      let branch = new WidgetSession(vbc2, 'validation', state)
      for (let pass = 0; pass < 2; pass++) {
        let current = branch.frame('project', 'App', '')
        let available = (nodes: CardNode[]): boolean => nodes.some((node: CardNode): boolean =>
          (node.kind === 'button' && node.enabled && node.action === button.action && node.value === button.value) || available(node.children))
        if (!available(current.nodes)) { break }
        branch.tap(current, current.token, button.action, button.value)
        branch.frame('project', 'App', '')
        let host = new UiHostEnvironment()
        let vm = new VirtualMachine(deserializeVbc2(vbc2), host, LIVE_MAX_STEPS)
        // The same state must still draw in the app, not only on the card.
        decodeVeraUi(vm.execute('view', [decodeRuntimeValue(JSON.parse(branch.encodedState()) as Object)]))
      }
    }
    return ''
  } catch (e) { return 'Widget validation: ' + (e as Error).message }
}

/**
 * A widget that reads or builds state the app does not keep (E2031 no such field, E2022 unknown field). The reply's changes to
 * the app's own declarations are dropped (spliceWidget), so adding the field again cannot work: the next attempt is told so.
 */
export function widgetRepairNote(errors: string): string {
  if (!/\bE20(31|22)\b/.test(errors)) { return errors }
  return 'The widget cannot add fields to the state or change the app\'s existing classes and functions: they are kept ' +
    'exactly as the app has them, and any change to them is dropped. Show and change only what the state already holds; ' +
    'leave out what it does not.\n' + errors
}
