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
 *
 * Render first, fill after: when the result will be `template`, `onPreview` gets the same screen with the
 * blocks' default text as soon as Jev answers, before the search and the content fill. The final answer
 * then replaces it. When the filled program fails to compile or run, the default-text program is the
 * result instead of `scratch`.
 */

import { settings } from './SettingsStore'
import { selectSections, composeProgram, SectionPickOutcome, SectionPick } from './VeraSectionCompose'
import { fillSectionsContent } from './VeraTemplateContent'
import { compileVeraSource } from './VeraCompiler'
import { smokeRun, SmokeResult } from './VeraSmokeRun'
import { webSearch } from './VeraWebSearch'
import { deepseek } from './DeepSeekEngine'
import { holesOf, holeValues, holeBodiesBySlot, fillHoles, HoleFill } from './VeraHoles'
import { Composition, Block, compositionToJson } from './VeraComposition'

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
  /** -1 when no search was made. */
  searchMs: number = -1
  contentMs: number = 0
  /** The composition record (VeraComposition.ets) as JSON, for template and complete; the program above is rebuilt from it. */
  composition: string = ''
  layout: string = 'stack'
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

/**
 * Composes, compiles and smoke-runs into `build` (source, vbc2, composition). `baseValues` are stored
 * in the record and `holeBodies` beside them; `instanceValues` are what is composed. Answers '' or
 * the reason it failed.
 */
function composeInto(build: TemplateBuild, prompt: string, globalValues: Map<string, string>,
    instanceValues: Map<string, string>[], baseValues: Map<string, string>[], holeBodies: Map<string, string>): string {
  let source = composeProgram(build.kinds, globalValues, instanceValues)
  let vbc2 = ''
  try {
    vbc2 = compileVeraSource(source).vbc2
  } catch (_e) {
    return 'failed to compile'
  }
  let smoke: SmokeResult = smokeRun(vbc2)
  if (!smoke.ok) { return 'did not run (' + smoke.error + ')' }
  build.source = source
  build.vbc2 = vbc2
  let record = new Composition()
  record.layout = build.layout
  record.prompt = prompt
  globalValues.forEach((v: string, k: string) => { record.globals.set(k, v) })
  let bodiesBySlot = holeBodiesBySlot(build.kinds, holeBodies)
  for (let i = 0; i < build.kinds.length; i++) { record.blocks.push(new Block(build.kinds[i], baseValues[i], bodiesBySlot[i])) }
  build.composition = compositionToJson(record)
  return ''
}

/** Jev's values with every content field, list and hole at its default: the screen before the fill answers. */
async function defaultTextBuild(prompt: string, outcome: SectionPickOutcome, sections: SectionPick[],
    build: TemplateBuild): Promise<TemplateBuild | null> {
  let preview = new TemplateBuild()
  preview.action = BUILD_TEMPLATE
  preview.kinds = build.kinds
  preview.layout = build.layout
  preview.jevMs = build.jevMs
  // 'server' mode makes no call: it answers every field's fallback and the lists' fallback rows.
  let defaults = await fillSectionsContent(build.kinds, prompt, 'server')
  let globalValues: Map<string, string> = new Map<string, string>()
  outcome.globalValues.forEach((v: string, k: string) => { globalValues.set(k, v) })
  defaults.globalValues.forEach((v: string, k: string) => { globalValues.set(k, v) })
  let values = mergeHoleValues(sections.map((p: SectionPick): Map<string, string> => p.slotValues), defaults.instanceValues)
  let error = composeInto(preview, prompt, globalValues, values, values, new Map<string, string>())
  if (error.length > 0) { return null }
  preview.note = outcome.note + ' content=pending'
  preview.status = 'Composed ' + build.kinds.join('+') + ', filling in the text...'
  return preview
}

/** The screen already shown stays the result, with the timings of the run that failed after it. */
function keepPreview(build: TemplateBuild, preview: TemplateBuild, reason: string): TemplateBuild {
  preview.searchMs = build.searchMs
  preview.contentMs = build.contentMs
  preview.note = preview.note.replace(' content=pending', '') + ' ' + reason + '; kept the default text'
  preview.status = 'Composed ' + preview.kinds.join('+') + ' with its default text'
  return preview
}

