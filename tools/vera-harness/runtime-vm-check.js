// Unit checks for VM resource traps that cannot be exercised by a normal app:
// array literals and recursive call depth. No platform, no device.
'use strict'
const assert = require('node:assert/strict')
const {loadVera} = require('./source-loader')
const vmMod = loadVera('VeraInterpreter')
const {Instruction, BytecodeFunction, BytecodeModule, VirtualMachine, VeraStringValue, VeraArrayValue} = vmMod
const {UiHostEnvironment, MAX_PENDING_EFFECTS} = loadVera('VeraUi')

function instruction(op, fields = {}) {
  const i = new Instruction(op)
  Object.assign(i, fields)
  return i
}

// A literal larger than the array limit is a trap before any elements are taken.
{
  const make = instruction('make-array', {count: vmMod.MAX_ARRAY_LENGTH + 1})
  const ret = instruction('return')
  const fn = new BytecodeFunction('init', 0, 0, false, [make, ret], [])
  const vm = new VirtualMachine(new BytecodeModule([fn], ['init']))
  assert.throws(() => vm.execute('init'), e => e.trapCode === 'R0022' && /array length/.test(e.message))
}

// Recursive Vera calls trap at the depth limit instead of overflowing JS.
{
  const load = instruction('load-function', {name: 'loop'})
  const call = instruction('call', {count: 0, awaited: false})
  const ret = instruction('return')
  const fn = new BytecodeFunction('loop', 0, 0, false, [load, call, ret], [])
  const vm = new VirtualMachine(new BytecodeModule([fn], ['loop']))
  assert.throws(() => vm.execute('loop'), e => e.trapCode === 'R0031' && /call depth/.test(e.message))
}

// A normal array under the cap still runs.
{
  const make = instruction('make-array', {count: vmMod.MAX_ARRAY_LENGTH})
  const ret = instruction('return')
  const fn = new BytecodeFunction('init', 0, 0, false, [make, ret], [])
  // make-array pops the elements it is told about; provide them on the stack first.
  const pushes = []
  for (let i = 0; i < vmMod.MAX_ARRAY_LENGTH; i++) pushes.push(instruction('push-number', {numValue: i}))
  fn.instructions = pushes.concat([make, ret])
  const vm = new VirtualMachine(new BytecodeModule([fn], ['init']))
  const value = vm.execute('init')
  assert.equal(value.elements.length, vmMod.MAX_ARRAY_LENGTH)
}

// The VM refuses the 33rd queued effect in one handler instead of allocating
// an unbounded pending queue.
{
  const host = new UiHostEnvironment()
  host.effectsAllowed = true
  const target = new VeraStringValue('CameraKit.CameraManager.setTorchMode')
  const params = new VeraArrayValue([new VeraStringValue('mode'), new VeraStringValue('ON')])
  const handler = new VeraStringValue('onAnswer')
  for (let i = 0; i < MAX_PENDING_EFFECTS; i++) {
    host.invoke('std/sdk', 'call', [target, params, handler], false)
  }
  assert.throws(() => host.invoke('std/sdk', 'call', [target, params, handler], false),
    e => e.trapCode === 'R0032' && /too many phone actions/.test(e.message))
  host.effectsAllowed = false
}

console.log('runtime-vm-check: all checks passed')
