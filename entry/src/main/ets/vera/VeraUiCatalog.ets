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

import { iconNames } from './VeraIcons'

export class PropSpec {
  name: string
  /** 'string' | 'int' | 'boolean' | 'view' | 'view[]' | 'string[]' | 'int[]' | 'icon' */
  kind: string
  /** Key into STYLE_SETS when this prop is a style name; empty otherwise. */
  styleSet: string
  /**
   * May be left off the end of the call.
   *
   * Only trailing properties may be optional, and they exist so the vocabulary
   * can grow without breaking anything. The host already reads a missing
   * argument as its default, so that saved bytecode keeps running; this is the
   * same tolerance at the other end, so that a *model* which learnt the old
   * signature is not failed for it either. Getting this wrong cost a whole
   * generation attempt the first time an icon was added.
   */
  optional: boolean
  constructor(name: string, kind: string, styleSet: string = '', optional: boolean = false) {
    this.name = name; this.kind = kind; this.styleSet = styleSet; this.optional = optional
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
  /**
   * When to reach for this component and when not to, in prose.
   *
   * The summary says what a component *is*, which is enough for a primitive. A
   * composite also needs to say what it is *for*, because the failure it exists
   * to prevent is a model that can already build the same thing out of Column
   * and Card and therefore does. Empty for the primitives; see
   * describeCatalogForPrompt.
   */
  guidance: string
  constructor(name: string, nodeKind: string, props: PropSpec[], summary: string,
      payloadKind: string = '', guidance: string = '') {
    this.name = name; this.nodeKind = nodeKind; this.props = props; this.summary = summary
    this.payloadKind = payloadKind; this.guidance = guidance
  }
}

function style(set: string): PropSpec { return new PropSpec('style', 'string', set) }

/**
 * A property naming one of the icons in VeraIcons.
 *
 * Its own kind rather than a plain string so the compiler can hold it to the
 * closed set, the way it holds a style name. An icon that does not exist would
 * otherwise draw nothing and look like the renderer had failed.
 */
function icon(name: string): PropSpec { return new PropSpec(name, 'icon', '', true) }

export const STYLE_SETS: Map<string, string[]> = new Map<string, string[]>([
  ['column', ['default', 'compact', 'spacious', 'center', 'end', 'surface', 'accent']],
  ['row', ['default', 'compact', 'spacious', 'center', 'end', 'split', 'joined', 'surface', 'accent']],
  ['card', ['surface', 'accent', 'success', 'warning', 'danger']],
  ['text', ['display', 'title', 'heading', 'body', 'caption', 'eyebrow', 'metric', 'muted', 'success', 'warning', 'danger']],
  ['button', ['primary', 'secondary', 'success', 'danger']],
  ['cell', ['default', 'accent', 'success', 'danger']],
  ['spacer', ['none', 'small', 'default', 'large']],
  ['path', ['default', 'accent', 'success', 'warning', 'danger', 'muted', 'light']],
  ['image', ['default']],
  ['field', ['default', 'multiline']],
  ['toggle', ['default']],
  ['checkbox', ['default']],
  ['slider', ['default', 'accent', 'success', 'warning', 'danger']],
  ['select', ['default']],
  ['divider', ['default']],
  ['progress', ['default', 'accent', 'success', 'warning', 'danger']],
  ['ticker', ['default']],
  ['grid', ['default', 'compact', 'spacious']],
  ['canvas', ['default', 'small', 'large']],
  ['listitem', ['default', 'accent', 'success', 'warning', 'danger']],

  // The compositional layer. A preset is one word that settles the palette, the
  // radii, the rhythm and the type scale together -- see VeraTheme.
  ['apptheme', ['clean', 'soft', 'expressive', 'editorial', 'technical', 'playful']],
  ['header', ['default', 'center']],
  ['hero', ['plain', 'accent']],
  ['adaptivecolumns', ['default', 'compact', 'spacious']],
  ['section', ['content', 'hero', 'summary', 'supporting', 'warning']],
  ['sectionheader', ['default', 'accent', 'muted']],
  ['listgroup', ['default', 'compact', 'comfortable']],
  ['banner', ['default', 'accent', 'success', 'warning', 'danger']],
  ['emptystate', ['default', 'muted']],
  ['stat', ['default', 'accent', 'success', 'warning', 'danger']],
  ['metricgroup', ['default', 'compact', 'spacious']],

  // The typed numeric layer: the number travels as a number.
  ['inttext', ['display', 'title', 'heading', 'body', 'caption', 'metric', 'muted', 'success', 'warning', 'danger']],
  ['intstat', ['default', 'accent', 'success', 'warning', 'danger']],
  ['intfield', ['default']],
  ['timefield', ['default']],
  ['intlistitem', ['default', 'accent', 'success', 'warning', 'danger']],
  ['actionbar', ['default', 'end', 'center', 'spread']],
  ['kvgroup', ['default', 'compact', 'spacious']],
  ['kvitem', ['default', 'accent', 'success', 'warning', 'danger']],
  ['icon', ['default', 'muted', 'accent', 'success', 'warning', 'danger']],
  ['iconbutton', ['primary', 'secondary', 'success', 'danger', 'quiet']],
  ['badge', ['default', 'accent', 'success', 'warning', 'danger']],
  ['timeline', ['default', 'compact', 'comfortable']],
  ['timelineitem', ['default', 'accent', 'success', 'warning', 'danger']],
  ['table', ['default']],
  ['tablerow', ['default', 'accent', 'success', 'warning', 'danger']],

  // Loading and transient-status feedback. No tone variation yet -- a
  // one-entry list here means describeCatalogForPrompt leaves the "styles:"
  // line out, the same way ui.Divider and ui.Scroll already do.
  ['skeleton', ['default']],
  ['spinner', ['default', 'accent']],
  ['snackbar', ['default', 'success', 'warning', 'danger']],
  ['sparkline', ['default', 'accent', 'success', 'warning', 'danger']],
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
    'vector shape; spinPeriodMs > 0 rotates it', '',
    'Draws real vector graphics -- circles, gears, arrows, icons, chart shapes -- so use it whenever the user asks to draw something, instead of substituting a number and buttons. commands is an SVG path string using M L C Q A Z with absolute coordinates only. The drawing box is 0..100 in both axes; centre artwork on 50,50. There is no math at runtime: compute every coordinate yourself and write plain number literals. spinPeriodMs rotates the shape (0 is static, 2000 is one turn every 2 seconds) and needs no handler, state field or timer. A circle is "M50 10 A40 40 0 1 0 50 90 A40 40 0 1 0 50 10 Z".'),
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
      new PropSpec('action', 'string'),
      new PropSpec('keyboardType', 'string', '', true),
      new PropSpec('required', 'boolean', '', true),
      new PropSpec('requiredMessage', 'string', '', true),
      new PropSpec('minLength', 'int', '', true),
      new PropSpec('minLengthMessage', 'string', '', true),
      new PropSpec('maxLength', 'int', '', true),
      new PropSpec('maxLengthMessage', 'string', '', true),
      new PropSpec('pattern', 'string', '', true),
      new PropSpec('patternMessage', 'string', '', true),
      new PropSpec('email', 'boolean', '', true),
      new PropSpec('emailMessage', 'string', '', true)],
    'text the user types; the handler takes (state, value: string)', 'string',
    'keyboardType is "", "number", "phone" or "email" and only changes which keys the ' +
    'on-screen keyboard offers -- it never rejects a character. required, minLength, ' +
    'maxLength, pattern (a regex) and email each turn on one check, shown under the ' +
    'field in its own words via the matching ...Message prop (a sensible default is ' +
    'used if left blank); none of them stop what reaches the handler, since VERA has ' +
    'no way to refuse a value once typed.'),
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
    'one drawing: the ui.Path children share a single 0..100 field and overlap', '',
    'For a drawing made of several shapes -- a face, an animal, a scene, a chart. Each ui.Path child keeps the position and size you gave it and may have its own colour; give them back to front (the head before the ears, the face before the eyes). Outside a Canvas every ui.Path is centred alone in its own band, which is right only for a single icon.'),
  new ComponentSpec('Grid', 'grid',
    [style('grid'), new PropSpec('columns', 'int'), new PropSpec('children', 'view[]')],
    'lays its children out in N equal columns, wrapping onto new rows', '',
    'For anything laid out in equal columns -- a board, a calendar, a keypad -- rather than building rows by hand.'),
  new ComponentSpec('ListItem', 'listitem',
    [style('listitem'), new PropSpec('text', 'string'), new PropSpec('label', 'string'),
      new PropSpec('value', 'string'), new PropSpec('action', 'string'),
      new PropSpec('eventValue', 'int'), new PropSpec('enabled', 'boolean'),
      icon('icon')],
    'one row of a list: title, subtitle, trailing text, leading icon, tappable'),
  new ComponentSpec('Ticker', 'ticker',
    [style('ticker'), new PropSpec('id', 'string'), new PropSpec('intervalMs', 'int'),
      new PropSpec('running', 'boolean'), new PropSpec('action', 'string')],
    'draws nothing; calls the handler every intervalMs with the elapsed ms', 'int',
    'Keeps a displayed time or a countdown moving -- never add a refresh button instead. The handler is onTick(state, elapsedMs: int), called every interval; use it to advance a stopwatch, a game or a clock. Accumulate the elapsed value it gives you: do not subtract two clock readings, because time.nowSeconds() only changes once a second. Match intervalMs to the precision shown: 1000 for whole seconds, 50 for hundredths. Example: ui.Ticker("default", "clock", 1000, true, "onTick").'),
  new ComponentSpec('Divider', 'divider', [style('divider')], 'a horizontal rule'),
  new ComponentSpec('BackHandler', 'backhandler',
    [new PropSpec('action', 'string')],
    'draws nothing; calls the handler, with 0, on the system back gesture', 'int',
    'VERA has no separate navigation stack -- "screens" are just a state.screen-style field and ui.When choosing which View to draw. Add one ui.BackHandler wherever a screen other than the first is showing, so the hardware/system back gesture does something sensible (return to the previous screen, close a dialog) instead of the OS default, which exits the app. Leave it out of the first screen so back still exits normally. Only one should be live at a time; if several are drawn in the same frame the last one decoded wins.'),
  new ComponentSpec('Progress', 'progress',
    [style('progress'), new PropSpec('label', 'string'), new PropSpec('value', 'int'),
      new PropSpec('maximum', 'int')], 'a progress bar'),
  new ComponentSpec('Select', 'select',
    [style('select'), new PropSpec('label', 'string'), new PropSpec('options', 'string[]'),
      new PropSpec('selected', 'int'), new PropSpec('action', 'string')],
    'choose one option; the handler takes (state, index: int)', 'int'),

  // The compositional layer.
  //
  // Everything above is a primitive: it says what to draw. These say what a
  // part of a screen *is*, and the renderer decides how that looks under the
  // chosen theme. They exist because a model handed only Column, Card and Text
  // rebuilds the same header, the same stat row and the same list out of them
  // every time, slightly differently and slightly worse.
  //
  // None of them adds a field to VeraUiNode. Each reuses text/label/value/
  // columns/children, which is why decode is untouched and its measured cost
  // does not move. The mapping is written out in each summary so the prompt
  // carries it too.
  new ComponentSpec('AppTheme', 'apptheme',
    [style('apptheme'), new PropSpec('primary', 'string'), new PropSpec('children', 'view[]')],
    'the whole app in one look; primary is a "#rrggbb" seed or "" for the preset\'s own',
    '',
    'Wrap everything view returns in exactly one of these. The preset is the app\'s character, so choose it for the app you were asked for: clean for restrained and neutral, soft for calm and friendly, expressive for bold and atmospheric, editorial for content that leads, technical for dense precise numbers, playful for energetic. Do not pick clean just because an example uses it.'),
  new ComponentSpec('Hero', 'hero',
    [style('hero'), new PropSpec('eyebrow', 'string'), new PropSpec('title', 'string'),
      new PropSpec('supporting', 'string'), new PropSpec('children', 'view[]')],
    'a focal area with optional eyebrow, title, supporting text, and related content',
    '',
    'Use plain for an open focal area or accent for a tinted surface. Empty strings omit text. Children can hold a result, visual, or action. Use only when the content needs this emphasis. Do not add a redundant Header above Hero.'),
  new ComponentSpec('AdaptiveColumns', 'adaptivecolumns',
    [style('adaptivecolumns'), new PropSpec('minimumWidth', 'int'), new PropSpec('children', 'view[]')],
    'ordered content in one or two top-aligned columns, based on available width',
    '',
    'Use for independent related groups. The renderer measures available width and includes the theme gap. minimumWidth defaults to 240 when nonpositive and otherwise has a minimum of 160. Narrow containers keep one column.'),
  new ComponentSpec('Header', 'header',
    [style('header'), new PropSpec('title', 'string'), new PropSpec('eyebrow', 'string'),
      new PropSpec('supporting', 'string'), icon('icon')],
    'the app\'s own title block: eyebrow above, title, supporting line below',
    '',
    'Use when the title should lead the screen. A result, visual, or collection can lead instead. Leave eyebrow or supporting as "" when there is nothing to say.'),
  new ComponentSpec('Section', 'section',
    [style('section'), new PropSpec('title', 'string'), new PropSpec('subtitle', 'string'),
      new PropSpec('children', 'view[]')],
    'one part of the screen, with a role: hero summary content supporting warning',
    '',
    'Give each part of the screen its own Section and let the role say what the part is for. The spacing between sections comes from the theme, so do not add ui.Spacer between them. Prefer this over a Card when all you want is a titled group.'),
  new ComponentSpec('SectionHeader', 'sectionheader',
    [style('sectionheader'), new PropSpec('title', 'string'), new PropSpec('subtitle', 'string'),
      new PropSpec('count', 'string')],
    'a heading inside a section: title, subtitle, and a count on the right',
    '',
    'Use for hierarchy inside a Section without starting another surface. count is for "3 of 8" and the like; pass "" when there is no count.'),
  new ComponentSpec('ListGroup', 'listgroup',
    [style('listgroup'), new PropSpec('title', 'string'), new PropSpec('children', 'view[]')],
    'one bounded surface holding related ui.ListItem rows, separated for you',
    '',
    'Two or more related rows belong in one of these, not in a Card each. The frame, the separators and the row rhythm are the renderer\'s job. Rows are ui.ListItem or ui.IntListItem; a ui.SectionHeader may open the group and a ui.ActionBar may follow the row it belongs to.'),
  new ComponentSpec('InsetBanner', 'banner',
    [style('banner'), new PropSpec('title', 'string'), new PropSpec('message', 'string'),
      new PropSpec('actionText', 'string'), new PropSpec('action', 'string'),
      icon('icon')],
    'a standing status or guidance note in a tone, with one optional action',
    '',
    'For something that stays true while the person works -- a permission that was refused, a warning, the result of the last call. Pass actionText "" and action "" when there is nothing to tap; the handler, if you name one, is called with 0.'),
  new ComponentSpec('EmptyState', 'emptystate',
    [style('emptystate'), new PropSpec('title', 'string'), new PropSpec('message', 'string'),
      new PropSpec('actionText', 'string'), new PropSpec('action', 'string'),
      icon('icon')],
    'what to show where a collection is empty: title, message, one way forward',
    '',
    'State starts empty, so this is the first thing the person sees. Put one behind ui.When(list.length() === 0, ...) for every collection the app keeps. Pass actionText "" and action "" when there is nothing to tap; the handler, if you name one, is called with 0.'),
  new ComponentSpec('Stat', 'stat',
    [style('stat'), new PropSpec('label', 'string'), new PropSpec('value', 'string'),
      new PropSpec('supporting', 'string'), icon('icon')],
    'one number told properly: label above, value large, supporting line below',
    '',
    'For a summary figure. It draws no surface of its own, so put two to four inside a ui.MetricGroup rather than one inside a Card.'),
  new ComponentSpec('MetricGroup', 'metricgroup',
    [style('metricgroup'), new PropSpec('columns', 'int'), new PropSpec('children', 'view[]')],
    'two to four ui.Stat or ui.IntStat children across one surface, in equal columns',
    '',
    'The summary strip at the top of a screen. Only ui.Stat or ui.IntStat children. columns is a maximum: a narrow screen uses fewer.'),

  // The typed numeric layer.
  //
  // The language has no number formatting and no way back from a string to an
  // int, so until now every number on screen was a string the program had
  // already built with ui.intToString, and anything wider than one digit needed
  // a padding function written by hand. These take the number and let the
  // renderer format it, which also means a number the person types can come
  // back as an int instead of unparseable text.
  new ComponentSpec('IntText', 'inttext',
    [style('inttext'), new PropSpec('value', 'int'), new PropSpec('prefix', 'string'),
      new PropSpec('suffix', 'string'), new PropSpec('minimumDigits', 'int')],
    'a whole number as text: prefix, the number padded to minimumDigits, suffix',
    '',
    'Use instead of ui.Text with ui.intToString. minimumDigits 2 writes 7 as "07", so a clock is ui.IntText("body", h, "", ":", 2) beside ui.IntText("body", m, "", "", 2) and needs no pad function. Use prefix and suffix for units and currency rather than gluing strings together.'),
  new ComponentSpec('ClockText', 'clocktext',
    [style('inttext'), new PropSpec('minutes', 'int'), new PropSpec('prefix', 'string'),
      new PropSpec('suffix', 'string')],
    'a time of day from minutes since midnight, written as HH:MM',
    '',
    'The only way to show a time. Never build one from two ui.IntText and never write a padding function for it: 9:05 in the morning is ui.ClockText("body", 545, "", ""). Minutes since midnight is what time.hourOfDay() * 60 + time.minuteOfHour() gives and what ui.TimeField hands back, so the three fit together.'),
  new ComponentSpec('IntStat', 'intstat',
    [style('intstat'), new PropSpec('label', 'string'), new PropSpec('value', 'int'),
      new PropSpec('prefix', 'string'), new PropSpec('suffix', 'string'),
      new PropSpec('minimumDigits', 'int'), new PropSpec('supporting', 'string'),
      icon('icon')],
    'ui.Stat for a number the program holds as an int',
    '',
    'Prefer this to ui.Stat whenever the figure is a number rather than text. Same place: inside a ui.MetricGroup.'),
  new ComponentSpec('IntField', 'intfield',
    [style('intfield'), new PropSpec('label', 'string'), new PropSpec('value', 'int'),
      new PropSpec('minimum', 'int'), new PropSpec('maximum', 'int'),
      new PropSpec('action', 'string')],
    'a number the user sets with - and +; the handler takes (state, value: int)', 'int',
    'The only way to get a number from the person. A ui.TextField hands you a string and there is no way to turn a string into an int, so a typed quantity has to come through here. minimum and maximum bound it.'),
  new ComponentSpec('TimeField', 'timefield',
    [style('timefield'), new PropSpec('label', 'string'), new PropSpec('value', 'int'),
      new PropSpec('action', 'string')],
    'a time of day, as minutes since midnight; the handler takes (state, value: int)', 'int',
    'For a time the person chooses. The value is minutes since midnight, which is the same shape time.hourOfDay() * 60 + time.minuteOfHour() produces, so it compares with the clock directly.'),
  new ComponentSpec('IntListItem', 'intlistitem',
    [style('intlistitem'), new PropSpec('title', 'string'), new PropSpec('subtitle', 'string'),
      new PropSpec('value', 'int'), new PropSpec('prefix', 'string'),
      new PropSpec('suffix', 'string'), new PropSpec('minimumDigits', 'int'),
      new PropSpec('action', 'string'), new PropSpec('eventValue', 'int'),
      new PropSpec('enabled', 'boolean'), icon('icon')],
    'a ui.ListItem whose trailing value is a number, formatted for you',
    '',
    'For a row that ends in a quantity, an amount or a time. It goes in a ui.ListGroup exactly like ui.ListItem. Note it carries two numbers: value is what is shown, eventValue is what the tap hands the handler.'),
  new ComponentSpec('ActionBar', 'actionbar',
    [style('actionbar'), new PropSpec('children', 'view[]')],
    'the row of buttons for a screen or a section',
    '',
    'Gather the actions into one of these instead of leaving buttons loose in a Column. It takes ui.Button, ui.IconButton and ui.Badge. One action is primary and the rest are not.'),
  // A timeline is not a list.
  //
  // A list says these things belong together; a timeline says they happen one
  // after another, and the rail between the markers is the part that says it.
  // An itinerary, a log, a treatment course and a delivery all want this and
  // were all coming out as ui.ListGroup, which shows the stops but not that
  // there is an hour of travelling between two of them.
  new ComponentSpec('Timeline', 'timeline',
    [style('timeline'), new PropSpec('title', 'string'), new PropSpec('children', 'view[]')],
    'events in the order they happen, joined by a rail',
    '',
    'For anything that runs in time -- an itinerary, a course of treatment, a history, a delivery. A list says these things belong together; a timeline says they follow one another. Prefer it to ui.ListGroup whenever the order is chronological rather than merely grouped. Children are ui.TimelineItem; a ui.ActionBar may follow the entry it belongs to.'),
  new ComponentSpec('TimelineItem', 'timelineitem',
    [style('timelineitem'), new PropSpec('title', 'string'), new PropSpec('subtitle', 'string'),
      new PropSpec('trailing', 'string'), new PropSpec('action', 'string'),
      new PropSpec('eventValue', 'int'), new PropSpec('enabled', 'boolean'),
      icon('icon')],
    'one moment on a timeline; same fields as ui.ListItem, plus its marker',
    '',
    'Put the time in trailing, so the times line up down the right edge. The icon becomes the marker on the rail -- "pin" for a place, "check" for something done, "clock" for something still ahead; with no icon the marker is a plain dot.'),

  new ComponentSpec('KeyValueGroup', 'kvgroup',
    [style('kvgroup'), new PropSpec('columns', 'int'), new PropSpec('children', 'view[]')],
    'ui.KeyValueItem children in equal columns, for facts rather than figures',
    '',
    'For the details of a thing -- where, how long, which platform. Use this rather than a ui.MetricGroup when the values are words, and rather than a ListGroup when they are short enough to sit two to a row.'),
  // Icons.
  //
  // Added late, and the reason they matter more than the count suggests is that
  // most of them are not drawn by ui.Icon at all: they are the `icon` property
  // that every composite below now carries. A screen of actions reading
  // "Navigate" "Add to calendar" "Mark reached" three times over is a wall of
  // text, and no amount of spacing fixes it -- what fixes it is two of the
  // three becoming a glyph.
  new ComponentSpec('Icon', 'icon',
    [style('icon'), icon('name')], 'one icon on its own',
    '',
    'For an icon that is not part of something else. Most icons should instead be the icon property of a ListItem, Banner, EmptyState, Header or Stat, which places them properly.'),
  new ComponentSpec('IconButton', 'iconbutton',
    [style('iconbutton'), icon('icon'), new PropSpec('label', 'string'),
      new PropSpec('action', 'string'), new PropSpec('value', 'int'),
      new PropSpec('enabled', 'boolean')],
    'a button that is only an icon; label is what it does, for accessibility',
    '',
    'Use for a secondary action beside a primary one, so a row of three actions does not become three blocks of text. The label is never drawn but must still say what the button does. Keep the one action a person is most likely to want as a full ui.Button.'),
  new ComponentSpec('Badge', 'badge',
    [style('badge'), new PropSpec('text', 'string'), icon('icon')],
    'a short status, drawn as a chip rather than a line of text',
    '',
    'For the state of the thing next to it -- "Reached", "Overdue", "3 left". Pass icon "" for no icon. Do not use it for ordinary text.'),

  new ComponentSpec('KeyValueItem', 'kvitem',
    [style('kvitem'), new PropSpec('label', 'string'), new PropSpec('value', 'string'),
      new PropSpec('supporting', 'string')],
    'one labelled fact: label above, value below',
    '',
    'Only inside a ui.KeyValueGroup.'),

  // A real grid of rows and columns, which neither ui.Grid (equal tappable
  // cells for a keypad or board, one int payload each) nor ui.KeyValueGroup
  // (facts, two per row, no header) is shaped for.
  new ComponentSpec('Table', 'table',
    [style('table'), new PropSpec('headers', 'string[]'), new PropSpec('columns', 'int'),
      new PropSpec('children', 'view[]')],
    'rows and columns of text, with an optional header row',
    '',
    'For data that genuinely has columns -- a list of orders with date, item and amount; a schedule with time and place. headers names each column and may be an empty array for no header row; columns must match both headers\' length (when given) and every ui.TableRow\'s own cells length. Children are ui.TableRow. Prefer ui.ListGroup when each row is really just a title with a trailing value -- a table is for three or more columns of data read down as well as across.'),
  new ComponentSpec('TableRow', 'tablerow',
    [style('tablerow'), new PropSpec('cells', 'string[]')],
    'one row of a ui.Table: one string per column, in order',
    '',
    'Only inside a ui.Table, and always with as many cells as the table has columns. Give it a tone -- accent, success, warning, danger -- to call out one row, a total line or a problem entry, the same way a ui.ListItem can.'),

  // Loading and transient-status feedback. Added because the catalogue had no
  // way to say "this hasn't loaded yet" or "that just happened" -- a screen
  // either showed its real content or showed nothing at all while waiting.
  new ComponentSpec('Skeleton', 'skeleton',
    [style('skeleton'), new PropSpec('width', 'int'), new PropSpec('height', 'int'),
      new PropSpec('rounded', 'boolean', '', true)],
    'a placeholder box the size of the content that has not arrived yet',
    '',
    'Put one where real content will appear once it is ready, instead of leaving that space blank or showing a zero. width and height are the box in points; rounded softens the corners for anything that will end up looking like a chip or an avatar.'),
  new ComponentSpec('Spinner', 'spinner',
    [style('spinner'), new PropSpec('label', 'string', '', true)],
    'a small spinning indicator that something is in progress',
    '',
    'For a wait with no useful progress number to show -- reach for ui.Progress instead when there is one. label is shown beside it and may be "".'),
  new ComponentSpec('Snackbar', 'snackbar',
    [style('snackbar'), new PropSpec('message', 'string'), new PropSpec('actionText', 'string'),
      new PropSpec('action', 'string')],
    'a one-line status strip the program raised itself, with one optional action',
    '',
    'For something that just happened and does not need to stay on screen -- "Saved", "Undo", a result the person did not have to ask for. Unlike ui.InsetBanner this is not meant to persist: put it behind ui.When(state.showX, ...) and have the handler that triggered it set state.showX true, and whatever dismisses it (a timer, the action button, the next tap) set it back to false. Pass actionText "" and action "" for no action; the handler, if named, is called with 0.'),

  // The one int[] prop in the language -- a chart's raw values travel as
  // numbers, not as a string the program built with ui.intToString and the
  // renderer tried to parse back. The renderer does the normalising and the
  // drawing, the same division of labour ui.IntText already has for a single
  // number.
  new ComponentSpec('Sparkline', 'sparkline',
    [style('sparkline'), new PropSpec('series', 'int[]'), new PropSpec('maximum', 'int'),
      new PropSpec('label', 'string', '', true), new PropSpec('bars', 'boolean', '', true)],
    'a line or bar chart of up to a few dozen values',
    '',
    'For a trend -- a week of steps, a balance over time, a reading taken repeatedly -- leave bars false for a connected line. For a handful of categories compared side by side -- spending per category, votes per option -- pass bars true for separate bars instead. series is the values in order; maximum bounds the vertical scale (pass the largest value you expect, not the largest value in series, so the chart does not jump every time a new point arrives). There is no x-axis label and no legend: say what the numbers are in label or in a ui.Text above it.'),
]

