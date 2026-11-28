# Building & deploying the on-device local Jev (Candle-CPU)

The runner is PR #62's `native/local-jev` (Rust/Candle). It cross-compiles for
`aarch64-unknown-linux-ohos` and is linked into `liblocaljev.so` (CMake target
`localjev`), which the app imports through `VeraLocalNapi.ets` and registers at
startup (`setLocalDecisionModel`). The hybrid route (`askJevViaLocal` in
`VeraCompose.ets`) uses it as the local backend; an empty answer falls back to the
cloud.

## 1. Cross-build the Rust static lib (host)

For **host-side experiments** (`local-laya --bundle ...`), build with
`RUSTFLAGS="-C target-cpu=native"` — candle's quantized kernels gate their SIMD
paths on compile-time `target_feature`s (`avx2` on x86, `neon` on aarch64), and
x86's default baseline is SSE2: without the flag the Q4 dot products run the
scalar fallback, **7.6× slower** (measured: a 6-question body 117 s → 15 s). The
aarch64-ohos cross-build needs nothing — `neon` is default-on for that target.
`LOCAL_JEV_TRACE=1` prints phase timings (tokenize / infer / marker) to stderr.

```bash
export OHOS=$HOME/ohos-sdk/<version>/native; BIN=$OHOS/llvm/bin
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER=$BIN/aarch64-unknown-linux-ohos-clang
export CC_aarch64_unknown_linux_ohos=$BIN/aarch64-unknown-linux-ohos-clang
export CXX_aarch64_unknown_linux_ohos=$BIN/aarch64-unknown-linux-ohos-clang++
export AR_aarch64_unknown_linux_ohos=$BIN/llvm-ar
export CARGO_TARGET_DIR=$HOME/vlj/target-ohos
# optional: embed calibrated weights (else the build has empty consts):
#   export LAYA_BUNDLE_DIR=<bundle dir with the .gguf manifest>
cargo build --locked --release --lib --target aarch64-unknown-linux-ohos \
  --manifest-path native/local-jev/Cargo.toml
# -> $CARGO_TARGET_DIR/aarch64-unknown-linux-ohos/release/liblocal_jev.a
```

## 2. Link it into the app

Set the archive path in `entry/build-profile.json5` (this file is machine-local;
do **not** commit the path):

```json5
"externalNativeOptions": {
  "arguments": "-DVERA_LOCAL_JEV_ARCHIVE=/abs/path/to/liblocal_jev.a", ...
}
```

The committed `CMakeLists.txt` reads `VERA_LOCAL_JEV_ARCHIVE` from `-D` (or the
environment); with nothing set it builds a stub `liblocaljev.so` and the app
falls back to the cloud. A fresh CMake configure is needed after changing the
argument (delete `entry/.cxx/.../CMakeCache.txt`).

## 3. Build (and install)

```bash
./build-hap.sh --unsigned     # then ./sign-system.sh, ./update-phone.sh, etc.
```

## Troubleshooting: phone not appearing in `hdc` (usbipd → WSL)

A single `usbipd attach --wsl --busid <id>` can **race the phone's first USB
enumeration**: it attaches, then immediately drops —
`vhci_hcd: connection closed`, or `usb 1-1: device descriptor read/all, error -62`
(ETIME). Repeated detach/attach, `modprobe -r/-a vhci_hcd`, and re-plugging do not
reliably clear it. The reliable fix is **`--auto-attach`**, which retries through
the transient until a clean enumeration succeeds:

```
usbipd attach --wsl --busid <id> --auto-attach
```

It stays in the foreground (keep it running); once attached, `lsusb` shows
`12d1:1101 HDC Device` and `hdc list targets` shows the serial.

## Status (host-validated 2026-11-23; serving on-device 2026-11-24)

- **Candle cross-compiles for aarch64-ohos** — `liblocal_jev.a`.
- **The NAPI integrates** — `liblocaljev.so` links and the HAP builds with **0 diagnostics**.
- **Empty-bundle build is safe**: `local_jev_predict` returns empty answers, which
  the hybrid route treats as "ask the cloud".
