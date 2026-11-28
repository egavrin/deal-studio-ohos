#!/usr/bin/env python3
"""Convert the openJev (rlcd-modernbert-151m) ONNX into a MindSpore Lite .ms.

MindSpore Lite's converter rejects several ops / dtypes in the raw export, so this
applies a chain of semantics-preserving rewrites before converter_lite. The result
is a static 1x256 .ms that builds, and on the same ONNX is numerically faithful
(ORIG vs STATIC logits agree to fp16).

SOLVED (measured): the masked-query softmax NaN is removed at the source by replacing
the -inf attention-mask fill with a finite -1e4 (`finite_mask_fill`). A fully-masked
row's softmax then becomes a valid uniform distribution instead of 0/0, and a real row's
masked keys get weight exp(-1e4-max)~0 (still effectively masked), so real-token outputs
are unchanged but no NaN is ever produced. With this the .ms builds and RUNS on MindSpore
Lite: host CPU 529 ms; device CPU 1.45-1.68 s; host parity on a real masked prompt matches
ORT's argmax (lower logits drift, fp16). (An earlier self-attention `Where(diag,0,M)`
sink was tried first and broke MindSpore's graph build -- 2.9.0 Build failed, 2.6.0
segfault -- so the constant swap is used instead.)

REMAINING (NPU): on the phone, MindSpore NNRT enumerates the Kirin9010 NPU but the model
cannot run on it. The C-NDK probe (entry/src/main/cpp/napi_msnnrt.cpp) shows why: the NNRT
backend is unreachable (`get hdi service nnrt_device_service failed, -19`) and NNRT rejects
the graph (`Authentication failed, input model cannot run by npu`) -- an NNRT HDI/op-coverage
issue, not the model's NaN (solved above). See docs/local-jev/replacement-analysis.md §7.11; the CPU path is
the working on-device runtime.

Rewrites (all exact):
  1. Einsum (2)          -> MatMul (rotary) / Unsqueeze+Transpose+MatMul+Squeeze (head)
  2. dynamic inputs      -> static [1,seq] + onnx.shape_inference + onnxsim
  3. Flatten(axis=2)     -> Reshape([seq,1])                   converter's InferShapeByNNACL rejects axis>rank-1
  4. Cast(int64->bool)   -> Greater(x, 0)                      MindSpore's Cast kernel lacks int64->bool
  5. IsNaN (22)          -> Not(Equal(x, x))                   NaN detection; MindSpore has no IsNaN kernel

Usage:
  python convert_openjev_to_ms.py \
      --onnx model_fp16.onnx \
      --converter /path/to/mindspore-lite-*/tools/converter/converter/converter_lite \
      --out jev.ms [--seq 256]

Requires: onnx, onnxsim, numpy, and a working converter_lite.
"""
import argparse
import os
import subprocess

import numpy as np
import onnx
from onnx import helper, numpy_helper

BOOL = 9  # ONNX TensorProto.BOOL


def attr_int(n, name):
    for a in n.attribute:
        if a.name == name:
            return a.i
    return None


def attr_str(n, name):
    for a in n.attribute:
        if a.name == name:
            return a.s.decode() if isinstance(a.s, bytes) else a.s
    return None


def strip_isnan(m):
    """MindSpore rejects IsNaN; reproduce it exactly as Not(Equal(x, x)) -- NaN != NaN.

    The guard must be preserved, not replaced by Constant(False): fully-masked
    attention rows (padding) produce a NaN softmax and `Where(IsNaN(softmax), 0,
    softmax)` zeroes them. Dropping the guard propagates NaN to the logits. Apply
    this AFTER onnxsim so the simplifier does not fold Equal(x, x) to True.
    """
    g = m.graph
    new = []
    count = 0
    for n in g.node:
        if n.op_type == 'IsNaN':
            x = n.input[0]
            out = n.output[0]
            eq = out + '_eq'
            new.append(helper.make_node('Equal', [x, x], [eq]))
            new.append(helper.make_node('Not', [eq], [out]))
            count += 1
        else:
            new.append(n)
    del g.node[:]
    g.node.extend(new)
    return count


def rewrite_einsum(m):
    g = m.graph
    opset = [o.version for o in m.opset_import if o.domain in ('', 'ai.onnx')][0]
    new = []
    count = 0

    def axes_const(name, arr):
        return helper.make_node('Constant', [], [name],
                                value=numpy_helper.from_array(np.array(arr, dtype=np.int64), name=name + '_v'))

    for n in g.node:
        if n.op_type != 'Einsum':
            new.append(n)
            continue
        eq = attr_str(n, 'equation')
        ins = list(n.input)
        out = n.output[0]
        if eq == 'bks,bsd->bkd':
            # batched A[b,k,s] x B[b,s,d] -> [b,k,d]
            new.append(helper.make_node('MatMul', [ins[0], ins[1]], [out]))
            count += 1
        elif eq == 'BD,BCD->BC':
            # head: A[B,D] x B[B,C,D] -> [B,C]  =  (A[.,1,D] . B[B,D,C]) squeeze
            ua, tb, mm = out + '_ua', out + '_tb', out + '_mm'
            if opset >= 13:
                new.append(axes_const(out + '_ax1', [1]))
                new.append(helper.make_node('Unsqueeze', [ins[0], out + '_ax1'], [ua]))
            else:
                new.append(helper.make_node('Unsqueeze', [ins[0]], [ua], axes=[1]))
            new.append(helper.make_node('Transpose', [ins[1]], [tb], perm=[0, 2, 1]))
            new.append(helper.make_node('MatMul', [ua, tb], [mm]))
            if opset >= 13:
                new.append(axes_const(out + '_ax2', [1]))
                new.append(helper.make_node('Squeeze', [mm, out + '_ax2'], [out]))
            else:
                new.append(helper.make_node('Squeeze', [mm], [out], axes=[1]))
            count += 1
        else:
            raise SystemExit('unexpected einsum equation: ' + eq)
    del g.node[:]
    g.node.extend(new)
    return count


