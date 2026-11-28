// Unit checks for the hybrid local-decision routing: the hard/cloud-tier
// classifier, the Jev-body split, the per-question fallback body, and the answer
// merge. Pure functions, no model, no device.
'use strict'
const assert = require('node:assert/strict')
const {loadVera} = require('./source-loader')

const local = loadVera('VeraLocalDecision')

// The hard tier is the verify/claims question keys ("does.N") plus the
// formula/anatomy picks the calibration data keeps on the cloud ("expr.N",
// "show.N" -- 1/13 and 7/13 agreement, docs/local-jev/cpu-vs-cloud.md).
assert.equal(local.isHardQuestion('does.0'), true)
assert.equal(local.isHardQuestion('does.12'), true)
assert.equal(local.isHardQuestion('expr.total'), true)
assert.equal(local.isHardQuestion('show.total'), true)
for (const key of ['theme', 'steps.total', 'written.total', 'live.0',
  'whose.0', 'ready.0', 'clock.part', 'list.part', 'unit.from', 'widget.name',
  'within.value.v', 'within.event.e', 'asked.name', 'arg.e.fx.p', 'doesnot']) {
  assert.equal(local.isHardQuestion(key), false, key + ' must be easy/standard')
}

// A mixed body splits by key; both halves keep the same state and model.
const body = JSON.stringify({
  model: 'jev-latest',
  state: 'Request: a to-do app\nThe section, as code:\nfunction view(){}',
  questions: {
    'does.0': {type: 'choice', instructions: 'x', criteria: {yes: 'y', no: 'n'}},
    'does.1': {type: 'choice', instructions: 'y', criteria: {yes: 'y', no: 'n'}},
    'expr.total': {type: 'choice', instructions: 'z', criteria: {a: '1', b: '2'}},
    'theme': {type: 'choice', instructions: 't', criteria: {clean: 'c', soft: 's'}}
  }
})
const split = local.splitJevBody(body)
assert.equal(split.hardCount, 3)
assert.equal(split.easyCount, 1)
const hard = JSON.parse(split.hard)
const easy = JSON.parse(split.easy)
assert.deepEqual(Object.keys(hard.questions).sort(), ['does.0', 'does.1', 'expr.total'])
assert.deepEqual(Object.keys(easy.questions).sort(), ['theme'])
assert.equal(hard.state, JSON.parse(body).state, 'hard keeps the shared state')
assert.equal(easy.state, JSON.parse(body).state, 'easy keeps the shared state')
assert.equal(hard.model, 'jev-latest')
assert.equal(easy.model, 'jev-latest')

// An all-hard body (a verify/claims call) has no easy half.
const allHard = JSON.stringify({model: 'jev-latest', state: 's',
  questions: {'does.0': {type: 'choice'}, 'does.1': {type: 'choice'}}})
const sh = local.splitJevBody(allHard)
assert.equal(sh.hardCount, 2)
assert.equal(sh.easyCount, 0)
assert.equal(sh.easy, '', 'no easy half when nothing is easy')

// An all-easy body (a compose/align/edit call) has no hard half.
const allEasy = JSON.stringify({model: 'jev-latest', state: 's',
  questions: {'theme': {type: 'choice'}, 'live.0': {type: 'noul'}}})
const se = local.splitJevBody(allEasy)
assert.equal(se.hardCount, 0)
assert.equal(se.easyCount, 2)
assert.equal(se.hard, '', 'no hard half when nothing is hard')

// A body that cannot be parsed comes back whole on the easy side (still answered).
const junk = local.splitJevBody('not json')
assert.equal(junk.easyCount, 1)
assert.equal(junk.easy, 'not json')
assert.equal(junk.hardCount, 0)

// Merging keeps every answer from both halves; '' and junk contribute nothing.
const hardReply = JSON.stringify({answers: {'does.0': {choice: 'yes', confidence: 0.9}}})
const easyReply = JSON.stringify({answers: {theme: {choice: 'soft', confidence: 0.7},
  'expr.total': {choice: 'a+b', confidence: 0.6}}})
const merged = JSON.parse(local.mergeJevAnswers(hardReply, easyReply))
assert.deepEqual(Object.keys(merged.answers).sort(), ['does.0', 'expr.total', 'theme'])
assert.equal(merged.answers['does.0'].choice, 'yes')
assert.equal(merged.answers.theme.choice, 'soft')

