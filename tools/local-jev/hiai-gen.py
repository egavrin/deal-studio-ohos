#!/usr/bin/env python3
"""HiAI ModelDef generator for the Laya ModernBERT + offline executor.

Emits the on-device-compilable protobuf (ge_ir.proto wire format; conventions
mirrored from the working e2e probe: has_out_attr=1, NCHW, NPU device_type,
the four zero model-attrs) for the full 22-layer model with weights as Const
tensors, from the validated numpy reference (laya-numpy-ref.py, parity
0.12-0.39 vs Candle on all 8 fixture bodies).

Layout decisions (see docs/local-jev/replacement-analysis.md §7.11):
- 2D tensors only ([seq, X]) -- no batch dim, no Transpose op needed for the
  projections.
- RoPE on the full [seq, 768]: the rotate-half permutation is a fixed
  block-diagonal MatMul; cos/sin tile across heads; the q scale (1/8) folds
  into the q tables. Only the per-head score MatMuls are unrolled (12 per
  layer via SplitD).
- LayerNorm: beta is a zeros Const where the model has no bias (encoder
  norms), real bias where it does (head + scorer norms).
- Local attention mask: a [seq, seq] Const (-1e4 outside the 64 window);
  global layers have no mask op.
- Markers are baked in (static shapes): one-hot selector MatMuls pick the
  option rows, ConcatD feeds the scorer, the graph OUTPUTS the logits.
- The graph input is the raw (pre-norm) embedding [seq, 768]; the embedding
  norm is the first op. The ids->embedding Gather is host-side for now.

The executor (hiai_exec.py) re-parses the emitted protobuf and interprets the
ops in numpy, so the graph is validated end-to-end WITHOUT the phone:
    python hiai-gen.py <bundle> <body.json> --question steps.bmi
"""
import argparse
import hashlib
import json
import struct
import sys

import numpy as np

import os
_HERE = os.path.dirname(os.path.abspath(__file__))
_EVAL = os.path.join(_HERE, 'eval')
# the reference module has a hyphenated filename -- load by path
import importlib.util as _ilu
_spec = _ilu.spec_from_file_location(
    'laya_numpy_ref', os.path.join(_EVAL, 'laya-numpy-ref.py'))
_ref = _ilu.module_from_spec(_spec)
sys.modules['laya_numpy_ref'] = _ref
_spec.loader.exec_module(_ref)
from laya_numpy_ref import Model, build_sequence, rope_tables, EPS

DT_FLOAT = 1


# ---- protobuf wire writer ---------------------------------------------------

def varint(v):
    if v < 0:
        v += 1 << 64  # two's complement (protobuf int64)
    out = bytearray()
    while True:
        b = v & 0x7F
        v >>= 7
        if v:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def tag(f, wt):
    return varint((f << 3) | wt)


def w_vint(f, v):
    return tag(f, 0) + varint(v)


def w_bytes(f, b):
    return tag(f, 2) + varint(len(b)) + b


def w_f32(f, x):
    return tag(f, 5) + struct.pack('<f', x)


def w_msg(f, payload):
    return w_bytes(f, payload)


def shape_def(dims):
    # proto3 packed repeated int64: the HiAI runtime's parser expects packed
    # (the C++ implementation emits packed; unpacked is valid protobuf but the
    # runtime rejected it -- field 1 as length-delimited packed varints).
    packed = b''.join(varint(d) for d in dims)
    return w_bytes(1, packed)


def tensor_desc(name, dtype, dims):
    return (w_bytes(1, name.encode()) + w_vint(2, dtype) +
            w_msg(3, shape_def(dims)) + w_bytes(4, b'NCHW') +
            w_vint(9, 1) + w_bytes(14, b'NPU'))


def tensor_def(desc, data):
    return w_msg(1, desc) + w_bytes(2, data)


def attr_i(v):
    return w_vint(3, v)


def attr_b(v):
    # AttrValue's bool field: the runtime's op parsers for adj_x1/adj_x2
    # expect a BOOL-typed attr -- an int-typed attr with the same name is
    # ignored, which silently drops the adjoint (non-square operands then
    # fail shape inference; square ones run WRONG).
    return w_vint(5, 1 if v else 0)


def attr_f(v):
    return w_f32(4, v)


def attr_tensor(td):
    return w_msg(12, td)


def attr_entry(key, val):
    return w_bytes(1, key.encode()) + w_msg(2, val)


# ---- graph builder ----------------------------------------------------------

HEADS, DIM, HDIM = 12, 768, 64


