# Working on this repo

A HarmonyOS app that generates small programs from a plain-English prompt,
compiles them on the phone and renders them as native ArkUI. `entry/src/main/
ets/vera/` is the language: compiler, VM, the `std/ui` catalogue and the theme.
`entry/src/main/ets/components/VeraPreview.ets` is the renderer.

## Before you build: find out what is missing, then ask

The build needs three things that are not in this repo. Run this first — it
prints what it found and what it did not:

```bash
bash -c 'source ./tool-paths.sh
for t in arkui-hvigor arkui-sign arkui-device-cli; do
  printf "%-18s %s\n" "$t" "$(vera_kit_bin $t 2>&1 | tail -1)"; done
printf "%-18s %s\n" hdc "$(vera_hdc_dir 2>&1 | tail -1)"
printf "%-18s %s\n" hapsigner "$(vera_hapsigner 2>&1 | tail -1)"'
```

| what | used for | how the scripts find it |
|---|---|---|
| **ArkTS Agent Kit** | `arkui-hvigor` builds, `arkui-sign` debug-signs, `arkui-device-cli` dumps the screen | `$KIT_ROOT`, else a few known locations; the binaries live in `tools/` in an unpacked kit and `.venv/bin` in a pip install, and both are searched |
| **hdc** | everything that talks to the phone | `$HDC_DIR`, else `~/Desktop/hdc`, `~/hdc`, else `PATH` |
| **hapsigner** | `sign-system.sh` calls `dist/hap-sign-tool.jar`; needs a JRE | `$HAPSIGNER`, else `~/agent-kit-sdk/hapsigner` |

**If any of them prints an ERROR line, stop and ask the person working with you
— do not guess a path and do not install anything.** Ask exactly this:

> This repo needs the ArkTS Agent Kit, hdc and hapsigner, and I cannot find
> *(name the ones that failed)*. Where are they on this machine? I will use them
> through `KIT_ROOT` / `HDC_DIR` / `HAPSIGNER` — or I can add the location to
> `tool-paths.sh` if it should be found automatically from now on.

An explicitly set variable is an instruction, not a hint: if the thing is not
where it says, the script fails and names the variable rather than quietly using
another copy.

## Building, signing, installing

```bash
./build-hap.sh      # builds, then debug-signs; finds the UDID itself
./sign-system.sh    # re-signs the unsigned HAP as a system app
hdc install /tmp/vera-probe-dyn-hap/vera-probe-dyn-system-signed.hap
./measure.sh 3      # timings -> results/device.jsonl
```

`build-hap.sh` cannot produce a system app: `arkui-sign` takes no profile
argument and reads the kit's own template. A program that calls `std/intent`
needs one, because `insightIntentDriver` is a system API — so the usual route is
`build-hap.sh`, ignore the HAP it signs, then `sign-system.sh` and install that.

## Three traps that cost real time

**Never `hdc uninstall`.** It destroys `{filesDir}/vera`: every saved project,
every program's state and the DeepSeek API key. There is no backup route. If an
install is refused, work out why instead — and note that a normal app cannot be
updated into a system app in place (`9568294 apptype not same`), so a bundle that
has ever been installed normally has to be built under a throwaway `bundleName`
to test a system profile.

**The API key is a launch parameter**, never compiled in, and it survives
restarts once stored:

```bash
hdc shell aa start -a EntryAbility -b com.vera.probe.dyn --ps deepseekKey sk-...
```

The same goes for `vera-server`, if the Server generation mode is wanted:
`--ps veraServer http://host:port`. Neither has a default, and neither belongs
in the source.

**Prompts typed into the Generate screen are written in English**, even when the
conversation is not.

## Checking things without a device

The ArkTS build leaves plain TypeScript in
`entry/build/default/cache/default/default@CompileArkTS/esmodule/release/entry/src/main/ets/vera/`,
so the compiler, the VM, the UI decoder and the theme all run under node on the
host. That is the fast way to check a change: seconds, no install, no
generation. Two things to know — imports come out as
`"@normalized:N&&&entry/src/main/ets/vera/X&"` and must be rewritten to
`"./X.js"`, and `compileVeraSource` **throws** `CompileError` carrying
`.diagnostics` rather than returning them.

For anything visual, render a proof sheet rather than waiting on a generated app
to happen to contain the thing you changed: a hand-built node tree in the
renderer, or an SVG rasterised on the host. Chasing a layout bug through
minute-long generations does not converge — that mistake has been made here.

## Where the pieces are

| file | what it is |
|---|---|
| `entry/src/main/ets/vera/VeraUiCatalog.ets` | the one description of `std/ui`: components, styles, icons, composition rules. The compiler interface, the validator and the model's prompt are all generated from it |
| `entry/src/main/ets/vera/VeraTheme.ets` | six presets, light and dark, and every colour and size the renderer uses |
| `entry/src/main/ets/vera/VeraIcons.ets` | sixteen icons as path data, normalised to one optical size |
| `entry/src/main/resources/rawfile/vera-skill.txt` | the prompt, with `{{UI_CATALOG}}` and the intent and calendar catalogues spliced in |
| `docs/demo-prompts.md` | the prompts this is demonstrated with, and what to check in the output |
| `docs/examples/shanghai-layover.vera` | a program the model actually wrote, kept verbatim |

Adding a component means editing the catalogue, adding a case in
`VeraUi.ets`, and adding a branch in `VeraPreview.ets` — the compiler, the
validator and the prompt follow from the catalogue on their own. The renderer
keeps a second hardcoded list of kinds it can draw and complains on startup if
it drifts from the catalogue.
