// The general blocks behind "shared costs between friends": record_log (source) and number_strip,
// breakdown_table, series_chart, settle_up (readers), driven in the real VM with the numbers of the example.
// Nothing here says "expenses": the labels and captions are plain content values.
'use strict'
const assert = require('node:assert/strict')
const {loadVera} = require('./source-loader')
const {fragments} = loadVera('VeraTemplates')
const {expandListRows} = loadVera('VeraTemplateContent')
const {composeProgram} = loadVera('VeraSectionCompose')
const {compileVeraSource} = loadVera('VeraCompiler')
const {VirtualMachine, deserializeVbc2, decodeRuntimeValue} = loadVera('VeraInterpreter')
const {UiHostEnvironment, decodeVeraUi} = loadVera('VeraUi')
const num = v => decodeRuntimeValue(['n', v])
const str = v => decodeRuntimeValue(['s', v])

const globals = new Map([['__THEME__', 'clean'], ['__HEADER_STYLE__', 'default'], ['__BANNER_SECTION__', 'hide'], ['__TITLE__', 'Check']])
function values(kind, over = {}) {
  const spec = fragments().find(f => f.kind === kind), m = new Map()
  spec.slots.forEach(s => m.set(s.token, s.values[0]))
  spec.contentFields.forEach(c => m.set(c.token, c.token === '__CURRENCY_IDX__' ? '$' : c.fallback))
  spec.listFields.forEach(l => m.set(l.token, kind === 'record_log' && over.labels !== undefined
    ? over.labels.map(n => '"' + n + '"').join(', ') : expandListRows(undefined, l).text))
  return m
}
function build(kinds, over = {}) {
  const src = composeProgram(kinds, globals, kinds.map(k => values(k, over)))
  const r = compileVeraSource(src)
  return new VirtualMachine(deserializeVbc2(r.vbc2 !== undefined ? r.vbc2 : r), new UiHostEnvironment())
}
const walk = (n, f) => { f(n); (n.children || []).forEach(c => walk(c, f)) }
const view = (vm, st) => decodeVeraUi(vm.execute('view', [st]))[0]
const strings = (vm, st) => { const out = []; walk(view(vm, st), n => { out.push(n.text, n.label, n.value, ...(n.options || [])) }); return out.filter(Boolean) }
const nums = (vm, st) => { const out = []; walk(view(vm, st), n => { if (n.kind === 'numberstat') out.push(n.numberValue) }); return out }
const series = (vm, st) => { let s = null; walk(view(vm, st), n => { if (n.kind === 'sparkline') s = n }); return s }

const ALL = ['record_log', 'number_strip', 'breakdown_table', 'series_chart', 'settle_up']
const names = ['Anna', 'Ben', 'Carol', 'Dan']

{
  const vm = build(ALL, {labels: names})
  let st = vm.execute('init')
  assert.deepEqual(nums(vm, st), [0, 0]); assert.match(strings(vm, st).join('|'), /All settled up/)
  const add = (who, amount, note = '') => {
    st = vm.execute('setWho1', [st, num(who)]); st = vm.execute('setAmount1', [st, str(amount)])
    st = vm.execute('setNote1', [st, str(note)]); st = vm.execute('addRecord1', [st, num(0)])
  }
  add(0, '120', 'dinner'); add(2, '60', 'taxi')
  assert.deepEqual(nums(vm, st), [180, 45], 'total and average')
  assert.deepEqual(Array.from(series(vm, st).series), [120, 0, 60, 0]); assert.deepEqual(Array.from(series(vm, st).categories), names)
  const s = strings(vm, st).join('|')
  assert.match(s, /Ben pays Anna/); assert.match(s, /Dan pays Anna/); assert.match(s, /Dan pays Carol/)
  assert.doesNotMatch(s, /Anna pays|Carol pays|Ben pays Carol/)
  assert.match(s, /\+\$75\.00/); assert.match(s, /-\$45\.00/); assert.match(s, /\+\$15\.00/)
  assert.match(s, /\$45\.00/); assert.match(s, /dinner/); assert.match(s, /taxi/)
  // every settled balance goes to zero: the transfers add up to what the creditors are owed
  let paid = 0; walk(view(vm, st), n => { if (/ pays /.test(n.text || '')) paid += parseFloat(n.value.replace('$', '')) })
  assert.equal(paid, 90, 'creditors are owed 75 + 15')
  // cents, rounded to cents; a blank or non-positive amount adds nothing
  add(1, '10.10'); add(1, '5.05')
  assert.deepEqual(nums(vm, st), [195.15, 48.79]); assert.equal(Array.from(series(vm, st).series)[1], 15.15)
  const before = JSON.stringify([nums(vm, st), Array.from(series(vm, st).series)])
  add(1, ''); add(1, '0'); add(1, 'abc')
  assert.equal(JSON.stringify([nums(vm, st), Array.from(series(vm, st).series)]), before, 'blank, zero and text amounts are ignored')
  st = vm.execute('removeLastRecord1', [st, num(0)])
  assert.deepEqual(nums(vm, st), [190.1, 47.53])
  st = vm.execute('clearRecords1', [st, num(0)])
  assert.deepEqual(nums(vm, st), [0, 0]); assert.match(strings(vm, st).join('|'), /All settled up/)
  st = vm.execute('clearRecords1', [st, num(0)])   // clearing nothing is fine
}

