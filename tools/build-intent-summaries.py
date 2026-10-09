#!/usr/bin/env python3
"""
Writes a one-to-two sentence plain-language summary for every intent the phone
can call, so intent search can match what a person wants ("play some music",
"turn on do-not-disturb") instead of an intent name read as English.

Inputs, neither of which lives in this repository (see tools/intent-import.py):
  --db       insight_intent.db pulled from the phone: which intents exist.
  --celia    a directory holding insight_intent_tools.json and
             insight_intent_execute_map.json from the assistant's own HAP
             (/system/app/HwHmosVAssistant/HwHmosSystemAgent.hap,
             resources/rawfile/): what a call does, in Chinese, and what its
             parameters mean.

The celia text is proprietary and is only a lead. It is handed to the model as
facts to be put in our own words, never copied: the model is told to write
fresh English, and what comes out is ours. An intent celia does not know gets
a summary written from its name alone, marked source "name" so it can be
audited (and trusted less) separately.

Output: { "bundle/IntentName": {"summary": "...", "source": "celia"|"name"} }.
The key is bundle/intentName, the same key VeraIntentIndex builds at run time.
Rerunning skips what is done; the API key is read from a file (default
~/.deepseek-key), never from the command line, and never printed.

Usage:
    python3 tools/build-intent-summaries.py --db ~/work/celia/insight_intent.db \\
        --celia ~/work/celia/rawfile --out tools/intent-summaries.json --pilot 40
"""

import argparse
import importlib.util
import json
import random
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


imp = load('intent_import', 'intent-import.py')      # load_device, load_celia
sums = load('build_sdk_summaries', 'build-sdk-summaries.py')  # read_key, Meter, peak_now

BASE_URL = 'https://api.deepseek.com'
MODEL = 'deepseek-flash'

SYSTEM = """You write search-index summaries of phone intents: small actions that an installed app exposes, such as "set a timer" or "open a music search page". The index is searched with what a person wants to do, in everyday words, so a summary must be findable by that wish.

For each intent write ONE or TWO plain sentences, at most 40 words:
 - first what calling it does, in plain English, naming the app by what it is ("the Music app", "phone settings") when that helps;
 - then what someone would ask for to want this, in everyday words ("play a song", "turn on Bluetooth", "set an alarm").
Rules:
 - Write fresh English in your own words. Never translate the supplied text sentence by sentence and never quote it; it is a lead to what the intent does, not text to reuse.
 - Only say what the supplied facts support. If an intent has "facts: none", you only have its name and its app's bundle name: say what the name most plausibly means, briefly, and do not invent parameters, values or side effects.
 - When parameters take a closed set of values, you may mention what they choose between, in plain words.
 - Do not mention bundle names, ability names, API names, modes or version numbers. Do not start with "This intent".

Reply with one JSON object mapping each given key to its summary string, and nothing else."""


def flat_params(parameters):
    """Parameter name -> {what it is (celia's words), type, closed set} from a tool's JSON schema."""
    out = []
    props = (parameters or {}).get('properties') or {}
    for name, schema in props.items():
        if not isinstance(schema, dict):
            continue
        row = {'name': name.strip().rstrip(':'), 'about': schema.get('description', ''),
               'type': schema.get('type', '')}
        enum = [v for v in schema.get('enum', []) if isinstance(v, (str, int))]
        if enum:
            row['values'] = enum
        out.append(row)
    return out


def collect(db_path, celia_dir):
    """key -> brief for every intent the phone can call from a UIAbility."""
    device = imp.load_device(db_path)
    tools, execute_map = imp.load_celia(celia_dir)
    by_intent = defaultdict(list)
    for tool_name, entry in execute_map.items():
        tool = tools.get(tool_name)
        bundle = entry.get('bundleName', '')
        if tool is None or bundle.startswith('${'):
            continue
        by_intent[(bundle, entry.get('insightIntentName', ''))].append((tool, entry))
    briefs = {}
    for (bundle, intent), records in sorted(device.items()):
        if not any(r['uiAbility']['ability'] for r in records):
            continue  # an extension, which insightIntentDriver.execute as we call it cannot reach
        brief = {'intent': intent, 'bundle': bundle}
        declared = records[0].get('parameters')
        if isinstance(declared, dict) and declared:
            brief['declared_parameters'] = sorted(declared)
        celia = []
        for tool, entry in by_intent.get((bundle, intent), []):
            fixed = {k: v for k, v in (entry.get('intentParam') or {}).items()
                     if isinstance(v, str) and not v.startswith('${')} if isinstance(entry.get('intentParam'), dict) else {}
            celia.append({'description': tool.get('description', ''),
                          'parameters': flat_params(tool.get('parameters')),
                          'always_sends': fixed})
        brief['facts'] = celia if celia else 'none'
        brief['source'] = 'celia' if celia else 'name'
        briefs[f'{bundle}/{intent}'] = brief
    return briefs


