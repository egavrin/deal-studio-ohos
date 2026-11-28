#!/usr/bin/env python3
"""Numpy reference forward for the Laya ModernBERT model, from the gguf.

Purpose: the parity reference for the HiAI NPU port. Reads the same Q4_0
weights the device runs (dequantized to F32 here), implements the exact math
of native/local-jev/src/laya.rs + laya_backbone.rs (GeGLU MLP, rotate-half
RoPE with per-layer theta 160000 global / 10000 local, alternating every 3rd
layer global, local window 64, no-bias encoder LayerNorms, layer 0 without
attn_norm, biased head layers, post-encoder type embedding, marker scorer),
and validates against the recorded Candle device outputs (laya_raw fixtures).

Usage: python laya-numpy-ref.py <bundle_dir> <body.json> [trace]
Prints per-question logits; with a laya_raw json as 3rd arg, compares.
"""
import json
import struct
import sys

import numpy as np

EPS = 1e-5
HEADS, DIM = 12, 768
HEAD_DIM = DIM // HEADS
LOCAL_WINDOW = 64  # local_attention 128 / 2


# ---- gguf parsing ----------------------------------------------------------

def read_gguf(path):
    f = open(path, 'rb')
    magic = f.read(4)
    assert magic == b'GGUF'
    struct.unpack('<I', f.read(4))
    ntens, = struct.unpack('<Q', f.read(8))
    nkv, = struct.unpack('<Q', f.read(8))

    def rd_str():
        n, = struct.unpack('<Q', f.read(8))
        return f.read(n).decode()

    def rd_val(t):
        if t == 8:
            return rd_str()
        sizes = {0: 1, 1: 1, 7: 1, 2: 2, 3: 2, 4: 4, 5: 4, 6: 4, 10: 8, 11: 8, 12: 8}
        fmts = {0: 'B', 1: 'b', 2: 'H', 3: 'h', 4: 'I', 5: 'i', 6: 'f', 7: 'B', 10: 'Q', 11: 'Q', 12: 'd'}
        if t in sizes:
            return struct.unpack('<' + fmts[t], f.read(sizes[t]))[0]
        if t == 9:
            et, = struct.unpack('<I', f.read(4))
            n, = struct.unpack('<Q', f.read(8))
            return [rd_val(et) for _ in range(n)]
        raise ValueError(t)

    meta = {}
    for _ in range(nkv):
        k = rd_str()
        t, = struct.unpack('<I', f.read(4))
        meta[k] = rd_val(t)

    infos = []
    for _ in range(ntens):
        name = rd_str()
        nd, = struct.unpack('<I', f.read(4))
        dims = struct.unpack('<' + 'Q' * nd, f.read(8 * nd))
        tt, = struct.unpack('<I', f.read(4))
        off, = struct.unpack('<Q', f.read(8))
        infos.append((name, tt, dims, off))
    align = meta.get('general.alignment', 32)
    data_start = (f.tell() + align - 1) // align * align

    class LazyTensors(dict):
        """Dequantize Q4_0 tensors on first access. F32/F16 load eagerly."""
        def __init__(self, loader):
            super().__init__()
            self._loader = loader

        def __missing__(self, name):
            arr = self._loader(name)
            self[name] = arr
            return arr

    def load_tensor(name):
        tt, dims, off = infos_by_name[name]
        f.seek(data_start + off)
        n = 1
        for d in dims:
            n *= d
        if tt == 0:  # F32
            flat = np.frombuffer(f.read(4 * n), dtype='<f4').astype(np.float32)
        elif tt == 1:  # F16
            flat = np.frombuffer(f.read(2 * n), dtype='<f2').astype(np.float32)
        elif tt == 2:  # Q4_0: blocks {f16 d; u8 qs[16]} = 32 values, 18 bytes
            nb = n // 32
            raw = np.frombuffer(f.read(18 * nb), dtype=np.uint8).reshape(nb, 18)
            d = raw[:, :2].copy().view('<f2').reshape(nb).astype(np.float32)  # [nb]
            qs = raw[:, 2:]  # [nb, 16]
            lo = (qs & 0xF).astype(np.int8) - 8
            hi = (qs >> 4).astype(np.int8) - 8
            # candle's dequantize_row_q4_0: LOW nibbles fill the first half of
            # the block (0..15), HIGH nibbles the second half (16..31) -- not
            # interleaved.
            vals = np.empty((nb, 32), dtype=np.float32)
            vals[:, :16] = lo * d[:, None]
            vals[:, 16:] = hi * d[:, None]
            flat = vals.reshape(-1)
        else:
            raise ValueError('tensor type %d not handled (%s)' % (tt, name))
        # gguf dims are (ne0=fastest, ne1, ...): reshape to [ne_last, ..., ne0]
        shape = list(reversed(dims))
        return flat.reshape(shape)

    infos_by_name = {name: (tt, dims, off) for name, tt, dims, off in infos}
    tensors = LazyTensors(load_tensor)
    return meta, tensors


