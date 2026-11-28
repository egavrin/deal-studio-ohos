//! Experimental quantized Laya. Serving answers requires a manifest calibration;
//! without one, predict stays gated and diagnostic scores never authorize production answers.
use crate::laya_backbone::{attention, Config as EncoderConfig, ModernBert};
use crate::{parse_diagnostic_request, uncertain, Question, Request};
use candle_core::{DType, Device, IndexOp, Tensor};
use candle_nn::LayerNorm;
use candle_transformers::{
    quantized_nn::{self as qnn, Linear},
    quantized_var_builder::VarBuilder,
};
use serde::Deserialize;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeMap, BTreeSet},
    path::Path,
    time::{Duration, Instant},
};
use tokenizers::Tokenizer;

const CALL_TOKENS: usize = 8192;
// Questions per forward pass. The matmuls are rayon-parallel (candle:
// Parallelism::Rayon(num_cpus)), so a larger batch amortizes the serial phases
// (softmax/layernorm/quantize, tokenization) across the parallel ones;
// batch_len still bounds padding waste and the call token budget.
const MAX_BATCH_QUESTIONS: usize = 8;
const HEAD_INSTRUCTION_RESERVE: usize = 16;
const OPTION_PAYLOAD_LIMIT: usize = 256;

#[derive(Deserialize)]
pub struct Config {
    encoder_config: EncoderConfig,
    /// Share the state encoding across questions (prefix KV cache): the state
    /// is encoded once per body and each question's own tokens attend to the
    /// cache -- an approximation (encoders are bidirectional; the state's
    /// representations no longer see the questions). The head is unaffected:
    /// its attention is position-free, and the type embedding is post-encoder.
    ///
    /// MEASURED (2026-11-25, prefix-parity.py): 1.52-1.63x faster but NOT
    /// sound -- 27.7% of argmax picks change and a prefix-specific calibration
    /// refit caps at ~85-87% cloud-agreement vs 94.4% exact. Default OFF; enable
    /// only for a model trained with a state-first layout (then it is exact).
    #[serde(default)]
    prefix_state: Option<bool>,
    head_layers: usize,
    max_len: usize,
    head_max_len: usize,
    temperature: Vec<f64>,
    cls_token_id: u32,
    sep_token_id: u32,
    mask_token_id: u32,
    mask_token: String,
}

/// Serving calibration, from the manifest's `calibration` block. Fitted on the
/// 2026-11-24 device run against the cloud's answers (agreement calibration,
/// not ground truth -- see tools/local-jev/eval/laya-calibrate.py); `calibrated`
/// is the gate that turns the Laya predict path on.
#[derive(Deserialize, Clone, Copy)]
pub struct Calibration {
    pub calibrated: bool,
    pub temperature: f64,
    pub min_confidence: f64,
}

impl Calibration {
    fn valid(&self) -> bool {
        self.temperature.is_finite()
            && self.temperature > 0.
            && self.min_confidence.is_finite()
            && (0.5..=1.).contains(&self.min_confidence)
    }
}

struct HeadLayer {
    input: Linear,
    output: Linear,
    norm1: LayerNorm,
    norm2: LayerNorm,
    linear1: Linear,
    linear2: Linear,
}
impl HeadLayer {
    fn load(vb: VarBuilder, dim: usize) -> candle_core::Result<Self> {
        let input = Linear::from_arc(
            vb.pp("self_attn").get((dim * 3, dim), "in_proj_weight")?,
            Some(
                vb.pp("self_attn")
                    .get(dim * 3, "in_proj_bias")?
                    .dequantize(vb.device())?,
            ),
        )?;
        Ok(Self {
            input,
            output: qnn::linear(dim, dim, vb.pp("self_attn.out_proj"))?,
            norm1: qnn::layer_norm(dim, 1e-5, vb.pp("norm1"))?,
            norm2: qnn::layer_norm(dim, 1e-5, vb.pp("norm2"))?,
            linear1: qnn::linear(dim, dim * 4, vb.pp("linear1"))?,
            linear2: qnn::linear(dim * 4, dim, vb.pp("linear2"))?,
        })
    }
    fn forward(&self, x: &Tensor, lengths: Option<&[usize]>) -> candle_core::Result<Tensor> {
        let (b, n, dim) = x.dims3()?;
        let heads = dim / 64;
        let qkv = x
            .apply(&self.norm1)?
            .apply(&self.input)?
            .reshape((b, n, 3, heads, 64))?
            .permute((2, 0, 3, 1, 4))?;
        let q = (qkv.i(0)?.contiguous()? / 8.)?;
        let k = qkv.i(1)?.contiguous()?;
        let v = qkv.i(2)?.contiguous()?;
        let attention = attention(&q, &k, &v, None, lengths)?
            .transpose(1, 2)?
            .reshape((b, n, dim))?
            .apply(&self.output)?;
        let h = (x + attention)?;
        let ff = h
            .apply(&self.norm2)?
            .apply(&self.linear1)?
            .relu()?
            .apply(&self.linear2)?;
        h + ff
    }
}

struct PreparedQuestion<'a> {
    key: &'a str,
    kind: &'a str,
    ids: Vec<u32>,
    markers: Vec<usize>,
    options: Vec<String>,
    truncation: Value,
}

impl PreparedQuestion<'_> {
    fn kind_index(&self) -> u32 {
        if self.kind == "choice" {
            0
        } else {
            2
        }
    }
}

