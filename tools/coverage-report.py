#!/usr/bin/env python3
"""
Turns a phone sweep (tools/device-jev-sweep.py output) plus docs/prompts/coverage-gold.json into the
coverage baseline report: per prompt the picked blocks and projected outcome, per domain and split the
share template / complete / scratch, the false-accept rate on negatives, and the "prompt -> missing
role" table for everything that ends as scratch or complete.

Outcome is a projection from Jev's note, not a pipeline run:
  no block picked or vetoed            -> scratch
  blocks picked, logic=... in the note -> complete (the model finishes the composed base)
  blocks picked, nothing else          -> template

Per-prompt rows are printed for the dev split only; the held-out split is reported as aggregates so the
design of blocks is not shaped by looking at it (pass --show-heldout to override).

    python3 tools/coverage-report.py /tmp/cov/sweep.json -o eval/results/2026-10-16-coverage-baseline.json
"""
import argparse, collections, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SEC = re.compile(r'section\d+=([a-z_]+)(?:\(([^)]*)\))?')


def project(note):
    blocks = []
    for kind, _why in SEC.findall(note):
        if kind != 'none' and kind not in blocks:
            blocks.append(kind)
    layout = re.search(r'layout=([a-z_]+)', note)
    if note.startswith('vetoed') or not blocks:
        outcome = 'scratch'
    elif 'logic=' in note:
        outcome = 'complete'
    else:
        outcome = 'template'
    return blocks, (layout.group(1) if layout else None), outcome


def share(rows):
    n = len(rows)
    if n == 0:
        return None
    c = collections.Counter(r['outcome'] for r in rows)
    return {'n': n, **{k: round(c[k] / n, 3) for k in ('template', 'complete', 'scratch')}}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('sweep')
    ap.add_argument('-o', '--out', required=True)
    ap.add_argument('--gold', default=os.path.join(ROOT, 'docs/prompts/coverage-gold.json'))
    ap.add_argument('--show-heldout', action='store_true')
    args = ap.parse_args()
    gold = {r['id']: r for r in json.load(open(args.gold))}
    sweep = json.load(open(args.sweep))
    rows = []
    for s in sweep:
        g = gold.get(s['id'])
        if g is None:
            continue
        blocks, layout, outcome = project(s['picked']) if s['picked'] != 'NO ANSWER' else ([], None, 'no_answer')
        rows.append({'id': s['id'], 'intentId': g['intentId'], 'domain': g['domain'], 'split': g['split'],
                     'phrasing': g['phrasing'], 'negative': g['negative'], 'prompt': g['prompt'],
                     'expect': g['expect'], 'blocks': blocks, 'layout': layout, 'outcome': outcome,
                     'ms': s.get('ms'), 'picked': s['picked'], 'raw': s.get('raw', '')})
    answered = [r for r in rows if r['outcome'] != 'no_answer']
    positive = [r for r in answered if not r['negative']]
    negative = [r for r in answered if r['negative']]
    report = {
        'date': os.environ.get('REPORT_DATE', ''),
        'method': 'phone sweep (device-jev-sweep.py); outcome is projected from the Jev note, not a pipeline run',
        'rows': len(rows), 'no_answer': [r['id'] for r in rows if r['outcome'] == 'no_answer'],
        'overall_positive': share(positive),
        'by_split_positive': {sp: share([r for r in positive if r['split'] == sp]) for sp in ('dev', 'heldout')},
        'by_domain_dev': {d: share([r for r in positive if r['split'] == 'dev' and r['domain'] == d])
                          for d in sorted({r['domain'] for r in positive})},
        'false_accept': {'negatives': len(negative),
                         'accepted': [r['id'] for r in negative if r['outcome'] != 'scratch'],
                         'rate': round(sum(r['outcome'] != 'scratch' for r in negative) / len(negative), 3) if negative else None},
        'expected_vs_projected_positive': dict(collections.Counter(
            (r['expect']['outcome'], r['outcome']) .__repr__() for r in positive)),
        'missing_role_table_dev': [
            {'id': r['id'], 'prompt': r['prompt'], 'wants': r['expect']['roles'], 'got': r['blocks'],
             'outcome': r['outcome']} for r in positive if r['split'] == 'dev' and r['outcome'] != 'template'],
        'rows_detail': [r for r in rows if r['split'] == 'dev' or args.show_heldout],
    }
    json.dump(report, open(args.out, 'w'), indent=1)
    print(json.dumps({k: report[k] for k in ('rows', 'overall_positive', 'by_split_positive', 'false_accept')}, indent=1))


if __name__ == '__main__':
    main()
