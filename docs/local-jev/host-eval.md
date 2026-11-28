# Local-Jev host evaluation (no phone)

Host-only evaluation of local decision models against **recorded cloud Jev**. No
phone, no install: openJev runs via onnxruntime on the host (ORT handles the
masked/padded attention that MindSpore cannot — see §7.1 of
`replacement-analysis.md`), and Laya runs via the dev-machine service
(`tools/local-jev/service.js`). The harness is in `tools/local-jev/eval/`. Bare
section references (§3.2, §5.A, ...) below point into `replacement-analysis.md`.

## Setup

- **Bodies**: 8 recorded compose fixtures (`tools/vera-harness/compose/<name>/`), the
  Jev **body** rebuilt exactly with `buildComposeRequest(prompt, parseSketch(sketch.json))`
  from the fixture's prompt (`compose-prompts.tsv`; `tip`/`egg` fall back to the sketch
  title) — ~112 Jev questions total.
  `build-bodies.js` writes `/tmp/eval/bodies/<name>.json` and pairs the recorded
  `jev-answer.json` as the cloud reference.
- **openJev** (`openjev-eval.py`): for each question, build the GLiClass input
  `<<LABEL>>It is {desc}…<<SEP>>Question: {instructions}\n\nContext:\n{state}`,
  tokenize to 256, run the ONNX (original `model_fp16.onnx`, ORT), softmax over the
  option logits → choice + confidence (abstain slot separate).
- **Laya** (`compare-eval.py` reads `localhost:8099` responses): the dev-machine
  service answering the whole body.
- **Compare** (`compare-eval.py`): per question key, cloud vs openJev vs Laya —
  choice match, noul side-of-0.5 match, confidence, abstain.

## openJev vs cloud Jev — agreement by decision type

| decision type | choice n | openJev agree | mean conf (correct/wrong) | abstain |
|---|---:|---:|---:|---:|
| `asked` (does the request ask for X) | 4 | 100% | 0.94 / — | 4 |
| `countdown` / `effect` / `moment` / `unit` | 7 | 100% | — | — |
| `steps` (one step vs more) | 13 | 92% | 0.89 / 0.96 | 2 |
| `widget` (how the person sets X) | 11 | 55% | 0.93 / 0.70 | 0 |
| `theme` (overall look) | 8 | 50% | 0.89 / 0.63 | 7 |
| `covers` / `arg` | 6 | 50% | — | — |
| `expr` (the formula for a value) | 13 | 31% | 0.54 / 0.22 | 0 |
| `show` (how a value is shown) | 13 | 31% | 0.58 / 0.52 | 11 |
| **overall** | **75** | **58.7%** | | |

## Findings

- **openJev is reliable on the easy/judgment decisions** — `asked`, `effect`,
  `moment`, `countdown`, `unit` at 100%, `steps` at 92%. This matches the analysis
  tiering (§3.2): easy decisions are saturated by a small encoder.
- **openJev is poor on the formula / anatomy decisions** — `expr` 31%, `show` 31%,
  `arg` 50%. These are the standard-to-hard *reasoning* picks the analysis flagged
  (§3.2, §5.B). They must stay on the cloud/LLM or be derived by the plan (§5.D),
  not a small encoder.
- **Calibration is off** — openJev is overconfident on wrong answers (`steps` 0.96 on
  wrong, `widget` 0.70, `theme` 0.63) and abstains heavily on `theme` (7) and `show`
  (11). The Vera thresholds are **not** usable as-is; §5.A per-type re-fit is required.
- **Laya on the WSL dev box is too slow** for real bodies: small fixtures answered
  (bmi 13, expenses 7), but egg/fuel/mortgage hit the model inference timeout
  (~2–10 s/question, >120 s for 15–25-question bodies). Part of that was the box,
  part was the build: those runs predate the discovery that host builds without
  `RUSTFLAGS="-C target-cpu=native"` fall back to candle's *scalar* Q4 kernels —
  7.6× slower (see `build.md` §1). With the flag the host answers the bmi body in
  ~2.6 s/question, and the phone's NEON path (default-on for aarch64) was never
  affected. Not a limit the phone's Candle path removes either way: measured
  on-device it is ~1.5 s per forward on these short fixture bodies and ~5 s per
  question on real ones (`cpu-vs-cloud.md`). Where Laya answered, agreement was
  modest and the sample too small to conclude.

## Calibration & routing (preliminary — small sample)

Fitting a single global temperature to openJev's confidence against "matches cloud"
(`calibrate.py`): **T\* ≈ 3.0** (openJev is overconfident) — NLL 0.690→0.574; ECE raw
0.132 → 0.129 (broadly calibrated but needs flattening). Per-type, the reliable local
picks are the high-confidence ones:

