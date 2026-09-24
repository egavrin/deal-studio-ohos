# Everything `std/ui` can draw

The whole interface a generated program may use, as the compiler accepts it and the renderer draws it.

Generated from `entry/src/main/ets/vera/VeraUiCatalog.ets` -- the same table that produces the compiler's
module interface, the validator's rules and the catalogue section of the model's prompt, so nothing here can
drift from what the phone runs. Anything not in this file is not in the language: the compiler rejects it.

44 components, 33 of them with a style set, 8 that hand a value back to a handler, 16 icons, 7 composition rules.

A program picks a component and one style name from a closed set. It cannot set a colour, a padding or a
size: those come from `VeraTheme.ets` and the renderer.

## Every function at a glance

| function | group | what it does |
|---|---|---|
| `ui.Column` | Layout | Vertical stack |
| `ui.Row` | Layout | Horizontal stack |
| `ui.Card` | Layout | Framed group |
| `ui.Scroll` | Layout | Scrolling group |
| `ui.Grid` | Layout | Lays its children out in N equal columns, wrapping onto new rows |
| `ui.Canvas` | Layout | One drawing: the ui.Path children share a single 0..100 field and overlap |
| `ui.Spacer` | Layout | Vertical gap |
| `ui.Divider` | Layout | A horizontal rule |
| `ui.Text` | Content | A line of text |
| `ui.IntText` | Content | A whole number as text: prefix, the number padded to minimumDigits, suffix |
| `ui.ClockText` | Content | A time of day from minutes since midnight, written as HH:MM |
| `ui.Image` | Content | An https image |
| `ui.Path` | Content | Vector shape |
| `ui.Icon` | Content | One icon on its own |
| `ui.Badge` | Content | A short status, drawn as a chip rather than a line of text |
| `ui.Progress` | Content | A progress bar |
| `ui.Button` | Input | Tappable button |
| `ui.IconButton` | Input | A button that is only an icon |
| `ui.Cell` | Input | Tappable grid cell |
| `ui.ActionBar` | Input | The row of buttons for a screen or a section |
| `ui.TextField` | Input | Text the user types |
| `ui.IntField` | Input | A number the user sets with - and + |
| `ui.TimeField` | Input | A time of day, as minutes since midnight |
| `ui.Toggle` | Input | On/off switch |
| `ui.Checkbox` | Input | Tick box |
| `ui.Slider` | Input | Pick a number in a range |
| `ui.Select` | Input | Choose one option |
| `ui.Ticker` | Input | Draws nothing |
| `ui.AppTheme` | Composition | The whole app in one look |
| `ui.Header` | Composition | The app's own title block: eyebrow above, title, supporting line below |
| `ui.Section` | Composition | One part of the screen, with a role: hero summary content supporting warning |
| `ui.SectionHeader` | Composition | A heading inside a section: title, subtitle, and a count on the right |
| `ui.ListGroup` | Composition | One bounded surface holding related ui.ListItem rows, separated for you |
| `ui.ListItem` | Composition | One row of a list: title, subtitle, trailing text, leading icon, tappable |
| `ui.IntListItem` | Composition | A ui.ListItem whose trailing value is a number, formatted for you |
| `ui.Timeline` | Composition | Events in the order they happen, joined by a rail |
| `ui.TimelineItem` | Composition | One moment on a timeline |
| `ui.MetricGroup` | Composition | Two to four ui.Stat or ui.IntStat children across one surface, in equal columns |
| `ui.Stat` | Composition | One number told properly: label above, value large, supporting line below |
| `ui.IntStat` | Composition | A ui.Stat for a number the program holds as an int |
| `ui.KeyValueGroup` | Composition | ui.KeyValueItem children in equal columns, for facts rather than figures |
| `ui.KeyValueItem` | Composition | One labelled fact: label above, value below |
| `ui.InsetBanner` | Composition | A standing status or guidance note in a tone, with one optional action |
| `ui.EmptyState` | Composition | What to show where a collection is empty: title, message, one way forward |
| `ui.When` | — | Draws the child when the condition is true, nothing when it is false |
| `ui.intToString` | — | A whole number as text |
| `ui.numberToString` | — | A fractional number as text |
| `ui.booleanToString` | — | A boolean as text |

