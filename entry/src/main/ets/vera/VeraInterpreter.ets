/**
 * VERA-L VBC2 Virtual Machine — dynamic ArkTS port of vera-server/src/vm.ts.
 *
 * Differences from the TypeScript original:
 *   - bigint → number with int32 range checks (dynamic ArkTS has no bigint)
 *   - readonly → dropped (not enforced in dynamic ArkTS)
 *   - discriminated union Instruction → class with all fields
 *   - JSON.parse for VBC2 deserialization
 */

export abstract class RuntimeValue {}
export class VeraIntValue extends RuntimeValue { value: number; constructor(v: number) { super(); this.value = v; } }
export class VeraNumberValue extends RuntimeValue { value: number; constructor(v: number) { super(); this.value = v; } }
export class VeraStringValue extends RuntimeValue { value: string; constructor(v: string) { super(); this.value = v; } }
export class VeraBooleanValue extends RuntimeValue { value: boolean; constructor(v: boolean) { super(); this.value = v; } }
export class VeraNullValue extends RuntimeValue {}
export class VeraArrayValue extends RuntimeValue { elements: RuntimeValue[]; constructor(e: RuntimeValue[]) { super(); this.elements = e; } }
export class VeraObjectValue extends RuntimeValue {
  classIdentity: string
  fields: Map<string, RuntimeValue> = new Map<string, RuntimeValue>()
  constructor(identity: string, fields: Map<string, RuntimeValue>) {
    super()
    this.classIdentity = identity
    this.fields = fields
  }
}

export class Cell {
  value: RuntimeValue
  constructor(v: RuntimeValue) { this.value = v; }
}

export class FunctionValue extends RuntimeValue {
  name: string
  captures: Cell[]
  constructor(name: string, captures: Cell[]) { super(); this.name = name; this.captures = captures; }
}

export class ExternalFunctionValue extends RuntimeValue {
  module: string
  funcName: string
  constructor(mod: string, name: string) { super(); this.module = mod; this.funcName = name; }
}

export const NULL_VALUE: VeraNullValue = new VeraNullValue()

export class RuntimeTrap extends Error {
  trapCode: string
  constructor(code: string, message: string) { super(message); this.trapCode = code; }
}

export abstract class HostEnvironment {
  abstract invoke(module: string, name: string, args: RuntimeValue[], awaited: boolean): RuntimeValue
}

export class EmptyHostEnvironment extends HostEnvironment {
  invoke(module: string, name: string, _args: RuntimeValue[], _awaited: boolean): RuntimeValue {
    throw new RuntimeTrap('R0015', `external function unavailable: ${module}.${name}`)
  }
}

export class Instruction {
  op: string
  value: string = ''
  numValue: number = 0
  boolValue: boolean = false
  slot: number = 0
  name: string = ''
  module: string = ''
  operator: string = ''
  integer: boolean = false
  target: number = 0
  count: number = 0
  awaited: boolean = false
  classIdentity: string = ''
  fields: string[] = []
  functionName: string = ''
  captures: number[] = []

  constructor(op: string) { this.op = op; }
}

export class BytecodeFunction {
  name: string
  parameterCount: number
  localCount: number
  isAsync: boolean
  instructions: Instruction[]

  constructor(name: string, paramCount: number, localCount: number, isAsync: boolean, instructions: Instruction[]) {
    this.name = name
    this.parameterCount = paramCount
    this.localCount = localCount
    this.isAsync = isAsync
    this.instructions = instructions
  }
}

export class BytecodeModule {
  functions: BytecodeFunction[]
  entryCandidates: string[]

  constructor(functions: BytecodeFunction[], entries: string[]) {
    this.functions = functions
    this.entryCandidates = entries
  }
}

class Frame {
  stack: RuntimeValue[] = []
  locals: Cell[]
  pc: number = 0
  fn: BytecodeFunction
  captures: Cell[]

  constructor(fn: BytecodeFunction, captures: Cell[], args: RuntimeValue[]) {
    this.fn = fn
    this.captures = captures
    this.locals = []
    for (let i: number = 0; i < fn.localCount; i++) {
      this.locals.push(new Cell(i < args.length ? args[i] : NULL_VALUE))
    }
  }
}

const MIN_INT: number = -2147483648
const MAX_INT: number = 2147483647

