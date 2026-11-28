# Local Jev on CPU vs NPU vs cloud — the E2E generation pipeline data (2026-11-27)

Three backends for the same work — the Jev decision questions of a real generation —
measured end to end and at each layer, on the engineering **Mate 80 Pro Max
(Kirin 9030, HiAI 109.636.120.010)**, same prompt ("a tip calculator with bill, tip
percent and people, showing the total"), same hybrid route with per-question cloud
fallback. The NPU numbers come from the serving path landed in commit 3e4973c:
the Rust engine routes `infer_group` through an in-process HiAI forward when the
fixed-shape batched graph (`hiai-gen.py --batched 8 --seq 256`, 278 MB) is
registered, and candle serves otherwise. The graph is offline-exact against the
numpy reference (22-layer logits Δ 0.002; §7.11 of the analysis).

**What this file is for**: the decision data behind "is the NPU path a win?" The
one-line answer is at the end; the honest version is that the raw forward is 4×
faster and the *pipeline* is not — yet — and both facts are in the tables below.

## 1. Correctness

### Logit level — how far each backend sits from the exact spec

The **numpy reference** (`tools/local-jev/eval/laya-numpy-ref.py`, parity-validated
against Candle on all 8 fixture bodies) is the portable spec of the model.

| comparison | worst logit Δ | measured |
|---|---|---|
| **NPU graph vs reference** | **0.002** | offline, 22-layer batched graph, host scorer on the graph's hidden states |
| **candle CPU vs reference** | **0.12–0.39** | host validation, all 8 fixtures (numerical drift of the CPU forward) |
| NPU vs candle (calibrated confidence) | −0.003 | device, the fixed spike body, back to back |

The NPU graph is structurally exact (same op order as the reference; the only new
noise is F16 weight storage + the NPU's internal FP16 compute). Candle's own drift
from the spec is ~100× larger than the NPU's, so NPU-vs-candle behavior is
dominated by candle's numerical drift, not by the F16 rounding.

The three-way on one fixed body (the LocalJevSpike tip-calculator, all three rows
measured on 2026-11-27):

| backend | expr.total logits (formula, row) | calibrated confidence | serves (≥ 0.71)? |
|---|---|---|---|
| numpy reference | (−0.794, −3.316) | 0.7588 | yes |
| candle CPU (host, same engine) | (−0.763, −3.269) | 0.7574 | yes |
| NPU device (FP16 through the graph) | — (log truncated; confidence comparable) | **0.7546** | yes |

### Decision level — what the pipeline actually serves

| backend | local answered / body questions | runs |
|---|---|---|
| candle CPU | 8/16, 6/16, 6/16, 5/15 | 4 hybrid generations across sessions |
| NPU | 7/15, 5/15 | 2 hybrid generations (2026-11-27) |
| cloud (glm-5.2) | the rest — it is the target the calibration was fitted against | every run |

**The within-candle variance (5–8 answers on the same class of body) is larger
than the NPU-vs-candle difference.** Only questions whose calibrated confidence
sits within ~0.005 of the min_confidence 0.71 boundary can flip between the
backends. The boundary case measured on the fixed body: `unit.bill` — reference
confidence 0.7130, candle 0.7087 (just below the threshold — does not serve).
The NPU's ±0.003 shift flips exactly this class of question; it is the noise
floor, not a bias.

Every hybrid generation (both backends) produced a correct, compiled, rendered app.

## 2. Time

### The raw forward — the model only, no pipeline

| | one question | throughput | notes |
|---|---|---|---|
| **CPU (candle, F32)** | **~5 s** | ~0.2 q/s | rayon-parallel, ~5.3/8 cores, ~4 GFLOPS effective; measured over 16-question real bodies |
| **NPU, single question** (seq 108) | **1.24 s** | ~0.8 q/s | 22-layer, F32 storage; build 2.6 s + init 2.5 s once |
| **NPU, batched** (B=8, S=256) | 7–14 s / batch | ~0.6–1 q/s amortized | the fixed-shape serving graph; build 2.1–2.6 s + init 3.7–6.5 s once per process |
| cloud (glm-5.2, device Wi-Fi) | — | 1–4 q/s | batched: 6 questions 1.7–3.7 s, 10 questions 2.3–8.9 s; network-dependent |

**Raw forward: the NPU is ~4× faster than the CPU.** The 2-layer graph runs in 34 ms
— the per-layer scaling says the NPU compute itself is not the constraint at these sizes.

### The E2E Jev phase — what the generation pipeline actually spends

From the hybrid generation runs (`Model` = the LLM sketch/compose calls; `Jev` = the
whole decision phase: local forward + the cloud batch for the questions the
calibration declines + the fallback round trip):

| | Jev phase | Model phase | total generation |
|---|---|---|---|
| **All-cloud** (no local model) | — | — | **~11 s** |
| **CPU hybrid** | 86.4 s | 4.4 s | ~91 s |
| **NPU hybrid** (first generation in a process) | **94.8 s** | 4.5 s | ~95 s |

Cloud Jev batches observed during these runs (glm-5.2 over the phone's Wi-Fi): 6
questions in 1.7–3.7 s; 10 questions in 2.3–8.9 s.

**The NPU E2E is currently ~8 s slower than the CPU E2E, despite the 4× faster
forward.** The decomposition of the local phase (82 s in the cold NPU run):
fixed-shape padding waste — every batch runs the full 8×256 slots while the
questions average ~150 tokens; first-run costs — the engine construction, graph
compile (~2.1 s) and init (~3.7 s) once per process; and the cloud fallback
latency, which dominates both hybrid rows equally. The warm-process steady state
(a second generation with the compile cached) was never measured — the first
generation includes all one-time costs, and every E2E run so far was a fresh
process.

## 3. Size

| build | HAP | model storage |
|---|---|---|
| CPU | 284 MB | 161 MB Q4 gguf (embedded) |
| NPU | 547 MB | + 278 MB graph rawfile (F16 weights + F32 LN gamma/beta) |

## 4. What the cloud comparison means here

The cloud "backend" in the pipeline is glm-5.2 through the app's JevProxy — the
same path the calibration was fitted against (the recorded cloud answers, n=109).
It is the reference for *agreement*, not ground truth (`cpu-vs-cloud.md` keeps the
agreement data: overall 59.8% vs the proxy, `expr` 1/13 — the formula type is
cloud-tiered by the routing check). In throughput terms the cloud wins on speed
(~11 s all-cloud vs ~90 s hybrid) but loses on availability: no network, no local
answers. The hybrid's value is offline capability; the NPU was supposed to be the
speed lever on top of that.

## 5. The honest verdict

- **Correctness: NPU ≈ CPU.** Both flow through the same calibration; the NPU is
  *closer* to the spec than candle is; boundary questions flip in both, within the
  same run-to-run variance.
- **Raw speed: NPU 4× faster** (1.24 s vs 5 s per question, and the gap widens with
  batching).
- **Pipeline speed: NPU not yet a win** — the fixed-shape batched graph pays S=256
  for S≈150 questions, and the first-run compile/init is not amortized across
  generations yet.
- **Cloud remains the throughput king** — and remains unavailable without network.

## 6. Where the time actually goes — the full Jev phase decomposition

The ~86–95 s Jev phase is not one cost. `batch_len()` sorts questions by
length and creates groups that limit extra attention work to 25%; for a
typical 15–16-question body the result is **six sequential groups**, routed
as follows:

| group | questions | route | est. time | why |
|---|---|---|---|---|
| 1 | 8 (122–133) | NPU B=8 S=256 | 11–14 s | 44% padding waste (real avg 128 of 256) |
| 2 | 5 (137–151) | NPU | 7–11 s | 3 empty slots wasted |
| 3 | 3 (183–191) | NPU | 7–11 s | 5 empty slots wasted |
| 4 | 1 (266) | **candle** | ~5 s | exceeds S=256 → fallback |
| 5 | 1 (412) | **candle** | ~7 s | longer, candle scales with length |
| 6 | 1 (587) | **candle** | ~10 s | longest |

Plus: engine construction 6–10 s (gguf + graph, once), tokenization 1–2 s,
hard-tier cloud batch 2–15 s (runs *before* the local), fallback cloud
batch 2–9 s (runs *after*). Total: **65–98 s** (matches the measured
86.4–94.8 s).

**The cloud does the same 15–16 decisions in ONE batched LLM call** (glm-5.2,
concurrency 4, max_tokens 5): 2–9 s total. The gap is 8–30×.

### Three structural reasons the cloud wins

1. **One call vs six sequential groups.** The cloud batches everything; the
   local must iterate groups because attention is quadratic and the grouping
   limits waste within each group.
2. **Fixed-shape padding.** S=256 for questions averaging ~128 tokens —
   44% of the compute is on zeros. The cloud has no padding.
3. **Long questions fall back to candle.** 3 of 16 questions (266–587
   tokens) exceed the graph's S=256; the candle fallback costs 15–22 s for
   those three alone.

### Is the data reasonable?

Yes. The numbers are consistent across runs, the decomposition adds up, and
the per-question costs match the raw FLOP analysis: 21 GFLOP per question ÷
~4 GFLOPS CPU = ~5 s (candle); ÷ ~15–20 GFLOPS NPU = ~1.4 s (raw forward);
~5 s in the pipeline (all overheads). The cloud's ~0.4 s/decision amortized
matches its measured batch timings.

### The fundamental floor

The NPU delivers ~15–20 GFLOPS effective at the fixed shape. At 21 GFLOP
per question and 15 per body, the minimum forward is ~15–20 s even with
zero overhead. The cloud's datacenter GPU does the same work in ~2 s. **The
NPU cannot close the gap for speed — its value is offline.** The honest
strategy: run hybrid when offline, all-cloud when online.

## 7. The optimization levers, quantified

| optimization | saving | effort | expected Jev phase |
|---|---|---|---|
| **Bucketed shapes** (S=128/192/256, each compiled + persisted) | removes ~50% of padding waste → forward 36→20–25 s | medium | 65–75 s |
| **Dynamic shapes** (`DynamicShapeConfig`, exists, untested) | removes all padding → forward 15–20 s | one probe | 50–60 s |
| **Parallel hard-tier + local** (concurrently) | saves the hard-tier time (2–15 s) | small | minus 2–15 s |
| **Skip candle for long questions** (extend graph or dedicated) | saves 15–22 s | medium | minus 15–22 s |
| **All of the above** | combined | all | **~40–50 s** |

**Model persistence** (implement 78459fe): saves the compile on cold
starts (~2.1 s) — verified working on device (save→restore→run) but small
relative to the total. The init cost (3.7–6.5 s) remains either way.

**Bucketed shapes — implemented, and the result is honest and negative
so far** (commit ebe7f73): the registry now takes multiple (path, batch,
seq) graphs, `infer_group` picks the smallest bucket that fits and
compiles lazily (persisted). The hard tier runs concurrently with the
local forward. S=192 B=8 replaced S=256 B=8 in the test build. Measured
E2E (same prompt, two runs): local phase ~79–81 s vs the S=256 baseline's
73–84 s — **flat within noise**. The expected ~14 s padding saving did
not demonstrate; either the NPU per-batch cost is not shape-proportional
at these sizes (fixed runtime overheads dominate), or the single-run
noise (cloud batch variance ±10 s) masks it. Resolving it needs per-batch
trace timing (LOCAL_JEV_TRACE prints to stderr, invisible on device) or
the model-test harness on the S=192 graph — both still to do.

**Warm-process amortization** — the compile + engine construction are once
per process; the second generation in a warm process skips them. Never
measured (the result screen has no back navigation; would need a "New"
button).

## Scope and honesty notes

- Two NPU hybrid runs, four CPU hybrid runs — the E2E totals are single-run
  observations, not averages; the variance table (within-candle 5–8/16) shows the
  noise floor of the served counts. The logit-level numbers are deterministic
  (offline) and reproducible.
- The NPU numbers are the *first working integration*, not an optimized one; the
  fixed-shape design was chosen to get a proven end-to-end path (one graph, one
  compile, any body) before optimizing shape selection.
- The NPU path was verified on ONE device (the Mate 80 Pro Max). The eng Mate 70
  (HiAI 106) and the retail Mate X6 (HiAI 107) need a re-run with the bool-attr
  fix — the original "blocked" verdicts there were the same attr-type bug (§7.11).
- `localJev.diagnosticScores(body)` is the tool for paired logit A/Bs of
  backends on device; the comparison above used it once (the spike), not per body.
- **Model persistence** (save the compiled graph to filesDir, restore on the
  next cold start) is implemented and verified on device (commit 78459fe):
  build→save→restore→run works; the timing improvement is ~2.1 s (the
  compile) — small relative to the total. The init cost (3.7–6.5 s) remains
  either way, so persistence alone does not change the E2E verdict.

Sisters: `cpu-vs-cloud.md` (the CPU-vs-cloud agreement data this file builds on),
`replacement-analysis.md` §7.11 (the NPU breakthrough and constraint history),
`build.md` (the CPU build), the E2E NPU landing commit 3e4973c.