The signature of each, with its types, styles and the rule for when to use it, follows below.

## The types

Six types appear in the component signatures, and every one of them is checked at compile time. A seventh,
`number`, reaches `std/ui` only through `ui.numberToString`.

| type | what it is |
|---|---|
| `View` | what every `ui.*` call returns. A program can pass it and store it in an array, and nothing else: there is no way to read a view back, change it or ask it anything. |
| `View[]` | the children of a container, written as an array literal or built with the array functions. 13 properties take one. |
| `string` | text. Also the type of a `style`, an `icon` and an `action`, each with its own rule below. |
| `int` | a whole number. Sizes, counts, minutes, slider values and the `value` a tap carries are all ints. |
| `boolean` | `enabled`, `checked`, `running`. |
| `string[]` | one property only: the `options` of `ui.Select`. |
| `number` | a fractional number. No component takes one: `ui.numberToString` is the only place it appears, and every component that holds a figure holds an `int`. |

Three of the string-typed properties are not free text:

- **`style`** is the first argument of every component and comes from that component's own closed set,
  listed under each entry below. A literal outside the set is diagnostic `E2105`; a style computed at
  runtime is not checked and falls back to the renderer's default.
- **`icon`** is one of the 16 names below, or `""` for none. An unknown literal is `E2108`.
- **`action`** is the name of a handler function in the program. A name with no handler behind it is `E2106`,
  and so is a handler whose parameter type does not match what the component hands it.

A trailing property in `[brackets]` may be left off the call. Only trailing properties are optional, and they
exist so the vocabulary can grow: a program written against an older catalogue still compiles, and a model
that learnt the old signature is not failed for it.

**What a handler looks like.** A component with an `action` calls a function of two arguments -- the state and
the value the component hands over:

```
function onVolume(state: AppState, value: int): AppState { ... }   // ui.Slider, ui.IntField, ui.TimeField, ui.Select, ui.Ticker
function onName(state: AppState, value: string): AppState { ... }  // ui.TextField
function onMute(state: AppState, value: boolean): AppState { ... }  // ui.Toggle, ui.Checkbox
function onTap(state: AppState, value: int): AppState { ... }      // everything else: the value written into the call
```

A component that takes an `action` but declares no payload of its own -- `ui.Button`, `ui.Cell`, `ui.ListItem`
and the rest -- hands the handler the `value` written into the call, as an int. The handler returns the new
state, and the state is saved for you.

## Layout

*boxes, gaps and rules*

### `ui.Column(style: string, children: View[]): View`

Vertical stack.

**Styles:** `default` `compact` `spacious` `center` `end` `surface` `accent`

### `ui.Row(style: string, children: View[]): View`

Horizontal stack.

**Styles:** `default` `compact` `spacious` `center` `end` `split` `joined` `surface` `accent`

### `ui.Card(style: string, children: View[]): View`

Framed group.

**Styles:** `surface` `accent` `success` `warning` `danger`

### `ui.Scroll(style: string, children: View[]): View`

Scrolling group.

### `ui.Grid(style: string, columns: int, children: View[]): View`

Lays its children out in N equal columns, wrapping onto new rows.

**Styles:** `default` `compact` `spacious`

### `ui.Canvas(style: string, children: View[]): View`

One drawing: the ui.Path children share a single 0..100 field and overlap.

**Styles:** `default` `small` `large`

### `ui.Spacer(style: string): View`

Vertical gap.

**Styles:** `none` `small` `default` `large`

### `ui.Divider(style: string): View`

A horizontal rule.

## Content

*what the program shows*

### `ui.Text(style: string, text: string): View`

A line of text.

**Styles:** `display` `title` `heading` `body` `caption` `eyebrow` `metric` `muted` `success` `warning` `danger`

### `ui.IntText(style: string, value: int, prefix: string, suffix: string, minimumDigits: int): View`

A whole number as text: prefix, the number padded to minimumDigits, suffix.

**Styles:** `display` `title` `heading` `body` `caption` `metric` `muted` `success` `warning` `danger`

