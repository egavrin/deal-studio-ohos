/**
 * The Jev template path as one call, shared by the Generate screen and the Chat screen.
 *
 * Jev picks the screen's sections (VeraSectionCompose.ets), a narrow model call fills their text
 * and lists (VeraTemplateContent.ets), the fragments are composed and compiled, the result is run
 * with every handler tapped (VeraSmoke.ets).
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
import { selectSections, readSectionPick, composeProgram, specsOf, SectionPickOutcome, SectionPick } from './VeraSectionCompose'
import { ScreenPlan, planFromBlocks, assemblePlan } from './ScreenPlan'
import { verifyWeakPick, VERIFY_WEAK_PICKS, VerifyAnswer } from './VeraPickVerify'
import { expandRequest, ExpandResult, expandRequestsEnabled } from './VeraRequestExpand'
import { RouteInfo, jevStateOf, logicOf, ROUTE_BLOCKS, ROUTE_BLOCKS_MODEL, ROUTE_SCRATCH, JEV_UNSURE, JEV_UNAVAILABLE, CHECK_NONE, CHECK_OFF, CHECK_YESNO,
  CHECK_CONFIRMED, CHECK_REJECTED, CHECK_FAILED } from './VeraRoute'
import { compileVeraSource, CompileResult } from './VeraCompiler'
import { smokeRun } from './VeraSmoke'
import { deepseek } from './DeepSeekEngine'
import { holeValues, holeBodiesBySlot } from './VeraHoles'
import { BlockRequest, BlockFill, fillSections, needsGrounding, mergedValues } from './SectionFill'
import { appBlockCalls } from './SectionFillApp'
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
  /** The search results the text was filled from ('' when no search was made or it found nothing), so a completion does not search again. */
  searchText: string = ''
  contentMs: number = 0
  /** The composition record (VeraComposition.ets) as JSON, for template and complete; the program above is rebuilt from it. */
  composition: string = ''
  layout: string = 'stack'
  /**
   * The plan the program was assembled from (ScreenPlan.ets), once the sections are filled; null before. For `complete`
   * it has a slot to be written for each thing the request needs that the sections do not do.
   */
  plan: ScreenPlan | null = null
  /** Which way this request went and why, for the Generate screen and the Metrics tab (VeraRoute.ets). */
  route: RouteInfo = new RouteInfo()
}

/**
 * What a soft veto says the request needs that none of the sections does, in words: a slot of the plan for a section
 * the model writes (agent/AgentHole.ets). Jev reads that section against it with the request beside it, so the words
 * name the kind of thing, and the request says which.
 */
const SOFT_NEEDS: Map<string, string> = new Map<string, string>([
  ['needs_logic', 'works out what the request asks to be calculated, converted, totalled, split, compared or decided, from what the person enters'],
  ['needs_search_or_form', 'lets the person search, filter or sort, or fill in the form of several fields, that the request asks for'],
  ['needs_multiple_counters', 'keeps a separate count or running total for each person or thing the request names'],
  ['needs_live_ticking', 'shows what the request asks to tick, count or change by itself in real time'],
  ['needs_integration', 'has the phone or another app do what the request asks']
])

/** Blocks that show what they were filled with and do nothing else. */
const DISPLAY_ONLY_KINDS: string[] = ['key_facts', 'spotlight', 'metrics', 'trend_chart', 'bar_chart', 'data_table', 'timeline']

/**
 * Whether the soft vetoes that asked for a completion are all "needs_integration" and every block only displays: the
 * request wanted real-world numbers and the blocks were filled with them. Any other veto (a calculation, a form, a second
 * counter) or any block with taps and inputs still needs the model.
 */
export function groundedDisplayOnly(kinds: string[], logicTags: string[]): boolean {
  if (logicTags.length === 0) { return false }
  for (let tag of logicTags) { if (tag !== 'needs_integration') { return false } }
  let shown = kinds.filter((k: string): boolean => k !== 'none')
  if (shown.length === 0) { return false }
  for (let kind of shown) { if (DISPLAY_ONLY_KINDS.indexOf(kind) < 0) { return false } }
  return true
}

/**
 * The composed program is the right base but not enough for the request: the caller completes it (the model writes what the
 * plan has open). `modelRoute` is whether the route log says the model is part of it.
 */
