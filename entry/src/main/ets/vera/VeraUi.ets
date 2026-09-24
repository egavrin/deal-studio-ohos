import {
  RuntimeValue,
  VeraIntValue,
  VeraNumberValue,
  VeraStringValue,
  VeraBooleanValue,
  VeraNullValue,
  VeraArrayValue,
  VeraObjectValue,
  NULL_VALUE,
  HostEnvironment,
  RuntimeTrap,
} from './VeraInterpreter'
import { IntentSpec, intentByName } from './VeraIntentCatalog'
import { calendarFnByName } from './VeraCalendarCatalog'

export class VeraUiNode {
  id: number = 0
  kind: string = ''
  style: string = ''
  text: string = ''
  source: string = ''
  alt: string = ''
  action: string = ''
  eventValue: number = 0
  enabled: boolean = true
  commands: string = ''
  spinPeriodMs: number = 0
  label: string = ''
  tickerId: string = ''
  columns: number = 1
  value: string = ''
  checked: boolean = false
  minimum: number = 0
  maximum: number = 100
  options: string[] = []
  children: VeraUiNode[] = []

  /**
   * The typed numeric layer.
   *
   * A number used to reach the screen only as a string the program had already
   * built -- ui.intToString, and a hand-written pad2 for anything wider than
   * one digit, because the language has no number formatting and no way back
   * from a string to an int. So every count was formatted by the program, and
   * a program that wanted "07" wrote the function to produce it.
   *
   * These carry the number itself and say how to show it, and the renderer does
   * the formatting. `intValue` is the number; `eventValue` stays what it always
   * was, the payload of a tap, so a row can carry both.
   */
  intValue: number = 0
  prefix: string = ''
  suffix: string = ''
  minimumDigits: number = 1

  /** The name of an icon in VeraIcons; '' for none. */
  icon: string = ''
}

function asString(v: RuntimeValue): string {
  if (v instanceof VeraStringValue) { return (v as VeraStringValue).value }
  throw new RuntimeTrap('R0020', 'expected string argument')
}

function asInt(v: RuntimeValue): number {
  if (v instanceof VeraIntValue) { return (v as VeraIntValue).value }
  throw new RuntimeTrap('R0020', 'expected int argument')
}

function asBool(v: RuntimeValue): boolean {
  if (v instanceof VeraBooleanValue) { return (v as VeraBooleanValue).value }
  throw new RuntimeTrap('R0020', 'expected boolean argument')
}

function asArray(v: RuntimeValue): VeraArrayValue {
  if (v instanceof VeraArrayValue) { return v as VeraArrayValue }
  throw new RuntimeTrap('R0020', 'expected array argument')
}

/**
 * Reading an argument that a saved program may not have passed.
 *
 * The VM hands `invoke` exactly the arguments the bytecode pushed, so the day a
 * component gains a property, every program compiled before that day calls it
 * one argument short and asString(undefined) traps. The programs are stored as
 * bytecode, not source, so they cannot be recompiled -- a saved app would simply
 * stop running.
 *
 * Reading past the end as "not given" is what makes the vocabulary extensible:
 * a property may be appended to any component for ever after, old programs keep
 * running with the default, and new ones still have to pass it because the
 * compiler checks arity (E2036) against the catalogue.
 */
function argString(args: RuntimeValue[], i: number, fallback: string = ''): string {
  if (i >= args.length) { return fallback }
  return asString(args[i])
}

function argInt(args: RuntimeValue[], i: number, fallback: number = 0): number {
  if (i >= args.length) { return fallback }
  return asInt(args[i])
}

function argBool(args: RuntimeValue[], i: number, fallback: boolean = true): boolean {
  if (i >= args.length) { return fallback }
  return asBool(args[i])
}

function argArray(args: RuntimeValue[], i: number): VeraArrayValue {
  if (i >= args.length) { return new VeraArrayValue([]) }
  return asArray(args[i])
}

function viewNode(type: string, fields: Array<[string, RuntimeValue]>): VeraObjectValue {
  let map = new Map<string, RuntimeValue>()
  map.set('type', new VeraStringValue(type))
  for (let pair of fields) {
    map.set(pair[0], pair[1])
  }
  return new VeraObjectValue('std/ui:View', map)
}

function containerNode(type: string, args: RuntimeValue[]): RuntimeValue {
  return viewNode(type, [
    ['style', new VeraStringValue(argString(args, 0))],
    ['children', argArray(args, 1)],
  ])
}

/**
 * The clock, as seen by a generated program.
 *
 * Local time, and every value an int: nowSeconds fits int32 until 2038, whereas
 * milliseconds (~1.8e12) would trip the VM's overflow check on arrival.
 * daysSinceEpoch is what makes "is this the same day as the last dose?"
 * expressible without any date arithmetic in the language.
 */
