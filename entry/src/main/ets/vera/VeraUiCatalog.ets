/**
 * The one description of the std/ui vocabulary.
 *
 * It used to live in four places that nothing cross-checked: the compiler's
 * module interface, the host decoder, the renderer's style ternaries, and the
 * prose catalogue in vera-skill.txt. Adding one component meant four edits, and
 * style names were typed as bare strings, so a misspelt style was never caught
 * anywhere -- it just silently hit the renderer's default branch.
 *
 * This module is pure data. It carries prop *kinds* as strings rather than
 * compiler types, so it does not import the compiler and there is no cycle.
 */

export class PropSpec {
  name: string
  /** 'string' | 'int' | 'boolean' | 'view' | 'view[]' */
  kind: string
  /** Key into STYLE_SETS when this prop is a style name; empty otherwise. */
  styleSet: string
  constructor(name: string, kind: string, styleSet: string = '') {
    this.name = name; this.kind = kind; this.styleSet = styleSet
  }
}

export class ComponentSpec {
  /** Name in the language: ui.<name> */
  name: string
  /** Node kind the decoder and renderer use. */
  nodeKind: string
  props: PropSpec[]
  summary: string
  /**
   * What this component hands its handler: '' for none, or 'string' / 'int' /
   * 'boolean'. Until now the only payload in the whole system was an int chosen
   * by the program itself, so nothing a person typed or toggled could reach it.
   */
  payloadKind: string
  constructor(name: string, nodeKind: string, props: PropSpec[], summary: string,
      payloadKind: string = '') {
    this.name = name; this.nodeKind = nodeKind; this.props = props; this.summary = summary
    this.payloadKind = payloadKind
  }
}

function style(set: string): PropSpec { return new PropSpec('style', 'string', set) }

export const STYLE_SETS: Map<string, string[]> = new Map<string, string[]>([
  ['column', ['default', 'compact', 'spacious', 'center', 'surface', 'accent']],
  ['row', ['default', 'compact', 'spacious', 'center', 'split', 'surface', 'accent']],
  ['card', ['surface', 'accent', 'success', 'warning', 'danger']],
  ['text', ['title', 'heading', 'body', 'caption', 'metric', 'muted', 'success', 'warning', 'danger']],
  ['button', ['primary', 'secondary', 'success', 'danger']],
  ['cell', ['default', 'accent', 'success', 'danger']],
  ['spacer', ['none', 'small', 'default', 'large']],
  ['path', ['default', 'accent', 'success', 'warning', 'danger', 'muted', 'light']],
  ['image', ['default']],
  ['field', ['default', 'multiline']],
  ['toggle', ['default']],
  ['checkbox', ['default']],
  ['slider', ['default']],
  ['select', ['default']],
  ['divider', ['default']],
  ['progress', ['default', 'accent', 'success', 'warning', 'danger']],
  ['ticker', ['default']],
  ['grid', ['default', 'compact', 'spacious']],
  ['canvas', ['default', 'small', 'large']],
  ['listitem', ['default', 'accent', 'success', 'warning', 'danger']],
])

