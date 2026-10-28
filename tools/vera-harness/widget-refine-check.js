const assert = require('node:assert/strict')
const fs = require('node:fs'), path = require('node:path')
const {loadVera} = require('./source-loader')
const {compileVeraSource, widgetRefinementError} = loadVera('VeraCompiler')
const {smokeRun} = loadVera('VeraSmoke')
const {widgetRefinementPrompt, validateWidgetRefinement} = loadVera('VeraWidgetRefine')
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
console.log('PASS widget refinement: additive preservation, signature, catalogue prompt, smoke/repair diagnostics, saved-state validation')