/**
 * Which children a container will accept, where that can be seen in the source.
 *
 * The rule these encode is a design rule, not a type rule: a ListGroup holding
 * Cards is a well-typed program that draws the exact thing ListGroup exists to
 * replace. The compiler checks it because a compile error is fed back to the
 * model and fixed on the next attempt, whereas anything the renderer notices is
 * seen only by whoever is watching the screen.
 *
 * An empty list means "anything". Enforced by checkComposition in
 * VeraCompiler, and only where the children are written out literally -- a list
 * built by a loop cannot be read here and passes, the same limitation the style
 * check has.
 */
export class ChildRule {
  /** Component name, as written in the language. */
  parent: string
  /** Names allowed as direct children; empty means no restriction. */
  allowed: string[]
  /** Names refused as descendants at any depth below this one. */
  refusedInside: string[]
  constructor(parent: string, allowed: string[], refusedInside: string[] = []) {
    this.parent = parent; this.allowed = allowed; this.refusedInside = refusedInside
  }
}

export const CHILD_RULES: ChildRule[] = [
  // A rule that forbids something the model was told to write is not a rule,
  // it is a trap: the generation loop spends an attempt, the model is handed a
  // diagnostic for obeying its instructions, and the budget is a third gone
  // before any real work starts. Two of these were exactly that -- the prompt's
  // own worked example puts an IconButton in an ActionBar, and the renderer has
  // a branch for an ActionBar inside a ListGroup -- and both were rejected
  // here. Measured on device: the first attempt at the layover prompt failed on
  // E2107 and nothing else.
  //
  // So these forbid only what is actually wrong and would actually draw badly.
  new ChildRule('ListGroup', ['ListItem', 'IntListItem', 'SectionHeader', 'ActionBar', 'When'], []),
  new ChildRule('MetricGroup', ['Stat', 'IntStat', 'When'], []),
  new ChildRule('KeyValueGroup', ['KeyValueItem', 'When'], []),
  new ChildRule('Timeline', ['TimelineItem', 'ActionBar', 'When'], []),
  new ChildRule('Table', ['TableRow', 'When'], []),
  new ChildRule('ActionBar', ['Button', 'IconButton', 'Badge', 'When'], []),
  // A card inside a card is the nesting deal-studio calls out by name: two
  // frames, two paddings, and no more meaning than one.
  new ChildRule('Card', [], ['Card']),
  // One look per program.
  new ChildRule('AppTheme', [], ['AppTheme']),
]