class Graph:
    nlayers = 22
    def __init__(self, name, weights, seq):
        self.name = name
        self.t = weights
        self.seq = seq
        self.ops = []
        self.inputs = []
        self.outputs = []
        self.shapes = {}
        self._cid = 0
        self._const_cache = {}

    def _cname(self, p):
        self._cid += 1
        return '%s%d' % (p, self._cid)

    F16 = True  # class-level default; main() can flip to F32 for testing

    def const_i32(self, arr, prefix='c'):
        """Int32 Const (for Reshape shape inputs — the runtime requires INT32)."""
        arr = np.ascontiguousarray(arr, dtype=np.int32)
        name = self._cname(prefix)
        desc = tensor_desc(name, 7, list(arr.shape))  # DT_INT32
        self.ops.append(
            w_bytes(1, name.encode()) + w_bytes(2, b'Const') +
            w_msg(10, attr_entry('value', attr_tensor(tensor_def(desc, arr.tobytes())))) +
            w_vint(20, 1) +
            w_msg(34, tensor_desc('y', 7, list(arr.shape))))
        self.shapes[name] = list(arr.shape)
        return name

    def const(self, arr, prefix='c', f16=None, cache=True):
        if f16 is None:
            f16 = self.F16
        # Identical consts (the rope tables and the rotate matrix, emitted
        # once per head) are deduplicated: later calls reference the first
        # emission. F16 is only for the big weight projections; LayerNorm
        # gamma/beta and the small tables pass f16=False (F16 gamma/beta are
        # rejected by the builder -- device-probed).
        dtype = 2 if f16 else DT_FLOAT  # DT_FLOAT16
        if cache:
            flat = np.ascontiguousarray(arr, np.float32) if dtype == DT_FLOAT else np.ascontiguousarray(arr, dtype='<f2')
            key = (hashlib.sha1(flat.tobytes()).hexdigest(), dtype, tuple(arr.shape))
            if key in self._const_cache:
                return self._const_cache[key]
        store = np.ascontiguousarray(arr, dtype='<f2') if f16 else np.ascontiguousarray(arr, np.float32)
        name = self._cname(prefix)
        desc = tensor_desc(name, dtype, list(arr.shape))
        self.ops.append(
            w_bytes(1, name.encode()) + w_bytes(2, b'Const') +
            w_msg(10, attr_entry('value', attr_tensor(tensor_def(desc, store.tobytes())))) +
            w_vint(20, 1) +
            w_msg(34, tensor_desc('y', dtype, list(arr.shape))))
        self.shapes[name] = list(arr.shape)
        self.shapes[name + '__dtype'] = dtype
        if cache:
            flat = np.ascontiguousarray(arr, np.float32) if dtype == DT_FLOAT else np.ascontiguousarray(arr, dtype='<f2')
            self._const_cache[(hashlib.sha1(flat.tobytes()).hexdigest(), dtype, tuple(arr.shape))] = name
        return name

    def data(self, name, dims):
        self.ops.append(
            w_bytes(1, name.encode()) + w_bytes(2, b'Data') +
            w_vint(20, 1) +
            w_msg(33, tensor_desc('x', DT_FLOAT, dims)) +
            w_msg(34, tensor_desc('y', DT_FLOAT, dims)))
        self.shapes[name] = dims
        self.inputs.append(name + ':0')
        return name

    def op(self, name, typ, inputs, out, attrs=(), n_in=None, n_out=1):
        # The runtime's GraphSerializer requires "name:portIndex" for every
        # input reference (SplitNameAndIndex fails on bare names).
        inputs = [i if ':' in i else i + ':0' for i in inputs]
        def shape_of(ref):
            if ref in self.shapes:
                return self.shapes[ref]
            return self.shapes[ref.rsplit(':', 1)[0]]

        ins = [tensor_desc('x%d' % k, DT_FLOAT, shape_of(i))
               for k, i in enumerate(inputs)]
        outs = [tensor_desc('y%d' % i if n_out > 1 else 'y', DT_FLOAT, out)
                for i in range(n_out)]
        self.ops.append(
            w_bytes(1, name.encode()) + w_bytes(2, typ.encode()) +
            b''.join(w_bytes(5, i.encode()) for i in inputs) +
            b''.join(w_msg(10, attr_entry(k, v)) for k, v in attrs) +
            w_vint(20, 1) + b''.join(w_msg(33, d) for d in ins) +
            b''.join(w_msg(34, d) for d in outs))
        if n_out == 1:
            self.shapes[name] = out
        else:
            for i in range(n_out):
                self.shapes['%s:%d' % (name, i)] = out
        return name

    # composed helpers -------------------------------------------------------

    def sub(self, name, a, b):
        return self.op(name, 'Sub', [a, b], self.shapes[a if a in self.shapes else a.rsplit(":", 1)[0]])

    def realdiv(self, name, a, b):
        return self.op(name, 'RealDiv', [a, b], self.shapes[a if a in self.shapes else a.rsplit(":", 1)[0]])

    def matm(self, name, a, warr, free_key=None):
        """y = W @ a with W a Const [out, in]: the transposed-space weight
        projection (y^T = W x^T). No adjoint attr -- plain 2D MatMul."""
        w = self.const(warr, name + '_w')
        if free_key is not None:
            self.t[free_key] = None
        out = [warr.shape[0], self.shapes[a if a in self.shapes else a.rsplit(':', 1)[0]][1]]
        return self.op(name, 'MatMul', [w, a], out)

    def pad_heads(self, name, a, heads, real, rows):
        """Pads a [heads*real, s] per-head tensor to [heads*rows, s] with an
        identity-padded Const matmul: output row h*rows+i selects input row
        h*real+i for i < real, zero beyond. Avoids ConcatD -- the runtime
        rejects a concat-derived operand in the transposed BatchMatMul
        (0x560C0808 at run), but a matmul-derived one is fine."""
        w = np.zeros((heads * rows, heads * real), np.float32)
        for h in range(heads):
            for i in range(real):
                w[h * rows + i, h * real + i] = 1.0
        s = self.shapes[a if a in self.shapes else a.rsplit(':', 1)[0]][1]
        return self.op(name, 'MatMul', [self.const(np.ascontiguousarray(w), name + '_w'), a],
                       [heads * rows, s])

    def bmm(self, name, a, b, out, adj_x1=False, adj_x2=False):
        # The adjoint flags are BOOL-typed attrs: an int-typed attr with the
        # same name is ignored by the runtime's op parser, silently dropping
        # the adjoint (non-square operands then fail shape inference; square
        # ones run with the wrong, untransposed product).
        attrs = [('adj_x1', attr_b(adj_x1)),
                 ('adj_x2', attr_b(adj_x2))]
        return self.op(name, 'BatchMatMul', [a, b], out, attrs=attrs)

    def reshape_op(self, name, a, shape):
        s = self.const_i32(np.asarray(shape, np.int32))
        return self.op(name, 'Reshape', [a, s], list(shape))

    # Mul/Sub-only Newton rsqrt iterations: enough to cover the crawl from the
    # basin edge at the smallest measured variance (~6e-4) plus the quadratic
    # tail, without any division in the chain.
    NEWTON_ITERS = 36

    def ln_t(self, name, a, gamma, beta=None, free_key=None, fold=False):
        """LayerNorm over the FEATURE ROWS of a transposed [d, s] stream.

        The runtime's LayerNorm only normalises trailing axes, so the
        statistics are built by hand: mean and variance via a ones-row Const
        matmul, the reciprocal square root by Newton iteration (only Mul, Sub
        and RealDiv -- all verified on device), scale/shift by broadcast.
        """
        d, s = self.shapes[a if a in self.shapes else a.rsplit(':', 1)[0]]
        ones = np.full((1, d), 1.0 / d, np.float32)  # the mean, not the sum
        if free_key is not None:
            self.t[free_key] = None
        g_arr = gamma
        mu = self.op(name + '_mu', 'MatMul', [self.const(ones, name + '_ones'), a], [1, s])
        # Sub is banned like RealDiv: a Sub-derived tensor cannot be a MatMul's
        # second operand on this runtime, and the LN feeds every projection.
        # x - mu = x + mu * -1.
        dv = self.op(name + '_d', 'Add', [a, self.mul(name + '_dn', mu,
                   self.const(np.full((1, s), -1.0, np.float32), name + '_dn1'))],
                     [d, s])
        d2 = self.mul(name + '_d2', dv, dv)
        var = self.op(name + '_v', 'MatMul', [self.const(ones, name + '_ones2'), d2], [1, s])
        ve = self.op(name + '_ve', 'Add', [var, self.const(np.full((1, s), EPS, np.float32), name + '_eps')], [1, s])
        # rsqrt(v) by the Mul/Sub-only Newton y <- y (1.5 - 0.5 v y^2), seeded
        # with the constant 0.4: RealDiv is banned -- an output of a chain
        # that contains it cannot serve as a MatMul's second operand on this
        # runtime (instant build rejection), and the LayerNorm feeds every
        # weight projection. The measured variance range of this network
        # ([~6e-4, ~6]) keeps v * y0^2 inside the convergence basin, and the
        # crawl from the basin edge is covered by the iteration count.
        r = self.const(np.full((1, s), 0.003, np.float32), name + '_ns')
        for it in range(self.NEWTON_ITERS):
            r2 = self.mul(name + '_n%d_2' % it, r, r)
            vr = self.mul(name + '_n%d_v' % it, ve, r2)
            # corr = 1.5 - 0.5*vr = 1.5 + vr*(-0.5), Mul/Add only.
            vh = self.mul(name + '_n%d_h' % it, vr,
                          self.const(np.full((1, s), -0.5, np.float32), name + '_n%dqc' % it))
            corr = self.op(name + '_n%d_c' % it, 'Add',
                           [self.const(np.full((1, s), 1.5, np.float32), name + '_n%doc' % it), vh], [1, s])
            r = self.mul(name + '_n%d' % it, r, corr)
        xn = self.mul(name + '_xn', dv, r)
        if fold:
            # The gamma/beta are folded into the consumer's weight/bias
            # instead: an elementwise op with a Const input cannot feed a
            # large-Const MatMul on this runtime, and every weight
            # projection is exactly that.
            return xn, np.asarray(g_arr, np.float32), (np.asarray(beta, np.float32) if beta is not None else None)
        y = self.mul(name + '_g', xn, self.const(np.asarray(g_arr, np.float32).reshape(d, 1), name + '_gam'))
        if beta is not None:
            y = self.op(name + '_b', 'Add', [y, self.const(np.asarray(beta, np.float32).reshape(d, 1), name + '_bet')], [d, s])
        return y, None, None


    def wmm(self, name, a, warr, bias=None, free_key=None):
        """y = a @ W with W given as [out, in] (the gguf layout): stored
        pre-transposed as [in, out] with NO adjoint attr -- a const-B MatMul
        carrying adj after a fused LayerNorm is rejected by the runtime
        (device-probed: LN -> MatMul no-adj builds, LN -> MatMul adj does
        not). free_key: the model weight dict entry to drop after emission."""
        w = self.const(np.ascontiguousarray(warr.T), name + '_w')
        if free_key is not None:
            self.t[free_key] = None
        out = [self.shapes[a][0], warr.shape[0]]
        self.op(name, 'MatMul', [a, w], out)
        y = name
        if bias is not None:
            b = self.const(bias, name + '_b')
            y = self.op(name + '_b', 'Add', [y, b], out)
        return y

    def add(self, name, a, b):
        return self.op(name, 'Add', [a, b], self.shapes[a if a in self.shapes else a.rsplit(":", 1)[0]])

    def mul(self, name, a, b):
        return self.op(name, 'Mul', [a, b], self.shapes[a if a in self.shapes else a.rsplit(":", 1)[0]])

    def layernorm(self, name, a, gamma, beta=None):
        g = self.const(gamma, name + '_g')
        b = self.const(beta if beta is not None else np.zeros(DIM, np.float32), name + '_b')
        return self.op(name, 'LayerNorm', [a, g, b], self.shapes[a],
                       attrs=[('begin_norm_axis', attr_i(len(self.shapes[a]) - 1)),
                              ('begin_params_axis', attr_i(len(self.shapes[a]) - 1)),
                              ('epsilon', attr_f(EPS))])

    def splitd(self, name, a, n, axis):
        parts = list(self.shapes[a])
        parts[axis] //= n
        self.op(name, 'SplitD', [a], parts,
                attrs=[('split_dim', attr_i(axis)), ('num_split', attr_i(n))], n_out=n)
        return name

    def softmax(self, name, a, axis=None):
        if axis is None:
            axis = len(self.shapes[a]) - 1  # last axis, as a positive index
        return self.op(name, 'Softmax', [a], self.shapes[a], attrs=[('axis', attr_i(axis))])

    def activation(self, name, a, mode):
        return self.op(name, 'Activation', [a], self.shapes[a], attrs=[('mode', attr_i(mode))])

    def concatd(self, name, parts, axis):
        out = list(self.shapes[parts[0]])
        out[axis] = sum(self.shapes[p][axis] for p in parts)
        return self.op(name, 'ConcatD', parts, out,
                       attrs=[('concat_dim', attr_i(axis)), ('N', attr_i(len(parts)))])

    def serialize(self):
        body = w_bytes(1, self.name.encode())
        for i in self.inputs:
            body += w_bytes(4, i.encode())
        for o in self.outputs:
            body += w_bytes(5, o.encode())
        for op in self.ops:
            body += w_msg(6, op)
        return body


