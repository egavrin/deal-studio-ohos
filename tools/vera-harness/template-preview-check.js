// Render first, fill after: buildFromTemplates hands the caller the default-text screen before the content fill,
// for every fragment kind, then the filled screen that replaces it. A failed fill, a filled screen that does not
// compile, a cancel and a `complete` base are covered too. Canned Jev and model answers, no network.
'use strict'
const assert = require('node:assert/strict')
const {loadVera} = require('./source-loader')
const compose = loadVera('VeraSectionCompose')
const {fragments} = loadVera('VeraTemplates')
const {deepseek} = loadVera('DeepSeekEngine')
const {settings} = loadVera('SettingsStore')
const search = loadVera('VeraWebSearch')
const {smokeRun} = loadVera('VeraSmokeRun')
const {buildFromTemplates} = loadVera('VeraTemplatePipeline')

settings.getSelectorKey = () => 'test-key'
settings.hasExaKey = () => true
search.webSearch = async () => 'Some result.'
let events = []
let answer = () => JSON.stringify({title: 'Filled Title'})
deepseek.extractTemplateContent = async (system) => {
  events.push(system.includes('section1_') || system.includes('title') ? 'fill' : 'model')
  await new Promise(r => setTimeout(r, 20))
  return answer()
}

function jev(sections, vetoes) {
  const answers = {}
  sections.forEach((k, i) => { answers['section' + (i + 1)] = {choice: k, confidence: 0.9} })
  for (const k of ['needs_integration', 'needs_real_data', 'needs_search_or_form', 'needs_live_ticking', 'needs_multiple_counters', 'needs_logic'])
    answers['veto.' + k] = {noul: (vetoes || {})[k] || 0}
  return compose.readSectionPick(JSON.stringify({answers}))
}
async function run(outcome, opts = {}) {
  compose.selectSections = async () => outcome
  events = []
  const previews = []
  const build = await buildFromTemplates('a screen', 'deepseek', () => {}, () => opts.cancel ? previews.length > 0 : false,
    p => { previews.push(p); events.push('preview') })
  return {build, previews}
}

;(async () => {
  // Every fragment kind: one default-text preview before the fill, it runs, and the filled screen replaces it.
  // A screen of placeholder buttons alone is a `complete` base, so `actions` is checked beside a real block.
  for (const f of fragments()) {
    const kinds = f.kind === 'actions' ? ['metrics', 'actions'] : [f.kind]
    const outcome = jev(kinds)
    assert.ok(outcome.sections !== null, f.kind + ': Jev pick')
    const {build, previews} = await run(outcome)
    assert.equal(previews.length, 1, f.kind + ': one preview')
    const p = previews[0]
    assert.equal(p.action, 'template', f.kind)
    assert.deepEqual(p.kinds, kinds, f.kind)
    assert.ok(p.vbc2.length > 0 && p.composition.length > 0, f.kind + ': preview compiled')
    const smoke = smokeRun(p.vbc2)
    assert.ok(smoke.ok && smoke.nodes >= 2, f.kind + ': preview runs: ' + smoke.error)
    assert.match(p.source, /Demo Screen/, f.kind + ': default title')
    assert.match(p.note, /content=pending/, f.kind)
    assert.equal(events.indexOf('preview'), 0, f.kind + ': preview before any model call, got ' + events.join(','))
    assert.equal(build.action, 'template', f.kind + ': ' + build.note)
    assert.match(build.source, /Filled Title/, f.kind + ': filled screen')
    assert.notEqual(build.source, p.source, f.kind + ': the filled screen replaces the preview')
    assert.notEqual(build.composition, p.composition, f.kind)
  }

  // The fill answers nothing: the final screen is the default text, the same program as the preview.
  answer = () => null
  let {build, previews} = await run(jev(['checklist']))
  assert.equal(build.action, 'template'); assert.match(build.note, /content=default\(no response\)/)
  assert.equal(build.source, previews[0].source)
  answer = () => JSON.stringify({title: 'Filled Title'})

  // The filled screen does not compile: the preview stays the result instead of generating from scratch.
  const realCompose = compose.composeProgram
  compose.composeProgram = (kinds, globals, values) => globals.get('__TITLE__') === 'Filled Title' ? 'not a program' : realCompose(kinds, globals, values)
  ;({build, previews} = await run(jev(['checklist'])))
  compose.composeProgram = realCompose
  assert.equal(build.action, 'template'); assert.equal(build.source, previews[0].source); assert.equal(build.vbc2, previews[0].vbc2)
  assert.match(build.note, /failed to compile; kept the default text/); assert.doesNotMatch(build.note, /pending/)

  // Stop while the fill runs (the preview is up): cancelled, and the caller keeps the preview.
  ;({build, previews} = await run(jev(['checklist']), {cancel: true}))
  assert.equal(build.action, 'cancelled'); assert.equal(previews.length, 1); assert.deepEqual(events, ['preview', 'fill'])

  // A base the model finishes (a soft veto, placeholder buttons only) is not shown early.
  ;({build, previews} = await run(jev(['checklist'], {needs_logic: 0.95})))
  assert.equal(build.action, 'complete'); assert.equal(previews.length, 0)
  ;({build, previews} = await run(jev(['actions'])))
  assert.equal(build.action, 'complete'); assert.equal(previews.length, 0)

  // A grounded request: the preview comes before the search too.
  ;({build, previews} = await run(jev(['trend_chart'])))
  assert.equal(previews.length, 1); assert.match(build.note, /search=ok/)

  console.log('template-preview-check: ok (' + fragments().length + ' fragment kinds)')
})().catch(e => { console.error(e); process.exit(1) })