export class VirtualMachine {
  private functions: Map<string, BytecodeFunction> = new Map<string, BytecodeFunction>()
  private functionValues: Map<string, FunctionValue> = new Map<string, FunctionValue>()
  private externalValues: Map<string, ExternalFunctionValue> = new Map<string, ExternalFunctionValue>()
  private host: HostEnvironment
  private maxSteps: number
  private steps: number = 0

  constructor(module: BytecodeModule, host: HostEnvironment = new EmptyHostEnvironment(), maxSteps: number = 500000) {
    this.host = host
    this.maxSteps = maxSteps
    for (let fn of module.functions) {
      this.functions.set(fn.name, fn)
    }
  }

  // Steps executed by the most recent execute() call (reset per call).
  stepsExecuted(): number { return this.steps }

  execute(entry: string, args: RuntimeValue[] = []): RuntimeValue {
    let fn = this.functions.get(entry)
    if (fn == undefined) {
      throw new RuntimeTrap('R0001', `entry function not found: ${entry}`)
    }
    this.steps = 0
    return this.run(new Frame(fn, [], args))
  }

  private run(frame: Frame): RuntimeValue {
    while (frame.pc < frame.fn.instructions.length) {
      this.steps += 1
      if (this.steps > this.maxSteps) {
        throw new RuntimeTrap('R0017', `execution exceeded ${this.maxSteps} steps`)
      }
      let inst = frame.fn.instructions[frame.pc]
      frame.pc += 1
      switch (inst.op) {
        case 'push-int':
          frame.stack.push(new VeraIntValue(this.checked(parseInt(inst.value))))
          break
        case 'push-number':
          frame.stack.push(new VeraNumberValue(inst.numValue))
          break
        case 'push-string':
          frame.stack.push(new VeraStringValue(inst.value))
          break
        case 'push-boolean':
          frame.stack.push(new VeraBooleanValue(inst.boolValue))
          break
        case 'push-null':
          frame.stack.push(NULL_VALUE)
          break
        case 'load-local':
          frame.stack.push(this.cell(frame.locals, inst.slot).value)
          break
        case 'store-local':
          this.cell(frame.locals, inst.slot).value = this.pop(frame)
          break
        case 'load-capture':
          frame.stack.push(this.cell(frame.captures, inst.slot).value)
          break
        case 'store-capture':
          this.cell(frame.captures, inst.slot).value = this.pop(frame)
          break
        case 'load-function': {
          let val = this.functionValues.get(inst.name)
          if (val == undefined) {
            val = new FunctionValue(inst.name, [])
            this.functionValues.set(inst.name, val)
          }
          frame.stack.push(val)
          break
        }
        case 'load-external': {
          let key = `${inst.module}::${inst.name}`
          let val = this.externalValues.get(key)
          if (val == undefined) {
            val = new ExternalFunctionValue(inst.module, inst.name)
            this.externalValues.set(key, val)
          }
          frame.stack.push(val)
          break
        }
        case 'pop':
          this.pop(frame)
          break
        case 'duplicate':
          frame.stack.push(frame.stack[frame.stack.length - 1])
          break
        case 'unary':
          frame.stack.push(this.unary(inst.operator, this.pop(frame)))
          break
        case 'binary': {
          let r = this.pop(frame)
          let l = this.pop(frame)
          frame.stack.push(this.binary(inst.operator, inst.integer, l, r))
          break
        }
        case 'jump':
          frame.pc = inst.target
          break
        case 'jump-if-false':
          if (!this.asBoolean(this.pop(frame))) { frame.pc = inst.target; }
          break
        case 'call':
          this.callInst(frame, inst)
          break
        case 'return':
          return this.pop(frame)
        case 'make-array':
          frame.stack.push(new VeraArrayValue(this.take(frame, inst.count)))
          break
        case 'array-push': {
          let v = this.pop(frame)
          let arr = this.asArray(this.pop(frame))
          if (arr.elements.length >= 4096) {
            throw new RuntimeTrap('R0022', 'array length limit reached (4096)')
          }
          arr.elements.push(v)
          frame.stack.push(new VeraIntValue(arr.elements.length))
          break
        }
        case 'array-pop': {
          let arr = this.asArray(this.pop(frame))
          if (arr.elements.length === 0) {
            throw new RuntimeTrap('R0023', 'pop from an empty array')
          }
          frame.stack.push(arr.elements.pop() as RuntimeValue)
          break
        }
        case 'length': {
          let v = this.pop(frame)
          if (v instanceof VeraArrayValue) {
            frame.stack.push(new VeraIntValue(v.elements.length))
          } else if (v instanceof VeraStringValue) {
            frame.stack.push(new VeraIntValue(v.value.length))
          } else {
            throw new RuntimeTrap('R0008', 'expected array or string')
          }
          break
        }
        case 'string-symbols': {
          let v = this.pop(frame)
          if (!(v instanceof VeraStringValue)) { throw new RuntimeTrap('R0008', 'expected string') }
          let chars: RuntimeValue[] = []
          for (let ch of Array.from(v.value)) { chars.push(new VeraStringValue(ch)) }
          frame.stack.push(new VeraArrayValue(chars))
          break
        }
        case 'ensure-not-null': {
          let v = this.pop(frame)
          if (v instanceof VeraNullValue) { throw new RuntimeTrap('R0018', 'ensure-not-null failed') }
          frame.stack.push(v)
          break
        }
        case 'load-index': {
          let idx = this.index(this.pop(frame))
          let arr = this.asArray(this.pop(frame))
          frame.stack.push(this.indexValue(arr, idx))
          break
        }
        case 'store-index': {
          let v = this.pop(frame)
          let idx = this.index(this.pop(frame))
          let arr = this.asArray(this.pop(frame))
          this.indexValue(arr, idx)
          arr.elements[idx] = v
          break
        }
        case 'make-object': {
          let vals = this.take(frame, inst.fields.length)
          let fields = new Map<string, RuntimeValue>()
          for (let i: number = 0; i < inst.fields.length; i++) {
            fields.set(inst.fields[i], vals[i])
          }
          frame.stack.push(new VeraObjectValue(inst.classIdentity, fields))
          break
        }
        case 'load-field': {
          let obj = this.asObject(this.pop(frame))
          let v = obj.fields.get(inst.name)
          if (v == undefined) { throw new RuntimeTrap('R0010', `missing field ${inst.name}`) }
          frame.stack.push(v)
          break
        }
        case 'store-field': {
          let v = this.pop(frame)
          let obj = this.asObject(this.pop(frame))
          if (!obj.fields.has(inst.name)) { throw new RuntimeTrap('R0010', `missing field ${inst.name}`) }
          obj.fields.set(inst.name, v)
          break
        }
        case 'make-closure': {
          let caps: Cell[] = []
          for (let c of inst.captures) {
            if (c >= 0) { caps.push(this.cell(frame.locals, c)) }
            else { caps.push(this.cell(frame.captures, -c - 1)) }
          }
          frame.stack.push(new FunctionValue(inst.functionName, caps))
          break
        }
      }
    }
    throw new RuntimeTrap('R0012', 'function ended without return')
  }

