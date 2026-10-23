/**
 * The record of a composed screen, and structural edits made through it.
 *
 * A composition is what composeProgram needs and nothing more: the layout, the shared cosmetic
 * choices, and per block its kind, its cosmetic and content values and its hole bodies. It is kept
 * beside the program's code (Version.composition). "Add a filter", "remove the chart", "put the
 * summary on top" then change the record and rebuild the program through composeProgram, with no
 * model call for the structure; only an added block's text is asked for (fillSectionsContent).
 * A request that is not a structural change -- different text, different numbers, new behaviour --
 * is answered `none` by Jev and goes to the model's refine path as before.
 *
 * Hole bodies are stored without their //@hole markers, keyed by hole key, because the markers carry
 * the slot number and the slot number changes when blocks move.
 */

import http from '@ohos.net.http'
import hilog from '@ohos.hilog'
import { fragments, FragmentSpec } from './VeraTemplates'
import { specsOf, markedHole, readChoiceValue } from './VeraSectionCompose'
import { planFromBlocks, assemblePlan } from './ScreenPlan'
import { fillSectionsContent } from './VeraTemplateContent'
import { arrangeInLayout, LAYOUT_STACK } from './VeraLayouts'
import { compileVeraSource, CompileResult } from './VeraCompiler'
import { smokeRun } from './VeraSmoke'

const DOMAIN = 0x0000
const ENDPOINT: string = 'https://api.typesafe.ai/v1/systemone'
const MODEL: string = 'jev-latest'
const MAX_BLOCKS: number = 6
const EDIT_ABOVE: number = 0.6

export const OP_NONE: string = 'none'
export const OP_ADD: string = 'add_block'
export const OP_REMOVE: string = 'remove_block'
export const OP_REPLACE: string = 'replace_block'
export const OP_TOP: string = 'move_to_top'
export const OP_BOTTOM: string = 'move_to_bottom'

export class Block {
  kind: string
  /** Cosmetic and content tokens (containing "IDX") -> value. */
  values: Map<string, string>
  /** Hole key (no slot number) -> body, no markers. */
  holes: Map<string, string>
  constructor(kind: string, values: Map<string, string>, holes: Map<string, string>) {
    this.kind = kind
    this.values = values
    this.holes = holes
  }
}

export class Composition {
  layout: string = LAYOUT_STACK
  /** The request the screen was built from. */
  prompt: string = ''
  /** "__THEME__", "__HEADER_STYLE__", "__BANNER_SECTION__", "__TITLE__". */
  globals: Map<string, string> = new Map<string, string>()
  blocks: Block[] = []

  kinds(): string[] {
    let out: string[] = []
    for (let b of this.blocks) { out.push(b.kind) }
    return out
  }

  copy(): Composition {
    let c = new Composition()
    c.layout = this.layout
    c.prompt = this.prompt
    this.globals.forEach((v: string, k: string) => { c.globals.set(k, v) })
    for (let b of this.blocks) {
      let values: Map<string, string> = new Map<string, string>()
      b.values.forEach((v: string, k: string) => { values.set(k, v) })
      let holes: Map<string, string> = new Map<string, string>()
      b.holes.forEach((v: string, k: string) => { holes.set(k, v) })
      c.blocks.push(new Block(b.kind, values, holes))
    }
    return c
  }
}

function findSpec(kind: string): FragmentSpec | null {
  for (let spec of fragments()) { if (spec.kind === kind) { return spec } }
  return null
}

/** The program for a composition, through its plan (ScreenPlan.ets), as the Jev path assembles it. */
export function composeFrom(c: Composition): string {
  let kinds = c.kinds()
  let instanceValues: Map<string, string>[] = []
  for (let i = 0; i < c.blocks.length; i++) {
    let merged: Map<string, string> = new Map<string, string>()
    c.blocks[i].values.forEach((v: string, k: string) => { merged.set(k, v) })
    let spec = findSpec(c.blocks[i].kind)
    if (spec !== null) {
      for (let hole of spec.holes) {
        let body = c.blocks[i].holes.get(hole.key)
        if (body !== undefined) { merged.set(hole.token, markedHole(hole.key, (i + 1).toString(), body)) }
      }
    }
    instanceValues.push(merged)
  }
  return assemblePlan(planFromBlocks(c.prompt, c.layout, specsOf(kinds), c.globals, instanceValues))
}

