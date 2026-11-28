# Host-Jev evaluation (no phone)

Compare a local decision model against **recorded cloud Jev**, on the host. Inputs
are the recorded compose fixtures (`tools/vera-harness/compose/<name>/{sketch.json,
jev-answer.json}`). Results and interpretation: `docs/local-jev/host-eval.md`.

## Pipeline

1. **`build-bodies.js`** — rebuild each fixture's Jev body exactly
   (`buildComposeRequest(prompt, parseSketch(sketch.json))`, prompt from
   `tools/vera-harness/compose-prompts.tsv`) into `/tmp/eval/bodies/<name>.json`,
   and copy the recorded `jev-answer.json` to `/tmp/eval/cloud/`. `tip` and `egg` have no
   prompt in the tsv, so their sketch title is used as the prompt. Needs
   `VERA_TYPESCRIPT_PATH`.

   ```bash
   VERA_TYPESCRIPT_PATH=<.../typescript> node tools/local-jev/eval/build-bodies.js
   ```

2. **`openjev-eval.py`** — run openJev (ONNX via onnxruntime; ORT is the correct
   reference runtime, it handles the masked/padded attention MindSpore cannot) over
   the bodies → `/tmp/eval/openjev/`. Needs `~/vlj/openjev/{model_fp16.onnx,
   tokenizer.json}` and a Python with `onnxruntime` + `tokenizers`.

   ```bash
   python tools/local-jev/eval/openjev-eval.py
   ```

3. **Laya (optional)** — POST each body to the dev service
   (`tools/local-jev/service.js` on `127.0.0.1:8099`, started with
   `VERA_LAYA_CLI` + `VERA_LAYA_MANIFEST`) → `/tmp/eval/laya/`. Slow on the WSL box
   (times out on 15–25-question bodies); small bodies answer.

4. **`compare-eval.py`** — per-type agreement: cloud vs openJev vs Laya.

5. **`calibrate.py`** — global temperature, ECE, and per-type coverage/agreement at
   thresholds → a local-vs-cloud routing call.

6. **`laya-calibrate.py`** — the serving calibration for the on-device Laya bundle:
   fits temperature + min_confidence from the recorded device run
   (`laya_raw` logits vs `proxy-answers` cloud answers) and emits the
   `calibration` block for `laya-manifest.json` (provenance hashes included).
   In-sample, n≈109 — preliminary; re-run at scale before trusting thresholds.

## HiAI NPU graph port (host-side, no phone)

7. **`../hiai-gen.py`** — the HiAI ModelDef protobuf generator: emits the full
   22-layer Laya ModernBERT (or `--layers N` for truncated test models) as a
   ge_ir.proto wire-format model from the numpy reference. Weight projections
   as FP16 Consts (the NPU's native dtype). `--out model.pb` +
   `model.pb.input` (the pre-norm embedding). **Format bugs (all found
   on-device):** packed varint `ShapeDef.dim`, "name:port" input refs,
   DT_INT32 Reshape shape Consts. The attention transpose (adj_x2 for
   MatMul/BatchMatMul) is BLOCKED by shape inference on both HiAI 106 and
   107 — see docs/local-jev/replacement-analysis.md §7.11.

8. **`../hiai_exec.py`** — the offline executor: re-parses the emitted
   protobuf and interprets the ops in numpy (MatMul/adj, Add, Mul, LayerNorm,
   Softmax, SplitD, ConcatD, Activation, Reshape, BatchMatMul/adj, packed
   dims, int32 Consts). The offline validation loop: run hiai-gen.py with
   exec to compare the graph logits against the reference — 0.0017 for the
   full 22-layer model, 0.04 for 2-layer (FP16 storage noise).

## Caveat

The sample is ~75 choice questions over 8 fixtures (n = 2–13 per type), enough for
the routing split but not final thresholds. §5.A of the analysis calls for
200–500 labelled decisions per task — re-run `calibrate.py` on the Phase-0 at-scale
logs before trusting per-type thresholds.

9. **`state-condense.py`** — the condensed-state measurement for the pipeline
   change of handing the on-device model a shorter state: runs the host scorer
   on a body's full state and on truncated variants, applies the serving
   calibration from the bundle manifest, and reports argmax flips, served-set
   changes, cloud agreement on the declined questions, and the forward time
   (model load excluded, via `LOCAL_JEV_TRACE`). Inputs are a body file, a
   bodies directory, or a run-log recorded with `--ps jevLocalLog 1`. The bar is
   the one prefix-KV failed: near-zero argmax flips.

   ```bash
   python tools/local-jev/eval/state-condense.py \
     --runlog <pulled run-log.jsonl> --bundle .local-jev/bundle-q4
   ```
