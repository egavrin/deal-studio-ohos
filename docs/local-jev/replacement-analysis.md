# Replacing cloud Jev with an open-source System-one model

Analysis and proposal. Built and verified end to end on the phone: PR #62's Rust/Candle
Laya runner as the on-device NAPI backend (`liblocaljev.so`), wired through the hybrid
route (`askJevViaLocal`, hard tier → cloud, per-question cloud fallback) and serving
real decisions in real generations under a fitted calibration (§6.5's addendum, and
`build.md`). §7 covers the additional work to target the phone's NPU.

> **Bottom line.** Cloud Jev is a non-autoregressive, RLCD-calibrated *decision* model — it
> reads a state plus schema-bound questions and returns typed answers with calibrated
> probabilities, never text. A verified open-source class of exactly this now exists, and
> independent benchmarks (JevBench) show **where the accuracy cliff is**: a **74M** model
> already matches hosted Jev on *easy* decisions (83% vs 88%); a **151M model is the best
> single-medium default** (easy 86%, standard 66%); a **421M** encoder lifts *standard* to 73%
> but **no encoder ≤421M beats chance on hard / code-reading decisions** (all at 33–38%; a 4B
> decoder reaches ~70%).
>
> So the plan is **tiered by task class**: one ~151M decision model covers the easy/standard
> steps (1–7, 10) as a near-drop-in via `askJevViaLocal`; the retrieval-like sites (intent,
> align) can use the in-repo **embeddings**; the **hard code-reading steps (verify/claims,
> 8/9) need a 4B+ decoder, the cloud, or the co-design that removes them** (the compile/smoke
> gate). Tiering pays off **by task class (a static map), not by confidence.** On an 8–12 GB
> phone, **RAM is not binding** (151M ≈ 150 MB INT8); the binding costs are **first-load/compile
> time, thermal throttling, and calibration transfer**, so thresholds must be re-calibrated.
> Open decisions are in §6.4.
>
> The earlier "small LLM + SetFit + embeddings" plan is superseded for the decision steps; it
> is kept only as fallback context (§3.3).

---

## 1. Jev in the Vera pipeline

**Jev** is "TypeSafe System One" — a hosted, *calibrated decision model* at
`api.typesafe.ai/v1/systemone` (`JevSelector.ets`, `VeraCompose.ets:4751`). It is the
workhorse *decision* model of the compose path, distinct from the *generation* model
(DeepSeek/cloud chat) that writes plans and code. `docs/agent.md` puts it plainly: each live
run of the 121-prompt bench makes **several hundred Jev calls** (~2–5 batched round trips per
prompt).

### 1.1 The contract (`JevProxy.ets`)

One Jev round trip carries a **batch of independent questions** over a shared `state`, and
returns one answer per question:

```
request:  {"model":"jev-latest","state":"<context>","questions":{
  "<key>":{"type":"choice","instructions":"...","criteria":{"<opt>":"<desc>",...}},
  "<key>":{"type":"noul","instructions":"..."}
}}
response: {"answers":{"<key>":{"choice":"<opt>","confidence":0.62},
                      "<key>":{"noul":0.71}}}
```

The repo uses two question types (Jev also exposes `score`, unused here):

| type | semantics | output |
|---|---|---|
| `choice` | pick exactly one of N options (N usually 2–8), each a one-line description | chosen option key + a **calibrated** confidence 0..1 |
| `noul` | a yes/no probability (A=yes, B=no) | a **calibrated** probability 0..1 |

Callers apply **thresholds** to the confidence/probability (`PICK_ABOVE` 0.25,
`FORMULA_ABOVE` 0.4, `READY_ABOVE` 0.5, `LIVE_ABOVE` 0.65, `KEEP_ABOVE` 0.2, …). Calibration
is therefore not cosmetic — the thresholds were tuned against Jev's probability distribution.

### 1.2 The two current implementations

1. **Cloud Jev** (the real TypeSafe endpoint) — one HTTP round trip per batch, 70–500 ms.
2. **JevProxy** (`--ps jevProxy 1`, `askJevViaCloud`) — the LLM-*simulated* Jev: one short
   chat-completions call **per question** (temperature 0, max_tokens 5), asking the model to
   "reply with only the letter", reading confidence from **top-token logprobs** renormalised
   over the option letters, concurrent 4 at a time. Its own header warns it is "only
   calibrated-ish — tends to be overconfident"; the argmax fallback returns confidence 1.0,
   which the thresholds were *not* tuned for.

### 1.3 The single integration point