fn batch_len(questions: &[PreparedQuestion<'_>]) -> usize {
    let mut real_cells = 0;
    let mut count = 0;
    for question in questions.iter().take(MAX_BATCH_QUESTIONS) {
        let n = question.ids.len();
        real_cells += n * n;
        let rows = count + 1;
        // Limit extra attention work to 25 percent for each length-sorted group.
        if rows * n > CALL_TOKENS || 4 * rows * n * n > 5 * real_cells {
            break;
        }
        count = rows;
    }
    count
}

fn allocate_options(source: &[Vec<u32>], head_max_len: usize) -> Result<Vec<Vec<u32>>, String> {
    let per = (head_max_len - HEAD_INSTRUCTION_RESERVE) / source.len();
    if per < 2 {
        return Err("head_token_budget".into());
    }
    let mut spans: Vec<_> = source
        .iter()
        .map(|tokens| tokens[..tokens.len().min(per - 1)].to_vec())
        .collect();
    let mut counts = BTreeMap::new();
    for span in &spans {
        *counts.entry(span.clone()).or_insert(0usize) += 1;
    }
    let mut used: BTreeSet<_> = counts
        .iter()
        .filter(|&(_, &count)| count == 1)
        .map(|(span, _)| span.clone())
        .collect();
    for (tokens, span) in source.iter().zip(&mut spans) {
        if counts[span] == 1 || used.insert(span.clone()) {
            continue;
        }
        let k = span.len();
        let mut replacement = None;
        'search: for prefix in (0..k).rev() {
            let tail = k - prefix;
            for start in prefix + 1..=tokens.len() - tail {
                let candidate: Vec<_> = tokens[..prefix]
                    .iter()
                    .chain(&tokens[start..start + tail])
                    .copied()
                    .collect();
                if used.insert(candidate.clone()) {
                    replacement = Some(candidate);
                    break 'search;
                }
            }
        }
        *span = replacement.ok_or("option_tokens_collapsed")?;
    }
    Ok(spans)
}

#[derive(Default)]
pub(crate) struct ScoreTimings {
    pub preparation: Duration,
    pub forward: Duration,
}

fn measure<T>(elapsed: Option<&mut Duration>, run: impl FnOnce() -> T) -> T {
    if let Some(elapsed) = elapsed {
        let start = Instant::now();
        let result = run();
        *elapsed += start.elapsed();
        result
    } else {
        run()
    }
}

pub struct Engine {
    encoder: ModernBert,
    head: Vec<HeadLayer>,
    type_embedding: Tensor,
    norm: LayerNorm,
    scorer1: Linear,
    scorer2: Linear,
    tokenizer: Tokenizer,
    config: Config,
    calibration: Option<Calibration>,
    /// Registered NPU serving buckets (path, batch, seq), in registration
    /// order; the group picks the smallest bucket that fits.
    npu_specs: Vec<(String, usize, usize)>,
    /// Lazily-compiled bucket instances, aligned with npu_specs. Engine is
    /// only used under its global Mutex, so RefCell is safe here.
    npu_buckets: std::cell::RefCell<Vec<Option<crate::npu::NpuForward>>>,
}