  private callInst(frame: Frame, inst: Instruction): void {
    let args = this.take(frame, inst.count)
    let callee = this.pop(frame)
    if (callee instanceof FunctionValue) {
      let fn = this.functions.get(callee.name)
      if (fn == undefined) { throw new RuntimeTrap('R0001', `function not found: ${callee.name}`) }
      if (fn.isAsync !== inst.awaited) { throw new RuntimeTrap('R0013', 'async call invariant') }
      frame.stack.push(this.run(new Frame(fn, callee.captures, args)))
    } else if (callee instanceof ExternalFunctionValue) {
      frame.stack.push(this.host.invoke(callee.module, callee.funcName, args, inst.awaited))
    } else {
      throw new RuntimeTrap('R0014', 'value is not callable')
    }
  }

  private unary(op: string, value: RuntimeValue): RuntimeValue {
    if (op === '!') { return new VeraBooleanValue(!this.asBoolean(value)) }
    if (value instanceof VeraIntValue) { return new VeraIntValue(this.checked(-value.value)) }
    if (value instanceof VeraNumberValue) { return new VeraNumberValue(-value.value) }
    throw new RuntimeTrap('R0002', 'invalid unary operand')
  }

  private binary(op: string, integer: boolean, left: RuntimeValue, right: RuntimeValue): RuntimeValue {
    if (op === '===') { return new VeraBooleanValue(this.equal(left, right)) }
    if (op === '!==') { return new VeraBooleanValue(!this.equal(left, right)) }
    if (op === '&&') { return new VeraBooleanValue(this.asBoolean(left) && this.asBoolean(right)) }
    if (op === '||') { return new VeraBooleanValue(this.asBoolean(left) || this.asBoolean(right)) }
    if (left instanceof VeraStringValue && right instanceof VeraStringValue) {
      if (op === '+') { return new VeraStringValue(left.value + right.value) }
      return new VeraBooleanValue(this.compareStr(op, left.value, right.value))
    }
    if (integer) { return this.intBinary(op, this.asInt(left), this.asInt(right)) }
    let a = this.asNumber(left)
    let b = this.asNumber(right)
    if (op === '+') { return new VeraNumberValue(a + b) }
    if (op === '-') { return new VeraNumberValue(a - b) }
    if (op === '*') { return new VeraNumberValue(a * b) }
    if (op === '/') { return new VeraNumberValue(a / b) }
    return new VeraBooleanValue(this.compareNum(op, a, b))
  }

