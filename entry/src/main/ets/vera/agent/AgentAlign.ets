/**
 * What the composition leaves for the model to write, offered once more to the catalogue first. The plan's ready needs, the
 * events no effect does and the items of "other" that the vocabulary lacks all end up in `custom`, and the model writes a
 * section for them; but a section of the catalogue may already do exactly that (a daily medicine reminder is `reminders`, a
 * single calendar event is `calendar_event`). One Jev question per such need -- a ready-made section of the list, or none --
 * and only what Jev finds no section for is left to be written.
 *
 * What stays for the model whatever Jev says: the person's own records (a section with content would make them up) and the
 * figures worked out by a formula the vocabulary lacks (they are the screen's own). A section Jev names that the screen
 * already has is not taken as covering the need: its slots here are the catalogue's defaults, and a need it would only
 * cover with a slot turned on would be lost. Switched by `--ps veraAlign` (setAlignEnabled); off, nothing here runs.
 */

import { Composition, SketchInput, READY_KINDS, JevAsk } from '../VeraCompose'
import { fragments, vetoes, FragmentSpec, VetoSpec } from '../VeraTemplates'

/** Sections a need that nothing else does may be given: the plan's ready kinds, and the two that do phone work no effect does. */
export const ALIGN_KINDS: string[] = READY_KINDS.concat(['reminders', 'calendar_event'])
/** Of those, the two that do phone work: their content is the person's own entry, never looked up. */
const PHONE_KINDS: string[] = ['reminders', 'calendar_event']
/** How sure Jev must be of a section for a need, as for a section's pick (VeraSectionCompose.ets). */
export const ALIGN_ABOVE: number = 0.5
/** The bar the catalogue gives its own needs_real_data question. */
const REAL_DATA_ABOVE: number = 0.35
const NONE: string = 'none'
/** The mark the composer puts on a need that is the person's own records (VeraCompose.ets's readComposition). */
export const OWN_MARK: string = ' -- these are the person\'s own'
const FIGURE_MARK: string = 'the figure "'

let alignEnabled: boolean = false
export function setAlignEnabled(on: boolean): void { alignEnabled = on }
export function alignIsEnabled(): boolean { return alignEnabled }

export class AlignedNeed {
  need: string = ''
  /** The section Jev named, '' for none or for less than ALIGN_ABOVE. */
  kind: string = ''
  p: number = 0
}

export class AlignResult {
  /** One entry for each need that was asked about. */
  asked: AlignedNeed[] = []
  /** The sections added to the composition, in order. */
  added: string[] = []
  /** The needs now done by those sections: no longer for the model to write. */
  taken: string[] = []
  /** Whether Jev says the added sections' content has to come from a search. */
  realData: boolean = false
  /** For the trace: what was asked and decided, '' when nothing was. */
  note: string = ''
  ms: number = 0
}

/** The needs of `custom` a section may do: not the person's own records, not a figure. */
export function alignCandidates(comp: Composition): string[] {
  return comp.custom.filter((need: string): boolean => need.indexOf(OWN_MARK) < 0 && !need.startsWith(FIGURE_MARK))
}

function criteriaOf(specs: FragmentSpec[]): Record<string, Object> {
  let out: Record<string, Object> = {}
  for (let spec of specs) { if (ALIGN_KINDS.indexOf(spec.kind) >= 0) { out[spec.kind] = spec.criteria } }
  out[NONE] = 'no listed part does it'
  return out
}

/** One batched Jev request: for each need a choice among the sections of ALIGN_KINDS or none, and whether the content must be real. */
export function buildAlignRequest(prompt: string, needs: string[]): string {
  let questions: Record<string, Object> = {}
  let criteria = criteriaOf(fragments())
  for (let i = 0; i < needs.length; i++) {
    let q: Record<string, Object> = {}
    q['type'] = 'choice'
    q['instructions'] = 'A person asked for an app. One thing it must do: "' + needs[i] + '". Which ready-made part of the screen does ' +
      'exactly that on its own, with nothing important missing? Answer none if no listed part does it.'
    q['criteria'] = criteria
    questions['need.' + i.toString()] = q
  }
  let real: VetoSpec | undefined = vetoes().find((v: VetoSpec): boolean => v.key === 'needs_real_data')
  if (real !== undefined) {
    let rq: Record<string, Object> = {}
    rq['type'] = 'choice'
    rq['instructions'] = real.instructions
    let rc: Record<string, Object> = {}
    real.criteria.forEach((text: string, key: string) => { rc[key] = text })
    rq['criteria'] = rc
    questions['real_data'] = rq
  }
  let body: Record<string, Object> = {}
  body['model'] = 'jev-latest'
  body['state'] = prompt
  body['questions'] = questions
  return JSON.stringify(body)
}