function invokeStdTime(name: string, args: RuntimeValue[]): RuntimeValue {
  let now = new Date()
  switch (name) {
    case 'nowSeconds':
      return new VeraIntValue(Math.floor(now.getTime() / 1000))
    case 'daysSinceEpoch':
      // Local midnights, not UTC: a dose taken at 23:30 belongs to that day for
      // the person holding the phone.
      return new VeraIntValue(Math.floor(
        (now.getTime() - now.getTimezoneOffset() * 60000) / 86400000))
    case 'millisOfDay':
      // Milliseconds since local midnight. A full epoch timestamp in
      // milliseconds is ~1.8e12 and would not survive int32, but a day is only
      // 86.4 million, so this is how a program gets sub-second resolution.
      return new VeraIntValue(
        ((now.getHours() * 60 + now.getMinutes()) * 60 + now.getSeconds()) * 1000 +
        now.getMilliseconds())
    case 'hourOfDay': return new VeraIntValue(now.getHours())
    case 'minuteOfHour': return new VeraIntValue(now.getMinutes())
    case 'weekday': return new VeraIntValue(now.getDay())
    // daysSinceEpoch can say "the same day" but not "which day". Anything read
    // back later -- a history row, a summary shown to another person -- needs
    // to name the date, so these three are the calendar.
    case 'dayOfMonth': return new VeraIntValue(now.getDate())
    case 'monthOfYear': return new VeraIntValue(now.getMonth() + 1)
    case 'year': return new VeraIntValue(now.getFullYear())
    default:
      throw new RuntimeTrap('R0015', `unknown std/time function: ${name}`)
  }
}

const INT32_MIN: number = -2147483648
const INT32_MAX: number = 2147483647

function asNumberArg(v: RuntimeValue): number {
  if (v instanceof VeraNumberValue) { return (v as VeraNumberValue).value }
  throw new RuntimeTrap('R0020', 'expected number argument')
}

/** Keep a host-produced int inside the range the VM will accept back. */
function clampInt(v: number): number {
  let n = Math.trunc(v)
  if (n < INT32_MIN) { return INT32_MIN }
  if (n > INT32_MAX) { return INT32_MAX }
  return n
}

/**
 * Arithmetic the language cannot express, plus a deterministic generator.
 *
 * randomStep is xorshift32 done with JS bitwise operators, which wrap by
 * definition -- the VM's own multiply would trap on the overflow this needs, so
 * a pseudo-random sequence cannot be written in VERA-L at all.
 */
function invokeStdMath(name: string, args: RuntimeValue[]): RuntimeValue {
  switch (name) {
    case 'intToNumber': return new VeraNumberValue(asInt(args[0]))
    case 'numberToInt': return new VeraIntValue(clampInt(asNumberArg(args[0])))
    case 'pi': return new VeraNumberValue(Math.PI)
    case 'sqrt': return new VeraNumberValue(Math.sqrt(asNumberArg(args[0])))
    case 'sin': return new VeraNumberValue(Math.sin(asNumberArg(args[0])))
    case 'cos': return new VeraNumberValue(Math.cos(asNumberArg(args[0])))
    case 'atan2': return new VeraNumberValue(Math.atan2(asNumberArg(args[0]), asNumberArg(args[1])))
    case 'pow': return new VeraNumberValue(Math.pow(asNumberArg(args[0]), asNumberArg(args[1])))
    case 'floorToInt': return new VeraIntValue(clampInt(Math.floor(asNumberArg(args[0]))))
    case 'roundToInt': return new VeraIntValue(clampInt(Math.round(asNumberArg(args[0]))))
    case 'absInt': return new VeraIntValue(clampInt(Math.abs(asInt(args[0]))))
    case 'absNumber': return new VeraNumberValue(Math.abs(asNumberArg(args[0])))
    case 'minInt': return new VeraIntValue(Math.min(asInt(args[0]), asInt(args[1])))
    case 'maxInt': return new VeraIntValue(Math.max(asInt(args[0]), asInt(args[1])))
    case 'minNumber': return new VeraNumberValue(Math.min(asNumberArg(args[0]), asNumberArg(args[1])))
    case 'maxNumber': return new VeraNumberValue(Math.max(asNumberArg(args[0]), asNumberArg(args[1])))
    case 'randomStep': {
      let x = asInt(args[0]) | 0
      if (x === 0) { x = 0x2545F491 }
      x = x ^ (x << 13); x = x ^ (x >>> 17); x = x ^ (x << 5)
      return new VeraIntValue(clampInt(x | 0))
    }
    case 'randomBelow': {
      let seed = asInt(args[0]) | 0
      let bound = asInt(args[1])
      if (bound <= 0) { throw new RuntimeTrap('R0026', 'randomBelow needs a positive bound') }
      return new VeraIntValue(Math.abs(seed) % bound)
    }
    default:
      throw new RuntimeTrap('R0015', `unknown std/math function: ${name}`)
  }
}

/**
 * Text, per the `std/strings` library in VERA-L.md.
 *
 * The language gives a string only `+`, comparison, `.length()` and for-of over
 * its characters, so a program could assemble text but never take it apart.
 *
 * Positions here are Unicode scalar values, as the spec requires, not the
 * UTF-16 code units ArkTS counts -- hence the Array.from before any indexing.
 * The `.length()` intrinsic still counts code units, so it and strings.length
 * disagree on an emoji and agree on everything in the BMP; for-of over a string
 * already counts scalars, so this side is the one with two allies.
 */