  private intBinary(op: string, left: number, right: number): RuntimeValue {
    if (op === '+') { return new VeraIntValue(this.checked(left + right)) }
    if (op === '-') { return new VeraIntValue(this.checked(left - right)) }
    if (op === '*') { return new VeraIntValue(this.checked(left * right)) }
    if (op === '/') {
      if (right === 0) { throw new RuntimeTrap('R0003', 'integer division by zero') }
      return new VeraIntValue(this.checked(Math.trunc(left / right)))
    }
    if (op === '%') {
      if (right === 0) { throw new RuntimeTrap('R0004', 'integer modulo by zero') }
      return new VeraIntValue(left % right)
    }
    if (op === '<') { return new VeraBooleanValue(left < right) }
    if (op === '<=') { return new VeraBooleanValue(left <= right) }
    if (op === '>') { return new VeraBooleanValue(left > right) }
    if (op === '>=') { return new VeraBooleanValue(left >= right) }
    throw new RuntimeTrap('R0005', `invalid comparison ${op}`)
  }

  private compareNum(op: string, a: number, b: number): boolean {
    if (op === '<') { return a < b }
    if (op === '<=') { return a <= b }
    if (op === '>') { return a > b }
    if (op === '>=') { return a >= b }
    throw new RuntimeTrap('R0005', `invalid comparison ${op}`)
  }

  private compareStr(op: string, a: string, b: string): boolean {
    if (op === '<') { return a < b }
    if (op === '<=') { return a <= b }
    if (op === '>') { return a > b }
    if (op === '>=') { return a >= b }
    throw new RuntimeTrap('R0005', `invalid comparison ${op}`)
  }

  private equal(a: RuntimeValue, b: RuntimeValue): boolean {
    if (a instanceof VeraNullValue || b instanceof VeraNullValue) { return a instanceof VeraNullValue && b instanceof VeraNullValue }
    if (a instanceof VeraIntValue && b instanceof VeraIntValue) { return a.value === b.value }
    if (a instanceof VeraNumberValue && b instanceof VeraNumberValue) { return a.value === b.value }
    if (a instanceof VeraStringValue && b instanceof VeraStringValue) { return a.value === b.value }
    if (a instanceof VeraBooleanValue && b instanceof VeraBooleanValue) { return a.value === b.value }
    if (a instanceof FunctionValue && b instanceof FunctionValue) { return a === b }
    if (a instanceof ExternalFunctionValue && b instanceof ExternalFunctionValue) { return a === b }
    return false
  }

  private checked(value: number): number {
    if (value < MIN_INT || value > MAX_INT) { throw new RuntimeTrap('R0006', 'integer overflow') }
    return value
  }

  private pop(frame: Frame): RuntimeValue {
    let v = frame.stack.pop()
    if (v == undefined) { throw new RuntimeTrap('R0007', 'stack underflow') }
    return v
  }