const mergedOne = JSON.parse(local.mergeJevAnswers('', easyReply))
assert.deepEqual(Object.keys(mergedOne.answers).sort(), ['expr.total', 'theme'],
  'an empty hard reply adds nothing')
const mergedNone = JSON.parse(local.mergeJevAnswers('junk', ''))
assert.deepEqual(mergedNone.answers, {}, 'nothing answered is an empty answers map, still valid JSON')

// The per-question fallback: the cloud body is exactly the questions the local
// model did not answer. A partial local reply leaves holes for the cloud only.
const easyBody = JSON.stringify({model: 'jev-latest', state: 's',
  questions: {'steps.count': {type: 'choice', instructions: 'i', criteria: {one: 'a', more: 'b'}},
    'theme': {type: 'choice', instructions: 't', criteria: {clean: 'c', soft: 's'}}}})
const partial = JSON.stringify({answers: {'steps.count': {choice: 'one', confidence: 0.85}}})
const rest = JSON.parse(local.unansweredJevBody(easyBody, partial))
assert.deepEqual(Object.keys(rest.questions), ['theme'])
assert.equal(rest.model, 'jev-latest')
assert.equal(rest.state, 's')
// a full reply leaves nothing for the cloud
assert.equal(local.unansweredJevBody(easyBody,
  JSON.stringify({answers: {'steps.count': {choice: 'one'}, 'theme': {choice: 'clean'}}})), '')
// an empty or unparseable reply (stub, uncalibrated model) leaves everything
assert.equal(local.unansweredJevBody(easyBody, ''), easyBody)
assert.equal(local.unansweredJevBody(easyBody, 'not json'), easyBody)
// and the merge of a partial local reply with the cloud's answers has no holes
const both = JSON.parse(local.mergeJevAnswers(partial,
  JSON.stringify({answers: {theme: {choice: 'clean', confidence: 1}}})))
assert.deepEqual(Object.keys(both.answers).sort(), ['steps.count', 'theme'])
assert.equal(both.answers['steps.count'].choice, 'one')
assert.equal(both.answers['theme'].choice, 'clean')

// Over-budget bodies split in halves: each half keeps the state and the model.
const big = JSON.stringify({model: 'jev-latest', state: 's', questions: {
  'theme': {type: 'choice'}, 'a': {type: 'choice'}, 'b': {type: 'choice'}, 'c': {type: 'choice'}}})
const halves = local.splitJevBodyHalf(big)
assert.equal(halves.length, 2)
const h0 = JSON.parse(halves[0]), h1 = JSON.parse(halves[1])
assert.equal(h0.state, 's'); assert.equal(h1.state, 's')
assert.equal(h0.model, 'jev-latest'); assert.equal(h1.model, 'jev-latest')
assert.deepEqual(Object.keys(h0.questions).sort(), ['a', 'theme'])
assert.deepEqual(Object.keys(h1.questions).sort(), ['b', 'c'])
assert.equal(local.splitJevBodyHalf(JSON.stringify({state: 's', questions: {'a': {}}})).length, 0,
  'a single question cannot be split')
assert.equal(local.splitJevBodyHalf('not json').length, 0)

// The reason a local reply answered nothing, and the merged refit datum.
assert.equal(local.jevLocalReason('{"answers":{},"local":{"status":"uncertain","reason":"call_token_budget"}}'),
  'call_token_budget')
assert.equal(local.jevLocalReason('{"answers":{}}'), '')
assert.equal(local.jevLocalReason('junk'), '')
const withScores = local.mergeJevAnswers(
  '{"answers":{"a":{"choice":"x"}},"scores":{"a":{"logits":{"x":1,"y":0}}}}',
  '{"answers":{"b":{"choice":"y"}},"scores":{"b":{"logits":{"y":2,"z":1}}}}')
const mergedScores = JSON.parse(withScores)
assert.deepEqual(Object.keys(mergedScores.answers).sort(), ['a', 'b'])
assert.deepEqual(Object.keys(mergedScores.scores).sort(), ['a', 'b'], 'raw logits survive the merge')

// The default backend is unavailable, so the route falls back to the cloud.
assert.equal(local.localDecisionModel().available(), false, 'no model registered by default')

console.log('local-decision-route-check: ok')