function scalars(s: string): string[] {
  return Array.from(s)
}

/**
 * Unicode White_Space. ArkTS's own trim() follows the ECMAScript definition,
 * which omits U+0085, so the set is spelled out rather than delegated.
 */
function isSpace(ch: string): boolean {
  let c = ch.charCodeAt(0)
  if (c === 0x20 || (c >= 0x09 && c <= 0x0D)) { return true }
  if (c === 0x85 || c === 0xA0 || c === 0x1680) { return true }
  if (c >= 0x2000 && c <= 0x200A) { return true }
  return c === 0x2028 || c === 0x2029 || c === 0x202F || c === 0x205F || c === 0x3000
}

function invokeStdStrings(name: string, args: RuntimeValue[]): RuntimeValue {
  switch (name) {
    case 'length':
      return new VeraIntValue(scalars(asString(args[0])).length)
    case 'substring': {
      let chars = scalars(asString(args[0]))
      let start = asInt(args[1])
      let end = asInt(args[2])
      // The spec raises rather than clamping: a bad range is a bug in the
      // program, and silently returning a shorter string hides it.
      if (start < 0 || end < start || end > chars.length) {
        throw new RuntimeTrap('R0009', 'string index out of bounds')
      }
      return new VeraStringValue(chars.slice(start, end).join(''))
    }
    case 'contains':
      return new VeraBooleanValue(asString(args[0]).indexOf(asString(args[1])) >= 0)
    case 'startsWith':
      return new VeraBooleanValue(asString(args[0]).startsWith(asString(args[1])))
    case 'endsWith':
      return new VeraBooleanValue(asString(args[0]).endsWith(asString(args[1])))
    case 'replace': {
      let text = asString(args[0])
      let from = asString(args[1])
      let to = asString(args[2])
      // An empty needle would match at every position forever.
      if (from.length === 0) { return new VeraStringValue(text) }
      let out = ''
      let i = 0
      while (i < text.length) {
        let hit = text.indexOf(from, i)
        if (hit < 0) { out += text.substring(i); break }
        out += text.substring(i, hit) + to
        i = hit + from.length
      }
      return new VeraStringValue(out)
    }
    case 'split': {
      let text = asString(args[0])
      let sep = asString(args[1])
      let parts: RuntimeValue[] = []
      if (sep.length === 0) {
        for (let ch of scalars(text)) { parts.push(new VeraStringValue(ch)) }
        return new VeraArrayValue(parts)
      }
      let i = 0
      while (true) {
        let hit = text.indexOf(sep, i)
        if (hit < 0) { parts.push(new VeraStringValue(text.substring(i))); break }
        parts.push(new VeraStringValue(text.substring(i, hit)))
        i = hit + sep.length
      }
      return new VeraArrayValue(parts)
    }
    case 'trim': {
      let chars = scalars(asString(args[0]))
      let start = 0
      let end = chars.length
      while (start < end && isSpace(chars[start])) { start++ }
      while (end > start && isSpace(chars[end - 1])) { end-- }
      return new VeraStringValue(chars.slice(start, end).join(''))
    }
    default:
      throw new RuntimeTrap('R0015', `unknown std/strings function: ${name}`)
  }
}

/**
 * One intent the program asked for, waiting to be run.
 *
 * The VM is synchronous -- invoke() has to return a value on the spot -- while
 * the platform answers with a promise. So the call does not run the intent; it
 * records the request, and whoever drives the VM runs it afterwards and brings
 * the answer back through the ordinary handler path.
 */
export class HostEffect {
  id: number
  /** 'intent' or 'calendar' -- which host the request is for. */
  kind: string
  /** Which function of that host: the intent's row name, or addEvent/clearEvents. */
  fn: string
  /** The intent's row; null for a raw call and for any other kind. */
  spec: IntentSpec | null
  values: Map<string, string>
  resultHandler: string
  /** intent.call only: bundle/module/ability/IntentName, as the program wrote it. */
  rawTarget: string = ''
  /** intent.call only: the parameter names, in the order the program wrote them. */
  rawParams: string = ''
  /** intent.call only: 'foreground' or 'background'. */
  rawMode: string = ''
  constructor(id: number, kind: string, fn: string, spec: IntentSpec | null,
      values: Map<string, string>, resultHandler: string) {
    this.id = id; this.kind = kind; this.fn = fn; this.spec = spec
    this.values = values; this.resultHandler = resultHandler
  }
}

export class UiHostEnvironment extends HostEnvironment {
  /** Requests made during the handler that is running now. */
  pendingEffects: HostEffect[] = []
  /**
   * Whether an effect may be requested at all: true while a handler runs, false
   * while view() runs. view is a pure function of state and is re-run on every
   * change, so an intent call from there would start navigation on every
   * repaint.
   */
  effectsAllowed: boolean = false
  private nextEffectId: number = 1

