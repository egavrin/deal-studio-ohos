/**
 * The Jev template path as one call, shared by the Generate screen and the Chat screen.
 *
 * Jev picks the screen's sections (VeraSectionCompose.ets), a narrow model call fills their text
 * and lists (VeraTemplateContent.ets), the fragments are composed and compiled, the result is run
 * once (VeraSmokeRun.ets).
 * The caller gets one of three answers and acts on it:
 *
 *   template   the composed program is the result; show it as it is.
 *   complete   the composed program is the right base but not enough for the request (a soft veto
 *              fired, or every block is placeholder buttons): hand `source` to the model to finish,
 *              keep it as the fallback if that fails.
 *   scratch    no usable composition (Jev picked nothing, a hard veto, no search for data the request
 *              needs, the composition did not compile or did not run): generate from scratch.
 *   cancelled  the caller asked to stop while this ran.
 *
 * Never throws: every failure ends as `scratch` with the reason in `note`.
 */

import { settings } from './SettingsStore'
import { selectSections, readSectionPick, composeProgram, SectionPickOutcome, SectionPick } from './VeraSectionCompose'
import { verifyWeakPick, VERIFY_WEAK_PICKS, VerifyAnswer } from './VeraPickVerify'
import { RouteInfo, jevStateOf, logicOf, ROUTE_BLOCKS, ROUTE_BLOCKS_MODEL, ROUTE_SCRATCH, JEV_UNSURE, CHECK_NONE, CHECK_OFF, CHECK_YESNO,
  CHECK_CONFIRMED, CHECK_REJECTED, CHECK_FAILED } from './VeraRoute'
import { fillSectionsContent } from './VeraTemplateContent'
import { compileVeraSource } from './VeraCompiler'
import { smokeRun, SmokeResult } from './VeraSmokeRun'
import { webSearch } from './VeraWebSearch'
import { deepseek, discoveryToolResult } from './DeepSeekEngine'
import { holesOf, holeValues, holeBodiesBySlot, fillHoles, HoleFill, HoleInstance } from './VeraHoles'
import { Composition, Block, compositionToJson } from './VeraComposition'
import { fillIntentRows, IntentRowsFill } from './VeraIntentPanel'

export const BUILD_TEMPLATE: string = 'template'
export const BUILD_COMPLETE: string = 'complete'
export const BUILD_SCRATCH: string = 'scratch'
export const BUILD_CANCELLED: string = 'cancelled'

export class TemplateBuild {
  action: string = BUILD_SCRATCH
  /** What Jev and the fill answered, for the "Jev:" row. */
  note: string = ''
  /** One line for the page's status area. */
  status: string = ''
  source: string = ''
  vbc2: string = ''
  /** The chosen section kinds, 'none' for an empty slot. */
  kinds: string[] = []
  jevMs: number = 0
  /** Milliseconds spent on the second opinion for a weak pick, 0 when it was not asked. */
  verifyMs: number = 0
  /** -1 when no search was made. */
  searchMs: number = -1
  contentMs: number = 0
  /** The composition record (VeraComposition.ets) as JSON, for template and complete; the program above is rebuilt from it. */
  composition: string = ''
  layout: string = 'stack'
  /** Which way this request went and why, for the Generate screen and the Metrics tab (VeraRoute.ets). */
  route: RouteInfo = new RouteInfo()
}

/** Per-slot copies of `values` with `extra` added; the caller's maps are not changed. */
function mergeHoleValues(values: Map<string, string>[], extra: Map<string, string>[]): Map<string, string>[] {
  let out: Map<string, string>[] = []
  for (let i = 0; i < values.length; i++) {
    let merged: Map<string, string> = new Map<string, string>()
    values[i].forEach((v: string, k: string) => { merged.set(k, v) })
    if (i < extra.length) { extra[i].forEach((v: string, k: string) => { merged.set(k, v) }) }
    out.push(merged)
  }
  return out
}

function scratch(note: string, status: string, build: TemplateBuild, failure: string = ''): TemplateBuild {
  build.action = BUILD_SCRATCH
  build.route.route = ROUTE_SCRATCH
  build.route.failure = failure
  if (build.route.note.length === 0) { build.route.note = note }
  build.note = note
  build.status = status
  return build
}

/**
 * `mode` is the Generate screen's generation mode ('deepseek', 'local' or 'server'); the chat is
 * always 'deepseek'. Server mode cannot ground a composition in a search, so a request that needs
 * real data goes to scratch there.
 */