export function markComplete(build: TemplateBuild, note: string, status: string, modelRoute: boolean = true): TemplateBuild {
  build.action = BUILD_COMPLETE
  if (modelRoute) { build.route.route = ROUTE_BLOCKS_MODEL }
  build.note = note
  build.status = status
  return build
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
    // A rewrite of the request starts with Jev's first answer and is read only if Jev picks nothing; otherwise it is dropped.
    let expanding: Promise<ExpandResult> | null = expandRequestsEnabled() && mode === 'deepseek' && settings.hasApiKey() ? expandRequest(prompt) : null
    let jevStart = Date.now()
    let outcome: SectionPickOutcome = await selectSections(prompt, settings.getSelectorKey())
    build.jevMs = Date.now() - jevStart
    if (isCancelled()) { build.action = BUILD_CANCELLED; return build }
    // What the model is shown as the request: the rewrite when it rescued the pick, else what the person typed.
    // The web search, the phone-function lookup and the record keep the original wording.
    let work = prompt
    // Not when Jev did not answer at all (no key, timeout, an error): a second call to the same service would only wait out
    // another timeout, 15 s on the phone.
    if (outcome.sections === null && expanding !== null && jevStateOf(outcome) !== JEV_UNAVAILABLE) {
      onStatus('Rewriting the request...')
      let rewrite: ExpandResult = await expanding
      if (isCancelled()) { build.action = BUILD_CANCELLED; return build }
      build.route.expandMs = rewrite.ms
      if (rewrite.text.length > 0) {
        let retryStart = Date.now()
        let second: SectionPickOutcome = await selectSections(rewrite.text, settings.getSelectorKey())
        build.jevMs = build.jevMs + (Date.now() - retryStart)
        if (isCancelled()) { build.action = BUILD_CANCELLED; return build }
        // Only a pick counts: a veto or another nothing keeps the first answer, so a correct veto is never lost. A pick Jev
        // only "wanted" (no section chose it, the best guess above the floor) does not count either: a rewrite made "animated
        // dice" an intent panel at 0.62, where the first answer, nothing, was right and led to a program written from scratch.
        let picked = second.sections !== null && second.wanted.length === 0 &&
          second.sections.some((p: SectionPick): boolean => p.kind !== 'none')
        console.info('VERA-EXPAND used=' + picked.toString() + ' first=' + outcome.note + ' second=' + second.note)
        if (picked) {
          outcome = second
          work = rewrite.text
          build.route.expanded = rewrite.text
        }
      }
    }
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
    // grounded in one real search before it is trusted. A trend_chart or a live_facts needs grounding whatever Jev
    // said (SectionFill.ets's needsGrounding): its gate is one probability on the whole request and can miss on an
    // identical prompt from one run to the next.
    let canSearch = mode !== 'server' && settings.hasExaKey()
    if (needsGrounding(build.kinds, outcome.needsRealData) && !canSearch) {
      return scratch(outcome.note + ' (needs real data, no search available; generating normally)', '', build,
        'Jev chose ' + build.kinds.join(' + ') + ', but the request needs real data and no search is available, so the model writes it from scratch.')
    }

    // The intent panel's rows are a call of their own, made while the content is filled: it needs only the request.
    let rowsKinds = build.kinds
    let rowsFill: Promise<IntentRowsFill> | null = null
    if (rowsKinds.indexOf('intent_panel') >= 0 && mode === 'deepseek') {
      rowsFill = fillIntentRows(prompt, rowsKinds,
        (system: string, user: string): Promise<string | null> => deepseek.extractTemplateContent(system, user, 600))
    }

    // The search, the content, the live-source checks and the holes: the fill both builders share (SectionFill.ets).
    let kinds = build.kinds
    let request = new BlockRequest()
    request.kinds = kinds
    request.prompt = prompt
    request.work = work
    request.mode = mode
    request.realData = outcome.needsRealData
    for (let section of sections) { request.slotValues.push(section.slotValues) }
    request.globals = outcome.globalValues
    request.compose = (filled: Map<string, string>[], globals: Map<string, string>): string => composeProgram(kinds, globals, filled)
    let fill: BlockFill = await fillSections(request, appBlockCalls(canSearch, onStatus, isCancelled))
    if (fill.cancelled || isCancelled()) { build.action = BUILD_CANCELLED; return build }
    build.searchMs = fill.searchMs
    build.contentMs = fill.contentMs
    build.route.holes = fill.holeBodies.size > 0

    let globalValues: Map<string, string> = fill.globals
    let baseValues = fill.baseValues
    let instanceValues = fill.values
    let holeBodies: Map<string, string> = fill.holeBodies
    let searchTag = ''
    if (fill.grounded) {
      searchTag = ' search=' + (fill.searched ? 'ok' : 'empty')
      build.route.searched = fill.searched
      if (fill.searched) { build.searchText = fill.searchText }
    }
    let note = outcome.note + searchTag + (fill.contentNote.length > 0 ? ' ' + fill.contentNote : '') +
      (fill.liveNotes.length > 0 ? ' ' + fill.liveNotes.join(' ') : '') + (fill.holesNote.length > 0 ? ' ' + fill.holesNote : '')
    let shown = build.kinds.filter((k: string): boolean => k !== 'none').join('+')
    let panelRows = -1
    if (build.kinds.indexOf('intent_panel') >= 0) {
      panelRows = 0
      if (rowsFill !== null) {
        let rows: IntentRowsFill = await rowsFill
        if (isCancelled()) { build.action = BUILD_CANCELLED; return build }
        rows.bodies.forEach((v: string, k: string) => { holeBodies.set(k, v) })
        instanceValues = mergedValues(instanceValues, holeValues(build.kinds, rows.bodies))
        panelRows = rows.rows
        note = note + ' ' + rows.note
      } else {
        note = note + ' intents=none(' + mode + ')'
      }
    }
    let plan = planFromBlocks(prompt, build.layout, specsOf(build.kinds), globalValues, instanceValues)
    build.plan = plan
    let source = assemblePlan(plan)
    let compiled: CompileResult
    try {
      compiled = compileVeraSource(source)
    } catch (_e) {
      return scratch('composed ' + shown + ' but it failed to compile; generated normally',
        'Template pick failed to compile, generating normally...', build,
        'Jev chose ' + shown + ', but the composed program did not compile, so the model writes it from scratch.')
    }
    // Started, drawn, and every handler tapped: the check every served program passes (VeraSmoke.ets).
    let problem = smokeRun(compiled)
    if (problem.length > 0) {
      return scratch('composed ' + shown + ' but it did not run (' + problem + '); generated normally',
        'Template pick did not run, generating normally...', build,
        'Jev chose ' + shown + ', but the composed program did not run (' + problem + '), so the model writes it from scratch.')
    }
    build.source = source
    build.vbc2 = compiled.vbc2
    let record = new Composition()
    record.layout = build.layout
    record.prompt = prompt
    globalValues.forEach((v: string, k: string) => { record.globals.set(k, v) })
    let bodiesBySlot = holeBodiesBySlot(build.kinds, holeBodies)
    for (let i = 0; i < build.kinds.length; i++) { record.blocks.push(new Block(build.kinds[i], baseValues[i], bodiesBySlot[i])) }
    build.composition = compositionToJson(record)

    // A block that only shows facts, filled from a search that found them, is finished: the one soft veto left is "needs
    // the real world" (needs_integration, below the hard bar), and the search has just been to the real world. Without this
    // the model searched again and rewrote the whole screen (the weather screen: 27 s, 18 s of it the rewrite).
    let filledFromSearch = outcome.needsLogic && build.route.searched && groundedDisplayOnly(build.kinds, outcome.softVetoes)
    if (filledFromSearch) { note = note + ' (data filled from search, no completion)' }
    if (outcome.needsLogic && !filledFromSearch) {
      for (let key of outcome.softVetoes) { plan.addToWrite('missing.' + key, SOFT_NEEDS.get(key) ?? key, key === 'needs_integration') }
      build.route.logic = logicOf(outcome.note)
      return markComplete(build, note, 'Composed ' + shown + ', adding the logic the request needs...')
    }
    // An intent panel without rows shows only "No actions": the model writes the calls instead.
    if (panelRows === 0) {
      plan.addToWrite('missing.needs_integration', SOFT_NEEDS.get('needs_integration')!, true)
      return markComplete(build, note, 'Composed ' + shown + ', finding the phone actions the request needs...')
    }
    // The actions block's buttons only note which one was tapped. A screen of nothing else looks finished and does
    // nothing: phone-action requests ("a button for the torch") landed here without tripping needs_integration.
    if (sections.every((p: SectionPick): boolean => p.kind === 'actions')) {
      plan.addToWrite('missing.buttons', 'makes each button do what the request asks, rather than only noting that it was tapped', true)
      return markComplete(build, note + ' (placeholder buttons only)', 'Composed ' + shown + ', making its buttons do what the request asks...', false)
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