  invoke(module: string, name: string, args: RuntimeValue[], awaited: boolean): RuntimeValue {
    if (module === 'std/time') { return invokeStdTime(name, args) }
    if (module === 'std/math') { return invokeStdMath(name, args) }
    if (module === 'std/strings') { return invokeStdStrings(name, args) }
    if (module === 'std/intent') { return this.queueIntent(name, args) }
    if (module === 'std/calendar') { return this.queueCalendar(name, args) }
    if (module !== 'std/ui') {
      throw new RuntimeTrap('R0015', `external function unavailable: ${module}.${name}`)
    }
    switch (name) {
      case 'Column': return containerNode('column', args)
      case 'Row': return containerNode('row', args)
      case 'Card': return containerNode('card', args)
      case 'Scroll': return containerNode('scroll', args)
      case 'Canvas': return containerNode('canvas', args)
      case 'Text':
        return viewNode('text', [
          ['style', new VeraStringValue(argString(args, 0))],
          ['text', new VeraStringValue(argString(args, 1))],
        ])
      case 'Spacer':
        return viewNode('spacer', [
          ['style', new VeraStringValue(argString(args, 0))],
        ])
      case 'Image':
        return viewNode('image', [
          ['style', new VeraStringValue(argString(args, 0))],
          ['src', new VeraStringValue(argString(args, 1))],
          ['alt', new VeraStringValue(argString(args, 2))],
        ])
      case 'Path':
        return viewNode('path', [
          ['style', new VeraStringValue(argString(args, 0))],
          ['commands', new VeraStringValue(argString(args, 1))],
          ['spinPeriodMs', new VeraIntValue(argInt(args, 2))],
        ])
      case 'TextField':
        return viewNode('field', [
          ['style', new VeraStringValue(argString(args, 0))],
          ['label', new VeraStringValue(argString(args, 1))],
          ['value', new VeraStringValue(argString(args, 2))],
          ['action', new VeraStringValue(argString(args, 3))],
        ])
      case 'Toggle':
      case 'Checkbox':
        return viewNode(name === 'Toggle' ? 'toggle' : 'checkbox', [
          ['style', new VeraStringValue(argString(args, 0))],
          ['label', new VeraStringValue(argString(args, 1))],
          ['checked', new VeraBooleanValue(argBool(args, 2))],
          ['action', new VeraStringValue(argString(args, 3))],
        ])
      case 'Slider':
        return viewNode('slider', [
          ['style', new VeraStringValue(argString(args, 0))],
          ['label', new VeraStringValue(argString(args, 1))],
          ['value', new VeraIntValue(argInt(args, 2))],
          ['minimum', new VeraIntValue(argInt(args, 3))],
          ['maximum', new VeraIntValue(argInt(args, 4))],
          ['action', new VeraStringValue(argString(args, 5))],
        ])
      case 'Select':
        return viewNode('select', [
          ['style', new VeraStringValue(argString(args, 0))],
          ['label', new VeraStringValue(argString(args, 1))],
          ['options', argArray(args, 2)],
          ['value', new VeraIntValue(argInt(args, 3))],
          ['action', new VeraStringValue(argString(args, 4))],
        ])
      case 'Grid':
        return viewNode('grid', [
          ['style', new VeraStringValue(argString(args, 0))],
          ['columns', new VeraIntValue(argInt(args, 1))],
          ['children', argArray(args, 2)],
        ])
      case 'ListItem':
        return viewNode('listitem', [
          ['style', new VeraStringValue(argString(args, 0))],
          ['text', new VeraStringValue(argString(args, 1))],
          ['label', new VeraStringValue(argString(args, 2))],
          ['value', new VeraStringValue(argString(args, 3))],
          ['action', new VeraStringValue(argString(args, 4))],
          ['eventValue', new VeraIntValue(argInt(args, 5))],
          ['enabled', new VeraBooleanValue(argBool(args, 6))],
          ['icon', new VeraStringValue(argString(args, 7))],
        ])
      case 'Ticker':
        return viewNode('ticker', [
          ['style', new VeraStringValue(argString(args, 0))],
          ['tickerId', new VeraStringValue(argString(args, 1))],
          ['minimum', new VeraIntValue(argInt(args, 2))],
          ['checked', new VeraBooleanValue(argBool(args, 3))],
          ['action', new VeraStringValue(argString(args, 4))],
        ])
      case 'Divider':
        return viewNode('divider', [
          ['style', new VeraStringValue(argString(args, 0))],
        ])
      case 'Progress':
        return viewNode('progress', [
          ['style', new VeraStringValue(argString(args, 0))],
          ['label', new VeraStringValue(argString(args, 1))],
          ['value', new VeraIntValue(argInt(args, 2))],
          ['maximum', new VeraIntValue(argInt(args, 3))],
        ])
      case 'Button':
        return viewNode('button', [
          ['style', new VeraStringValue(argString(args, 0))],
          ['text', new VeraStringValue(argString(args, 1))],
          ['action', new VeraStringValue(argString(args, 2))],
          ['value', new VeraIntValue(argInt(args, 3))],
          ['enabled', new VeraBooleanValue(argBool(args, 4))],
        ])
      case 'Cell':
        return viewNode('cell', [
          ['style', new VeraStringValue(argString(args, 0))],
          ['text', new VeraStringValue(argString(args, 1))],
          ['action', new VeraStringValue(argString(args, 2))],
          ['value', new VeraIntValue(argInt(args, 3))],
          ['enabled', new VeraBooleanValue(argBool(args, 4))],
        ])
      // The compositional layer. Every one of these reuses fields the decoder
      // already reads -- text, label, value, columns, children -- so nothing
      // below decodeNode changes and its measured cost stays where it was.
      case 'AppTheme':
        return viewNode('apptheme', [
          ['style', new VeraStringValue(argString(args, 0))],
          // The seed colour, under the name the decoder already reads a string
          // from. '' means the preset keeps its own primary.
          ['value', new VeraStringValue(argString(args, 1))],
          ['children', argArray(args, 2)],
        ])
      case 'Header':
        return viewNode('header', [
          ['style', new VeraStringValue(argString(args, 0))],
          ['text', new VeraStringValue(argString(args, 1))],
          ['label', new VeraStringValue(argString(args, 2))],
          ['value', new VeraStringValue(argString(args, 3))],
          ['icon', new VeraStringValue(argString(args, 4))],
        ])
      case 'Section':
        return viewNode('section', [
          ['style', new VeraStringValue(argString(args, 0))],
          ['text', new VeraStringValue(argString(args, 1))],
          ['label', new VeraStringValue(argString(args, 2))],
          ['children', argArray(args, 3)],
        ])
      case 'SectionHeader':
        return viewNode('sectionheader', [
          ['style', new VeraStringValue(argString(args, 0))],
          ['text', new VeraStringValue(argString(args, 1))],
          ['label', new VeraStringValue(argString(args, 2))],
          ['value', new VeraStringValue(argString(args, 3))],
        ])
      case 'ListGroup':
        return viewNode('listgroup', [
          ['style', new VeraStringValue(argString(args, 0))],
          ['text', new VeraStringValue(argString(args, 1))],
          ['children', argArray(args, 2)],
        ])
      case 'InsetBanner':
        return viewNode('banner', [
          ['style', new VeraStringValue(argString(args, 0))],
          ['text', new VeraStringValue(argString(args, 1))],
          ['label', new VeraStringValue(argString(args, 2))],
          ['value', new VeraStringValue(argString(args, 3))],
          ['action', new VeraStringValue(argString(args, 4))],
          ['icon', new VeraStringValue(argString(args, 5))],
        ])
      case 'EmptyState':
        return viewNode('emptystate', [
          ['style', new VeraStringValue(argString(args, 0))],
          ['text', new VeraStringValue(argString(args, 1))],
          ['label', new VeraStringValue(argString(args, 2))],
          ['value', new VeraStringValue(argString(args, 3))],
          ['action', new VeraStringValue(argString(args, 4))],
          ['icon', new VeraStringValue(argString(args, 5))],
        ])
      case 'Stat':
        // label is the caption, text the figure, value the line beneath -- the
        // figure goes in 'text' because that is the field a Text-like node
        // carries and the renderer draws largest.
        return viewNode('stat', [
          ['style', new VeraStringValue(argString(args, 0))],
          ['label', new VeraStringValue(argString(args, 1))],
          ['text', new VeraStringValue(argString(args, 2))],
          ['value', new VeraStringValue(argString(args, 3))],
          ['icon', new VeraStringValue(argString(args, 4))],
        ])
      case 'MetricGroup':
        return viewNode('metricgroup', [
          ['style', new VeraStringValue(argString(args, 0))],
          ['columns', new VeraIntValue(argInt(args, 1))],
          ['children', argArray(args, 2)],
        ])
      // The typed numeric layer. The number travels as a number and the
      // renderer formats it, so a program never builds a digit string and
      // never needs the padding function it cannot write.
      case 'IntText':
        return viewNode('inttext', [
          ['style', new VeraStringValue(argString(args, 0))],
          ['intValue', new VeraIntValue(argInt(args, 1))],
          ['prefix', new VeraStringValue(argString(args, 2))],
          ['suffix', new VeraStringValue(argString(args, 3))],
          ['minimumDigits', new VeraIntValue(argInt(args, 4))],
        ])
      case 'ClockText':
        return viewNode('clocktext', [
          ['style', new VeraStringValue(argString(args, 0))],
          ['intValue', new VeraIntValue(argInt(args, 1))],
          ['prefix', new VeraStringValue(argString(args, 2))],
          ['suffix', new VeraStringValue(argString(args, 3))],
        ])
      case 'IntStat':
        return viewNode('intstat', [
          ['style', new VeraStringValue(argString(args, 0))],
          ['label', new VeraStringValue(argString(args, 1))],
          ['intValue', new VeraIntValue(argInt(args, 2))],
          ['prefix', new VeraStringValue(argString(args, 3))],
          ['suffix', new VeraStringValue(argString(args, 4))],
          ['minimumDigits', new VeraIntValue(argInt(args, 5))],
          ['value', new VeraStringValue(argString(args, 6))],
          ['icon', new VeraStringValue(argString(args, 7))],
        ])
      case 'IntField':
        return viewNode('intfield', [
          ['style', new VeraStringValue(argString(args, 0))],
          ['label', new VeraStringValue(argString(args, 1))],
          ['intValue', new VeraIntValue(argInt(args, 2))],
          ['minimum', new VeraIntValue(argInt(args, 3))],
          ['maximum', new VeraIntValue(argInt(args, 4))],
          ['action', new VeraStringValue(argString(args, 5))],
        ])
      case 'TimeField':
        return viewNode('timefield', [
          ['style', new VeraStringValue(argString(args, 0))],
          ['label', new VeraStringValue(argString(args, 1))],
          ['intValue', new VeraIntValue(argInt(args, 2))],
          ['action', new VeraStringValue(argString(args, 3))],
        ])
      case 'IntListItem':
        return viewNode('intlistitem', [
          ['style', new VeraStringValue(argString(args, 0))],
          ['text', new VeraStringValue(argString(args, 1))],
          ['label', new VeraStringValue(argString(args, 2))],
          ['intValue', new VeraIntValue(argInt(args, 3))],
          ['prefix', new VeraStringValue(argString(args, 4))],
          ['suffix', new VeraStringValue(argString(args, 5))],
          ['minimumDigits', new VeraIntValue(argInt(args, 6))],
          ['action', new VeraStringValue(argString(args, 7))],
          ['eventValue', new VeraIntValue(argInt(args, 8))],
          ['enabled', new VeraBooleanValue(argBool(args, 9))],
          ['icon', new VeraStringValue(argString(args, 10))],
        ])
      case 'ActionBar':
        return containerNode('actionbar', args)
      case 'Timeline':
        return viewNode('timeline', [
          ['style', new VeraStringValue(argString(args, 0))],
          ['text', new VeraStringValue(argString(args, 1))],
          ['children', argArray(args, 2)],
        ])
      case 'TimelineItem':
        return viewNode('timelineitem', [
          ['style', new VeraStringValue(argString(args, 0))],
          ['text', new VeraStringValue(argString(args, 1))],
          ['label', new VeraStringValue(argString(args, 2))],
          ['value', new VeraStringValue(argString(args, 3))],
          ['action', new VeraStringValue(argString(args, 4))],
          ['eventValue', new VeraIntValue(argInt(args, 5))],
          ['enabled', new VeraBooleanValue(argBool(args, 6))],
          ['icon', new VeraStringValue(argString(args, 7))],
        ])
      case 'KeyValueGroup':
        return viewNode('kvgroup', [
          ['style', new VeraStringValue(argString(args, 0))],
          ['columns', new VeraIntValue(argInt(args, 1))],
          ['children', argArray(args, 2)],
        ])
      case 'KeyValueItem':
        return viewNode('kvitem', [
          ['style', new VeraStringValue(argString(args, 0))],
          ['label', new VeraStringValue(argString(args, 1))],
          ['text', new VeraStringValue(argString(args, 2))],
          ['value', new VeraStringValue(argString(args, 3))],
        ])
      case 'Icon':
        return viewNode('icon', [
          ['style', new VeraStringValue(argString(args, 0))],
          ['icon', new VeraStringValue(argString(args, 1))],
        ])
      case 'IconButton':
        return viewNode('iconbutton', [
          ['style', new VeraStringValue(argString(args, 0))],
          ['icon', new VeraStringValue(argString(args, 1))],
          ['label', new VeraStringValue(argString(args, 2))],
          ['action', new VeraStringValue(argString(args, 3))],
          ['value', new VeraIntValue(argInt(args, 4))],
          ['enabled', new VeraBooleanValue(argBool(args, 5))],
        ])
      case 'Badge':
        return viewNode('badge', [
          ['style', new VeraStringValue(argString(args, 0))],
          ['text', new VeraStringValue(argString(args, 1))],
          ['icon', new VeraStringValue(argString(args, 2))],
        ])
      case 'When':
        if (asBool(args[0])) { return args[1] }
        return viewNode('spacer', [['style', new VeraStringValue('none')]])
      case 'intToString':
        return new VeraStringValue(asInt(args[0]).toString())
      case 'numberToString': {
        if (!(args[0] instanceof VeraNumberValue)) { throw new RuntimeTrap('R0020', 'expected number argument') }
        return new VeraStringValue((args[0] as VeraNumberValue).value.toString())
      }
      case 'booleanToString':
        return new VeraStringValue(asBool(args[0]) ? 'true' : 'false')
      default:
        throw new RuntimeTrap('R0015', `unknown std/ui function: ${name}`)
    }
  }

