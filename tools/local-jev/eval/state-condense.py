#!/usr/bin/env python3
"""Measure what a condensed Jev state costs the on-device Laya model.

The local model re-reads the shared state for every question of a body, and its
attention is quadratic in the sequence length, so the state is the dominant cost
on state-heavy bodies (a plan text, a section as code). This script answers the
question a pipeline change must answer first: does handing the model a shorter
state change what it would answer?

For each body it runs the host `local-laya --scores` on the full state and on
condensed variants (the state cut to its first K characters, at a line or word
boundary; optionally with the code section dropped), applies the serving
calibration from the bundle manifest, and compares every variant with the
full-state run:

  - argmax flips (the metric that rejected prefix-KV state sharing: 27.7%)
  - which questions the calibration would still serve, and whether the served
    answers change
  - the questions the full-state calibration declines, where the cloud
    answered: how often the variant's argmax would have matched the cloud
    (the headroom a per-type threshold refit could serve)
  - wall time per variant (same host binary, so relative)

Inputs: `--body FILE` (one Jev body), `--bodies DIR` (a directory of them), or
`--runlog FILE` (a run-log.jsonl; the last record's recorded local-decision
bodies, and the cloud answers recorded beside them). The run-log path needs
`--ps jevLocalLog 1` to have been set for that run.
"""
import argparse
import json
import math
import os
import subprocess
import sys
import time


def load_calibration(bundle):
    with open(os.path.join(bundle, 'laya-manifest.json'), encoding='utf-8') as stream:
        block = json.load(stream).get('calibration') or {}
    return float(block.get('temperature', 1.0)), float(block.get('min_confidence', 0.5))


def decisions(scores, temperature, threshold):
    """The serving decision rule, mirroring crate::decisions."""
    answers = {}
    argmax = {}
    for key, question in scores.items():
        logits = question.get('logits') or {}
        vals = [(k, v / temperature) for k, v in logits.items()
                if isinstance(v, (int, float)) and math.isfinite(v)]
        if len(vals) < 2:
            continue
        top = max(v for _, v in vals)
        total = sum(math.exp(v - top) for _, v in vals)
        best_id = max(vals, key=lambda kv: kv[1])[0]
        argmax[key] = best_id
        confidence = math.exp(max(v for _, v in vals) - top) / total
        if confidence < threshold:
            continue
        if question.get('type') == 'noul':
            chosen = dict(vals).get('true')
            if chosen is not None:
                answers[key] = math.exp(chosen - top) / total
        else:
            answers[key] = best_id
    return answers, argmax


def cut_at_boundary(text, limit):
    if len(text) <= limit:
        return text
    cut = text.rfind('\n', 0, limit)
    if cut < limit // 2:
        cut = text.rfind(' ', 0, limit)
    if cut < limit // 2:
        cut = limit
    return text[:cut]


def variants_of(state, limits):
    out = [('full', state)]
    for limit in limits:
        if len(state) > limit:
            out.append(('head-%d' % limit, cut_at_boundary(state, limit)))
    marker = state.find('The section, as code:')
    if marker > 0:
        out.append(('no-code', state[:marker].rstrip()))
    return out


def run_cli(cli, bundle, body):
    started = time.perf_counter()
    env = dict(os.environ)
    env['LOCAL_JEV_TRACE'] = '1'
    # --diagnostic-scores is the capped input policy the serving path uses
    # (real compose bodies exceed the strict head budget and are truncated).
    proc = subprocess.run([cli, '--bundle', bundle, '--diagnostic-scores'],
                          input=json.dumps(body, ensure_ascii=False).encode('utf-8'),
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=900, env=env)
    wall_ms = int((time.perf_counter() - started) * 1000)
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr.decode('utf-8', 'replace')[:400] + '\n')
        return None, {'wall_ms': wall_ms}
    reply = json.loads(proc.stdout.decode('utf-8'))
    # The trace line separates the forward pass from the one-time model load
    # every fresh process pays: total_ms is tokenize+infer+marker only.
    stats = {'wall_ms': wall_ms, 'total_ms': -1, 'infer_ms': -1, 'seq_tokens': -1}
    for line in proc.stderr.decode('utf-8', 'replace').splitlines():
        if line.startswith('LOCAL_JEV_TRACE'):
            for field in line.replace('LOCAL_JEV_TRACE', '').split():
                if '=' in field:
                    key, value = field.split('=', 1)
                    if key in stats:
                        stats[key] = int(value)
    return (reply.get('scores') or {}), stats


def bodies_from_args(args):
    out = []
    if args.body:
        out.append((os.path.basename(args.body), json.load(open(args.body, encoding='utf-8'))))
    if args.bodies:
        for name in sorted(os.listdir(args.bodies)):
            if name.endswith('.json'):
                path = os.path.join(args.bodies, name)
                out.append((name[:-5], json.load(open(path, encoding='utf-8'))))
    if args.runlog:
        with open(args.runlog, encoding='utf-8') as stream:
            records = [json.loads(line) for line in stream if line.strip()]
        record = records[-1]
        calls = record.get('selectorCalls') or []
        for call in calls:
            if call.get('backend') == 'local-decision' and call.get('body'):
                out.append(('recorded', json.loads(call['body'])))
    return out