/** "a, b or c" -- 'a or b or c' reads like a stutter in a compiler message. */
export function listWords(words: string[]): string {
  if (words.length < 2) { return words.join('') }
  let head: string[] = []
  for (let i = 0; i < words.length - 1; i++) { head.push(words[i]) }
  return head.join(', ') + ' or ' + words[words.length - 1]
}

/** The rule for a component name, or null when it has none. */
export function childRuleFor(name: string): ChildRule | null {
  for (let r of CHILD_RULES) { if (r.parent === name) { return r } }
  return null
}

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
 * Components the prompt always describes: the composition layer the skill's
 * rules are written in terms of, the basic stacks, and the number components.
 * Everything else is offered only when the request needs it -- see
 * VeraUiIndex.ets.
 */
export const CORE_COMPONENTS: string[] = [
  'Column', 'Row', 'Card', 'Text', 'Spacer', 'Button',
  'AppTheme', 'Hero', 'AdaptiveColumns', 'Header', 'Section', 'SectionHeader', 'ListGroup', 'ListItem',
  'IntListItem', 'ActionBar', 'IconButton', 'Badge', 'EmptyState', 'InsetBanner',
  'Stat', 'IntStat', 'MetricGroup', 'IntText', 'ClockText',
]

/** Components that are described only when selected. */
export function optionalComponents(): ComponentSpec[] {
  let out: ComponentSpec[] = []
  for (let c of CATALOG) {
    if (CORE_COMPONENTS.indexOf(c.name) < 0) { out.push(c) }
  }
  return out
}