  private take(frame: Frame, count: number): RuntimeValue[] {
    if (frame.stack.length < count) { throw new RuntimeTrap('R0007', 'stack underflow') }
    let result: RuntimeValue[] = []
    let start = frame.stack.length - count
    for (let i = start; i < frame.stack.length; i++) { result.push(frame.stack[i]) }
    while (frame.stack.length > start) { this.pop(frame) }
    return result
  }

  private asInt(v: RuntimeValue): number { if (!(v instanceof VeraIntValue)) { throw new RuntimeTrap('R0008', 'expected int') } return (v as VeraIntValue).value }
  private asNumber(v: RuntimeValue): number { if (!(v instanceof VeraNumberValue)) { throw new RuntimeTrap('R0008', 'expected number') } return (v as VeraNumberValue).value }
  private asBoolean(v: RuntimeValue): boolean { if (!(v instanceof VeraBooleanValue)) { throw new RuntimeTrap('R0008', 'expected boolean') } return (v as VeraBooleanValue).value }
  private asArray(v: RuntimeValue): VeraArrayValue { if (!(v instanceof VeraArrayValue)) { throw new RuntimeTrap('R0008', 'expected array') } return v as VeraArrayValue }
  private asObject(v: RuntimeValue): VeraObjectValue { if (!(v instanceof VeraObjectValue)) { throw new RuntimeTrap('R0008', 'expected object') } return v as VeraObjectValue }
  private index(v: RuntimeValue): number { let i = this.asInt(v); if (i < 0 || i > MAX_INT) { throw new RuntimeTrap('R0009', 'array index out of bounds') } return i }
  private indexValue(arr: VeraArrayValue, idx: number): RuntimeValue { if (idx < 0 || idx >= arr.elements.length) { throw new RuntimeTrap('R0009', 'array index out of bounds') } return arr.elements[idx] }
  private cell(vals: Cell[], idx: number): Cell { if (idx < 0 || idx >= vals.length) { throw new RuntimeTrap('R0016', 'invalid slot') } return vals[idx] }
}

export function formatRuntimeValue(value: RuntimeValue): string {
  if (value instanceof VeraIntValue) { return value.value.toString() }
  if (value instanceof VeraNumberValue) { return value.value.toString() }
  if (value instanceof VeraStringValue) { return value.value }
  if (value instanceof VeraBooleanValue) { return value.value ? 'true' : 'false' }
  if (value instanceof VeraNullValue) { return 'null' }
  if (value instanceof VeraArrayValue) { return '[' + value.elements.map((e: RuntimeValue) => formatRuntimeValue(e)).join(', ') + ']' }
  if (value instanceof VeraObjectValue) {
    let entries: string[] = []
    for (let entry of value.fields) { entries.push(entry[0] + ': ' + formatRuntimeValue(entry[1])) }
    return '{' + entries.join(', ') + '}'
  }
  if (value instanceof FunctionValue) { return `<function ${value.name}>` }
  if (value instanceof ExternalFunctionValue) { return `<external ${value.module}.${value.funcName}>` }
  return '<unknown>'
}

/**
 * Program state, encoded so it survives a restart.
 *
 * Tagged rather than plain JSON for two reasons: plain JSON cannot tell an int
 * from a number, which matters because arithmetic here refuses to mix them; and
 * it would lose classIdentity, which make-object sets and which field access
 * relies on.
 *
 * Functions are deliberately unrepresentable. A closure in state would be a
 * captured environment that no longer exists after a restart, so it is better to
 * fail loudly at save time than to restore something subtly wrong.
 */
export function encodeRuntimeValue(value: RuntimeValue): Object {
  if (value instanceof VeraIntValue) { return ['i', (value as VeraIntValue).value] as Object }
  if (value instanceof VeraNumberValue) { return ['n', (value as VeraNumberValue).value] as Object }
  if (value instanceof VeraStringValue) { return ['s', (value as VeraStringValue).value] as Object }
  if (value instanceof VeraBooleanValue) { return ['b', (value as VeraBooleanValue).value] as Object }
  if (value instanceof VeraNullValue) { return ['z'] as Object }
  if (value instanceof VeraArrayValue) {
    let items: Object[] = []
    for (let e of (value as VeraArrayValue).elements) { items.push(encodeRuntimeValue(e)) }
    return ['a', items] as Object
  }
  if (value instanceof VeraObjectValue) {
    let obj = value as VeraObjectValue
    let entries: Object[] = []
    for (let entry of obj.fields) { entries.push([entry[0], encodeRuntimeValue(entry[1])] as Object) }
    return ['o', obj.classIdentity, entries] as Object
  }
  throw new RuntimeTrap('R0024', 'value cannot be saved: ' + formatRuntimeValue(value))
}

