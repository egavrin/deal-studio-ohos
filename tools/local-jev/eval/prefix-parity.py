#!/usr/bin/env python3
"""Compare baseline (per-question full sequences) vs prefix (shared state KV)
Laya scores on the fixture bodies: logit drift, argmax flips, served-set
changes at the serving threshold (T=2.2, min_confidence=0.71), and wall time
from the LOCAL_JEV_TRACE lines. Decides whether the approximation is sound."""
import glob, json, os, re, sys

T, THRESH = 2.2, 0.71

def softmax(logits, t):
    ks = list(logits)
    scaled = {k: v / t for k, v in logits.items()}
    top = max(scaled.values())
    e = {k: pow(2.718281828, v - top) for k, v in scaled.items()}
    z = sum(e.values())
    return {k: v / z for k, v in e.items()}

def decide(logits):
    p = softmax(logits, T)
    pick = max(p, key=p.get)
    return pick, p[pick]

tot_q = flip = served_base = served_same = 0
max_d = 0.0
sum_d = 0.0
n_d = 0
for base_f in sorted(glob.glob('/tmp/prefix-base-*.json')):
    name = os.path.basename(base_f)[len('prefix-base-'):-len('.json')]
    new_f = f'/tmp/prefix-new-{name}.json'
    if not os.path.exists(new_f):
        print(f'{name}: no prefix run'); continue
    try:
        a = json.load(open(base_f)).get('scores', {})
        b = json.load(open(new_f)).get('scores', {})
    except (json.JSONDecodeError, OSError):
        print(f'{name}: unreadable run (in progress?)'); continue
    if not b:
        print(f'{name}: prefix run failed: {json.load(open(new_f))}'); continue
    for k in a:
        if k not in b:
            print(f'{name}/{k}: missing in prefix'); continue
        la, lb = a[k]['logits'], b[k]['logits']
        for o in la:
            if o in lb:
                d = abs(la[o] - lb[o])
                max_d = max(max_d, d); sum_d += d; n_d += 1
        tot_q += 1
        pa, ca = decide(la)
        pb, cb = decide(lb)
        if pa != pb: flip += 1
        if ca >= THRESH:
            served_base += 1
            if pa == pb and cb >= THRESH: served_same += 1
            elif pa != pb or cb < THRESH:
                print(f'  lost/changed served {name}/{k} (base {pa}@{ca:.2f} -> prefix {pb}@{cb:.2f})')
        elif cb >= THRESH:
            print(f'  new-served only {name}/{k} ({pa} -> {pb})')

print(f'\nquestions: {tot_q}, argmax flips: {flip} ({flip/max(tot_q,1):.1%})')
print(f'logit drift: max {max_d:.3f}, mean {sum_d/max(n_d,1):.4f} over {n_d} logits')
print(f'baseline-served (conf>={THRESH}): {served_base}, same pick+conf in prefix: {served_same}')

print('\nwall time (total_ms) per body:')
tb = tn = 0
for name in sorted(os.path.basename(f)[len('prefix-base-'):-len('.json')] for f in glob.glob('/tmp/prefix-base-*.trace')):
    def ms(path, tag):
        try:
            for line in open(path):
                m = re.search(r'total_ms=(\d+)', line)
                if m: return int(m.group(1))
        except FileNotFoundError: pass
        return None
    b_ms = ms(f'/tmp/prefix-base-{name}.trace', 'base')
    n_ms = ms(f'/tmp/prefix-new-{name}.trace', 'new')
    if b_ms and n_ms:
        tb += b_ms; tn += n_ms
        print(f'  {name:12s} base {b_ms:6d} ms  prefix {n_ms:6d} ms  ({b_ms/n_ms:.2f}x)')
print(f'  TOTAL base {tb} ms  prefix {tn} ms  speedup {tb/max(tn,1):.2f}x')