/** Pairs that make no sense apart: each is useless, or uncompilable, without the other. */
const COMPANIONS: string[][] = [
  ['Canvas', 'Path'],
  ['Grid', 'Cell'],
  ['Timeline', 'TimelineItem'],
  ['KeyValueGroup', 'KeyValueItem'],
  ['Table', 'TableRow'],
]

/**
 * What the prompt should describe for a request: the core, whatever was picked,
 * and whatever those need to be written correctly -- a parent brings the
 * children it allows, and a companion brings the other half of its pair.
 */
export function selectUiComponents(picked: string[]): Set<string> {
  let out = new Set<string>()
  for (let n of CORE_COMPONENTS) { out.add(n) }
  for (let n of picked) { out.add(n) }
  let changed = true
  while (changed) {
    changed = false
    for (let r of CHILD_RULES) {
      if (!out.has(r.parent)) { continue }
      for (let child of r.allowed) {
        if (child !== 'When' && !out.has(child)) { out.add(child); changed = true }
      }
    }
    for (let pair of COMPANIONS) {
      if (out.has(pair[0]) !== out.has(pair[1])) {
        out.add(pair[0]); out.add(pair[1]); changed = true
      }
    }
  }
  return out
}

/** Component names written as ui.<Name> in a program, so a refinement keeps what it already uses. */
export function componentsUsedIn(source: string): string[] {
  let found: string[] = []
  for (let c of CATALOG) {
    if (source.indexOf('ui.' + c.name + '(') >= 0) { found.push(c.name) }
  }
  return found
}

