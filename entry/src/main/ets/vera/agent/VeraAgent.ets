/**
 * The agent: the slow path for a request the blocks do not serve. It plans the screen (DeepSeek, no thinking,
 * a JSON plan), has Jev choose how each part of the plan is built, assembles the program and checks it --
 * compiled, then run once with every handler tapped (VeraSmoke.ets) -- before anything is shown.
 *
 * The plan is VeraCompose.ets's sketch; Jev's choices bind each of its parts, and pick a section of the catalogue
 * (VeraTemplates.ets) for each need the plan says one handles whole, whose content and holes the host fills. What
 * neither does is one custom section the model writes (AgentCustom.ets). Callers see only runAgent and AgentResult,
 * so those can change behind it. Never throws.
 */

import { AgentHost } from './AgentHost'
import { BlockRequest, BlockFill } from '../SectionFill'
import { CustomResult } from './AgentCustom'
import { writeHole } from './AgentHole'
import { AgentQuestion, Asked, askBlocking } from './AgentQuestions'
import { composeWith, composePlanEnabled, provisionalProgram, sketchPlan, assembleProgram, screenPlan, partCount, customInputs, ComposeResult, Composition, Sketch } from '../VeraCompose'
import { ScreenPlan, assemblePlan } from '../ScreenPlan'
import { compileVeraSource } from '../VeraCompiler'
import { Repaired, settleProgram } from './AgentRepair'
import { AlignResult, alignIsEnabled, alignLeftovers } from './AgentAlign'
import { Composition as ScreenRecord, compositionFromPlan, rebuilds } from '../VeraComposition'
import { holeBodiesBySlot } from '../VeraHoles'

export class AgentRequest {
  /** What to build, in the person's words (or the chat's request for them). */
  prompt: string = ''
  /** A widget inside a chat reply rather than a whole screen. */
  widget: boolean = false
}

export class AgentResult {
  /** The checked program; empty when the agent could not build one. */
  source: string = ''
  vbc2: string = ''
  /** One line for the trace: what was built, or why not. */
  note: string = ''
  /** Why the assembled program was not served: compile or runtime diagnostics, '' when it was or when nothing was assembled. */
  errors: string = ''
  /** The plan and Jev's answers, with their timings. */
  composed: ComposeResult = new ComposeResult()
  /** The plan in words for a generation to keep to, '' when there is none or plans are off. */
  plan: string = ''
  /** The catalogue's sections on the screen, in order; empty when it has none. */
  blocks: string[] = []
  /** What filling them did, when there were any. */
  blockFill: BlockFill | null = null
  /** What was left for the model to write that sections of the catalogue were then found for (AgentAlign.ets); null when not asked. */
  align: AlignResult | null = null
  /** What writing the custom section did, when the composition needed one. */
  custom: CustomResult | null = null
  /** What repairing the assembled program by edits did, when it did not compile or run; null otherwise. */
  repair: Repaired | null = null
  /** What writing the whole screen as one hole did, when nothing narrower served (agent/VeraBuildRoute.ets). */
  whole: CustomResult | null = null
  /** The questions put to the person, with their answers. */
  asked: Asked[] = []
  /** The screen's plan (ScreenPlan.ets) as far as it got: every slot and what fills it; null when Jev chose nothing. */
  screen: ScreenPlan | null = null
  /** The record of the served screen (VeraComposition.ets), for edits that change its structure; null when there is none that rebuilds this very program. */
  record: ScreenRecord | null = null
  firstPreviewMs: number = 0
  previews: number = 0
  checkMs: number = 0
  ms: number = 0
}

/**
 * The record of the screen the agent served: its plan's components in order, the catalogue's blocks with the values and hole
 * bodies they were filled with. Null unless it rebuilds exactly the served program, so a screen no edit can be made to
 * through the record is never claimed to have one.
 */
function recordOf(result: AgentResult, comp: Composition, prompt: string): ScreenRecord | null {
  if (result.screen === null) { return null }
  let base: Map<string, string>[] = []
  let holes: Map<string, string>[] = []
  let fill = result.blockFill
  if (fill !== null && comp.blocks.length > 0) {
    let kinds: string[] = []
    let offset = partCount(comp)
    for (let i = 0; i < offset; i++) { kinds.push('none') }
    kinds = kinds.concat(comp.blocks)
    base = fill.baseValues
    holes = holeBodiesBySlot(kinds, fill.holeBodies).slice(offset)
  }
  let record = compositionFromPlan(result.screen!, prompt, base, holes)
  return rebuilds(record, result.source) ? record : null
}

