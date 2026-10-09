import { iconNames } from "./VeraIcons";
export class PropSpec {
    name: string;
    kind: string;
    styleSet: string;
    optional: boolean;
    constructor(r182: string, s182: string, t182: string = '', u182: boolean = false) {
        this.name = r182;
        this.kind = s182;
        this.styleSet = t182;
        this.optional = u182;
    }
}
export class ComponentSpec {
    name: string;
    nodeKind: string;
    props: PropSpec[];
    summary: string;
    payloadKind: string;
    guidance: string;
    constructor(l182: string, m182: string, n182: PropSpec[], o182: string, p182: string = '', q182: string = '') {
        this.name = l182;
        this.nodeKind = m182;
        this.props = n182;
        this.summary = o182;
        this.payloadKind = p182;
        this.guidance = q182;
    }
}
function style(k182: string): PropSpec { return new PropSpec('style', 'string', k182); }
function icon(j182: string): PropSpec { return new PropSpec(j182, 'icon', '', true); }
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
    ['apptheme', ['clean', 'soft', 'expressive', 'editorial', 'technical', 'playful']],
    ['header', ['default', 'center']],
    ['section', ['content', 'hero', 'summary', 'supporting', 'warning']],
    ['sectionheader', ['default', 'accent', 'muted']],
    ['listgroup', ['default', 'compact', 'comfortable']],
    ['banner', ['default', 'accent', 'success', 'warning', 'danger']],
    ['emptystate', ['default', 'muted']],
    ['stat', ['default', 'accent', 'success', 'warning', 'danger']],
    ['metricgroup', ['default', 'compact', 'spacious']],
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
    ['skeleton', ['default']],
    ['spinner', ['default', 'accent']],
    ['snackbar', ['default', 'success', 'warning', 'danger']],
    ['sparkline', ['default', 'accent', 'success', 'warning', 'danger']],
]);
export const CATALOG: ComponentSpec[] = [
    new ComponentSpec('Column', 'column', [style('column'), new PropSpec('children', 'view[]')], 'vertical stack'),
    new ComponentSpec('Row', 'row', [style('row'), new PropSpec('children', 'view[]')], 'horizontal stack'),
    new ComponentSpec('Card', 'card', [style('card'), new PropSpec('children', 'view[]')], 'framed group'),
    new ComponentSpec('Scroll', 'scroll', [style('column'), new PropSpec('children', 'view[]')], 'scrolling group'),
    new ComponentSpec('Text', 'text', [style('text'), new PropSpec('text', 'string')], 'a line of text'),
    new ComponentSpec('Spacer', 'spacer', [style('spacer')], 'vertical gap'),
    new ComponentSpec('Image', 'image', [style('image'), new PropSpec('src', 'string'), new PropSpec('alt', 'string')], 'https image'),
    new ComponentSpec('Path', 'path', [style('path'), new PropSpec('commands', 'string'), new PropSpec('spinPeriodMs', 'int')], 'vector shape; spinPeriodMs > 0 rotates it', '', 'Draws real vector graphics -- circles, gears, arrows, icons, chart shapes -- so use it whenever the user asks to draw something, instead of substituting a number and buttons. commands is an SVG path string using M L C Q A Z with absolute coordinates only. The drawing box is 0..100 in both axes; centre artwork on 50,50. There is no math at runtime: compute every coordinate yourself and write plain number literals. spinPeriodMs rotates the shape (0 is static, 2000 is one turn every 2 seconds) and needs no handler, state field or timer. A circle is "M50 10 A40 40 0 1 0 50 90 A40 40 0 1 0 50 10 Z".'),
    new ComponentSpec('Button', 'button', [style('button'), new PropSpec('text', 'string'), new PropSpec('action', 'string'),
        new PropSpec('value', 'int'), new PropSpec('enabled', 'boolean')], 'tappable button'),
    new ComponentSpec('Cell', 'cell', [style('cell'), new PropSpec('text', 'string'), new PropSpec('action', 'string'),
        new PropSpec('value', 'int'), new PropSpec('enabled', 'boolean')], 'tappable grid cell'),
    new ComponentSpec('TextField', 'field', [style('field'), new PropSpec('label', 'string'), new PropSpec('value', 'string'),
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
        new PropSpec('emailMessage', 'string', '', true)], 'text the user types; the handler takes (state, value: string)', 'string', 'keyboardType is "", "number", "phone" or "email" and only changes which keys the ' +
        'on-screen keyboard offers -- it never rejects a character. required, minLength, ' +
        'maxLength, pattern (a regex) and email each turn on one check, shown under the ' +
        'field in its own words via the matching ...Message prop (a sensible default is ' +
        'used if left blank); none of them stop what reaches the handler, since VERA has ' +
        'no way to refuse a value once typed.'),
    new ComponentSpec('Toggle', 'toggle', [style('toggle'), new PropSpec('label', 'string'), new PropSpec('checked', 'boolean'),
        new PropSpec('action', 'string')], 'on/off switch; the handler takes (state, value: boolean)', 'boolean'),
    new ComponentSpec('Checkbox', 'checkbox', [style('checkbox'), new PropSpec('label', 'string'), new PropSpec('checked', 'boolean'),
        new PropSpec('action', 'string')], 'tick box; the handler takes (state, value: boolean)', 'boolean'),
    new ComponentSpec('Slider', 'slider', [style('slider'), new PropSpec('label', 'string'), new PropSpec('value', 'int'),
        new PropSpec('minimum', 'int'), new PropSpec('maximum', 'int'),
        new PropSpec('action', 'string')], 'pick a number in a range; the handler takes (state, value: int)', 'int'),
    new ComponentSpec('Canvas', 'canvas', [style('canvas'), new PropSpec('children', 'view[]')], 'one drawing: the ui.Path children share a single 0..100 field and overlap', '', 'For a drawing made of several shapes -- a face, an animal, a scene, a chart. Each ui.Path child keeps the position and size you gave it and may have its own colour; give them back to front (the head before the ears, the face before the eyes). Outside a Canvas every ui.Path is centred alone in its own band, which is right only for a single icon.'),
    new ComponentSpec('Grid', 'grid', [style('grid'), new PropSpec('columns', 'int'), new PropSpec('children', 'view[]')], 'lays its children out in N equal columns, wrapping onto new rows', '', 'For anything laid out in equal columns -- a board, a calendar, a keypad -- rather than building rows by hand.'),
    new ComponentSpec('ListItem', 'listitem', [style('listitem'), new PropSpec('text', 'string'), new PropSpec('label', 'string'),
        new PropSpec('value', 'string'), new PropSpec('action', 'string'),
        new PropSpec('eventValue', 'int'), new PropSpec('enabled', 'boolean'),
        icon('icon')], 'one row of a list: title, subtitle, trailing text, leading icon, tappable'),
    new ComponentSpec('Ticker', 'ticker', [style('ticker'), new PropSpec('id', 'string'), new PropSpec('intervalMs', 'int'),
        new PropSpec('running', 'boolean'), new PropSpec('action', 'string')], 'draws nothing; calls the handler every intervalMs with the elapsed ms', 'int', 'Keeps a displayed time or a countdown moving -- never add a refresh button instead. The handler is onTick(state, elapsedMs: int), called every interval; use it to advance a stopwatch, a game or a clock. Accumulate the elapsed value it gives you: do not subtract two clock readings, because time.nowSeconds() only changes once a second. Match intervalMs to the precision shown: 1000 for whole seconds, 50 for hundredths. Example: ui.Ticker("default", "clock", 1000, true, "onTick").'),
    new ComponentSpec('Divider', 'divider', [style('divider')], 'a horizontal rule'),
    new ComponentSpec('BackHandler', 'backhandler', [new PropSpec('action', 'string')], 'draws nothing; calls the handler, with 0, on the system back gesture', 'int', 'VERA has no separate navigation stack -- "screens" are just a state.screen-style field and ui.When choosing which View to draw. Add one ui.BackHandler wherever a screen other than the first is showing, so the hardware/system back gesture does something sensible (return to the previous screen, close a dialog) instead of the OS default, which exits the app. Leave it out of the first screen so back still exits normally. Only one should be live at a time; if several are drawn in the same frame the last one decoded wins.'),
    new ComponentSpec('Progress', 'progress', [style('progress'), new PropSpec('label', 'string'), new PropSpec('value', 'int'),
        new PropSpec('maximum', 'int')], 'a progress bar'),
    new ComponentSpec('Select', 'select', [style('select'), new PropSpec('label', 'string'), new PropSpec('options', 'string[]'),
        new PropSpec('selected', 'int'), new PropSpec('action', 'string')], 'choose one option; the handler takes (state, index: int)', 'int'),
    new ComponentSpec('AppTheme', 'apptheme', [style('apptheme'), new PropSpec('primary', 'string'), new PropSpec('children', 'view[]')], 'the whole app in one look; primary is a "#rrggbb" seed or "" for the preset\'s own', '', 'Wrap everything view returns in exactly one of these. The preset is the app\'s character, so choose it for the app you were asked for: clean for restrained and neutral, soft for calm and friendly, expressive for bold and atmospheric, editorial for content that leads, technical for dense precise numbers, playful for energetic. Do not pick clean just because an example uses it.'),
    new ComponentSpec('Header', 'header', [style('header'), new PropSpec('title', 'string'), new PropSpec('eyebrow', 'string'),
        new PropSpec('supporting', 'string'), icon('icon')], 'the app\'s own title block: eyebrow above, title, supporting line below', '', 'Open the screen with one of these instead of a bare ui.Text. Use it once. Leave eyebrow or supporting as "" when there is nothing to say.'),
    new ComponentSpec('Section', 'section', [style('section'), new PropSpec('title', 'string'), new PropSpec('subtitle', 'string'),
        new PropSpec('children', 'view[]')], 'one part of the screen, with a role: hero summary content supporting warning', '', 'Give each part of the screen its own Section and let the role say what the part is for. The spacing between sections comes from the theme, so do not add ui.Spacer between them. Prefer this over a Card when all you want is a titled group.'),
    new ComponentSpec('SectionHeader', 'sectionheader', [style('sectionheader'), new PropSpec('title', 'string'), new PropSpec('subtitle', 'string'),
        new PropSpec('count', 'string')], 'a heading inside a section: title, subtitle, and a count on the right', '', 'Use for hierarchy inside a Section without starting another surface. count is for "3 of 8" and the like; pass "" when there is no count.'),
    new ComponentSpec('ListGroup', 'listgroup', [style('listgroup'), new PropSpec('title', 'string'), new PropSpec('children', 'view[]')], 'one bounded surface holding related ui.ListItem rows, separated for you', '', 'Two or more related rows belong in one of these, not in a Card each. The frame, the separators and the row rhythm are the renderer\'s job. Rows are ui.ListItem or ui.IntListItem; a ui.SectionHeader may open the group and a ui.ActionBar may follow the row it belongs to.'),
    new ComponentSpec('InsetBanner', 'banner', [style('banner'), new PropSpec('title', 'string'), new PropSpec('message', 'string'),
        new PropSpec('actionText', 'string'), new PropSpec('action', 'string'),
        icon('icon')], 'a standing status or guidance note in a tone, with one optional action', '', 'For something that stays true while the person works -- a permission that was refused, a warning, the result of the last call. Pass actionText "" and action "" when there is nothing to tap; the handler, if you name one, is called with 0.'),
    new ComponentSpec('EmptyState', 'emptystate', [style('emptystate'), new PropSpec('title', 'string'), new PropSpec('message', 'string'),
        new PropSpec('actionText', 'string'), new PropSpec('action', 'string'),
        icon('icon')], 'what to show where a collection is empty: title, message, one way forward', '', 'State starts empty, so this is the first thing the person sees. Put one behind ui.When(list.length() === 0, ...) for every collection the app keeps. Pass actionText "" and action "" when there is nothing to tap; the handler, if you name one, is called with 0.'),
    new ComponentSpec('Stat', 'stat', [style('stat'), new PropSpec('label', 'string'), new PropSpec('value', 'string'),
        new PropSpec('supporting', 'string'), icon('icon')], 'one number told properly: label above, value large, supporting line below', '', 'For a summary figure. It draws no surface of its own, so put two to four inside a ui.MetricGroup rather than one inside a Card.'),
    new ComponentSpec('MetricGroup', 'metricgroup', [style('metricgroup'), new PropSpec('columns', 'int'), new PropSpec('children', 'view[]')], 'two to four ui.Stat or ui.IntStat children across one surface, in equal columns', '', 'The summary strip at the top of a screen. Only ui.Stat or ui.IntStat children. columns is a maximum: a narrow screen uses fewer.'),
    new ComponentSpec('IntText', 'inttext', [style('inttext'), new PropSpec('value', 'int'), new PropSpec('prefix', 'string'),
        new PropSpec('suffix', 'string'), new PropSpec('minimumDigits', 'int')], 'a whole number as text: prefix, the number padded to minimumDigits, suffix', '', 'Use instead of ui.Text with ui.intToString. minimumDigits 2 writes 7 as "07", so a clock is ui.IntText("body", h, "", ":", 2) beside ui.IntText("body", m, "", "", 2) and needs no pad function. Use prefix and suffix for units and currency rather than gluing strings together.'),
    new ComponentSpec('ClockText', 'clocktext', [style('inttext'), new PropSpec('minutes', 'int'), new PropSpec('prefix', 'string'),
        new PropSpec('suffix', 'string')], 'a time of day from minutes since midnight, written as HH:MM', '', 'The only way to show a time. Never build one from two ui.IntText and never write a padding function for it: 9:05 in the morning is ui.ClockText("body", 545, "", ""). Minutes since midnight is what time.hourOfDay() * 60 + time.minuteOfHour() gives and what ui.TimeField hands back, so the three fit together.'),
    new ComponentSpec('IntStat', 'intstat', [style('intstat'), new PropSpec('label', 'string'), new PropSpec('value', 'int'),
        new PropSpec('prefix', 'string'), new PropSpec('suffix', 'string'),
        new PropSpec('minimumDigits', 'int'), new PropSpec('supporting', 'string'),
        icon('icon')], 'ui.Stat for a number the program holds as an int', '', 'Prefer this to ui.Stat whenever the figure is a number rather than text. Same place: inside a ui.MetricGroup.'),
    new ComponentSpec('IntField', 'intfield', [style('intfield'), new PropSpec('label', 'string'), new PropSpec('value', 'int'),
        new PropSpec('minimum', 'int'), new PropSpec('maximum', 'int'),
        new PropSpec('action', 'string')], 'a number the user sets with - and +; the handler takes (state, value: int)', 'int', 'The only way to get a number from the person. A ui.TextField hands you a string and there is no way to turn a string into an int, so a typed quantity has to come through here. minimum and maximum bound it.'),
    new ComponentSpec('TimeField', 'timefield', [style('timefield'), new PropSpec('label', 'string'), new PropSpec('value', 'int'),
        new PropSpec('action', 'string')], 'a time of day, as minutes since midnight; the handler takes (state, value: int)', 'int', 'For a time the person chooses. The value is minutes since midnight, which is the same shape time.hourOfDay() * 60 + time.minuteOfHour() produces, so it compares with the clock directly.'),
    new ComponentSpec('IntListItem', 'intlistitem', [style('intlistitem'), new PropSpec('title', 'string'), new PropSpec('subtitle', 'string'),
        new PropSpec('value', 'int'), new PropSpec('prefix', 'string'),
        new PropSpec('suffix', 'string'), new PropSpec('minimumDigits', 'int'),
        new PropSpec('action', 'string'), new PropSpec('eventValue', 'int'),
        new PropSpec('enabled', 'boolean'), icon('icon')], 'a ui.ListItem whose trailing value is a number, formatted for you', '', 'For a row that ends in a quantity, an amount or a time. It goes in a ui.ListGroup exactly like ui.ListItem. Note it carries two numbers: value is what is shown, eventValue is what the tap hands the handler.'),
    new ComponentSpec('ActionBar', 'actionbar', [style('actionbar'), new PropSpec('children', 'view[]')], 'the row of buttons for a screen or a section', '', 'Gather the actions into one of these instead of leaving buttons loose in a Column. It takes ui.Button, ui.IconButton and ui.Badge. One action is primary and the rest are not.'),
    new ComponentSpec('Timeline', 'timeline', [style('timeline'), new PropSpec('title', 'string'), new PropSpec('children', 'view[]')], 'events in the order they happen, joined by a rail', '', 'For anything that runs in time -- an itinerary, a course of treatment, a history, a delivery. A list says these things belong together; a timeline says they follow one another. Prefer it to ui.ListGroup whenever the order is chronological rather than merely grouped. Children are ui.TimelineItem; a ui.ActionBar may follow the entry it belongs to.'),
    new ComponentSpec('TimelineItem', 'timelineitem', [style('timelineitem'), new PropSpec('title', 'string'), new PropSpec('subtitle', 'string'),
        new PropSpec('trailing', 'string'), new PropSpec('action', 'string'),
        new PropSpec('eventValue', 'int'), new PropSpec('enabled', 'boolean'),
        icon('icon')], 'one moment on a timeline; same fields as ui.ListItem, plus its marker', '', 'Put the time in trailing, so the times line up down the right edge. The icon becomes the marker on the rail -- "pin" for a place, "check" for something done, "clock" for something still ahead; with no icon the marker is a plain dot.'),
    new ComponentSpec('KeyValueGroup', 'kvgroup', [style('kvgroup'), new PropSpec('columns', 'int'), new PropSpec('children', 'view[]')], 'ui.KeyValueItem children in equal columns, for facts rather than figures', '', 'For the details of a thing -- where, how long, which platform. Use this rather than a ui.MetricGroup when the values are words, and rather than a ListGroup when they are short enough to sit two to a row.'),
    new ComponentSpec('Icon', 'icon', [style('icon'), icon('name')], 'one icon on its own', '', 'For an icon that is not part of something else. Most icons should instead be the icon property of a ListItem, Banner, EmptyState, Header or Stat, which places them properly.'),
    new ComponentSpec('IconButton', 'iconbutton', [style('iconbutton'), icon('icon'), new PropSpec('label', 'string'),
        new PropSpec('action', 'string'), new PropSpec('value', 'int'),
        new PropSpec('enabled', 'boolean')], 'a button that is only an icon; label is what it does, for accessibility', '', 'Use for a secondary action beside a primary one, so a row of three actions does not become three blocks of text. The label is never drawn but must still say what the button does. Keep the one action a person is most likely to want as a full ui.Button.'),
    new ComponentSpec('Badge', 'badge', [style('badge'), new PropSpec('text', 'string'), icon('icon')], 'a short status, drawn as a chip rather than a line of text', '', 'For the state of the thing next to it -- "Reached", "Overdue", "3 left". Pass icon "" for no icon. Do not use it for ordinary text.'),
    new ComponentSpec('KeyValueItem', 'kvitem', [style('kvitem'), new PropSpec('label', 'string'), new PropSpec('value', 'string'),
        new PropSpec('supporting', 'string')], 'one labelled fact: label above, value below', '', 'Only inside a ui.KeyValueGroup.'),
    new ComponentSpec('Table', 'table', [style('table'), new PropSpec('headers', 'string[]'), new PropSpec('columns', 'int'),
        new PropSpec('children', 'view[]')], 'rows and columns of text, with an optional header row', '', 'For data that genuinely has columns -- a list of orders with date, item and amount; a schedule with time and place. headers names each column and may be an empty array for no header row; columns must match both headers\' length (when given) and every ui.TableRow\'s own cells length. Children are ui.TableRow. Prefer ui.ListGroup when each row is really just a title with a trailing value -- a table is for three or more columns of data read down as well as across.'),
    new ComponentSpec('TableRow', 'tablerow', [style('tablerow'), new PropSpec('cells', 'string[]')], 'one row of a ui.Table: one string per column, in order', '', 'Only inside a ui.Table, and always with as many cells as the table has columns. Give it a tone -- accent, success, warning, danger -- to call out one row, a total line or a problem entry, the same way a ui.ListItem can.'),
    new ComponentSpec('Skeleton', 'skeleton', [style('skeleton'), new PropSpec('width', 'int'), new PropSpec('height', 'int'),
        new PropSpec('rounded', 'boolean', '', true)], 'a placeholder box the size of the content that has not arrived yet', '', 'Put one where real content will appear once it is ready, instead of leaving that space blank or showing a zero. width and height are the box in points; rounded softens the corners for anything that will end up looking like a chip or an avatar.'),
    new ComponentSpec('Spinner', 'spinner', [style('spinner'), new PropSpec('label', 'string', '', true)], 'a small spinning indicator that something is in progress', '', 'For a wait with no useful progress number to show -- reach for ui.Progress instead when there is one. label is shown beside it and may be "".'),
    new ComponentSpec('Snackbar', 'snackbar', [style('snackbar'), new PropSpec('message', 'string'), new PropSpec('actionText', 'string'),
        new PropSpec('action', 'string')], 'a one-line status strip the program raised itself, with one optional action', '', 'For something that just happened and does not need to stay on screen -- "Saved", "Undo", a result the person did not have to ask for. Unlike ui.InsetBanner this is not meant to persist: put it behind ui.When(state.showX, ...) and have the handler that triggered it set state.showX true, and whatever dismisses it (a timer, the action button, the next tap) set it back to false. Pass actionText "" and action "" for no action; the handler, if named, is called with 0.'),
    new ComponentSpec('Sparkline', 'sparkline', [style('sparkline'), new PropSpec('series', 'int[]'), new PropSpec('maximum', 'int'),
        new PropSpec('label', 'string', '', true), new PropSpec('bars', 'boolean', '', true)], 'a line or bar chart of up to a few dozen values', '', 'For a trend -- a week of steps, a balance over time, a reading taken repeatedly -- leave bars false for a connected line. For a handful of categories compared side by side -- spending per category, votes per option -- pass bars true for separate bars instead. series is the values in order; maximum bounds the vertical scale (pass the largest value you expect, not the largest value in series, so the chart does not jump every time a new point arrives). There is no x-axis label and no legend: say what the numbers are in label or in a ui.Text above it.'),
];
export class ChildRule {
    parent: string;
    allowed: string[];
    refusedInside: string[];
    constructor(g182: string, h182: string[], i182: string[] = []) {
        this.parent = g182;
        this.allowed = h182;
        this.refusedInside = i182;
    }
}
export const CHILD_RULES: ChildRule[] = [
    new ChildRule('ListGroup', ['ListItem', 'IntListItem', 'SectionHeader', 'ActionBar', 'When'], []),
    new ChildRule('MetricGroup', ['Stat', 'IntStat', 'When'], []),
    new ChildRule('KeyValueGroup', ['KeyValueItem', 'When'], []),
    new ChildRule('Timeline', ['TimelineItem', 'ActionBar', 'When'], []),
    new ChildRule('Table', ['TableRow', 'When'], []),
    new ChildRule('ActionBar', ['Button', 'IconButton', 'Badge', 'When'], []),
    new ChildRule('Card', [], ['Card']),
    new ChildRule('AppTheme', [], ['AppTheme']),
];
export function listWords(d182: string[]): string {
    if (d182.length < 2) {
        return d182.join('');
    }
    let e182: string[] = [];
    for (let f182 = 0; f182 < d182.length - 1; f182++) {
        e182.push(d182[f182]);
    }
    return e182.join(', ') + ' or ' + d182[d182.length - 1];
}
export function childRuleFor(b182: string): ChildRule | null {
    for (let c182 of CHILD_RULES) {
        if (c182.parent === b182) {
            return c182;
        }
    }
    return null;
}
export function payloadKindFor(z181: string): string {
    for (let a182 of CATALOG) {
        if (a182.nodeKind === z181) {
            return a182.payloadKind;
        }
    }
    return '';
}
export function stylesFor(x181: string): string[] {
    let y181 = STYLE_SETS.get(x181);
    return y181 !== undefined ? y181 : [];
}
export function catalogKinds(): string[] {
    let v181: string[] = [];
    for (let w181 of CATALOG) {
        v181.push(w181.nodeKind);
    }
    return v181;
}
export const CORE_COMPONENTS: string[] = [
    'Column', 'Row', 'Card', 'Text', 'Spacer', 'Button',
    'AppTheme', 'Header', 'Section', 'SectionHeader', 'ListGroup', 'ListItem',
    'IntListItem', 'ActionBar', 'IconButton', 'Badge', 'EmptyState', 'InsetBanner',
    'Stat', 'IntStat', 'MetricGroup', 'IntText', 'ClockText',
];
export function optionalComponents(): ComponentSpec[] {
    let t181: ComponentSpec[] = [];
    for (let u181 of CATALOG) {
        if (CORE_COMPONENTS.indexOf(u181.name) < 0) {
            t181.push(u181);
        }
    }
    return t181;
}
const COMPANIONS: string[][] = [
    ['Canvas', 'Path'],
    ['Grid', 'Cell'],
    ['Timeline', 'TimelineItem'],
    ['KeyValueGroup', 'KeyValueItem'],
    ['Table', 'TableRow'],
];
export function selectUiComponents(l181: string[]): Set<string> {
    let m181 = new Set<string>();
    for (let s181 of CORE_COMPONENTS) {
        m181.add(s181);
    }
    for (let r181 of l181) {
        m181.add(r181);
    }
    let n181 = true;
    while (n181) {
        n181 = false;
        for (let p181 of CHILD_RULES) {
            if (!m181.has(p181.parent)) {
                continue;
            }
            for (let q181 of p181.allowed) {
                if (q181 !== 'When' && !m181.has(q181)) {
                    m181.add(q181);
                    n181 = true;
                }
            }
        }
        for (let o181 of COMPANIONS) {
            if (m181.has(o181[0]) !== m181.has(o181[1])) {
                m181.add(o181[0]);
                m181.add(o181[1]);
                n181 = true;
            }
        }
    }
    return m181;
}
export function componentsUsedIn(i181: string): string[] {
    let j181: string[] = [];
    for (let k181 of CATALOG) {
        if (i181.indexOf('ui.' + k181.name + '(') >= 0) {
            j181.push(k181.name);
        }
    }
    return j181;
}
export function componentEmbeddingText(h181: ComponentSpec): string {
    return h181.name + ' -- ' + h181.summary + (h181.guidance.length > 0 ? ' ' + h181.guidance : '');
}
function signatureLine(e181: ComponentSpec): string {
    let f181: string[] = [];
    for (let g181 of e181.props) {
        f181.push(g181.optional ? '[' + g181.name + ']' : g181.name);
    }
    return '  ui.' + e181.name + '(' + f181.join(', ') + ')  -- ' + e181.summary;
}
function hasIconProp(c181: ComponentSpec): boolean {
    for (let d181 of c181.props) {
        if (d181.kind === 'icon') {
            return true;
        }
    }
    return false;
}
export function describeComponents(y180: string[]): string {
    let z180: string[] = [];
    for (let a181 of CATALOG) {
        if (y180.indexOf(a181.name) < 0) {
            continue;
        }
        z180.push(signatureLine(a181));
        let b181 = stylesFor(a181.nodeKind);
        if (b181.length > 1) {
            z180.push('    styles: ' + b181.join(' '));
        }
        if (a181.guidance.length > 0) {
            z180.push('    ' + a181.guidance);
        }
    }
    return z180.join('\n');
}
export function describeCatalogForPrompt(f180: Set<string> | null = null): string {
    let g180: ComponentSpec[] = [];
    for (let x180 of CATALOG) {
        if (f180 === null || f180.has(x180.name)) {
            g180.push(x180);
        }
    }
    let h180: string[] = [];
    h180.push('UI constructors (all return ui.View):');
    for (let w180 of g180) {
        h180.push(signatureLine(w180));
    }
    h180.push('  ui.When(condition, child)  -- child when true, nothing when false');
    h180.push('  ui.intToString(n), ui.numberToString(n), ui.booleanToString(b)');
    h180.push('');
    h180.push('Allowed styles:');
    for (let u180 of g180) {
        let v180 = stylesFor(u180.nodeKind);
        if (v180.length > 1) {
            h180.push('  ' + u180.name + ': ' + v180.join(' '));
        }
    }
    let i180: ComponentSpec[] = [];
    for (let t180 of g180) {
        if (t180.guidance.length > 0) {
            i180.push(t180);
        }
    }
    if (i180.length > 0) {
        h180.push('');
        h180.push('When to use each of these:');
        for (let s180 of i180) {
            h180.push('  ui.' + s180.name + ' -- ' + s180.guidance);
        }
    }
    let j180 = false;
    for (let r180 of g180) {
        if (hasIconProp(r180)) {
            j180 = true;
        }
    }
    if (j180) {
        h180.push('');
        h180.push('Icon names (the only ones that exist):');
        let o180 = iconNames();
        let p180: string[] = [];
        for (let q180 of o180) {
            p180.push(q180);
            if (p180.length === 8) {
                h180.push('  ' + p180.join(' '));
                p180 = [];
            }
        }
        if (p180.length > 0) {
            h180.push('  ' + p180.join(' '));
        }
        h180.push('  Pass "" where a component takes an icon and you do not want one.');
    }
    let k180: string[] = [];
    for (let m180 of CHILD_RULES) {
        if (f180 !== null && !f180.has(m180.parent)) {
            continue;
        }
        if (m180.allowed.length > 0) {
            k180.push('  ' + m180.parent + ' takes only ' + listWords(m180.allowed) + ' children.');
        }
        for (let n180 of m180.refusedInside) {
            k180.push('  ' + m180.parent + ' may not contain another ' + n180 + '.');
        }
    }
    if (k180.length > 0) {
        h180.push('');
        h180.push('Composition rules the compiler enforces:');
        for (let l180 of k180) {
            h180.push(l180);
        }
    }
    return h180.join('\n');
}
