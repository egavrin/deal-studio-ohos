# VERA-L UI Architecture over ArkUI

> **Predates the current renderer.** Rendering moved out of RunnerPage into
> VeraPreview, and the tree is no longer rebuilt per frame -- a persistent
> @Trace'd tree is reconciled in place. This file also has nothing on std/intent
> or std/calendar, which did not exist when it was written. The five-stage
> pipeline below is still the right shape; the names and the last stage are not.
> See `architecture.html` for the current picture.


## Overview

VERA-L programs never touch ArkUI directly. The VM produces pure data trees; a thin mapping layer in RunnerPage renders them as native HarmonyOS components. The architecture has 5 stages.

## Pipeline

```
VERA-L source
  │
  ▼
┌─────────────────────────────────────────────────────┐
│ 1. Pure Functions (VERA-L program)                  │
│                                                     │
│   init() → AppState        initial state            │
│   view(state) → ui.View    pure view tree           │
│   handler(state, val) → AppState   no mutation      │
└─────────────────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────────────────┐
│ 2. VM Execution (VeraInterpreter.ets)               │
│                                                     │
│   Calls view(state) → ui.Column(...), ui.Button()   │
│   UiHostEnvironment builds VeraObjectValue nodes:   │
│                                                     │
│   VeraObjectValue {                                 │
│     classIdentity: "std/ui:View"                    │
│     fields: Map {                                   │
│       "type"     → "column"                         │
│       "style"    → "spacious"                       │
│       "children" → VeraArrayValue[...]              │
│     }                                               │
│   }                                                 │
│                                                     │
│   Result: a tree of RuntimeValue objects            │
└─────────────────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────────────────┐
│ 3. decodeVeraUi() (VeraUi.ets)                      │
│                                                     │
│   Walks RuntimeValue tree, extracts typed fields:   │
│                                                     │
│   VeraUiNode {                                      │
│     kind: string       // "column", "button", ...   │
│     style: string      // "spacious", "primary"     │
│     text: string       // display text              │
│     action: string     // handler function name     │
│     eventValue: number // value passed to handler   │
│     enabled: boolean                                │
│     children: VeraUiNode[]                          │
│     source: string     // image src                 │
│     alt: string        // image alt                 │
│   }                                                 │
└─────────────────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────────────────┐
│ 4. @Builder renderNode() (RunnerPage.ets)           │
│                                                     │
│   Switches on node.kind → ArkUI component:          │
│                                                     │
│   kind        ArkUI               Style via         │
│   ─────────── ─────────────────── ────────────────  │
│   "column"    Column()            .padding, .align  │
│   "row"       Row()               .justifyContent   │
│   "text"      Text(node.text)     .fontSize, color  │
│   "button"    Button(node.text)   .onClick → handle │
│   "card"      Column().bg().r()   .backgroundColor  │
│   "cell"      Row()               tap row style     │
│   "spacer"    Blank()             height             │
│   "image"     Image(node.source)  .objectFit        │
│   "scroll"    Scroll()            nested children   │
└─────────────────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────────────────┐
│ 5. Interaction Loop                                 │
│                                                     │
│   @State ──→ view() ──→ decode ──→ ArkUI ──→ Screen│
│     ▲                                         │     │
│     │                                    tap  │     │
│     │                                         ▼     │
│     └── handler(state, val) ◄── onClick(action,val) │
│          returns new state                          │
│                                                     │
│   State update triggers reactive rebuild:           │
│   view(newState) → decodeVeraUi → renderNode        │
│   Whole tree is replaced, no diffing.               │
└─────────────────────────────────────────────────────┘
```

## Pseudo-code

### VERA-L program (user-authored)

```
import * as ui from "std/ui"

@jsonable
class AppState {
  count: int;
}

function init(): AppState {
  return {count: 0};
}

function change(state: AppState, amount: int): AppState {
  return {count: state.count + amount};
}

function view(state: AppState): ui.View {
  return ui.Column("spacious", [
    ui.Text("title", "Counter"),
    ui.Text("metric", ui.intToString(state.count)),
    ui.Row("spacious", [
      ui.Button("secondary", "-", "change", -1, true),
      ui.Button("primary", "+", "change", 1, true)
    ])
  ]);
}
```

### Host side (ArkTS, simplified)

```
// RunnerPage.ets — simplified pseudo-code

@State currentState: RuntimeValue = vm.execute("init", [])
@State nodes: VeraUiNode[] = decodeVeraUi(vm.execute("view", [currentState]))

handleAction(action: string, value: number) {
  let intVal = new VeraIntValue(value)
  let newState = vm.execute(action, [currentState, intVal])
  currentState = newState
  nodes = decodeVeraUi(vm.execute("view", [newState]))
}

@Builder renderNode(node: VeraUiNode) {
  switch (node.kind) {
    case "column":
      Column() { ForEach(node.children, child => renderNode(child)) }
    case "text":
      Text(node.text).fontSize(styleToSize(node.style))
    case "button":
      Button(node.text)
        .onClick(() => handleAction(node.action, node.eventValue))
        .enabled(node.enabled)
    // ... other kinds
  }
}
```

## Key design decisions

1. **VERA-L never sees ArkUI.** The `ui.*` functions in the VM just build value objects. All rendering is in one `@Builder` in RunnerPage.

2. **No diffing.** Every state change rebuilds the full view tree. VERA-L programs are small (< 80 nodes), so this is fast enough and avoids reconciliation complexity.

3. **Actions are strings.** `ui.Button("primary", "+", "change", 1, true)` stores the handler name `"change"` as a string. On tap, RunnerPage looks up and calls the VM function by name.

4. **State is opaque.** RunnerPage holds `currentState` as a `RuntimeValue` — it never inspects or modifies it. Only VERA-L handlers produce new state.

5. **Styles are a closed set.** Each component kind has a fixed set of allowed style names (e.g. Button: `primary`, `secondary`, `success`, `danger`). The `@Builder` maps these to ArkUI properties. No CSS, no arbitrary styling.