export async function buildFromTemplates(prompt: string, mode: string, onStatus: (status: string) => void,
    isCancelled: () => boolean): Promise<TemplateBuild> {
  let build = new TemplateBuild()
  try {
    onStatus('Checking for a canned template...')
    let jevStart = Date.now()
    let outcome: SectionPickOutcome = await selectSections(prompt, settings.getSelectorKey())
    build.jevMs = Date.now() - jevStart
    if (isCancelled()) { build.action = BUILD_CANCELLED; return build }
    build.route.jev = jevStateOf(outcome)
    build.route.note = outcome.note
    build.route.weak = outcome.weakKinds
    if (outcome.sections === null && !VERIFY_WEAK_PICKS && outcome.weakKinds.length > 0) { build.route.check = CHECK_OFF }
    if (outcome.sections === null && VERIFY_WEAK_PICKS && mode !== 'server' && outcome.weakKinds.length > 0 && outcome.rawBody.length > 0) {
      onStatus('Double-checking a weak pick...')
      let verifyStart = Date.now()
      let second: VerifyAnswer = await verifyWeakPick(prompt, outcome.weakKinds)
      build.verifyMs = Date.now() - verifyStart
      if (isCancelled()) { build.action = BUILD_CANCELLED; return build }
      build.route.missing = second.missing
      if (second.confirmed.length > 0) {
        let confirmedNote = 'verified ' + second.confirmed.join('+')
        outcome = readSectionPick(outcome.rawBody, second.confirmed)
        outcome.note = outcome.note + ' ' + confirmedNote
        build.route.check = CHECK_CONFIRMED
        build.route.jev = JEV_UNSURE
      } else {
        outcome.note = outcome.note + ' verify=no' + (second.missing.length > 0 ? ' missing=' + second.missing : '')
        build.route.check = second.failed ? CHECK_FAILED : CHECK_REJECTED
      }
    }
    if (outcome.sections === null) {
      return scratch(outcome.note, '', build)
    }
    // Empty sections are dropped: the composition record keeps only blocks that exist, and the
    // numbers in the generated names follow the blocks that are really there.
    let sections = outcome.sections.filter((p: SectionPick): boolean => p.kind !== 'none')
    if (sections.length === 0) { return scratch(outcome.note, '', build) }
    for (let section of sections) { build.kinds.push(section.kind) }
    build.layout = outcome.layout
    build.route.kinds = build.kinds
    if (outcome.wanted.length > 0 && build.route.check === CHECK_NONE) {
      build.route.check = CHECK_YESNO
      build.route.wanted = outcome.wanted
      build.route.wantedP = outcome.wantedP
    }

    // needs_real_data alone does not null outcome.sections -- it means this composition has to be
    // grounded in one real search before it is trusted. A trend_chart needs grounding whatever Jev
    // said: its gate is one probability on the whole request and can miss on an identical prompt
    // from one run to the next, and a chart of invented round numbers is never what a chart request
    // wants.
    let needsGrounding = outcome.needsRealData || build.kinds.indexOf('trend_chart') >= 0
    let canGround = needsGrounding && mode !== 'server' && settings.hasExaKey()
    if (needsGrounding && !canGround) {
      return scratch(outcome.note + ' (needs real data, no search available; generating normally)', '', build,
        'Jev chose ' + build.kinds.join(' + ') + ', but the request needs real data and no search is available, so the model writes it from scratch.')
    }
    let searchText = ''
    if (needsGrounding) {
      onStatus('Looking up real data...')
      let searchStart = Date.now()
      searchText = await webSearch(prompt)
      build.searchMs = Date.now() - searchStart
      if (isCancelled()) { build.action = BUILD_CANCELLED; return build }
    }

    // The intent panel's rows are a call of their own, made while the content is filled: it needs only the request.
    let rowsKinds = build.kinds
    let rowsFill: Promise<IntentRowsFill> | null = null
    if (rowsKinds.indexOf('intent_panel') >= 0 && mode === 'deepseek') {
      rowsFill = fillIntentRows(prompt, rowsKinds,
        (system: string, user: string): Promise<string | null> => deepseek.extractTemplateContent(system, user, 600))
    }
    let contentStart = Date.now()
    let content = await fillSectionsContent(build.kinds, prompt, mode, searchText)
    build.contentMs = Date.now() - contentStart
    if (isCancelled()) { build.action = BUILD_CANCELLED; return build }

    let globalValues: Map<string, string> = new Map<string, string>()
    outcome.globalValues.forEach((v: string, k: string) => { globalValues.set(k, v) })
    content.globalValues.forEach((v: string, k: string) => { globalValues.set(k, v) })
    let instanceValues: Map<string, string>[] = []
    for (let i = 0; i < sections.length; i++) {
      let merged: Map<string, string> = new Map<string, string>()
      sections[i].slotValues.forEach((v: string, k: string) => { merged.set(k, v) })
      let contentForSlot = content.instanceValues[i]
      if (contentForSlot !== undefined) { contentForSlot.forEach((v: string, k: string) => { merged.set(k, v) }) }
      instanceValues.push(merged)
    }
    let searchTag = ''
    if (needsGrounding) {
      let searchOk = searchText.length > 0 && !searchText.startsWith('Search failed:') && searchText !== 'No results.'
      searchTag = ' search=' + (searchOk ? 'ok' : 'empty')
      build.route.searched = searchOk
    }
    let note = outcome.note + searchTag + (content.note.length > 0 ? ' ' + content.note : '')
    let shown = build.kinds.filter((k: string): boolean => k !== 'none').join('+')

    // Holes: function bodies the model writes for the chosen blocks (the filter's match rule), settled
    // against the compiler. Defaults apply when the model cannot or the mode has no model to ask.
    let baseValues = instanceValues
    let holeBodies: Map<string, string> = new Map<string, string>()
    if (holesOf(build.kinds, instanceValues).some((h: HoleInstance): boolean => h.spec.byModel)) {
      if (mode === 'deepseek') {
        onStatus('Writing the details...')
        let kinds = build.kinds
        // A hole that may call the phone is shown the SDK functions found for the request, the same lookup the model's own
        // find_sdk_function tool makes, so it copies a real target instead of guessing one.
        let sdkContext = ''
        for (let hole of holesOf(kinds, instanceValues)) {
          if (hole.spec.usesSdk) {
            sdkContext = (await discoveryToolResult('find_sdk_function', prompt.substring(0, 300), 0)).substring(0, 2500)
            break
          }
        }
        let fill: HoleFill = await fillHoles(prompt, kinds,
          (system: string, user: string): Promise<string | null> => deepseek.extractTemplateContent(system, user, 500, 'Function bodies for the blocks'),
          (bodies: Map<string, string>): string => composeProgram(kinds, globalValues, mergeHoleValues(instanceValues, holeValues(kinds, bodies))),
          instanceValues, sdkContext)
        if (isCancelled()) { build.action = BUILD_CANCELLED; return build }
        holeBodies = fill.bodies
        build.route.holes = fill.bodies.size > 0
        instanceValues = mergeHoleValues(instanceValues, holeValues(kinds, fill.bodies))
        if (fill.note.length > 0) { note = note + ' ' + fill.note }
      } else {
        note = note + ' holes=default(' + mode + ')'
      }
    }
    let panelRows = -1
    if (build.kinds.indexOf('intent_panel') >= 0) {
      panelRows = 0
      if (rowsFill !== null) {
        let rows: IntentRowsFill = await rowsFill
        if (isCancelled()) { build.action = BUILD_CANCELLED; return build }
        rows.bodies.forEach((v: string, k: string) => { holeBodies.set(k, v) })
        instanceValues = mergeHoleValues(instanceValues, holeValues(build.kinds, rows.bodies))
        panelRows = rows.rows
        note = note + ' ' + rows.note
      } else {
        note = note + ' intents=none(' + mode + ')'
      }
    }
    let source = composeProgram(build.kinds, globalValues, instanceValues)
    let vbc2 = ''
    try {
      vbc2 = compileVeraSource(source).vbc2
    } catch (_e) {
      return scratch('composed ' + shown + ' but it failed to compile; generated normally',
        'Template pick failed to compile, generating normally...', build,
        'Jev chose ' + shown + ', but the composed program did not compile, so the model writes it from scratch.')
    }
    let smoke: SmokeResult = smokeRun(vbc2)
    if (!smoke.ok) {
      return scratch('composed ' + shown + ' but it did not run (' + smoke.error + '); generated normally',
        'Template pick did not run, generating normally...', build,
        'Jev chose ' + shown + ', but the composed program did not run (' + smoke.error + '), so the model writes it from scratch.')
    }
    build.source = source
    build.vbc2 = vbc2
    let record = new Composition()
    record.layout = build.layout
    record.prompt = prompt
    globalValues.forEach((v: string, k: string) => { record.globals.set(k, v) })
    let bodiesBySlot = holeBodiesBySlot(build.kinds, holeBodies)
    for (let i = 0; i < build.kinds.length; i++) { record.blocks.push(new Block(build.kinds[i], baseValues[i], bodiesBySlot[i])) }
    build.composition = compositionToJson(record)

    if (outcome.needsLogic) {
      build.action = BUILD_COMPLETE
      build.route.route = ROUTE_BLOCKS_MODEL
      build.route.logic = logicOf(outcome.note)
      build.note = note
      build.status = 'Composed ' + shown + ', adding the logic the request needs...'
      return build
    }
    // An intent panel without rows shows only "No actions": the model writes the calls instead.
    if (panelRows === 0) {
      build.action = BUILD_COMPLETE
      build.route.route = ROUTE_BLOCKS_MODEL
      build.note = note
      build.status = 'Composed ' + shown + ', finding the phone actions the request needs...'
      return build
    }
    // The actions block's buttons only note which one was tapped. A screen of nothing else looks finished and does
    // nothing: phone-action requests ("a button for the torch") landed here without tripping needs_integration.
    if (sections.every((p: SectionPick): boolean => p.kind === 'actions')) {
      build.action = BUILD_COMPLETE
      build.note = note + ' (placeholder buttons only)'
      build.status = 'Composed ' + shown + ', making its buttons do what the request asks...'
      return build
    }
    build.action = BUILD_TEMPLATE
    build.route.route = ROUTE_BLOCKS
    build.note = note
    build.status = 'Composed ' + shown + ': ' + note.replace(' content:', ' | content:')
    return build
  } catch (e) {
    return scratch('template path failed (' + (e as Error).message + '); generated normally', '', build,
      'The block path failed (' + (e as Error).message + '), so the model writes it from scratch.')
  }
}