/** The text a component is embedded as. */
export function componentEmbeddingText(c: ComponentSpec): string {
  return c.name + ' -- ' + c.summary + (c.guidance.length > 0 ? ' ' + c.guidance : '')
}

function signatureLine(c: ComponentSpec): string {
  let args: string[] = []
  // A trailing optional argument is written in brackets, because it may be
  // left off entirely.
  for (let p of c.props) { args.push(p.optional ? '[' + p.name + ']' : p.name) }
  return '  ui.' + c.name + '(' + args.join(', ') + ')  -- ' + c.summary
}

function hasIconProp(c: ComponentSpec): boolean {
  for (let p of c.props) { if (p.kind === 'icon') { return true } }
  return false
}

/**
 * Signatures, styles and guidance for named components, as the answer to
 * find_ui_component.
 */
export function describeComponents(names: string[]): string {
  let lines: string[] = []
  for (let c of CATALOG) {
    if (names.indexOf(c.name) < 0) { continue }
    lines.push(signatureLine(c))
    let set = stylesFor(c.nodeKind)
    if (set.length > 1) { lines.push('    styles: ' + set.join(' ')) }
    if (c.guidance.length > 0) { lines.push('    ' + c.guidance) }
  }
  return lines.join('\n')
}

/**
 * The catalogue section of the model's prompt, generated so it cannot drift from
 * what the compiler accepts and the renderer draws. With a selection it
 * describes only those components; without one, all of them.
 */
