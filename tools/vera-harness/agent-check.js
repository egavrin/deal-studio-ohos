// agent/VeraAgent.ets and agent/VeraBuildRoute.ets without the network: a host that replays recorded sketches and Jev
// answers (tools/vera-harness/compose/) through runAgent -- streamed plan, previews, assembly, compile, first run -- and
// the route's order between the agent and the blocks. The blocks have no network here, so they answer scratch, except
// where a canned section pick stands in for Jev's.
'use strict'
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const {loadVera} = require('./source-loader')
const {AgentHost} = loadVera('agent/AgentHost')
const {AgentRequest, runAgent} = loadVera('agent/VeraAgent')
const route = loadVera('agent/VeraBuildRoute')

const fixture = (label, file) => fs.readFileSync(path.join(__dirname, 'compose', label, file), 'utf8')

// The sketch arrives in pieces, as DeepSeek streams it; Jev answers with the recorded body.
function replayHost(label, {jev = fixture(label, 'jev-answer.json'), cancelled = () => false} = {}) {
  const host = new AgentHost()
  const seen = {status: [], previews: 0, plans: 0, jev: 0}
  host.askPlan = async (system, user, onText) => {
    seen.plans++
    assert.match(system, /JSON sketch/)
    const text = fixture(label, 'sketch.json')
    for (let i = 40; i < text.length; i += 40) onText(text.slice(0, i))
    return text
  }
  host.askJev = async body => { seen.jev++; JSON.parse(body); return jev }
  host.status = s => seen.status.push(s)
  host.preview = vbc2 => { assert.ok(vbc2.length > 0); seen.previews++ }
  host.cancelled = cancelled
  return {host, seen}
}

const request = (prompt, widget = false) => Object.assign(new AgentRequest(), {prompt, widget})

