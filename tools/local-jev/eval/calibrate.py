# Per-type calibration + routing from the host-Jev eval.
# Inputs: /tmp/eval/{bodies,cloud,openjev}/<name>.json (see tools/local-jev/eval/).
# For each choice question: openJev confidence, and match-with-cloud. Fits one global
# temperature (to correct openJev's overconfidence), reports ECE before/after, then
# per-type coverage/agreement at thresholds and a local-vs-cloud routing call.
import json, glob, os, math, collections

fixtures = sorted(os.path.basename(p)[:-5] for p in glob.glob('/tmp/eval/bodies/*.json'))
rows = []  # (type, confidence, match(0/1), abstain)
for name in fixtures:
    try:
        cloud = json.load(open('/tmp/eval/cloud/%s.json' % name)); cloud = cloud.get('answers', cloud)
        oj = json.load(open('/tmp/eval/openjev/%s.json' % name)); oj = oj.get('answers', oj)
    except Exception:
        continue
    for key, c in cloud.items():
        o = oj.get(key)
        if not o or 'choice' not in c or 'choice' not in o:
            continue
        rows.append((key.split('.')[0], float(o.get('confidence', 0.5)),
                     1.0 if o['choice'] == c['choice'] else 0.0, float(o.get('abstain', 0))))

n = len(rows)
def logit(p):
    p = min(max(p, 1e-6), 1 - 1e-6); return math.log(p / (1 - p))
def sig(x):
    return 1 / (1 + math.exp(-x))
def nll(T):
    s = 0.0
    for _, conf, m, _ in rows:
        p = sig(logit(conf) / T)
        s += -(m * math.log(max(p, 1e-9)) + (1 - m) * math.log(max(1 - p, 1e-9)))
    return s / n
def ece(T):
    bins = collections.defaultdict(list)
    for _, conf, m, _ in rows:
        p = sig(logit(conf) / T); bins[min(int(p * 10), 9)].append((p, m))
    e = 0.0
    for b, items in bins.items():
        e += len(items) / n * abs(sum(p for p, _ in items) / len(items) - sum(m for _, m in items) / len(items))
    return e

Ts = [0.4, 0.6, 0.8, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0, 4.0, 6.0]
bestT = min(Ts, key=nll)
print('choice questions: %d' % n)
print('global temperature: T*=%.2f  (NLL %.4f vs raw %.4f)' % (bestT, nll(bestT), nll(1.0)))
print('ECE: raw=%.3f  calibrated(T*)=%.3f' % (ece(1.0), ece(bestT)))

types = sorted(set(r[0] for r in rows))
print('\n%-11s %3s  %s' % ('type', 'n', 'thr -> coverage/agreement (openJev >= thr)'))
for t in types:
    rr = [r for r in rows if r[0] == t]
    parts = []
    for thr in (0.3, 0.5, 0.65, 0.8):
        above = [r for r in rr if r[1] >= thr]
        agr = sum(r[2] for r in above) / len(above) if above else 0.0
        parts.append('%.2f:%d/%.2f' % (thr, len(above), agr))
    print('%-11s %3d  %s' % (t, len(rr), '  '.join(parts)))

print('\nrouting at thr=0.5 (agreement with cloud):')
for t in types:
    rr = [r for r in rows if r[0] == t]; above = [r for r in rr if r[1] >= 0.5]
    agr = sum(r[2] for r in above) / len(above) if above else 0.0
    if not above:
        call = 'no confident picks'
    elif agr >= 0.85:
        call = 'LOCAL'
    elif agr < 0.6:
        call = 'CLOUD / plan'
    else:
        call = 'borderline (raise thr or cloud)'
    print('  %-11s cov=%d/%d agree=%.2f -> %s' % (t, len(above), len(rr), agr, call))