export const CATALOG: ComponentSpec[] = [
  new ComponentSpec('Column', 'column',
    [style('column'), new PropSpec('children', 'view[]')], 'vertical stack'),
  new ComponentSpec('Row', 'row',
    [style('row'), new PropSpec('children', 'view[]')], 'horizontal stack'),
  new ComponentSpec('Card', 'card',
    [style('card'), new PropSpec('children', 'view[]')], 'framed group'),
  new ComponentSpec('Scroll', 'scroll',
    [style('column'), new PropSpec('children', 'view[]')], 'scrolling group'),
  new ComponentSpec('Text', 'text',
    [style('text'), new PropSpec('text', 'string')], 'a line of text'),
  new ComponentSpec('Spacer', 'spacer',
    [style('spacer')], 'vertical gap'),
  new ComponentSpec('Image', 'image',
    [style('image'), new PropSpec('src', 'string'), new PropSpec('alt', 'string')], 'https image'),
  new ComponentSpec('Path', 'path',
    [style('path'), new PropSpec('commands', 'string'), new PropSpec('spinPeriodMs', 'int')],
    'vector shape; spinPeriodMs > 0 rotates it'),
  new ComponentSpec('Button', 'button',
    [style('button'), new PropSpec('text', 'string'), new PropSpec('action', 'string'),
      new PropSpec('value', 'int'), new PropSpec('enabled', 'boolean')], 'tappable button'),
  new ComponentSpec('Cell', 'cell',
    [style('cell'), new PropSpec('text', 'string'), new PropSpec('action', 'string'),
      new PropSpec('value', 'int'), new PropSpec('enabled', 'boolean')], 'tappable grid cell'),

  // Everything below hands the handler a value the person chose, so the handler
  // takes that type instead of an int.
  new ComponentSpec('TextField', 'field',
    [style('field'), new PropSpec('label', 'string'), new PropSpec('value', 'string'),
      new PropSpec('action', 'string')],
    'text the user types; the handler takes (state, value: string)', 'string'),
  new ComponentSpec('Toggle', 'toggle',
    [style('toggle'), new PropSpec('label', 'string'), new PropSpec('checked', 'boolean'),
      new PropSpec('action', 'string')],
    'on/off switch; the handler takes (state, value: boolean)', 'boolean'),
  new ComponentSpec('Checkbox', 'checkbox',
    [style('checkbox'), new PropSpec('label', 'string'), new PropSpec('checked', 'boolean'),
      new PropSpec('action', 'string')],
    'tick box; the handler takes (state, value: boolean)', 'boolean'),
  new ComponentSpec('Slider', 'slider',
    [style('slider'), new PropSpec('label', 'string'), new PropSpec('value', 'int'),
      new PropSpec('minimum', 'int'), new PropSpec('maximum', 'int'),
      new PropSpec('action', 'string')],
    'pick a number in a range; the handler takes (state, value: int)', 'int'),
  new ComponentSpec('Canvas', 'canvas',
    [style('canvas'), new PropSpec('children', 'view[]')],
    'one drawing: the ui.Path children share a single 0..100 field and overlap'),
  new ComponentSpec('Grid', 'grid',
    [style('grid'), new PropSpec('columns', 'int'), new PropSpec('children', 'view[]')],
    'lays its children out in N equal columns, wrapping onto new rows'),
  new ComponentSpec('ListItem', 'listitem',
    [style('listitem'), new PropSpec('text', 'string'), new PropSpec('label', 'string'),
      new PropSpec('value', 'string'), new PropSpec('action', 'string'),
      new PropSpec('eventValue', 'int'), new PropSpec('enabled', 'boolean')],
    'one row of a list: title, subtitle, trailing text, tappable'),
  new ComponentSpec('Ticker', 'ticker',
    [style('ticker'), new PropSpec('id', 'string'), new PropSpec('intervalMs', 'int'),
      new PropSpec('running', 'boolean'), new PropSpec('action', 'string')],
    'draws nothing; calls the handler every intervalMs with the elapsed ms', 'int'),
  new ComponentSpec('Divider', 'divider', [style('divider')], 'a horizontal rule'),
  new ComponentSpec('Progress', 'progress',
    [style('progress'), new PropSpec('label', 'string'), new PropSpec('value', 'int'),
      new PropSpec('maximum', 'int')], 'a progress bar'),
  new ComponentSpec('Select', 'select',
    [style('select'), new PropSpec('label', 'string'), new PropSpec('options', 'string[]'),
      new PropSpec('selected', 'int'), new PropSpec('action', 'string')],
    'choose one option; the handler takes (state, index: int)', 'int'),
]

/** '' when the component has no handler payload. */
export function payloadKindFor(nodeKind: string): string {
  for (let c of CATALOG) { if (c.nodeKind === nodeKind) { return c.payloadKind } }
  return ''
}

/** Style names the renderer understands for a node kind; empty if unconstrained. */
export function stylesFor(nodeKind: string): string[] {
  let s = STYLE_SETS.get(nodeKind)
  return s !== undefined ? s : []
}

/** Node kinds the decoder can produce, for the renderer's coverage check. */
export function catalogKinds(): string[] {
  let kinds: string[] = []
  for (let c of CATALOG) { kinds.push(c.nodeKind) }
  return kinds
}

/**
 * The catalogue section of the model's prompt, generated so it cannot drift from
 * what the compiler accepts and the renderer draws.
 */
export function describeCatalogForPrompt(): string {
  let lines: string[] = []
  lines.push('UI constructors (all return ui.View):')
  for (let c of CATALOG) {
    let args: string[] = []
    for (let p of c.props) { args.push(p.name) }
    lines.push('  ui.' + c.name + '(' + args.join(', ') + ')  -- ' + c.summary)
  }
  lines.push('  ui.When(condition, child)  -- child when true, nothing when false')
  lines.push('  ui.intToString(n), ui.numberToString(n), ui.booleanToString(b)')
  lines.push('')
  lines.push('Allowed styles:')
  for (let c of CATALOG) {
    let set = stylesFor(c.nodeKind)
    if (set.length > 1) { lines.push('  ' + c.name + ': ' + set.join(' ')) }
  }
  return lines.join('\n')
}