function answerOf(answers: Record<string, Object>, key: string): Record<string, Object> | null {
  let a = answers[key]
  return a === null || a === undefined ? null : a as Record<string, Object>
}

/** Jev's answers as one decision per need, in order; a need Jev did not answer, or is unsure of, has no section. */
export function readAlignment(body: string, needs: string[], result: AlignResult): void {
  let answers: Record<string, Object> = {}
  try {
    let found = (JSON.parse(body) as Record<string, Object>)['answers']
    if (found !== null && found !== undefined) { answers = found as Record<string, Object> }
  } catch (_e) {
    // No usable answer: nothing below is decided.
  }
  for (let i = 0; i < needs.length; i++) {
    let aligned = new AlignedNeed()
    aligned.need = needs[i]
    let a = answerOf(answers, 'need.' + i.toString())
    if (a !== null) {
      let choice = typeof a['choice'] === 'string' ? a['choice'] as string : ''
      aligned.p = typeof a['confidence'] === 'number' ? a['confidence'] as number : 1
      if (ALIGN_KINDS.indexOf(choice) >= 0 && aligned.p >= ALIGN_ABOVE) { aligned.kind = choice }
    }
    result.asked.push(aligned)
  }
  let real = answerOf(answers, 'real_data')
  if (real !== null) {
    let p = typeof real['confidence'] === 'number' ? real['confidence'] as number : 1
    result.realData = real['choice'] === 'true' && p >= REAL_DATA_ABOVE
  }
}

/**
 * Gives the composition the sections found: each new kind once, whatever number of needs it does, and takes those needs out
 * of what is left to write. A need whose section the screen already has stays, as the header says. Inputs the composer kept
 * only for the section the model was to write are left out when nothing is left to write: they would read nothing.
 */
export function applyAlignment(comp: Composition, result: AlignResult): void {
  for (let aligned of result.asked) {
    if (aligned.kind.length === 0) { continue }
    if (comp.blocks.indexOf(aligned.kind) >= 0 && result.added.indexOf(aligned.kind) < 0) { continue }
    if (result.added.indexOf(aligned.kind) < 0) {
      comp.blocks.push(aligned.kind)
      result.added.push(aligned.kind)
    }
    result.taken.push(aligned.need)
    comp.custom = comp.custom.filter((n: string): boolean => n !== aligned.need)
    comp.phoneNeeds = comp.phoneNeeds.filter((n: string): boolean => n !== aligned.need)
    comp.unboundNeeds = comp.unboundNeeds.filter((n: string): boolean => n !== aligned.need)
  }
  if (result.taken.length > 0 && comp.custom.length === 0 && comp.customReads.length > 0) {
    let kept = comp.inputs.filter((i: SketchInput): boolean => comp.customReads.indexOf(i.id) >= 0)
    if (kept.length > 0) {
      comp.dropped.push('input ' + kept.map((i: SketchInput): string => '"' + i.label + '"').join(', ') + ': a section does it')
      comp.inputs = comp.inputs.filter((i: SketchInput): boolean => comp.customReads.indexOf(i.id) < 0)
    }
    comp.customReads = []
  }
  // Only a section with content of its own is filled from a search.
  if (result.realData && result.added.some((k: string): boolean => PHONE_KINDS.indexOf(k) < 0)) { comp.realData = true }
}

/** Asks Jev about what is left to write and gives the composition the sections it finds. Never throws. */
export async function alignLeftovers(comp: Composition, prompt: string, askJev: JevAsk): Promise<AlignResult> {
  let result = new AlignResult()
  let needs = alignCandidates(comp)
  if (needs.length === 0) { return result }
  let started = Date.now()
  let body = ''
  try {
    body = await askJev(buildAlignRequest(prompt, needs))
  } catch (_e) {
    body = ''
  }
  result.ms = Date.now() - started
  if (body.length === 0) {
    result.note = '; align: Jev did not answer'
    return result
  }
  readAlignment(body, needs, result)
  applyAlignment(comp, result)
  result.note = '; align: ' + result.asked.map((a: AlignedNeed): string => a.kind.length > 0 ? a.kind + '@' + a.p.toFixed(2) : 'none').join(', ') +
    (result.added.length > 0 ? ' -> sections ' + result.added.join('+') : '')
  return result
}