export async function runAgent(request: AgentRequest, host: AgentHost): Promise<AgentResult> {
  let result = new AgentResult()
  let started = Date.now()
  host.status(request.widget ? 'Sketching the widget...' : 'Composing...')
  let composed = await composeWith(request.prompt, host.askPlan, host.askJev, (partial: Sketch): void => {
    if (host.cancelled()) { return }
    let source = provisionalProgram(partial, request.widget)
    if (source.length === 0) { return }
    try {
      host.preview(compileVeraSource(source).vbc2)
      result.previews++
      if (result.firstPreviewMs === 0) { result.firstPreviewMs = Date.now() - started }
    } catch (_e) {
      // A partial plan that does not compile is skipped; the next one replaces it.
    }
  }, request.widget, async (sketch: Sketch): Promise<string> => {
    if (host.cancelled()) { return '' }
    let settled = await askBlocking(request.prompt, sketch.questions, host.askJev, (q: AgentQuestion): Promise<number | null> => {
      host.status('Waiting for your answer...')
      return host.ask(q)
    }, result.asked)
    if (settled.length > 0) { host.status('Planning again with your answer...') }
    return settled
  })
  result.composed = composed
  result.note = composed.note
  result.plan = composed.parsed !== null && composePlanEnabled() ? sketchPlan(composed.parsed!) : ''
  // What the composition leaves to be written is first offered to the catalogue: a section may do exactly that.
  if (composed.composition !== null && alignIsEnabled() && !host.cancelled()) {
    host.status('Looking for ready-made parts...')
    let aligned = await alignLeftovers(composed.composition!, request.prompt, host.askJev)
    if (aligned.asked.length > 0 || aligned.note.length > 0) {
      result.align = aligned
      result.note += aligned.note
    }
  }
  // Sections of the catalogue: their content written for the request (from a search when it needs real data), and
  // their holes, before the program is assembled.
  if (composed.composition !== null && !host.cancelled()) {
    let comp: Composition = composed.composition!
    let values: Map<string, string>[] = []
    let ready = true
    if (comp.blocks.length > 0) {
      host.status(comp.realData ? 'Looking up real data...' : 'Filling in the sections...')
      let blocks = new BlockRequest()
      blocks.kinds = comp.blocks
      blocks.prompt = request.prompt
      blocks.realData = comp.realData
      blocks.offset = partCount(comp)
      blocks.compose = (filled: Map<string, string>[], _globals: Map<string, string>): string => assembleProgram(comp, filled)
      let fill = await host.fillBlocks(blocks)
      result.blocks = comp.blocks
      result.blockFill = fill
      result.note += '; ' + (fill.failed.length > 0 ? fill.failed : fill.note)
      ready = fill.failed.length === 0
      values = fill.values
    }
    // The plan, and what nothing ready does in it: one section the model writes into the program the rest makes.
    let plan = screenPlan(comp, values)
    result.screen = plan
    if (ready && plan.toWrite().length > 0 && !host.cancelled()) {
      host.status('Writing the rest...')
      let written = await writeHole(plan, request.prompt, customInputs(comp), host)
      result.custom = written
      ready = plan.toWrite().length === 0
      if (written !== null) {
        result.note += '; ' + (written.section !== null ? 'custom section in ' + written.attempts.toString() + ' attempt(s)' :
          'reported on the screen (' + written.failed + ')')
      }
    }
    if (ready) { composed.source = assemblePlan(plan) }
  }
  if (composed.source.length > 0) {
    let settled = await settleProgram(composed.source, request.prompt, host)
    result.checkMs = settled.checkMs
    result.repair = settled.repair
    result.errors = settled.errors
    result.note += settled.note
    composed.source = settled.source
    if (settled.errors.length === 0) {
      result.source = settled.source
      result.vbc2 = settled.vbc2
      // A program the repair edited is no longer the plan's: there is no record of it.
      if (settled.repair === null && composed.composition !== null) { result.record = recordOf(result, composed.composition!, request.prompt) }
    } else {
      result.note += '; ' + settled.errors
    }
  }
  result.ms = Date.now() - started
  return result
}
