// The second opinion on a weak pick: Jev's weak candidates are reported, a confirmed one is built as if it had cleared
// the bar, the model's answer is read strictly (only named candidates, anything odd confirms nothing). No network.
'use strict'
const assert = require('node:assert/strict')
const {loadVera} = require('./source-loader')
const {readSectionPick} = loadVera('VeraSectionCompose')
const {readVerifyAnswer, buildVerifyUser} = loadVera('VeraPickVerify')

function body(sections, vetoes = {}, extra = {}) {
  const answers = {}
  sections.forEach(([k, c], i) => { answers['section' + (i + 1)] = {choice: k, confidence: c} })
  for (let i = sections.length; i < 6; i++) answers['section' + (i + 1)] = {choice: 'none', confidence: 0.6}
  const keys = ['needs_integration', 'needs_real_data', 'needs_search_or_form', 'needs_live_ticking', 'needs_multiple_counters', 'needs_logic']
  keys.forEach(k => { answers['veto.' + k] = {noul: vetoes[k] === undefined ? 0 : vetoes[k]} })
  Object.assign(answers, extra)
  return JSON.stringify({answers})
}
const kinds = o => o.sections.map(s => s.kind).filter(k => k !== 'none')

// the shape of "List for 10 people for birthday cake": checklist 0.30, nothing else
let weak = readSectionPick(body([['checklist', 0.30], ['none', 0.5]]))
assert.equal(weak.sections, null); assert.deepEqual(weak.weakKinds, ['checklist'])
// below the weak floor is not a candidate
assert.deepEqual(readSectionPick(body([['checklist', 0.20]])).weakKinds, [])
// several sections naming the same or different weak kinds: distinct, in section order
assert.deepEqual(readSectionPick(body([['checklist', 0.3], ['note', 0.4], ['checklist', 0.45]])).weakKinds, ['checklist', 'note'])
// a strong pick leaves nothing weak and is untouched
let strong = readSectionPick(body([['checklist', 0.8]]))
assert.deepEqual(kinds(strong), ['checklist']); assert.deepEqual(strong.weakKinds, [])
// a hard veto reports nothing weak: it must not be second-guessed
let vetoed = readSectionPick(body([['checklist', 0.3]], {needs_integration: 0.95}))
assert.equal(vetoed.sections, null); assert.deepEqual(vetoed.weakKinds, [])
// confirmed: built as picked; an unconfirmed other kind stays out
let confirmed = readSectionPick(body([['checklist', 0.3], ['note', 0.4]]), ['checklist'])
assert.deepEqual(kinds(confirmed), ['checklist']); assert.deepEqual(confirmed.weakKinds, [])
// confirming a kind that was never a candidate changes nothing
assert.equal(readSectionPick(body([['checklist', 0.3]]), ['timeline']).sections, null)
// a confirmed kind below the weak floor is still not picked
assert.equal(readSectionPick(body([['checklist', 0.1]]), ['checklist']).sections, null)

// the model's answer
const cand = ['checklist', 'note']
assert.deepEqual(readVerifyAnswer('{"confirm": ["checklist"], "missing": ""}', cand).confirmed, ['checklist'])
assert.deepEqual(readVerifyAnswer('```json\n{"confirm": ["note", "checklist", "note"], "missing": "x"}\n```', cand).confirmed, ['note', 'checklist'])
assert.deepEqual(readVerifyAnswer('{"confirm": ["timeline", "key_facts"]}', cand).confirmed, [], 'only named candidates')
assert.deepEqual(readVerifyAnswer('{"confirm": "checklist"}', cand).confirmed, [], 'not an array')
assert.deepEqual(readVerifyAnswer('sure, the checklist is fine', cand).confirmed, [], 'prose')
assert.deepEqual(readVerifyAnswer('', cand).confirmed, [])
assert.equal(readVerifyAnswer('{"confirm": [], "missing": "  scaling by the number of people  "}', cand).missing, 'scaling by the number of people')
assert.equal(readVerifyAnswer('{"confirm": [], "missing": ' + JSON.stringify('x'.repeat(200)) + '}', cand).missing.length, 80)

// the question names the request and each candidate's criteria text
const user = buildVerifyUser('List for 10 people for birthday cake', ['checklist', 'nonsense'])
assert.match(user, /^Request: List for 10 people for birthday cake/); assert.match(user, /- checklist: /); assert.doesNotMatch(user, /nonsense/)
console.log('verify-check ok')