;(async () => {
  // Served: a checked program, previews while the plan streamed, and the plan in words for a generation.
  {
    const {host, seen} = replayHost('tip')
    const r = await runAgent(request('tip calculator'), host)
    assert.ok(r.vbc2.length > 0, r.note)
    assert.equal(r.errors, '')
    assert.ok(r.source.includes('function view('))
    assert.ok(seen.previews > 0 && r.previews === seen.previews && r.firstPreviewMs >= 0)
    assert.equal(seen.plans, 1)
    assert.equal(seen.jev, 1)
    assert.deepEqual(seen.status, ['Composing...'])
    assert.match(r.plan, /^A sketch of this app/)
    assert.match(r.note, /^composed: /)
  }
  // A widget says so in its status and is assembled as one.
  {
    const {host, seen} = replayHost('egg')
    const r = await runAgent(request('egg timer', true), host)
    assert.ok(r.vbc2.length > 0, r.note)
    assert.deepEqual(seen.status, ['Sketching the widget...'])
  }
  // Jev does not answer, twice: nothing served by the agent, but the plan is kept for the route's wider holes.
  {
    const {host, seen} = replayHost('tip', {jev: ''})
    const r = await runAgent(request('tip calculator'), host)
    assert.equal(r.vbc2, '')
    assert.equal(r.note, 'Jev did not answer twice')
    assert.equal(seen.jev, 2)
    assert.match(r.plan, /^A sketch of this app/)
  }
  // Jev answers the second time: served.
  {
    const {host} = replayHost('tip')
    const answer = host.askJev
    let calls = 0
    host.askJev = async body => ++calls === 1 ? '' : answer(body)
    const r = await runAgent(request('tip calculator'), host)
    assert.ok(r.vbc2.length > 0, r.note)
    assert.equal(calls, 2)
  }
  // A plan that cannot be used is asked for again with what was wrong quoted, then once with thinking on.
  {
    const {host} = replayHost('tip')
    const good = fixture('tip', 'sketch.json')
    const asks = []
    const replies = ['not json at all', null, good]
    host.askPlan = async (system, user, onText, think) => { asks.push({user, think}); return replies.shift() }
    const r = await runAgent(request('tip calculator'), host)
    assert.ok(r.vbc2.length > 0, r.note)
    assert.equal(r.composed.planTries, 3)
    assert.deepEqual(asks.map(a => a.think), [false, false, true])
    assert.match(asks[1].user, /could not be used: it was not one JSON object in the form asked for: not json at all/)
    assert.match(asks[2].user, /could not be used: there was no answer/)
    const none = replayHost('tip').host
    none.askPlan = async () => 'nope'
    const r2 = await runAgent(request('tip calculator'), none)
    assert.equal(r2.note, 'no usable sketch after 3 tries')
  }

  // A need the plan says a ready-made section handles: Jev's section joins the composition's own parts, its content
  // filled by the host (here the catalogue's defaults), and the program is served. Sections alone make a screen too.
  for (const [label, kind, own] of [['sections-tipping', 'key_facts', true], ['sections-beach', 'checklist', false]]) {
    const {host} = replayHost(label)
    let asked = null
    host.fillBlocks = async request => { asked = request; return loadVera('agent/AgentHost').defaultBlockFill(request) }
    const r = await runAgent(request(label), host)
    assert.ok(r.vbc2.length > 0, label + ': ' + r.note)
    assert.deepEqual(r.blocks, [kind])
    assert.deepEqual(asked.kinds, [kind])
    assert.ok(asked.offset > 0)
    assert.ok(asked.compose(r.blockFill.values).includes('function view('))
    assert.match(r.note, new RegExp('sections ' + kind))
    assert.equal(/composed: 0 inputs/.test(r.note), !own, label)
  }
  // Real data with no search: the host refuses the sections, and nothing is served.
  {
    const {host} = replayHost('sections-tipping')
    host.fillBlocks = async () => Object.assign(new (loadVera('agent/AgentHost').BlockFill)(), {failed: 'sections need real data and no search is available'})
    const r = await runAgent(request('tipping'), host)
    assert.equal(r.vbc2, '')
    assert.match(r.note, /no search is available/)
  }

  // The custom section: what nothing else does, written as one block into the program the rest makes, checked like
  // any block, the failing lines quoted back for a repair; a phone call it makes up, or an answer it cannot give, is
  // never served.
  {
    const {CustomRequest, writeSection, parseSection} = loadVera('agent/AgentCustom')
    const c = loadVera('VeraCompose')
    const comp = c.readComposition(fixture('tip', 'jev-answer.json'), c.parseSketch(fixture('tip', 'sketch.json')))
    const section = (functions, view) => '<classes>\n</classes>\n<fields>\nc_count: number = 0\n</fields>\n<functions>\n' + functions +
      '\n</functions>\n<view>\n' + view + '\n</view>'
    const good = section('function c_bump(state: AppState, value: number): AppState {\n  return {c_count: state.c_count + 1__PASSTHROUGH__};\n}',
      'sections.push(ui.Section("content", "", "", [ui.Button("primary", "Count " + ui.numberToString(state.c_count), "c_bump", 0, true)]));')
    const broken = good.replace('state.c_count + 1', 'state.c_cuont + 1')
    const asks = []
    const run = async replies => {
      const request = Object.assign(new CustomRequest(), {needs: ['a counter'], prompt: 'tip calculator with a counter',
        compose: s => c.assembleProgram(comp, [], s)})
      asks.length = 0
      return writeSection(request, 'LANGUAGE', async (system, user, budget, think) => { asks.push({system, user, budget, think}); return replies.shift() })
    }
    assert.equal(parseSection('no tags'), null)
    assert.equal(parseSection(good).stateFields[0].name, 'c_count')
    let r = await run([good])
    assert.ok(r.section !== null && r.attempts === 1, r.failed)
    assert.match(asks[0].system, /^LANGUAGE/)
    assert.match(asks[0].user, /The program so far/)
    assert.match(c.assembleProgram(comp, [], r.section), /return \{c_count: state\.c_count \+ 1, /)
    r = await run([broken, good])
    assert.ok(r.section !== null && r.attempts === 2, r.failed)
    assert.match(asks[1].user, /It failed:[\s\S]*c_cuont/)
    r = await run([good.replace('return {', 'sdk.call("x/y", [], "c_bump");\n  return {'), good])
    assert.equal(r.attempts, 2)
    assert.match(asks[1].user, /sdk\.call/)
    // Compiles and runs, but Jev does not read it as doing a need: asked for again, saying which; still not, the best one is
    // served and only what it misses is reported.
    {
      const {verifyRequest, undone} = loadVera('agent/AgentCustom')
      const request = Object.assign(new CustomRequest(), {needs: ['a counter', 'a photo'], prompt: 'p', compose: s => c.assembleProgram(comp, [], s)})
      const body = JSON.parse(verifyRequest(request, good))
      assert.deepEqual(Object.keys(body.questions), ['does.0', 'does.1'])
      assert.match(body.state, /c_bump/)
      const said = (a, b) => JSON.stringify({answers: {'does.0': {probabilities: {yes: a, no: 1 - a}}, 'does.1': {probabilities: {yes: b, no: 1 - b}}}})
      assert.deepEqual(undone(request, said(0.9, 0.2)), ['a photo'])
      assert.deepEqual(undone(request, ''), [])
      request.verify = async () => said(0.9, 0.2)
      const users = []
      const partial = await writeSection(request, 'L', async (system, user) => { users.push(user); return good })
      assert.ok(partial.section !== null)
      assert.deepEqual(partial.missed, ['a photo'])
      assert.match(partial.failed, /does not do: a photo/)
      assert.equal(partial.attempts, 4)
      assert.match(users[1], /it does not do: a photo/)
      assert.match(body.state, /saved and restored by the phone between visits/)
      let reads = [said(0.9, 0.2), said(0.9, 0.8)]
      request.verify = async () => reads.shift()
      const second = await writeSection(request, 'L', async () => good)
      assert.ok(second.section !== null)
      assert.equal(second.attempts, 2)
    }
    r = await run(['<cannot>it needs the camera</cannot>'])
    assert.equal(r.section, null)
    assert.equal(r.cannot, 'it needs the camera')
    assert.match(r.failed, /cannot: it needs the camera/)
    assert.equal(asks.length, 1)
    // The quick tries and their repairs fail: one more, thinking, with a larger budget; then it is refused.
    r = await run([broken, broken, broken, broken])
    assert.equal(r.section, null)
    assert.equal(r.attempts, 4)
    assert.deepEqual(asks.map(a => a.think), [false, false, false, true])
    assert.ok(asks[3].budget > asks[0].budget)
    r = await run([broken, broken, broken, good])
    assert.ok(r.section !== null && r.thought)
  }

  // Questions: Jev keeps only those a default cannot stand in for; the person's answer, when it differs from the
  // default the plan was drawn for, has the plan drawn again with it; no answer is the default.
  {
    const {blockingRequest, blockingOf, askBlocking} = loadVera('agent/AgentQuestions')
    const c = loadVera('VeraCompose')
    const sketch = c.parseSketch(JSON.stringify({title: 'Converter', inputs: [], values: [], questions: [
      {id: 'units', ask: 'Which units?', options: ['km to miles', 'kg to pounds'], default: 0},
      {id: 'look', ask: 'Which colour?', options: ['blue', 'green'], default: 1},
      {id: 'bad', ask: 'One option only?', options: ['only']}]}))
    assert.equal(sketch.questions.length, 2)
    assert.equal(sketch.questions[1].fallback, 1)
    const body = JSON.parse(blockingRequest('a converter', sketch.questions))
    assert.deepEqual(Object.keys(body.questions), ['blocking.0', 'blocking.1'])
    const jev = (a, b) => async () => JSON.stringify({answers: {'blocking.0': {probabilities: {ask: a, skip: 1 - a}}, 'blocking.1': {probabilities: {ask: b, skip: 1 - b}}}})
    assert.deepEqual(blockingOf(await jev(0.9, 0.1)(), sketch.questions).map(q => q.id), ['units'])
    assert.deepEqual(blockingOf('', sketch.questions), [])
    const shown = []
    let log = []
    let settled = await askBlocking('a converter', sketch.questions, jev(0.9, 0.1), async q => { shown.push(q); return 1 }, log)
    assert.equal(shown.length, 1)
    assert.equal(shown[0].fallback, 0)
    assert.match(settled, /Which units\? kg to pounds/)
    assert.equal(log[0].changed, true)
    log = []
    assert.equal(await askBlocking('a converter', sketch.questions, jev(0.9, 0.1), async () => null, log), '')
    assert.match(log[0].answer, /km to miles \(default\)/)
    // Through the agent: an answer that differs draws the plan again, with the answer in the request.
    const {host} = replayHost('tip')
    const plans = []
    const askPlan = host.askPlan
    host.askPlan = async (system, user, onText) => {
      plans.push(user)
      if (plans.length === 1) return JSON.stringify(Object.assign(JSON.parse(fixture('tip', 'sketch.json')), {questions: [{id: 'q', ask: 'Split it?', options: ['yes', 'no'], default: 0}]}))
      return askPlan(system, user, onText)
    }
    const askJev = host.askJev
    host.askJev = async b => JSON.parse(b).questions['blocking.0'] ? jev(0.9, 0)() : askJev(b)
    host.ask = async () => 1
    const r = await runAgent(request('tip calculator'), host)
    assert.equal(plans.length, 2)
    assert.match(plans[1], /The person was asked, and answered:\n- Split it\? no/)
    assert.equal(r.composed.replanned, true)
    assert.ok(r.vbc2.length > 0, r.note)
    assert.equal(r.asked.length, 1)
  }

  // The route, agent first (the default): a served agent ends it and the blocks never run.
  const routeRequest = (prompt, blocks) => Object.assign(new route.RouteRequest(), {agent: request(prompt), blocksPrompt: blocks ? prompt : ''})
  assert.equal(route.routeOrder(), route.ORDER_AGENT_FIRST)
  {
    const {host} = replayHost('tip')
    const o = await route.buildScreen(routeRequest('tip calculator', true), host)
    assert.equal(o.kind, route.OUTCOME_AGENT)
    assert.equal(o.blocks, null)
  }
  // The agent refuses: the blocks run next, and with neither serving the screen is not built, with what each said.
  {
    const {host} = replayHost('tip', {jev: ''})
    const o = await route.buildScreen(routeRequest('tip calculator', true), host)
    assert.equal(o.kind, route.OUTCOME_NOT_BUILT)
    assert.notEqual(o.blocks, null)
    assert.match(o.reason, /^agent: .*\| blocks: /)
  }
  // The blocks hand on the right sections for a request that needs more than they do: the layout stays, and what it
  // lacks is written into it as one section the model writes and Jev reads against the need, before any generation.
  {
    const compose = loadVera('VeraSectionCompose')
    const {deepseek} = loadVera('DeepSeekEngine')
    const {settings} = loadVera('SettingsStore')
    settings.getSelectorKey = () => 'test-key'
    settings.hasExaKey = () => false
    const savedPick = compose.selectSections, savedContent = deepseek.extractTemplateContent
    deepseek.extractTemplateContent = async () => JSON.stringify({title: 'Party'})
    const answers = {section1: {choice: 'metrics', confidence: 0.9}}
    for (const k of ['needs_integration', 'needs_real_data', 'needs_search_or_form', 'needs_live_ticking', 'needs_multiple_counters', 'needs_multiple_series', 'needs_logic'])
      answers['veto.' + k] = {noul: k === 'needs_logic' ? 0.95 : 0}
    compose.selectSections = async () => compose.readSectionPick(JSON.stringify({answers}))
    const section = '<classes>\n</classes>\n<fields>\nc_people: number = 4\n</fields>\n<functions>\n' +
      'function c_more(state: AppState, v: number): AppState {\n  return {c_people: state.c_people + 1__PASSTHROUGH__};\n}\n</functions>\n' +
      '<view>\nsections.push(ui.Section("content", "", "", [ui.Text("body", "Slices each: " + ui.numberToString(16 / state.c_people)), ' +
      'ui.Button("secondary", "One more", "c_more", 0, true)]));\n</view>'
    const finishing = (jevDoes, reply = section) => {
      const {host, seen} = replayHost('tip', {jev: ''})
      host.language = 'VERA-L'
      const asked = []
      host.askCode = async (system, user) => { asked.push(user); return reply }
      host.askJev = async body => {
        seen.jev++
        const q = JSON.parse(body).questions
        if (q['does.0']) return JSON.stringify({answers: {'does.0': {probabilities: {yes: jevDoes, no: 1 - jevDoes}}}})
        return ''
      }
      return {host, asked}
    }
    let {host, asked} = finishing(0.9)
    let o = await route.buildScreen(routeRequest('pizza slices per person', true), host)
    assert.equal(o.kind, route.OUTCOME_TEMPLATE, o.blocks && o.blocks.note)
    assert.equal(o.blocks.action, 'template')
    assert.match(o.blocks.source, /c_people/)
    assert.ok(o.blocks.vbc2.length > 0)
    assert.equal(o.blocks.composition, '')
    assert.equal(o.hole.attempts, 1)
    assert.match(asked[0], /works out what the request asks to be calculated/)
    assert.ok(o.blocks.plan.slots.some(s => s.id === 'missing.needs_logic' && s.fill === 'hole'))
    // Jev does not read the section as doing its one need, through the repairs and the thinking try: the layout is served
    // with a notice in place of what it lacks, not handed to the model.
    ;({host, asked} = finishing(0.1))
    o = await route.buildScreen(routeRequest('pizza slices per person', true), host)
    assert.equal(o.kind, route.OUTCOME_TEMPLATE)
    assert.equal(asked.length, 4)
    assert.doesNotMatch(o.blocks.source, /c_people/)
    assert.match(o.blocks.source, /ui\.InsetBanner\("warning", "Part of this app could not be built", "Not built: works out what the request asks/)
    assert.ok(o.blocks.plan.slots.some(s => s.id === 'missing.needs_logic' && s.fill === 'reported'))
    // The writer says it cannot: its own sentence is the notice, and it is not asked again.
    ;({host, asked} = finishing(0.9, '<cannot>This app cannot use the camera.</cannot>'))
    o = await route.buildScreen(routeRequest('pizza slices per person', true), host)
    assert.equal(o.kind, route.OUTCOME_TEMPLATE)
    assert.equal(asked.length, 1)
    assert.match(o.blocks.source, /"This app cannot use the camera\."/)
    // Another generation mode finishes the program its own way.
    ;({host, asked} = finishing(0.9))
    o = await route.buildScreen(Object.assign(routeRequest('pizza slices per person', true), {mode: 'local'}), host)
    assert.equal(o.kind, route.OUTCOME_COMPLETE)
    assert.equal(asked.length, 0)
    // Something the phone does that nothing here can: the agent serves the rest of its screen with the writer's own
    // sentence as a notice in its place; the blocks are not needed.
    const egg = JSON.parse(fixture('egg', 'jev-answer.json'))
    const effectKey = Object.keys(egg.answers).find(k => k.startsWith('effect.'))
    egg.answers[effectKey] = {choice: 'unavailable', confidence: 0.95}
    {
      const {host} = replayHost('egg', {jev: JSON.stringify(egg)})
      host.language = 'VERA-L'
      const asked = []
      host.askCode = async (system, user) => { asked.push(user); return '<cannot>This phone gives apps no way to vibrate here.</cannot>' }
      o = await route.buildScreen(routeRequest('egg timer that vibrates', true), host)
      assert.equal(o.kind, route.OUTCOME_AGENT, o.agent.note)
      assert.equal(o.blocks, null)
      assert.equal(asked.length, 1)
      assert.match(o.agent.source, /ui\.InsetBanner\("warning", "Not available on this phone", "This phone gives apps no way to vibrate here\."/)
      assert.match(o.agent.note, /reported on the screen/)
      assert.ok(o.agent.screen.slots.some(s => s.phone && s.fill === 'reported'))
    }
    compose.selectSections = savedPick
    deepseek.extractTemplateContent = savedContent
  }
  // Something the phone does that no effect is: the agent leaves it to its section, shown the phone's functions found
  // for it; the section may call only those, and a target it makes up is sent back for a repair.
  {
    const egg = JSON.parse(fixture('egg', 'jev-answer.json'))
    egg.answers[Object.keys(egg.answers).find(k => k.startsWith('effect.'))] = {choice: 'unavailable', confidence: 0.95}
    const alarm = 'com.huawei.hmos.clock/entry/EntryAbility/CreateAlarm'
    const found = JSON.stringify({results: [{kind: 'registry', description: 'creates an alarm',
      call: 'sdk.call("' + alarm + '", ["hour", "7", "minute", "30"], "yourHandlerName", "background")'}]})
    const calling = target => '<classes>\n</classes>\n<fields>\nc_said: string = ""\n</fields>\n<functions>\n' +
      'function c_set(state: AppState, v: number): AppState {\n  sdk.call("' + target + '", ["hour", "7", "minute", "30"], "c_answer", "background");\n' +
      '  return {c_said: "Setting the alarm..."__PASSTHROUGH__};\n}\n' +
      'function c_answer(state: AppState, value: string): AppState {\n  return {c_said: value__PASSTHROUGH__};\n}\n</functions>\n' +
      '<view>\nsections.push(ui.Section("content", "", "", [ui.Button("primary", "Set alarm", "c_set", 0, true), ui.Text("body", state.c_said)]));\n</view>'
    const phoneHost = (replies, lookup) => {
      const {host} = replayHost('egg', {jev: JSON.stringify(egg)})
      const jevPlan = host.askJev
      host.language = 'VERA-L'
      const seen = {systems: [], users: [], lookups: []}
      host.askCode = async (system, user) => { seen.systems.push(system); seen.users.push(user); return replies.length > 1 ? replies.shift() : replies[0] }
      host.lookup = async need => { seen.lookups.push(need); return lookup }
      host.askJev = async body => JSON.parse(body).questions['does.0'] ?
        JSON.stringify({answers: {'does.0': {probabilities: {yes: 0.9, no: 0.1}}}}) : jevPlan(body)
      return {host, seen}
    }
    let {host, seen} = phoneHost([calling(alarm)], found)
    let r = await runAgent(request('egg timer that sets an alarm'), host)
    assert.ok(r.vbc2.length > 0, r.note)
    assert.ok(r.source.includes(alarm))
    assert.equal(seen.lookups.length, 1)
    assert.match(seen.users[0], /Phone functions found/)
    assert.match(seen.systems[0], /calling ONLY targets from/)
    assert.ok(r.screen.slots.some(s => s.phone && s.fill === 'hole'), require('util').inspect(r.screen.slots.map(s => s.id + ':' + s.fill + (s.phone ? ':phone' : ''))))
    // A made-up target is sent back, named; the repair that calls the one found is served.
    ;({host, seen} = phoneHost([calling('com.example/clock/Main/SetAlarm'), calling(alarm)], found))
    r = await runAgent(request('egg timer that sets an alarm'), host)
    assert.ok(r.vbc2.length > 0, r.note)
    assert.equal(r.custom.attempts, 2)
    assert.match(seen.users[1], /calls "com\.example\/clock\/Main\/SetAlarm", which is not one of the phone functions found/)
    // Nothing found: no phone calls at all; a section that keeps calling is not served, and the rest of the screen is,
    // with a notice saying it could not be built.
    ;({host, seen} = phoneHost([calling(alarm)], JSON.stringify({results: []})))
    r = await runAgent(request('egg timer that sets an alarm'), host)
    assert.match(seen.systems[0], /never calls sdk\.call/)
    assert.doesNotMatch(seen.users[0], /Phone functions found/)
    assert.match(r.note, /calls sdk\.call, which it never may/)
    assert.doesNotMatch(r.source, new RegExp(alarm))
    assert.match(r.source, /ui\.InsetBanner\("warning", "Part of this app could not be built"/)
  }
  // Nothing narrower serves: the whole screen is one hole, written against the sketch and read by Jev against everything
  // it says the screen does, before any generation.
  {
    const screen = '<classes>\n</classes>\n<fields>\nc_bill: number = 50\nc_pct: number = 15\n</fields>\n<functions>\n' +
      'function c_setBill(state: AppState, v: number): AppState {\n  return {c_bill: v__PASSTHROUGH__};\n}\n</functions>\n<view>\n' +
      'sections.push(ui.Section("content", "", "", [ui.Text("body", "Tip: " + ui.numberToString(state.c_bill * state.c_pct / 100))]));\n</view>'
    const wholeHost = (jevDoes, reply = screen) => {
      const {host, seen} = replayHost('tip', {jev: ''})
      const sketchJev = host.askJev
      host.language = 'VERA-L'
      const asks = []
      host.askCode = async (system, user, budget) => { asks.push({user, budget}); return reply }
      host.askJev = async body => {
        const q = JSON.parse(body).questions
        if (!q || !q['does.0']) return sketchJev(body)
        const answers = {}
        for (const k of Object.keys(q)) answers[k] = {probabilities: {yes: jevDoes, no: 1 - jevDoes}}
        return JSON.stringify({answers})
      }
      return {host, asks, seen}
    }
    let {host, asks} = wholeHost(0.9)
    let o = await route.buildScreen(routeRequest('tip calculator', false), host)
    assert.equal(o.kind, route.OUTCOME_AGENT, o.agent.note)
    assert.match(o.agent.source, /c_bill/)
    assert.ok(o.agent.vbc2.length > 0)
    assert.equal(o.agent.whole.attempts, 1)
    assert.match(o.agent.note, /whole screen written in 1 attempt/)
    assert.equal(asks.length, 1)
    assert.ok(asks[0].budget > 3000)
    assert.match(asks[0].user, /your section is the whole screen/)
    assert.ok(o.agent.screen.slots.length > 1 && o.agent.screen.slots.every(s => s.fill === 'hole'))
    assert.match(o.agent.source, /ui\.Header\(/)
    // Jev does not read it as doing what the sketch says: not built.
    ;({host} = wholeHost(0.2))
    o = await route.buildScreen(routeRequest('tip calculator', false), host)
    assert.equal(o.kind, route.OUTCOME_NOT_BUILT)
    assert.match(o.agent.note, /whole screen: custom section does not do/)
    // Switched off: not built, without asking the writer.
    route.setWholeScreenEnabled(false)
    ;({host, asks} = wholeHost(0.9))
    o = await route.buildScreen(routeRequest('tip calculator', false), host)
    assert.equal(o.kind, route.OUTCOME_NOT_BUILT)
    assert.equal(asks.length, 0)
    route.setWholeScreenEnabled(true)
  }
  // An assembled program that does not compile is repaired by SEARCH/REPLACE edits to it, checked again; edits that do
  // not apply are asked for once more, and what still fails is said.
  {
    const {repairProgram, checkProgram} = loadVera('agent/AgentRepair')
    const broken = 'import * as ui from "std/ui"\n@jsonable\nclass AppState { n: number; }\nfunction init(): AppState { return {n: 0}; }\n' +
      'function bump(state: AppState, v: number): AppState { return {n: state.n + "1"}; }\n' +
      'function view(state: AppState): ui.View { return ui.AppTheme("clean", "", [ui.Section("content", "", "", [ui.Text("body", ui.numberToString(state.n))])]); }'
    const errors = checkProgram(broken)
    assert.notEqual(errors, '')
    const edit = '<<<<<<< SEARCH\nfunction bump(state: AppState, v: number): AppState { return {n: state.n + "1"}; }\n=======\n' +
      'function bump(state: AppState, v: number): AppState { return {n: state.n + 1}; }\n>>>>>>> REPLACE'
    const asked = []
    let r = await repairProgram(broken, errors, 'a counter', 'VERA-L', async (system, user, budget) => { asked.push({user, budget}); return edit })
    assert.equal(r.failed, '')
    assert.equal(r.rounds, 1)
    assert.match(r.source, /state\.n \+ 1\}/)
    assert.ok(r.vbc2.length > 0)
    assert.match(asked[0].user, /^The program:\n/)
    assert.match(asked[0].user, /SEARCH/)
    const replies = ['<<<<<<< SEARCH\nno such line\n=======\nx\n>>>>>>> REPLACE', edit]
    r = await repairProgram(broken, errors, 'a counter', 'VERA-L', async () => replies.shift())
    assert.equal(r.rounds, 2)
    assert.equal(r.failed, '')
    r = await repairProgram(broken, errors, 'a counter', 'VERA-L', async () => 'no edits here')
    assert.equal(r.source, '')
    assert.notEqual(r.failed, '')
  }
  // What one hole of a request learned is not asked again by the next: a phone need it said it cannot do is reported as
  // it said, and a lookup is made once.
  {
    const {writeHole} = loadVera('agent/AgentHole')
    const P = loadVera('ScreenPlan')
    const host = new (loadVera('agent/AgentHost').AgentHost)()
    host.language = 'VERA-L'
    let writes = 0, lookups = 0
    host.askCode = async () => { writes++; return '<cannot>This phone does not let apps set alarms.</cannot>' }
    host.lookup = async () => { lookups++; return JSON.stringify({results: []}) }
    const recorded = []
    host.onHole = r => recorded.push(r)
    const plan = () => {
      const p = new P.ScreenPlan()
      p.components.push(new P.PlanComponent(P.FILL_PART, null, new Map()))
      p.addToWrite('a', 'set an alarm (the person taps Set)', true)
      return p
    }
    const first = plan()
    await writeHole(first, 'alarm', [], host)
    assert.equal(writes, 1)
    const second = plan()
    const r = await writeHole(second, 'alarm', [], host)
    assert.equal(writes, 1)
    assert.equal(lookups, 1)
    assert.equal(r.cannot, 'This phone does not let apps set alarms.')
    assert.equal(second.slots[0].fill, P.FILL_REPORTED)
    const whole = new P.ScreenPlan()
    whole.addToWrite('a', 'set an alarm (the person taps Set)', true)
    assert.match((await writeHole(whole, 'alarm', [], host)).failed, /known from an earlier hole/)
    assert.equal(writes, 1)
    // Each hole is recorded with how it ended, for the report of what recurs (hole-report.py).
    assert.deepEqual(recorded.map(r => r.outcome), ['reported', 'known'])
    assert.deepEqual(recorded[0].needs, ['set an alarm (the person taps Set)'])
    assert.deepEqual(recorded[0].phone, [true])
    assert.equal(recorded[0].why, 'This phone does not let apps set alarms.')
  }
  // Jev's pick of sections starts with the agent's plan, not after it, and the blocks use that pick, not a second one.
  {
    const compose = loadVera('VeraSectionCompose')
    const saved = compose.selectSections
    const order = []
    compose.selectSections = async () => { order.push('pick'); return new compose.SectionPickOutcome(null, new Map(), 'none') }
    const {host} = replayHost('tip', {jev: ''})
    const plan = host.askPlan
    host.askPlan = async (...a) => { order.push('plan'); return plan(...a) }
    const o = await route.buildScreen(routeRequest('tip calculator', true), host)
    assert.equal(o.kind, route.OUTCOME_NOT_BUILT)
    assert.deepEqual(order, ['pick', 'plan'])
    compose.selectSections = saved
  }
  // Blocks first: the blocks run before the agent, and the agent still serves what they do not.
  route.setRouteOrder(route.ORDER_BLOCKS_FIRST)
  {
    const {host, seen} = replayHost('tip')
    const o = await route.buildScreen(routeRequest('tip calculator', true), host)
    assert.equal(o.kind, route.OUTCOME_AGENT)
    assert.notEqual(o.blocks, null)
    assert.equal(seen.plans, 1)
  }
  route.setRouteOrder('anything else')
  assert.equal(route.routeOrder(), route.ORDER_AGENT_FIRST)
  // Neither builder asked for: straight to scratch, no model call.
  {
    const {host, seen} = replayHost('tip')
    const o = await route.buildScreen(new route.RouteRequest(), host)
    assert.equal(o.kind, route.OUTCOME_NOT_BUILT)
    assert.equal(seen.plans, 0)
  }
  // Cancelled before it starts: nothing is asked.
  {
    const {host, seen} = replayHost('tip', {cancelled: () => true})
    const o = await route.buildScreen(routeRequest('tip calculator', true), host)
    assert.equal(o.kind, route.OUTCOME_CANCELLED)
    assert.equal(seen.plans, 0)
  }
  console.log('agent-check: ok')
})().catch(e => { console.error(e); process.exit(1) })
