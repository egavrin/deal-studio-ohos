// The request rewrite (VeraRequestExpand.ets) and how buildFromTemplates uses it: only when Jev picked nothing, only
// a pick counts, a veto is never lost, the rewrite is dropped when Jev answered. Canned answers, no network.
'use strict'
const assert = require('node:assert/strict')
const {loadVera} = require('./source-loader')
const compose = loadVera('VeraSectionCompose')
const expand = loadVera('VeraRequestExpand')
const {deepseek} = loadVera('DeepSeekEngine')
const {settings} = loadVera('SettingsStore')
const {buildFromTemplates} = loadVera('VeraTemplatePipeline')

// cleanExpanded: what a usable rewrite is
const clean = expand.cleanExpanded
assert.equal(clean('  A phone app screen that shows the weather.  ', 'weather'), 'A phone app screen that shows the weather.')
assert.equal(clean('"A phone app screen that adds two numbers."', 'add'), 'A phone app screen that adds two numbers.')
assert.equal(clean("'A phone app screen that adds two numbers.'", 'add'), 'A phone app screen that adds two numbers.')
assert.equal(clean('```\nA phone app screen that adds.\n```', 'add'), 'A phone app screen that adds.')
assert.equal(clean('A phone app screen that adds.\n\nThis works because...', 'add'), 'A phone app screen that adds.')
assert.equal(clean('', 'x'), '')
assert.equal(clean('   ', 'x'), '')
assert.equal(clean("I can't help with that.", 'x'), '')
assert.equal(clean("Sorry, that is not possible", 'x'), '')
assert.equal(clean('x'.repeat(expand.EXPAND_MAX_CHARS + 1), 'x'), '')
assert.equal(clean('x'.repeat(expand.EXPAND_MAX_CHARS), 'y').length, expand.EXPAND_MAX_CHARS)
assert.equal(clean('Tip Calc', 'tip calc'), '', 'the original, however it is cased, is not a rewrite')

settings.getSelectorKey = () => 'test-key'
settings.hasApiKey = () => true
settings.hasExaKey = () => false
const filled = []
deepseek.extractTemplateContent = async (system, user) => {
  filled.push(user)
  return JSON.stringify({title: 'Test', section1_items: [['Milk', '2 L'], ['Eggs', '12'], ['Bread', '']]})
}

function jev(sections, vetoes, extra) {
  const answers = Object.assign({}, extra)
  sections.forEach((k, i) => { answers['section' + (i + 1)] = {choice: k, confidence: 0.9} })
  for (const k of ['needs_integration', 'needs_real_data', 'needs_search_or_form', 'needs_live_ticking', 'needs_multiple_counters', 'needs_multiple_series', 'needs_logic'])
    answers['veto.' + k] = {noul: (vetoes || {})[k] || 0}
  return compose.readSectionPick(JSON.stringify({answers}))
}

// Jev answers by the text it is given; `rewrite` is what the model returns ('' for none).
async function run(prompt, answers, rewrite, opts = {}) {
  const asked = []
  let expandCalls = 0
  compose.selectSections = async text => { asked.push(text); return answers[text] || jev(['none', 'none']) }
  expand.expandRequestsEnabled = () => true
  expand.expandRequest = async () => { expandCalls++; return {text: rewrite, ms: 7} }
  filled.length = 0
  let cancelled = false
  const build = await buildFromTemplates(prompt, opts.mode || 'deepseek', () => {}, () => {
    if (opts.cancelAfterRewrite && expandCalls > 0 && asked.length === 1) cancelled = true
    return cancelled
  })
  return {build, asked, expandCalls}
}
const REWRITE = 'A phone app screen that keeps a grocery list.'