Both implementations route through one function, `askJev(body, apiKey)` in
`VeraCompose.ets`: `useJevLocal()` adds the hybrid local branch (§6), `useJevProxy()`
selects the cloud-LLM proxy, else the real TypeSafe endpoint. **`selectEdit`
(`VeraComposition.ets:495`) is *not* behind this switch** — it calls `askJevViaCloud`
(the cloud-LLM proxy) directly, so it neither reaches TypeSafe nor the local route. The
local route therefore covers the `askJev` call sites — the agent flow (`AgentAlign`,
`AgentClaims`, `AgentQuestions`, `AgentAppHost`, `VeraAgent`'s slot requests) — and
**wiring `selectEdit` in is a follow-up**, not something the seam already gives.

### 1.4 Local precedent already in the repo

- `findSdkFunctionByEmbedding` / `findIntentFunctionByEmbedding` /
  `findUiComponentsByEmbedding` (`VeraSdkEmbeddingCache`, `VeraIntentEmbeddingCache`,
  `VeraUiIndex`) rank SDK targets / intents / UI components by **cosine similarity** of a
  llama.cpp embedding of the "need" string, with a keyword fallback. (A separate call path
  from Jev — retrieval, not the composer's decisions — and the basis for §5.E's "Tier A".)
- `LlamaEngine.ets` exposes `llamaInit`/`llamaGenerate`/`llamaStop`/`llamaFree`
  (`libllama.so`) — on-device inference infrastructure already exists.

---

## 2. The ten decision steps

### 2.1 What each step decides

| # | step (call site) | decides | type | N | threshold | input complexity | judgment kind |
|---|---|---|---|---|---|---|---|
| 1 | intent domain (`JevSelector.ets`) | which intent catalogue domains to load | noul (per domain) | 2 | `KEEP_ABOVE` 0.2 (asymmetric: err wide) | low (request only) | retrieval-ish (topic match) |
| 2 | blocking questions (`AgentQuestions.ets` `blockingRequest`) | which plan questions to ask the person | noul/choice | 2 | `ASK_ABOVE` 0.6 | medium | judgment |
| 3 | part-or-section (`NeedsChoose.ets` `buildChooseRequest`) | per need: part vs catalogue section; whose data; needs search? | choice | 2–4 | `READY_ABOVE` 0.5 | medium | judgment + retrieval |
| 4 | compose (`VeraCompose.ets` `buildComposeRequest`) — the big one | theme; widget per input; asked/added; formula per value (`expr`/`steps`/`written`); effect+moment per event; section per ready need; covered; live yes/no; whose; real-data; unit; deadline; arg | choice + noul | 2–8 | 0.25–0.7 (varied) | medium-high | mixed (formula = reasoning) |
| 5 | align (`AgentAlign.ets`) | per leftover need: a ready-made section or none | choice | N sections | `ALIGN_ABOVE` 0.5 | medium | retrieval (section↔need fit) |
| 6 | live figure (`VeraCompose.ets`, in compose) | is this need a live figure of the real world? | noul | 2 | `LIVE_ABOVE` 0.65 | low-medium | judgment |
| 7 | slot fill (`VeraSectionCompose.ets` `buildSlotRequest`) | what each chosen section offers, read from the request | choice | varies | per-call | medium | judgment (extraction) |
| 8 | section verify (`AgentCustom.ets` `verifyRequest`) | does the written section actually do each need? | choice/noul | 2 | `DOES_ABOVE` 0.5 | **high (reads generated code)** | **code reading** |
| 9 | claims (`AgentClaims.ets` `verifyRequest`) | does the assembled screen already do what a section claimed? | choice/noul | 2 | per-call | high (reads assembled screen) | **code reading** |
| 10 | structural edit (`VeraComposition.ets` `buildEditRequest`/`selectEdit`) | which edit (add/remove/move/swap a block) | choice | 4 | per-call | medium | judgment |

### 2.2 What the decision model must satisfy (cross-cutting)

- **Latency.** ~2–5 batched round trips per prompt; cloud Jev is 70–500 ms/round trip,
  JevProxy one cloud call per question. A replacement must not regress generation speed.
- **Calibration.** Every answer is threshold-gated; thresholds were tuned to Jev's
  distribution, so either match it or re-calibrate (§5.A).
- **Determinism.** temperature 0; the same request must give the same pick.
- **Short input, single answer.** ~100–300 tokens in, one option/probability out.
- **Closed, enumerable option spaces.** Catalogue sections, parts, effects, formula templates,
  edit kinds — a closed set.

### 2.3 The three kinds (a risk lens, not an architecture)

**retrieval-like** (1, 5, the section pick of 4), **judgment/classification** (2, 3, 6, 7, 10,
the formula/effect parts of 4), and **code reading** (8, 9). This is a **risk gradient**: 1–7
and 10 are "easy/standard" decisions a small encoder handles; 8/9 are hard decisions no small
encoder handles (§3.2). It does not imply three mechanisms — §5 assigns each call site the
cheapest mechanism that clears its tier.

---

## 3. Open-source model survey

The task is **calibrated selection over a small closed option set**, not generation. The
survey found a purpose-built open-source class (§3.1), established the capability cliff by
size (§3.2), confirmed what does *not* exist (§3.3), and catalogues older fallbacks (§3.4).

### 3.1 The finding: purpose-built System-one decision models

**What Jev is (verified):** a non-autoregressive model that reads a `state` + schema-bound
questions and returns typed probabilistic decisions (`choice`/`score`/`noul`) in one forward
pass — no text generation. Trained via **RLCD** (Reinforcement Learning for Calibrated
Decisions) with strictly proper scoring rules. ~100× faster than an LLM because it never
autoregresses. A *generative* decoder instead pays **prompt prefill** (~0.6–2.5 s on phone
CPU for ~256 tokens), even with KV-cache reuse ~0.2–0.5 s/question — slower than cloud Jev.
This is why a decision model, not a small LLM, is the right replacement.

**Verified open-source decision models** (corrected against the Aug-2026 landscape; measured
phone latencies are on a Galaxy S26 / LiteRT where noted):

| model | params | measured latency | licence | notes / caveats | source |
|---|---|---|---|---|---|
| **openJev 151M** (`heman10x/rlcd-modernbert-151m`) | 151M | ~30–60 ms GPU/NPU (est.); 280 ms desktop CPU | Apache 2.0 | the runnable 151M System-one checkpoint (the "Verdict 2.0" weights are unreleased); RLCD-inspired CE+Brier, per-cardinality temperature; **the recommended single default** | [github](https://github.com/Heman10x-NGU/openJev-verdict-2.0), [HF](https://huggingface.co/heman10x/rlcd-modernbert-151m) |
| **Laya** (Convai) | 421M English, 322M multilingual, + typed-decisions | **84 ms NPU / 127 ms GPU** (256 tok); 5–12 s first load | Apache 2.0 | best easy+standard accuracy; **no published 150M checkpoint**; degrades past ~20 options; 512-token context | [HF](https://huggingface.co/convaiinnovations/laya), [LiteRT](https://huggingface.co/litert-community/laya-LiteRT) |
| **GLiNER2.5-Decide** (Fastino) | **486M total** (340M non-embedding) | 28.6 ms NPU / 41 ms GPU FP16 (128 tok) | Apache 2.0 | supervised/decision-tuned (not RLCD); strong easy, not a reasoning model | [HF](https://huggingface.co/fastino/GLiNER2.5-Decide) |
| **Von** (wfzyx) | 395M ModernBERT | sub-15 ms vendor | Apache 2.0 | **ARCHIVED**; README points to `LiquidAI/d1-omni-600M`; collapses out-of-distribution (26.7% on unfamiliar domains) | [github](https://github.com/wfzyx/von) |
| **Cloudflare Clef / Clef-flash** | **9B (flash) / 27B** — Qwen-based | 38.8 ms vendor hosted / 695 ms independent | Apache 2.0 | **hosted, not on-device**; the *open cloud/edge replacement* for api.typesafe.ai, not a phone model | [blog](https://blog.cloudflare.com/clef-decision-models/), [HF](https://huggingface.co/Cloudflare/clef) |
| StartLux-Decision | 0.8B–27B | 0.8B edge-feasible | **CC BY-NC (weights)** | RLCD²; **non-commercial** — exclude without a separate licence | [github](https://github.com/StartLuxLabs/StartLux-Decision) |
| Liquid AI d1-omni-600M, GLiNER2.5-small (74M), OpenDecider, d1 | 74M–600M | edge-feasible at the small end | varies (some Apache 2.0) | more family members; verify before committing | (survey) |

Also: **CLM-8B** (Stanford+NVIDIA, Apache 2.0) — contrastive, 9× faster than Jev but
**explicitly lacks calibrated probabilities**, confirming calibration is the hard part.

### 3.2 The capability cliff by size (the decisive evidence, JevBench v1.2)

Independent JevBench tier accuracy (easy / standard / judge / hard; chance on hard ≈30–35%):

| system | params | easy | standard | judge | hard (code/reasoning) |
|---|---:|---:|---:|---:|---:|
| hosted Jev (reference) | — | 87.6 | 83.9 | 83.6 | **73.4** |
| Laya | 421M | 94.4 | 72.9 | 69.2 | 34.1 |
| openJev | 151M | 86.1 | 65.6 | 61.0 | 38.2 |
| GLiNER2.5-small | 74M | 83.3 | 47.9 | 50.0 | 33.2 |
| reflex (decoder) | 4B | 86.1 | 87.5 | 68.7 | **70.3** |
| Winnow (decoder) | 12B | 82.2 | 98.2 | 82.1 | 71.9 |

Reading it:

- **Easy is saturated by 74M** — a 74M classifier is only ~4 pts behind hosted Jev, and Laya
  beats Jev on easy. Simple binary/lexical decisions do **not** need 150M+.
- **Standard is where size pays** — 74M 48% → 151M 66% → 421M 73% → Jev 84%.
- **Hard is a wall for every encoder** — 74M, 151M and 421M all land at 33–38% (chance).
  **A bigger encoder does not buy reasoning.** A 4B decoder jumps to ~70%; 12B to ~72%;
  27B-with-thinking to ~83%.
- **Corollary for Vera:** `code reading` (steps 8/9) is in the hard tier — **no encoder
  ≤421M can do it**; it needs a 4B+ decoder or the cloud, or the co-design that removes it
  (§5.D). The formula/unit/arg sub-questions of step 4 are standard-to-hard — risky for a
  small encoder, a reason to keep step 4 on the 151M default and measure carefully.

Tiny-encoder ladder for the truly simple decisions (GLUE, Ettin series): 17M ≈ 79, 32M ≈ 84,
68M ≈ 87, MiniLM-33M ≈ 85 — so "does the request mention a camera?" is a 17–74M question.

### 3.3 Confirmed gaps (what does *not* exist open-source)

- **Speculative-decoding draft models** (EAGLE/Medusa/REST/Lookahead) — predict *tokens* for a
  target LLM (and need its hidden states), not semantic choices. Not a Jev replacement.
- **MoE gate networks** — route tokens to experts, not semantic choices (Grouter is the only
  decoupled one; still token-level). Not reusable.
- **Pre-Jev reward/verifier models** — output scalar scores, not calibrated choice/noul
  distributions; no typed-decision API.
- **No trained decision checkpoint below ~69M** — below that it is a general tiny encoder plus
  a logistic/classification head, not a System-one model.

### 3.4 Fallback / repurposed families (superseded for the decision steps, kept for gaps)

| family | examples | latency | fit | caveat |
|---|---|---|---|---|
| small decoder LLM | Qwen3-0.6B/1.7B (Apache), Phi-4-mini (MIT), Gemma-3, Llama-3.2, SmolLM2 | ~0.2–0.5 s/question | **hard tier** (4B+ needed for code/reasoning) | prefill; letter-logprob overconfident |
| encoder classifier | SetFit on MiniLM/MPNet (~110M, 8/class), DeBERTa-v3-base (86M) | ~10–20 ms | closed-set choice | supervised; one per type; no code reading |
| tiny encoder | Ettin-17M/32M/68M (MIT), MiniLM-L6 22.7M, MobileBERT 25M, DistilBERT 67M | 20–64 ms | trivial binary/lexical | encoder + head; needs labels |
| embedding rerank | extend `VeraIntentEmbeddingCache`/`VeraSdkEmbeddingCache` | ~10–50 ms | retrieval-like choice | weak on reasoning |
| rules | XGBoost on lexical features; keyword rules; pre-filters (`timerMayTakeCountdown`, …) | <1 ms | keyword-driven `noul` | brittle |
| calibration | temperature/Platt/conformal (TS4CP, ICML 2025) | — | any model | vendor ECE ≠ your ECE |

---

## 4. Fit per decision step

Mapping the §3.2 cliff onto the ten steps — **the encoder covers easy/standard; code reading
goes elsewhere**:

| step | tier | freq | cheapest mechanism | risk |
|---|---|---|---|---|
| 1 intent domain | trivial | ~10 | **embeddings / rules** (in-repo); 74M encoder if labels change | low |
| 2 blocking questions | standard | low | 151M model | low |
| 3 part-or-section | standard | medium | 151M model | low |
| 4 compose (formula/effect/widget/section/live/…) | standard→hard | **high** | 151M model, one batch; **measure the formula/unit/arg sub-questions** (standard-to-hard) | medium |
| 5 align | retrieval | medium | 151M model or **embeddings** | low |
| 6 live yes/no | standard | low | 151M model | low |
| 7 slot fill | standard | low–medium | 151M model | low–medium |
| 8 section verify (reads code) | **hard** | low | **4B+ decoder or cloud** (no encoder works); or co-design §5.D | **high — the real risk** |
| 9 claims (reads screen) | hard | low | 4B+ decoder or cloud; or §5.D | high |
| 10 structural edit | standard | low | 151M model | low |

So: **one 151M model serves steps 1–7 and 10** (with embeddings for the retrieval-ish 1 and 5);
**steps 8/9 are not encoder-addressable** and must escalate (§5.B) or be co-designed away
(§5.D).

---

## 5. Co-design: what to change beyond the drop-in

A bare drop-in runs but is not *sound*: the pipeline is shaped around cloud Jev's semantics in
two places — the **thresholds** (tuned to Jev's distribution) and the **tiering of questions**
(a 151M encoder is excellent easy, fine standard, at-chance hard). Six moves; A and B are the
soundness must-haves, E is the resource/tiering answer to the phone question.

### A. Calibration alignment — *soundness, mandatory*

Re-fit the ~15 threshold constants per decision type on the local model's distribution, using
logged cloud-Jev outcomes as the reference (Phase 0 set). Vendor ECE does not transfer
(Laya base ECE 0.466 → 0.081 after per-type temperature refit; Von/Certo degrade OOD). Budget
**200–500 labelled decisions per task** to fit temperature/Platt and validate the gate; if you
cannot label, do not automate on confidence. **Quantize weight-only (FP16 / Q8 / weight-only
INT8), keep the head in FP32** — dynamic INT8 collapsed Laya from 76.7% to 65–69%, while
weight-only INT8 changed **0/116** answers. Treat INT4 as experimental (unvalidated ECE).

### B. Escalate the hard tier — *soundness, highest value*

Steps 8/9 (and any low-confidence step-4 reasoning question) are **hard-tier**: no encoder
≤421M helps (§3.2). Escalate them to a **4B+ decoder or the cloud**, not to a bigger encoder.
Two shapes, chosen by the §6.4 decision:
- **hybrid**: local 151M for 1–7,10; cloud (TypeSafe or open Clef-flash) for 8/9 — the routing
  already supports per-call fallback;
- **pure-local**: local 151M + a 4B Q4 decoder for 8/9 (feasible but memory-tight: 2.3–2.6 GB
  Q4 alongside the app).
A **static task-class map** decides the tier — **not** a dynamic confidence router (OOD
calibration is poor for this model class; a misroute sends a hard item to the small model;
published cascades gain only 1–4% AUC, LEV ~15–24% compute at <1 pt). The route reads each
question's class from the generation plan, which is known at build time.

### C. Exploit cheap determinism — *speed/quality, optional*

- **Batch the whole body in one forward pass** (the route already gets one body; do not loop).
- **Cache decisions** keyed by `(stateDigest, question)` so an edit/refine reuses them — faster
  *and* consistent.
- **Let confident, *calibrated* picks expand the "built from Jev's picks alone" set** — the
  agent already serves simple requests with no model write (composer-parts-only median 2.0 s vs
  6–17 s when a section is written). A fast, correctly-calibrated 151M model can be confident
  on more cases → fewer generation calls → faster, same quality. Depends on A.

### D. Remove the code-reading step from the critical path — *soundness, targeted*

The pipeline already compiles and runs every program with every handler tapped
(`VeraSmoke.ets`) and repairs failures. So Jev's verify answer is a *speed hint* ("skip
re-asking the model"), not a correctness gate. On low confidence, **let verify/claims re-ask
the generation model** and rely on compile/smoke to catch failures. This removes the hard tier
from the decision model entirely — the cleanest way to handle 8/9 without a 4B decoder.

### E. Tier by task class, given phone resources — *the resource answer*

**Tier the decision mechanism by call site, not by sub-question and not by confidence**
(splitting a batch loses the shared-state single pass for negligible gain). For Vera on a
phone:

| tier | what | mechanism | footprint / latency | when it pays |
|---|---|---|---|---|
| **A — trivial** | step 1 (intent topics), retrieval parts of 5 | in-repo **embeddings/rules**; a 17–74M encoder only if labels change | ~0 extra (embeddings already loaded) / ~ms | always (it is free) |
| **B — standard** | steps 2, 3, 4, 6, 7, 10 | **one 151M model** (openJev 151M) | ≈150 MB INT8 / ~30–60 ms | default |
| **B+ — accuracy-critical** | step 4 formula/unit/arg if measurement shows 151M is weak | **Laya 421M** | ≈421 MB INT8 / 84–127 ms, 5–12 s first load | only if standard accuracy (73 vs 66) is worth 2.8× footprint |
| **C — hard** | steps 8, 9 | **4B+ decoder or cloud**, or §5.D | 2.3–2.6 GB Q4 (tight) or network | the hard-tier wall is architectural |

**Phone resource reality (why "smaller models for simple tasks" is *marginal*):**
- **RAM is not binding.** 151M ≈ 190–240 MB at INT8; 421M ≈ 500–650 MB; available RAM on
  phones is typically <4 GB but a ≤650 MB model fits comfortably. It only binds if a 4B
  generator is co-resident.
- **First-load/compile *is* binding.** Laya 5–12 s GPU compile / 35–59 s NPU compile
  (cached 0.7–1.3 s); a 74M model loads <1 s. In short sessions killed between runs, first
  load dominates the experience; keeping two models resident doubles it.
- **Thermal throttling *is* binding.** Sustained use slowed one encoder from 470 ms to 1200 ms.
- **Battery is small** (order 0.03–0.5 Wh/1000 decisions). **Accuracy/calibration transfer is
  the real binding cost.**
- **A smaller tier (17–74M) is worth adding only if** easy calls dominate *and* you measured a
  latency/thermal problem — it cuts those calls ~5–10× in cost but does not lift standard/hard
  accuracy. On a flagship with cloud generation, one 151M model is simpler and its RAM is not
  a problem.

**HarmonyOS caveat:** no public decision-encoder benchmark on HarmonyOS/Kirin exists; all
measured data is Android/Snapdragon or Apple. Plan a CPU/GPU fallback and measure on the
target device.

### Guardrails — what *not* to co-design

- Do not hand generation to the decision model.
- Do not remove the compile / smoke / claims gates.
- **Do not use a bigger encoder for hard tasks** — it does not help (§3.2); escalate instead.
- Do not build a dynamic confidence router first; start with the static task-class map.
- Do not use naive dynamic INT8; weight-only INT8 / FP16 only; validate near-tie flips on
  100–200 local items.
- Check option cardinality per question against the model's cap (Laya degrades past ~20);

### Sequencing (soundness first, then optimise)

1. **Drop-in + measure** — `askJevViaLocal` on openJev 151M, one batched pass, Phase 0 logs;
   bench per step and per threshold vs cloud Jev.
2. **A (calibrate)** — per-type temperature/conformal on 200–500 local decisions. *Makes it
   sound.*
3. **B/D (escalate or remove the hard tier)** — route 8/9 to cloud/4B or the compile-gate
   co-design; static task-class map.
4. **C/E (exploit + optionally add tier A)** — caching, expanded "picks alone"; add a 74M tier
   only if measured need.

---

## 6. Proposal / plan

### 6.1 Recommended architecture (on-device NPU target)

The target is a decision model running on the **phone's NPU**, behind the seam already built and
phone-verified: `askJevViaLocal` (hybrid — hard tier → cloud, cloud fallback) plus a
`LocalDecisionModel` registered via `setLocalDecisionModel(...)`. §7 is the detailed "what it
requires"; this is the plan built on it. The target backend is:

- **Runtime:** a **MindSpore Lite / NNRt (HIAI)** model on the Kirin NPU, wrapped as an ArkTS
  `LocalDecisionModel` (the runtime's ArkTS API, or a thin `localjev` NAPI over PR #62's C ABI),
  registered at startup. **The route does not change.**
- **Model:** **openJev 151M** by default (Apache 2.0, smallest/fastest per JevBench), converted to the
  NPU format (INT8, operator-coverage checked); **Laya 421M** only if it wins the conversion+accuracy
  spike (§7.6).
- **Tiering (§4, §5.E):** trivial steps (1, align) → the in-repo **embeddings**; standard
  (2, 3, 4, 6, 7, 10) → the NPU model; hard code-reading (8, 9) → **cloud** (USB-net) or the §5.D
  co-design.
- **Calibration (§5.A / §7.4):** per-type thresholds re-fit on-device (200–500 decisions).
- **Packaging/perf (§7.3 / §7.5):** embed or download the bundle; batch per-option passes; cache by
  `stateDigest`.
- The **dev-machine HTTP service** (PR #62 / Candle, reached over `hdc rport`) stays as the
  iteration harness, not the target.

### 6.2 Phased plan (NPU target)

- **Phase 0 — NPU-feasibility spike (phone, small).** Can a system-signed app run *any*
  MindSpore Lite / NNRt / HIAI model on the Kirin NPU, and does the backend support a
  ModernBERT-sized graph? De-risks everything (§7.1 / §7.10). Do this before converting anything.
- **Phase 1 — convert + pick.** Convert **openJev 151M and Laya 421M** (PyTorch → ONNX → NPU format,
  INT8), check operator coverage, and pick the clean one (§7.6). Produce the bundle + tokenizer.
- **Phase 2 — NAPI/seam + packaging.** Wire `localjev` (or the MindSpore ArkTS API) into
  `setLocalDecisionModel(...)`; embed/download the bundle; handle first-load/compile (§7.2–7.3).
  The production backend is now on-device; the HTTP service stays for dev.
- **Phase 3 — calibrate (on-device).** Per-type temperature/conformal on 200–500 on-device decisions
  vs cloud Jev; re-fit the Vera thresholds (§5.A / §7.4). *The soundness gate.*
- **Phase 4 — performance + hard tier.** Batch per-option passes, cache by `stateDigest`, measure
  thermal/battery; confirm 8/9 → cloud on-device; re-bench the 121 prompts (§7.5 / §7.7).
- **Phase 5 — verification & ship.** NPU-vs-CPU fallback detection, on-device `abi-check`/behaviour,
  latency/thermal benchmarks; enable the on-device route by default only after these pass (§7.8).

**Why this order (and what it supersedes).** Feasibility gates everything: if a system-signed app
cannot reach the NPU (§7.1) or the backend lacks a ModernBERT op, conversion and calibration are
wasted — so the spike is Phase 0, not last. Calibration moves to Phase 3 (on-device) because NPU
INT8 shifts the probability distribution; a dev-machine eval is kept only to *choose the model* in
Phase 1. The dev-machine HTTP service (PR #62 / Candle, over `hdc rport`) is the **iteration
harness, not the product**. Tier routing (§5.E) and the hard-tier decision are independent of the
runtime and can be done any time (placed in Phase 4). This supersedes the earlier draft ordering
that put calibration first and on-device last.

### 6.3 Risks

- **NPU access (biggest)** — third-party NPU access on HarmonyOS NEXT is often restricted to HMS
  HiAI / system privileges. The app is system-signed, which helps, but this is the first thing to
  prove (§7.1 / §7.10); the whole NPU target depends on it.
- **Operator coverage** — ModernBERT (RoPE, alternating attention) must run on the NPU backend; a
  missing op silently falls back to CPU (§7.8), erasing the speed win.
- **Conversion / quantization calibration shift** — NPU INT8 changes the probability distribution;
  the thresholds must be re-fit (§7.4).
- **Hard tier (8/9)** — no encoder works (§3.2); route it to cloud (§7.7) or the §5.D co-design. Low
  frequency, so a cloud fallback is a small residual dependency, not a regression.
- **Licence.** openJev/Laya/GLiNER Apache 2.0 (clean); Von archived; **StartLux weights
  CC BY-NC** (exclude for commercial); Cloudflare Clef Apache 2.0 but **hosted**.
- **Calibration transfer.** Vendor ECE ≠ production; budget labels; static map not dynamic router.
- **On-device.** RAM fine; **first-load/compile and thermal are the binding costs**; no HarmonyOS
  benchmark exists — measure on-device.
- **Maturity.** Class is new (2026); vendor benches (JevBench is semi-independent) — validate on
  the repo's own eval set.

### 6.4 What needs a decision before implementation

1. **NPU runtime:** MindSpore Lite vs NNRt/HIAI vs HMS HiAI — depends on the feasibility spike
   (§7.1 / §7.10); pick the one the system-signed app can actually reach.
2. **Model:** openJev 151M vs Laya 421M — decided by the conversion + operator-coverage + accuracy
   spike (§7.6).
3. **Packaging:** embed the bundle in the HAP vs download-on-first-run (§7.3).
4. **Hard tier (8/9):** cloud (USB-net) vs the §5.D compile-gate co-design; both viable, and
   **no on-device encoder solves it** (§3.2 / §7.7).
5. **Data / device / quality bar:** OK to log cloud-Jev answers as the eval/label set? A host for
   conversion + calibration? Allowed regression on the 121-prompt bench vs cloud-Jev?

### 6.5 Status (2026-11-23) — verified findings and pivot

The Phase 0/1 experiments (see §7.1 and `host-eval.md`) settled the key
unknowns; the plan pivots accordingly:

- **NPU access is real** — a system-signed app enumerates the Kirin 9010 NPU
  (`NPU_ohos.boot.hardware.Kirin9010_v2_0`, plus `HIAI_F`) via MindSpore Lite (§7.1).
- **MindSpore Lite cannot run openJev** — masked-attention softmax is NaN and its
  `IsNaN` guard cannot be reproduced in MindSpore (§7.1), so the **MindSpore-NPU path is
  not viable for this model**; NPU would need an author-side re-export avoiding masked-NaN.
- **The on-device target is Candle-CPU** — PR #62's Rust/Candle runner handles masked
  attention and NaN correctly. CPU, not NPU, but real on-device. Cross-builds for
  `aarch64-unknown-linux-ohos` → `localjev` NAPI → ArkTS `LocalDecisionModel` (via
  `setLocalDecisionModel`). (The "far faster than the WSL dev-box" hope this section
  originally carried did not hold: measured on-device it is ~1.5 s per forward on the
  short fixture bodies and ~5 s per question on real ones — `cpu-vs-cloud.md`.)
- **Built and host-validated** — Candle cross-compiles for `aarch64-unknown-linux-ohos`;
  the `localjev` NAPI (`napi_local_jev.cpp`) links it into `liblocaljev.so` (17 MB
  stripped) and the HAP builds with 0 diagnostics. Empty-bundle answers are empty (the
  route falls back to the cloud). (At this date calibrated weights and an on-device run
  were the remaining steps — both done by the addendum below.) Build/deploy: `build.md`.
- **The model is not a universal decision engine** — host eval vs recorded cloud Jev
  (openJev via onnxruntime) gives 92–100% on the easy/judgment steps but 31–50% on the
  formula/reasoning steps, and it is overconfident (T\*≈3.0). So the §5.E call-site map
  becomes:
  - **LOCAL (Candle)** — `asked`, `effect`, `moment`, `countdown`, `steps`, `unit`, and
    confident `widget`/`theme`;
  - **CLOUD / plan (§5.D)** — `expr`, `show`, `arg`, `covers`, and code-reading
    (verify/claims);
  - per-type thresholds re-fit (§5.A) on 200–500/task logs before trusting local answers.

§6.1–§6.4 above document the original NPU-targeted reasoning; this status supersedes
its backend choice (MindSpore-NPU → Candle-CPU) and fixes the routing.

**Addendum (2026-11-24, later): the local model now serves in the running app.** A serving
calibration (T\*=2.2, min_confidence 0.71) fitted from the recorded device run
(`tools/local-jev/eval/laya-calibrate.py`) sits in the Laya bundle manifest, and
`local_jev_predict` runs the batched scorer through it: a real generation logged
`local answered 8/16` with the cloud covering the rest (per-question fallback,
`unansweredJevBody`), compiled and rendered. `expr`/`show` are cloud-tier prefixes outright
(the fair-measurement report), and the Settings page has an "On-device decisions" switch.
Build/deploy and the current serving state: `build.md`; the fair local-vs-cloud
measurement: `cpu-vs-cloud.md`; the host eval: `host-eval.md`. Still open: the at-scale
per-type calibration refit (§5.A — the fit so far is in-sample, n≈109), `selectEdit` is not
behind the hybrid switch, and local serving costs ~5 s/decision on real bodies (NPU: §7.11).

---

## 7. The on-device NPU path — what it additionally requires

§6 targets a *local* decision model, and that much is built: the on-device NAPI backend
(`liblocaljev.so`) runs PR #62's **Rust/Candle** Laya runner **on the phone's CPU** and serves
decisions (§6.5's addendum). What it does not do is use the **Kirin NPU** — Candle has no
HarmonyOS NPU backend. Moving the model onto the NPU is a different, larger job. This is the
extra work, in dependency order.

### 7.1 Replace the runtime (Candle → HarmonyOS NPU) — the dominant item

Candle has no HarmonyOS NPU backend. The NPU is reached only through a HarmonyOS runtime, with the
model in that runtime's format.

**Phase 0 finding (verified on the phone).** The OHOS **MindSpore Lite NDK** is a first-party,
SDK-shipped NPU path (`libmindspore_lite_ndk.so`, `types.h`: `OH_AI_DEVICETYPE_KIRIN_NPU`,
`OH_AI_DEVICETYPE_NNRT`). A system-signed app test (`entry/.../vera/NpuSpike.ets`, launched with
`--ps npuSpike 1`, loads a stock `.ms` pushed into filesDir) confirms:
- `getAllNNRTDeviceDescriptions()` returns **2 accelerators (type 3)**: `NPU_ohos.boot.hardware.Kirin9010_v2_0`
  and `HIAI_F` — the **Kirin 9010 NPU is reachable** to the app (not restricted to HMS/system UI).
- CPU `loadModelFromFile` + `predict` of a real `.ms` works (~84 ms, 4 inputs → 1 output).
- NNRT `loadModelFromFile(target:['nnrt'])` returns, but a stock AR-engine model's `getInputs()` is
  `undefined` — that model **is not NNRT-buildable**. So **NPU access is resolved**; **operator
  coverage per converted model is the remaining gate** — to be confirmed with a decision-model `.ms`.

**Phase 1 finding (updated 2026-11-24) — the NaN blocker is solved; the model runs on MindSpore CPU,
but the NPU (NNRT) still can't be driven.** The decision model — **openJev
(`heman10x/rlcd-modernbert-151m`, ModernBERT + GLiClass 25-slot head)** — ships as `model_fp16.onnx`;
`tools/local-jev/convert_openjev_to_ms.py` rewrites the converter-rejected ops exactly
(`Einsum`→`MatMul`, static 1×256 + `onnxsim`, `Flatten`→`Reshape`, `Cast(int64→bool)`→`Greater`,
`IsNaN`→`Not(Equal(x,x))`). The original export could not *run* on MindSpore because a fully-masked
(padding) query row makes the softmax `0/0 = NaN`, and the model's `Where(IsNaN,0,·)` guard can't be
reproduced (no `IsNaN` kernel; `Equal` faults on NaN). That is now **solved at the source**: replace the
`−inf` attention-mask fill with a finite `−1e4` (`finite_mask_fill`) — a fully-masked row's softmax
becomes a valid uniform distribution instead of `0/0`, and a real row's masked keys still get weight ≈0,
so real-token outputs are unchanged but **no NaN ever arises**. (A self-attention `Where(diag,0,M)` sink
was tried first and **broke MindSpore's graph build** — 2.9.0 `Build failed`, 2.6.0 segfault — so the
constant swap is used instead.)

Measured with the finite-fill `.ms`: it **builds and runs on MindSpore Lite** — host CPU benchmark
**Success, 529 ms**; on-device CPU `inputs=2, outputs=1, ~1.45–1.68 s`; host parity on a real masked
prompt gives an **argmax matching ORT** (lower logits drift ~fp16). **The NPU cannot run this model via
MindSpore-NNRT** — confirmed with the C NDK (`napi_msnnrt.cpp`, which bypasses the ArkTS API entirely).
On the phone the NNRT logs are unambiguous: `get hdi service nnrt_device_service failed, -19` →
`NNRt: RegisterBackend failed`; then `NNRt: Authentication failed, input model cannot run by npu.` →
`OH_NNCompilation_Build failed` → `BuildKirinNPUModel failed`. So two concrete blockers: **(1) the NNRT
HDI device service is unreachable for the app** (`-19` — likely a permission or a missing service), and
**(2) NNRT rejects the model** ("cannot run by npu" — its op/format authentication fails for this
ModernBERT graph). It also flags a version skew: the on-device engine is **2.7.0** while the model was
converted with **2.9.0**. None of this is the model's NaN (solved) or the converter ops — it is the NNRT
backend and its op coverage. So the working on-device runtime is **CPU**; the NPU needs the `-19` access
resolved (permission/service), NNRT op coverage of the transformer, or a different vendor-NPU runtime
(HiAI Foundation).

- **Backends to evaluate:** the **MindSpore Lite NDK** (`.ms` models, `OH_AI_DEVICETYPE_KIRIN_NPU`)
  is the concrete candidate; `@ohos.ai.mindSporeLite` (ArkTS) and NNRt are alternatives. HiAI
  Foundation libs are present on the phone but have no public API d.ts — use only if NDK NPU fails.
- **Conversion pipeline:** PyTorch → ONNX → (`.ms` / NNRt) + **INT8 quantization**; reproduce the
  tokenizer and the option-marker input template exactly on-device.
- **Operator coverage:** Laya and openJev are both ModernBERT-backed (RoPE, alternating attention);
  the NPU backend must support every op, or it silently falls back to CPU (§7.8).
- **Access risk (de-risk first):** third-party NPU access on HarmonyOS NEXT is often restricted to
  HMS HiAI / system privileges. The app is **system-signed (`system_basic`)**, which helps, but this
  is the biggest unknown — a phone spike (§7.10) decides whether the rest is worth doing.

### 7.2 NAPI / ArkTS integration — small — *done*

The `VeraLocalDecision.ets` seam is ready (`LocalDecisionModel` + `setLocalDecisionModel`), and
the NAPI itself is built (`napi_local_jev.cpp`, the `napi_llama.cpp` async-work pattern, target
`localjev`, ArkTS `VeraLocalNapi.ets`, registered at startup — build.md). What §7 needs beyond it
is a *MindSpore/NNRT-backed* NAPI (`napi_msnnrt.cpp` is the probe), which would replace the custom
NAPI if that runtime wins.

### 7.3 Model size & packaging

- **HAP size:** Q4 bundle ≈ 207 MB (Laya FP16 ≈ 1 GB). Decide **embed vs download-on-first-run**
  (AppGallery per-module limits, install time, storage); the NPU/INT8 format may shrink it.
- **First-load / compile:** Laya is 5–12 s GPU / 35–59 s NPU compile first load, 0.7–1.3 s cached
  (survey). Bundle a pre-compiled graph where the runtime allows; plan cold vs warm start.

### 7.4 Calibration under NPU quantization — soundness, mandatory (§5.A)

NPU INT8 is typically **static** quantization. The survey shows naive/dynamic INT8 destroys
calibration (Laya 76.7%→65–69%) while **weight-only INT8 changed 0/116 answers**. Validate the
converted model's ECE and **re-fit the Vera thresholds per decision type** (temperature/Platt,
conformal on the err-wide `noul`s) on 200–500 on-device decisions. The dev-machine prototype leaves
this open; it does not close on NPU by itself.

### 7.5 Performance engineering (batching, thermal)

The on-device CPU path batches questions (≤4 per forward, `batched_scores`) at a measured
**~5 s/question on real bodies** (cpu-vs-cloud.md) — the CPU is not the answer at this rate. On
the NPU the win comes from **batching the per-option encodings (and ideally the whole body) into
few large ops** — the source of the ~50–200 ms/question figure. Add **caching by
`(stateDigest, question)`** (§5.C) to avoid re-running identical decisions, and measure **thermal
throttling** (survey: 2.5× slowdown under sustained load) and battery.

### 7.6 Model choice for NPU (Laya vs openJev 151M)

§3.1 recommends **openJev 151M** (JevBench hard 38 vs 34, standard 66 vs 73); PR #62 uses
**Laya 421M**. Pick after a **conversion-feasibility + accuracy spike**: whichever has clean NPU
operator coverage and better per-step numbers on the repo bench.

**Correction (2026-11-25, arithmetic): the "2.8× smaller/faster" framing was param-count
reasoning and is wrong on the speed half.** Both models share the *same encoder* —
ModernBERT-base, 22 layers × 768 hidden — so the per-question FLOPs are ~identical
(≈21.8 GFLOP for Laya vs ≈20.5 for openJev at 110 tokens, a ~6% difference from the
head). The params that differ are the **embedding table** (Laya 197M vs openJev 39M) —
lookups, no FLOPs. What openJev actually buys: a **~3× smaller bundle** (Q4 ≈ 80 MB vs
202 MB), a **genuine held-out calibration** (`calibrator.json`: temperature 2.8, per-k,
1753 items, zero JevBench fitting), and better measured easy-type agreement (host-eval:
`steps` 92%, `asked` 100%). What it costs: a new Rust engine (its GLiClass head is
different — text/classes projectors + a dot-product scorer, one sequence per question
with inline `<<LABEL>>` options) and a new gguf export. A quality/packaging lever, not
a speed one.

### 7.7 Hard tier + cloud on-device

The NPU encoder still **cannot read code** (8/9 — chance for any ≤421M encoder, §3.2). On-device
those must **escalate to cloud** (via the USB-net VPN; the phone reached `8.152.x:443` in testing)
or adopt the **§5.D compile-gate co-design**. Confirm the hard-tier cloud route on-device and
measure quality.

### 7.8 Verification (the acceptance gate)

- **NPU-vs-CPU fallback detection:** log which backend actually ran (a missing op silently falls back).
- **Behaviour:** an on-device equivalent of `abi-check` (finite logits, deterministic), plus per-step
  agreement/ECE vs cloud on-device.
- **Benchmarks on the target phone** (no public HarmonyOS NPU benchmark exists, §7.5): first-load,
  warm latency, sustained thermal, memory, battery.

### 7.9 Memory & licence

~150 MB (openJev) to ~1 GB (Laya) resident; fine on a flagship alone, tight co-resident with a 4B
generator. Laya/openJev are Apache-2.0; confirm the NPU-converted artifacts' terms.

### 7.10 Dependencies / sequencing

1. **NPU-feasibility spike on the phone** — can a system-signed app run *any* MindSpore/NNRt/HiAI
   model on the Kirin NPU? This de-risks everything; do it before converting a model.
2. **Model conversion + operator-coverage check** for Laya and openJev → pick the clean one (§7.6).
3. **NAPI/seam + packaging** (§7.2–7.3) — the app side is small; the runtime is the work.
4. **Calibration + thresholds on-device** (§7.4).
5. **Batching + thermal**, then hard-tier cloud validation (§7.5, §7.7).

**Bottom line:** the app-side seam is nearly free (already built and phone-verified); the cost is
concentrated in the **NPU runtime + model conversion + calibration**, plus **NPU-access
uncertainty**. So the next action is not conversion — it is the small NPU-feasibility spike.

---

### 7.11 NPU status & TODO (2026-11-24; NNRT closed and HiAI gate opened 2026-11-25)

The narrative for this is §7.1 above (Phase 0/1 findings, the log lines, the blockers); this
is the working state in brief: **the NaN blocker is solved** (`finite_mask_fill`, the `.ms`
builds and runs on MindSpore — host 529 ms, device CPU ~1.45–1.68 s, ORT-parity argmax);
**the NPU does not run the model via MindSpore-NNRT**; the **working on-device runtime is
CPU** — Candle/Laya via `liblocaljev.so`, and MindSpore-CPU openJev via `msnnrt`. The
realistic NPU route is **HiAI Foundation**, not open NNRT.

**2026-11-26, third device: engineering Mate 80 Pro Max (HLS-AL00 "XTD", Kirin 9030,
API 26, fresh install, no root available to shell). Both NPU doors probed; neither
opens for the transformer graph:**

- **HiAI Foundation: the gate opens and E2E passes, but the attention transpose
  blocker is unchanged on the newer hardware.** `--ps hiaiSpike 1`: npu=1,
  version_int 550395480 (0x20CE5E58 = 32.206.94.88 — a different, newer build than
  the 106/107-era images on the other two phones). `--ps hiaiE2E 1`: on-device
  compile + NPU run, exact result (10.000). `--ps hiaiOps 1`: the same op set as
  both older phones — MatMul, Add, Mul, RealDiv, LayerNorm, Softmax, BatchMatMul,
  ConcatD, GeLU, Reshape build and run with correct values; Sqrt, Rsqrt, Exp, Sin,
  Cos, **TransposeD and Transpose(list-attr) fail to build**. `--ps hiaiModel 1`
  (the 2-layer Laya graph from rawfile): **`build_failed`, rc=1, 226 ms** — the
  same failure as HiAI 106/107. Three HiAI versions now agree: the attention
  transpose is a platform limitation, not a per-device-version gap that newer
  silicon fixes.
- **NNRT is OPEN on this phone — the first device where the app can actually
  reach the service.** `--ps nnrtSpike 1` enumerates two devices and selects the
  accelerator `NPU_ohos.boot.hardware.Kirin9030_v2_0` (a real device name, not the
  phantom the old engineering phone fabricated). The service is deployed AND an
  ordinary app may call it — no SELinux gate, no -19. But the converted graph is
  still refused: with the 303 MB openJev `.ms` (jev_fill.ms) packaged in rawfile
  and landed in filesDir, `ModelBuildFromFile` on the NNRT accelerator fails
  (status -1, ~270 ms — rejected before any compile work), while **the same file
  on a CPU device context builds successfully** (`cpuBuild: 0`, a control added
  to the probe for exactly this question). So the file and the runtime agree;
  **it is the NPU that rejects the transformer graph** — the same class of
  "input model cannot run by npu" refusal as before, now isolated cleanly from
  connectivity and format questions.
- Practical notes for this phone: no `su`, and the app's filesDir is not
  shell-writable, so the model reaches the phone via rawfile (the nnrtSpike now
  copies `rawfile/jev-fill.ms` to filesDir on first run — the same delivery
  pattern as the HiAI model test); a fresh install has no saved state to protect.

**2026-11-26 (later): the transposed-space layout -- the attention blocker
broken at op level, one optimizer wall left.** A new generator mode
(`hiai-gen.py --layout transposed`) restructures the whole residual stream as
`[d, s]` (features are rows, input embedding transposed host-side for free):
every weight projection becomes a plain Const-first MatMul with a
pre-transposed weight, the head split/merge becomes a Reshape, and the
attention score product becomes `BatchMatMul(adj_x1)` -- the adjoint whose
shape inference the runtime actually accepts. The graph is offline-exact
against the numpy reference (F32 delta 4.4e-6 at 22 layers; F16 0.0019, same
as the normal layout) and survives every op-level device probe. The session
also fixed the model-test NAPI to feed every declared input (probes with
several Data inputs failed at run before that).

The complete op-level constraint map of HiAI 109.636 (each row
device-probed, ~50 models):

- `BatchMatMul(adj_x1)` **requires square operands** -- the shape check never
  applies the adjoint; even `[2,3,2]` fails. Workaround (VERIFIED working):
  pad K/Q's per-head feature rows 64->seq with an identity-padded Const
  matmul (`pad_heads`), making the operands `[heads, s, s]`; the zero rows
  contribute nothing to the contraction, scores exact.
- `BatchMatMul`'s **second operand must be a Const** (a Data or derived B is
  rejected). Workaround (VERIFIED): the V-product as
  `(V^T C) masked-by M, times the flat P2d` -- three plain ops using
  scatter/mask Consts; per-head `V^T_h P^T_h` in ONE 2D MatMul.
- `Softmax(axis=-2)`, 2D->3D `Reshape`, 3D `ConcatD`, batch-broadcast
  `Mul/Add` all work at model scale.
- `SplitD(axis=0)` fails at run (2D and 3D).
- A concat-derived operand into the score BatchMatMul builds but fails at
  run (0x560C0808) -- feed it from a MatMul instead (the `pad_heads` route).
- **The LayerNorm wall**: the hand-built transposed LN (mean/var via
  ones-row Const matmuls + rsqrt by iteration) runs on the NPU in isolation,
  but **its output cannot feed a large-Const-first MatMul** -- and every
  weight projection is exactly that. `RealDiv` and `Sub` outputs are
  hard-rejected as MatMul B operands (single-op probes), so the LN was
  rewritten division-free and Sub-free (Mul/Add-only Newton, seed 0.003, 36
  iterations, offline-exact) -- and the projection still fails. The
  remaining signature: a ~200-op chain of `[1, s]` elementwise ops feeding a
  `[768,768]`-Const MatMul is rejected at build, while the same chain alone,
  and the same MatMul with shallow-chain operands, both pass. This looks
  like an optimizer/constant-folding limit in HiAI 109.636, not an op-set
  gap; the next lever is restructuring the LN (chunked iterations, or
  computing mu/var on the host side per frame).

**2026-11-27: THE NPU PATH IS PROVEN. The full 22-layer model runs on the
Kirin 9030 NPU with correct logits.** The entire "attention transpose
blocker" was two wire-format bugs in our generator, not platform limits:

1. **The adjoint attrs must be BOOL-typed.** `adj_x1`/`adj_x2` emitted as
   int (AttrValue field 3) are silently ignored by the runtime's op parser;
   the runtime requires the bool field (field 5). With int attrs, non-square
   operands fail shape inference (the adjoint is never applied) and square
   ones run the UNTRANSPOSED product -- which is why every "square
   workaround" passed shape checks and still produced wrong results. With
   bool attrs, `BatchMatMul(adj_x2)` works directly at [12,108,64]x
   [12,108,64] -> [12,108,108] with exact adjoint semantics
   (device-verified: b1/b4 probes).
2. **Weight Consts must be F32.** F16 Consts are rejected by the builder
   (identical graphs: F16 fails, F32 passes -- d6f16 vs d6). The NPU still
   executes FP16 internally; the dtype is only storage.
3. Weight matmuls take PRE-TRANSPOSED weights with NO adj attr: a const-B
   MatMul carrying adj after a fused LayerNorm is rejected (c2 vs c3
   probes), without adj it builds.

The working graph is the NORMAL layout (fused LayerNorm op, per-head
SplitD + Reshape + BatchMatMul(adj_x2, bool)), generated by
`hiai-gen.py` (default emission). Device results (Mate 80 Pro Max):

- 2-layer F32: build 1077 ms, init 47 ms, **run 34 ms**, logits
  [-0.1196, -0.1044] vs reference [-0.12, -0.1055].
- 22-layer F32 (643 MB, 3892 ops): build 2568 ms, init 2506 ms,
  **run 1237 ms** (seq=108), logits [-1.8602, -1.4122] vs reference
  [-1.858, -1.4142] -- delta ~0.002.
- vs the CPU path (~5 s per question): **~4x faster**, one compile per
  shape (2.5 s) amortized across the question batch.

The transposed-space layout, the hand-built LayerNorm, the square-padding
and the C+M V-product workarounds are all unnecessary on this runtime --
kept in the generator as dead `--layout transposed` code paths. The
preceding day's "constraint map" findings (square operands, Const-B
BatchMatMul, RealDiv/Sub poisons, optimizer walls) are RETRACTED: they
were artifacts of the int-attr bug, which silently disabled adjoints and
made valid graphs fail in confusing, order-dependent ways.

**E2E NPU data report (2026-11-27, docs/local-jev/cpu-vs-npu-vs-cloud.md):** the
measured three-backend comparison. Logits: NPU 0.002 from the numpy reference vs
candle's 0.12-0.39 (the NPU is *closer* to the spec); calibrated confidence
-0.003 vs candle; served-count variance within candle exceeds the backend
difference. Raw forward: NPU 1.24 s vs candle 5 s per question (4x). E2E Jev
phase: NPU 94.8 s vs CPU 86.4 s vs ~11 s all-cloud -- the 4x forward win is
currently eaten by fixed-shape padding (S=256 for S~150 questions) and the
first-run compile/init. Next levers: bucketed shapes, the
HIAI_MR_DynamicShapeConfig API (exists, untested), warm-process amortization
(compile is once per process, never measured on a second generation), and
batch packing for the fixed shape.

**Optimization results (2026-11-27, commits 78459fe / ebe7f73 / d91596a):**
three of the levers are implemented and verified on device. Model
persistence (SaveToFile/RestoreFromFile) skips the compile on cold starts,
saving ~2.1 s (the 3.7-6.5 s init remains). The hard-tier cloud batch now
runs concurrently with the local forward (the Jev phase is
max(cloud, local+fallback), not the sum). Bucketed shapes: the registry
takes multiple (path, batch, seq) graphs, infer_group picks the smallest
fitting bucket and compiles lazily; S=192 B=8 replaced S=256 B=8 in the
test build. **The honest result: the bucketed E2E local phase is flat**
(~79-81 s vs the 73-84 s S=256 baseline) -- the expected ~14 s padding
saving is within noise, not demonstrated; the NPU per-batch cost may not
be shape-proportional at these sizes, and resolving it needs per-batch
trace timing (LOCAL_JEV_TRACE -> stderr, invisible on device) or the
model-test harness on the S=192 graph. The full Jev-phase decomposition
(six groups: 3 NPU + 3 candle, the padding waste, the engine init, the
sequential ordering) and the fundamental-floor analysis are in
cpu-vs-npu-vs-cloud.md sections 6-7.

Remaining for the E2E serving path: the per-batch NPU decomposition
(trace output or model-test on S=192), DynamicShapeConfig (one probe,
would remove all padding), and warm-process amortization measurement
(the result screen's New navigation is hard to drive programmatically).

Net: the two phones were complementary before (eng: system-signed, no NNRT
service; retail: NNRT service, SELinux-gated); this third phone has both
privileges at once — system signing works AND the NNRT service is reachable —
and still neither runtime accepts the transformer graph. The NPU question is
now purely a graph/op-coverage question on both paths: HiAI needs the attention
transpose (or a layout that avoids it), NNRT needs whatever op subset its NPU
accepts (undocumented; the CPU-control split gives a clean way to test
candidates).

**2026-11-25, device reconnaissance (root shell + in-app probe; retail follow-up
later the same day on a commercial Mate X6, Kirin 9020, HarmonyOS 7.0.0.111 retail,
AGC debug-profile app — non-system-signed):**

- **Retail answers the NNRT question the engineering phone could not: the service
  IS deployed there, and access is an SELinux privilege gate.** The retail probe
  logs the exact denial: `[selinux] o:r:debug_hap:s0 haven't "get service"
  permission to nnrt_device_service` → `get hdi service nnrt_device_service
  failed, -19`. So the engineering phone's -19 was "not deployed"; retail's -19
  is "deployed, but a normal/debug app may not touch it". An AGC debug profile
  (apl=normal) cannot pass that gate — a system/privileged app would, but the
  retail device rejects our OpenHarmony system CA at install, so we cannot test
  the privileged side on retail. The two phones are complementary: engineering
  (system-signed, no NNRT service) and retail (NNRT service, no system signing).
- **Retail op battery (same --ps hiaiOps 1):** every working op runs correctly,
  and **8/10 partition to the NPU** — including **BatchMatMul** — but **plain 2D
  MatMul falls to CPU on the retail image** (`not supported in npucl store
  [elementary_lib]/[fe_lib]`), unlike the engineering phone where MatMul got
  NPU:1. **TransposeD and Transpose both fail to build** (build=1) on retail —
  the per-head SplitD unroll is the only attention layout that works
  cross-device. The graph generator should use BatchMatMul (3D, batch-1) for
  the weight projections for retail NPU coverage.
- **Retail HiAI E2E from the debug-profile app: PASS** — same MatMul graph
  compiles and returns {"ok":1,"output":10.000} (on CPU partition, per the
  above), and the HiAI Foundation gate opens from a non-system app (dlopen +
  IsNpuSupport=1 + ModelManager symbols resolve; version 107.636.120.010).

**Engineering-phone findings (original):**

- **NNRT is CLOSED on the engineering device — the HDI service is not deployed.** No `nnrt_device_service`
  host exists (nothing in `/vendor/etc/hdfconfig`, no process hosting `libnnrt`, the client
  proxies `libnnrt_proxy_1.0/2.0/2.1` sit unused in platformsdk), and the "enumerated device"
  `NPU_ohos.boot.hardware.Kirin9010_v2_0` is a phantom: `param get` for it fails (errNum 106).
  The MindSpore NNRT client fabricates device names from boot params, then fails to reach any
  service behind them — that is the whole of `-19` and the "Authentication failed" that
  follows. Not a permission problem; nothing app-side can fix it. The public
  `neural_network_runtime` NDK API in the SDK routes to the same undeployed service, so the
  version-match retest (TODO #3) is moot. (This is an engineering phone; retail images may
  differ.)
- **The HiAI Foundation gate is OPEN from our app.** `/system/lib64/platformsdk/libhiai.so`
  (434 KB client) exports the full **HiAI Model Runtime C API — 381 `HIAI_MR_*` symbols**
  (BuiltModel restore/save, `ModelManager_Init/Run/RunAsync`, NDTensor, AIPP, dynamic shapes,
  **an on-device `HIAI_MR_ModelBuilder_Build`** with precision/quantize/tuning options).
  Proven with `--ps hiaiSpike 1` (napi_msnnrt.cpp): **this app's process dlopens it,
  `HIAI_Foundation_IsNpuSupport` returns 1, and `GetSymbol` resolves the ModelManager API** —
  a system-signed non-HMS app can reach the vendor NPU path. Huawei documents the same API
  as the public "HiAI Foundation Kit" NDK (linking `libhiai_foundation.so` in the full
  HarmonyOS SDK); the graph-authoring C++ DDK headers are public in the
  `huaweicodelabs/HiAI-Foundation` codelab (IRBuild).

Artifacts: the converter `tools/local-jev/convert_openjev_to_ms.py`; the C-NDK probes
`entry/src/main/cpp/napi_msnnrt.cpp` (`--ps nnrtSpike 1` NNRT, `--ps hiaiSpike 1` HiAI);
the ArkTS spike
`entry/src/main/ets/vera/NpuSpike.ets` (`--ps npuSpike 1`).

TODO (to actually reach the NPU), updated 2026-11-25:

1. ~~NNRT HDI access~~ — **closed: the service is not deployed on this device** (see above).
2. ~~NNRT op coverage~~ — **moot** (same reason).
3. ~~Version-match~~ — **moot** (same reason).
4. **HiAI Foundation** — *PROVEN END-TO-END from our app (2026-11-25, later)*:
   a `--ps hiaiE2E 1` spike (napi_msnnrt.cpp) builds a MatMul graph
   (Data[1,4] × Const[4,1]) through the **stable `hiai::I*Def` pure-virtual
   interfaces** (vendored headers, Apache-2.0, entry/src/main/cpp/hiai/ — from
   the public DDK reference 946166920/hiai_ddk), serializes the model def,
   hands it to **`HIAI_MR_ModelBuilder_Build` — the on-device compiler** — loads
   it with `ModelManager_Init`, runs it, and gets the right answer
   ({"ok":1,"output":10.000,"pass":true}). The server log confirms genuine NPU
   execution: partition NPU:1/CPU:0, an FP16 NPU kernel
   (executor_fc_fp16_tiling5_2_cutCo_filterL1), SetNPUPerf:200. **The app uid
   passes the server's rpc rule** (a root-shell client is rejected:
   "moduleID:16 not support this uid:0" — the app registers as moduleID 11).
   Everything is dlsym'd at runtime: no link-time dependency on the system libs.
   Findings that made it work: the graph IO lists need "name:portIndex" strings
   ("x:0"), ops need BOTH input and output descs (an op whose descs are missing
   parses but fails GraphSerializer), and the old public C++ op-authoring
   headers (the huawevalabs codelab, an older DDK generation) do NOT match
   this runtime's object layouts — use the interface path instead.
   b2. **Graph format bugs (each found on-device, all fixed in the generator)**:
   - `ShapeDef.dim` must use proto3 **packed** varint encoding (the runtime's
     parser rejects unpacked; caught by byte-level comparison with the working
     e2e model).
   - Input references must include the port suffix ("name:0") — bare names
     make `SplitNameAndIndex` fail and `GraphSerializer.UnSerialize` returns
     false.
   - Reshape's shape input must be `DT_INT32` (a Const with int32 bytes), not
     the default DT_FLOAT — the runtime's Verify rejects wrong dtypes.
   - The attention transpose blocker (below) was found only AFTER these three
     were fixed — each masked the next.
   b3. **Attention transpose BLOCKED on BOTH HiAI versions** (106 engineering,
   107 retail — tested 2026-11-26): `MatMul(adj_x2)` and
   `BatchMatMul(adj_x2)` both fail shape inference (the inference engine
   doesn't apply the adj transpose before checking dims:
   `x1Dims[1] != x2Dims[0]`); `TransposeD`/`Transpose` fail to build entirely
   on both; there is no fused attention op in the 200+ op HiAI set. This is
   a platform-level limitation for transformer architectures on HiAI
   Foundation — the attention pattern `q @ k^T` cannot be compiled. The model
   protobuf (after the format fixes) parses and the graph optimizer opens —
   the failure is specifically at per-op shape inference.
   b4. **Numpy reference gotchas** (tools/local-jev/eval/laya-numpy-ref.py,
   validated 0.12-0.39 vs Candle on all 8 fixture bodies):
   - candle's Q4_0 dequant puts LOW nibbles in block positions 0..15 and
     HIGH in 16..31 — halves, NOT interleaved.
   - The tokenizer: candle calls `encode(text, false)` — NO bos/eos wrapping.
   - `criteria` is a Rust BTreeMap: options iterate in SORTED key order
     (affects marker positions).
   - The lazy-loaded weight dict: `if key in t` does NOT trigger
     `__missing__` — attention norms were silently skipped until probed by
     getitem.
   - The stage-dump debugger (`LOCAL_JEV_DUMP=dir` on local-laya) enables
     layer-by-layer bisection against the reference.
   b5. **Model delivery to a retail phone**: rawfile-packaged HAP (the model
   + input as resources, read via `getRawFileContent`, written to filesDir,
   read by the NAPI). No HTTP, no rport, no sandbox issues — the app reads
   from its own resources. The offline executor (hiai_exec.py) validates
   the graph end-to-end without any phone (2-layer delta 0.04).
   b. **Op coverage — RESOLVED, FEASIBLE (2026-11-25, `--ps hiaiOps 1`)**: an
      op battery compiles+runs one tiny graph per op ModernBERT needs.
      Compiling and numerically correct on-device: **MatMul, BatchMatMul
      (transpose flags), Softmax (exact), LayerNorm (exact — the NPU store
      rejects its input dim and the model partitions it to CPU transparently),
      Activation mode 15 = GeLU (exact: gelu(1,2,3,4) = 0.841/1.955/2.996),
      Add, Mul, RealDiv (values show the NPU's FP16 arithmetic), ConcatD,
      Reshape.** Rejected standalone ("no runtime support the Model"):
      Sqrt/Rsqrt/Exp/Sin/Cos — all circumventable: RoPE Sin/Cos become
      precomputed Const tables, Exp lives inside native Softmax, Rsqrt inside
      native LayerNorm. So the ModernBERT graph is expressible; remaining:
   c. generate the 22-layer graph via the interface API, convert the weights
      to Const tensors, parity-check logits against the Candle/OR reference
      and measure latency vs the CPU's ~5 s/question;
   d. if parity holds, port the serving path and re-check calibration (the NPU
      is FP16 — §7.4).
5. **On-device NPU validation** — done for a single MatMul (4a); the model-scale
   validation is 4c.
6. **Format/quantization** — the builder takes precision-mode options
   (FP32/FP16) and quantize configs; the NPU compiles FP16 kernels natively.

---

## Sources

### The Jev analogue class (purpose-built System-one decision models)
- TypeSafe introducing System One & Jev: https://typesafe.ai/blog/introducing-system-one-models-and-jev
- LangChain guide to Jev: https://www.langchain.com/blog/building-a-harness-with-jev
- JEV & Laya as System One Decision Layers (arXiv 2609.28940): https://arxiv.org/html/2609.28940v1
- openJev 151M (runnable checkpoint): https://huggingface.co/heman10x/rlcd-modernbert-151m , https://github.com/Heman10x-NGU/openJev-verdict-2.0
- Laya (421M/322M, Apache 2.0) + LiteRT on-device: https://huggingface.co/convaiinnovations/laya , https://huggingface.co/litert-community/laya-LiteRT , https://github.com/nandhakishorm/laya
- GLiNER2.5-Decide (486M) + small (74M): https://huggingface.co/fastino/GLiNER2.5-Decide , https://huggingface.co/litert-community/GLiNER2.5-Decide-LiteRT
- Von (ARCHIVED): https://github.com/wfzyx/von
- Cloudflare Clef / Clef-flash (9B/27B, hosted): https://blog.cloudflare.com/clef-decision-models/ , https://huggingface.co/Cloudflare/clef
- StartLux-Decision (CC BY-NC weights): https://github.com/StartLuxLabs/StartLux-Decision
- Liquid AI d1-omni-600M (Von's successor): https://huggingface.co/LiquidAI/d1-omni-600M
- Quantization evidence (weight-only INT8, 0 answers changed): https://huggingface.co/inferenceprince/laya-onnx-int8

### Capability by size (the cliff)
- JevBench v1.2 tier results: https://github.com/fstandhartinger/jevbench/blob/main/RESULTS-v1.2.md
- JevBench hard-tier method: https://github.com/fstandhartinger/jevbench/blob/main/datasets/HARD-TIER.md
- OpenDecisions/InnerJev (decoder scaling): https://arxiv.org/html/2610.17205v1
- LEV (on-demand depth, 15–24% compute): https://arxiv.org/html/2610.20951v1
- Tiny encoders (Ettin ladder, GLUE): https://arxiv.org/abs/2507.11412 , https://huggingface.co/jhu-clsp/ettin-encoder-17m
- MiniLM-L6: https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2
- MobileBERT (62 ms Pixel 4): https://aclanthology.org/2020.acl-main.195.pdf

### Routing / cascades (static map vs dynamic router)
- Cascade routing (ICML 2025, 1–4% AUC): https://arxiv.org/html/2410.10347v1
- Dynamic routing survey: https://arxiv.org/html/2603.04445v2
- OrcaRouter (Laya vs Von, OOD collapse, vendor benches don't transfer): https://www.orcarouter.ai/blog/laya-vs-von
- RouteLLM: https://github.com/lm-sys/routellm

### On-device resource reality
- On-device LLMs 2026 (RAM/bandwidth): https://v-chandra.github.io/on-device-llms/
- EnerInfer (NPU + mem power): https://arxiv.org/html/2606.23001v1
- LocalAI decision-model deep dive: https://local-ai-zone.github.io/blog/system-one-decision-models-deep-dive.html

### Confirmed gaps / fallbacks
- Speculative decoding (EAGLE/Medusa — token-level): https://github.com/SafeAILab/EAGLE
- MoE routers (Grouter — token-level): https://github.com/JimmyAwoe/Grouter
- SetFit, DeBERTa-v3 vs ModernBERT, TS4CP: see §3.4 fallback references
- ONNX Runtime + Arm KleidiAI: https://onnxruntime.ai/blogs.html