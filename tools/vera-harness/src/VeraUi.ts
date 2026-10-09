import { VeraIntValue, VeraNumberValue, VeraStringValue, VeraBooleanValue, VeraArrayValue, VeraObjectValue, HostEnvironment, RuntimeTrap, } from "./VeraInterpreter";
import type { RuntimeValue } from "./VeraInterpreter";
export class VeraUiNode {
    id: number = 0;
    kind: string = '';
    style: string = '';
    text: string = '';
    source: string = '';
    alt: string = '';
    action: string = '';
    eventValue: number = 0;
    enabled: boolean = true;
    commands: string = '';
    spinPeriodMs: number = 0;
    label: string = '';
    tickerId: string = '';
    columns: number = 1;
    value: string = '';
    checked: boolean = false;
    minimum: number = 0;
    maximum: number = 100;
    options: string[] = [];
    series: number[] = [];
    bars: boolean = false;
    children: VeraUiNode[] = [];
    intValue: number = 0;
    prefix: string = '';
    suffix: string = '';
    minimumDigits: number = 1;
    icon: string = '';
    keyboardType: string = '';
    required: boolean = false;
    requiredMessage: string = '';
    minLength: number = 0;
    minLengthMessage: string = '';
    maxLength: number = -1;
    maxLengthMessage: string = '';
    pattern: string = '';
    patternMessage: string = '';
    email: boolean = false;
    emailMessage: string = '';
}
function asString(l179: RuntimeValue): string {
    if (l179 instanceof VeraStringValue) {
        return (l179 as VeraStringValue).value;
    }
    throw new RuntimeTrap('R0020', 'expected string argument');
}
function asInt(k179: RuntimeValue): number {
    if (k179 instanceof VeraIntValue) {
        return (k179 as VeraIntValue).value;
    }
    throw new RuntimeTrap('R0020', 'expected int argument');
}
function asBool(j179: RuntimeValue): boolean {
    if (j179 instanceof VeraBooleanValue) {
        return (j179 as VeraBooleanValue).value;
    }
    throw new RuntimeTrap('R0020', 'expected boolean argument');
}
function asArray(i179: RuntimeValue): VeraArrayValue {
    if (i179 instanceof VeraArrayValue) {
        return i179 as VeraArrayValue;
    }
    throw new RuntimeTrap('R0020', 'expected array argument');
}
function argString(f179: RuntimeValue[], g179: number, h179: string = ''): string {
    if (g179 >= f179.length) {
        return h179;
    }
    return asString(f179[g179]);
}
function argInt(c179: RuntimeValue[], d179: number, e179: number = 0): number {
    if (d179 >= c179.length) {
        return e179;
    }
    return asInt(c179[d179]);
}
function argBool(z178: RuntimeValue[], a179: number, b179: boolean = true): boolean {
    if (a179 >= z178.length) {
        return b179;
    }
    return asBool(z178[a179]);
}
function argArray(x178: RuntimeValue[], y178: number): VeraArrayValue {
    if (y178 >= x178.length) {
        return new VeraArrayValue([]);
    }
    return asArray(x178[y178]);
}
function viewNode(t178: string, u178: Array<[
    string,
    RuntimeValue
]>): VeraObjectValue {
    let v178 = new Map<string, RuntimeValue>();
    v178.set('type', new VeraStringValue(t178));
    for (let w178 of u178) {
        v178.set(w178[0], w178[1]);
    }
    return new VeraObjectValue('std/ui:View', v178);
}
function containerNode(r178: string, s178: RuntimeValue[]): RuntimeValue {
    return viewNode(r178, [
        ['style', new VeraStringValue(argString(s178, 0))],
        ['children', argArray(s178, 1)],
    ]);
}
function invokeStdTime(o178: string, p178: RuntimeValue[]): RuntimeValue {
    let q178 = new Date();
    switch (o178) {
        case 'nowSeconds':
            return new VeraIntValue(Math.floor(q178.getTime() / 1000));
        case 'daysSinceEpoch':
            return new VeraIntValue(Math.floor((q178.getTime() - q178.getTimezoneOffset() * 60000) / 86400000));
        case 'millisOfDay':
            return new VeraIntValue(((q178.getHours() * 60 + q178.getMinutes()) * 60 + q178.getSeconds()) * 1000 +
                q178.getMilliseconds());
        case 'hourOfDay': return new VeraIntValue(q178.getHours());
        case 'minuteOfHour': return new VeraIntValue(q178.getMinutes());
        case 'weekday': return new VeraIntValue(q178.getDay());
        case 'dayOfMonth': return new VeraIntValue(q178.getDate());
        case 'monthOfYear': return new VeraIntValue(q178.getMonth() + 1);
        case 'year': return new VeraIntValue(q178.getFullYear());
        default:
            throw new RuntimeTrap('R0015', `unknown std/time function: ${o178}`);
    }
}
const INT32_MIN: number = -2147483648;
const INT32_MAX: number = 2147483647;
function asNumberArg(n178: RuntimeValue): number {
    if (n178 instanceof VeraNumberValue) {
        return (n178 as VeraNumberValue).value;
    }
    throw new RuntimeTrap('R0020', 'expected number argument');
}
function clampInt(l178: number): number {
    let m178 = Math.trunc(l178);
    if (m178 < INT32_MIN) {
        return INT32_MIN;
    }
    if (m178 > INT32_MAX) {
        return INT32_MAX;
    }
    return m178;
}
function invokeStdMath(g178: string, h178: RuntimeValue[]): RuntimeValue {
    switch (g178) {
        case 'intToNumber': return new VeraNumberValue(asInt(h178[0]));
        case 'numberToInt': return new VeraIntValue(clampInt(asNumberArg(h178[0])));
        case 'pi': return new VeraNumberValue(Math.PI);
        case 'sqrt': return new VeraNumberValue(Math.sqrt(asNumberArg(h178[0])));
        case 'sin': return new VeraNumberValue(Math.sin(asNumberArg(h178[0])));
        case 'cos': return new VeraNumberValue(Math.cos(asNumberArg(h178[0])));
        case 'atan2': return new VeraNumberValue(Math.atan2(asNumberArg(h178[0]), asNumberArg(h178[1])));
        case 'pow': return new VeraNumberValue(Math.pow(asNumberArg(h178[0]), asNumberArg(h178[1])));
        case 'floorToInt': return new VeraIntValue(clampInt(Math.floor(asNumberArg(h178[0]))));
        case 'roundToInt': return new VeraIntValue(clampInt(Math.round(asNumberArg(h178[0]))));
        case 'absInt': return new VeraIntValue(clampInt(Math.abs(asInt(h178[0]))));
        case 'absNumber': return new VeraNumberValue(Math.abs(asNumberArg(h178[0])));
        case 'minInt': return new VeraIntValue(Math.min(asInt(h178[0]), asInt(h178[1])));
        case 'maxInt': return new VeraIntValue(Math.max(asInt(h178[0]), asInt(h178[1])));
        case 'minNumber': return new VeraNumberValue(Math.min(asNumberArg(h178[0]), asNumberArg(h178[1])));
        case 'maxNumber': return new VeraNumberValue(Math.max(asNumberArg(h178[0]), asNumberArg(h178[1])));
        case 'randomStep': {
            let k178 = asInt(h178[0]) | 0;
            if (k178 === 0) {
                k178 = 0x2545F491;
            }
            k178 = k178 ^ (k178 << 13);
            k178 = k178 ^ (k178 >>> 17);
            k178 = k178 ^ (k178 << 5);
            return new VeraIntValue(clampInt(k178 | 0));
        }
        case 'randomBelow': {
            let i178 = asInt(h178[0]) | 0;
            let j178 = asInt(h178[1]);
            if (j178 <= 0) {
                throw new RuntimeTrap('R0026', 'randomBelow needs a positive bound');
            }
            return new VeraIntValue(Math.abs(i178) % j178);
        }
        default:
            throw new RuntimeTrap('R0015', `unknown std/math function: ${g178}`);
    }
}
function scalars(f178: string): string[] {
    return Array.from(f178);
}
function isSpace(d178: string): boolean {
    let e178 = d178.charCodeAt(0);
    if (e178 === 0x20 || (e178 >= 0x09 && e178 <= 0x0D)) {
        return true;
    }
    if (e178 === 0x85 || e178 === 0xA0 || e178 === 0x1680) {
        return true;
    }
    if (e178 >= 0x2000 && e178 <= 0x200A) {
        return true;
    }
    return e178 === 0x2028 || e178 === 0x2029 || e178 === 0x202F || e178 === 0x205F || e178 === 0x3000;
}
function invokeStdStrings(j177: string, k177: RuntimeValue[]): RuntimeValue {
    switch (j177) {
        case 'length':
            return new VeraIntValue(scalars(asString(k177[0])).length);
        case 'substring': {
            let a178 = scalars(asString(k177[0]));
            let b178 = asInt(k177[1]);
            let c178 = asInt(k177[2]);
            if (b178 < 0 || c178 < b178 || c178 > a178.length) {
                throw new RuntimeTrap('R0009', 'string index out of bounds');
            }
            return new VeraStringValue(a178.slice(b178, c178).join(''));
        }
        case 'contains':
            return new VeraBooleanValue(asString(k177[0]).indexOf(asString(k177[1])) >= 0);
        case 'startsWith':
            return new VeraBooleanValue(asString(k177[0]).startsWith(asString(k177[1])));
        case 'endsWith':
            return new VeraBooleanValue(asString(k177[0]).endsWith(asString(k177[1])));
        case 'replace': {
            let u177 = asString(k177[0]);
            let v177 = asString(k177[1]);
            let w177 = asString(k177[2]);
            if (v177.length === 0) {
                return new VeraStringValue(u177);
            }
            let x177 = '';
            let y177 = 0;
            while (y177 < u177.length) {
                let z177 = u177.indexOf(v177, y177);
                if (z177 < 0) {
                    x177 += u177.substring(y177);
                    break;
                }
                x177 += u177.substring(y177, z177) + w177;
                y177 = z177 + v177.length;
            }
            return new VeraStringValue(x177);
        }
        case 'split': {
            let o177 = asString(k177[0]);
            let p177 = asString(k177[1]);
            let q177: RuntimeValue[] = [];
            if (p177.length === 0) {
                for (let t177 of scalars(o177)) {
                    q177.push(new VeraStringValue(t177));
                }
                return new VeraArrayValue(q177);
            }
            let r177 = 0;
            while (true) {
                let s177 = o177.indexOf(p177, r177);
                if (s177 < 0) {
                    q177.push(new VeraStringValue(o177.substring(r177)));
                    break;
                }
                q177.push(new VeraStringValue(o177.substring(r177, s177)));
                r177 = s177 + p177.length;
            }
            return new VeraArrayValue(q177);
        }
        case 'trim': {
            let l177 = scalars(asString(k177[0]));
            let m177 = 0;
            let n177 = l177.length;
            while (m177 < n177 && isSpace(l177[m177])) {
                m177++;
            }
            while (n177 > m177 && isSpace(l177[n177 - 1])) {
                n177--;
            }
            return new VeraStringValue(l177.slice(m177, n177).join(''));
        }
        default:
            throw new RuntimeTrap('R0015', `unknown std/strings function: ${j177}`);
    }
}
export class HostEffect {
    id: number;
    kind: string;
    fn: string;
    values: Map<string, string>;
    resultHandler: string;
    rawTarget: string = '';
    rawParams: string = '';
    rawMode: string = '';
    constructor(e177: number, f177: string, g177: string, h177: Map<string, string>, i177: string) {
        this.id = e177;
        this.kind = f177;
        this.fn = g177;
        this.values = h177;
        this.resultHandler = i177;
    }
}
export class UiHostEnvironment extends HostEnvironment {
    pendingEffects: HostEffect[] = [];
    effectsAllowed: boolean = false;
    private nextEffectId: number = 1;
    invoke(a177: string, b177: string, c177: RuntimeValue[], d177: boolean): RuntimeValue {
        if (a177 === 'std/time') {
            return invokeStdTime(b177, c177);
        }
        if (a177 === 'std/math') {
            return invokeStdMath(b177, c177);
        }
        if (a177 === 'std/strings') {
            return invokeStdStrings(b177, c177);
        }
        if (a177 === 'std/sdk') {
            return this.queueSdk(c177);
        }
        if (a177 !== 'std/ui') {
            throw new RuntimeTrap('R0015', `external function unavailable: ${a177}.${b177}`);
        }
        switch (b177) {
            case 'Column': return containerNode('column', c177);
            case 'Row': return containerNode('row', c177);
            case 'Card': return containerNode('card', c177);
            case 'Scroll': return containerNode('scroll', c177);
            case 'Canvas': return containerNode('canvas', c177);
            case 'Text':
                return viewNode('text', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['text', new VeraStringValue(argString(c177, 1))],
                ]);
            case 'Spacer':
                return viewNode('spacer', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                ]);
            case 'Image':
                return viewNode('image', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['src', new VeraStringValue(argString(c177, 1))],
                    ['alt', new VeraStringValue(argString(c177, 2))],
                ]);
            case 'Path':
                return viewNode('path', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['commands', new VeraStringValue(argString(c177, 1))],
                    ['spinPeriodMs', new VeraIntValue(argInt(c177, 2))],
                ]);
            case 'TextField':
                return viewNode('field', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['label', new VeraStringValue(argString(c177, 1))],
                    ['value', new VeraStringValue(argString(c177, 2))],
                    ['action', new VeraStringValue(argString(c177, 3))],
                    ['keyboardType', new VeraStringValue(argString(c177, 4))],
                    ['required', new VeraBooleanValue(argBool(c177, 5, false))],
                    ['requiredMessage', new VeraStringValue(argString(c177, 6))],
                    ['minLength', new VeraIntValue(argInt(c177, 7, 0))],
                    ['minLengthMessage', new VeraStringValue(argString(c177, 8))],
                    ['maxLength', new VeraIntValue(argInt(c177, 9, -1))],
                    ['maxLengthMessage', new VeraStringValue(argString(c177, 10))],
                    ['pattern', new VeraStringValue(argString(c177, 11))],
                    ['patternMessage', new VeraStringValue(argString(c177, 12))],
                    ['email', new VeraBooleanValue(argBool(c177, 13, false))],
                    ['emailMessage', new VeraStringValue(argString(c177, 14))],
                ]);
            case 'Toggle':
            case 'Checkbox':
                return viewNode(b177 === 'Toggle' ? 'toggle' : 'checkbox', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['label', new VeraStringValue(argString(c177, 1))],
                    ['checked', new VeraBooleanValue(argBool(c177, 2))],
                    ['action', new VeraStringValue(argString(c177, 3))],
                ]);
            case 'Slider':
                return viewNode('slider', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['label', new VeraStringValue(argString(c177, 1))],
                    ['value', new VeraIntValue(argInt(c177, 2))],
                    ['minimum', new VeraIntValue(argInt(c177, 3))],
                    ['maximum', new VeraIntValue(argInt(c177, 4))],
                    ['action', new VeraStringValue(argString(c177, 5))],
                ]);
            case 'Select':
                return viewNode('select', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['label', new VeraStringValue(argString(c177, 1))],
                    ['options', argArray(c177, 2)],
                    ['value', new VeraIntValue(argInt(c177, 3))],
                    ['action', new VeraStringValue(argString(c177, 4))],
                ]);
            case 'Grid':
                return viewNode('grid', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['columns', new VeraIntValue(argInt(c177, 1))],
                    ['children', argArray(c177, 2)],
                ]);
            case 'ListItem':
                return viewNode('listitem', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['text', new VeraStringValue(argString(c177, 1))],
                    ['label', new VeraStringValue(argString(c177, 2))],
                    ['value', new VeraStringValue(argString(c177, 3))],
                    ['action', new VeraStringValue(argString(c177, 4))],
                    ['eventValue', new VeraIntValue(argInt(c177, 5))],
                    ['enabled', new VeraBooleanValue(argBool(c177, 6))],
                    ['icon', new VeraStringValue(argString(c177, 7))],
                ]);
            case 'Ticker':
                return viewNode('ticker', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['tickerId', new VeraStringValue(argString(c177, 1))],
                    ['minimum', new VeraIntValue(argInt(c177, 2))],
                    ['checked', new VeraBooleanValue(argBool(c177, 3))],
                    ['action', new VeraStringValue(argString(c177, 4))],
                ]);
            case 'Divider':
                return viewNode('divider', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                ]);
            case 'BackHandler':
                return viewNode('backhandler', [
                    ['action', new VeraStringValue(argString(c177, 0))],
                ]);
            case 'Progress':
                return viewNode('progress', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['label', new VeraStringValue(argString(c177, 1))],
                    ['value', new VeraIntValue(argInt(c177, 2))],
                    ['maximum', new VeraIntValue(argInt(c177, 3))],
                ]);
            case 'Button':
                return viewNode('button', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['text', new VeraStringValue(argString(c177, 1))],
                    ['action', new VeraStringValue(argString(c177, 2))],
                    ['value', new VeraIntValue(argInt(c177, 3))],
                    ['enabled', new VeraBooleanValue(argBool(c177, 4))],
                ]);
            case 'Cell':
                return viewNode('cell', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['text', new VeraStringValue(argString(c177, 1))],
                    ['action', new VeraStringValue(argString(c177, 2))],
                    ['value', new VeraIntValue(argInt(c177, 3))],
                    ['enabled', new VeraBooleanValue(argBool(c177, 4))],
                ]);
            case 'AppTheme':
                return viewNode('apptheme', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['value', new VeraStringValue(argString(c177, 1))],
                    ['children', argArray(c177, 2)],
                ]);
            case 'Header':
                return viewNode('header', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['text', new VeraStringValue(argString(c177, 1))],
                    ['label', new VeraStringValue(argString(c177, 2))],
                    ['value', new VeraStringValue(argString(c177, 3))],
                    ['icon', new VeraStringValue(argString(c177, 4))],
                ]);
            case 'Section':
                return viewNode('section', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['text', new VeraStringValue(argString(c177, 1))],
                    ['label', new VeraStringValue(argString(c177, 2))],
                    ['children', argArray(c177, 3)],
                ]);
            case 'SectionHeader':
                return viewNode('sectionheader', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['text', new VeraStringValue(argString(c177, 1))],
                    ['label', new VeraStringValue(argString(c177, 2))],
                    ['value', new VeraStringValue(argString(c177, 3))],
                ]);
            case 'ListGroup':
                return viewNode('listgroup', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['text', new VeraStringValue(argString(c177, 1))],
                    ['children', argArray(c177, 2)],
                ]);
            case 'InsetBanner':
                return viewNode('banner', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['text', new VeraStringValue(argString(c177, 1))],
                    ['label', new VeraStringValue(argString(c177, 2))],
                    ['value', new VeraStringValue(argString(c177, 3))],
                    ['action', new VeraStringValue(argString(c177, 4))],
                    ['icon', new VeraStringValue(argString(c177, 5))],
                ]);
            case 'EmptyState':
                return viewNode('emptystate', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['text', new VeraStringValue(argString(c177, 1))],
                    ['label', new VeraStringValue(argString(c177, 2))],
                    ['value', new VeraStringValue(argString(c177, 3))],
                    ['action', new VeraStringValue(argString(c177, 4))],
                    ['icon', new VeraStringValue(argString(c177, 5))],
                ]);
            case 'Stat':
                return viewNode('stat', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['label', new VeraStringValue(argString(c177, 1))],
                    ['text', new VeraStringValue(argString(c177, 2))],
                    ['value', new VeraStringValue(argString(c177, 3))],
                    ['icon', new VeraStringValue(argString(c177, 4))],
                ]);
            case 'MetricGroup':
                return viewNode('metricgroup', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['columns', new VeraIntValue(argInt(c177, 1))],
                    ['children', argArray(c177, 2)],
                ]);
            case 'IntText':
                return viewNode('inttext', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['intValue', new VeraIntValue(argInt(c177, 1))],
                    ['prefix', new VeraStringValue(argString(c177, 2))],
                    ['suffix', new VeraStringValue(argString(c177, 3))],
                    ['minimumDigits', new VeraIntValue(argInt(c177, 4))],
                ]);
            case 'ClockText':
                return viewNode('clocktext', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['intValue', new VeraIntValue(argInt(c177, 1))],
                    ['prefix', new VeraStringValue(argString(c177, 2))],
                    ['suffix', new VeraStringValue(argString(c177, 3))],
                ]);
            case 'IntStat':
                return viewNode('intstat', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['label', new VeraStringValue(argString(c177, 1))],
                    ['intValue', new VeraIntValue(argInt(c177, 2))],
                    ['prefix', new VeraStringValue(argString(c177, 3))],
                    ['suffix', new VeraStringValue(argString(c177, 4))],
                    ['minimumDigits', new VeraIntValue(argInt(c177, 5))],
                    ['value', new VeraStringValue(argString(c177, 6))],
                    ['icon', new VeraStringValue(argString(c177, 7))],
                ]);
            case 'IntField':
                return viewNode('intfield', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['label', new VeraStringValue(argString(c177, 1))],
                    ['intValue', new VeraIntValue(argInt(c177, 2))],
                    ['minimum', new VeraIntValue(argInt(c177, 3))],
                    ['maximum', new VeraIntValue(argInt(c177, 4))],
                    ['action', new VeraStringValue(argString(c177, 5))],
                ]);
            case 'TimeField':
                return viewNode('timefield', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['label', new VeraStringValue(argString(c177, 1))],
                    ['intValue', new VeraIntValue(argInt(c177, 2))],
                    ['action', new VeraStringValue(argString(c177, 3))],
                ]);
            case 'IntListItem':
                return viewNode('intlistitem', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['text', new VeraStringValue(argString(c177, 1))],
                    ['label', new VeraStringValue(argString(c177, 2))],
                    ['intValue', new VeraIntValue(argInt(c177, 3))],
                    ['prefix', new VeraStringValue(argString(c177, 4))],
                    ['suffix', new VeraStringValue(argString(c177, 5))],
                    ['minimumDigits', new VeraIntValue(argInt(c177, 6))],
                    ['action', new VeraStringValue(argString(c177, 7))],
                    ['eventValue', new VeraIntValue(argInt(c177, 8))],
                    ['enabled', new VeraBooleanValue(argBool(c177, 9))],
                    ['icon', new VeraStringValue(argString(c177, 10))],
                ]);
            case 'ActionBar':
                return containerNode('actionbar', c177);
            case 'Timeline':
                return viewNode('timeline', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['text', new VeraStringValue(argString(c177, 1))],
                    ['children', argArray(c177, 2)],
                ]);
            case 'TimelineItem':
                return viewNode('timelineitem', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['text', new VeraStringValue(argString(c177, 1))],
                    ['label', new VeraStringValue(argString(c177, 2))],
                    ['value', new VeraStringValue(argString(c177, 3))],
                    ['action', new VeraStringValue(argString(c177, 4))],
                    ['eventValue', new VeraIntValue(argInt(c177, 5))],
                    ['enabled', new VeraBooleanValue(argBool(c177, 6))],
                    ['icon', new VeraStringValue(argString(c177, 7))],
                ]);
            case 'Table':
                return viewNode('table', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['options', argArray(c177, 1)],
                    ['columns', new VeraIntValue(argInt(c177, 2))],
                    ['children', argArray(c177, 3)],
                ]);
            case 'TableRow':
                return viewNode('tablerow', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['options', argArray(c177, 1)],
                ]);
            case 'KeyValueGroup':
                return viewNode('kvgroup', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['columns', new VeraIntValue(argInt(c177, 1))],
                    ['children', argArray(c177, 2)],
                ]);
            case 'KeyValueItem':
                return viewNode('kvitem', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['label', new VeraStringValue(argString(c177, 1))],
                    ['text', new VeraStringValue(argString(c177, 2))],
                    ['value', new VeraStringValue(argString(c177, 3))],
                ]);
            case 'Icon':
                return viewNode('icon', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['icon', new VeraStringValue(argString(c177, 1))],
                ]);
            case 'IconButton':
                return viewNode('iconbutton', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['icon', new VeraStringValue(argString(c177, 1))],
                    ['label', new VeraStringValue(argString(c177, 2))],
                    ['action', new VeraStringValue(argString(c177, 3))],
                    ['value', new VeraIntValue(argInt(c177, 4))],
                    ['enabled', new VeraBooleanValue(argBool(c177, 5))],
                ]);
            case 'Badge':
                return viewNode('badge', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['text', new VeraStringValue(argString(c177, 1))],
                    ['icon', new VeraStringValue(argString(c177, 2))],
                ]);
            case 'Skeleton':
                return viewNode('skeleton', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['minimum', new VeraIntValue(argInt(c177, 1))],
                    ['maximum', new VeraIntValue(argInt(c177, 2))],
                    ['checked', new VeraBooleanValue(argBool(c177, 3, false))],
                ]);
            case 'Spinner':
                return viewNode('spinner', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['label', new VeraStringValue(argString(c177, 1))],
                ]);
            case 'Snackbar':
                return viewNode('snackbar', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['text', new VeraStringValue(argString(c177, 1))],
                    ['value', new VeraStringValue(argString(c177, 2))],
                    ['action', new VeraStringValue(argString(c177, 3))],
                ]);
            case 'Sparkline':
                return viewNode('sparkline', [
                    ['style', new VeraStringValue(argString(c177, 0))],
                    ['series', argArray(c177, 1)],
                    ['maximum', new VeraIntValue(argInt(c177, 2))],
                    ['label', new VeraStringValue(argString(c177, 3))],
                    ['bars', new VeraBooleanValue(argBool(c177, 4, false))],
                ]);
            case 'When':
                if (asBool(c177[0])) {
                    return c177[1];
                }
                return viewNode('spacer', [['style', new VeraStringValue('none')]]);
            case 'intToString':
                return new VeraStringValue(asInt(c177[0]).toString());
            case 'numberToString': {
                if (!(c177[0] instanceof VeraNumberValue)) {
                    throw new RuntimeTrap('R0020', 'expected number argument');
                }
                return new VeraStringValue((c177[0] as VeraNumberValue).value.toString());
            }
            case 'booleanToString':
                return new VeraStringValue(asBool(c177[0]) ? 'true' : 'false');
            default:
                throw new RuntimeTrap('R0015', `unknown std/ui function: ${b177}`);
        }
    }
    private queueSdk(q176: RuntimeValue[]): RuntimeValue {
        if (!this.effectsAllowed) {
            throw new RuntimeTrap('R0026', 'sdk.call may only be called from a handler, not from view');
        }
        let r176 = asString(q176[0]).trim();
        let s176 = asArray(q176[1]).elements;
        if (s176.length % 2 !== 0) {
            throw new RuntimeTrap('R0027', 'sdk.call parameters are name and value in pairs; got ' + s176.length.toString() + ' items');
        }
        let t176 = new Map<string, string>();
        let u176: string[] = [];
        for (let y176 = 0; y176 + 1 < s176.length; y176 = y176 + 2) {
            let z176 = asString(s176[y176]).trim();
            if (z176.length === 0) {
                continue;
            }
            t176.set(z176, asString(s176[y176 + 1]));
            u176.push(z176);
        }
        let v176 = q176.length > 3 ? asString(q176[3]) : 'background';
        let w176 = this.nextEffectId;
        this.nextEffectId = w176 + 1;
        let x176 = new HostEffect(w176, 'sdk', 'call', t176, asString(q176[2]));
        x176.rawTarget = r176;
        x176.rawParams = u176.join(' ');
        x176.rawMode = v176;
        this.pendingEffects.push(x176);
        return new VeraIntValue(w176);
    }
}
let nextNodeId: number = 0;
export function decodeVeraUi(p176: RuntimeValue): VeraUiNode[] {
    nextNodeId = 0;
    if (p176 instanceof VeraObjectValue) {
        return [decodeNode(p176 as VeraObjectValue, 0)];
    }
    return [];
}
function decodeNode(e176: VeraObjectValue, f176: number): VeraUiNode {
    if (f176 > 8) {
        throw new RuntimeTrap('R0021', 'view tree too deep (max 8)');
    }
    let g176 = new VeraUiNode();
    g176.id = nextNodeId;
    nextNodeId += 1;
    for (let h176 of e176.fields.entries()) {
        let i176: string = h176[0];
        let j176: RuntimeValue = h176[1];
        switch (i176) {
            case 'type':
                if (j176 instanceof VeraStringValue) {
                    g176.kind = (j176 as VeraStringValue).value;
                }
                break;
            case 'style':
                if (j176 instanceof VeraStringValue) {
                    g176.style = (j176 as VeraStringValue).value;
                }
                break;
            case 'text':
                if (j176 instanceof VeraStringValue) {
                    g176.text = (j176 as VeraStringValue).value;
                }
                break;
            case 'src':
                if (j176 instanceof VeraStringValue) {
                    g176.source = (j176 as VeraStringValue).value;
                }
                break;
            case 'alt':
                if (j176 instanceof VeraStringValue) {
                    g176.alt = (j176 as VeraStringValue).value;
                }
                break;
            case 'action':
                if (j176 instanceof VeraStringValue) {
                    g176.action = (j176 as VeraStringValue).value;
                }
                break;
            case 'label':
                if (j176 instanceof VeraStringValue) {
                    g176.label = (j176 as VeraStringValue).value;
                }
                break;
            case 'tickerId':
                if (j176 instanceof VeraStringValue) {
                    g176.tickerId = (j176 as VeraStringValue).value;
                }
                break;
            case 'commands':
                if (j176 instanceof VeraStringValue) {
                    g176.commands = (j176 as VeraStringValue).value;
                }
                break;
            case 'prefix':
                if (j176 instanceof VeraStringValue) {
                    g176.prefix = (j176 as VeraStringValue).value;
                }
                break;
            case 'icon':
                if (j176 instanceof VeraStringValue) {
                    g176.icon = (j176 as VeraStringValue).value;
                }
                break;
            case 'suffix':
                if (j176 instanceof VeraStringValue) {
                    g176.suffix = (j176 as VeraStringValue).value;
                }
                break;
            case 'value':
                if (j176 instanceof VeraIntValue) {
                    g176.eventValue = (j176 as VeraIntValue).value;
                }
                else if (j176 instanceof VeraStringValue) {
                    g176.value = (j176 as VeraStringValue).value;
                }
                break;
            case 'eventValue':
                if (j176 instanceof VeraIntValue) {
                    g176.eventValue = (j176 as VeraIntValue).value;
                }
                break;
            case 'intValue':
                if (j176 instanceof VeraIntValue) {
                    g176.intValue = (j176 as VeraIntValue).value;
                }
                break;
            case 'minimumDigits':
                if (j176 instanceof VeraIntValue) {
                    g176.minimumDigits = (j176 as VeraIntValue).value;
                }
                break;
            case 'spinPeriodMs':
                if (j176 instanceof VeraIntValue) {
                    g176.spinPeriodMs = (j176 as VeraIntValue).value;
                }
                break;
            case 'columns':
                if (j176 instanceof VeraIntValue) {
                    g176.columns = (j176 as VeraIntValue).value;
                }
                break;
            case 'minimum':
                if (j176 instanceof VeraIntValue) {
                    g176.minimum = (j176 as VeraIntValue).value;
                }
                break;
            case 'maximum':
                if (j176 instanceof VeraIntValue) {
                    g176.maximum = (j176 as VeraIntValue).value;
                }
                break;
            case 'checked':
                if (j176 instanceof VeraBooleanValue) {
                    g176.checked = (j176 as VeraBooleanValue).value;
                }
                break;
            case 'enabled':
                if (j176 instanceof VeraBooleanValue) {
                    g176.enabled = (j176 as VeraBooleanValue).value;
                }
                break;
            case 'bars':
                if (j176 instanceof VeraBooleanValue) {
                    g176.bars = (j176 as VeraBooleanValue).value;
                }
                break;
            case 'options':
                if (j176 instanceof VeraArrayValue) {
                    let n176: string[] = [];
                    for (let o176 of (j176 as VeraArrayValue).elements) {
                        if (o176 instanceof VeraStringValue) {
                            n176.push((o176 as VeraStringValue).value);
                        }
                    }
                    g176.options = n176;
                }
                break;
            case 'series':
                if (j176 instanceof VeraArrayValue) {
                    let l176: number[] = [];
                    for (let m176 of (j176 as VeraArrayValue).elements) {
                        if (m176 instanceof VeraIntValue) {
                            l176.push((m176 as VeraIntValue).value);
                        }
                    }
                    g176.series = l176;
                }
                break;
            case 'keyboardType':
                if (j176 instanceof VeraStringValue) {
                    g176.keyboardType = (j176 as VeraStringValue).value;
                }
                break;
            case 'required':
                if (j176 instanceof VeraBooleanValue) {
                    g176.required = (j176 as VeraBooleanValue).value;
                }
                break;
            case 'requiredMessage':
                if (j176 instanceof VeraStringValue) {
                    g176.requiredMessage = (j176 as VeraStringValue).value;
                }
                break;
            case 'minLength':
                if (j176 instanceof VeraIntValue) {
                    g176.minLength = (j176 as VeraIntValue).value;
                }
                break;
            case 'minLengthMessage':
                if (j176 instanceof VeraStringValue) {
                    g176.minLengthMessage = (j176 as VeraStringValue).value;
                }
                break;
            case 'maxLength':
                if (j176 instanceof VeraIntValue) {
                    g176.maxLength = (j176 as VeraIntValue).value;
                }
                break;
            case 'maxLengthMessage':
                if (j176 instanceof VeraStringValue) {
                    g176.maxLengthMessage = (j176 as VeraStringValue).value;
                }
                break;
            case 'pattern':
                if (j176 instanceof VeraStringValue) {
                    g176.pattern = (j176 as VeraStringValue).value;
                }
                break;
            case 'patternMessage':
                if (j176 instanceof VeraStringValue) {
                    g176.patternMessage = (j176 as VeraStringValue).value;
                }
                break;
            case 'email':
                if (j176 instanceof VeraBooleanValue) {
                    g176.email = (j176 as VeraBooleanValue).value;
                }
                break;
            case 'emailMessage':
                if (j176 instanceof VeraStringValue) {
                    g176.emailMessage = (j176 as VeraStringValue).value;
                }
                break;
            case 'children':
                if (j176 instanceof VeraArrayValue) {
                    for (let k176 of (j176 as VeraArrayValue).elements) {
                        if (k176 instanceof VeraObjectValue) {
                            g176.children.push(decodeNode(k176 as VeraObjectValue, f176 + 1));
                        }
                    }
                }
                break;
            default:
                break;
        }
    }
    return g176;
}
