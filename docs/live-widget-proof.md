# Live-widget foundation / counter proof

This is the first slice of `ISSUE-home-screen-widgets.md`, Part 2, **not the complete feature**.

## Try it

1. In VERA's project library, use the first top-right menu item, **Widget example**. It creates a separate `Widget counter` project; it never replaces an existing program.
2. On its project page, tap **Widget**.
3. On this phone `isRequestPublishFormSupported()` returns false. The fallback opens the system widget manager. Add **VERA live app**.
4. Tap the unbound widget's title, then choose a project in **Choose widget app**.
5. On the counter card, +/− run the VERA handler in the form extension. The title/arrow opens the full program.

The same Widget action is available for any project. A program without `widget(state)` displays a tile-like fallback and opens the app. An uncompiled project opens its project page.

## Architecture

- `FormBindings.ets`: persistent form-to-project mapping; reloads for every access because app and extension are separate processes.
- `VeraLiveWidget.ets`: platform-independent VM session, rendering projection and event validation.
- `LiveFormService.ets`: load latest version/state, render, validate tap, run handler, render the candidate state, commit only on success.
- `VeraStateStamp.ets`: unchanged state-stamp formula shared with VeraPreview.
- `LiveCard.ets`: launcher-only binding renderer. Fixed depth; no compiler/VM/filesystem imports.
- `FormUpdater.ets`: list/live form routing and coalesced refresh after app state saves.
- `VeraPreview.ets`: reload saved state when the app foreground signal changes.
- State-file writes use a temporary sibling plus rename. Other project/version write semantics are unchanged.

Initial supported kinds are explicitly opted into `ComponentSpec.card`: AppTheme (root only), Column, Row, Text, NumberText, Button, Spacer and Divider. Do not infer that all app components are card-safe.

Limits: 100,000 VM steps per entry call; four layout levels (the theme wrapper does not consume a level); 40 nodes; 256 characters per text; 8,000 UTF-16 code units for the complete frame. This is a conservative application budget, **not a measured platform maximum**. Theme currently resolves light mode only.

Events contain `handler`, numeric `value`, and an exact state/version token. The OS overwrites a message field named `action` with the transport action (`message`), so that name must not be used for the program handler. Only an enabled button in the freshly rendered tree can dispatch. SDK effects are collected but never executed; an effectful handler does not commit state. The card asks the person to open the app; it does not try extension `startAbility`.

The root ForEach key includes the frame token. Without this, nested card builders retain the old displayed number even though updateForm succeeds.

## Verification on this machine

```sh
export VERA_TYPESCRIPT_PATH=/home/mbolshov/agentsdk/command_line_tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js
node tools/vera-harness/live-widget-check.js
node tools/vera-harness/live-form-check.js
node tools/vera-harness/widget-launch-check.js
node tools/vera-harness/smoke-check.js
node tools/vera-harness/visual-check.js /tmp/vera-live-proof/visual-host.json
node tools/vera-harness/chat-handoff-check.js . /tmp/vera-live-proof/chat-host.json
```

Native build and in-place system-signed update succeeded with zero reported diagnostics; identity and first-install time were preserved. No uninstall or app-data clearing.

Device evidence in `/tmp/vera-live-proof/`:

- `final-home`: persisted count 3 after app update.
- `final-plus`: card + changes 3 → 4.
- `final-minus`: card − changes 4 → 3.
- `final-app`: opening the program shows 3.
- `app-to-widget`: app-side + was reflected on the card (2).
- `roundtrip`: subsequent widget-side + was reflected in the app (3).
- `hilog.txt`: measured form handler + render + state-save duration 11–13 ms for the counter; frame about 1.2 KB. This is not end-to-end tap latency.

Screenshots and accessibility dumps were captured, but full visual QA is **not signed off**. The configured external image analyzer rejected requests (413 on full PNG, 400 on cropped JPEG). No independent QC/subagent tool was available in this session. This proof must not be represented as full Part 2 acceptance.

## Make widget follow-up (implemented on host; NOT installed/accepted)

ProjectPage now offers **Make widget** for the latest runnable version. It opens the existing Generate/refine screen with an English request; the person still chooses Generate, reviews the fullscreen preview and saves explicitly. The action does not automatically publish a card.

- `VeraWidgetRefine.ets` derives card-safe constructor signatures from `ComponentSpec.card` and budgets from the runtime constants. These instructions apply only to this refinement, not new-screen generation.
- The compiler checks an optional synchronous `widget(init-result): ui.View` signature (`E2112`). `smokeRun` validates widget trees and actual enabled buttons, twice when still present, without executing phone effects. Failures enter the existing local/DeepSeek repair loop. Server results also receive local validation (server errors remain manual retries).
- Additive preservation checks compare declaration tokens, ignoring comments/formatting: existing classes, init, view, handlers and imports cannot change; widget and new helpers may be added. This deliberately prioritizes safe state carry-over over wider model edits.
- Save rechecks preservation and widget execution against the base version's **latest saved state**, refuses a changed latest-version ID, and stages that state with the new bytecode stamp before publishing the new version. Existing version/state files remain untouched. There is still no cross-process transaction/locking: state remains last-writer-wins.
- Foreground restoration now redraws the same runner instance. Background signals stop program timers; timer reconciliation is disabled while backgrounded.

Host evidence for this follow-up:

- `widget-refine-check.js`: preservation, optional signature, catalogue-derived instructions, smoke diagnostics and saved-state validation pass.
- `live-widget-check.js`: repeated rows with distinct item IDs, middle-row removal, shifted rows and stale/removed-item taps pass using Column/Row (no ListGroup/ListItem required).
- `live-form-check.js`: two widgets sharing state, stale tokens across widgets, binding removal/rebind, missing-project fallback and preserved state in a new version pass.
- `capability-check.js`: **10/10 pass**, including executing extracted renderer lifecycle methods with the real VM, restoring the same runner instance and stopping timers on background. Report `/tmp/vera-widget-capability.json`.
- Widget launch, smoke and visual-tree checks pass (**97/97** visual-tree checks; not screenshot QA).
- Chat regression: **39 pass / 18 fail**. An archived clean HEAD has the exact same failing check names and counts; these are baseline failures, not a clean suite. Reports `/tmp/vera-widget-chat{,-baseline}.json`. The earlier summary's chat-success statement should not be used as evidence for this follow-up.

Native update attempt: `./update-phone.sh` stopped **before installation** with Hvigor `ENOENT .../compiler.cache/modules`. Log `/tmp/vera-widget-refine-update.log` and `.hvigor/outputs/build-logs/build.log` (23:51:32 entry). The current native source changes have **not** passed an ArkTS build and are **not** on the phone. Build-generated lockfile noise was restored. No uninstall, data clearing or build-cache deletion was performed.

Independent QC and device/visual verification remain blocked: tool discovery exposes no independent task/subagent review tool. No merge-ready or full Part 2 claim is made.

## Deferred / known limits

- Habit-list fixture, ListGroup/ListItem and remaining card-safe components.
- Successful native build and end-to-end model/device test of Make widget, including saved-state carry-over.
- Actual platform payload maximum, large form sizes, dark mode and full visual/accessibility QA.
- Removal/rebind lifecycle device coverage and foreground resume to an existing runner without a new router push.
- Last-writer-wins state is intentional; binding-map updates currently use read/modify/replace, so truly concurrent bind/remove operations can overwrite each other.
- Background timer pause/resume change has host lifecycle coverage only; device proof remains outstanding. Timer/game programs are not supported widget fits.
- Independent QC gate remains required before treating the slice as ready to merge.
