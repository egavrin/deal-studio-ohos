/**
 * Which builder makes a new screen, the same for the Generate screen and the chat: the blocks
 * (VeraTemplatePipeline.ets) and the agent (VeraAgent.ets), in the order set below. When neither serves, the
 * screen is not built and the outcome says why: the route itself never generates from scratch. What happens then is
 * the caller's: the Generate screen has the model write the whole program, the chat shows the reason. The caller
 * turns the outcome into its own state; this file decides nothing about pages.
 *
 * A composition the blocks hand on to be completed -- the right sections, but the request needs more than they do -- is
 * kept until the agent has had its turn, so the agent is always tried first. Then its layout stays and what it lacks is
 * written into it as one section (AgentHole.ets), as the agent fills what nothing ready does; only when that cannot be
 * done does the route go on to the whole screen below. What the agent's plan asks the phone to do and could not bind is
 * something the blocks' layout lacks too: a pick of sections that does not do it is not a finished screen.
 *
 * When no part of the screen can be built from what is ready, the hole widens to the whole screen: the model writes it
 * as one section against the agent's plan of it, looked up and checked the same way (AgentHole.ets), and Jev reads it
 * against everything the plan says the screen does. Only then does the route return OUTCOME_COMPLETE (the blocks' base,
 * for the caller's model to finish) or OUTCOME_NOT_BUILT. Never throws.
 */

import { AgentHost } from './AgentHost'
import { AgentRequest, AgentResult, runAgent } from './VeraAgent'
import { CustomResult } from './AgentCustom'
import { writeHole } from './AgentHole'
import { buildFromTemplates, markComplete, TemplateBuild, BUILD_TEMPLATE, BUILD_COMPLETE, BUILD_CANCELLED } from '../VeraTemplatePipeline'
import { assemblePlan, PlanSlot, ScreenPlan } from '../ScreenPlan'
import { wholeScreenPlan, sketchConstants } from '../VeraCompose'
import { settleProgram } from './AgentRepair'

/** The agent's program is the result. */
export const OUTCOME_AGENT: string = 'agent'
/** The blocks' program is the result. */
export const OUTCOME_TEMPLATE: string = 'template'
/** The blocks' program is the base for the model to finish (`blocks.source`), and the fallback if it cannot. */
export const OUTCOME_COMPLETE: string = 'complete'
/**
 * Nothing served: the screen is not built, and `reason` says why. The route does not generate: the chat shows the
 * reason as an error, and the Generate screen has the model write the whole program (GeneratePage.ets).
 */
export const OUTCOME_NOT_BUILT: string = 'not-built'
export const OUTCOME_CANCELLED: string = 'cancelled'

export const ORDER_AGENT_FIRST: string = 'agent-first'
export const ORDER_BLOCKS_FIRST: string = 'blocks-first'

/** The whole screen as one hole before any generation; `--ps veraWhole 0` turns it off, for comparison. */
let wholeScreen: boolean = true
export function setWholeScreenEnabled(on: boolean): void { wholeScreen = on }
export function wholeScreenEnabled(): boolean { return wholeScreen }

/** Agent first until the blocks' pick is cheap enough to put in front of every request; `--ps veraOrder blocks-first` swaps them. */
let order: string = ORDER_AGENT_FIRST
export function setRouteOrder(next: string): void { order = next === ORDER_BLOCKS_FIRST ? ORDER_BLOCKS_FIRST : ORDER_AGENT_FIRST }
export function routeOrder(): string { return order }

export class RouteRequest {
  /** What the agent builds from; null when the agent is not to be tried. */
  agent: AgentRequest | null = null
  /** What the blocks build from; '' when they are not to be tried. */
  blocksPrompt: string = ''
  /** The Generate screen's generation mode; the chat is always 'deepseek'. */
  mode: string = 'deepseek'
}