| type | openJev coverage/agreement (conf ≥ 0.5 / ≥ 0.8) | routing |
|---|---|---|
| asked, countdown, effect, moment, steps, unit | 92–100% at every threshold | **LOCAL** |
| widget | 11/11 @0.55 · 7/11 @**0.86** | LOCAL at a high threshold (≥0.8), else cloud |
| theme | 7/8 @0.57 · 4/8 @**1.00** | LOCAL at a high threshold (≥0.8), else cloud |
| expr | 2/13 @1.00 · 0/13 @0.8 | CLOUD / plan (only 2 confident picks; weak coverage) |
| show | 4/13 @0.25 · 2/13 @0.5 | **CLOUD / plan** |
| arg, covers | 50% | **CLOUD / plan** |

**Caveat**: n = 2–13 per type — too small for a final threshold fit. This is the
*procedure + preliminary* numbers; §5.A calls for **200–500 labelled decisions per
task**, so re-run `calibrate.py` on the Phase 0 at-scale logs before trusting the
per-type thresholds. The routing split is already robust, though: the formula steps
(expr/show/arg) are clearly cloud/plan territory and the rest are local.

Routing recommendation (the §5.E call-site map, updated with this data):
- **LOCAL (openJev / Candle)**: `asked`, `effect`, `moment`, `countdown`, `steps`,
  `unit`, and the confident side of `widget`/`theme` (threshold ≥0.8).
- **CLOUD / plan (§5.D)**: `expr` (the formula), `show`, `arg`, `covers` — the
  reasoning picks a small encoder cannot do.
- Unchanged: code-reading (verify/claims) → cloud / compile-gate co-design.

## Conclusion

The data validates the **tiered design**: a local decision model (openJev via
Candle on-device) for the easy/judgment steps, **cloud/LLM (or the plan) for the
formula (`expr`/`show`/`arg`) and code-reading steps**, with **per-type calibration**
(§5.A) before the local answers are trusted. It also shows the standard-step
threshold must be re-fit, not reused, and that a generic 151M encoder is the wrong
tool for the formula picks — exactly what §3.2/§5.B predicted.

## Body size, state length and chunked on-device serving (2026-11-28)

Measured from bodies recorded on the phone with the new dev selector recording
(`--ps jevLocalLog 1`), on the host runner with the serving calibration
(T*=2.2, min_confidence 0.71).

**Where the tokens are.** Compose-route bodies carry a *short* state
(~300–950 chars: the request plus the sketch's parts) and heavy *questions* —
`arg`/`expr`/`effect`/`countdown` questions run 600–900 chars each, `expr` up to
30+ formula options. Condensing the state is therefore not the speed lever for
this route; the question/option text is (the capped input policy already
truncates options, and `state_tokens_dropped` is 0 on these bodies).
`state-condense.py` stays for the bodies that do carry a long state (agent-route
bodies with the section as code).

**The per-call token budget silently zeroes local serving on big sketches.** The
engine caps one call at 8192 tokens over all questions (`CALL_TOKENS`), checked
before any inference. A recorded 35-question body was rejected with
`call_token_budget`: the local tier answered 0/35 in ~4 s and the cloud covered
everything. The served-fraction metric now shows this as 0% instead of hiding it.

**Chunked serving (now in the hybrid route).** The route splits an over-budget
easy half in halves, recursively, and merges the replies; a rejected attempt
costs only its tokenization. The same recorded 35-question body, run as three
chunks on the host:

| | full body | 12/12/11 chunks |
|---|---|---|
| served locally | 0/35 (`call_token_budget`) | **13/35** (steps 5, written 5, arg 2, widget 1) |
| agreement with the cloud's answers | — | 8/13 (62%, n=13) |
| host forward time | 3 s (reject only) | ~576 s (~15 s/question at these option sizes) |

The same behaviour end-to-end on the phone: a workout-timer request whose sketch
asked 56 easy questions served **18/56 locally in 859 s** (written 4/4, steps
4/4, unit 4/5, arg 6/21) with the cloud covering the remaining 38 in ~6 s — a
run that, before chunking, answered 0 on-device and finished in ~15 s.

The 62% is one body and 13 decisions — well below the in-sample 94.4%, so the
per-type refit (§5.A) stays the gate for trusting what gets served. The wall
cost is the binding constraint: chunking fixes *coverage* on big sketches, and
the Metrics tab now shows both the served fraction and the time it cost, so the
NPU (§7.11) or better kernels remain what make big-body serving practical.