  /**
   * Records an intent request and hands the program back a request id.
   *
   * The program never names a platform parameter: it writes the record this
   * intent's catalogue row declares, and the names and values in it are
   * translated on the way out, in VeraIntents. An empty string is a field the
   * program chose not to send -- the language has no optional record fields, so
   * that is how an optional parameter is spelled.
   */
  private queueIntent(name: string, args: RuntimeValue[]): RuntimeValue {
    if (name === 'call') { return this.queueRawIntent(args) }
    let spec = intentByName(name)
    if (spec === null) {
      throw new RuntimeTrap('R0015', `unknown std/intent function: ${name}`)
    }
    if (!this.effectsAllowed) {
      throw new RuntimeTrap('R0026',
        `intent.${name} may only be called from a handler, not from view`)
    }
    if (!(args[0] instanceof VeraObjectValue)) {
      throw new RuntimeTrap('R0020', 'expected a parameter record')
    }
    let record = args[0] as VeraObjectValue
    let values = new Map<string, string>()
    for (let p of spec!.params) {
      let field = record.fields.get(p.name)
      if (field === undefined) { continue }
      let value = field as RuntimeValue
      if (value instanceof VeraStringValue) {
        values.set(p.name, (value as VeraStringValue).value)
      } else if (value instanceof VeraIntValue) {
        values.set(p.name, (value as VeraIntValue).value.toString())
      }
    }
    let id = this.nextEffectId
    this.nextEffectId = id + 1
    this.pendingEffects.push(new HostEffect(id, 'intent', name, spec!, values, asString(args[1])))
    return new VeraIntValue(id)
  }