- **The public Laya bundle now serves real local decisions** (2026-11-24): a
  calibration fitted from the recorded device run (T\*=2.2, min_confidence 0.71 —
  `tools/local-jev/eval/laya-calibrate.py`) sits in the bundle's
  `laya-manifest.json`, and `local_jev_predict` runs the batched scorer through it
  instead of the unconditional `laya_not_human_calibrated` gate. Low-confidence
  questions are simply absent from the answers and the app asks the cloud for
  exactly those (`unansweredJevBody` in VeraLocalDecision.ets); `expr`/`show`
  questions never reach the local model at all (cloud-tier prefixes). A real
  generation on the phone logged `VERA-JEVLOCAL local answered 8/16` and produced
  a correct, compiled, rendered app.
- **Serving cost**: the 16-question easy half of that body took **~84 s → ~80 s** on the
  Kirin CPU (~5 s/question; ~1.5 s only on the short fixture bodies) — one-time model
  load ~5 s included. This makes a hybrid generation ~85 s vs ~11 s all-cloud. Tuning
  was measured, not guessed: the matmuls are already rayon-parallel (~5.3 of 8 cores
  busy during inference — candle uses `Parallelism::Rayon(num_cpus)`); raising the
  question batch 4→8 gained ~5%; halving `max_len` 1024→512 gained only ~3% with
  identical answers, so the cost is **not** attention/length-bound and truncating state
  is not worth it (config kept at 1024). The structural levers, one now measured:
  - **Shared state encoding (prefix KV) — implemented and REJECTED (2026-11-25).**
    The state is encoded once per body and each question attends to the cached
    per-layer K/V (`prefix_state` in the bundle config, default off; the parity
    harness is `tools/local-jev/eval/prefix-parity.py`). Host-measured: the
    **speedup is real (1.52–1.63×)** over the 8 fixture bodies, but the
    approximation is not sound — the state's bidirectional interaction with the
    question is signal, not redundancy: **27.7% of argmax picks change**, mean
    logit drift 0.8, confidence systematically drops on the `steps` types the
    calibration serves, and a prefix-specific calibration refit caps at ~85–87%
    cloud-agreement vs the exact path's 94.4%. Not shippable; kept behind the
    flag for a model trained with a state-first layout, where it would be exact.
  - **Better Q4 kernels** (candle's run at ~4 GFLOPS effective on the phone — a
    llama.cpp-grade rewrite).
  - **The NPU** (§7.11) or **decision caching** (§5.C of the analysis).
  - A smaller model is **not** a speed lever: openJev-151M shares Laya's encoder
    (§7.6's corrected math) — same FLOPs; it is a bundle-size and
    calibration-quality option.
- **Size**: with the bundle embedded, a **284 MB HAP / 233 MB `liblocaljev.so`**
  (0.71-threshold Q4 bundle). The empty-bundle build (17 MB `.so`) is for daily
  use without local serving.

## On-device validation (2026-11-24, Kirin 9010, engineering Mate 70)

Deployed with embedded Laya Q4 weights and run via
`hdc shell aa start -a EntryAbility -b com.vera.probe.dyn --ps localJevSpike 1`:

- The NAPI loads (`abi=1`). Candle **runs the model on the device CPU**: a
  `diagnosticScores` call (cold — model load + a 3-question forward pass) took
  **5261 ms** and returned real diagnostic output (model name, per-question
  truncation) with no NaN or crash.
- `predict` returned the uncalibrated gate (`{"answers":{}}`) in ~1 ms without
  re-running inference (this was the pre-calibration morning run; the calibrated
  build serves — see the status above).
- This was a **284 MB HAP / 223 MB `liblocaljev.so`** (weights embedded; the current
  calibrated build links 233 MB). For daily use the empty-bundle build (17 MB `.so`)
  does not serve local decisions — it has no embedded weights, so predict reports
  `model_unavailable` and the route answers from the cloud — at a fraction of the
  size; embed weights to serve locally or run on-device inference tests.

So the on-device path is proven end to end (NAPI → Candle → Kirin CPU) **and now
serves real decisions in real generations** (see the status above). What remains is the
at-scale per-type calibration refit (§5.A of `replacement-analysis.md`) and speed:
per-question warm latency on real bodies is ~5 s (the 5261 ms cold figure above
includes the one-time model load).