;(async () => {
  // Jev answered: the rewrite is not used, Jev is asked once, the route says nothing about a rewrite
  let r = await run('grocery', {grocery: jev(['checklist'])}, REWRITE)
  assert.equal(r.build.action, 'template'); assert.deepEqual(r.asked, ['grocery']); assert.equal(r.build.route.expanded, ''); assert.equal(r.build.route.expandMs, -1)

  // Jev picked nothing, the rewrite gives it something: asked twice, the rewrite is what the model is shown
  r = await run('groc', {[REWRITE]: jev(['checklist'])}, REWRITE)
  assert.equal(r.build.action, 'template'); assert.deepEqual(r.asked, ['groc', REWRITE])
  assert.equal(r.build.route.expanded, REWRITE); assert.equal(r.build.route.expandMs, 7)
  assert.ok(filled.length > 0 && filled.every(u => u.includes(REWRITE)), 'the text fill sees the rewrite')
  assert.match(loadVera('VeraRoute').routeWhy(r.build.route), /found nothing for the request as typed.*rewrote it/)

  // the rewrite is vetoed: the first answer stands, the route is scratch, nothing says a rewrite was used
  r = await run('groc', {[REWRITE]: jev(['checklist'], {needs_integration: 0.97})}, REWRITE)
  assert.equal(r.build.action, 'scratch'); assert.deepEqual(r.asked, ['groc', REWRITE]); assert.equal(r.build.route.expanded, '')
  assert.doesNotMatch(r.build.note, /vetoed needs_integration/, 'the first answer, not the rewrite\'s veto')

  // a veto on the request as typed is also "nothing picked", so the rewrite is tried; if the rewrite picks blocks it wins.
  // What keeps a correct veto is the rewrite prompt (it must keep camera, microphone, other-app and live-data needs) and the
  // second Jev's own veto, measured on the negative prompt set -- not this gate. If the rewrite is vetoed too, the first stands.
  r = await run('video call mom', {'video call mom': jev(['checklist'], {needs_integration: 0.97}), [REWRITE]: jev(['checklist'], {needs_integration: 0.95})}, REWRITE)
  assert.equal(r.build.action, 'scratch'); assert.match(r.build.note, /vetoed needs_integration=0\.97/); assert.equal(r.build.route.expanded, '')
  r = await run('weather', {weather: jev(['checklist'], {needs_integration: 0.97}), [REWRITE]: jev(['checklist'])}, REWRITE)
  assert.equal(r.build.action, 'template'); assert.equal(r.build.route.expanded, REWRITE)

  // the rewrite only "wanted" a block (no section chose it): the first answer, nothing, stands -- a rewrite of "animated dice"
  // became an intent panel at 0.62 and the request was no longer generated from scratch
  r = await run('dice', {[REWRITE]: jev(['none'], {}, {'include.checklist': {noul: 0.62}})}, REWRITE)
  assert.equal(jev(['none'], {}, {'include.checklist': {noul: 0.62}}).wanted, 'checklist', 'the helper really builds a wanted pick')
  assert.equal(r.build.action, 'scratch'); assert.equal(r.build.route.expanded, '')

  // the rewrite is another nothing
  r = await run('groc', {}, REWRITE)
  assert.equal(r.build.action, 'scratch'); assert.equal(r.build.route.expanded, '')

  // Jev did not answer (timeout, error): a second call would only wait out another timeout
  r = await run('groc', {groc: new compose.SectionPickOutcome(null, new Map(), 'none (selector unreachable)'), [REWRITE]: jev(['checklist'])}, REWRITE)
  assert.equal(r.build.action, 'scratch'); assert.deepEqual(r.asked, ['groc']); assert.equal(r.build.route.expanded, '')

  // no rewrite came back: one Jev call
  r = await run('groc', {}, '')
  assert.equal(r.build.action, 'scratch'); assert.deepEqual(r.asked, ['groc'])

  // no model to ask in this mode: the rewrite is not even started
  r = await run('groc', {[REWRITE]: jev(['checklist'])}, REWRITE, {mode: 'server'})
  assert.equal(r.expandCalls, 0); assert.equal(r.build.action, 'scratch')

  // cancelled while the rewrite was pending
  r = await run('groc', {[REWRITE]: jev(['checklist'])}, REWRITE, {cancelAfterRewrite: true})
  assert.equal(r.build.action, 'cancelled'); assert.deepEqual(r.asked, ['groc'])

  console.log('expand-check ok')
})().catch(e => { console.error(e); process.exit(1) })