// the balance chart variant and the count: cosmetic slots flip what the readers show
{
  const vals = ALL.map(k => values(k, {labels: names}))
  vals[1].set('__SHOW_COUNT_IDX__', 'true'); vals[3].set('__USE_BALANCES_IDX__', 'true')
  const r = compileVeraSource(composeProgram(ALL, globals, vals))
  const vm = new VirtualMachine(deserializeVbc2(r.vbc2 !== undefined ? r.vbc2 : r), new UiHostEnvironment())
  let st = vm.execute('init')
  st = vm.execute('setAmount1', [st, str('100')]); st = vm.execute('addRecord1', [st, num(0)])
  assert.deepEqual(nums(vm, st), [100, 25, 1], 'count shown')
  assert.deepEqual(Array.from(series(vm, st).series), [75, -25, -25, -25], 'balances, negative bars included')
}


// odd cents: balances are whole cents that sum to exactly zero, and the transfers add up to what is owed
{
  const vals = ALL.map(k => values(k, {labels: names}))
  vals[3].set('__USE_BALANCES_IDX__', 'true')
  const r = compileVeraSource(composeProgram(ALL, globals, vals))
  const vm = new VirtualMachine(deserializeVbc2(r.vbc2 !== undefined ? r.vbc2 : r), new UiHostEnvironment())
  let st = vm.execute('init')
  st = vm.execute('setAmount1', [st, str('120.50')]); st = vm.execute('addRecord1', [st, num(0)])
  const bals = Array.from(series(vm, st).series)
  assert.deepEqual(bals, [90.37, -30.13, -30.12, -30.12]); assert.equal(Math.round(bals.reduce((a, b) => a + b, 0) * 100), 0, 'sum is zero')
  let paid = 0; walk(view(vm, st), n => { if (/ pays /.test(n.text || '')) paid += Math.round(parseFloat(n.value.replace('$', '')) * 100) })
  assert.equal(paid, 9037, 'the transfers settle exactly')
}

// edge: no labels at all, readers alone, and every reader without a source
{
  const vm = build(ALL, {labels: []})
  const st = vm.execute('init'); assert.deepEqual(nums(vm, st), [0, 0]); view(vm, st)
  for (const k of ALL.slice(1)) { const alone = build([k]); view(alone, alone.execute('init')) }
}

// the same blocks, another domain and other words: points per player, no money
{
  const vm = build(['record_log', 'breakdown_table'], {labels: ['Red', 'Blue']})
  let st = vm.execute('init')
  st = vm.execute('setWho1', [st, num(1)]); st = vm.execute('setAmount1', [st, str('7')]); st = vm.execute('addRecord1', [st, num(0)])
  const s = strings(vm, st).join('|')
  assert.match(s, /Blue/); assert.match(s, /\$7\.00/)
}
console.log('ledger-check ok')