function mapToObject(m: Map<string, string>): Record<string, Object> {
  let o: Record<string, Object> = {}
  m.forEach((v: string, k: string) => { o[k] = v })
  return o
}

function objectToMap(o: Object | undefined): Map<string, string> {
  let m: Map<string, string> = new Map<string, string>()
  if (o === undefined || o === null || typeof o !== 'object') { return m }
  let rec = o as Record<string, Object>
  let keys = Object.keys(rec)
  for (let k of keys) { if (typeof rec[k] === 'string') { m.set(k, rec[k] as string) } }
  return m
}

export function compositionToJson(c: Composition): string {
  let blocks: Object[] = []
  for (let b of c.blocks) {
    let o: Record<string, Object> = {}
    o['kind'] = b.kind
    o['values'] = mapToObject(b.values)
    o['holes'] = mapToObject(b.holes)
    blocks.push(o)
  }
  let root: Record<string, Object> = {}
  root['v'] = 1
  root['layout'] = c.layout
  root['prompt'] = c.prompt
  root['globals'] = mapToObject(c.globals)
  root['blocks'] = blocks
  return JSON.stringify(root)
}

/** null when the text is not a composition this version can rebuild (empty, damaged, an unknown kind). */
export function compositionFromJson(text: string): Composition | null {
  if (text.length === 0) { return null }
  try {
    let root = JSON.parse(text) as Record<string, Object>
    if ((root['v'] as number) !== 1) { return null }
    let c = new Composition()
    c.layout = (root['layout'] as string) || LAYOUT_STACK
    c.prompt = (root['prompt'] as string) || ''
    c.globals = objectToMap(root['globals'])
    let raw = root['blocks'] as Object[]
    for (let item of raw) {
      let o = item as Record<string, Object>
      let kind = o['kind'] as string
      if (findSpec(kind) === null) { return null }
      c.blocks.push(new Block(kind, objectToMap(o['values']), objectToMap(o['holes'])))
    }
    return c.blocks.length > 0 ? c : null
  } catch (_e) {
    return null
  }
}

export class CompositionEdit {
  op: string = OP_NONE
  /** An existing block's kind (remove, replace, move). */
  target: string = ''
  /** The kind to add, or to put in place of the target. */
  kind: string = ''
  note: string = ''
}

/** Defaults for a block that was not part of the screen when its text was filled: first cosmetic values, content fallbacks. */
function defaultValues(spec: FragmentSpec): Map<string, string> {
  let m: Map<string, string> = new Map<string, string>()
  for (let slot of spec.slots) { m.set(slot.token, slot.values[0]) }
  for (let field of spec.contentFields) { m.set(field.token, field.fallback) }
  return m
}

/**
 * The composition after an edit, or null when the edit cannot be applied (a kind that is already there,
 * too many blocks, a target that is not on the screen, a move inside a layout). `values` are the text
 * and cosmetic values of an added block; defaults when omitted. A layout whose slot rules the result
 * breaks is dropped back to the plain stack rather than refused: the person asked for the change, not
 * for the layout.
 */
export function applyEdit(c: Composition, edit: CompositionEdit, values: Map<string, string> | null = null): Composition | null {
  let out = c.copy()
  let kinds = out.kinds()
  if (edit.op === OP_ADD) {
    let spec = findSpec(edit.kind)
    if (spec === null || kinds.indexOf(edit.kind) >= 0 || kinds.length >= MAX_BLOCKS) { return null }
    out.blocks.push(new Block(edit.kind, values !== null ? values : defaultValues(spec), new Map<string, string>()))
  } else if (edit.op === OP_REMOVE) {
    let at = kinds.indexOf(edit.target)
    if (at < 0 || kinds.length <= 1) { return null }
    out.blocks.splice(at, 1)
  } else if (edit.op === OP_REPLACE) {
    let at = kinds.indexOf(edit.target)
    let spec = findSpec(edit.kind)
    if (at < 0 || spec === null || kinds.indexOf(edit.kind) >= 0) { return null }
    out.blocks[at] = new Block(edit.kind, values !== null ? values : defaultValues(spec), new Map<string, string>())
  } else if (edit.op === OP_TOP || edit.op === OP_BOTTOM) {
    let at = kinds.indexOf(edit.target)
    if (at < 0 || out.layout !== LAYOUT_STACK) { return null }
    let moved = out.blocks.splice(at, 1)[0]
    if (edit.op === OP_TOP) { out.blocks.unshift(moved) } else { out.blocks.push(moved) }
  } else {
    return null
  }
  if (out.layout !== LAYOUT_STACK) {
    let order = arrangeInLayout(out.layout, out.kinds())
    if (order === null) {
      out.layout = LAYOUT_STACK
    } else {
      let placed: Block[] = []
      for (let i of order) { placed.push(out.blocks[i]) }
      out.blocks = placed
    }
  }
  return out
}