export class RouteOutcome {
  kind: string = OUTCOME_NOT_BUILT
  /** The agent's answer when it ran, served or not. */
  agent: AgentResult | null = null
  /** The blocks' answer when they ran, served or not. */
  blocks: TemplateBuild | null = null
  /** Why nothing was built, for the person to see: what the agent and the blocks said; '' when something was. */
  reason: string = ''
  /** What writing the blocks' missing part did, when the blocks asked for one; null otherwise. */
  hole: CustomResult | null = null
}

/**
 * What the agent's plan asks the phone to do that it could not bind, as slots of the blocks' plan to be written: the
 * sections Jev picked do not do it either. A finished template that lacks it is then one to be completed.
 */
function addAgentNeeds(build: TemplateBuild, agent: AgentResult | null): void {
  if (agent === null || build.plan === null) { return }
  let plan = build.plan!
  let needs = agent.composed.unboundNeeds
  let added: string[] = []
  for (let i = 0; i < needs.length; i++) {
    let id = 'asked.' + i.toString()
    if (plan.slots.some((s: PlanSlot): boolean => s.id === id)) { continue }
    plan.addToWrite(id, needs[i], true)
    added.push(needs[i])
  }
  if (added.length > 0 && build.action === BUILD_TEMPLATE) {
    markComplete(build, build.note + '; the plan also asks: ' + added.join('; '),
      'Composed ' + build.kinds.join('+') + ', adding what the request asks the phone to do...')
  }
}

/**
 * The whole screen as one hole, against the agent's sketch of it (or the request alone when there is none): true when
 * it served, with the agent's result then holding the program.
 */
async function writeWholeScreen(request: RouteRequest, host: AgentHost, outcome: RouteOutcome): Promise<boolean> {
  let agent = outcome.agent
  if (!wholeScreen || request.agent === null || agent === null || request.mode !== 'deepseek') { return false }
  let prompt = request.agent!.prompt
  let sketch = agent!.composed.parsed
  let plan: ScreenPlan
  if (sketch !== null) {
    plan = wholeScreenPlan(sketch!, request.agent!.widget)
  } else {
    plan = new ScreenPlan()
    plan.widget = request.agent!.widget
    plan.globals.set('__HEADER_STYLE__', 'none')
    plan.addToWrite('screen.0', 'everything the request asks', true)
  }
  plan.prompt = prompt
  host.status('Writing the whole screen...')
  let facts: string[] = sketch !== null ? sketchConstants(sketch!) : []
  if (plan.widget) { facts.push('This is a small widget inside a chat reply: no header of its own, at most two sections, compact') }
  let written = await writeHole(plan, prompt, [], host, facts)
  agent!.whole = written
  if (written === null || written.section === null) {
    agent!.note += '; whole screen: ' + (written !== null ? written.failed : 'nothing to write')
    return false
  }
  let settled = await settleProgram(assemblePlan(plan), prompt, host)
  agent!.checkMs += settled.checkMs
  if (settled.repair !== null) { agent!.repair = settled.repair }
  agent!.note += settled.note
  if (settled.errors.length > 0) {
    agent!.note += '; whole screen: ' + settled.errors
    return false
  }
  agent!.vbc2 = settled.vbc2
  agent!.source = settled.source
  agent!.composed.source = settled.source
  agent!.errors = ''
  agent!.screen = plan
  agent!.note += '; whole screen written in ' + written.attempts.toString() + ' attempt(s)'
  return true
}

/**
 * The blocks' layout with what it lacks written into it: true when the program is now whole, and `build` then holds
 * it as a finished template; false leaves `build` as it was.
 */