> Use instead of ui.Text with ui.intToString. minimumDigits 2 writes 7 as "07", so a clock is ui.IntText("body", h, "", ":", 2) beside ui.IntText("body", m, "", "", 2) and needs no pad function. Use prefix and suffix for units and currency rather than gluing strings together.

### `ui.ClockText(style: string, minutes: int, prefix: string, suffix: string): View`

A time of day from minutes since midnight, written as HH:MM.

> The only way to show a time. Never build one from two ui.IntText and never write a padding function for it: 9:05 in the morning is ui.ClockText("body", 545, "", ""). Minutes since midnight is what time.hourOfDay() * 60 + time.minuteOfHour() gives and what ui.TimeField hands back, so the three fit together.

### `ui.Image(style: string, src: string, alt: string): View`

Https image.

### `ui.Path(style: string, commands: string, spinPeriodMs: int): View`

Vector shape; spinPeriodMs > 0 rotates it.

**Styles:** `default` `accent` `success` `warning` `danger` `muted` `light`

### `ui.Icon(style: string, [name: string]): View`

One icon on its own.

**Styles:** `default` `muted` `accent` `success` `warning` `danger`

> For an icon that is not part of something else. Most icons should instead be the icon property of a ListItem, Banner, EmptyState, Header or Stat, which places them properly.

### `ui.Badge(style: string, text: string, [icon: string]): View`

A short status, drawn as a chip rather than a line of text.

**Styles:** `default` `accent` `success` `warning` `danger`

> For the state of the thing next to it -- "Reached", "Overdue", "3 left". Pass icon "" for no icon. Do not use it for ordinary text.

### `ui.Progress(style: string, label: string, value: int, maximum: int): View`

A progress bar.

**Styles:** `default` `accent` `success` `warning` `danger`

## Actions and input

*everything a person can touch*

### `ui.Button(style: string, text: string, action: string, value: int, enabled: boolean): View`

Tappable button.

**Styles:** `primary` `secondary` `success` `danger`

### `ui.IconButton(style: string, [icon: string], label: string, action: string, value: int, enabled: boolean): View`

A button that is only an icon; label is what it does, for accessibility.

**Styles:** `primary` `secondary` `success` `danger` `quiet`

> Use for a secondary action beside a primary one, so a row of three actions does not become three blocks of text. The label is never drawn but must still say what the button does. Keep the one action a person is most likely to want as a full ui.Button.

### `ui.Cell(style: string, text: string, action: string, value: int, enabled: boolean): View`

Tappable grid cell.

**Styles:** `default` `accent` `success` `danger`

### `ui.ActionBar(style: string, children: View[]): View`

The row of buttons for a screen or a section.

**Styles:** `default` `end` `center` `spread`

> Gather the actions into one of these instead of leaving buttons loose in a Column. It takes ui.Button, ui.IconButton and ui.Badge. One action is primary and the rest are not.

### `ui.TextField(style: string, label: string, value: string, action: string): View`

Text the user types; the handler takes (state, value: string).

**Styles:** `default` `multiline`

**Handler receives:** `string`

### `ui.IntField(style: string, label: string, value: int, minimum: int, maximum: int, action: string): View`

A number the user sets with - and +; the handler takes (state, value: int).

**Handler receives:** `int`

> The only way to get a number from the person. A ui.TextField hands you a string and there is no way to turn a string into an int, so a typed quantity has to come through here. minimum and maximum bound it.

### `ui.TimeField(style: string, label: string, value: int, action: string): View`

A time of day, as minutes since midnight; the handler takes (state, value: int).

**Handler receives:** `int`

> For a time the person chooses. The value is minutes since midnight, which is the same shape time.hourOfDay() * 60 + time.minuteOfHour() produces, so it compares with the clock directly.

### `ui.Toggle(style: string, label: string, checked: boolean, action: string): View`

On/off switch; the handler takes (state, value: boolean).

**Handler receives:** `boolean`

### `ui.Checkbox(style: string, label: string, checked: boolean, action: string): View`

Tick box; the handler takes (state, value: boolean).

**Handler receives:** `boolean`

