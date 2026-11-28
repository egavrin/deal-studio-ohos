# Local Jev model on CPU vs cloud — fair, like-for-like report (2026-11-24)

Same bodies, same input, same machine, for both sides. This file **replaces** an earlier
version whose table was not apples-to-apples; the corrections are listed at the end.

## Method (what makes it like-for-like)

- **Same bodies**: 8 recorded compose fixtures → 112 questions (75 choice + 37 noul), identical
  for both sides. The body text (`state` + `questions`) is byte-identical.
- **Local = Laya, UNTRUNCATED, on the Kirin CPU** (Candle, the deployed model): budgets raised
  (`OPTION_PAYLOAD_LIMIT` 48→256, config `head_max_len` 256→1024), verified **112/112 questions
  with 0 tokens dropped** (previously 24/112 truncated).
- **Cloud = the JevProxy** (`askJevViaCloud`, the app's own cloud path, deepseek-v4.1-flash over
  the USB network) — run on the **same 112 questions on the same device**; all 112 answered,
  first attempt, no timeouts. **Secondary reference**: the **recorded cloud-Jev answers already in
  the repo** (`tools/vera-harness/compose/<name>/jev-answer.json`, `"model":"jev-1.13.0"`) on the
  same 75 choice questions — **static data from a prior run, not a live call**; the fixture records
  only the model id, so it is shown as "recorded cloud Jev (jev-1.13.0)", not as any vendor.
- All runs on the engineering Mate 70 (Kirin 9010 CPU).

## What this measures — and what it does not (honest scope)

The **local answers here are the model's *diagnostic* decisions**: Laya was run with
`local-laya --diagnostic-scores` and the per-option logits softmaxed → argmax. At the
time of this table the app's local backend returned empty for this **uncalibrated**
model, so the *running app* fell back to the cloud; this report compared the
**model's capability** against the cloud, not the shipped behaviour.

**Update (same day, later): the local model now serves in the running app** — this
report's capability numbers describe the live behavior, not a diagnostic-only what-if.
The serving calibration was fitted from this very data (temperature T\*=2.2,
min_confidence 0.71, `tools/local-jev/eval/laya-calibrate.py`): 18/109 questions served
at 94.4% agreement, in-sample; `expr`/`show` questions are cloud-tiered outright (this
table's sharp disagreement types), and the cloud covers whatever the calibration
declines. Build, deploy and the on-device serving state: `build.md`.

The cloud side is the app's **live JevProxy** (its stored DashScope key, the normal cloud path);
the 52% reference is the repo's **recorded `jev-answer.json` fixtures** (static, `jev-1.13.0`) —
no live TypeSafe call.

## Decision agreement (local vs cloud) — agreement, not accuracy

| type | local vs **JevProxy** (n) | local vs **recorded cloud Jev (jev-1.13.0)** (n) |
|---|---|---|
| `steps` | 12/13 | 12/13 |
| `asked` | 23/30 | 3/4 |
| `arg` | 10/14 | 1/4 |
| `widget` | 5/11 | 4/11 |
| `show` | 7/13 | 8/13 |
| `theme` | 4/8 | 6/8 |
| `expr` (the formula) | **1/13** | **1/13** |
| `covers`/`effect`/`moment`/`countdown`/`unit` | 0/2·1/2·1/2·1/2·2/2 | 0/2·1/2·1/2·1/2·1/1 |
| **overall** | **67/112 = 59.8%** | **39/75 = 52.0%** |

(This is *agreement*, not correctness — neither side is ground truth; the JevProxy is an LLM
proxy, so it is not the real cloud Jev. Local agrees \~52–60% with the cloud depending on which
cloud, and the disagreement is concentrated in `expr`.)

## Time per decision (same device, Mate 70)

| | one decision | batched / throughput | conditions |
|---|---|---|---|
| **local (Laya, device CPU)** | **~1.5 s** on these short fixture bodies; **~5 s** on real compose bodies (measured in the hybrid run; the sequences fit well under the 1024 cap — halving it changed the time ~3%) | serial: N × that | offline, deterministic |
| **cloud (JevProxy, device)** | ~1.75 s (one LLM call; `stopwatch` 1752 ms / 1 q) | **~0.42 s/decision amortized** (112/112 in this run, batched 4-way, `max_tokens=5`) | network-dependent, variable |

- **Single decision**: local ~1.5 s ≈ cloud ~1.75 s — comparable.
- **Throughput**: the cloud batches (`JEV_CONCURRENCY=4`) with tiny outputs, so it amortizes to
  ~0.42 s/decision — **faster than the serial local forward (~1.5 s)** for many decisions.
- **Variance is the cloud's weakness**: this run answered 112/112 cleanly, but an earlier probe
  hit a **20 s timeout** on the USB-network relay. Local has no network and no tail.

## Honest corrections to the earlier (unfair) table

1. **"Local 311 ms" was host CPU** (x86 ORT), not the phone. On the **device** it is **~1.5 s**.
2. **"Cloud 0.8–2.1 s" mixed a 3-question batch wall** with a per-decision number. Cleanly: one
   cloud decision ≈ **1.75 s**; batched amortized ≈ **0.42 s/decision**.
3. **The truncation did NOT bias the result.** I earlier implied 21% truncation understated Laya.
   Untruncated, local-vs-recorded-cloud-Jev is **still exactly 39/75 (52.0%)** with identical per-type —
   so untruncation is **decision-neutral**; the truncation was benign.
4. **"Cloud" is not one thing.** Local-vs-recorded-cloud-Jev (`jev-1.13.0`) is **52.0%**; local-vs-JevProxy
   (the app's proxy) is **59.8%**. Both are reported; the JevProxy is not ground truth.

## Findings

- **`expr` (the formula) is the sharp, unambiguous disagreement** — 1/13 vs both clouds. It must
  stay on the cloud/plan; a small local model picks a different formula almost every time.
- **`steps` (12/13) and most structural asks agree** — the local model tracks the cloud on the
  structural decisions.
- **Local carries the offline structural layer; the cloud carries the formula + code-reading.**
- **Calibration**: both overconfident on wrong picks (logit-softmax confidence; earlier
  measurement ~0.6 on wrong), so per-type thresholds are still required before trusting local.
  The serving fit that now exists (T\*=2.2, threshold 0.71) is the *global* temperature +
  agreement threshold from this data — in-sample, n=109 — not the per-type refit
  (`replacement-analysis.md` §5.A) that the plan calls for; re-fit at scale before trusting
  the thresholds, and the `expr`/`show` cloud routing is
  what carries those types in the meantime.

## Caveat

75 choice / 112 total, n = 1–30 per type — enough for the routing split and the `expr`-vs-rest
contrast, not for final thresholds; JevProxy ≠ ground truth. Re-run at scale for final thresholds.