async function finishBlocks(build: TemplateBuild, prompt: string, host: AgentHost, outcome: RouteOutcome): Promise<boolean> {
  let plan = build.plan
  if (plan === null || plan.toWrite().length === 0) { return false }
  host.status('Writing what the sections do not do...')
  let written = await writeHole(plan, prompt, [], host)
  outcome.hole = written
  if (written === null || plan.toWrite().length > 0) {
    build.note += '; ' + (written !== null ? written.failed : 'nothing to write')
    return false
  }
  let settled = await settleProgram(assemblePlan(plan), prompt, host)
  build.note += settled.note
  if (settled.errors.length > 0) {
    build.note += '; written section: ' + settled.errors
    return false
  }
  build.vbc2 = settled.vbc2
  build.source = settled.source
  build.action = BUILD_TEMPLATE
  // The composition record has no place for a written section: a structural edit would drop it, so there is none.
  build.composition = ''
  build.note += written.section !== null ? '; written section in ' + written.attempts.toString() + ' attempt(s)' :
    '; reported on the screen (' + written.failed + ')'
  build.status = 'Composed ' + build.kinds.join('+') + (written.section !== null ? ' with a section written for the rest' :
    ', with a notice for what it cannot do')
  return true
}

export async function buildScreen(request: RouteRequest, host: AgentHost): Promise<RouteOutcome> {
  let outcome = new RouteOutcome()
  let steps: string[] = order === ORDER_BLOCKS_FIRST ? ['blocks', 'agent'] : ['agent', 'blocks']
  for (let step of steps) {
    if (host.cancelled()) { outcome.kind = OUTCOME_CANCELLED; return outcome }
    if (step === 'agent' && request.agent !== null) {
      let result = await runAgent(request.agent!, host)
      outcome.agent = result
      if (host.cancelled()) { outcome.kind = OUTCOME_CANCELLED; return outcome }
      if (result.vbc2.length > 0) { outcome.kind = OUTCOME_AGENT; return outcome }
    }
    if (step === 'blocks' && request.blocksPrompt.length > 0) {
      let build = await buildFromTemplates(request.blocksPrompt, request.mode, host.status, host.cancelled)
      outcome.blocks = build
      if (build.action === BUILD_CANCELLED) { outcome.kind = OUTCOME_CANCELLED; return outcome }
      addAgentNeeds(build, outcome.agent)
      if (build.action === BUILD_TEMPLATE) { outcome.kind = OUTCOME_TEMPLATE; return outcome }
    }
  }
  if (outcome.blocks !== null && outcome.blocks!.action === BUILD_COMPLETE) {
    addAgentNeeds(outcome.blocks!, outcome.agent)
    // The section is DeepSeek's to write; another generation mode finishes the program its own way.
    if (request.mode === 'deepseek' && await finishBlocks(outcome.blocks!, request.blocksPrompt, host, outcome)) {
      outcome.kind = host.cancelled() ? OUTCOME_CANCELLED : OUTCOME_TEMPLATE
      return outcome
    }
    if (host.cancelled()) { outcome.kind = OUTCOME_CANCELLED; return outcome }
  }
  if (await writeWholeScreen(request, host, outcome)) {
    outcome.kind = host.cancelled() ? OUTCOME_CANCELLED : OUTCOME_AGENT
    return outcome
  }
  if (host.cancelled()) { outcome.kind = OUTCOME_CANCELLED; return outcome }
  if (outcome.blocks !== null && outcome.blocks!.action === BUILD_COMPLETE) {
    outcome.kind = OUTCOME_COMPLETE
    return outcome
  }
  outcome.kind = OUTCOME_NOT_BUILT
  outcome.reason = notBuiltReason(outcome)
  return outcome
}

/** What the agent and the blocks said, for a screen neither built. */
function notBuiltReason(outcome: RouteOutcome): string {
  let parts: string[] = []
  if (outcome.agent !== null) { parts.push('agent: ' + (outcome.agent!.note.length > 0 ? outcome.agent!.note : 'no answer')) }
  if (outcome.blocks !== null) { parts.push('blocks: ' + (outcome.blocks!.note.length > 0 ? outcome.blocks!.note : outcome.blocks!.action)) }
  return parts.length > 0 ? parts.join(' | ') : 'nothing was tried'
}
