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
import { CALENDAR_EVENT_PARAMS } from './VeraCalendarCatalog'

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
    ['style', new VeraStringValue(asString(args[0]))],
    ['children', asArray(args[1])],
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
  /** The intent's row; null for any other kind. */
  spec: IntentSpec | null
  values: Map<string, string>
  resultHandler: string
  constructor(id: number, kind: string, spec: IntentSpec | null,
      values: Map<string, string>, resultHandler: string) {
    this.id = id; this.kind = kind; this.spec = spec
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
          ['style', new VeraStringValue(asString(args[0]))],
          ['text', new VeraStringValue(asString(args[1]))],
        ])
      case 'Spacer':
        return viewNode('spacer', [
          ['style', new VeraStringValue(asString(args[0]))],
        ])
      case 'Image':
        return viewNode('image', [
          ['style', new VeraStringValue(asString(args[0]))],
          ['src', new VeraStringValue(asString(args[1]))],
          ['alt', new VeraStringValue(asString(args[2]))],
        ])
      case 'Path':
        return viewNode('path', [
          ['style', new VeraStringValue(asString(args[0]))],
          ['commands', new VeraStringValue(asString(args[1]))],
          ['spinPeriodMs', new VeraIntValue(asInt(args[2]))],
        ])
      case 'TextField':
        return viewNode('field', [
          ['style', new VeraStringValue(asString(args[0]))],
          ['label', new VeraStringValue(asString(args[1]))],
          ['value', new VeraStringValue(asString(args[2]))],
          ['action', new VeraStringValue(asString(args[3]))],
        ])
      case 'Toggle':
      case 'Checkbox':
        return viewNode(name === 'Toggle' ? 'toggle' : 'checkbox', [
          ['style', new VeraStringValue(asString(args[0]))],
          ['label', new VeraStringValue(asString(args[1]))],
          ['checked', new VeraBooleanValue(asBool(args[2]))],
          ['action', new VeraStringValue(asString(args[3]))],
        ])
      case 'Slider':
        return viewNode('slider', [
          ['style', new VeraStringValue(asString(args[0]))],
          ['label', new VeraStringValue(asString(args[1]))],
          ['value', new VeraIntValue(asInt(args[2]))],
          ['minimum', new VeraIntValue(asInt(args[3]))],
          ['maximum', new VeraIntValue(asInt(args[4]))],
          ['action', new VeraStringValue(asString(args[5]))],
        ])
      case 'Select':
        return viewNode('select', [
          ['style', new VeraStringValue(asString(args[0]))],
          ['label', new VeraStringValue(asString(args[1]))],
          ['options', asArray(args[2])],
          ['value', new VeraIntValue(asInt(args[3]))],
          ['action', new VeraStringValue(asString(args[4]))],
        ])
      case 'Grid':
        return viewNode('grid', [
          ['style', new VeraStringValue(asString(args[0]))],
          ['columns', new VeraIntValue(asInt(args[1]))],
          ['children', asArray(args[2])],
        ])
      case 'ListItem':
        return viewNode('listitem', [
          ['style', new VeraStringValue(asString(args[0]))],
          ['text', new VeraStringValue(asString(args[1]))],
          ['label', new VeraStringValue(asString(args[2]))],
          ['value', new VeraStringValue(asString(args[3]))],
          ['action', new VeraStringValue(asString(args[4]))],
          ['eventValue', new VeraIntValue(asInt(args[5]))],
          ['enabled', new VeraBooleanValue(asBool(args[6]))],
        ])
      case 'Ticker':
        return viewNode('ticker', [
          ['style', new VeraStringValue(asString(args[0]))],
          ['tickerId', new VeraStringValue(asString(args[1]))],
          ['minimum', new VeraIntValue(asInt(args[2]))],
          ['checked', new VeraBooleanValue(asBool(args[3]))],
          ['action', new VeraStringValue(asString(args[4]))],
        ])
      case 'Divider':
        return viewNode('divider', [
          ['style', new VeraStringValue(asString(args[0]))],
        ])
      case 'Progress':
        return viewNode('progress', [
          ['style', new VeraStringValue(asString(args[0]))],
          ['label', new VeraStringValue(asString(args[1]))],
          ['value', new VeraIntValue(asInt(args[2]))],
          ['maximum', new VeraIntValue(asInt(args[3]))],
        ])
      case 'Button':
        return viewNode('button', [
          ['style', new VeraStringValue(asString(args[0]))],
          ['text', new VeraStringValue(asString(args[1]))],
          ['action', new VeraStringValue(asString(args[2]))],
          ['value', new VeraIntValue(asInt(args[3]))],
          ['enabled', new VeraBooleanValue(asBool(args[4]))],
        ])
      case 'Cell':
        return viewNode('cell', [
          ['style', new VeraStringValue(asString(args[0]))],
          ['text', new VeraStringValue(asString(args[1]))],
          ['action', new VeraStringValue(asString(args[2]))],
          ['value', new VeraIntValue(asInt(args[3]))],
          ['enabled', new VeraBooleanValue(asBool(args[4]))],
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
    this.pendingEffects.push(new HostEffect(id, 'intent', spec!, values, asString(args[1])))
    return new VeraIntValue(id)
  }

  /**
   * The same shape as queueIntent, for the calendar. The record is read by the
   * field names the catalogue declares, so the program never has to know what
   * Calendar Kit calls anything either.
   */
  private queueCalendar(name: string, args: RuntimeValue[]): RuntimeValue {
    if (name !== 'addEvent') {
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
    for (let p of CALENDAR_EVENT_PARAMS) {
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
    this.pendingEffects.push(new HostEffect(id, 'calendar', null, values, asString(args[1])))
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
  let typeVal = obj.fields.get('type')
  if (typeVal != undefined && typeVal instanceof VeraStringValue) {
    node.kind = (typeVal as VeraStringValue).value
  }
  let styleVal = obj.fields.get('style')
  if (styleVal != undefined && styleVal instanceof VeraStringValue) {
    node.style = (styleVal as VeraStringValue).value
  }
  let textVal = obj.fields.get('text')
  if (textVal != undefined && textVal instanceof VeraStringValue) {
    node.text = (textVal as VeraStringValue).value
  }
  let srcVal = obj.fields.get('src')
  if (srcVal != undefined && srcVal instanceof VeraStringValue) {
    node.source = (srcVal as VeraStringValue).value
  }
  let altVal = obj.fields.get('alt')
  if (altVal != undefined && altVal instanceof VeraStringValue) {
    node.alt = (altVal as VeraStringValue).value
  }
  let actionVal = obj.fields.get('action')
  if (actionVal != undefined && actionVal instanceof VeraStringValue) {
    node.action = (actionVal as VeraStringValue).value
  }
  let valueVal = obj.fields.get('value')
  if (valueVal != undefined && valueVal instanceof VeraIntValue) {
    node.eventValue = (valueVal as VeraIntValue).value
  }
  let commandsVal = obj.fields.get('commands')
  if (commandsVal != undefined && commandsVal instanceof VeraStringValue) {
    node.commands = (commandsVal as VeraStringValue).value
  }
  let spinVal = obj.fields.get('spinPeriodMs')
  if (spinVal != undefined && spinVal instanceof VeraIntValue) {
    node.spinPeriodMs = (spinVal as VeraIntValue).value
  }
  let columnsVal = obj.fields.get('columns')
  if (columnsVal != undefined && columnsVal instanceof VeraIntValue) {
    node.columns = (columnsVal as VeraIntValue).value
  }
  // ListItem names its tap payload explicitly; Button and Cell call the same
  // thing 'value', which a ListItem uses for its trailing text instead.
  let eventValField = obj.fields.get('eventValue')
  if (eventValField != undefined && eventValField instanceof VeraIntValue) {
    node.eventValue = (eventValField as VeraIntValue).value
  }
  let tickerIdVal = obj.fields.get('tickerId')
  if (tickerIdVal != undefined && tickerIdVal instanceof VeraStringValue) {
    node.tickerId = (tickerIdVal as VeraStringValue).value
  }
  let labelVal = obj.fields.get('label')
  if (labelVal != undefined && labelVal instanceof VeraStringValue) {
    node.label = (labelVal as VeraStringValue).value
  }
  // 'value' carries the text of a field and the position of a slider or select,
  // so it arrives as either a string or an int.
  let valueField = obj.fields.get('value')
  if (valueField != undefined && valueField instanceof VeraStringValue) {
    node.value = (valueField as VeraStringValue).value
  }
  let checkedVal = obj.fields.get('checked')
  if (checkedVal != undefined && checkedVal instanceof VeraBooleanValue) {
    node.checked = (checkedVal as VeraBooleanValue).value
  }
  let minVal = obj.fields.get('minimum')
  if (minVal != undefined && minVal instanceof VeraIntValue) {
    node.minimum = (minVal as VeraIntValue).value
  }
  let maxVal = obj.fields.get('maximum')
  if (maxVal != undefined && maxVal instanceof VeraIntValue) {
    node.maximum = (maxVal as VeraIntValue).value
  }
  let optionsVal = obj.fields.get('options')
  if (optionsVal != undefined && optionsVal instanceof VeraArrayValue) {
    let opts: string[] = []
    for (let o of (optionsVal as VeraArrayValue).elements) {
      if (o instanceof VeraStringValue) { opts.push((o as VeraStringValue).value) }
    }
    node.options = opts
  }
  let enabledVal = obj.fields.get('enabled')
  if (enabledVal != undefined && enabledVal instanceof VeraBooleanValue) {
    node.enabled = (enabledVal as VeraBooleanValue).value
  }
  let childrenVal = obj.fields.get('children')
  if (childrenVal != undefined && childrenVal instanceof VeraArrayValue) {
    let arr = childrenVal as VeraArrayValue
    for (let child of arr.elements) {
      if (child instanceof VeraObjectValue) {
        node.children.push(decodeNode(child as VeraObjectValue, depth + 1))
      }
    }
  }
  return node
}