  /**
   * An intent the catalogue never heard of: the program names the target and
   * writes the platform's own parameters.
   *
   * Nothing is translated on the way out, because there is nothing to translate
   * it against. The payload is passed on as the program wrote it, and what
   * comes back is whatever the target said. The person confirms the call before
   * it runs -- that check lives in the renderer, where a dialog can be drawn
   * that the program cannot touch.
   */
  private queueRawIntent(args: RuntimeValue[]): RuntimeValue {
    if (!this.effectsAllowed) {
      throw new RuntimeTrap('R0026',
        'intent.call may only be called from a handler, not from view')
    }
    let target = asString(args[0]).trim()
    if (target.split('/').length !== 4) {
      throw new RuntimeTrap('R0027',
        'intent.call target must be "bundle/module/ability/IntentName"; got "' + target + '"')
    }
    let mode = asString(args[2])
    if (mode !== 'foreground' && mode !== 'background') {
      throw new RuntimeTrap('R0027',
        'intent.call mode must be "foreground" or "background"; got "' + mode + '"')
    }
    // Name, value, name, value. Built here rather than trusted as JSON,
    // because a program has no way to escape a string and would eventually
    // write a payload that does not parse -- which is exactly what the first
    // program to use this did.
    let pairs = asArray(args[1]).elements
    if (pairs.length % 2 !== 0) {
      throw new RuntimeTrap('R0027',
        'intent.call parameters are name and value in pairs; got ' + pairs.length.toString() + ' items')
    }
    let values = new Map<string, string>()
    let order: string[] = []
    for (let i = 0; i + 1 < pairs.length; i = i + 2) {
      let key = asString(pairs[i]).trim()
      if (key.length === 0) { continue }
      values.set(key, asString(pairs[i + 1]))
      order.push(key)
    }
    let id = this.nextEffectId
    this.nextEffectId = id + 1
    let effect = new HostEffect(id, 'intent', 'call', null, values, asString(args[3]))
    effect.rawTarget = target
    effect.rawParams = order.join(' ')
    effect.rawMode = mode
    this.pendingEffects.push(effect)
    return new VeraIntValue(id)
  }

