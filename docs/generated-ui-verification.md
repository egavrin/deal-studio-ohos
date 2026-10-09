# Generated interface refresh: verification

The change improves visual direction prompts and the native renderer for generated applications and chat widgets.
Saved applications receive the new typography, spacing, and palette without a source or state migration.
The application shell and the DeepSeek settings from PR #13 retain their existing contracts.

## Revisions and evidence

The baseline is `df66e50276ea66ffa7f29a527e5f847491ea99ff`.
The tested implementation is `b3acfcf456af10142eeeb4000344b071597b1382`.
Later evidence commits contain documentation and artifacts only.

Fixtures and failure cases were defined before production edits.
The baseline counter, countdown, expense, reading, and habit workflows all compiled, initialized, decoded, and exercised their handlers.
Their pre-change bytecode, exact sources, saved state, and revision are in `tools/vera-harness/compatibility`.
Candidate fixtures are in `tools/vera-harness/examples/visual-*.vera`.

| Check | Expected | Observed |
| --- | --- | --- |
| Current-source visual and compatibility harness | Every check passes | 93/93 PASS |
| Existing prompt workflow harness, with visual handoff | Every check passes | 22/22 PASS |
| Enabled text and button contrast | At least 4.5:1 on tested surfaces | 4,896 pairs pass; minimum 4.500019:1 |
| Theme and width matrix | Both revisions, six themes, two modes, three widths, compact widgets | 96 proofs, 16 labeled sheets |
| Empty children, long text, and narrow composition proofs | Full-size text and ordered one/two columns | Six additional proofs inspected |
| Native build and screenshots | Run when tools are available | Unavailable |

The visual checks use the actual current compiler, VM, UI host, and decoder.
They exercise counter changes, countdown ticks and termination, budget edits, reading saves, and habit completion.
They restore pre-change bytecode and tagged saved state and exercise the original handlers.
They check both new signatures, empty children, long text, child order, and default/clamped minimum widths.
The geometry checks execute extracted native helpers and live-tree reconciliation with host decorator stubs.
They check one column before measurement, threshold transitions, gap subtraction, widget type caps, and retained live widths.
These checks do not execute ArkUI layout.

The prompt checks execute real application transport and repair methods with mocked HTTP and UI bookkeeping.
They cover full and selected catalogue assembly, widgets, refinement, exact compiler feedback, and tool continuation.
The chat marker retains explicit visual preferences, values, units, behavior, and a verified fixture image address.
Every DeepSeek application generation attempt still has enabled reasoning and a 32,768-token output limit.
Ordinary chat and component selection retain their previous settings.

The contrast criterion follows [W3C contrast guidance](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html).
It covers eight enabled ink roles on eight supported surfaces and four button styles.
Each preset runs in light and dark mode with its default accent and five extreme seed colors.
This is a color acceptance criterion, not a claim of full accessibility conformance.

## Repeat the checks

Run from the repository root with an available TypeScript module.
Set `VERA_TYPESCRIPT_PATH` when Node cannot resolve `typescript` normally.
Use an available `sharp` module for raster proofs, with `NODE_PATH` if necessary.
The saved reports contain the exact commands and module paths used on this machine.

```bash
node tools/vera-harness/visual-check.js /tmp/vera-visual-verification.json
node tools/vera-harness/prompt-check.js . /tmp/vera-prompt-verification.json
VISUAL_BASELINE_DIR=$(mktemp -d)
git archive df66e50276ea66ffa7f29a527e5f847491ea99ff entry/src/main/ets | tar -x -C "$VISUAL_BASELINE_DIR"
node tools/vera-harness/visual-proofs.js /tmp/vera-visual-proofs "$VISUAL_BASELINE_DIR/entry/src/main/ets"
```

The loader reads application sources in each process. It does not use stale `out` copies.
It uses the existing host SDK-index stub, so these checks do not establish device adapter support.
Baseline full-screen proofs load saved old bytecode and the original theme source.
Candidate full-screen proofs compile current fixture sources.
Compact counter widgets use the same source in both phases.
The comparison changes composition and rendering together and does not isolate their individual effects.

[Summary](visual-evidence/summary.json) records acceptance totals and image inspection limits.
[Complete host results](visual-evidence/host-results.json.gz) contain commands, revisions, expectations, results, decoded trees, and every contrast pair.
[Proof archive](visual-evidence/proofs.tar.gz) contains all SVGs, PNGs, decoded trees, edge sources, and image paths.
[Matrix manifest](visual-evidence/manifest.json) records source and image hashes.
To repeat an edge proof, extract its `.vera` source and use `run.js` followed by `proof-sheet.js` at its named width.

## Image inspection

All 96 matrix images were inspected through the 16 sheets below.
All six edge images were also inspected.
The inspection covered hierarchy, alignment, wrapping, repeated surfaces, and clipping.
The candidate expense fixture uses one column at 320/360 vp and two columns at 600 vp.
Editorial headings use serif with system body text. Technical prominent values use monospace.
Compact widgets omit Hero and AdaptiveColumns, with metric text capped at 32 vp.

Host images are approximations. They use resolved theme values and estimated text widths.
Some short button labels wrap because of that estimate, and exact device line breaks and control heights can differ.
No clipping was observed in the inspected host images. Native behavior remains unverified.
The fixtures are deterministic sources. A beauty claim requires a separate evaluation with real model outputs.

| Mode and width | Baseline | Candidate |
| --- | --- | --- |
| Light, 320 vp | [Sheet](visual-evidence/sheet-baseline-light-320.png) | [Sheet](visual-evidence/sheet-candidate-light-320.png) |
| Dark, 320 vp | [Sheet](visual-evidence/sheet-baseline-dark-320.png) | [Sheet](visual-evidence/sheet-candidate-dark-320.png) |
| Light, 360 vp | [Sheet](visual-evidence/sheet-baseline-light-360.png) | [Sheet](visual-evidence/sheet-candidate-light-360.png) |
| Dark, 360 vp | [Sheet](visual-evidence/sheet-baseline-dark-360.png) | [Sheet](visual-evidence/sheet-candidate-dark-360.png) |
| Light, 600 vp | [Sheet](visual-evidence/sheet-baseline-light-600.png) | [Sheet](visual-evidence/sheet-candidate-light-600.png) |
| Dark, 600 vp | [Sheet](visual-evidence/sheet-baseline-dark-600.png) | [Sheet](visual-evidence/sheet-candidate-dark-600.png) |
| Light, compact widgets | [Sheet](visual-evidence/sheet-baseline-light-320-widget.png) | [Sheet](visual-evidence/sheet-candidate-light-320-widget.png) |
| Dark, compact widgets | [Sheet](visual-evidence/sheet-baseline-dark-320-widget.png) | [Sheet](visual-evidence/sheet-candidate-dark-320-widget.png) |

## Native verification limit

Tool discovery could not find `arkui-hvigor`, `arkui-sign`, `arkui-device-cli`, `hdc`, or `hapsigner`.
No native build, installation, screenshot, or device interaction was run.
The user previously authorized continuation with available tools. No toolchain installation was attempted.

## Coordination record

The selected route was `sol-astra`, after an interrupted Claude Opus High companion request produced no recoverable patch.
The remaining companion process was stopped before native fallback.
The native package requested `gpt-6-astra` with High reasoning. It supplied the core patch and one focused repair.
The root implemented native integration and owned acceptance. No separate verifier or nested agent was used.
The root identifies as GPT-6, but its exact variant, reasoning setting, and service tier are not exposed in this session.
Child service-tier telemetry is also unavailable. This record is not a delegated benchmark result.
