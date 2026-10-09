export abstract class RuntimeValue {
}
export class VeraIntValue extends RuntimeValue {
    value: number;
    constructor(m116: number) { super(); this.value = m116; }
}
export class VeraNumberValue extends RuntimeValue {
    value: number;
    constructor(l116: number) { super(); this.value = l116; }
}
export class VeraStringValue extends RuntimeValue {
    value: string;
    constructor(k116: string) { super(); this.value = k116; }
}
export class VeraBooleanValue extends RuntimeValue {
    value: boolean;
    constructor(j116: boolean) { super(); this.value = j116; }
}
export class VeraNullValue extends RuntimeValue {
}
export class VeraArrayValue extends RuntimeValue {
    elements: RuntimeValue[];
    constructor(i116: RuntimeValue[]) { super(); this.elements = i116; }
}
export class VeraObjectValue extends RuntimeValue {
    classIdentity: string;
    fields: Map<string, RuntimeValue> = new Map<string, RuntimeValue>();
    constructor(g116: string, h116: Map<string, RuntimeValue>) {
        super();
        this.classIdentity = g116;
        this.fields = h116;
    }
}
export class Cell {
    value: RuntimeValue;
    constructor(f116: RuntimeValue) { this.value = f116; }
}
export class FunctionValue extends RuntimeValue {
    name: string;
    captures: Cell[];
    constructor(d116: string, e116: Cell[]) { super(); this.name = d116; this.captures = e116; }
}
export class ExternalFunctionValue extends RuntimeValue {
    module: string;
    funcName: string;
    constructor(b116: string, c116: string) { super(); this.module = b116; this.funcName = c116; }
}
export const NULL_VALUE: VeraNullValue = new VeraNullValue();
export class RuntimeTrap extends Error {
    trapCode: string;
    constructor(z115: string, a116: string) { super(a116); this.trapCode = z115; }
}
export abstract class HostEnvironment {
    abstract invoke(v115: string, w115: string, x115: RuntimeValue[], y115: boolean): RuntimeValue;
}
export class EmptyHostEnvironment extends HostEnvironment {
    invoke(r115: string, s115: string, t115: RuntimeValue[], u115: boolean): RuntimeValue {
        throw new RuntimeTrap('R0015', `external function unavailable: ${r115}.${s115}`);
    }
}
export class Instruction {
    op: string;
    value: string = '';
    numValue: number = 0;
    boolValue: boolean = false;
    slot: number = 0;
    name: string = '';
    module: string = '';
    operator: string = '';
    integer: boolean = false;
    target: number = 0;
    count: number = 0;
    awaited: boolean = false;
    classIdentity: string = '';
    fields: string[] = [];
    functionName: string = '';
    captures: number[] = [];
    constructor(q115: string) { this.op = q115; }
}
export class BytecodeFunction {
    name: string;
    parameterCount: number;
    localCount: number;
    isAsync: boolean;
    instructions: Instruction[];
    constructor(l115: string, m115: number, n115: number, o115: boolean, p115: Instruction[]) {
        this.name = l115;
        this.parameterCount = m115;
        this.localCount = n115;
        this.isAsync = o115;
        this.instructions = p115;
    }
}
export class BytecodeModule {
    functions: BytecodeFunction[];
    entryCandidates: string[];
    constructor(j115: BytecodeFunction[], k115: string[]) {
        this.functions = j115;
        this.entryCandidates = k115;
    }
}
class Frame {
    stack: RuntimeValue[] = [];
    locals: Cell[];
    pc: number = 0;
    fn: BytecodeFunction;
    captures: Cell[];
    constructor(f115: BytecodeFunction, g115: Cell[], h115: RuntimeValue[]) {
        this.fn = f115;
        this.captures = g115;
        this.locals = [];
        for (let i115: number = 0; i115 < f115.localCount; i115++) {
            this.locals.push(new Cell(i115 < h115.length ? h115[i115] : NULL_VALUE));
        }
    }
}
const MIN_INT: number = -2147483648;
const MAX_INT: number = 2147483647;
export class VirtualMachine {
    private functions: Map<string, BytecodeFunction> = new Map<string, BytecodeFunction>();
    private functionValues: Map<string, FunctionValue> = new Map<string, FunctionValue>();
    private externalValues: Map<string, ExternalFunctionValue> = new Map<string, ExternalFunctionValue>();
    private host: HostEnvironment;
    private maxSteps: number;
    private steps: number = 0;
    constructor(b115: BytecodeModule, c115: HostEnvironment = new EmptyHostEnvironment(), d115: number = 5000000) {
        this.host = c115;
        this.maxSteps = d115;
        for (let e115 of b115.functions) {
            this.functions.set(e115.name, e115);
        }
    }
    stepsExecuted(): number { return this.steps; }
    execute(y114: string, z114: RuntimeValue[] = []): RuntimeValue {
        let a115 = this.functions.get(y114);
        if (a115 == undefined) {
            throw new RuntimeTrap('R0001', `entry function not found: ${y114}`);
        }
        this.steps = 0;
        return this.run(new Frame(a115, [], z114));
    }
    private run(v113: Frame): RuntimeValue {
        while (v113.pc < v113.fn.instructions.length) {
            this.steps += 1;
            if (this.steps > this.maxSteps) {
                throw new RuntimeTrap('R0017', `execution exceeded ${this.maxSteps} steps`);
            }
            let w113 = v113.fn.instructions[v113.pc];
            v113.pc += 1;
            switch (w113.op) {
                case 'push-int':
                    v113.stack.push(new VeraIntValue(this.checked(parseInt(w113.value))));
                    break;
                case 'push-number':
                    v113.stack.push(new VeraNumberValue(w113.numValue));
                    break;
                case 'push-string':
                    v113.stack.push(new VeraStringValue(w113.value));
                    break;
                case 'push-boolean':
                    v113.stack.push(new VeraBooleanValue(w113.boolValue));
                    break;
                case 'push-null':
                    v113.stack.push(NULL_VALUE);
                    break;
                case 'load-local':
                    v113.stack.push(this.cell(v113.locals, w113.slot).value);
                    break;
                case 'store-local':
                    this.cell(v113.locals, w113.slot).value = this.pop(v113);
                    break;
                case 'load-capture':
                    v113.stack.push(this.cell(v113.captures, w113.slot).value);
                    break;
                case 'store-capture':
                    this.cell(v113.captures, w113.slot).value = this.pop(v113);
                    break;
                case 'load-function': {
                    let x114 = this.functionValues.get(w113.name);
                    if (x114 == undefined) {
                        x114 = new FunctionValue(w113.name, []);
                        this.functionValues.set(w113.name, x114);
                    }
                    v113.stack.push(x114);
                    break;
                }
                case 'load-external': {
                    let v114 = `${w113.module}::${w113.name}`;
                    let w114 = this.externalValues.get(v114);
                    if (w114 == undefined) {
                        w114 = new ExternalFunctionValue(w113.module, w113.name);
                        this.externalValues.set(v114, w114);
                    }
                    v113.stack.push(w114);
                    break;
                }
                case 'pop':
                    this.pop(v113);
                    break;
                case 'duplicate':
                    v113.stack.push(v113.stack[v113.stack.length - 1]);
                    break;
                case 'unary':
                    v113.stack.push(this.unary(w113.operator, this.pop(v113)));
                    break;
                case 'binary': {
                    let t114 = this.pop(v113);
                    let u114 = this.pop(v113);
                    v113.stack.push(this.binary(w113.operator, w113.integer, u114, t114));
                    break;
                }
                case 'jump':
                    v113.pc = w113.target;
                    break;
                case 'jump-if-false':
                    if (!this.asBoolean(this.pop(v113))) {
                        v113.pc = w113.target;
                    }
                    break;
                case 'call':
                    this.callInst(v113, w113);
                    break;
                case 'return':
                    return this.pop(v113);
                case 'make-array':
                    v113.stack.push(new VeraArrayValue(this.take(v113, w113.count)));
                    break;
                case 'array-push': {
                    let r114 = this.pop(v113);
                    let s114 = this.asArray(this.pop(v113));
                    if (s114.elements.length >= 4096) {
                        throw new RuntimeTrap('R0022', 'array length limit reached (4096)');
                    }
                    s114.elements.push(r114);
                    v113.stack.push(new VeraIntValue(s114.elements.length));
                    break;
                }
                case 'array-pop': {
                    let q114 = this.asArray(this.pop(v113));
                    if (q114.elements.length === 0) {
                        throw new RuntimeTrap('R0023', 'pop from an empty array');
                    }
                    v113.stack.push(q114.elements.pop() as RuntimeValue);
                    break;
                }
                case 'length': {
                    let p114 = this.pop(v113);
                    if (p114 instanceof VeraArrayValue) {
                        v113.stack.push(new VeraIntValue(p114.elements.length));
                    }
                    else if (p114 instanceof VeraStringValue) {
                        v113.stack.push(new VeraIntValue(p114.value.length));
                    }
                    else {
                        throw new RuntimeTrap('R0008', 'expected array or string');
                    }
                    break;
                }
                case 'string-symbols': {
                    let m114 = this.pop(v113);
                    if (!(m114 instanceof VeraStringValue)) {
                        throw new RuntimeTrap('R0008', 'expected string');
                    }
                    let n114: RuntimeValue[] = [];
                    for (let o114 of Array.from(m114.value)) {
                        n114.push(new VeraStringValue(o114));
                    }
                    v113.stack.push(new VeraArrayValue(n114));
                    break;
                }
                case 'ensure-not-null': {
                    let l114 = this.pop(v113);
                    if (l114 instanceof VeraNullValue) {
                        throw new RuntimeTrap('R0018', 'ensure-not-null failed');
                    }
                    v113.stack.push(l114);
                    break;
                }
                case 'load-index': {
                    let j114 = this.index(this.pop(v113));
                    let k114 = this.asArray(this.pop(v113));
                    v113.stack.push(this.indexValue(k114, j114));
                    break;
                }
                case 'store-index': {
                    let g114 = this.pop(v113);
                    let h114 = this.index(this.pop(v113));
                    let i114 = this.asArray(this.pop(v113));
                    this.indexValue(i114, h114);
                    i114.elements[h114] = g114;
                    break;
                }
                case 'make-object': {
                    let d114 = this.take(v113, w113.fields.length);
                    let e114 = new Map<string, RuntimeValue>();
                    for (let f114: number = 0; f114 < w113.fields.length; f114++) {
                        e114.set(w113.fields[f114], d114[f114]);
                    }
                    v113.stack.push(new VeraObjectValue(w113.classIdentity, e114));
                    break;
                }
                case 'load-field': {
                    let b114 = this.asObject(this.pop(v113));
                    let c114 = b114.fields.get(w113.name);
                    if (c114 == undefined) {
                        throw new RuntimeTrap('R0010', `missing field ${w113.name}`);
                    }
                    v113.stack.push(c114);
                    break;
                }
                case 'store-field': {
                    let z113 = this.pop(v113);
                    let a114 = this.asObject(this.pop(v113));
                    if (!a114.fields.has(w113.name)) {
                        throw new RuntimeTrap('R0010', `missing field ${w113.name}`);
                    }
                    a114.fields.set(w113.name, z113);
                    break;
                }
                case 'make-closure': {
                    let x113: Cell[] = [];
                    for (let y113 of w113.captures) {
                        if (y113 >= 0) {
                            x113.push(this.cell(v113.locals, y113));
                        }
                        else {
                            x113.push(this.cell(v113.captures, -y113 - 1));
                        }
                    }
                    v113.stack.push(new FunctionValue(w113.functionName, x113));
                    break;
                }
            }
        }
        throw new RuntimeTrap('R0012', 'function ended without return');
    }
    private callInst(q113: Frame, r113: Instruction): void {
        let s113 = this.take(q113, r113.count);
        let t113 = this.pop(q113);
        if (t113 instanceof FunctionValue) {
            let u113 = this.functions.get(t113.name);
            if (u113 == undefined) {
                throw new RuntimeTrap('R0001', `function not found: ${t113.name}`);
            }
            if (u113.isAsync !== r113.awaited) {
                throw new RuntimeTrap('R0013', 'async call invariant');
            }
            q113.stack.push(this.run(new Frame(u113, t113.captures, s113)));
        }
        else if (t113 instanceof ExternalFunctionValue) {
            q113.stack.push(this.host.invoke(t113.module, t113.funcName, s113, r113.awaited));
        }
        else {
            throw new RuntimeTrap('R0014', 'value is not callable');
        }
    }
    private unary(o113: string, p113: RuntimeValue): RuntimeValue {
        if (o113 === '!') {
            return new VeraBooleanValue(!this.asBoolean(p113));
        }
        if (p113 instanceof VeraIntValue) {
            return new VeraIntValue(this.checked(-p113.value));
        }
        if (p113 instanceof VeraNumberValue) {
            return new VeraNumberValue(-p113.value);
        }
        throw new RuntimeTrap('R0002', 'invalid unary operand');
    }
    private binary(i113: string, j113: boolean, k113: RuntimeValue, l113: RuntimeValue): RuntimeValue {
        if (i113 === '===') {
            return new VeraBooleanValue(this.equal(k113, l113));
        }
        if (i113 === '!==') {
            return new VeraBooleanValue(!this.equal(k113, l113));
        }
        if (i113 === '&&') {
            return new VeraBooleanValue(this.asBoolean(k113) && this.asBoolean(l113));
        }
        if (i113 === '||') {
            return new VeraBooleanValue(this.asBoolean(k113) || this.asBoolean(l113));
        }
        if (k113 instanceof VeraStringValue && l113 instanceof VeraStringValue) {
            if (i113 === '+') {
                return new VeraStringValue(k113.value + l113.value);
            }
            return new VeraBooleanValue(this.compareStr(i113, k113.value, l113.value));
        }
        if (j113) {
            return this.intBinary(i113, this.asInt(k113), this.asInt(l113));
        }
        let m113 = this.asNumber(k113);
        let n113 = this.asNumber(l113);
        if (i113 === '+') {
            return new VeraNumberValue(m113 + n113);
        }
        if (i113 === '-') {
            return new VeraNumberValue(m113 - n113);
        }
        if (i113 === '*') {
            return new VeraNumberValue(m113 * n113);
        }
        if (i113 === '/') {
            return new VeraNumberValue(m113 / n113);
        }
        return new VeraBooleanValue(this.compareNum(i113, m113, n113));
    }
    private intBinary(f113: string, g113: number, h113: number): RuntimeValue {
        if (f113 === '+') {
            return new VeraIntValue(this.checked(g113 + h113));
        }
        if (f113 === '-') {
            return new VeraIntValue(this.checked(g113 - h113));
        }
        if (f113 === '*') {
            return new VeraIntValue(this.checked(g113 * h113));
        }
        if (f113 === '/') {
            if (h113 === 0) {
                throw new RuntimeTrap('R0003', 'integer division by zero');
            }
            return new VeraIntValue(this.checked(Math.trunc(g113 / h113)));
        }
        if (f113 === '%') {
            if (h113 === 0) {
                throw new RuntimeTrap('R0004', 'integer modulo by zero');
            }
            return new VeraIntValue(g113 % h113);
        }
        if (f113 === '<') {
            return new VeraBooleanValue(g113 < h113);
        }
        if (f113 === '<=') {
            return new VeraBooleanValue(g113 <= h113);
        }
        if (f113 === '>') {
            return new VeraBooleanValue(g113 > h113);
        }
        if (f113 === '>=') {
            return new VeraBooleanValue(g113 >= h113);
        }
        throw new RuntimeTrap('R0005', `invalid comparison ${f113}`);
    }
    private compareNum(c113: string, d113: number, e113: number): boolean {
        if (c113 === '<') {
            return d113 < e113;
        }
        if (c113 === '<=') {
            return d113 <= e113;
        }
        if (c113 === '>') {
            return d113 > e113;
        }
        if (c113 === '>=') {
            return d113 >= e113;
        }
        throw new RuntimeTrap('R0005', `invalid comparison ${c113}`);
    }
    private compareStr(z112: string, a113: string, b113: string): boolean {
        if (z112 === '<') {
            return a113 < b113;
        }
        if (z112 === '<=') {
            return a113 <= b113;
        }
        if (z112 === '>') {
            return a113 > b113;
        }
        if (z112 === '>=') {
            return a113 >= b113;
        }
        throw new RuntimeTrap('R0005', `invalid comparison ${z112}`);
    }
    private equal(x112: RuntimeValue, y112: RuntimeValue): boolean {
        if (x112 instanceof VeraNullValue || y112 instanceof VeraNullValue) {
            return x112 instanceof VeraNullValue && y112 instanceof VeraNullValue;
        }
        if (x112 instanceof VeraIntValue && y112 instanceof VeraIntValue) {
            return x112.value === y112.value;
        }
        if (x112 instanceof VeraNumberValue && y112 instanceof VeraNumberValue) {
            return x112.value === y112.value;
        }
        if (x112 instanceof VeraStringValue && y112 instanceof VeraStringValue) {
            return x112.value === y112.value;
        }
        if (x112 instanceof VeraBooleanValue && y112 instanceof VeraBooleanValue) {
            return x112.value === y112.value;
        }
        if (x112 instanceof FunctionValue && y112 instanceof FunctionValue) {
            return x112 === y112;
        }
        if (x112 instanceof ExternalFunctionValue && y112 instanceof ExternalFunctionValue) {
            return x112 === y112;
        }
        return false;
    }
    private checked(w112: number): number {
        if (w112 < MIN_INT || w112 > MAX_INT) {
            throw new RuntimeTrap('R0006', 'integer overflow');
        }
        return w112;
    }
    private pop(u112: Frame): RuntimeValue {
        let v112 = u112.stack.pop();
        if (v112 == undefined) {
            throw new RuntimeTrap('R0007', 'stack underflow');
        }
        return v112;
    }
    private take(p112: Frame, q112: number): RuntimeValue[] {
        if (p112.stack.length < q112) {
            throw new RuntimeTrap('R0007', 'stack underflow');
        }
        let r112: RuntimeValue[] = [];
        let s112 = p112.stack.length - q112;
        for (let t112 = s112; t112 < p112.stack.length; t112++) {
            r112.push(p112.stack[t112]);
        }
        while (p112.stack.length > s112) {
            this.pop(p112);
        }
        return r112;
    }
    private asInt(o112: RuntimeValue): number {
        if (!(o112 instanceof VeraIntValue)) {
            throw new RuntimeTrap('R0008', 'expected int');
        }
        return (o112 as VeraIntValue).value;
    }
    private asNumber(n112: RuntimeValue): number {
        if (!(n112 instanceof VeraNumberValue)) {
            throw new RuntimeTrap('R0008', 'expected number');
        }
        return (n112 as VeraNumberValue).value;
    }
    private asBoolean(m112: RuntimeValue): boolean {
        if (!(m112 instanceof VeraBooleanValue)) {
            throw new RuntimeTrap('R0008', 'expected boolean');
        }
        return (m112 as VeraBooleanValue).value;
    }
    private asArray(l112: RuntimeValue): VeraArrayValue {
        if (!(l112 instanceof VeraArrayValue)) {
            throw new RuntimeTrap('R0008', 'expected array');
        }
        return l112 as VeraArrayValue;
    }
    private asObject(k112: RuntimeValue): VeraObjectValue {
        if (!(k112 instanceof VeraObjectValue)) {
            throw new RuntimeTrap('R0008', 'expected object');
        }
        return k112 as VeraObjectValue;
    }
    private index(i112: RuntimeValue): number {
        let j112 = this.asInt(i112);
        if (j112 < 0 || j112 > MAX_INT) {
            throw new RuntimeTrap('R0009', 'array index out of bounds');
        }
        return j112;
    }
    private indexValue(g112: VeraArrayValue, h112: number): RuntimeValue {
        if (h112 < 0 || h112 >= g112.elements.length) {
            throw new RuntimeTrap('R0009', 'array index out of bounds');
        }
        return g112.elements[h112];
    }
    private cell(e112: Cell[], f112: number): Cell {
        if (f112 < 0 || f112 >= e112.length) {
            throw new RuntimeTrap('R0016', 'invalid slot');
        }
        return e112[f112];
    }
}
export function formatRuntimeValue(a112: RuntimeValue): string {
    if (a112 instanceof VeraIntValue) {
        return a112.value.toString();
    }
    if (a112 instanceof VeraNumberValue) {
        return a112.value.toString();
    }
    if (a112 instanceof VeraStringValue) {
        return a112.value;
    }
    if (a112 instanceof VeraBooleanValue) {
        return a112.value ? 'true' : 'false';
    }
    if (a112 instanceof VeraNullValue) {
        return 'null';
    }
    if (a112 instanceof VeraArrayValue) {
        return '[' + a112.elements.map((d112: RuntimeValue) => formatRuntimeValue(d112)).join(', ') + ']';
    }
    if (a112 instanceof VeraObjectValue) {
        let b112: string[] = [];
        for (let c112 of a112.fields) {
            b112.push(c112[0] + ': ' + formatRuntimeValue(c112[1]));
        }
        return '{' + b112.join(', ') + '}';
    }
    if (a112 instanceof FunctionValue) {
        return `<function ${a112.name}>`;
    }
    if (a112 instanceof ExternalFunctionValue) {
        return `<external ${a112.module}.${a112.funcName}>`;
    }
    return '<unknown>';
}
export function encodeRuntimeValue(u111: RuntimeValue): Object {
    if (u111 instanceof VeraIntValue) {
        return ['i', (u111 as VeraIntValue).value] as Object;
    }
    if (u111 instanceof VeraNumberValue) {
        return ['n', (u111 as VeraNumberValue).value] as Object;
    }
    if (u111 instanceof VeraStringValue) {
        return ['s', (u111 as VeraStringValue).value] as Object;
    }
    if (u111 instanceof VeraBooleanValue) {
        return ['b', (u111 as VeraBooleanValue).value] as Object;
    }
    if (u111 instanceof VeraNullValue) {
        return ['z'] as Object;
    }
    if (u111 instanceof VeraArrayValue) {
        let y111: Object[] = [];
        for (let z111 of (u111 as VeraArrayValue).elements) {
            y111.push(encodeRuntimeValue(z111));
        }
        return ['a', y111] as Object;
    }
    if (u111 instanceof VeraObjectValue) {
        let v111 = u111 as VeraObjectValue;
        let w111: Object[] = [];
        for (let x111 of v111.fields) {
            w111.push([x111[0], encodeRuntimeValue(x111[1])] as Object);
        }
        return ['o', v111.classIdentity, w111] as Object;
    }
    throw new RuntimeTrap('R0024', 'value cannot be saved: ' + formatRuntimeValue(u111));
}
export function decodeRuntimeValue(m111: Object): RuntimeValue {
    let n111 = m111 as Object[];
    let o111 = n111[0] as string;
    if (o111 === 'i') {
        return new VeraIntValue(n111[1] as number);
    }
    if (o111 === 'n') {
        return new VeraNumberValue(n111[1] as number);
    }
    if (o111 === 's') {
        return new VeraStringValue(n111[1] as string);
    }
    if (o111 === 'b') {
        return new VeraBooleanValue(n111[1] as boolean);
    }
    if (o111 === 'z') {
        return NULL_VALUE;
    }
    if (o111 === 'a') {
        let s111: RuntimeValue[] = [];
        for (let t111 of n111[1] as Object[]) {
            s111.push(decodeRuntimeValue(t111));
        }
        return new VeraArrayValue(s111);
    }
    if (o111 === 'o') {
        let p111 = new Map<string, RuntimeValue>();
        for (let q111 of n111[2] as Object[]) {
            let r111 = q111 as Object[];
            p111.set(r111[0] as string, decodeRuntimeValue(r111[1]));
        }
        return new VeraObjectValue(n111[1] as string, p111);
    }
    throw new RuntimeTrap('R0025', 'unknown saved value tag: ' + o111);
}
export function deserializeVbc2(d111: string): BytecodeModule {
    let e111 = JSON.parse(d111) as Object[];
    if (!Array.isArray(e111) || e111[0] !== 'VBC2') {
        throw new RuntimeTrap('VBC0004', 'unsupported VBC version');
    }
    let f111 = e111[1] as string[];
    let g111 = e111[2] as Object[][];
    let h111: BytecodeFunction[] = [];
    for (let i111 of g111) {
        let j111 = i111[4] as Object[][];
        let k111: Instruction[] = [];
        for (let l111 of j111) {
            k111.push(decodeInstruction(l111));
        }
        h111.push(new BytecodeFunction(i111[0] as string, i111[1] as number, i111[2] as number, i111[3] as boolean, k111));
    }
    return new BytecodeModule(h111, f111);
}
function decodeInstruction(a111: Object[]): Instruction {
    let b111 = a111[0] as string;
    let c111 = new Instruction(b111);
    switch (b111) {
        case 'push-int':
            c111.value = a111[1] as string;
            break;
        case 'push-number':
            c111.numValue = a111[1] as number;
            break;
        case 'push-string':
            c111.value = a111[1] as string;
            break;
        case 'push-boolean':
            c111.boolValue = a111[1] as boolean;
            break;
        case 'push-null': break;
        case 'load-local':
            c111.slot = a111[1] as number;
            break;
        case 'store-local':
            c111.slot = a111[1] as number;
            break;
        case 'load-capture':
            c111.slot = a111[1] as number;
            break;
        case 'store-capture':
            c111.slot = a111[1] as number;
            break;
        case 'load-function':
            c111.name = a111[1] as string;
            break;
        case 'load-external':
            c111.module = a111[1] as string;
            c111.name = a111[2] as string;
            break;
        case 'pop': break;
        case 'duplicate': break;
        case 'unary':
            c111.operator = a111[1] as string;
            break;
        case 'binary':
            c111.operator = a111[1] as string;
            c111.integer = a111[2] as boolean;
            break;
        case 'jump':
            c111.target = a111[1] as number;
            break;
        case 'jump-if-false':
            c111.target = a111[1] as number;
            break;
        case 'call':
            c111.count = a111[1] as number;
            c111.awaited = a111[2] as boolean;
            break;
        case 'return': break;
        case 'make-array':
            c111.count = a111[1] as number;
            break;
        case 'array-push': break;
        case 'array-pop': break;
        case 'length': break;
        case 'string-symbols': break;
        case 'ensure-not-null': break;
        case 'load-index': break;
        case 'store-index': break;
        case 'make-object':
            c111.classIdentity = a111[1] as string;
            c111.fields = a111[2] as string[];
            break;
        case 'load-field':
            c111.name = a111[1] as string;
            break;
        case 'store-field':
            c111.name = a111[1] as string;
            break;
        case 'make-closure':
            c111.functionName = a111[1] as string;
            c111.captures = a111[2] as number[];
            break;
        default:
            throw new RuntimeTrap('VBC0003', `unknown opcode: ${b111}`);
    }
    return c111;
}