export function describeCatalogForPrompt(selected: Set<string> | null = null): string {
  let shown: ComponentSpec[] = []
  for (let c of CATALOG) {
    if (selected === null || selected.has(c.name)) { shown.push(c) }
  }
  let lines: string[] = []
  lines.push('UI constructors (all return ui.View):')
  for (let c of shown) { lines.push(signatureLine(c)) }
  lines.push('  ui.When(condition, child)  -- child when true, nothing when false')
  lines.push('  ui.intToString(n), ui.numberToString(n), ui.booleanToString(b)')
  lines.push('')
  lines.push('Allowed styles:')
  for (let c of shown) {
    let set = stylesFor(c.nodeKind)
    if (set.length > 1) { lines.push('  ' + c.name + ': ' + set.join(' ')) }
  }
  // The composite components, with the prose that says what each is for. A
  // signature alone does not stop a model rebuilding a header out of Column and
  // Text, because it could already do that and the signature does not say not
  // to.
  let guided: ComponentSpec[] = []
  for (let c of shown) { if (c.guidance.length > 0) { guided.push(c) } }
  if (guided.length > 0) {
    lines.push('')
    lines.push('When to use each of these:')
    for (let c of guided) {
      lines.push('  ui.' + c.name + ' -- ' + c.guidance)
    }
  }
  let wantsIcons = false
  for (let c of shown) { if (hasIconProp(c)) { wantsIcons = true } }
  if (wantsIcons) {
    lines.push('')
    lines.push('Icon names (the only ones that exist):')
    let names = iconNames()
    let row: string[] = []
    for (let n of names) {
      row.push(n)
      if (row.length === 8) { lines.push('  ' + row.join(' ')); row = [] }
    }
    if (row.length > 0) { lines.push('  ' + row.join(' ')) }
    lines.push('  Pass "" where a component takes an icon and you do not want one.')
  }

  let ruled: string[] = []
  for (let r of CHILD_RULES) {
    if (selected !== null && !selected.has(r.parent)) { continue }
    if (r.allowed.length > 0) {
      ruled.push('  ' + r.parent + ' takes only ' + listWords(r.allowed) + ' children.')
    }
    for (let bad of r.refusedInside) {
      ruled.push('  ' + r.parent + ' may not contain another ' + bad + '.')
    }
  }
  if (ruled.length > 0) {
    lines.push('')
    lines.push('Composition rules the compiler enforces:')
    for (let line of ruled) { lines.push(line) }
  }
  return lines.join('\n')
}