def model_def(name, graph):
    body = w_bytes(1, name.encode())
    body += w_msg(7, graph.serialize())
    for k in ('memory_size', 'stream_num', 'weight_size', 'event_num'):
        body += w_msg(11, attr_entry(k, attr_i(0)))
    return body


def rotate_mat():
    # out = x @ m with out[j] = sum_k x[k] m[k, j]:
    #   out[i]      = -x[i+32]  -> m[i+32, i]     = -1
    #   out[i+32]   =  x[i]     -> m[i,     i+32] = +1
    m = np.zeros((DIM, DIM), np.float32)
    for h in range(HEADS):
        o = h * HDIM
        for i in range(HDIM // 2):
            m[o + i + HDIM // 2, o + i] = -1.0
            m[o + i, o + i + HDIM // 2] = 1.0
    return m  # rot(x) = x @ m == rotate_half(x)


def build(g, kind_idx, markers, theta=160000.0, window=64):
    t, seq = g.t, g.seq
    cos, sin = rope_tables(seq, theta)
    tile = lambda a: np.tile(a, (1, HEADS)).astype(np.float32)
    cosq, sinq = tile(cos * 0.125), tile(sin * 0.125)  # q scale folded
    cosk, sink = tile(cos), tile(sin)
    pos = np.arange(seq)
    lmask = np.where(np.abs(pos[:, None] - pos[None, :]) > window,
                     -1e4, 0.0).astype(np.float32)
    rotm = rotate_mat()

    def rope(name, a, cosc, sinc):
        c = g.mul(name + '_c', a, cosc)
        r = g.wmm(name + '_r', a, rotm)
        rs = g.mul(name + '_rs', r, sinc)
        return g.add(name, c, rs)

    x = g.data('emb', [seq, DIM])
    x = g.layernorm('embnorm', x, t['encoder.embeddings.norm.weight'])

    for i in range(22):
        p = 'encoder.layers.%d.' % i
        local = (i % 3) != 0
        res = x
        an = p + 'attn_norm.weight'
        h = g.layernorm('l%d_an' % i, x, t[an]) if an in t else x
        qkv = g.wmm('l%d_qkv' % i, h, t[p + 'attn.Wqkv.weight'].T)
        s3 = g.splitd('l%d_s3' % i, qkv, 3, 1)
        qr = rope('l%d_rq' % i, s3 + ':0', cosq, sinq)
        kr = rope('l%d_rk' % i, s3 + ':1', cosk, sink)
        vv = s3 + ':2'
        sq = g.splitd('l%d_sq' % i, qr, HEADS, 1)
        sk = g.splitd('l%d_sk' % i, kr, HEADS, 1)
        sv = g.splitd('l%d_sv' % i, vv, HEADS, 1)
        heads = []
        for j in range(HEADS):
            qh, kh, vh = '%s:%d' % (sq, j), '%s:%d' % (sk, j), '%s:%d' % (sv, j)
            s = g.wmm('l%d_h%d_s' % (i, j), qh, t[p + 'attn.Wqkv.weight'].T[:0].reshape(64, 64)
                      if False else _eye_like(g, kh), adj=True)
            # NOTE: scores = qh @ kh^T: express as MatMul with adj_x2 on a
            # pass-through "weight" is not possible (both operands are nodes).
            # See _matmul_nodes below -- replaced in place.
            heads.append(None)
        x = None  # placeholder; real code emitted by build_v2
    raise SystemExit('internal: use build_v2')


def _eye_like(g, kh):
    return np.eye(g.shapes[kh][1], dtype=np.float32)


def build_transposed(g, kind_idx, markers, theta=160000.0, window=64, stop=None):
    """The transposed-space emitter: the residual stream runs as [d, s]
    (features are rows), which turns the attention score product into
    BatchMatMul(adj_x1) -- the adjoint HiAI's shape inference actually
    accepts -- and every weight projection into a plain Const matmul with a
    pre-transposed weight. LayerNorm is built by hand (ln_t). The input is
    the transposed embedding (host-side, free); the output is logits^T
    [options, markers], and the host reads marker columns.
    """
    t, seq = g.t, g.seq
    cos, sin = rope_tables(seq, theta)
    def full(a):
        return np.concatenate([a, a], axis=-1).astype(np.float32)
    # The q scale (1/sqrt(head_dim)) is baked into the Wq slice below, so the
    # rope tables carry no factor of their own.
    cosq = np.ascontiguousarray((np.tile(full(cos), (1, HEADS))).T)
    sinq = np.ascontiguousarray((np.tile(full(sin), (1, HEADS))).T)
    cosk = np.ascontiguousarray((np.tile(full(cos), (1, HEADS))).T)
    sink = np.ascontiguousarray((np.tile(full(sin), (1, HEADS))).T)
    pos = np.arange(seq)
    lmask = np.ascontiguousarray(np.where(np.abs(pos[:, None] - pos[None, :]) > window,
                                          -1e4, 0.0).astype(np.float32).T)
    rotm = np.ascontiguousarray(rotate_mat().T)
    scale = 1.0 / np.sqrt(float(HDIM))

    def rope_t(name, a, cosc, sinc):
        c = g.mul(name + '_c', a, g.const(cosc))
        r = g.matm(name + '_r', a, rotm)
        rs = g.mul(name + '_rs', r, g.const(sinc))
        return g.op(name, 'Add', [c, rs], g.shapes[a if a in g.shapes else a.rsplit(':', 1)[0]])

    x = g.data('embT', [DIM, seq])
    # The embedding norm defines the residual stream: its gamma is
    # materialized as a diag-gamma MatMul (an elementwise Mul's output could
    # not feed the weight projections on this runtime).
    x, g_emb, _ = g.ln_t('embnorm', x, t['encoder.embeddings.norm.weight'],
                          free_key='encoder.embeddings.norm.weight', fold=True)
    x = g.op('embsc', 'MatMul', [g.const(np.diag(g_emb).astype(np.float32), 'embsc_w'), x], [DIM, seq])

    for i in range(g.nlayers):
        p = 'encoder.layers.%d.' % i
        local = (i % 3) != 0
        res = x
        an = p + 'attn_norm.weight'
        h = x
        if an in t:
            # In-block norm: fold its gamma into the projection columns.
            h, g_an, _ = g.ln_t('l%d_an' % i, x, t[an], free_key=an, fold=True)
            Wqkv_scale = g_an[None, :]
        else:
            Wqkv_scale = None
        Wqkv = t[p + 'attn.Wqkv.weight']
        g.t[p + 'attn.Wqkv.weight'] = None
        # The stream is already gamma-scaled (the embsc diag MatMul); an
        # in-block attn norm folds its gamma into the projection columns.
        def _scl(W):
            return np.ascontiguousarray(W * (Wqkv_scale if Wqkv_scale is not None else 1.0))
        wq = _scl(Wqkv[:DIM] * scale)
        wk = _scl(Wqkv[DIM:2 * DIM])
        wv = _scl(Wqkv[2 * DIM:])
        # y^T = W x^T: the raw weight slices ARE the transposed-space consts.
        qt = g.matm('l%d_q' % i, h, wq)
        kt = g.matm('l%d_k' % i, h, wk)
        vt = g.matm('l%d_v' % i, h, wv)
        rqt = rope_t('l%d_rq' % i, qt, cosq, sinq)
        rkt = rope_t('l%d_rk' % i, kt, cosk, sink)
        # The runtime's BatchMatMul shape inference never applies the adjoint:
        # adj_x1 passes only for SQUARE operands, and a concat-derived operand
        # breaks the kernel at run. Pad K/Q's per-head feature rows from 64 to
        # seq with an identity-padded Const matmul instead -- the zero rows
        # contribute nothing to the contraction, so the scores are exact.
        if seq > HDIM:
            rqt = g.pad_heads('l%d_qp' % i, rqt, HEADS, HDIM, seq)
            rkt = g.pad_heads('l%d_kp' % i, rkt, HEADS, HDIM, seq)
        qh = g.reshape_op('l%d_qh' % i, rqt, [HEADS, seq, seq])
        kh = g.reshape_op('l%d_kh' % i, rkt, [HEADS, seq, seq])
        vh = g.reshape_op('l%d_vh' % i, vt, [DIM, seq])
        # scores^T = K Q^T per head: BatchMatMul(adj_x1) on square operands.
        st = g.bmm('l%d_st' % i, kh, qh, [HEADS, seq, seq], adj_x1=True)
        if local:
            st = g.op('l%d_mk' % i, 'Add', [st, g.const(lmask)], [HEADS, seq, seq])
        pt = g.op('l%d_p' % i, 'Softmax', [st], [HEADS, seq, seq],
                  attrs=[('axis', attr_i(-2))])
        # out^T = (V^T C) M-masked, times P2d: BatchMatMul needs a Const
        # second operand (dynamic P is rejected), and SplitD(axis=0) fails at
        # run -- but a 2D MatMul takes two derived operands. Scatter V^T
        # across per-head column blocks with the tiler C, mask each feature
        # row to its own head's block with M, and contract against the flat
        # P2d: (V^T C) M P2d sums exactly V^T_h P^T_h per head, in ONE matmul.
        p2d = g.reshape_op('l%d_p2d' % i, pt, [HEADS * seq, seq])
        ctil = np.zeros((seq, HEADS * seq), np.float32)
        for h in range(HEADS):
            for b in range(seq):
                ctil[b, h * seq + b] = 1.0
        vc = g.op('l%d_vc' % i, 'MatMul', [vh, g.const(ctil, 'l%d_ct' % i)], [DIM, HEADS * seq])
        msk = np.zeros((DIM, HEADS * seq), np.float32)
        for d in range(DIM):
            msk[d, (d // HDIM) * seq:(d // HDIM + 1) * seq] = 1.0
        v2 = g.mul('l%d_v2' % i, vc, g.const(msk, 'l%d_mk' % i))
        outt = g.op('l%d_ot' % i, 'MatMul', [v2, p2d], [DIM, seq])
        attn = g.matm('l%d_wo' % i, outt, t[p + 'attn.Wo.weight'],
                      free_key=p + 'attn.Wo.weight')
        x = g.add('l%d_ra' % i, res, attn)
        res = x
        h2, g_mlp, _ = g.ln_t('l%d_mn' % i, x, t[p + 'mlp_norm.weight'],
                               free_key=p + 'mlp_norm.weight', fold=True)
        Wi = t[p + 'mlp.Wi.weight']
        g.t[p + 'mlp.Wi.weight'] = None
        wgate = np.ascontiguousarray(Wi[:Wi.shape[0] // 2] * g_mlp[None, :])
        wup = np.ascontiguousarray(Wi[Wi.shape[0] // 2:] * g_mlp[None, :])
        gatet = g.matm('l%d_wg' % i, h2, wgate)
        upt = g.matm('l%d_wu' % i, h2, wup)
        gate = g.activation('l%d_g' % i, gatet, 15)  # GeLU
        m = g.mul('l%d_gm' % i, gate, upt)
        mt = g.matm('l%d_mo' % i, m, t[p + 'mlp.Wo.weight'],
                    free_key=p + 'mlp.Wo.weight')
        x = g.add('l%d_rm' % i, res, mt)
        print('layer %d ops=%d' % (i, len(g.ops)), file=sys.stderr, flush=True)

    x, g_fin, _ = g.ln_t('final', x, t['encoder.final_norm.weight'],
                          free_key='encoder.final_norm.weight', fold=True)
    # The final norm defines the pre-head stream: materialize its gamma the
    # same way.
    x = g.op('finsc', 'MatMul', [g.const(np.diag(g_fin).astype(np.float32), 'finsc_w'), x], [DIM, seq])
    # type embedding: per-feature row broadcast.
    typec = np.asarray(t['type_emb.weight'][kind_idx], np.float32).reshape(DIM, 1)
    g.t['type_emb.weight'] = None
    x = g.op('type', 'Add', [x, g.const(typec, 'type_c')], [DIM, seq])
    if stop == 'type':
        g.outputs = ['type:0']
        return x

    for hl in range(2):
        p = 'head.layers.%d.' % hl
        res = x
        # norm1 folded into in_proj: W' = W diag(gamma), bias' = bias + W beta.
        h, g_n1, b_n1 = g.ln_t('h%d_n1' % hl, x, t[p + 'norm1.weight'], beta=t[p + 'norm1.bias'],
                                free_key=p + 'norm1.weight', fold=True)
        g.t[p + 'norm1.bias'] = None
        Wip = t[p + 'self_attn.in_proj_weight']
        g.t[p + 'self_attn.in_proj_weight'] = None
        bip = t[p + 'self_attn.in_proj_bias']
        g.t[p + 'self_attn.in_proj_bias'] = None
        bq = np.asarray(bip[:DIM] * scale, np.float32) + (Wip[:DIM] * scale) @ (b_n1 if b_n1 is not None else np.zeros(DIM, np.float32))
        bk = np.asarray(bip[DIM:2 * DIM], np.float32) + Wip[DIM:2 * DIM] @ (b_n1 if b_n1 is not None else np.zeros(DIM, np.float32))
        bv = np.asarray(bip[2 * DIM:], np.float32) + Wip[2 * DIM:] @ (b_n1 if b_n1 is not None else np.zeros(DIM, np.float32))
        qt = g.op('h%d_qb' % hl, 'Add',
                  [g.matm('h%d_q' % hl, h, np.ascontiguousarray(Wip[:DIM] * scale * g_n1[None, :])),
                   g.const(bq.reshape(DIM, 1), 'h%dqb' % hl)], [DIM, seq])
        kt = g.op('h%d_kb' % hl, 'Add',
                  [g.matm('h%d_k' % hl, h, np.ascontiguousarray(Wip[DIM:2 * DIM] * g_n1[None, :])),
                   g.const(bk.reshape(DIM, 1), 'h%dkb' % hl)], [DIM, seq])
        vt = g.op('h%d_vb' % hl, 'Add',
                  [g.matm('h%d_v' % hl, h, np.ascontiguousarray(Wip[2 * DIM:] * g_n1[None, :])),
                   g.const(bv.reshape(DIM, 1), 'h%dvb' % hl)], [DIM, seq])
        if stop == 'h%d_q' % hl:
            g.outputs = ['h%d_qb:0']
            return x
        if seq > HDIM:
            qt = g.pad_heads('h%d_qp' % hl, qt, HEADS, HDIM, seq)
            kt = g.pad_heads('h%d_kp' % hl, kt, HEADS, HDIM, seq)
        qh = g.reshape_op('h%d_qh' % hl, qt, [HEADS, seq, seq])
        kh = g.reshape_op('h%d_kh' % hl, kt, [HEADS, seq, seq])
        vh = g.reshape_op('h%d_vh' % hl, vt, [DIM, seq])
        if stop == 'h%d_r' % hl:
            g.outputs = ['h%d_qh:0']
            return x
        st = g.bmm('h%d_st' % hl, kh, qh, [HEADS, seq, seq], adj_x1=True)
        if stop == 'h%d_s' % hl:
            g.outputs = ['h%d_st:0']
            return x
        pt = g.op('h%d_p' % hl, 'Softmax', [st], [HEADS, seq, seq],
                  attrs=[('axis', attr_i(-2))])
        if stop == 'h%d_p' % hl:
            g.outputs = ['h%d_p:0']
            return x
        p2d = g.reshape_op('h%d_p2d' % hl, pt, [HEADS * seq, seq])
        ctil = np.zeros((seq, HEADS * seq), np.float32)
        for h in range(HEADS):
            for b in range(seq):
                ctil[b, h * seq + b] = 1.0
        vc = g.op('h%d_vc' % hl, 'MatMul', [vh, g.const(ctil, 'h%d_ct' % hl)], [DIM, HEADS * seq])
        msk = np.zeros((DIM, HEADS * seq), np.float32)
        for d in range(DIM):
            msk[d, (d // HDIM) * seq:(d // HDIM + 1) * seq] = 1.0
        v2 = g.mul('h%d_v2' % hl, vc, g.const(msk, 'h%d_mk' % hl))
        if stop == 'h%d_v' % hl:
            g.outputs = ['h%d_v2:0']
            return x
        outt = g.op('h%d_ot' % hl, 'MatMul', [v2, p2d], [DIM, seq])
        if stop == 'h%d_o' % hl:
            g.outputs = ['h%d_ot:0']
            return x
        attn = g.matm('h%d_op' % hl, outt, t[p + 'self_attn.out_proj.weight'],
                      free_key=p + 'self_attn.out_proj.weight')
        attn = g.op('h%d_opb' % hl, 'Add', [attn,
                    g.const(np.asarray(t[p + 'self_attn.out_proj.bias'], np.float32).reshape(DIM, 1), 'h%dopb' % hl)],
                    [DIM, seq])
        g.t[p + 'self_attn.out_proj.bias'] = None
        x = g.add('h%d_ra' % hl, res, attn)
        if stop == 'h0a' and hl == 0:
            g.outputs = ['h0_ra:0']
            return x
        res = x
        h, g_n2, b_n2 = g.ln_t('h%d_n2' % hl, x, t[p + 'norm2.weight'], beta=t[p + 'norm2.bias'],
                                free_key=p + 'norm2.weight', fold=True)
        g.t[p + 'norm2.bias'] = None
        Wl1 = t[p + 'linear1.weight']
        bl1 = np.asarray(t[p + 'linear1.bias'], np.float32)
        g.t[p + 'linear1.weight'] = None
        g.t[p + 'linear1.bias'] = None
        ff = g.matm('h%d_f1' % hl, h, np.ascontiguousarray(Wl1 * g_n2[None, :]))
        ff = g.op('h%d_f1b' % hl, 'Add', [ff,
                  g.const((bl1 + Wl1 @ (b_n2 if b_n2 is not None else np.zeros(DIM, np.float32))).reshape(-1, 1), 'h%df1b' % hl)],
                  g.shapes[ff if ff in g.shapes else ff.rsplit(':', 1)[0]])
        ff = g.activation('h%d_rel' % hl, ff, 1)  # relu
        ff = g.matm('h%d_f2' % hl, ff, t[p + 'linear2.weight'],
                    free_key=p + 'linear2.weight')
        ff = g.op('h%d_f2b' % hl, 'Add', [ff,
                  g.const(np.asarray(t[p + 'linear2.bias'], np.float32).reshape(DIM, 1), 'h%df2b' % hl)],
                  [DIM, seq])
        g.t[p + 'linear2.bias'] = None
        x = g.add('h%d_rf' % hl, res, ff)
        if stop == 'h0f' and hl == 0:
            g.outputs = ['h0_rf:0']
            return x
        if stop == 'h1f' and hl == 1:
            g.outputs = ['h1_rf:0']
            return x

    # marker readout: H^T @ sel^T = (sel @ H)^T -- a plain Const matmul whose
    # weight is the transposed one-hot selector.
    sel = np.zeros((len(markers), seq), np.float32)
    for r, m in enumerate(markers):
        sel[r, m] = 1.0
    selc = g.const(np.ascontiguousarray(sel.T), 'mk_sel')  # [seq, n]
    mk = g.op('mk', 'MatMul', [x, selc], [DIM, len(markers)])
    s, g_sc0, b_sc0 = g.ln_t('sc0', mk, t['scorer.0.weight'],
                               beta=t['scorer.0.bias'],
                               free_key='scorer.0.weight', fold=True)
    # sc0's gamma/beta fold into scorer.1: W' = W diag(g), b' = b + W beta.
    W1 = t['scorer.1.weight']
    b1 = np.asarray(t['scorer.1.bias'], np.float32)
    g.t['scorer.1.weight'] = None
    g.t['scorer.1.bias'] = None
    s = g.matm('sc1', s, np.ascontiguousarray(W1 * g_sc0[None, :]))
    s = g.op('sc1b', 'Add', [s, g.const((b1 + W1 @ (b_sc0 if b_sc0 is not None else np.zeros(W1.shape[1], np.float32))).reshape(-1, 1), 'sc1_b')],
             g.shapes[s if s in g.shapes else s.rsplit(':', 1)[0]])
    s = g.activation('scg', s, 15)
    s = g.matm('sc2', s, t['scorer.3.weight'],
               free_key='scorer.3.weight')
    s = g.op('sc2b', 'Add', [s, g.const(np.asarray(t['scorer.3.bias'], np.float32).reshape(-1, 1), 'sc3_b')],
             g.shapes[s if s in g.shapes else s.rsplit(':', 1)[0]])
    g.t['scorer.3.bias'] = None
    g.outputs = [s + ':0']
    return s


def build_batched(g, batch, theta=160000.0, window=64):
    """The fixed-shape batched graph for the E2E serving path.

    One graph, one compile: `batch` question slots, each padded to the fixed
    `seq`. The padding mask arrives as a second input [batch, seq, seq] --
    the host knows each slot's real length (the local distance mask is a
    baked const broadcast over slots). The type embedding is added
    host-side and the scorer runs host-side on the returned hidden states,
    so the graph is purely the encoder + head layers, output
    [batch*seq, DIM].

    Weight Consts are F16 where the builder accepts them (the big
    projections) and F32 for LayerNorm gamma/beta and small tables (F16
    gamma/beta are rejected by the builder -- device-probed).
    """
    t, seq, B = g.t, g.seq, batch
    cos, sin = rope_tables(seq, theta)
    def full(a):
        return np.concatenate([a, a], axis=-1).astype(np.float32)
    # The rope tables are per-position [seq, 768]; the batched stream is
    # [B*seq, 768] with row b*seq+i taking position i -- so each table is
    # tiled B times along rows.
    cosq = np.tile(np.tile(full(cos) * 0.125, (1, HEADS)).astype(np.float32), (B, 1))
    sinq = np.tile(np.tile(full(sin) * 0.125, (1, HEADS)).astype(np.float32), (B, 1))
    cosk = np.tile(np.tile(full(cos), (1, HEADS)).astype(np.float32), (B, 1))
    sink = np.tile(np.tile(full(sin), (1, HEADS)).astype(np.float32), (B, 1))
    pos = np.arange(seq)
    dist = np.where(np.abs(pos[:, None] - pos[None, :]) > window, -1e4, 0.0).astype(np.float32)
    rotm = rotate_mat()

    def rope(name, a, cosc, sinc):
        c = g.mul(name + '_c', a, g.const(cosc, f16=False))
        r = g.mmn(name + '_r', a, g.const(rotm, f16=False))
        rs = g.mul(name + '_rs', r, g.const(sinc, f16=False))
        return g.add(name, c, rs)

    x = g.data('emb', [B * seq, DIM])
    pmask = g.data('pmask', [B, seq, seq])
    x = g.layernorm('embnorm', x, t['encoder.embeddings.norm.weight'])

    def masked_attention(tag, h, Wqkv_name, Wo_name, local, q_scale):
        """Per-head attention over [B*seq, ...] rows; scores as [B, S, S]."""
        Wqkv = t[Wqkv_name]
        g.t[Wqkv_name] = None
        qkv = g.wmm(tag + '_qkv', h, Wqkv, free_key=Wqkv_name)
        s3 = g.splitd(tag + '_s3', qkv, 3, 1)
        # rope on the full feature width BEFORE the head split (the tables
        # are [seq, 768]-shaped).
        qr = rope(tag + '_rq', s3 + ':0', cosq, sinq)
        kr = rope(tag + '_rk', s3 + ':1', cosk, sink)
        sq = g.splitd(tag + '_sq', qr, HEADS, 1)
        sk = g.splitd(tag + '_sk', kr, HEADS, 1)
        sv = g.splitd(tag + '_sv', s3 + ':2', HEADS, 1)
        heads = []
        for j in range(HEADS):
            # [B*S, 64] -> [B, S, 64]
            q3 = g.op(tag + '_q3_%d' % j, 'Reshape',
                      ['%s:%d' % (sq, j), g.const_i32(np.array([B, seq, HDIM]))], [B, seq, HDIM])
            k3 = g.op(tag + '_k3_%d' % j, 'Reshape',
                      ['%s:%d' % (sk, j), g.const_i32(np.array([B, seq, HDIM]))], [B, seq, HDIM])
            v3 = g.op(tag + '_v3_%d' % j, 'Reshape',
                      ['%s:%d' % (sv, j), g.const_i32(np.array([B, seq, HDIM]))], [B, seq, HDIM])
            sc = g.bmm(tag + '_sc%d' % j, q3, k3, [B, seq, seq], adj_x2=True)
            # the baked local distance mask broadcasts [S, S] over slots and
            # heads; the padding mask is the input, same shape per slot.
            if local:
                sc = g.op(tag + '_dm%d' % j, 'Add', [sc, g.const(dist, tag + '_dc%d' % j, f16=False)], [B, seq, seq])
            sc = g.op(tag + '_pm%d' % j, 'Add', [sc, pmask], [B, seq, seq])
            p3 = g.op(tag + '_p3_%d' % j, 'Softmax', [sc], [B, seq, seq],
                      attrs=[('axis', attr_i(2))])
            # out_h = P @ V: [B, S, S] @ [B, S, 64]
            oh = g.bmm(tag + '_oh%d' % j, p3, v3, [B, seq, HDIM])
            heads.append(g.op(tag + '_of%d' % j, 'Reshape',
                              [oh, g.const_i32(np.array([B * seq, HDIM]))], [B * seq, HDIM]))
        cat = g.concatd(tag + '_cat', heads, 1)
        return g.wmm(tag + '_wo', cat, t[Wo_name], free_key=Wo_name)

    for i in range(g.nlayers):
        p = 'encoder.layers.%d.' % i
        local = (i % 3) != 0
        res = x
        h = g.layernorm('l%d_an' % i, x, t[p + 'attn_norm.weight']) if (p + 'attn_norm.weight') in t else x
        # the reference has no attn_norm in this model (probed by KeyError),
        # so h = x; kept general via the membership test.
        attn = masked_attention('l%d' % i, h, p + 'attn.Wqkv.weight', p + 'attn.Wo.weight', local, 0.125)
        x = g.add('l%d_ra' % i, res, attn)
        res = x
        h2 = g.layernorm('l%d_mn' % i, x, t[p + 'mlp_norm.weight'])
        wi = g.wmm('l%d_wi' % i, h2, t[p + 'mlp.Wi.weight'], free_key=p + 'mlp.Wi.weight')
        gs = g.splitd('l%d_gs' % i, wi, 2, 1)
        gate = g.activation('l%d_g' % i, gs + ':0', 15)
        m = g.mul('l%d_gm' % i, gate, gs + ':1')
        m = g.wmm('l%d_mo' % i, m, t[p + 'mlp.Wo.weight'], free_key=p + 'mlp.Wo.weight')
        x = g.add('l%d_rm' % i, res, m)
        print('layer %d ops=%d' % (i, len(g.ops)), file=sys.stderr, flush=True)

    x = g.layernorm('final', x, t['encoder.final_norm.weight'])
    # The type embedding differs per question kind, so it arrives as a third
    # input [B*seq, DIM] the host broadcasts from the kind's vector.
    tadd = g.data('tadd', [B * seq, DIM])
    x = g.add('type', x, tadd)

    # The two head layers: no rope, no distance mask; the padding mask still
    # applies.
    for hl in range(2):
        p = 'head.layers.%d.' % hl
        res = x
        h = g.layernorm('h%d_n1' % hl, x, t[p + 'norm1.weight'], t[p + 'norm1.bias'])
        qkv = g.wmm('h%d_ip' % hl, h, t[p + 'self_attn.in_proj_weight'],
                    bias=t[p + 'self_attn.in_proj_bias'], free_key=p + 'self_attn.in_proj_weight')
        g.t[p + 'self_attn.in_proj_bias'] = None
        s3 = g.splitd('h%d_s3' % hl, qkv, 3, 1)
        sq = g.splitd('h%d_sq' % hl, s3 + ':0', HEADS, 1)
        sk = g.splitd('h%d_sk' % hl, s3 + ':1', HEADS, 1)
        sv = g.splitd('h%d_sv' % hl, s3 + ':2', HEADS, 1)
        heads = []
        for j in range(HEADS):
            q3 = g.op('h%d_q3_%d' % (hl, j), 'Reshape',
                      ['%s:%d' % (sq, j), g.const_i32(np.array([B, seq, HDIM]))], [B, seq, HDIM])
            # The reference scales q by 1/8 before the scores.
            q3s = g.mul('h%d_qs_%d' % (hl, j), q3,
                        g.const(np.full((B, seq, HDIM), 0.125, np.float32), 'h%d_qc%d' % (hl, j), f16=False))
            k3 = g.op('h%d_k3_%d' % (hl, j), 'Reshape',
                      ['%s:%d' % (sk, j), g.const_i32(np.array([B, seq, HDIM]))], [B, seq, HDIM])
            v3 = g.op('h%d_v3_%d' % (hl, j), 'Reshape',
                      ['%s:%d' % (sv, j), g.const_i32(np.array([B, seq, HDIM]))], [B, seq, HDIM])
            sc = g.bmm('h%d_sc_%d' % (hl, j), q3s, k3, [B, seq, seq], adj_x2=True)
            sc = g.op('h%d_pm_%d' % (hl, j), 'Add', [sc, pmask], [B, seq, seq])
            p3 = g.op('h%d_p3_%d' % (hl, j), 'Softmax', [sc], [B, seq, seq],
                      attrs=[('axis', attr_i(2))])
            oh = g.bmm('h%d_oh_%d' % (hl, j), p3, v3, [B, seq, HDIM])
            heads.append(g.op('h%d_of_%d' % (hl, j), 'Reshape',
                              [oh, g.const_i32(np.array([B * seq, HDIM]))], [B * seq, HDIM]))
        cat = g.concatd('h%d_cat' % hl, heads, 1)
        attn = g.wmm('h%d_op' % hl, cat, t[p + 'self_attn.out_proj.weight'],
                     bias=t[p + 'self_attn.out_proj.bias'], free_key=p + 'self_attn.out_proj.weight')
        g.t[p + 'self_attn.out_proj.bias'] = None
        x = g.add('h%d_ra' % hl, res, attn)
        res = x
        h = g.layernorm('h%d_n2' % hl, x, t[p + 'norm2.weight'], t[p + 'norm2.bias'])
        ff = g.wmm('h%d_f1' % hl, h, t[p + 'linear1.weight'],
                   bias=t[p + 'linear1.bias'], free_key=p + 'linear1.weight')
        g.t[p + 'linear1.bias'] = None
        ff = g.activation('h%d_rel' % hl, ff, 1)
        ff = g.wmm('h%d_f2' % hl, ff, t[p + 'linear2.weight'],
                   bias=t[p + 'linear2.bias'], free_key=p + 'linear2.weight')
        g.t[p + 'linear2.bias'] = None
        x = g.add('h%d_rf' % hl, res, ff)

    g.outputs = [x + ':0']
    return x


def build_v2(g, kind_idx, markers, theta=160000.0, window=64):
    """The real emitter (node-to-node MatMul supported via g.mmn)."""
    t, seq = g.t, g.seq
    cos, sin = rope_tables(seq, theta)  # [seq, 32] freq pairs per head
    # candle rope: cos64 = concat([cos, cos]) per head (the halves convention),
    # then tiled across the 12 heads -> [seq, 768].
    def full(a):
        return np.concatenate([a, a], axis=-1).astype(np.float32)
    # The rope tables are per-position [seq, 768]; the batched stream is
    # [B*seq, 768] with row b*seq+i taking position i -- so each table is
    # tiled B times along rows.
    cosq = np.tile(np.tile(full(cos) * 0.125, (1, HEADS)).astype(np.float32), (B, 1))
    sinq = np.tile(np.tile(full(sin) * 0.125, (1, HEADS)).astype(np.float32), (B, 1))
    cosk = np.tile(np.tile(full(cos), (1, HEADS)).astype(np.float32), (B, 1))
    sink = np.tile(np.tile(full(sin), (1, HEADS)).astype(np.float32), (B, 1))
    pos = np.arange(seq)
    lmask = np.where(np.abs(pos[:, None] - pos[None, :]) > window,
                     -1e4, 0.0).astype(np.float32)
    rotm = rotate_mat()

    def rope(name, a, cosc, sinc):
        c = g.mul(name + '_c', a, g.const(cosc))
        r = g.mmn(name + '_r', a, g.const(rotm))
        rs = g.mul(name + '_rs', r, g.const(sinc))
        return g.add(name, c, rs)

    x = g.data('emb', [seq, DIM])
    x = g.layernorm('embnorm', x, t['encoder.embeddings.norm.weight'])

    for i in range(g.nlayers):
        p = 'encoder.layers.%d.' % i
        local = (i % 3) != 0
        res = x
        an = p + 'attn_norm.weight'
        h = g.layernorm('l%d_an' % i, x, t[an]) if an in t else x
        qkv = g.wmm('l%d_qkv' % i, h, t[p + 'attn.Wqkv.weight'],
                    free_key=p + 'attn.Wqkv.weight')
        s3 = g.splitd('l%d_s3' % i, qkv, 3, 1)
        qr = rope('l%d_rq' % i, s3 + ':0', cosq, sinq)
        kr = rope('l%d_rk' % i, s3 + ':1', cosk, sink)
        sq = g.splitd('l%d_sq' % i, qr, HEADS, 1)
        sk = g.splitd('l%d_sk' % i, kr, HEADS, 1)
        sv = g.splitd('l%d_sv' % i, s3 + ':2', HEADS, 1)
        # Per-head attention: 2D MatMul's shape inference rejects adj_x2
        # (x1Dims[1] != x2Dims[0]), so scores go through BatchMatMul (3D,
        # batch=1) which handles the transpose flag. Output is 2D MatMul
        # (no adj needed: [seq,seq] @ [seq,64]).
        heads = []
        for j in range(HEADS):
            vh = '%s:%d' % (sv, j)
            qh3 = g.op('l%d_q3_%d' % (i, j), 'Reshape',
                       ['%s:%d' % (sq, j), g.const_i32(np.array([1, seq, 64]))],
                       [1, seq, 64])
            kh3 = g.op('l%d_k3_%d' % (i, j), 'Reshape',
                       ['%s:%d' % (sk, j), g.const_i32(np.array([1, seq, 64]))],
                       [1, seq, 64])
            s3 = g.op('l%d_s3_%d' % (i, j), 'BatchMatMul', [qh3, kh3],
                      [1, seq, seq], attrs=[('adj_x2', attr_b(True))])
            if local:
                s3 = g.op('l%d_m3_%d' % (i, j), 'Add', [s3, g.const(lmask)],
                         [1, seq, seq])
            p3 = g.op('l%d_p3_%d' % (i, j), 'Softmax', [s3], [1, seq, seq],
                     attrs=[('axis', attr_i(2))])
            p2 = g.op('l%d_p2_%d' % (i, j), 'Reshape',
                      [p3, g.const_i32(np.array([seq, seq]))],
                      [seq, seq])
            heads.append(g.mmn('l%d_h%d_o' % (i, j), p2, vh))
        attn = g.concatd('l%d_cat' % i, heads, 1)
        attn = g.wmm('l%d_wo' % i, attn, t[p + 'attn.Wo.weight'],
                     free_key=p + 'attn.Wo.weight')
        x = g.add('l%d_ra' % i, res, attn)
        res = x
        h = g.layernorm('l%d_mn' % i, x, t[p + 'mlp_norm.weight'])
        wi = g.wmm('l%d_wi' % i, h, t[p + 'mlp.Wi.weight'],
                   free_key=p + 'mlp.Wi.weight')
        gs = g.splitd('l%d_gs' % i, wi, 2, 1)
        gate = g.activation('l%d_g' % i, gs + ':0', 15)  # GeLU
        m = g.mul('l%d_gm' % i, gate, gs + ':1')
        m = g.wmm('l%d_mo' % i, m, t[p + 'mlp.Wo.weight'],
                    free_key=p + 'mlp.Wo.weight')
        x = g.add('l%d_rm' % i, res, m)
        import sys as _s; print('layer %d ops=%d' % (i, len(g.ops)), file=_s.stderr, flush=True)

    x = g.layernorm('final', x, t['encoder.final_norm.weight'])
    typec = np.tile(t['type_emb.weight'][kind_idx][None, :], (seq, 1)).astype(np.float32)
    x = g.op('type', 'Add', [x, g.const(typec)], [seq, DIM])

    for hl in range(2):
        p = 'head.layers.%d.' % hl
        res = x
        h = g.layernorm('h%d_n1' % hl, x, t[p + 'norm1.weight'], t[p + 'norm1.bias'])
        qkv = g.wmm('h%d_ip' % hl, h, t[p + 'self_attn.in_proj_weight'],
                    bias=t[p + 'self_attn.in_proj_bias'])
        s3 = g.splitd('h%d_s3' % hl, qkv, 3, 1)
        sq = g.splitd('h%d_sq' % hl, s3 + ':0', HEADS, 1)
        sk = g.splitd('h%d_sk' % hl, s3 + ':1', HEADS, 1)
        sv = g.splitd('h%d_sv' % hl, s3 + ':2', HEADS, 1)
        heads = []
        for j in range(HEADS):
            qh = g.mul('h%d_q%d' % (hl, j), '%s:%d' % (sq, j),
                       g.const(np.full((seq, HDIM), 0.125, np.float32)))
            q3 = g.op('h%d_q3_%d' % (hl, j), 'Reshape',
                       [qh, g.const_i32(np.array([1, seq, HDIM]))], [1, seq, HDIM])
            k3 = g.op('h%d_k3_%d' % (hl, j), 'Reshape',
                       ['%s:%d' % (sk, j), g.const_i32(np.array([1, seq, HDIM]))], [1, seq, HDIM])
            s3 = g.bmm('h%d_s3_%d' % (hl, j), q3, k3, [1, seq, seq], adj_x2=True)
            p3 = g.op('h%d_p3_%d' % (hl, j), 'Softmax', [s3], [1, seq, seq],
                      attrs=[('axis', attr_i(2))])
            p_ = g.op('h%d_p2_%d' % (hl, j), 'Reshape',
                      [p3, g.const_i32(np.array([seq, seq]))], [seq, seq])
            heads.append(g.mmn('h%d_h%d_o' % (hl, j), p_, '%s:%d' % (sv, j)))
        attn = g.concatd('h%d_cat' % hl, heads, 1)
        attn = g.wmm('h%d_op' % hl, attn, t[p + 'self_attn.out_proj.weight'],
                     bias=t[p + 'self_attn.out_proj.bias'])
        x = g.add('h%d_ra' % hl, res, attn)
        res = x
        h = g.layernorm('h%d_n2' % hl, x, t[p + 'norm2.weight'], t[p + 'norm2.bias'])
        ff = g.wmm('h%d_f1' % hl, h, t[p + 'linear1.weight'],
                   bias=t[p + 'linear1.bias'])
        ff = g.activation('h%d_rel' % hl, ff, 1)  # relu
        ff = g.wmm('h%d_f2' % hl, ff, t[p + 'linear2.weight'],
                   bias=t[p + 'linear2.bias'])
        x = g.add('h%d_rf' % hl, res, ff)

    # markers: one-hot selector rows [n, seq] @ x -> [n, 768]
    sel = np.zeros((len(markers), seq), np.float32)
    for r, m in enumerate(markers):
        sel[r, m] = 1.0
    mk = g.mmn('mk', g.const(sel), x)
    s = g.layernorm('sc0', mk, t['scorer.0.weight'], t['scorer.0.bias'])
    s = g.wmm('sc1', s, t['scorer.1.weight'], bias=t['scorer.1.bias'])
    s = g.activation('scg', s, 15)
    s = g.wmm('sc2', s, t['scorer.3.weight'], bias=t['scorer.3.bias'])
    g.outputs = [s + ':0']
    return s


def _add_mmn(GraphClass):
    def mmn(self, name, a, b, adj2=False):
        # adj2 kept for the old call sites but never as an attr: the caller
        # must pass b already in [k, n] layout (pre-transposed).
        sa, sb = self.shapes[a], self.shapes[b]
        out = [sa[0], sb[1] if not adj2 else sa[1]]
        if adj2:
            out = [sa[0], sb[0]]
        return self.op(name, 'MatMul', [a, b], out)
    GraphClass.mmn = mmn
    return GraphClass


Graph = _add_mmn(Graph)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('bundle')
    ap.add_argument('body')
    ap.add_argument('--question', default=None)
    ap.add_argument('--out', default='/tmp/hiai-model.pb')
    ap.add_argument('--no-exec', action='store_true')
    ap.add_argument('--f32', action='store_true', help='emit F32 weights (default F16)')
    ap.add_argument('--layers', type=int, default=22, help='encoder layers to emit')
    ap.add_argument('--batched', type=int, default=0, metavar='B',
                    help='emit the fixed-shape batched serving graph: B slots, seq from --seq')
    ap.add_argument('--layout', choices=['normal', 'transposed'], default='normal',
                    help='transposed: the residual stream runs as [d, s], avoiding the blocked adj_x2')
    ap.add_argument('--stop', default=None,
                    help='transposed bisection: emit only through this stage (type/h0a/h0f/h1f)')
    ap.add_argument('--seq', type=int, default=0,
                    help='fixed seq for the batched graph (padded buckets)')
    a = ap.parse_args()

    model = Model(a.bundle)
    body = json.load(open(a.body))
    key = a.question or sorted(body['questions'])[0]
    q = body['questions'][key]
    from tokenizers import Tokenizer
    tok = Tokenizer.from_file(a.bundle + '/tokenizer.json')
    ids, markers, opts = build_sequence(model, tok, body, key, q)
    seq = len(ids)
    kind_idx = 0 if q.get('type', 'choice') == 'choice' else 2
    print('question %s: seq=%d markers=%s opts=%s' % (key, seq, markers, opts))

    # The reference runs FIRST: the graph build frees weight entries as it
    # emits them (free-after-emit), which the reference forward still needs.
    emb = model.t['encoder.embeddings.tok_embeddings.weight'][np.asarray(ids)]
    emb = np.ascontiguousarray(emb, np.float32)
    ref = None
    if not a.no_exec:
        # The reference must see the same layer count as the graph, or a
        # partial-layer validation compares against the full model.
        saved_nlayers = model.nlayers
        model.nlayers = a.layers
        ref = model.marker_logits(model.forward(ids, q.get('type', 'choice')), markers)
        model.nlayers = saved_nlayers
        print('numpy logits:', np.round(ref, 4))

    if a.batched > 0:
        S = a.seq if a.seq > 0 else max(len(ids), 64)
        g = Graph('laya', model.t, S)
        g.nlayers = a.layers
        # The mixed-dtype emission: F16 for the big weight Consts, F32 for
        # LayerNorm gamma/beta and the rope/mask tables.
        g.F16 = True
        build_batched(g, a.batched)
        buf = model_def('laya_npu', g)
        open(a.out, 'wb').write(buf)
        print('wrote %s (%.1f MB, %d ops) B=%d S=%d' % (a.out, len(buf) / 1e6, len(g.ops), a.batched, S))
        # the batched graph has no exec path yet (multi-input semantics)
        return

    g = Graph('laya', model.t, seq)
    g.nlayers = a.layers
    g.F16 = not a.f32
    if a.layout == 'transposed':
        build_transposed(g, kind_idx, markers, stop=a.stop)
        feed = np.ascontiguousarray(emb.T)
    else:
        build_v2(g, kind_idx, markers)
        feed = emb
    buf = model_def('laya_npu', g)
    open(a.out, 'wb').write(buf)
    print('wrote %s (%.1f MB, %d ops)' % (a.out, len(buf) / 1e6, len(g.ops)))
    open(a.out + '.input', 'wb').write(feed.tobytes())

    if not a.no_exec:
        import hiai_exec
        in_name = 'embT' if a.layout == 'transposed' else 'emb'
        out = hiai_exec.run(a.out, {in_name: feed})[g.outputs[0].split(':')[0]]
        cmp_out = out.T.ravel() if a.layout == 'transposed' else out.ravel()
        print('graph logits:', np.round(cmp_out, 4))
        print('max|delta|  :', float(np.abs(cmp_out - ref).max()))


if __name__ == '__main__':
    main()
