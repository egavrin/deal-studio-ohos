#!/usr/bin/env python3
"""Offline executor for the emitted HiAI ModelDef protobuf.

Parses the wire format (same reader as the analysis walker) and interprets
the ops in numpy -- the phone-free validation of the generated graph. Op set:
Data, Const, MatMul (adj_x2), Add, Mul, LayerNorm, Softmax, SplitD, ConcatD,
Activation. Tensors are keyed "opname:port".
"""
import struct

import numpy as np


def rd_varint(d, i):
    v = sh = 0
    while True:
        b = d[i]
        i += 1
        v |= (b & 0x7F) << sh
        sh += 7
        if not b & 0x80:
            return v, i


def walk(d):
    i = 0
    out = []
    while i < len(d):
        key, i = rd_varint(d, i)
        f, wt = key >> 3, key & 7
        if wt == 0:
            v, i = rd_varint(d, i)
            out.append((f, 'v', v))
        elif wt == 2:
            ln, i = rd_varint(d, i)
            out.append((f, 'b', d[i:i + ln]))
            i += ln
        elif wt == 5:
            out.append((f, 'f', struct.unpack('<f', d[i:i + 4])[0]))
            i += 4
        else:
            raise ValueError('wire type %d' % wt)
    return out


def parse_attrs(entry):
    """attr map entry {key(str f1), value(AttrDef f2)} -> dict."""
    fields = walk(entry)
    key = None
    val = None
    for f, t, v in fields:
        if f == 1:
            key = v.decode()
        elif f == 2:
            val = v
    a = walk(val)
    attrs = {}
    for f, t, v in a:
        if f == 3:
            attrs['i'] = v
        elif f == 4:
            attrs['f'] = v
        elif f == 5:
            attrs['b'] = bool(v)
        elif f == 12:  # TensorDef
            tf = walk(v)
            desc = walk([x for x in tf if x[0] == 1][0][2])
            # parse dtype (field 2 of TensorDescriptor)
            dtype_fields = [x for x in desc if x[0] == 2]
            dtype = dtype_fields[0][2] if dtype_fields else 1  # default DT_FLOAT
            shape_msg = walk([x for x in desc if x[0] == 3][0][2])
            dims = []
            for sf, st, sv in shape_msg:
                if sf == 1:
                    if isinstance(sv, bytes):
                        pi = 0
                        while pi < len(sv):
                            val, pi = rd_varint(sv, pi)
                            dims.append(val)
                    else:
                        dims.append(sv)
            data = [x for x in tf if x[0] == 2]
            attrs['tensor'] = (dims, data[0][2] if data else b'', dtype)
    return key, attrs


def parse_model(buf):
    top = walk(buf)
    graphs = [v for f, t, v in top if f == 7]
    g = walk(graphs[0])
    name = [v for f, t, v in g if f == 1][0].decode()
    inputs = [v.decode() for f, t, v in g if f == 4]
    outputs = [v.decode() for f, t, v in g if f == 5]
    ops = []
    for f, t, v in g:
        if f != 6:
            continue
        o = walk(v)
        oname = otype = None
        ins, attrs, indescs, outdescs = [], {}, [], []
        for ff, tt, vv in o:
            if ff == 1:
                oname = vv.decode()
            elif ff == 2:
                otype = vv.decode()
            elif ff == 5:
                ins.append(vv.decode())
            elif ff == 10:
                k, av = parse_attrs(vv)
                attrs[k] = av
            elif ff == 33:
                indescs.append(vv)
            elif ff == 34:
                outdescs.append(vv)
        nout = 1
        if otype == 'SplitD':
            nout = attrs['num_split']['i']
        ops.append((oname, otype, ins, attrs, nout))
    return {'name': name, 'inputs': inputs, 'outputs': outputs, 'ops': ops}


def _gelu(x):
    import math
    erf = np.vectorize(math.erf)
    return (0.5 * x * (1 + erf(x / np.sqrt(2)))).astype(np.float32)