### `ui.Slider(style: string, label: string, value: int, minimum: int, maximum: int, action: string): View`

Pick a number in a range; the handler takes (state, value: int).

**Handler receives:** `int`

### `ui.Select(style: string, label: string, options: string[], selected: int, action: string): View`

Choose one option; the handler takes (state, index: int).

**Handler receives:** `int`

### `ui.Ticker(style: string, id: string, intervalMs: int, running: boolean, action: string): View`

Draws nothing; calls the handler every intervalMs with the elapsed ms.

**Handler receives:** `int`

## Composition

*the shape of an app, not its pixels*

### `ui.AppTheme(style: string, primary: string, children: View[]): View`

The whole app in one look; primary is a "#rrggbb" seed or "" for the preset's own.

**Styles:** `clean` `soft` `expressive` `editorial` `technical` `playful`

> Wrap everything view returns in exactly one of these. The preset is the app's character, so choose it for the app you were asked for: clean for restrained and neutral, soft for calm and friendly, expressive for bold and atmospheric, editorial for content that leads, technical for dense precise numbers, playful for energetic. Do not pick clean just because an example uses it.

### `ui.Header(style: string, title: string, eyebrow: string, supporting: string, [icon: string]): View`

The app's own title block: eyebrow above, title, supporting line below.

**Styles:** `default` `center`

> Open the screen with one of these instead of a bare ui.Text. Use it once. Leave eyebrow or supporting as "" when there is nothing to say.

### `ui.Section(style: string, title: string, subtitle: string, children: View[]): View`

One part of the screen, with a role: hero summary content supporting warning.

**Styles:** `content` `hero` `summary` `supporting` `warning`

> Give each part of the screen its own Section and let the role say what the part is for. The spacing between sections comes from the theme, so do not add ui.Spacer between them. Prefer this over a Card when all you want is a titled group.

### `ui.SectionHeader(style: string, title: string, subtitle: string, count: string): View`

A heading inside a section: title, subtitle, and a count on the right.

**Styles:** `default` `accent` `muted`

> Use for hierarchy inside a Section without starting another surface. count is for "3 of 8" and the like; pass "" when there is no count.

### `ui.ListGroup(style: string, title: string, children: View[]): View`

One bounded surface holding related ui.ListItem rows, separated for you.

**Styles:** `default` `compact` `comfortable`

> Two or more related rows belong in one of these, not in a Card each. The frame, the separators and the row rhythm are the renderer's job. Rows are ui.ListItem or ui.IntListItem; a ui.SectionHeader may open the group and a ui.ActionBar may follow the row it belongs to.

### `ui.ListItem(style: string, text: string, label: string, value: string, action: string, eventValue: int, enabled: boolean, [icon: string]): View`

One row of a list: title, subtitle, trailing text, leading icon, tappable.

**Styles:** `default` `accent` `success` `warning` `danger`

### `ui.IntListItem(style: string, title: string, subtitle: string, value: int, prefix: string, suffix: string, minimumDigits: int, action: string, eventValue: int, enabled: boolean, [icon: string]): View`

A ui.ListItem whose trailing value is a number, formatted for you.

**Styles:** `default` `accent` `success` `warning` `danger`

> For a row that ends in a quantity, an amount or a time. It goes in a ui.ListGroup exactly like ui.ListItem. Note it carries two numbers: value is what is shown, eventValue is what the tap hands the handler.

### `ui.Timeline(style: string, title: string, children: View[]): View`

Events in the order they happen, joined by a rail.

**Styles:** `default` `compact` `comfortable`

> For anything that runs in time -- an itinerary, a course of treatment, a history. Prefer it to ui.ListGroup whenever the order is chronological rather than merely grouped. Children are ui.TimelineItem; a ui.ActionBar may follow the entry it belongs to.

### `ui.TimelineItem(style: string, title: string, subtitle: string, trailing: string, action: string, eventValue: int, enabled: boolean, [icon: string]): View`

One moment on a timeline; same fields as ui.ListItem, plus its marker.

**Styles:** `default` `accent` `success` `warning` `danger`

> Put the time in trailing, so the times line up down the right edge. The icon becomes the marker on the rail -- "pin" for a place, "check" for something done, "clock" for something still ahead; with no icon the marker is a plain dot.