def cloud_answers_from_args(args):
    """The answers the selected source gave, from a recorded run's cloud calls."""
    if not args.runlog:
        return {}
    with open(args.runlog, encoding='utf-8') as stream:
        record = [json.loads(line) for line in stream if line.strip()][-1]
    answers = {}
    for call in record.get('selectorCalls') or []:
        if call.get('backend') != 'local-decision' and call.get('reply'):
            try:
                found = (json.loads(call['reply']).get('answers') or {})
            except ValueError:
                continue
            for key, value in found.items():
                answers[key] = value.get('choice') if isinstance(value, dict) else value
    return answers


def compare(name, full, variant, label, cloud, temperature, threshold):
    served_full, argmax_full = decisions(full, temperature, threshold)
    served_var, argmax_var = decisions(variant, temperature, threshold)
    shared = [k for k in argmax_full if k in argmax_var]
    flips = [k for k in shared if argmax_full[k] != argmax_var[k]]
    both_served = [k for k in served_full if k in served_var]
    changed = [k for k in both_served if served_full[k] != served_var[k]]
    dropped = [k for k in served_full if k not in served_var]
    added = [k for k in served_var if k not in served_full]
    declined = [k for k in argmax_full if k not in served_full]
    cloud_hit = [k for k in declined if k in cloud and cloud[k] == argmax_full[k]]
    print('%-12s %-9s q=%-3d flips=%-3d(%4.1f%%) served=%-3d changed=%-2d drop=%-2d add=%-2d '
          'declined-match-cloud=%d/%d' % (
              name, label, len(shared), len(flips),
              100.0 * len(flips) / max(1, len(shared)),
              len(served_var), len(changed), len(dropped), len(added),
              len(cloud_hit), len(declined)))
    return {
        'body': name, 'variant': label, 'questions': len(shared),
        'argmax_flips': len(flips), 'served': len(served_var),
        'served_changed': len(changed), 'served_dropped': len(dropped),
        'served_added': len(added), 'cloud_match_on_declined': len(cloud_hit),
        'declined': len(declined),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--body', help='one Jev body JSON file')
    parser.add_argument('--bodies', help='a directory of Jev body JSON files')
    parser.add_argument('--runlog', help='a run-log.jsonl with recorded bodies')
    parser.add_argument('--cli', default='native/local-jev/target/release/local-laya')
    parser.add_argument('--bundle', default='.local-jev/bundle-q4')
    parser.add_argument('--limits', default='200,400,800', help='state head lengths to try')
    parser.add_argument('--out', help='write the results table as JSON')
    args = parser.parse_args()

    temperature, threshold = load_calibration(args.bundle)
    print('calibration: temperature=%.3f min_confidence=%.3f' % (temperature, threshold))
    limits = [int(x) for x in args.limits.split(',') if x.strip()]
    cloud = cloud_answers_from_args(args)
    bodies = bodies_from_args(args)
    if not bodies:
        parser.error('give one of --body, --bodies or --runlog')
    rows = []
    timings = []
    for index, (name, body) in enumerate(bodies):
        label = name if len(bodies) == 1 else '%s-%d' % (name, index)
        state = body.get('state', '')
        print('\n%s: state %d chars, %d questions' % (label, len(state), len(body.get('questions') or {})))
        results = {}
        times = {}
        for variant, variant_state in variants_of(state, limits):
            variant_body = dict(body)
            variant_body['state'] = variant_state
            scores, stats = run_cli(args.cli, args.bundle, variant_body)
            times[variant] = stats
            if scores is None:
                print('%-12s %-9s FAILED' % (label, variant))
                continue
            results[variant] = scores
            if variant == 'full':
                full_scores = scores
        for variant, scores in results.items():
            if variant == 'full':
                continue
            rows.append(compare(label, full_scores, scores, variant, cloud, temperature, threshold))
        for variant, stats in times.items():
            timings.append({'body': label, 'variant': variant, 'ms': stats['total_ms'],
                            'wall_ms': stats['wall_ms'], 'infer_ms': stats['infer_ms'],
                            'seq_tokens': stats['seq_tokens']})
        full = times.get('full') or {}
        print('%-12s %-9s seq_tokens=%s forward=%s ms (host, load excluded)' % (
            label, 'full', full.get('seq_tokens', -1), full.get('total_ms', -1)))
    if args.out:
        with open(args.out, 'w', encoding='utf-8') as stream:
            json.dump({'rows': rows, 'timings': timings,
                       'calibration': {'temperature': temperature, 'min_confidence': threshold}},
                      stream, indent=2)
        print('\nwrote %s' % args.out)


if __name__ == '__main__':
    main()
