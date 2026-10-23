// buildFromTemplates with canned Jev and model answers: template, complete (soft veto, a screen of placeholder
// buttons only), scratch (hard veto, did not compile) and cancelled. No network.
'use strict'
const assert = require('node:assert/strict')
const {loadVera} = require('./source-loader')
const compose = loadVera('VeraSectionCompose')
const content = loadVera('VeraTemplateContent')
const {deepseek} = loadVera('DeepSeekEngine')
const {settings} = loadVera('SettingsStore')
const {buildFromTemplates} = loadVera('VeraTemplatePipeline')

settings.getSelectorKey = () => 'test-key'
settings.hasExaKey = () => false
deepseek.extractTemplateContent = async () => JSON.stringify({title: 'Test', section1_items: [['Milk', '2 L'], ['Eggs', '12'], ['Bread', '']]})

function jev(sections, vetoes) {
  const answers = {}
  sections.forEach((k, i) => { answers['section' + (i + 1)] = {choice: k, confidence: 0.9} })
  for (const k of ['needs_integration', 'needs_real_data', 'needs_search_or_form', 'needs_live_ticking', 'needs_multiple_counters', 'needs_multiple_series', 'needs_logic'])
    answers['veto.' + k] = {noul: (vetoes || {})[k] || 0}
  return compose.readSectionPick(JSON.stringify({answers}))
}
const run = async (outcome, opts = {}) => {
  compose.selectSections = async () => outcome
  let cancelled = false
  const statuses = []
  const build = await buildFromTemplates('grocery', 'deepseek', s => { statuses.push(s) }, () => opts.cancelAfterJev ? true : cancelled)
  return {build, statuses}
}
;(async () => {
  let {build} = await run(jev(['checklist']))
  assert.equal(build.action, 'template'); assert.match(build.source, /label: "Milk", detail: "2 L"/); assert.ok(build.vbc2.length > 0)
  // no coverage judge: its scores did not separate good screens from bad ones, and nothing read them
  assert.doesNotMatch(build.note, /covers=/); assert.equal('covers' in build, false)

  // buttons that only note which one was tapped are not a finished screen: the model has to make them do something
  ;({build} = await run(jev(['actions'])))
  assert.equal(build.action, 'complete'); assert.match(build.note, /placeholder buttons only/); assert.ok(build.source.length > 0); assert.ok(build.vbc2.length > 0)
  // what the sections lack is a slot of the plan, to be written (agent/AgentHole.ets)
  assert.deepEqual(build.plan.toWrite().map(s => s.id), ['missing.buttons'])
  ;({build} = await run(jev(['metrics', 'actions'])))
  assert.equal(build.action, 'template', 'actions beside a real block stays a template')

  ;({build} = await run(jev(['checklist'], {needs_logic: 0.95})))
  assert.equal(build.action, 'complete'); assert.match(build.status, /adding the logic/)
  assert.deepEqual(build.plan.toWrite().map(s => s.id), ['missing.needs_logic'])

  ;({build} = await run(jev(['checklist'], {needs_integration: 0.97})))
  assert.equal(build.action, 'scratch'); assert.match(build.note, /vetoed needs_integration/)

  ;({build} = await run(jev(['none', 'none'])))
  assert.equal(build.action, 'scratch')

  ;({build} = await run(jev(['checklist'], {needs_real_data: 0.9})))
  assert.equal(build.action, 'scratch'); assert.match(build.note, /no search available/)

  ;({build} = await run(jev(['checklist']), {cancelAfterJev: true}))
  assert.equal(build.action, 'cancelled')

  // a composition that compiles but cannot run must not reach the screen: break the checklist view for this run
  const templates = loadVera('VeraTemplates'), real = templates.fragments
  templates.fragments = () => real().map(f => {
    if (f.kind === 'checklist') f.viewBlock = f.viewBlock.replace('let count: number = state.itemsIDX.length();', 'let count: number = state.itemsIDX.length(); let boom: number = state.itemsIDX[99].detail.length();')
    return f
  })
  ;({build} = await run(jev(['checklist'])))
  templates.fragments = real
  assert.equal(build.action, 'scratch'); assert.match(build.note, /did not run/)
  // a filter beside a list: the model is asked for the match rule too, and an answer without it keeps the default
  {
    const saved = deepseek.extractTemplateContent
    const rowsAnswer = {title: 'Books', section2_items: [['Dune', 'Sand.'], ['Emma', 'Manners.'], ['Ulysses', 'Dublin.']]}
    const lower = 'return query.length() === 0 || strings.contains(strings.toLowerCase(label), strings.toLowerCase(query));'
    let calls = 0
    deepseek.extractTemplateContent = async () => { calls++; return JSON.stringify(Object.assign({holes: {rowMatches2: lower}}, rowsAnswer)) }
    ;({build} = await run(jev(['filter_box', 'master_list', 'detail_view'])))
    assert.equal(build.action, 'template'); assert.match(build.note, /holes=filled\(1\)/); assert.match(build.source, /strings\.toLowerCase\(label\)/)
    assert.equal(build.route.holes, true, 'the route says the model wrote function bodies')
    deepseek.extractTemplateContent = async () => JSON.stringify(rowsAnswer)
    ;({build} = await run(jev(['filter_box', 'master_list', 'detail_view'])))
    assert.equal(build.action, 'template'); assert.match(build.note, /holes=default\(unusable answer\)/); assert.match(build.source, /strings\.contains\(label, query\)/)
    assert.equal(build.route.holes, false)
    // no filter: the model is not asked about holes at all
    calls = 0
    deepseek.extractTemplateContent = async () => { calls++; return JSON.stringify(rowsAnswer) }
    ;({build} = await run(jev(['master_list', 'detail_view'])))
    assert.equal(build.action, 'template'); assert.doesNotMatch(build.note, /holes=/)
    assert.equal(calls, 1, 'only the content call')
    deepseek.extractTemplateContent = saved
  }

  // an intent panel: its rows come from a call of their own, made beside the content call; with no usable row the
  // panel is only a base for the model, never a finished screen
  {
    const reg = loadVera('VeraIntentRegistry'), saved = deepseek.extractTemplateContent, savedReg = reg.registryEntries
    const torch = new reg.RegistryEntry()
    Object.assign(torch, {target: 'com.ohos.sceneboard/entry/EntryAbility/OpenFlashlight', bundle: 'com.ohos.sceneboard',
      intentName: 'OpenFlashlight', modes: 'background', domain: 'system', params: [], paramHints: [], words: 'grocery torch'})
    reg.registryEntries = () => [torch]
    let rowsAnswer = JSON.stringify({section1: [{n: 1, label: 'Torch on'}]})
    deepseek.extractTemplateContent = async (system) => /phone actions/.test(system) ? rowsAnswer : JSON.stringify({title: 'Torch'})
    ;({build} = await run(jev(['intent_panel'])))
    assert.equal(build.action, 'template'); assert.match(build.note, /intents=1\/1/)
    assert.match(build.source, /target: "com\.ohos\.sceneboard\/entry\/EntryAbility\/OpenFlashlight"/)
    assert.match(build.composition, /OpenFlashlight/, 'the record keeps the rows')
    rowsAnswer = 'no'
    ;({build} = await run(jev(['intent_panel'])))
    assert.equal(build.action, 'complete'); assert.match(build.note, /intents=none/); assert.match(build.status, /phone actions/)
    assert.deepEqual(build.plan.toWrite().map(s => s.id), ['missing.needs_integration'])
    deepseek.extractTemplateContent = saved
    reg.registryEntries = savedReg
  }

  // a timer whose finish action the model writes: it is shown the SDK functions found for the request, the body is settled against the
  // compiler, and the route says the model wrote function bodies
  {
    const engine = loadVera('DeepSeekEngine'), saved = deepseek.extractTemplateContent, savedDiscovery = engine.discoveryToolResult
    const seen = []
    engine.discoveryToolResult = async (name, need) => { seen.push([name, need]); return '{"found":[{"call":"SensorServiceKit.vibrator.vibrate"}]}' }
    let hole = null
    deepseek.extractTemplateContent = async (system, user) => {
      if (/Functions to write/.test(user)) { hole = {system, user}; return JSON.stringify({holes: {whenFinished1: 'sdk.call("SensorServiceKit.vibrator.vibrate", ["duration", "1500"], "onFinishedAnswerIDX");\nreturn 0;'}}) }
      return JSON.stringify({title: 'Egg', section1_presets: [['Soft', '360'], ['Hard', '600']]})
    }
    const timerJev = slot => compose.readSectionPick(JSON.stringify({answers: Object.assign({section1: {choice: 'timer', confidence: 0.9},
      'section1.timer.finish_action': {noul: slot}}, Object.fromEntries(['needs_integration', 'needs_real_data', 'needs_search_or_form',
      'needs_live_ticking', 'needs_multiple_counters', 'needs_multiple_series', 'needs_logic'].map(k => ['veto.' + k, {noul: k === 'needs_integration' ? 0.82 : 0}])))}))
    ;({build} = await run(timerJev(0.9), 0.9))
    assert.equal(build.action, 'template', 'the finish action is covered by the hole: no model rewrite'); assert.equal(build.route.holes, true)
    assert.match(build.source, /sdk\.call\("SensorServiceKit\.vibrator\.vibrate"/); assert.match(build.source, /"onFinishedAnswer1"/)
    assert.deepEqual(seen, [['find_sdk_function', 'grocery']]); assert.match(hole.user, /SensorServiceKit\.vibrator\.vibrate/)
    // no finish action asked for: no lookup, no hole call, and the integration veto still decides
    seen.length = 0; hole = null
    ;({build} = await run(timerJev(0.1), 0.9))
    assert.equal(build.action, 'complete'); assert.equal(seen.length, 0); assert.equal(hole, null)
    deepseek.extractTemplateContent = saved; engine.discoveryToolResult = savedDiscovery
  }

  // the route: what Jev said, whether a second look was taken, and which way the request went
  const verify = loadVera('VeraPickVerify')
  const weakBody = extra => JSON.stringify({answers: Object.assign({section1: {choice: 'checklist', confidence: 0.3}, section2: {choice: 'none', confidence: 0.6},
    'veto.needs_integration': {noul: 0}, 'veto.needs_real_data': {noul: 0}, 'veto.needs_search_or_form': {noul: 0}, 'veto.needs_live_ticking': {noul: 0},
    'veto.needs_multiple_counters': {noul: 0}, 'veto.needs_multiple_series': {noul: 0}, 'veto.needs_logic': {noul: 0}}, extra || {})})
  const weak = extra => { const o = compose.readSectionPick(weakBody(extra)); o.rawBody = weakBody(extra); return o }
  ;({build} = await run(jev(['checklist']), 0.9))
  assert.deepEqual([build.route.route, build.route.jev, build.route.check], ['blocks', 'sure', 'none']); assert.deepEqual(build.route.kinds, ['checklist'])
  ;({build} = await run(jev(['checklist'], {needs_logic: 0.95}), 0.9))
  assert.deepEqual([build.route.route, build.route.jev], ['blocks+model', 'sure']); assert.match(build.route.logic, /needs_logic=0\.95/)
  ;({build} = await run(jev(['checklist'], {needs_integration: 0.97}), 0.9))
  assert.deepEqual([build.route.route, build.route.jev], ['scratch', 'vetoed'])
  ;({build} = await run(jev(['none', 'none']), 0.9))
  assert.deepEqual([build.route.route, build.route.jev], ['scratch', 'none'])
  ;({build} = await run(jev(['checklist'], {needs_real_data: 0.9}), 0.9))
  assert.equal(build.route.route, 'scratch'); assert.match(build.route.failure, /needs real data/)
  // weak pick, second look off (the shipped setting): scratch, and the page can say the check was off
  ;({build} = await run(weak(), 0.9))
  assert.deepEqual([build.route.route, build.route.jev, build.route.check, build.route.weak], ['scratch', 'unsure', 'off', ['checklist']])
  // weak pick, second look on
  verify.VERIFY_WEAK_PICKS = true
  verify.verifyWeakPick = async () => Object.assign(new verify.VerifyAnswer(), {confirmed: ['checklist']})
  ;({build} = await run(weak(), 0.9))
  assert.deepEqual([build.route.route, build.route.jev, build.route.check], ['blocks', 'unsure', 'confirmed']); assert.deepEqual(build.route.kinds, ['checklist'])
  verify.verifyWeakPick = async () => Object.assign(new verify.VerifyAnswer(), {missing: 'scaling by people'})
  ;({build} = await run(weak(), 0.9))
  assert.deepEqual([build.route.route, build.route.check, build.route.missing], ['scratch', 'rejected', 'scaling by people'])
  verify.verifyWeakPick = async () => Object.assign(new verify.VerifyAnswer(), {failed: true})
  ;({build} = await run(weak(), 0.9))
  assert.deepEqual([build.route.route, build.route.check], ['scratch', 'failed'])
  verify.VERIFY_WEAK_PICKS = false
  // the yes/no question built the block
  ;({build} = await run(weak({'include.checklist': {noul: 0.6}}), 0.9))
  assert.deepEqual([build.route.route, build.route.jev, build.route.check, build.route.wanted], ['blocks', 'unsure', 'yesno', 'checklist'])

  // data filled from a search into a block that only shows it: finished, not handed to the model (the weather screen cost
  // 27 s because the model searched again and rewrote it); anything else the soft vetoes ask for still is
  {
    const search = loadVera('VeraWebSearch'), savedSearch = search.webSearch, savedExa = settings.hasExaKey
    settings.hasExaKey = () => true
    let searches = []
    search.webSearch = async q => { searches.push(q); return searchAnswer }
    let searchAnswer = 'Weather today: 18 C, light rain, wind 12 km/h.'
    ;({build} = await run(jev(['key_facts'], {needs_real_data: 0.9, needs_integration: 0.5})))
    assert.equal(build.action, 'template'); assert.match(build.note, /data filled from search, no completion/)
    assert.equal(build.route.route, 'blocks'); assert.equal(build.searchText, searchAnswer); assert.equal(searches.length, 1)
    // the same request with a calculation beside it is still the model's to finish, and keeps the results for it
    ;({build} = await run(jev(['key_facts'], {needs_real_data: 0.9, needs_integration: 0.5, needs_logic: 0.95})))
    assert.equal(build.action, 'complete'); assert.equal(build.searchText, searchAnswer)
    // a block with inputs is not display-only
    ;({build} = await run(jev(['checklist'], {needs_real_data: 0.9, needs_integration: 0.5})))
    assert.equal(build.action, 'complete')
    // a search that found nothing leaves the completion in place and gives it no results
    searchAnswer = 'No results.'
    ;({build} = await run(jev(['key_facts'], {needs_real_data: 0.9, needs_integration: 0.5})))
    assert.equal(build.action, 'complete'); assert.equal(build.searchText, '')
    // no search needed: the soft veto alone still completes
    ;({build} = await run(jev(['key_facts'], {needs_integration: 0.5})))
    assert.equal(build.action, 'complete'); assert.equal(build.searchText, '')
    // a hard integration veto never reaches here
    ;({build} = await run(jev(['key_facts'], {needs_real_data: 0.9, needs_integration: 0.95})))
    assert.equal(build.action, 'scratch')
    const {groundedDisplayOnly} = loadVera('VeraTemplatePipeline')
    assert.equal(groundedDisplayOnly(['key_facts', 'none', 'trend_chart'], ['needs_integration']), true)
    assert.equal(groundedDisplayOnly(['key_facts'], []), false)
    assert.equal(groundedDisplayOnly(['key_facts'], ['needs_integration', 'needs_logic']), false)
    assert.equal(groundedDisplayOnly(['none', 'none'], ['needs_integration']), false)
    assert.equal(groundedDisplayOnly(['key_facts', 'intent_panel'], ['needs_integration']), false)
    search.webSearch = savedSearch
    settings.hasExaKey = savedExa
  }

  // a live-data block: grounded in a search whatever Jev said about real data, a finished template (it covers the integration and live
  // ticking vetoes), its first figures and source checked against that search, and a source that is not in the results is blanked
  {
    const search = loadVera('VeraWebSearch'), savedSearch = search.webSearch, savedExa = settings.hasExaKey
    const savedModel = deepseek.extractTemplateContent
    settings.hasExaKey = () => true
    const SEARCH = 'Web results for "usd rub".\n1. Bank of Russia (https://www.cbr.ru/currency_base/daily/)\nUSD 92,45 as of today\n'
    let searches = 0
    search.webSearch = async () => { searches++; return SEARCH }
    let fill = {section1_label1: 'USD/RUB', section1_value1: '92,45', section1_query: 'usd rub exchange rate today', section1_source_name: 'bogus.org', section1_source_url: 'https://www.cbr.ru/currency_base/daily/'}
    deepseek.extractTemplateContent = async () => JSON.stringify(fill)
    ;({build} = await run(jev(['live_facts'], {needs_integration: 0.5, needs_live_ticking: 0.9})))
    assert.equal(build.action, 'template', 'a live block is a finished template, not a completion'); assert.equal(searches, 1, 'grounded without needs_real_data')
    assert.match(build.note, /live=checked\(source=ok figures=1\)/)
    assert.match(build.source, /v1_1: "92,45"|let v11: string = "92,45"|"92,45"/); assert.match(build.source, /srcUrl.*https:\/\/www\.cbr\.ru\/currency_base\/daily\//s)
    assert.doesNotMatch(build.source, /bogus\.org/, 'the model\'s source name is replaced by the address\'s own domain')
    assert.match(build.source, /cbr\.ru/)
    // an address and a figure the search did not contain are not shown as found
    fill = {section1_label1: 'USD/RUB', section1_value1: '95,10', section1_query: '', section1_source_name: 'made.up', section1_source_url: 'https://made.up/rate'}
    ;({build} = await run(jev(['live_facts'])))
    assert.equal(build.action, 'template'); assert.match(build.note, /source=none figures=0/)
    assert.doesNotMatch(build.source, /made\.up|95,10/); assert.match(build.source, /usd rub|grocery/, 'an empty query becomes the request')
    // no search key: nowhere to refresh from, so the model writes it
    settings.hasExaKey = () => false
    ;({build} = await run(jev(['live_facts'])))
    assert.equal(build.action, 'scratch')
    search.webSearch = savedSearch; settings.hasExaKey = savedExa; deepseek.extractTemplateContent = savedModel
  }

  console.log('pipeline-check: ok')
})().catch(e => { console.error(e); process.exit(1) })