// ---- Jev: which structural edit is this request? ----

function opCriteria(): Record<string, Object> {
  let m: Record<string, Object> = {}
  m[OP_ADD] = 'the request asks for a whole new part to be added to the screen, such as a filter, a chart, a summary or a list'
  m[OP_REMOVE] = 'the request asks for a whole part of the screen to be taken away'
  m[OP_REPLACE] = 'the request asks for one part of the screen to be swapped for a different kind of part, such as a list for a table'
  m[OP_TOP] = 'the request asks for a whole part to be moved above everything else'
  m[OP_BOTTOM] = 'the request asks for a whole part to be moved below everything else'
  m[OP_NONE] = 'the request changes the wording, numbers, items, look or behaviour of what is already there, or is anything else'
  return m
}

export function buildEditRequest(request: string, c: Composition): string {
  let specs = fragments()
  let present: string[] = c.kinds()
  let kindCriteria: Record<string, Object> = {}
  let targetCriteria: Record<string, Object> = {}
  for (let spec of specs) {
    kindCriteria[spec.kind] = spec.criteria
    if (present.indexOf(spec.kind) >= 0) { targetCriteria[spec.kind] = spec.criteria }
  }
  kindCriteria['none'] = 'no new part is needed'
  targetCriteria['none'] = 'the request does not point at one of the existing parts'
  let opQuestion: Record<string, Object> = {}
  opQuestion['type'] = 'choice'
  opQuestion['instructions'] = 'The person is changing a screen that is already built. Does the change add, remove, replace or move a whole part of the screen? ' +
    'Answer none when it only changes what an existing part says or does.'
  opQuestion['criteria'] = opCriteria()
  let targetQuestion: Record<string, Object> = {}
  targetQuestion['type'] = 'choice'
  targetQuestion['instructions'] = 'Which existing part of the screen does the change point at (the part to remove, replace or move)?'
  targetQuestion['criteria'] = targetCriteria
  let kindQuestion: Record<string, Object> = {}
  kindQuestion['type'] = 'choice'
  kindQuestion['instructions'] = 'Which kind of part should be added, or put in place of the one being replaced?'
  kindQuestion['criteria'] = kindCriteria
  let questions: Record<string, Object> = {}
  questions['edit.op'] = opQuestion
  questions['edit.target'] = targetQuestion
  questions['edit.kind'] = kindQuestion
  let body: Record<string, Object> = {}
  body['model'] = MODEL
  body['state'] = request
  body['questions'] = questions
  return JSON.stringify(body)
}

/** Jev's answer as an edit; `none` whenever any part of it is missing, unsure or inconsistent with the screen. Never throws. */
export function readEditAnswer(body: string, c: Composition): CompositionEdit {
  let edit = new CompositionEdit()
  let answers: Record<string, Object> = {}
  try {
    let parsed = JSON.parse(body) as Record<string, Object>
    let found = parsed['answers']
    if (found === null || found === undefined) { edit.note = 'edit=none(no answers)'; return edit }
    answers = found as Record<string, Object>
  } catch (_e) {
    edit.note = 'edit=none(unreadable)'
    return edit
  }
  let present = c.kinds()
  let allKinds: string[] = ['none']
  for (let spec of fragments()) { allKinds.push(spec.kind) }
  let op = readChoiceValue(answers, 'edit.op', [OP_NONE, OP_ADD, OP_REMOVE, OP_REPLACE, OP_TOP, OP_BOTTOM], EDIT_ABOVE, OP_NONE)
  let target = readChoiceValue(answers, 'edit.target', present.concat(['none']), EDIT_ABOVE, 'none')
  let kind = readChoiceValue(answers, 'edit.kind', allKinds, EDIT_ABOVE, 'none')
  let needsTarget = op === OP_REMOVE || op === OP_REPLACE || op === OP_TOP || op === OP_BOTTOM
  let needsKind = op === OP_ADD || op === OP_REPLACE
  if (op === OP_NONE || (needsTarget && target === 'none') || (needsKind && kind === 'none')) {
    edit.note = 'edit=none' + (op !== OP_NONE ? '(' + op + ' unsure)' : '')
    return edit
  }
  edit.op = op
  edit.target = needsTarget ? target : ''
  edit.kind = needsKind ? kind : ''
  edit.note = 'edit=' + op + (edit.target.length > 0 ? ' target=' + edit.target : '') + (edit.kind.length > 0 ? ' kind=' + edit.kind : '')
  return edit
}