def bake_static(m, seq):
    for inp in m.graph.input:
        d = inp.type.tensor_type.shape.dim
        while len(d) < 2:
            d.add()
        d[0].dim_value = 1
        d[1].dim_value = seq
    try:
        return onnx.shape_inference.infer_shapes(m, strict_mode=False)
    except Exception:
        return m


def simplify(m, seq):
    import onnxsim
    shapes = {i.name: [1, seq] for i in m.graph.input}
    out, ok = onnxsim.simplify(m, overwrite_input_shapes=shapes)
    print('onnxsim ok =', ok)
    return out


def flatten_to_reshape(m, seq):
    g = m.graph
    new = []
    count = 0
    for n in g.node:
        if n.op_type == 'Flatten' and attr_int(n, 'axis') == 2:
            inp, out = n.input[0], n.output[0]
            sc = out + '_rshape'
            g.initializer.append(numpy_helper.from_array(np.array([seq, 1], dtype=np.int64), name=sc))
            new.append(helper.make_node('Reshape', [inp, sc], [out], name=n.name + '_reshape'))
            count += 1
        else:
            new.append(n)
    del g.node[:]
    g.node.extend(new)
    return count


def cast_bool_to_greater(m):
    g = m.graph
    new = []
    count = 0
    for n in g.node:
        if n.op_type == 'Cast' and attr_int(n, 'to') == BOOL:
            inp, out = n.input[0], n.output[0]
            z = out + '_z'
            dt = np.int64 if inp == 'attention_mask' else np.int32
            g.initializer.append(numpy_helper.from_array(np.array(0, dtype=dt), name=z))
            new.append(helper.make_node('Greater', [inp, z], [out], name=n.name + '_gt'))
            count += 1
        else:
            new.append(n)
    del g.node[:]
    g.node.extend(new)
    return count


def finite_mask_fill(m, fill=-10000.0):
    """Replace the -inf attention-mask fill with a large *finite* negative.

    A fully-masked query row with an all -inf mask makes softmax 0/0 = NaN (the model
    zeroes it with Where(IsNaN,0,.) -- the guard MindSpore cannot reproduce). With a
    finite fill (-1e4): a fully-masked row's softmax is a valid *uniform* distribution
    (exp(0) each), and a real row's masked keys get weight exp(-1e4 - max) which
    underflows to 0 -- i.e. still effectively masked. So NaN never arises, the guard
    becomes a no-op, and the graph builds/runs on MindSpore. (The earlier self-attention
    'sink' -- Where(diag,0,M) -- broke MindSpore's graph build; a constant swap does not.)
    Only the -inf operand of a mask `Where(cond, 0, -inf)` is touched.
    """
    g = m.graph
    consts = {}
    for i in g.initializer:
        consts[i.name] = numpy_helper.to_array(i)
    for n in g.node:
        if n.op_type == 'Constant':
            for at in n.attribute:
                if at.name == 'value':
                    consts[n.output[0]] = numpy_helper.to_array(at.t)

    def is_scalar(name, target):
        v = consts.get(name)
        return v is not None and v.size == 1 and float(v.ravel()[0]) == target

    neg_inf_names = set()
    for n in g.node:
        if n.op_type == 'Where' and len(n.input) == 3:
            if is_scalar(n.input[1], 0.0) and is_scalar(n.input[2], float('-inf')):
                neg_inf_names.add(n.input[2])

    changed = 0
    for name in neg_inf_names:
        for i, init in enumerate(g.initializer):
            if init.name == name:
                arr = numpy_helper.to_array(init)
                g.initializer[i] = numpy_helper.from_array(np.full(arr.shape, fill, dtype=arr.dtype), name=name)
                changed += 1
        for n in g.node:
            if n.op_type == 'Constant' and n.output[0] == name:
                for at in n.attribute:
                    if at.name == 'value':
                        arr = numpy_helper.to_array(at.t)
                        at.t.CopyFrom(numpy_helper.from_array(np.full(arr.shape, fill, dtype=arr.dtype), name=''))
                        changed += 1
    return changed


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--onnx', required=True, help='openJev model_fp16.onnx (or fp32)')
    ap.add_argument('--converter', required=True, help='path to converter_lite')
    ap.add_argument('--out', required=True, help='output .ms path')
    ap.add_argument('--seq', type=int, default=256, help='fixed sequence length (default 256)')
    a = ap.parse_args()

    m = onnx.load(a.onnx)
    print('1. Einsum rewritten:', rewrite_einsum(m))
    m = bake_static(m, a.seq)
    print('2. static shapes baked at 1x%d' % a.seq)
    n_fill = finite_mask_fill(m)
    print('2.5 finite mask fill (-1e4, no masked-NaN):', n_fill)
    m = simplify(m, a.seq)
    print('3. Flatten->Reshape:', flatten_to_reshape(m, a.seq))
    print('4. Cast bool->Greater:', cast_bool_to_greater(m))
    print('5. IsNaN -> Not(Equal):', strip_isnan(m))

    tmp = a.out + '.onnx'
    onnx.save(m, tmp)
    base = a.out[:-3] if a.out.endswith('.ms') else a.out
    cmd = [a.converter, '--fmk=ONNX', '--modelFile=' + tmp, '--outputFile=' + base]
    print('converting: ' + ' '.join(cmd))
    subprocess.run(cmd, check=True)
    if not os.path.exists(base + '.ms'):
        raise SystemExit('conversion did not produce ' + base + '.ms')
    print('written ' + base + '.ms')


if __name__ == '__main__':
    main()