function scratch(note: string, status: string, build: TemplateBuild): TemplateBuild {
  build.action = BUILD_SCRATCH
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
    isCancelled: () => boolean, onPreview?: (preview: TemplateBuild) => void): Promise<TemplateBuild> {
  let build = new TemplateBuild()
  let preview: TemplateBuild | null = null
  try {
    onStatus('Checking for a canned template...')
    let jevStart = Date.now()
    let outcome: SectionPickOutcome = await selectSections(prompt, settings.getSelectorKey())
    build.jevMs = Date.now() - jevStart
    if (isCancelled()) { build.action = BUILD_CANCELLED; return build }
    if (outcome.sections === null) {
      return scratch(outcome.note, '', build)
    }
    // Empty sections are dropped: the composition record keeps only blocks that exist, and the
    // numbers in the generated names follow the blocks that are really there.
    let sections = outcome.sections.filter((p: SectionPick): boolean => p.kind !== 'none')
    if (sections.length === 0) { return scratch(outcome.note, '', build) }
    for (let section of sections) { build.kinds.push(section.kind) }
    build.layout = outcome.layout

    // needs_real_data alone does not null outcome.sections -- it means this composition has to be
    // grounded in one real search before it is trusted. A trend_chart needs grounding whatever Jev
    // said: its gate is one probability on the whole request and can miss on an identical prompt
    // from one run to the next, and a chart of invented round numbers is never what a chart request
    // wants.
    let needsGrounding = outcome.needsRealData || build.kinds.indexOf('trend_chart') >= 0
    let canGround = needsGrounding && mode !== 'server' && settings.hasExaKey()
    if (needsGrounding && !canGround) {
      return scratch(outcome.note + ' (needs real data, no search available; generating normally)', '', build)
    }
    // Only a screen that will be the result is shown early: a `complete` base is handed to the model next.
    let willBeTemplate = !outcome.needsLogic && !sections.every((p: SectionPick): boolean => p.kind === 'actions')
    if (onPreview !== undefined && willBeTemplate) {
      preview = await defaultTextBuild(prompt, outcome, sections, build)
      if (isCancelled()) { build.action = BUILD_CANCELLED; return build }
      if (preview !== null) { onPreview(preview) }
    }
    let searchText = ''
    if (needsGrounding) {
      onStatus('Looking up real data...')
      let searchStart = Date.now()
      searchText = await webSearch(prompt)
      build.searchMs = Date.now() - searchStart
      if (isCancelled()) { build.action = BUILD_CANCELLED; return build }
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
    }
    let note = outcome.note + searchTag + (content.note.length > 0 ? ' ' + content.note : '')
    let shown = build.kinds.filter((k: string): boolean => k !== 'none').join('+')

    // Holes: function bodies the model writes for the chosen blocks (the filter's match rule), settled
    // against the compiler. Defaults apply when the model cannot or the mode has no model to ask.
    let baseValues = instanceValues
    let holeBodies: Map<string, string> = new Map<string, string>()
    if (holesOf(build.kinds).length > 0) {
      if (mode === 'deepseek') {
        onStatus('Writing the details...')
        let kinds = build.kinds
        let fill: HoleFill = await fillHoles(prompt, kinds,
          (system: string, user: string): Promise<string | null> => deepseek.extractTemplateContent(system, user, 500),
          (bodies: Map<string, string>): string => composeProgram(kinds, globalValues, mergeHoleValues(instanceValues, holeValues(kinds, bodies))))
        if (isCancelled()) { build.action = BUILD_CANCELLED; return build }
        holeBodies = fill.bodies
        instanceValues = mergeHoleValues(instanceValues, holeValues(kinds, fill.bodies))
        if (fill.note.length > 0) { note = note + ' ' + fill.note }
      } else {
        note = note + ' holes=default(' + mode + ')'
      }
    }
    let error = composeInto(build, prompt, globalValues, instanceValues, baseValues, holeBodies)
    if (error.length > 0) {
      if (preview !== null) { return keepPreview(build, preview, 'the filled screen ' + error) }
      return scratch('composed ' + shown + ' but it ' + error + '; generated normally',
        'Template pick ' + error.replace(/ \(.*$/, '') + ', generating normally...', build)
    }

    if (outcome.needsLogic) {
      build.action = BUILD_COMPLETE
      build.note = note
      build.status = 'Composed ' + shown + ', adding the logic the request needs...'
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
    build.note = note
    build.status = 'Composed ' + shown + ': ' + note.replace(' content:', ' | content:')
    return build
  } catch (e) {
    if (preview !== null) { return keepPreview(build, preview, 'template path failed (' + (e as Error).message + ')') }
    return scratch('template path failed (' + (e as Error).message + '); generated normally', '', build)
  }
}