impl Engine {
    pub fn from_dir(path: &Path) -> Result<Self, String> {
        let names = [
            "laya-config.json",
            "tokenizer.json",
            "model.gguf",
            "laya-manifest.json",
        ];
        let size = names
            .iter()
            .try_fold(0u64, |total, name| {
                std::fs::metadata(path.join(name)).map(|m| total + m.len())
            })
            .map_err(|e| e.to_string())?;
        if size > 300_000_000 {
            return Err("assets_exceed_budget".into());
        }
        let data: Vec<_> = names
            .iter()
            .map(|name| std::fs::read(path.join(name)))
            .collect::<std::io::Result<_>>()
            .map_err(|e| e.to_string())?;
        Self::from_bytes(&data[0], &data[1], &data[2], &data[3])
    }
    pub fn embedded() -> Result<Self, String> {
        Self::from_bytes(
            crate::assets::LAYA_CONFIG,
            crate::assets::LAYA_TOKENIZER,
            crate::assets::LAYA_WEIGHTS,
            crate::assets::LAYA_MANIFEST,
        )
    }
    fn from_bytes(
        config: &[u8],
        tokenizer: &[u8],
        weights: &[u8],
        manifest: &[u8],
    ) -> Result<Self, String> {
        let load = || -> Result<Self, Box<dyn std::error::Error>> {
            if config.len() + tokenizer.len() + weights.len() + manifest.len() > 300_000_000 {
                return Err("assets_exceed_budget".into());
            }
            let manifest: Value = serde_json::from_slice(manifest)?;
            if manifest["format"] != "laya-gguf-mixed-v1"
                && manifest["format"] != "laya-gguf-q4k-v1"
                && manifest["format"] != "laya-gguf-q4_0-v1"
            {
                return Err("unsupported_manifest".into());
            }
            for (name, bytes) in [
                ("laya-config.json", config),
                ("tokenizer.json", tokenizer),
                ("model.gguf", weights),
            ] {
                if manifest["asset_sha256"][name].as_str()
                    != Some(format!("{:x}", Sha256::digest(bytes)).as_str())
                {
                    return Err("asset_hash_mismatch".into());
                }
            }
            let cfg: Config = serde_json::from_slice(config)?;
            let ec = &cfg.encoder_config;
            if !ec.supported_architecture()
                || ec.vocab_size != 256000
                || ec.intermediate_size != 1152
                || ec.global_attn_every_n_layers != 3
                || ec.local_attention != 128
                || !ec.layer_norm_eps.is_finite()
                || ec.layer_norm_eps <= 0.
                || !ec.global_rope_theta.is_finite()
                || ec.global_rope_theta <= 0.
                || !ec.local_rope_theta.is_finite()
                || ec.local_rope_theta <= 0.
                || cfg.max_len == 0
                || cfg.max_len > 1024
                || ec.max_position_embeddings > 8192
                || cfg.max_len > ec.max_position_embeddings
                || cfg.head_max_len < HEAD_INSTRUCTION_RESERVE
                || cfg.head_max_len > cfg.max_len
                || [cfg.cls_token_id, cfg.sep_token_id, cfg.mask_token_id]
                    .iter()
                    .any(|id| *id as usize >= ec.vocab_size)
            {
                return Err("unsupported_laya_architecture".into());
            }
            if cfg.temperature.len() != 3
                || cfg.temperature.iter().any(|x| !x.is_finite() || *x <= 0.)
                || cfg.head_layers != 2
            {
                return Err("invalid_laya_config".into());
            }
            // Serving calibration (optional block): when present and declaring
            // itself calibrated, its parameters must be usable -- same bounds as
            // the openJev manifest gate in lib.rs. Provenance hashes are checked
            // by the caller-facing manifest tooling, not the engine.
            let calibration: Option<Calibration> = manifest
                .get("calibration")
                .map(|c| serde_json::from_value(c.clone()))
                .transpose()
                .map_err(|_| "invalid_laya_calibration".to_string())?;
            if calibration.is_some_and(|c| c.calibrated && !c.valid()) {
                return Err("invalid_laya_calibration".into());
            }
            let mut tok = Tokenizer::from_bytes(tokenizer).map_err(|e| e.to_string())?;
            // Upstream training can persist the last per-option truncation setting in tokenizer.json.
            tok.with_truncation(None).map_err(|e| e.to_string())?;
            tok.with_padding(None);
            let vb = VarBuilder::from_gguf_buffer(weights, &Device::Cpu)?;
            let dim = cfg.encoder_config.hidden_size;
            let encoder = ModernBert::load(vb.clone(), &cfg.encoder_config)?;
            let head = (0..cfg.head_layers)
                .map(|i| HeadLayer::load(vb.pp(format!("head.layers.{i}")), dim))
                .collect::<candle_core::Result<_>>()?;
            let type_embedding = vb
                .get((3, dim), "type_emb.weight")?
                .dequantize(&Device::Cpu)?;
            let npu_specs = crate::npu_graph_specs();
            let npu_buckets = std::cell::RefCell::new(
                npu_specs.iter().map(|_| None).collect::<Vec<_>>(),
            );
            Ok(Self {
                encoder,
                head,
                type_embedding,
                norm: qnn::layer_norm(dim, 1e-5, vb.pp("scorer.0"))?,
                scorer1: qnn::linear(dim, dim, vb.pp("scorer.1"))?,
                scorer2: qnn::linear(dim, 1, vb.pp("scorer.3"))?,
                tokenizer: tok,
                config: cfg,
                npu_specs,
                npu_buckets,
                calibration,
            })
        };
        load().map_err(|e| e.to_string())
    }
    fn tokens(&self, text: &str) -> Result<Vec<u32>, String> {
        self.tokenizer
            .encode(text.replace(&self.config.mask_token, " "), false)
            .map(|x| x.get_ids().to_vec())
            .map_err(|e| e.to_string())
    }
    /// The question's own tokens: [cls][instruction][sep][mask+options...][sep],
    /// with the option markers. No state -- the prefix path supplies it.
    fn build_head<'a>(
        &self,
        key: &'a str,
        q: &'a Question,
        capped: bool,
    ) -> Result<PreparedQuestion<'a>, String> {
        let options: Vec<_> = if q.kind == "noul" {
            [
                ("false", "no, the statement does not hold"),
                ("true", "yes, the statement holds"),
            ]
            .iter()
            .map(|(k, default)| {
                (
                    k.to_string(),
                    q.criteria.get(*k).cloned().unwrap_or(default.to_string()),
                )
            })
            .collect()
        } else {
            q.criteria
                .iter()
                .map(|(k, v)| (k.clone(), v.clone()))
                .collect()
        };
        let mut instruction = self.tokens(&format!("{} question: {}", q.kind, q.instructions))?;
        let original_instruction = instruction.len();
        let mut original_options = 0;
        let mut option_tokens = Vec::new();
        for (id, description) in &options {
            let mut tokens = self.tokens(&format!(" {id}: {description}"))?;
            // Option descriptions are capped at OPTION_PAYLOAD_LIMIT tokens (raised from
            // upstream's 48 so real criteria descriptions are not truncated).
            original_options += tokens.len();
            if tokens.len() > OPTION_PAYLOAD_LIMIT && !capped {
                return Err("option_token_budget".into());
            }
            if capped {
                tokens.truncate(OPTION_PAYLOAD_LIMIT);
            }
            option_tokens.push(tokens);
        }
        let head = self.config.head_max_len;
        // The head region plus the frame (cls + three seps + the final token)
        // must fit inside max_len. When head_max_len sits at max_len (the
        // untruncated config), a capped allocation budgeted against head alone
        // overflows max_len and errors -- even though capped mode exists to
        // degrade, not fail. So the capped path budgets against the reduced
        // head; the strict path keeps the exact head budgets it errors on.
        let effective = if capped {
            head.min(self.config.max_len.saturating_sub(4))
        } else {
            head
        };
        let mut spans: Vec<_> = option_tokens.iter().map(Vec::as_slice).collect();
        let mut used: usize = spans.iter().map(|tokens| tokens.len() + 1).sum();
        let mut budget = effective.saturating_sub(used);
        if budget < HEAD_INSTRUCTION_RESERVE {
            if !capped {
                return Err("head_token_budget".into());
            }
            let per = (effective.saturating_sub(HEAD_INSTRUCTION_RESERVE) / spans.len()).max(4);
            for tokens in &mut spans {
                *tokens = &tokens[..tokens.len().min(per - 1)];
            }
            used = spans.iter().map(|tokens| tokens.len() + 1).sum();
            budget = effective.saturating_sub(used);
        }
        if instruction.len() > budget.max(8) && !capped {
            return Err("head_token_budget".into());
        }
        let collapsed = spans.iter().copied().collect::<BTreeSet<_>>().len() != spans.len();
        let repaired =
            capped && (collapsed || used + instruction.len().min(budget.max(8)) > effective);
        let repaired_options;
        if repaired {
            repaired_options =
                allocate_options(&option_tokens, effective.max(HEAD_INSTRUCTION_RESERVE))?;
            spans = repaired_options.iter().map(Vec::as_slice).collect();
            used = spans.iter().map(|tokens| tokens.len() + 1).sum();
            budget = effective.saturating_sub(used);
        } else if collapsed {
            return Err("option_tokens_collapsed".into());
        }
        if capped {
            instruction.truncate(budget.max(8));
        }
        let kept_instruction = instruction.len();
        let mut ids = vec![self.config.cls_token_id];
        ids.append(&mut instruction);
        ids.push(self.config.sep_token_id);
        let mut markers = Vec::new();
        for tokens in spans {
            markers.push(ids.len());
            ids.push(self.config.mask_token_id);
            ids.extend_from_slice(tokens);
        }
        ids.push(self.config.sep_token_id);
        if ids.len() > self.config.max_len {
            return Err("option_token_budget".into());
        }
        let kept_options = used - options.len();
        let mut truncation = json!({"instruction_tokens_dropped":original_instruction-kept_instruction,
            "option_tokens_dropped":original_options-kept_options,"state_tokens_dropped":0,
            "truncated": original_instruction>kept_instruction || original_options>kept_options});
        if repaired {
            truncation["option_budget_repaired"] = json!(true);
        }
        Ok(PreparedQuestion {
            key,
            kind: &q.kind,
            ids,
            markers,
            options: options.into_iter().map(|(k, _)| k).collect(),
            truncation,
        })
    }

    /// The full per-question sequence: the head part plus the state. The head
    /// builder is shared with the prefix path, which encodes the state once.
    fn sequence<'a>(
        &self,
        state_tokens: &[u32],
        key: &'a str,
        q: &'a Question,
        capped: bool,
    ) -> Result<PreparedQuestion<'a>, String> {
        let mut prepared = self.build_head(key, q, capped)?;
        let original_state = state_tokens.len();
        let room = self
            .config
            .max_len
            .saturating_sub(prepared.ids.len() + 1);
        if original_state > room && !capped {
            return Err("state_token_budget".into());
        }
        let kept_state = original_state.min(room);
        prepared.ids.extend_from_slice(&state_tokens[..kept_state]);
        prepared.ids.push(self.config.sep_token_id);
        if prepared.ids.len() > self.config.max_len {
            return Err("option_token_budget".into());
        }
        if original_state > kept_state {
            let dropped = json!(original_state - kept_state);
            prepared.truncation["state_tokens_dropped"] = dropped.clone();
            prepared.truncation["truncated"] = json!(true);
        }
        Ok(prepared)
    }
    pub fn scores(&self, body: &str) -> Result<Value, String> {
        self.score(body, false, false, None, None)
    }
    pub fn diagnostic_scores(&self, body: &str) -> Result<Value, String> {
        self.score(body, true, false, None, None)
    }
    pub fn batched_scores(
        &self,
        body: &str,
        capped: bool,
        batch_lengths: Option<&mut Vec<Vec<usize>>>,
    ) -> Result<Value, String> {
        self.score(body, capped, true, batch_lengths, None)
    }
    pub(crate) fn benchmark_scores(
        &self,
        body: &str,
        batched: bool,
        batch_lengths: &mut Vec<Vec<usize>>,
        timings: &mut ScoreTimings,
    ) -> Result<Value, String> {
        self.score(body, true, batched, Some(batch_lengths), Some(timings))
    }
    fn score(
        &self,
        body: &str,
        capped: bool,
        batched: bool,
        mut batch_lengths: Option<&mut Vec<Vec<usize>>>,
        mut timings: Option<&mut ScoreTimings>,
    ) -> Result<Value, String> {
let request = parse_diagnostic_request(body)?;
        if self.config.prefix_state.unwrap_or(false) {
            return self.score_prefix(&request, capped, batched, batch_lengths);
        }
        // Preflight every question before model execution.
        // Phase timings print to stderr when LOCAL_JEV_TRACE is set (host runs;
        // the NAPI stderr is not visible on device).
        let trace = std::env::var_os("LOCAL_JEV_TRACE").is_some();
        let started = Instant::now();
        let timings_started = timings.as_ref().map(|_| Instant::now());
        let state_tokens = self.tokens(&request.state)?;
        let mut sequences = request
            .questions
            .iter()
            .map(|(key, q)| self.sequence(&state_tokens, key, q, capped))
            .collect::<Result<Vec<_>, _>>()?;
        let tokenized = started.elapsed();
        if sequences.iter().map(|q| q.ids.len()).sum::<usize>() > CALL_TOKENS {
            return Err("call_token_budget".into());
        }
        if batched {
            sequences.sort_by_key(|q| q.ids.len());
        }
let seq_min = sequences.iter().map(|q| q.ids.len()).min().unwrap_or(0);
        let seq_max = sequences.iter().map(|q| q.ids.len()).max().unwrap_or(0);
        if let (Some(timings), Some(timings_started)) = (&mut timings, timings_started) {
            timings.preparation = timings_started.elapsed();
        }
        let mut output = BTreeMap::new();
        let mut truncations = BTreeMap::new();
        let mut remaining = sequences.as_slice();
        let mut infer_ns = std::time::Duration::ZERO;
        let mut marker_ns = std::time::Duration::ZERO;
        let mut groups = 0usize;
        while !remaining.is_empty() {
            let count = if batched { batch_len(remaining) } else { 1 };
            let (group, rest) = remaining.split_at(count);
            remaining = rest;
            if let Some(report) = &mut batch_lengths {
                report.push(group.iter().map(|q| q.ids.len()).collect());
            }
groups += 1;
            let t0 = Instant::now();
            let hidden = measure(timings.as_deref_mut().map(|t| &mut t.forward), || {
                self.infer_group(group)
            })
            .map_err(|e| e.to_string())?;
            infer_ns += t0.elapsed();
            for (row, question) in group.iter().enumerate() {
                let t1 = Instant::now();
                let values = measure(timings.as_deref_mut().map(|t| &mut t.forward), || {
                    self.marker_scores(&hidden, row, &question.markers)
                })
                .map_err(|e| e.to_string())?;
                marker_ns += t1.elapsed();
                if values.iter().any(|v| !v.is_finite()) {
                    return Err("nonfinite_scores".into());
                }
                truncations.insert(question.key, &question.truncation);
                let logits = question
                    .options
                    .iter()
                    .zip(values)
                    .collect::<BTreeMap<_, _>>();
                output.insert(question.key, json!({"type":question.kind,"logits":logits}));
            }
        }
        if trace {
            eprintln!(
                "LOCAL_JEV_TRACE questions={} groups={} seq_tokens={}..{} tokenize_ms={} infer_ms={} marker_ms={} total_ms={}",
                request.questions.len(),
                groups,
                seq_min,
                seq_max,
                tokenized.as_millis(),
                infer_ns.as_millis(),
                marker_ns.as_millis(),
                started.elapsed().as_millis()
            );
        }
        Ok(
            json!({"answers":{},"scores":output,"local":{"status":"uncertain","reason":"laya_not_human_calibrated","model":"laya-multilingual-quantized","input_policy":if capped {"playground-upstream-token-caps"}else{"strict-no-truncation"},"truncation":truncations}}),
        )
    }
    /// The prefix-mode scorer (Config::prefix_state): encode the shared state
    /// once, then each question's own tokens attend to the cached per-layer
    /// K/V. The head runs over [prefix | question] hidden states -- exact for
    /// the head (position-free attention) and the type embedding
    /// (post-encoder); the approximation is the state's own representations,
    /// which no longer see the questions.
    fn score_prefix(
        &self,
        request: &Request,
        capped: bool,
        batched: bool,
        mut batch_lengths: Option<&mut Vec<Vec<usize>>>,
    ) -> Result<Value, String> {
        let trace = std::env::var_os("LOCAL_JEV_TRACE").is_some();
        let started = std::time::Instant::now();
        let mut sequences = request
            .questions
            .iter()
            .map(|(key, q)| self.build_head(key, q, capped))
            .collect::<Result<Vec<_>, _>>()?;
        let tokenized = started.elapsed();
        let mut state_tokens = self.tokens(&request.state)?;
        let max_q = sequences.iter().map(|q| q.ids.len()).max().unwrap_or(0);
        let room = self.config.max_len.saturating_sub(max_q + 1);
        let original_state = state_tokens.len();
        if state_tokens.len() > room {
            if !capped {
                return Err("state_token_budget".into());
            }
            state_tokens.truncate(room);
        }
        let mut prefix_ids = state_tokens;
        prefix_ids.push(self.config.sep_token_id);
        let prefix_len = prefix_ids.len();
        let state_dropped = original_state + 1 - prefix_len;
        if sequences.iter().map(|q| q.ids.len()).sum::<usize>() + prefix_len > CALL_TOKENS {
            return Err("call_token_budget".into());
        }
        if batched {
            sequences.sort_by_key(|q| q.ids.len());
        }
        let device = &Device::Cpu;
        let prefix_input =
            Tensor::from_slice(&prefix_ids, (1, prefix_ids.len()), device).map_err(|e| e.to_string())?;
        let prefix_mask = Tensor::ones((1, prefix_ids.len()), DType::U32, device).map_err(|e| e.to_string())?;
        let (layers, prefix_hidden) = self
            .encoder
            .encode_prefix(&prefix_input, &prefix_mask)
            .map_err(|e| e.to_string())?;
        let encoded = started.elapsed();
        let mut output = BTreeMap::new();
        let mut truncations: BTreeMap<&str, Value> = BTreeMap::new();
        let mut remaining = sequences.as_slice();
        let mut groups = 0usize;
        while !remaining.is_empty() {
            let count = if batched { batch_len(remaining) } else { 1 };
            let (group, rest) = remaining.split_at(count);
            remaining = rest;
            groups += 1;
            if let Some(report) = &mut batch_lengths {
                report.push(group.iter().map(|q| q.ids.len()).collect());
            }
            let b = group.len();
            let n = group[b - 1].ids.len();
            let mut ids = Vec::with_capacity(b * n);
            let mut mask = Vec::with_capacity(b * n);
            let mut lengths = Vec::with_capacity(b);
            let mut kinds = Vec::with_capacity(b);
            for (row, question) in group.iter().enumerate() {
                ids.extend_from_slice(&question.ids);
                ids.resize((row + 1) * n, self.config.cls_token_id);
                mask.resize(row * n + question.ids.len(), 1u32);
                mask.resize((row + 1) * n, 0);
                lengths.push(prefix_len + question.ids.len());
                kinds.push(question.kind_index());
            }
            let input = Tensor::from_vec(ids, (b, n), device).map_err(|e| e.to_string())?;
            let qmask = Tensor::from_vec(mask, (b, n), device).map_err(|e| e.to_string())?;
            let hidden_q = self
                .encoder
                .forward_with_prefix(&input, &qmask, &layers)
                .map_err(|e| e.to_string())?;
            let dim = self.config.encoder_config.hidden_size;
            let kind_emb = self
                .type_embedding
                .index_select(&Tensor::new(kinds, device).map_err(|e| e.to_string())?, 0)
                .and_then(|k| k.reshape((b, 1, dim)))
                .map_err(|e| e.to_string())?;
            let prefix_h = prefix_hidden
                .broadcast_as((b, prefix_len, dim))
                .and_then(|p| p.broadcast_add(&kind_emb))
                .map_err(|e| e.to_string())?;
            let q_h = hidden_q
                .broadcast_add(&kind_emb)
                .map_err(|e| e.to_string())?;
            let mut h = Tensor::cat(&[prefix_h, q_h], 1).map_err(|e| e.to_string())?;
            for layer in &self.head {
                h = layer.forward(&h, Some(&lengths)).map_err(|e| e.to_string())?;
            }
            for (row, question) in group.iter().enumerate() {
                let markers: Vec<usize> =
                    question.markers.iter().map(|m| m + prefix_len).collect();
                let values = self
                    .marker_scores(&h, row, &markers)
                    .map_err(|e| e.to_string())?;
                if values.iter().any(|v| !v.is_finite()) {
                    return Err("nonfinite_scores".into());
                }
                let mut truncation = question.truncation.clone();
                if state_dropped > 0 {
                    truncation["state_tokens_dropped"] = json!(state_dropped);
                    truncation["truncated"] = json!(true);
                }
                truncations.insert(question.key, truncation);
                let logits = question
                    .options
                    .iter()
                    .zip(values)
                    .collect::<BTreeMap<_, _>>();
                output.insert(question.key, json!({"type":question.kind,"logits":logits}));
            }
        }
        if trace {
            eprintln!(
                "LOCAL_JEV_TRACE(prefix) questions={} groups={} prefix_tokens={} total_ms={} encode_prefix_ms={} tokenize_ms={}",
                request.questions.len(),
                groups,
                prefix_len,
                started.elapsed().as_millis(),
                (encoded - tokenized).as_millis(),
                tokenized.as_millis()
            );
        }
        Ok(
            json!({"answers":{},"scores":output,"local":{"status":"uncertain","reason":"laya_not_human_calibrated","model":"laya-multilingual-quantized","input_policy":if capped {"playground-upstream-token-caps"}else{"strict-no-truncation"},"truncation":truncations}}),
        )
    }
    fn infer_group(&self, group: &[PreparedQuestion<'_>]) -> candle_core::Result<Tensor> {
        let device = &Device::Cpu;
        // The NPU serving buckets: pick the smallest registered bucket whose
        // batch and padded seq fit the group. The graph computes the encoder,
        // the final norm, the type add and the head layers; the marker scorer
        // runs on the returned hidden states exactly as for the candle path.
        // The bucket is compiled lazily on first use and kept for the process.
        if !self.npu_specs.is_empty() {
            let max_len = group.iter().map(|q| q.ids.len()).max().unwrap_or(0);
            if let Some(idx) = self.pick_bucket(group.len(), max_len) {
                // Lazily compiled: the first group that needs a bucket pays
                // its build (persisted: a later cold start restores it).
                let npu = self.take_bucket(idx).or_else(|| self.compile_bucket(idx));
                if let Some(npu) = npu {
                    let hidden = self.npu_group_forward(&npu, group);
                    let (s, d) = (self.npu_specs[idx].2, npu.dim);
                    self.put_bucket(idx, npu);
                    if let Some(hidden) = hidden {
                        let b = group.len();
                        return Tensor::from_vec(hidden, (b, s, d), device);
                    }
                }
            }
        }
        if let [question] = group {
            let n = question.ids.len();
            let input = Tensor::from_slice(&question.ids, (1, n), device)?;
            let mask = Tensor::ones((1, n), DType::U32, device)?;
            let kind = self.type_embedding.i(question.kind_index() as usize)?;
            return self.forward(&input, &mask, &kind, None);
        }

        let b = group.len();
        let n = group[b - 1].ids.len();
        let mut ids = Vec::with_capacity(b * n);
        let mut mask = Vec::with_capacity(b * n);
        let mut kinds = Vec::with_capacity(b);
        let mut lengths = Vec::with_capacity(b);
        for (row, question) in group.iter().enumerate() {
            ids.extend_from_slice(&question.ids);
            // Use a validated token ID for padding that the attention masks hide.
            ids.resize((row + 1) * n, self.config.cls_token_id);
            mask.resize(row * n + question.ids.len(), 1u32);
            mask.resize((row + 1) * n, 0);
            kinds.push(question.kind_index());
            lengths.push(question.ids.len());
        }
        let input = Tensor::from_vec(ids, (b, n), device)?;
        let mask = Tensor::from_vec(mask, (b, n), device)?;
        let kinds = self
            .type_embedding
            .index_select(&Tensor::new(kinds, device)?, 0)?;
        let padded = lengths[0] < n;
        self.forward(&input, &mask, &kinds, padded.then_some(lengths.as_slice()))
    }
    fn forward(
        &self,
        input: &Tensor,
        mask: &Tensor,
        kinds: &Tensor,
        lengths: Option<&[usize]>,
    ) -> candle_core::Result<Tensor> {
        let b = input.dim(0)?;
        let kinds = kinds.reshape((b, 1, self.config.encoder_config.hidden_size))?;
        let mut hidden = self
            .encoder
            .forward(input, mask, lengths)?
            .broadcast_add(&kinds)?;
        for layer in &self.head {
            hidden = layer.forward(&hidden, lengths)?;
        }
        Ok(hidden)
    }
    /// Build the NPU graph inputs (raw embeddings, padding mask, type add)
    /// from the prepared questions and run it. None on any failure: the
    /// caller falls back to candle.
    /// The smallest registered bucket that fits the group; None when no
    /// bucket does (the candle path serves).
    fn pick_bucket(&self, batch: usize, max_len: usize) -> Option<usize> {
        let mut best: Option<usize> = None;
        for (idx, (_, b, s)) in self.npu_specs.iter().enumerate() {
            if batch <= *b && max_len <= *s {
                let better = match best {
                    None => true,
                    Some(j) => *s < self.npu_specs[j].2,
                };
                if better {
                    best = Some(idx);
                }
            }
        }
        best
    }

    /// Take the bucket out of its slot (a taken bucket is absent while in
    /// use; a failed forward or a panic just drops it -- the next group
    /// recompiles, and candle serves in the meantime).
    fn take_bucket(&self, idx: usize) -> Option<crate::npu::NpuForward> {
        let mut guard = self.npu_buckets.borrow_mut();
        guard.get_mut(idx).and_then(|slot| slot.take())
    }

    /// Compile (or restore) the bucket from its spec. None on any failure:
    /// the group falls back to candle.
    fn compile_bucket(&self, idx: usize) -> Option<crate::npu::NpuForward> {
        let (path, batch, seq) = &self.npu_specs[idx];
        let dim = self.config.encoder_config.hidden_size;
        crate::npu::NpuForward::try_new(Path::new(path), *batch, *seq, dim)
    }

    /// Return the bucket to its slot.
    fn put_bucket(&self, idx: usize, npu: crate::npu::NpuForward) {
        let mut guard = self.npu_buckets.borrow_mut();
        if let Some(slot) = guard.get_mut(idx) {
            *slot = Some(npu);
        }
    }

    fn npu_group_forward(&self, npu: &crate::npu::NpuForward, group: &[PreparedQuestion<'_>]) -> Option<Vec<f32>> {
        let (b, s, dim) = (npu.batch, npu.seq, npu.dim);
        let bs = b * s;
        let mut emb = vec![0f32; bs * dim];
        let mut tadd = vec![0f32; bs * dim];
        let mut pmask = vec![-1e4f32; b * s * s];
        for (slot, question) in group.iter().enumerate() {
            let len = question.ids.len().min(s);
            if len == 0 {
                continue;
            }
            let rows = self.encoder.embed_rows(&question.ids).ok()?;
            let base = slot * s;
            emb[base * dim..(base + len) * dim].copy_from_slice(&rows[..len * dim]);
            // The type vector goes into the real rows; padding rows stay 0.
            let kind = self
                .type_embedding
                .i(question.kind_index() as usize)
                .ok()?
                .to_vec1::<f32>()
                .ok()?;
            for i in 0..len {
                for (d, v) in kind.iter().enumerate() {
                    tadd[(base + i) * dim + d] = *v;
                }
            }
            // Real rows of this slot attend the real columns only.
            for i in 0..len {
                let row = slot * s * s + i * s;
                for j in 0..len {
                    pmask[row + j] = 0.0;
                }
            }
        }
        npu.forward(&emb, &pmask, &tadd)
    }

    fn marker_scores(
        &self,
        hidden: &Tensor,
        row: usize,
        markers: &[usize],
    ) -> candle_core::Result<Vec<f32>> {
        let selected = markers
            .iter()
            .map(|i| hidden.i((row, *i)))
            .collect::<candle_core::Result<Vec<_>>>()?;
        Tensor::stack(&selected, 0)?
            .apply(&self.norm)?
            .apply(&self.scorer1)?
            .gelu_erf()?
            .apply(&self.scorer2)?
            .flatten_all()?
            .to_vec1::<f32>()
    }
    /// Serve answers when the manifest declares a usable calibration: run the
    /// (capped) batched scorer and turn the logits into decisions through
    /// `crate::decisions` with the fitted temperature and min_confidence.
    /// Questions the calibration is not confident about are simply absent from
    /// `answers` -- the caller asks the cloud for those. Without a calibration
    /// this stays the diagnostic-only gate (empty answers, cloud fallback).
    pub fn predict(&self, body: &str) -> Value {
        let Some(calibration) = self.calibration.filter(|c| c.calibrated) else {
            return uncertain("laya_not_human_calibrated");
        };
        match self.batched_scores(body, true, None) {
            Ok(raw) => crate::decisions(&raw, calibration.temperature, calibration.min_confidence),
            Err(reason) => uncertain(&reason),
        }
    }
}

#[cfg(test)]
mod option_budget_tests {
    use super::*;

    #[test]
    fn allocation_reserves_unique_prefixes_and_uses_source_windows() {
        let shared = vec![1, 2, 3, 4];
        let source = [
            shared.clone(),
            shared.clone(),
            shared,
            vec![1, 3],
            vec![1, 4],
            vec![8],
        ];
        assert_eq!(
            allocate_options(&source, 34).unwrap(),
            [
                vec![1, 2],
                vec![2, 3],
                vec![3, 4],
                vec![1, 3],
                vec![1, 4],
                vec![8]
            ],
        );
        assert_eq!(
            allocate_options(&[vec![1, 2], vec![1, 2, 3, 4]], 22).unwrap(),
            [vec![1, 2], vec![1, 3]],
        );
    }

    #[test]
    fn allocation_rejects_insufficient_space_or_exhausted_spans() {
        let source = [vec![1, 2], vec![1, 2]];
        assert_eq!(
            allocate_options(&source, 19).unwrap_err(),
            "head_token_budget"
        );
        assert_eq!(allocate_options(&source, 20).unwrap(), [vec![1], vec![2]]);
        assert_eq!(
            allocate_options(&source, 22).unwrap_err(),
            "option_tokens_collapsed",
        );
    }

    #[test]
    #[ignore = "requires LAYA_TEST_BUNDLE pointing to a real bundle"]
    fn sequence_preserves_legacy_layout_and_bounds_the_fallback() {
        let bundle = std::env::var("LAYA_TEST_BUNDLE").expect("set LAYA_TEST_BUNDLE");
        let engine = Engine::from_dir(Path::new(&bundle)).unwrap();
        let config = &engine.config;
        let normal = Question {
            kind: "choice".into(),
            instructions: "Pick one".into(),
            criteria: BTreeMap::from([("a".into(), "one".into()), ("b".into(), "two".into())]),
        };
        let mut expected = vec![config.cls_token_id];
        expected.extend(engine.tokens("choice question: Pick one").unwrap());
        expected.push(config.sep_token_id);
        let mut markers = Vec::new();
        for (key, text) in &normal.criteria {
            markers.push(expected.len());
            expected.push(config.mask_token_id);
            expected.extend(engine.tokens(&format!(" {key}: {text}")).unwrap());
        }
        expected.push(config.sep_token_id);
        let state_tokens = engine.tokens("small state").unwrap();
        expected.extend_from_slice(&state_tokens);
        expected.push(config.sep_token_id);
        for capped in [true, false] {
            let prepared = engine
                .sequence(&state_tokens, "normal", &normal, capped)
                .unwrap();
            assert_eq!(prepared.ids, expected);
            assert_eq!(prepared.markers, markers);
            assert_eq!(prepared.options, ["a", "b"]);
            assert_eq!(
                prepared.truncation,
                json!({
                    "instruction_tokens_dropped": 0, "option_tokens_dropped": 0,
                    "state_tokens_dropped": 0, "truncated": false,
                })
            );
        }

        let wide = Question {
            kind: "choice".into(),
            instructions: "Pick one of these many different options from the list.".repeat(10),
            criteria: (0..65)
                .map(|i| {
                    (
                        format!("left {i:02}"),
                        format!("right {i:02} {}", " long".repeat(60)),
                    )
                })
                .collect(),
        };
        let state = " long state".repeat(1200);
        let state_tokens = engine.tokens(&state).unwrap();
        let prepared = engine.sequence(&state_tokens, "wide", &wide, true).unwrap();
        assert_eq!(
            prepared.options,
            wide.criteria.keys().cloned().collect::<Vec<_>>()
        );
        assert_eq!(prepared.markers.len(), wide.criteria.len());
        // The capped path repairs the allocation against the head: with 65 options
        // the payload shrinks to its shortest unique prefix and the instruction
        // takes what is left. The public bundle is the head-256 config this
        // shape was fitted for.
        let head_end = prepared.markers.last().unwrap() + 3;
        assert_eq!(prepared.ids[head_end], config.sep_token_id);
        assert_eq!(head_end - 2, config.head_max_len);
        assert_eq!(prepared.ids.len(), config.max_len);
        let original_instruction = engine
            .tokens(&format!("choice question: {}", wide.instructions))
            .unwrap()
            .len();
        let original_options: usize = wide
            .criteria
            .iter()
            .map(|(key, text)| engine.tokens(&format!(" {key}: {text}")).unwrap().len())
            .sum();
        assert_eq!(
            prepared.truncation,
            json!({
                "instruction_tokens_dropped": original_instruction - (config.head_max_len - 65 * 3),
                "option_tokens_dropped": original_options - 65 * 2,
                "state_tokens_dropped": state_tokens.len() - (config.max_len - head_end - 2),
                "truncated": true, "option_budget_repaired": true,
            })
        );
        let mut unique = std::collections::BTreeSet::new();
        for (marker, (key, text)) in prepared.markers.iter().copied().zip(&wide.criteria) {
            assert_eq!(prepared.ids[marker], config.mask_token_id);
            let payload = &prepared.ids[marker + 1..marker + 3];
            assert!(unique.insert(payload));
            let source = engine.tokens(&format!(" {key}: {text}")).unwrap();
            assert!(
                source[..48].windows(2).any(|pair| pair == payload)
                    || (source[0] == payload[0] && source[2..48].contains(&payload[1]))
            );
        }
        // Strict mode keeps the exact head budget: the options fit the payload
        // limit, so the instruction cannot, and the call is declined.
        assert_eq!(
            engine
                .sequence(&state_tokens, "wide", &wide, false)
                .err()
                .unwrap(),
            "head_token_budget"
        );
        let questions: BTreeMap<_, _> = (0..9).map(|i| (
            i.to_string(),
            json!({"type": wide.kind, "instructions": wide.instructions, "criteria": wide.criteria}),
        )).collect();
        assert_eq!(
            engine
                .diagnostic_scores(&json!({"state": state, "questions": questions}).to_string())
                .unwrap_err(),
            "call_token_budget",
        );
    }
}
