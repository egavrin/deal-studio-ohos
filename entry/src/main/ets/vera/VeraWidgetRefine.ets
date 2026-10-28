import { CATALOG, describeComponents } from './VeraUiCatalog'
import { widgetRefinementError } from './VeraCompiler'
import { VirtualMachine, deserializeVbc2, decodeRuntimeValue } from './VeraInterpreter'
import { decodeVeraUi, UiHostEnvironment } from './VeraUi'
import { WidgetSession, CardNode, LIVE_MAX_DEPTH, LIVE_MAX_NODES, LIVE_MAX_TEXT, LIVE_MAX_JSON, LIVE_MAX_STEPS } from './VeraLiveWidget'

/** Only Make widget receives these instructions. Fullscreen UI is not restricted. */
export function widgetRefinementPrompt(): string {
  let names = CATALOG.filter((component): boolean => component.card).map((component): string => component.name)
  return 'Add a compact home-screen widget to this existing program. Return the complete program.\n' +
    'Preserve every existing class, init, view and handler unchanged, including their signatures and bodies. ' +
    'Add or replace only function widget(state: the init return type): ui.View and new uniquely named helpers/number handlers. ' +
    'Share the existing state; do not add fields or reset data. Show the most useful summary and at most two small local actions. ' +
    'If an action needs SDK/intent effects, omit it: the widget title already opens the app. ' +
    'widget must be synchronous and side-effect free, with no ticker, scrolling, inputs, images, or networking. ' +
    'Use ONLY the card-safe constructors below in widget and its helpers; the fullscreen view keeps its full catalogue. ' +
    'AppTheme is optional and root-only; light theme only. Fit a 2x2 card with a title strip above your content. ' +
    'Prefer one Column with a summary and one Row of buttons; avoid long lists. ' +
    'Limits: depth ' + LIVE_MAX_DEPTH.toString() + ' excluding root AppTheme, ' + LIVE_MAX_NODES.toString() +
    ' nodes, ' + LIVE_MAX_TEXT.toString() + ' UTF-16 characters/text, ' + LIVE_MAX_JSON.toString() +
    ' UTF-16 units/frame including state token, ' + LIVE_MAX_STEPS.toString() + ' VM steps/entry.\n' + describeComponents(names)
}

/** Structural preservation is checked separately from runtime validation so repair gets precise feedback. */
export function validateWidgetRefinement(base: string, source: string, vbc2: string, saved: string = ''): string {
  try {
    let preservation = widgetRefinementError(base, source)
    if (preservation.length > 0) { return preservation }
    return checkWidget(vbc2, saved)
  } catch (e) { return 'Widget validation: ' + (e as Error).message }
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
