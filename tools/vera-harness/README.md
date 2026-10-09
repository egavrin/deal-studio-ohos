# vera-harness

Runs the real `std/ui` compiler, VM and decoder under plain Node — no device,
no build, no install. See `CLAUDE.md`'s "Checking things without a device"
for why this exists: chasing a layout bug through minute-long on-device
generations does not converge.

## What it is

`src/*.ts` are `VeraCompiler.ets` / `VeraInterpreter.ets` / `VeraUiCatalog.ets`
/ `VeraIcons.ets` / `VeraTheme.ets` / `VeraUi.ets`, copied **unmodified** from
the ArkTS compile cache — not hand-ported. `VeraSdkIndex.ts` is the one
hand-written stub: `VeraCompiler.ets` imports it only to check SDK target
names, which `std/ui` programs never do, so a two-line stand-in is enough and
avoids pulling in `LlamaEngine`/`VeraIntentRegistry` and their native/OS
dependencies.

`VeraPreview.ets` is **not** copied here and cannot be: it is
`@Component`/ArkUI and only runs on device or in the ArkTS preview. That is
what `proof-sheet.js` is for — a separate, deliberately approximate renderer
that draws the decoded tree as SVG so a layout change is still something you
can look at.

## Refreshing `src/*.ts` after a change

Edit the real `.ets` files under `entry/src/main/ets/vera/` as usual, then:

```bash
cd /home/stanislav/work/vera/vera-probe-dynamic
source ./tool-paths.sh
"$(vera_kit_bin arkui-hvigor)" --directory /tmp/ --json "$(pwd)"   # compile only, no sign/install

CACHE=entry/build/default/cache/default/default@CompileArkTS/esmodule/release/entry/src/main/ets/vera
for f in VeraInterpreter VeraUiCatalog VeraIcons VeraTheme VeraUi VeraCompiler; do
  sed -E 's#"@normalized:N&&&entry/src/main/ets/vera/([A-Za-z0-9_]+)&"#"./\1"#g' \
    "$CACHE/$f.ts" > tools/vera-harness/src/$f.ts
done

cd tools/vera-harness && /usr/bin/tsc -p tsconfig.json   # -> out/*.js
```

Only resync the files that actually changed if you want to save a few
seconds; resyncing all six is always correct.

## Running it

```bash
node run.js <path-to.vera> [entryFunction=view] [stateJson]
```

With no `stateJson` and `entryFunction=view` (the default), `init()` runs
first and its result becomes the state argument — the common case. Prints the
decoded `VeraUiNode` tree as JSON. A compile error prints its diagnostics
(code, line, column, message) and exits 1 rather than throwing.

`stateJson` is the VM's own tagged-tuple save format (`["s", "x"]`,
`["o", "AppState", [["field", value]]]`, ...), not plain JSON — in practice
it's simpler to write a throwaway `.vera` file whose `init()` returns the
state you want to test, the way `examples/backhandler-detail.vera` does.

For the SVG proof sheet:

```bash
node run.js x.vera | node proof-sheet.js [--select-wrap=false] [--preset=clean] > out.svg
convert out.svg out.png   # ImageMagick, for looking at it with the Read tool
```

`proof-sheet.js` is approximate on purpose: estimated text width, no real
ArkUI text metrics, no animation. It is for catching wrap/overflow/shape bugs
by eye, not for pixel-matching the device.

## What this can't verify, ever, without a device

Exact ArkUI measurement and text wrapping, animation playback (`ui.Spinner`'s
spin, `ui.Path`'s rotation), the on-screen keyboard a `TextField`'s
`keyboardType` actually offers, real dark-mode device colors, and the system
back gesture (`ui.BackHandler`). Each of those needs `build-hap.sh` →
`sign-system.sh` → `hdc install` and a look at the real screen.

## Fixtures

`examples/*.vera` are small test programs, one concern each (`select-demo`
for the overflow fix, `feedback-demo` for Skeleton/Spinner/Snackbar,
`sparkline-demo`, `textfield-demo`/`textfield-old` for validation and the
old-bytecode trailing-optional fallback, `backhandler-demo`/
`backhandler-detail` for the two states of the back-handler tree). `proofs/`
holds the generated `.svg`/`.png` pairs for the ones worth a picture.

`validation-check.js` mirrors `VeraPreview.ets`'s `textFieldIssue()` logic
exactly and runs it against a table of cases — written once, used identically
on the host and in the real render branch, so the validation rules are
confirmed before they ever touch ArkUI.
