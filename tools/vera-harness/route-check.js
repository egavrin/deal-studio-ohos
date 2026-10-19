// The route texts the Generate screen prints: what Jev said, the second look, and why the request went the way it did.
'use strict'
const assert = require('node:assert/strict')
const {loadVera} = require('./source-loader')
const r = loadVera('VeraRoute')
const info = (o) => Object.assign(new r.RouteInfo(), o)

assert.equal(r.logicOf('section1=checklist logic=needs_logic=0.99,needs_integration=0.5 content: x'), 'needs_logic=0.99, needs_integration=0.5')
assert.equal(r.logicOf('section1=checklist'), '')

// labels
assert.equal(r.routeLabel(info({route: 'blocks'})), 'Blocks, no model call')
assert.match(r.routeLabel(info({route: 'blocks+model'})), /model finishes/)
assert.match(r.routeLabel(info({route: 'scratch'})), /From scratch/)
assert.equal(r.jevLabel(info({jev: 'sure', kinds: ['checklist', 'timeline']})), 'Jev: chose checklist + timeline')
assert.equal(r.jevLabel(info({jev: 'unsure'})), 'Jev: unsure'); assert.equal(r.jevLabel(info({jev: 'vetoed'})), 'Jev: vetoed blocks')
assert.equal(r.checkLabel(info({check: 'none'})), 'Check: not needed'); assert.equal(r.checkLabel(info({check: 'off'})), 'Check: off')
assert.equal(r.checkLabel(info({check: 'yesno', wanted: 'checklist', wantedP: 0.6})), 'Check: yes/no question picked checklist (0.60)')
assert.equal(r.checkLabel(info({check: 'confirmed', kinds: ['checklist']})), 'Check: DeepSeek confirmed checklist')
assert.match(r.checkLabel(info({check: 'rejected'})), /rejected/); assert.match(r.checkLabel(info({check: 'failed'})), /did not answer/)

// reasons: every route says which of the four things happened
assert.match(r.routeWhy(info({route: 'blocks', jev: 'sure', kinds: ['checklist']})), /Jev was sure: it chose checklist\. No model call/)
assert.match(r.routeWhy(info({route: 'blocks', jev: 'unsure', check: 'confirmed', weak: ['checklist'], kinds: ['checklist']})), /unsure \(checklist\).*DeepSeek checked it and confirmed checklist/)
assert.match(r.routeWhy(info({route: 'blocks', jev: 'unsure', check: 'yesno', wanted: 'timeline', wantedP: 0.7, kinds: ['timeline']})), /yes\/no question "does the request ask for timeline" answered 0\.70/)
assert.match(r.routeWhy(info({route: 'blocks+model', jev: 'sure', kinds: ['timer'], logic: 'needs_integration=0.82'})), /Then the model finishes it because the request also needs a phone API or another app \(0\.82\)/)
assert.match(r.routeWhy(info({route: 'scratch', jev: 'unsure', check: 'rejected', weak: ['checklist'], missing: 'scaling by people'})), /DeepSeek checked and rejected it: it cannot do scaling by people/)
assert.match(r.routeWhy(info({route: 'scratch', jev: 'unsure', check: 'off', weak: ['checklist']})), /the DeepSeek check is off/)
assert.match(r.routeWhy(info({route: 'scratch', jev: 'unsure', check: 'failed', weak: ['note']})), /did not answer/)
assert.match(r.routeWhy(info({route: 'scratch', jev: 'vetoed', note: 'vetoed needs_integration=0.97'})), /vetoed building this from blocks \(needs_integration=0\.97\)/)
assert.match(r.routeWhy(info({route: 'scratch', jev: 'none'})), /no block that fits/)
assert.match(r.routeWhy(info({route: 'scratch', jev: 'unavailable', note: 'none (selector unreachable)'})), /did not answer \(none \(selector unreachable\)\)/)
assert.equal(r.routeWhy(info({route: 'scratch', jev: 'sure', failure: 'Jev chose x, but it did not compile.'})), 'Jev chose x, but it did not compile.')
assert.deepEqual(['blocks', 'blocks+model', 'scratch'].map(x => r.routeShort(info({route: x}))), ['Blocks', 'Blocks + model', 'Scratch'])
assert.deepEqual(['none', 'off', 'yesno', 'confirmed', 'rejected', 'failed'].map(x => r.checkShort(info({check: x}))), ['not needed', 'off', 'yes/no', 'confirmed', 'rejected', 'no answer'])
assert.equal(r.vetoWords('needs_logic=0.99'), 'calculation or logic (0.99)'); assert.equal(r.vetoWords('needs_x'), 'needs_x')
console.log('route-check ok')