### `ui.MetricGroup(style: string, columns: int, children: View[]): View`

Two to four ui.Stat or ui.IntStat children across one surface, in equal columns.

**Styles:** `default` `compact` `spacious`

> The summary strip at the top of a screen. Only ui.Stat or ui.IntStat children. columns is a maximum: a narrow screen uses fewer.

### `ui.Stat(style: string, label: string, value: string, supporting: string, [icon: string]): View`

One number told properly: label above, value large, supporting line below.

**Styles:** `default` `accent` `success` `warning` `danger`

> For a summary figure. It draws no surface of its own, so put two to four inside a ui.MetricGroup rather than one inside a Card.

### `ui.IntStat(style: string, label: string, value: int, prefix: string, suffix: string, minimumDigits: int, supporting: string, [icon: string]): View`

Ui.Stat for a number the program holds as an int.

**Styles:** `default` `accent` `success` `warning` `danger`

> Prefer this to ui.Stat whenever the figure is a number rather than text. Same place: inside a ui.MetricGroup.

### `ui.KeyValueGroup(style: string, columns: int, children: View[]): View`

Ui.KeyValueItem children in equal columns, for facts rather than figures.

**Styles:** `default` `compact` `spacious`

> For the details of a thing -- where, how long, which platform. Use this rather than a ui.MetricGroup when the values are words, and rather than a ListGroup when they are short enough to sit two to a row.

### `ui.KeyValueItem(style: string, label: string, value: string, supporting: string): View`

One labelled fact: label above, value below.

**Styles:** `default` `accent` `success` `warning` `danger`

> Only inside a ui.KeyValueGroup.

### `ui.InsetBanner(style: string, title: string, message: string, actionText: string, action: string, [icon: string]): View`

A standing status or guidance note in a tone, with one optional action.

**Styles:** `default` `accent` `success` `warning` `danger`

> For something that stays true while the person works -- a permission that was refused, a warning, the result of the last call. Pass actionText "" and action "" when there is nothing to tap; the handler, if you name one, is called with 0.

### `ui.EmptyState(style: string, title: string, message: string, actionText: string, action: string, [icon: string]): View`

What to show where a collection is empty: title, message, one way forward.

**Styles:** `default` `muted`

> State starts empty, so this is the first thing the person sees. Put one behind ui.When(list.length() === 0, ...) for every collection the app keeps. Pass actionText "" and action "" when there is nothing to tap; the handler, if you name one, is called with 0.

## Beyond the components

- `ui.When(condition: boolean, child: View): View` -- the child when true, nothing when false. This is how a
  program shows one thing or another; there is no `if` inside a view.
- `ui.intToString(n: int): string`, `ui.numberToString(n: number): string`,
  `ui.booleanToString(b: boolean): string` -- the only conversions into text.

### Icon names, the only ones that exist

`check` `close` `plus` `minus` `chevron-right` `navigate` `pin` `calendar` `clock` `star` `user` `warning` `info` `trash` `list` `chart`

Pass `""` where a component takes an icon and none is wanted. An icon is usually a property of a ListItem,
Banner, EmptyState, Header or Stat rather than a component of its own.

### Composition rules the compiler enforces

- ListGroup takes only ListItem, IntListItem, SectionHeader, ActionBar or When children.
- MetricGroup takes only Stat, IntStat or When children.
- KeyValueGroup takes only KeyValueItem or When children.
- Timeline takes only TimelineItem, ActionBar or When children.
- ActionBar takes only Button, IconButton, Badge or When children.
- Card may not contain another Card.
- AppTheme may not contain another AppTheme.

These are checked on the tree the program writes, not at runtime, and the violation is diagnostic `E2107`.

## Keeping this file true

Adding a component means editing `VeraUiCatalog.ets`, adding a case in `VeraUi.ets` and a branch in
`VeraPreview.ets`; the compiler, the validator and the prompt follow from the table on their own. The renderer
keeps its own list of kinds it can draw and complains on startup if the two drift apart. This file is written
from the same table and should be regenerated whenever the table changes.
