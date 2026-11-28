#!/usr/bin/env python3
"""Fit the Laya serving calibration from the recorded device run (2026-11-24).

Data: /tmp/eval/laya_raw/<name>.json -- the *untruncated* per-option logits the
deployed model produced on the Kirin CPU for the 8 recorded compose bodies --
and /tmp/eval/proxy-answers.json -- the JevProxy (cloud) answers for the same
112 questions, recorded on the same device.

Reference label = the cloud's choice. This is agreement calibration, not
ground-truth calibration: the fit makes the model's reported confidence honest
about "will match the cloud", which is the property the hybrid route relies on
(serve locally only where the local pick would be what the cloud says anyway).

Outputs the temperature (softmax flattening) and min_confidence (serve
threshold) for the laya-manifest.json `calibration` block, with the per-type
coverage/agreement the threshold was chosen on. n = 75 choice questions: this
is a preliminary, in-sample fit -- §5.A of the analysis calls for 200-500
labelled decisions per task before final thresholds; re-run at scale.
"""
import glob
import hashlib
import json
import math
import os
import sys

RAW = sys.argv[1] if len(sys.argv) > 1 else '/tmp/eval/laya_raw'
PROXY = sys.argv[2] if len(sys.argv) > 2 else '/tmp/eval/proxy-answers.json'


def load_records():
    proxy = json.load(open(PROXY))
    records = []
    for path in sorted(glob.glob(os.path.join(RAW, '*.json'))):
        fixture = os.path.basename(path)[:-5]
        scores = json.load(open(path)).get('scores', {})
        cloud = proxy.get(fixture)
        if not isinstance(cloud, dict):
            continue
        cloud_answers = cloud.get('answers')
        if isinstance(cloud_answers, str):
            cloud_answers = json.loads(cloud_answers).get('answers', {})
        elif isinstance(cloud_answers, dict):
            cloud_answers = cloud_answers.get('answers', {})
        if not isinstance(cloud_answers, dict):
            continue
        for key, entry in scores.items():
            label = cloud_answers.get(key)
            if not isinstance(label, dict):
                continue
            logits = entry.get('logits')
            choice = label.get('choice')
            if not isinstance(logits, dict) or not isinstance(choice, str):
                continue  # noul questions have no choice label; excluded from the fit
            if len(logits) < 2 or choice not in logits:
                continue
            records.append({
                'fixture': fixture,
                'key': key,
                'type': key.split('.')[0],
                'logits': logits,
                'cloud_choice': choice,
            })
    return records


def softmax(logits, temperature):
    scaled = {k: v / temperature for k, v in logits.items()}
    top = max(scaled.values())
    exp = {k: math.exp(v - top) for k, v in scaled.items()}
    total = sum(exp.values())
    return {k: v / total for k, v in exp.items()}


def fit_temperature(records):
    best = (None, float('inf'))
    t = 0.5
    while t <= 8.0001:
        nll = 0.0
        for r in records:
            p = softmax(r['logits'], t)[r['cloud_choice']]
            nll -= math.log(max(p, 1e-12))
        if nll < best[1]:
            best = (round(t, 3), nll)
        t += 0.01 if t < 2 else 0.05
    return best


def sweep_thresholds(records, temperature):
    rows = []
    for i in range(0, 47):  # 0.50 .. 0.96
        thr = 0.50 + i * 0.01
        served = []
        for r in records:
            p = softmax(r['logits'], temperature)
            pick = max(p, key=p.get)
            if p[pick] >= thr:
                served.append((r, pick))
        if not served:
            continue
        agree = sum(1 for r, pick in served if pick == r['cloud_choice'])
        rows.append((round(thr, 2), len(served), agree / len(served),
                     len(served) / len(records)))
    return rows


def type_breakdown(records, temperature, threshold):
    table = {}
    for r in records:
        p = softmax(r['logits'], temperature)
        pick = max(p, key=p.get)
        served = p[pick] >= threshold
        t = table.setdefault(r['type'], [0, 0, 0])  # served, agree, total
        t[2] += 1
        if served:
            t[0] += 1
            t[1] += 1 if pick == r['cloud_choice'] else 0
    return table


def dataset_sha256(records):
    canon = json.dumps(
        [{'fixture': r['fixture'], 'key': r['key'], 'logits': r['logits'],
          'cloud_choice': r['cloud_choice']} for r in records],
        sort_keys=True)
    return hashlib.sha256(canon.encode()).hexdigest()


def main():
    records = load_records()
    print('records (choice questions with local logits + cloud choice):', len(records))
    if not records:
        sys.exit('no usable records -- check the input paths')
    temperature, nll = fit_temperature(records)
    print('fitted temperature T* =', temperature, ' NLL =', round(nll, 3))
    print()
    print(' thr  served  agreement  coverage')
    for thr, n, agree, cov in sweep_thresholds(records, temperature):
        print(f' {thr:.2f}  {n:5d}   {agree:6.1%}    {cov:6.1%}')
    chosen = 0.9
    for thr, n, agree, cov in sweep_thresholds(records, temperature):
        if agree >= 0.90 and n >= 8:
            chosen = thr
            break
    print()
    print('chosen min_confidence =', chosen)
    table = type_breakdown(records, temperature, chosen)
    print('per-type (served/total, agreement among served):')
    for t in sorted(table):
        s, a, tot = table[t]
        print(f'  {t:12s} {s:3d}/{tot:3d}  {a / s:5.0%}' if s else f'  {t:12s}   0/{tot:3d}   --')
    sha = dataset_sha256(records)
    print()
    print('dataset sha256 =', sha)
    print('manifest calibration block:')
    print(json.dumps({
        'calibrated': True,
        'temperature': temperature,
        'min_confidence': chosen,
        'reference': 'cloud-jevproxy-agreement',
        'note': ('in-sample fit on the 2026-11-24 device run (laya_raw vs '
                 'proxy-answers); preliminary per docs/local-jev/cpu-vs-cloud.md'),
        'training_data_sha256': sha,
        'calibration_data_sha256': sha,
    }, indent=2))


if __name__ == '__main__':
    main()