export function decodeRuntimeValue(raw: Object): RuntimeValue {
  let parts = raw as Object[]
  let tag = parts[0] as string
  if (tag === 'i') { return new VeraIntValue(parts[1] as number) }
  if (tag === 'n') { return new VeraNumberValue(parts[1] as number) }
  if (tag === 's') { return new VeraStringValue(parts[1] as string) }
  if (tag === 'b') { return new VeraBooleanValue(parts[1] as boolean) }
  if (tag === 'z') { return NULL_VALUE }
  if (tag === 'a') {
    let items: RuntimeValue[] = []
    for (let e of parts[1] as Object[]) { items.push(decodeRuntimeValue(e)) }
    return new VeraArrayValue(items)
  }
  if (tag === 'o') {
    let fields = new Map<string, RuntimeValue>()
    for (let entry of parts[2] as Object[]) {
      let pair = entry as Object[]
      fields.set(pair[0] as string, decodeRuntimeValue(pair[1]))
    }
    return new VeraObjectValue(parts[1] as string, fields)
  }
  throw new RuntimeTrap('R0025', 'unknown saved value tag: ' + tag)
}

export function deserializeVbc2(source: string): BytecodeModule {
  let root = JSON.parse(source) as Object[]
  if (!Array.isArray(root) || root[0] !== 'VBC2') {
    throw new RuntimeTrap('VBC0004', 'unsupported VBC version')
  }
  let entries = root[1] as string[]
  let rawFunctions = root[2] as Object[][]
  let functions: BytecodeFunction[] = []
  for (let item of rawFunctions) {
    let rawInstructions = item[4] as Object[][]
    let instructions: Instruction[] = []
    for (let raw of rawInstructions) {
      instructions.push(decodeInstruction(raw))
    }
    functions.push(new BytecodeFunction(
      item[0] as string,
      item[1] as number,
      item[2] as number,
      item[3] as boolean,
      instructions
    ))
  }
  return new BytecodeModule(functions, entries)
}

function decodeInstruction(raw: Object[]): Instruction {
  let op = raw[0] as string
  let inst = new Instruction(op)
  switch (op) {
    case 'push-int': inst.value = raw[1] as string; break
    case 'push-number': inst.numValue = raw[1] as number; break
    case 'push-string': inst.value = raw[1] as string; break
    case 'push-boolean': inst.boolValue = raw[1] as boolean; break
    case 'push-null': break
    case 'load-local': inst.slot = raw[1] as number; break
    case 'store-local': inst.slot = raw[1] as number; break
    case 'load-capture': inst.slot = raw[1] as number; break
    case 'store-capture': inst.slot = raw[1] as number; break
    case 'load-function': inst.name = raw[1] as string; break
    case 'load-external': inst.module = raw[1] as string; inst.name = raw[2] as string; break
    case 'pop': break
    case 'duplicate': break
    case 'unary': inst.operator = raw[1] as string; break
    case 'binary': inst.operator = raw[1] as string; inst.integer = raw[2] as boolean; break
    case 'jump': inst.target = raw[1] as number; break
    case 'jump-if-false': inst.target = raw[1] as number; break
    case 'call': inst.count = raw[1] as number; inst.awaited = raw[2] as boolean; break
    case 'return': break
    case 'make-array': inst.count = raw[1] as number; break
    case 'array-push': break
    case 'array-pop': break
    case 'length': break
    case 'string-symbols': break
    case 'ensure-not-null': break
    case 'load-index': break
    case 'store-index': break
    case 'make-object':
      inst.classIdentity = raw[1] as string
      inst.fields = raw[2] as string[]
      break
    case 'load-field': inst.name = raw[1] as string; break
    case 'store-field': inst.name = raw[1] as string; break
    case 'make-closure':
      inst.functionName = raw[1] as string
      inst.captures = raw[2] as number[]
      break
    default:
      throw new RuntimeTrap('VBC0003', `unknown opcode: ${op}`)
  }
  return inst
}