def run(buf, data_inputs):
    m = parse_model(buf if isinstance(buf, (bytes, bytearray)) else open(buf, 'rb').read())
    tensors = {}
    for oname, otype, ins, attrs, nout in m['ops']:
        def get(ref):
            if ':' not in ref:
                ref += ':0'
            return tensors[ref]

        if otype == 'Data':
            tensors[oname + ':0'] = np.asarray(data_inputs[oname], np.float32)
            continue
        if otype == 'Const':
            dims, raw, dtype = attrs['value']['tensor']
            if dtype == 7:  # DT_INT32
                arr = np.frombuffer(raw, '<i4')
            elif dtype == 2:  # DT_FLOAT16
                arr = np.frombuffer(raw, '<f2').astype(np.float32)
            else:  # DT_FLOAT (1) and others: read as f32
                arr = np.frombuffer(raw, '<f4')
            tensors[oname + ':0'] = arr.reshape(dims)
            attrs['value']['tensor'] = (dims, b'', dtype)  # free raw bytes
            continue
        if otype == 'MatMul':
            a, b = get(ins[0]), get(ins[1])
            if attrs.get('adj_x1', {}).get('b', False) or attrs.get('adj_x1', {}).get('i', 0):
                a = a.T
            if attrs.get('adj_x2', {}).get('b', False) or attrs.get('adj_x2', {}).get('i', 0):
                b = b.T
            y = a @ b
        elif otype == 'Add':
            y = get(ins[0]) + get(ins[1])
        elif otype == 'Sub':
            y = get(ins[0]) - get(ins[1])
        elif otype == 'RealDiv':
            y = get(ins[0]) / get(ins[1])
        elif otype == 'Mul':
            y = get(ins[0]) * get(ins[1])
        elif otype == 'LayerNorm':
            x = get(ins[0])
            gamma, beta = get(ins[1]), get(ins[2])
            eps = attrs['epsilon']['f']
            axis = attrs['begin_norm_axis']['i']
            mu = x.mean(axis, keepdims=True)
            var = x.var(axis, keepdims=True)
            y = (x - mu) / np.sqrt(var + eps) * gamma + beta
        elif otype == 'Softmax':
            x = get(ins[0])
            axis = attrs['axis']['i']
            if axis >= 1 << 63:  # negative axes arrive as two's-complement varints
                axis -= 1 << 64
            e = np.exp(x - x.max(axis, keepdims=True))
            y = e / e.sum(axis, keepdims=True)
        elif otype == 'SplitD':
            x = get(ins[0])
            n = attrs['num_split']['i']
            axis = attrs['split_dim']['i']
            for i, part in enumerate(np.split(x, n, axis)):
                tensors['%s:%d' % (oname, i)] = np.ascontiguousarray(part)
            continue
        elif otype == 'ConcatD':
            axis = attrs['concat_dim']['i']
            y = np.concatenate([get(i) for i in ins], axis)
        elif otype == 'BatchMatMul':
            a, b = get(ins[0]), get(ins[1])
            if attrs.get('adj_x1', {}).get('b', False) or attrs.get('adj_x1', {}).get('i', 0):
                a = np.swapaxes(a, -1, -2)
            if attrs.get('adj_x2', {}).get('b', False) or attrs.get('adj_x2', {}).get('i', 0):
                b = np.swapaxes(b, -1, -2)
            y = a @ b
        elif otype == 'Reshape':
            x = get(ins[0])
            shape_arr = get(ins[1])
            if shape_arr.dtype in (np.float32, np.float16):
                shape = shape_arr.astype(np.int64).ravel().tolist()
            else:
                shape = shape_arr.ravel().tolist()
            y = x.reshape(shape)
        elif otype == 'Activation':
            x = get(ins[0])
            mode = attrs['mode']['i']
            if mode == 15:
                y = _gelu(x)
            elif mode == 1:
                y = np.maximum(x, 0)
            else:
                raise ValueError('activation mode %d' % mode)
        else:
            raise ValueError('op %s not implemented' % otype)
        tensors[oname + ':0'] = np.ascontiguousarray(y, np.float32)
    out = {}
    for o in m['outputs']:
        key = o if ':' in o else o + ':0'
        base = o.rsplit(':', 1)[0]
        if key in tensors or o in tensors:
            out[base] = tensors.get(key, tensors.get(o))
        else:
            raise KeyError('output %s not computed' % o)
    return out