/** Asks Jev. Never throws; any failure is an edit of `none`, which sends the request to the model's refine path. */
export async function selectEdit(request: string, c: Composition, apiKey: string): Promise<CompositionEdit> {
  let none = new CompositionEdit()
  if (apiKey.length === 0 || request.trim().length === 0) { none.note = 'edit=none(no key)'; return none }
  let client = http.createHttp()
  try {
    let headers: Record<string, string> = {}
    headers['Content-Type'] = 'application/json'
    headers['Authorization'] = 'Bearer ' + apiKey
    let response = await client.request(ENDPOINT, {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: buildEditRequest(request, c),
      connectTimeout: 5000,
      readTimeout: 15000
    })
    if ((response.responseCode as number) !== 200) { none.note = 'edit=none(selector ' + (response.responseCode as number).toString() + ')'; return none }
    let edit = readEditAnswer(response.result as string, c)
    hilog.info(DOMAIN, 'VERA', 'VERA-EDIT ' + edit.note)
    return edit
  } catch (e) {
    hilog.warn(DOMAIN, 'VERA', 'VERA-EDIT failed: ' + (e as Error).message)
    none.note = 'edit=none(selector unreachable)'
    return none
  } finally {
    client.destroy()
  }
}

export type EditSelector = (request: string, c: Composition) => Promise<CompositionEdit>

export class EditResult {
  /** True when the screen was rebuilt; false sends the request to the model's refine path. */
  applied: boolean = false
  note: string = ''
  composition: Composition | null = null
  source: string = ''
  vbc2: string = ''
}

/**
 * One structural edit end to end: Jev's choice, the new composition, text for an added block, rebuild,
 * compile and one run. Never throws; `applied` is false whenever any step does not hold, with the
 * reason in `note`, and the caller then refines with the model as it always did.
 */
export async function editComposition(request: string, c: Composition, mode: string, select: EditSelector): Promise<EditResult> {
  let result = new EditResult()
  try {
    let edit = await select(request, c)
    result.note = edit.note
    if (edit.op === OP_NONE) { return result }
    let values: Map<string, string> | null = null
    if (edit.kind.length > 0) {
      let spec = findSpec(edit.kind)
      if (spec === null) { return result }
      values = defaultValues(spec)
      if (mode === 'deepseek') {
        let fill = await fillSectionsContent([edit.kind], request, mode)
        let filled = fill.instanceValues[0]
        if (filled !== undefined) { filled.forEach((v: string, k: string) => { values!.set(k, v) }) }
        result.note = result.note + ' ' + fill.note
      }
    }
    let next = applyEdit(c, edit, values)
    if (next === null) { result.note = result.note + ' (cannot be applied)'; return result }
    let source = composeFrom(next)
    let compiled: CompileResult
    try {
      compiled = compileVeraSource(source)
    } catch (_e) {
      result.note = result.note + ' (did not compile)'
      return result
    }
    let problem = smokeRun(compiled)
    if (problem.length > 0) { result.note = result.note + ' (did not run: ' + problem + ')'; return result }
    result.applied = true
    result.composition = next
    result.source = source
    result.vbc2 = compiled.vbc2
    return result
  } catch (e) {
    result.note = result.note + ' (failed: ' + (e as Error).message + ')'
    return result
  }
}
