const assert = require('node:assert/strict')
const fs = require('node:fs'), path = require('node:path')
const {loadVera} = require('./source-loader')
const {compileVeraSource, widgetRefinementError, spliceWidget} = loadVera('VeraCompiler')
const {smokeRun} = loadVera('VeraSmoke')
const {widgetRefinementPrompt, validateWidgetRefinement, widgetRepairNote} = loadVera('VeraWidgetRefine')
const {WidgetSession} = loadVera('VeraLiveWidget')
const source = fs.readFileSync(path.join(__dirname,'../../entry/src/main/resources/rawfile/widget-counter.vera'),'utf8')
// Standalone fullscreen base, not a view delegating to widget.
const base = source.replace('function widget(', 'function compact(').replace('return widget(state);','return compact(state);')
const addition = '\nfunction widget(state: AppState): ui.View { return compact(state); }'
const candidate = base + addition
const compiled = compileVeraSource(candidate)
assert.equal(widgetRefinementError(base,candidate), '')
assert.equal(widgetRefinementError(base,'// comment\n' + candidate.replace('count: 0','count : 0')), '')
for (const [from,to,name] of [['count: number','count: string','AppState'],['count: 0','count: 10','init'],['state.count + value','state.count - value','change'],['return compact(state);','return ui.Text("body", "changed");','view']]) {
  assert.match(widgetRefinementError(base,candidate.replace(from,to)),new RegExp(name))
}
assert.match(widgetRefinementError(base,base),/add function widget/)
assert.equal(validateWidgetRefinement(base,candidate,compiled.vbc2), '')
assert.equal(smokeRun(compiled),'')
for (const altered of [candidate.replace('function widget(state: AppState)', 'async function widget(state: AppState)'),candidate.replace('function widget(state: AppState)', 'function widget(state: number)'),candidate.replace('function widget(state: AppState): ui.View', 'function widget(state: AppState): AppState')]) {
  assert.throws(()=>compileVeraSource(altered),/E2112/)
}
const unsafe = candidate.replace('return compact(state); }\nfunction widget','return compact(state); }\nfunction widget')
  .replace('function widget(state: AppState): ui.View { return compact(state); }','function widget(state: AppState): ui.View { return ui.Image("default", "url", "alt"); }')
assert.match(smokeRun(compileVeraSource(unsafe)),/Not card-safe/)
const saved = new WidgetSession(compiled.vbc2,'v','')
let frame = saved.frame('p','App','')
saved.tap(frame,frame.token,'change',1)
assert.equal(validateWidgetRefinement(base,candidate,compiled.vbc2,saved.encodedState()),'')
const prompt = widgetRefinementPrompt(), {CATALOG} = loadVera('VeraUiCatalog')
for (const component of CATALOG) {
  assert.equal(prompt.includes('  ui.' + component.name + '('),component.card,component.name)
}
assert.match(prompt,/100000 VM steps/)
assert.match(prompt,/8000 UTF-16/)
// What a widget is: the same state, what the person asked for, only the few things that matter.
assert.match(prompt,/draws the very state view\(state\) draws/)
assert.match(prompt,/request says what it should show/)
assert.match(prompt,/one to three figures/)
assert.match(prompt,/at most two buttons/)
// The reply's rewrite of an existing declaration is not taken; its widget, new helpers and new imports are.
const rewritten = 'import * as math from "std/math"\n' + base.replace('state.count + value', 'state.count + value * 2') +
  '\nfunction twice(n: number): number { return n * 2; }' + addition
const spliced = spliceWidget(base, rewritten)
assert.equal(widgetRefinementError(base, spliced), '')
assert.match(spliced, /state\.count \+ value \}/)
assert.doesNotMatch(spliced, /value \* 2/)
assert.match(spliced, /function twice/)
assert.match(spliced, /^import \* as math from "std\/math"/)
assert.equal(validateWidgetRefinement(base, spliced, compileVeraSource(spliced).vbc2), '')
// A widget already there is replaced; a reply that does not parse is left for the compiler.
assert.equal((spliceWidget(candidate, base + '\nfunction widget(state: AppState): ui.View { return ui.Text("body", "new"); }').match(/function widget/g) || []).length, 1)
assert.equal(spliceWidget(base, 'not a program {'), 'not a program {')
// A missing field is explained: the app's state is kept as it is.
assert.match(widgetRepairNote('3:5 E2031 class AppState has no field doneToday'), /cannot add fields to the state/)
assert.equal(widgetRepairNote('3:5 E2036 expected 5 arguments, found 4'), '3:5 E2036 expected 5 arguments, found 4')
// A widget is a glance: a button per item is refused with the reason, for the next attempt.
const crowded = base + '\nfunction widget(state: AppState): ui.View { return ui.Column("default", [ui.Button("default", "+1", "change", 1, true), ' +
  'ui.Button("default", "+2", "change", 2, true), ui.Button("default", "+3", "change", 3, true)]); }'
assert.match(validateWidgetRefinement(base, crowded, compileVeraSource(crowded).vbc2), /3 buttons; a widget has at most 2/)
console.log('PASS widget refinement: additive preservation, signature, catalogue prompt, smoke/repair diagnostics, saved-state validation, glance limits, splice')