def ask(key, batch, meter, timeout=120):
    items = {k: {f: v for f, v in b.items() if f != 'source'} for k, b in batch}
    body = json.dumps({
        'model': MODEL, 'temperature': 0.2, 'max_tokens': 4096, 'stream': False,
        'thinking': {'type': 'disabled'},
        'response_format': {'type': 'json_object'},
        'messages': [{'role': 'system', 'content': SYSTEM},
                     {'role': 'user', 'content': 'Intents (JSON):\n' + json.dumps(items, indent=0, ensure_ascii=False)}],
    }).encode()
    req = urllib.request.Request(BASE_URL + '/chat/completions', data=body, headers={
        'Content-Type': 'application/json', 'Authorization': 'Bearer ' + key})
    last = ''
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                data = json.load(r)
            meter.add(data.get('usage', {}))
            got = json.loads(data['choices'][0]['message']['content'])
            sources = dict(batch)
            return {k: {'summary': v.strip(), 'source': sources[k]['source']}
                    for k, v in got.items() if k in sources and isinstance(v, str) and v.strip()}
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
    ap.add_argument('--out', required=True, type=Path)
    ap.add_argument('--key-file', default='~/.deepseek-key')
    ap.add_argument('--pilot', type=int, default=0, help='only this many intents (seeded sample, half with celia facts)')
    ap.add_argument('--batch', type=int, default=8)
    ap.add_argument('--workers', type=int, default=8)
    ap.add_argument('--seed', type=int, default=1)
    ap.add_argument('--dry-run', type=int, default=0, metavar='N', help='print N briefs and stop; no key read, no request')
    args = ap.parse_args()

    briefs = collect(args.db.expanduser(), args.celia.expanduser())
    n_celia = sum(1 for b in briefs.values() if b['source'] == 'celia')
    print(f'{len(briefs)} callable intents, {n_celia} with celia facts, {len(briefs) - n_celia} name only', file=sys.stderr)

    if args.pilot:
        rng = random.Random(args.seed)
        with_c = sorted(k for k, b in briefs.items() if b['source'] == 'celia')
        without = sorted(k for k, b in briefs.items() if b['source'] == 'name')
        rng.shuffle(with_c); rng.shuffle(without)
        keep = with_c[:args.pilot // 2] + without[:args.pilot - args.pilot // 2]
        briefs = {k: briefs[k] for k in keep}
    if args.dry_run:
        for k in list(briefs)[:args.dry_run]:
            print(k); print(json.dumps(briefs[k], indent=1, ensure_ascii=False)); print()
        return 0

    done = json.loads(args.out.read_text()) if args.out.exists() else {}
    todo = {k: b for k, b in briefs.items() if k not in done}
    print(f'{len(done)} already done, {len(todo)} to do', file=sys.stderr)
    if not todo:
        return 0
    key = sums.read_key(args.key_file)
    meter = sums.Meter()
    items = sorted(todo.items())
    batches = [items[i:i + args.batch] for i in range(0, len(items), args.batch)]
    started = time.time()
    with ThreadPoolExecutor(args.workers) as pool:
        futures = [pool.submit(ask, key, b, meter) for b in batches]
        for n, f in enumerate(as_completed(futures), 1):
            done.update(f.result())
            args.out.parent.mkdir(parents=True, exist_ok=True)
            args.out.write_text(json.dumps(done, indent=0, ensure_ascii=False, sort_keys=True))
            print(f'{n}/{len(futures)} batches, {len(done)} summaries, ~${meter.cost():.4f}, {time.time() - started:.0f}s', file=sys.stderr)
    print(f'calls={meter.calls} failed_batches={meter.failed} est_cost=${meter.cost():.4f} '
          f'missing={sum(1 for k, _ in items if k not in done)}', file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
