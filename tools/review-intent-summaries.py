#!/usr/bin/env python3
"""
Second pass over tools/intent-summaries.json: a reviewer model reads each
summary next to the facts it was written from (and the other intents of the
same app, so "Get...Option" and "Set...Option" families can be told apart) and
either keeps it or rewrites it.

Output goes to --out (default: rewrites tools/intent-summaries.json in place
and keeps the previous text under "previous"); each reviewed row gains
"reviewed": true. A row already reviewed is skipped, so a rerun only does the
rest. The key is read from a file (~/.deepseek-key), never printed.

Usage:
    python3 tools/review-intent-summaries.py --db ~/work/celia/insight_intent.db \\
        --celia ~/work/celia/rawfile
"""

import argparse
import importlib.util
import json
import sys
import time
import urllib.error
import urllib.request
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

HERE = Path(__file__).resolve().parent


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


gen = load('build_intent_summaries', 'build-intent-summaries.py')  # collect, BASE_URL, MODEL
sums = gen.sums

SYSTEM = """You review search-index summaries of phone intents (small actions an installed app exposes). The index is searched with what a person wants to do, in everyday words, so a summary must be findable by that wish and must be TRUE to what the intent does.

For each intent you get: its name, its app (bundle), the current summary, the facts it was written from ("facts": celia text in Chinese plus parameters, or "none" when only the name is known), and "siblings": other intent names of the same app.

Check each summary for:
 - the wrong verb: Get/Check/Query read something, Set/Change/Switch/Turn change it, View/Jump/Open/Go open a page, Delete/Remove remove, Create/Add make. A summary that says "opens" for a setter, or "gets" for a setter, is wrong.
 - invention: details the name and facts do not support (when facts are "none", say only what the name most plausibly means).
 - vagueness: "a setting", "an option", "a specific task", "the front form". If the siblings or name say what it is about, say that; if nothing does, keep it short and honest rather than padded.
 - findability: the second sentence should be what someone would actually ask for ("turn off auto-rotate", "check my battery health"). Drop filler like "Ask to use X for a specific task".
 - leaks: bundle names, ability names, API names, "this intent", copied Chinese phrasing, typos copied from the name.

Rewrite only when something above is wrong or clearly improvable; otherwise keep the text exactly. 15 to 35 words, one or two sentences, fresh English, naming the app by what it is.

Reply with one JSON object mapping each given key to {"verdict": "ok" | "fix", "summary": "<final text>", "reason": "<few words, only for fix>"}. For "ok" repeat the current summary unchanged."""


def ask(batch, meter, key, timeout=180):
    items = {k: v for k, v in batch}
    body = json.dumps({
        'model': gen.MODEL, 'temperature': 0.1, 'max_tokens': 6000, 'stream': False,
        'thinking': {'type': 'disabled'},
        'response_format': {'type': 'json_object'},
        'messages': [{'role': 'system', 'content': SYSTEM},
                     {'role': 'user', 'content': 'Intents (JSON):\n' + json.dumps(items, indent=0, ensure_ascii=False)}],
    }).encode()
    req = urllib.request.Request(gen.BASE_URL + '/chat/completions', data=body, headers={
        'Content-Type': 'application/json', 'Authorization': 'Bearer ' + key})
    last = ''
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                data = json.load(r)
            meter.add(data.get('usage', {}))
            got = json.loads(data['choices'][0]['message']['content'])
            return {k: v for k, v in got.items() if k in items and isinstance(v, dict)
                    and isinstance(v.get('summary'), str) and v['summary'].strip()}
        except urllib.error.HTTPError as e:
            last = f'HTTP {e.code}'
            if e.code in (400, 401, 402, 403):
                break
        except Exception as e:
            last = type(e).__name__
        time.sleep(2 * (attempt + 1))
    with meter.lock:
        meter.failed += 1
    print(f'  batch of {len(batch)} failed: {last}', file=sys.stderr)
    return {}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--db', required=True, type=Path)
    ap.add_argument('--celia', required=True, type=Path)
    ap.add_argument('--file', default=HERE / 'intent-summaries.json', type=Path)
    ap.add_argument('--report', default=None, type=Path, help='write a verdict log (key, verdict, old, new, reason)')
    ap.add_argument('--key-file', default='~/.deepseek-key')
    ap.add_argument('--batch', type=int, default=8)
    ap.add_argument('--workers', type=int, default=8)
    ap.add_argument('--only', default='', help='comma-separated substrings; review only keys containing one')
    ap.add_argument('--limit', type=int, default=0, help='only the first N unreviewed (for a pilot)')
    args = ap.parse_args()

    briefs = gen.collect(args.db.expanduser(), args.celia.expanduser())
    rows = json.loads(args.file.read_text())
    by_bundle = defaultdict(list)
    for k, b in briefs.items():
        by_bundle[b['bundle']].append(b['intent'])

    todo = []
    for k in sorted(rows):
        if rows[k].get('reviewed') or k not in briefs:
            continue
        if args.only and not any(o in k for o in args.only.split(',')):
            continue
        b = briefs[k]
        item = {'intent': b['intent'], 'app': b['bundle'], 'current_summary': rows[k]['summary'],
                'facts': b['facts'], 'siblings': [n for n in sorted(by_bundle[b['bundle']]) if n != b['intent']][:40]}
        if 'declared_parameters' in b:
            item['declared_parameters'] = b['declared_parameters']
        todo.append((k, item))
    if args.limit:
        todo = todo[:args.limit]
    print(f'{len(rows)} summaries, {len(todo)} to review', file=sys.stderr)
    if not todo:
        return 0

    key = sums.read_key(args.key_file)
    meter = sums.Meter()
    batches = [todo[i:i + args.batch] for i in range(0, len(todo), args.batch)]
    log = []
    started = time.time()
    with ThreadPoolExecutor(args.workers) as pool:
        futures = [pool.submit(ask, b, meter, key) for b in batches]
        for n, f in enumerate(as_completed(futures), 1):
            for k, v in f.result().items():
                row = rows[k]
                new = v['summary'].strip()
                changed = new != row['summary']
                log.append({'key': k, 'verdict': 'fix' if changed else 'ok', 'old': row['summary'],
                            'new': new, 'reason': v.get('reason', '')})
                if changed:
                    row['previous'] = row['summary']
                    row['summary'] = new
                row['reviewed'] = True
            args.file.write_text(json.dumps(rows, indent=0, ensure_ascii=False, sort_keys=True))
            print(f'{n}/{len(futures)} batches, ~${meter.cost():.4f}, {time.time() - started:.0f}s', file=sys.stderr)
    fixed = sum(1 for e in log if e['verdict'] == 'fix')
    print(f'reviewed={len(log)} changed={fixed} unchanged={len(log) - fixed} failed_batches={meter.failed} '
          f'est_cost=${meter.cost():.4f}', file=sys.stderr)
    if args.report:
        args.report.write_text(json.dumps(log, indent=1, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    sys.exit(main())
