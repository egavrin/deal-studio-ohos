# Compare cloud Jev (recorded) vs openJev (ORT) vs Laya (dev service) on the
# host-eval bodies, per decision type. Choice match = same option picked; noul
# match = same side of a 0.5 threshold. Reports agreement, confidence, abstain.
import json, os, glob
import collections

FIX = sorted(os.path.basename(p)[:-5] for p in glob.glob('/tmp/eval/bodies/*.json'))

def load(kind, name):
    p = '/tmp/eval/%s/%s.json' % (kind, name)
    try:
        d = json.load(open(p))
        ans = d.get('answers', d)
        return ans if isinstance(ans, dict) else {}
    except Exception:
        return {}

def side(noul):
    try: return 'yes' if float(noul) >= 0.5 else 'no'
    except Exception: return None

def type_of(key):
    return key.split('.')[0]

stats = collections.defaultdict(lambda: collections.Counter())
conf = collections.defaultdict(list)
for name in FIX:
    cloud = load('cloud', name); oj = load('openjev', name); ly = load('laya', name)
    for key, c in cloud.items():
        t = type_of(key)
        oc = oj.get(key); lc = ly.get(key)
        if 'choice' in c or ('noul' not in c):
            cc = c.get('choice')
            if oc and 'choice' in oc and cc:
                stats[t]['n'] += 1
                ok = (oc['choice'] == cc)
                stats[t]['oj_match'] += 1 if ok else 0
                conf[t].append((ok, oc.get('confidence', 0), oc.get('abstain', 0)))
                stats[t]['oj_abstain'] += 1 if oc.get('abstain', 0) >= 0.5 else 0
            if lc and 'choice' in lc and cc:
                stats[t]['ln'] += 1
                stats[t]['ly_match'] += 1 if (lc['choice'] == cc) else 0
        else:
            cs = side(c.get('noul'))
            if oc and 'noul' in oc and cs:
                stats[t]['nn'] += 1
                stats[t]['oj_nmatch'] += 1 if side(oc['noul']) == cs else 0
            if lc and 'noul' in lc and cs:
                stats[t]['lnn'] += 1
                stats[t]['ly_nmatch'] += 1 if side(lc['noul']) == cs else 0

print('type        choice n=  oj_agree   meanConf(ok/bad)  abstain   | laya n= agree   | noul n= oj_agree laya')
tot = collections.Counter(); totconf = []
for t in sorted(stats):
    s = stats[t]; c = conf[t]
    if s['n']:
        ok_n = sum(1 for x in c if x[0]); bad_n = len(c) - ok_n
        mc_ok = sum(x[1] for x in c if x[0]) / ok_n if ok_n else 0
        mc_bad = sum(x[1] for x in c if not x[0]) / bad_n if bad_n else 0
        tot['n'] += s['n']; tot['oj_match'] += s['oj_match']
    else:
        mc_ok = mc_bad = 0
    line = '%-10s %4d %8d %5.2f  %5.2f/%5.2f  %3d | %4d %5d' % (
        t, s['n'], s['oj_match'], (s['oj_match']/s['n'] if s['n'] else 0), mc_ok, mc_bad, s['oj_abstain'], s['ln'], s['ly_match'])
    if s['nn'] or s['lnn']:
        line += ' | %4d %6d %5d' % (s['nn'], s['oj_nmatch'], s['ly_nmatch'])
    print(line)
print('TOTAL choice=%d oj_agree=%d (%.1f%%)' % (tot['n'], tot['oj_match'], 100.0*tot['oj_match']/tot['n'] if tot['n'] else 0))