# ---- model math ------------------------------------------------------------

def ln(x, w, b=None, eps=EPS):
    mu = x.mean(-1, keepdims=True)
    var = x.var(-1, keepdims=True)
    y = (x - mu) / np.sqrt(var + eps)
    return y * w + (b if b is not None else 0)


_erf = np.vectorize(__import__('math').erf)

def gelu_erf(x):
    return (0.5 * x * (1.0 + _erf(x / np.sqrt(2)))).astype(np.float32)


def softmax(x, axis=-1):
    e = np.exp(x - x.max(axis=axis, keepdims=True))
    return e / e.sum(axis=axis, keepdims=True)


def rope_tables(seq, theta):
    inv = 1.0 / theta ** (np.arange(0, HEAD_DIM, 2, dtype=np.float32) / HEAD_DIM)
    t = np.arange(seq, dtype=np.float32)[:, None] * inv[None, :]
    return np.cos(t), np.sin(t)


def apply_rope(x, cos, sin):
    # candle rope: rotate-half convention; x [h, s, 64], cos/sin [s, 32]
    cos64 = np.concatenate([cos, cos], -1)
    sin64 = np.concatenate([sin, sin], -1)
    x1, x2 = x[..., :HEAD_DIM // 2], x[..., HEAD_DIM // 2:]
    rot = np.concatenate([-x2, x1], -1)
    return x * cos64[None] + rot * sin64[None]


class Model:
    def __init__(self, bundle_dir):
        self.meta, self.t = read_gguf(bundle_dir + '/model.gguf')
        cfg = json.load(open(bundle_dir + '/laya-config.json'))
        self.nlayers = cfg['encoder_config']['num_hidden_layers']
        self.global_every = cfg['encoder_config']['global_attn_every_n_layers']
        self.theta_global = cfg['encoder_config']['global_rope_theta']
        self.theta_local = cfg['encoder_config'].get('local_rope_theta', self.theta_global)
        self.cls = cfg['cls_token_id']
        self.sep = cfg['sep_token_id']
        self.mask_tok = cfg['mask_token_id']
        self.mask_str = cfg['mask_token']
        self.max_len = cfg['max_len']

    def W(self, name):
        return self.t[name]

    def forward(self, ids, kind):
        t = self.t
        seq = len(ids)
        x = t['encoder.embeddings.tok_embeddings.weight'][np.asarray(ids)]
        x = ln(x, t['encoder.embeddings.norm.weight'])
        for i in range(self.nlayers):
            local = (i % self.global_every) != 0
            theta = self.theta_local if local else self.theta_global
            cos, sin = rope_tables(seq, theta)
            res = x
            an = 'encoder.layers.%d.attn_norm.weight' % i
            # t is lazy-loaded: membership tests never trigger __missing__,
            # so probe by getitem (KeyError = genuinely absent in the gguf).
            try:
                anw = t[an]
            except KeyError:
                h = x
            else:
                h = ln(x, anw)
            qkv = h @ t['encoder.layers.%d.attn.Wqkv.weight' % i].T  # [s, 2304]
            qkv = qkv.reshape(seq, 3, HEADS, HEAD_DIM)
            q, k, v = qkv[:, 0], qkv[:, 1], qkv[:, 2]  # [s, h, d]
            q, k, v = (a.transpose(1, 0, 2) for a in (q, k, v))  # [h, s, d]
            q = q / 8.0
            q = apply_rope(q, cos, sin)
            k = apply_rope(k, cos, sin)
            scores = q @ k.transpose(0, 2, 1)  # [h, s, s]
            if local:
                pos = np.arange(seq)
                dist = np.abs(pos[:, None] - pos[None, :])
                scores = np.where(dist > LOCAL_WINDOW, -np.inf, scores)
            a = softmax(scores, -1) @ v  # [h, s, d]
            a = a.transpose(1, 0, 2).reshape(seq, DIM)
            a = a @ t['encoder.layers.%d.attn.Wo.weight' % i].T
            x = res + a
            res = x
            h = ln(x, t['encoder.layers.%d.mlp_norm.weight' % i])
            wi = h @ t['encoder.layers.%d.mlp.Wi.weight' % i].T  # [s, 2304]
            gate, up = wi[..., :1152], wi[..., 1152:]
            m = (gelu_erf(gate) * up) @ t['encoder.layers.%d.mlp.Wo.weight' % i].T
            x = res + m
        x = ln(x, t['encoder.final_norm.weight'])
        kind_idx = 0 if kind == 'choice' else 2
        x = x + t['type_emb.weight'][kind_idx][None, :]
        for hl in range(2):
            p = 'head.layers.%d.' % hl
            res = x
            h = ln(x, t[p + 'norm1.weight'], t[p + 'norm1.bias'])
            qkv = h @ t[p + 'self_attn.in_proj_weight'].T + t[p + 'self_attn.in_proj_bias']
            qkv = qkv.reshape(seq, 3, HEADS, HEAD_DIM)
            q, k, v = (a.transpose(1, 0, 2) for a in (qkv[:, 0], qkv[:, 1], qkv[:, 2]))
            q = q / 8.0
            a = softmax(q @ k.transpose(0, 2, 1), -1) @ v
            a = a.transpose(1, 0, 2).reshape(seq, DIM)
            a = a @ t[p + 'self_attn.out_proj.weight'].T + t[p + 'self_attn.out_proj.bias']
            x = res + a
            res = x
            h = ln(x, t[p + 'norm2.weight'], t[p + 'norm2.bias'])
            ff = np.maximum(h @ t[p + 'linear1.weight'].T + t[p + 'linear1.bias'], 0)
            ff = ff @ t[p + 'linear2.weight'].T + t[p + 'linear2.bias']
            x = res + ff
        return x

    def marker_logits(self, x, markers):
        m = x[np.asarray(markers)]  # [n, 768]
        m = ln(m, t_ := self.t['scorer.0.weight'], self.t['scorer.0.bias'])
        m = gelu_erf(m @ self.t['scorer.1.weight'].T + self.t['scorer.1.bias'])
        return (m @ self.t['scorer.3.weight'].T + self.t['scorer.3.bias']).ravel()


# ---- input construction (mirrors laya.rs sequence()) ------------------------

from tokenizers import Tokenizer


def build_sequence(model, tok, body, key, q):
    # candle calls tokenizer.encode(text, false): NO special tokens (no
    # bos/eos wrapping) -- verified against candle's --report-batches lengths.
    def toks(text):
        enc = tok.encode(text.replace(model.mask_str, ' '), add_special_tokens=False)
        return enc.ids

    if q.get('type') == 'noul':
        crit = q.get('criteria') or {}
        opts = [
            ('false', crit.get('false', 'no, the statement does not hold')),
            ('true', crit.get('true', 'yes, the statement holds')),
        ]
    else:
        crit = q.get('criteria') or {}
        # Rust parses criteria as a BTreeMap: options are iterated in sorted
        # key order, not the JSON order.
        opts = sorted(crit.items())
    instr = toks('%s question: %s' % (q.get('type', 'choice'), q.get('instructions', '')))
    ids = [model.cls] + instr + [model.sep]
    markers = []
    for oid, desc in opts:
        ot = toks(' %s: %s' % (oid, desc))
        markers.append(len(ids))
        ids.append(model.mask_tok)
        ids.extend(ot)
    ids.append(model.sep)
    ids.extend(toks(body.get('state', '')))
    ids.append(model.sep)
    return ids, markers, [o[0] for o in opts]


def main():
    bundle, body_path = sys.argv[1], sys.argv[2]
    ref = sys.argv[3] if len(sys.argv) > 3 else None
    model = Model(bundle)
    tok = Tokenizer.from_file(bundle + '/tokenizer.json')
    body = json.load(open(body_path))
    state = body.get('state', '')

    ref_scores = json.load(open(ref))['scores'] if ref else {}
    worst = 0.0
    for key, q in body.get('questions', {}).items():
        ids, markers, opts = build_sequence(model, tok, body, key, q)
        kind = q.get('type', 'choice')
        x = model.forward(ids, kind)
        logits = model.marker_logits(x, markers)
        line = '%-28s ' % key
        for o, v in zip(opts, logits):
            line += '%s=%.4f ' % (o, v)
        if key in ref_scores:
            rl = ref_scores[key]['logits']
            d = max(abs(rl[o] - v) for o, v in zip(opts, logits) if o in rl)
            worst = max(worst, d)
            line += '| max|delta|=%.4f' % d
        print(line)
    if ref:
        print('worst logit delta vs reference: %.4f' % worst)


if __name__ == '__main__':
    main()