  /**
   * The same shape as queueIntent, for the calendar. The record is read by the
   * field names the catalogue declares, so the program never has to know what
   * Calendar Kit calls anything either.
   */
  private queueCalendar(name: string, args: RuntimeValue[]): RuntimeValue {
    let fn = calendarFnByName(name)
    if (fn === null) {
      throw new RuntimeTrap('R0015', `unknown std/calendar function: ${name}`)
    }
    if (!this.effectsAllowed) {
      throw new RuntimeTrap('R0026',
        `calendar.${name} may only be called from a handler, not from view`)
    }
    if (!(args[0] instanceof VeraObjectValue)) {
      throw new RuntimeTrap('R0020', 'expected a parameter record')
    }
    let record = args[0] as VeraObjectValue
    let values = new Map<string, string>()
    for (let p of fn!.params) {
      let field = record.fields.get(p.name)
      if (field === undefined) { continue }
      let value = field as RuntimeValue
      if (value instanceof VeraStringValue) {
        values.set(p.name, (value as VeraStringValue).value)
      } else if (value instanceof VeraIntValue) {
        values.set(p.name, (value as VeraIntValue).value.toString())
      }
    }
    let id = this.nextEffectId
    this.nextEffectId = id + 1
    this.pendingEffects.push(new HostEffect(id, 'calendar', name, null, values, asString(args[1])))
    return new VeraIntValue(id)
  }
}

let nextNodeId: number = 0

export function decodeVeraUi(value: RuntimeValue): VeraUiNode[] {
  nextNodeId = 0
  if (value instanceof VeraObjectValue) {
    return [decodeNode(value as VeraObjectValue, 0)]
  }
  return []
}

function decodeNode(obj: VeraObjectValue, depth: number): VeraUiNode {
  if (depth > 8) { throw new RuntimeTrap('R0021', 'view tree too deep (max 8)') }
  let node = new VeraUiNode()
  node.id = nextNodeId
  nextNodeId += 1

  // Walk the fields the node actually carries, rather than asking after each of
  // the two dozen a node might carry.
  //
  // This used to be one obj.fields.get() per possible field, so a ui.Text -- a
  // kind, a style and a string -- paid for twenty lookups to find its three,
  // and every node in every tree paid the same flat toll. Decode is a measured
  // phase, and the toll grew every time the vocabulary did. Reading what is
  // there instead makes the cost proportional to the node rather than to the
  // catalogue, which is why the typed numeric fields above could be added at
  // all.
  //
  // Iteration order is insertion order, which is the order the case in
  // UiHostEnvironment.invoke wrote the fields in. Exactly one pair depends on
  // that: ListItem writes 'value' -- its trailing text -- before 'eventValue',
  // its tap payload, and both can land in eventValue. The later write wins, as
  // it did when these were two statements in a fixed order.
  for (let entry of obj.fields.entries()) {
    let key: string = entry[0]
    let v: RuntimeValue = entry[1]
    switch (key) {
      case 'type':
        if (v instanceof VeraStringValue) { node.kind = (v as VeraStringValue).value }
        break
      case 'style':
        if (v instanceof VeraStringValue) { node.style = (v as VeraStringValue).value }
        break
      case 'text':
        if (v instanceof VeraStringValue) { node.text = (v as VeraStringValue).value }
        break
      case 'src':
        if (v instanceof VeraStringValue) { node.source = (v as VeraStringValue).value }
        break
      case 'alt':
        if (v instanceof VeraStringValue) { node.alt = (v as VeraStringValue).value }
        break
      case 'action':
        if (v instanceof VeraStringValue) { node.action = (v as VeraStringValue).value }
        break
      case 'label':
        if (v instanceof VeraStringValue) { node.label = (v as VeraStringValue).value }
        break
      case 'tickerId':
        if (v instanceof VeraStringValue) { node.tickerId = (v as VeraStringValue).value }
        break
      case 'commands':
        if (v instanceof VeraStringValue) { node.commands = (v as VeraStringValue).value }
        break
      case 'prefix':
        if (v instanceof VeraStringValue) { node.prefix = (v as VeraStringValue).value }
        break
      case 'icon':
        if (v instanceof VeraStringValue) { node.icon = (v as VeraStringValue).value }
        break
      case 'suffix':
        if (v instanceof VeraStringValue) { node.suffix = (v as VeraStringValue).value }
        break
      // 'value' carries the text of a field, the position of a slider or
      // select, and the trailing text of a list row, so it arrives as either a
      // string or an int and means something different in each.
      case 'value':
        if (v instanceof VeraIntValue) { node.eventValue = (v as VeraIntValue).value }
        else if (v instanceof VeraStringValue) { node.value = (v as VeraStringValue).value }
        break
      case 'eventValue':
        if (v instanceof VeraIntValue) { node.eventValue = (v as VeraIntValue).value }
        break
      case 'intValue':
        if (v instanceof VeraIntValue) { node.intValue = (v as VeraIntValue).value }
        break
      case 'minimumDigits':
        if (v instanceof VeraIntValue) { node.minimumDigits = (v as VeraIntValue).value }
        break
      case 'spinPeriodMs':
        if (v instanceof VeraIntValue) { node.spinPeriodMs = (v as VeraIntValue).value }
        break
      case 'columns':
        if (v instanceof VeraIntValue) { node.columns = (v as VeraIntValue).value }
        break
      case 'minimum':
        if (v instanceof VeraIntValue) { node.minimum = (v as VeraIntValue).value }
        break
      case 'maximum':
        if (v instanceof VeraIntValue) { node.maximum = (v as VeraIntValue).value }
        break
      case 'checked':
        if (v instanceof VeraBooleanValue) { node.checked = (v as VeraBooleanValue).value }
        break
      case 'enabled':
        if (v instanceof VeraBooleanValue) { node.enabled = (v as VeraBooleanValue).value }
        break
      case 'options':
        if (v instanceof VeraArrayValue) {
          let opts: string[] = []
          for (let o of (v as VeraArrayValue).elements) {
            if (o instanceof VeraStringValue) { opts.push((o as VeraStringValue).value) }
          }
          node.options = opts
        }
        break
      case 'children':
        if (v instanceof VeraArrayValue) {
          for (let child of (v as VeraArrayValue).elements) {
            if (child instanceof VeraObjectValue) {
              node.children.push(decodeNode(child as VeraObjectValue, depth + 1))
            }
          }
        }
        break
      default:
        break
    }
  }
  return node
}
