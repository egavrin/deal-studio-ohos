#!/usr/bin/env python3
"""
Picks up to 500 sdk-index entries that tools/generate-sdk-backend.py can turn
into a real VeraSdkBackend.ets adapter without a human reading each one's
actual signature -- the same reasoning as everything upstream of this: only
a namespace-level function is callable as `import X from '...'; X.name(...)`
without first constructing an instance (a `class` or `interface` member
needs one, and how -- a context? a factory call? -- isn't something a script
can read off the declaration generically), and only a small, simple set of
parameter and return types can be marshalled to and from sdk.call's plain
name/value strings without knowing what the type actually means (an enum's
member names, an object's shape).

Counted directly against tools/sdk-index.json on this checkout: strictly
zero-argument, primitive-returning namespace functions number only 165 --
not enough for 500. Broadened to up to 2 simple-typed parameters and a
primitive or void return (sync or wrapped in Promise<...>), the pool is
1,036, spread across every kit. This script selects from that pool, capping
per kit so a couple of large kits (ConnectivityKit, TelephonyKit) don't
crowd out everything else, and ranking by how likely a person is to
recognise the capability from its own description -- a soft signal, not a
guarantee, which is exactly why the output is a document to review rather
than something applied silently.

Usage:
    python3 tools/select-sdk-backend-candidates.py \
        --index entry/src/main/resources/rawfile/sdk-index.json \
        --out-json tools/sdk-backend-selected.json \
        --out-doc docs/sdk-backend-500.md \
        --limit 500
"""

import argparse
import json
import re
import sys
from collections import Counter, defaultdict

SIMPLE_PARAM_TYPES = {'string', 'number', 'int', 'long', 'double', 'boolean', 'bigint'}
PRIMITIVE_RETURNS = {'string', 'number', 'int', 'long', 'double', 'boolean', 'bigint', 'void'}
MAX_PARAMS = 2
PER_KIT_CAP = 55

# Soft ranking only: a description that mentions one of these reads as
# something a person would recognise, not an internal implementation detail.
RECOGNIZABLE_WORDS = [
    'battery', 'bluetooth', 'wifi', 'wi-fi', 'network', 'screen', 'display',
    'brightness', 'volume', 'storage', 'notification', 'location', 'gps',
    'sensor', 'camera', 'audio', 'microphone', 'orientation', 'lock',
    'unlock', 'support', 'enabled', 'disabled', 'status', 'state', 'airplane',
    'nfc', 'vibrat', 'flashlight', 'torch', 'charge', 'charging', 'signal',
    'roaming', 'call', 'sms', 'message', 'contact', 'calendar', 'alarm',
    'clock', 'timer', 'app', 'device', 'memory', 'cpu', 'temperature',
]


def split_params(params_text):
    """['name: type', 'name2?: type2'] from the raw joined param text, aware
    of nested <>/()/[] so a generic type's own commas don't split early."""
    if params_text.strip() == '':
        return []
    parts = []
    depth = 0
    cur = ''
    for ch in params_text:
        if ch == ',' and depth == 0:
            parts.append(cur)
            cur = ''
            continue
        if ch in '<([{':
            depth += 1
        if ch in '>)]}':
            depth -= 1
        cur += ch
    if cur.strip():
        parts.append(cur)
    return [p.strip() for p in parts]


def param_info(params_text):
    """(ok, [(name, type, optional), ...]) -- ok is False the moment one
    parameter isn't a simple type this script knows how to coerce."""
    parts = split_params(params_text)
    if len(parts) > MAX_PARAMS:
        return False, []
    if 'callback' in params_text.lower():
        return False, []
    out = []
    for p in parts:
        if ':' not in p:
            return False, []
        name, _, rest = p.partition(':')
        name = name.strip()
        optional = name.endswith('?')
        name = name.rstrip('?').strip()
        t = rest.split('=')[0].strip().rstrip('?').strip()
        if t not in SIMPLE_PARAM_TYPES:
            return False, []
        out.append((name, t, optional))
    return True, out


def return_info(return_type):
    """(ok, base_type, is_promise)."""
    rt = return_type.strip()
    if rt.startswith('Promise<') and rt.endswith('>'):
        inner = rt[len('Promise<'):-1].strip()
        return inner in PRIMITIVE_RETURNS, inner, True
    return rt in PRIMITIVE_RETURNS, rt, False


GRANTED_PERMISSIONS = (
    'ohos.permission.INTERNET',
    'ohos.permission.EXECUTE_INSIGHT_INTENT',
    'ohos.permission.START_INVISIBLE_ABILITY',
    'ohos.permission.ABILITY_BACKGROUND_COMMUNICATION',
    'ohos.permission.GET_BUNDLE_INFO_PRIVILEGED',
    'ohos.permission.STORAGE_MANAGER',
    # Added to reach 500 candidates: without these, only ~443 targets pass
    # every other filter, and none of them are WiFi, telephony or
    # notifications -- exactly the capabilities a person would recognise.
    # ACCESS_BLUETOOTH was tried too and dropped: unlike the rest, it's a
    # user_grant permission (confirmed against hvigor's own
    # userGrantPermissions.json, and the real build failure --
    # "reason and usedScene attributes are mandatory for user_grant
    # permissions" -- said so directly), so it needs a runtime request and
    # string-resource reason like READ_CALENDAR/WRITE_CALENDAR already do,
    # which is a real feature to add, not something a bulk selection script
    # should grant itself. The other six below really are system_grant.
    'ohos.permission.GET_WIFI_INFO',
    'ohos.permission.SET_WIFI_INFO',
    'ohos.permission.GET_TELEPHONY_STATE',
    'ohos.permission.SET_TELEPHONY_STATE',
    'ohos.permission.NOTIFICATION_CONTROLLER',
    'ohos.permission.GET_NETWORK_INFO',
)


def already_granted_permission(permission_text):
    """Empty, or already covered by one of the six permissions this app's
    manifest and signing profile carry -- see module.json5's own comment for
    why a seventh can't be added silently by a bulk script. Substring match
    because the JSDoc text sometimes trails a version note, e.g.
    "ohos.permission.STORAGE_MANAGER [since 10 - 14]"."""
    text = permission_text.strip()
    if text == '':
        return True
    return any(p in text for p in GRANTED_PERMISSIONS)


def recognizability_score(entry):
    text = (entry['name'] + ' ' + entry['description']).lower()
    return sum(1 for w in RECOGNIZABLE_WORDS if w in text)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--index', default='entry/src/main/resources/rawfile/sdk-index.json')
    ap.add_argument('--out-json', default='tools/sdk-backend-selected.json')
    ap.add_argument('--out-doc', default='docs/sdk-backend-500.md')
    ap.add_argument('--limit', type=int, default=500)
    ap.add_argument('--exclude', default='',
                     help='comma-separated kit.module.name targets to always skip '
                          '(fed back in by generate/build iteration when one fails to compile)')
    args = ap.parse_args()

    excluded = set(t.strip() for t in args.exclude.split(',') if t.strip())
    data = json.load(open(args.index, encoding='utf-8'))

    candidates = []
    for e in data:
        if e.get('scopeKind') != 'namespace':
            continue
        if e['deprecated']:
            continue
        if not already_granted_permission(e.get('permission', '')):
            continue
        ok_params, params = param_info(e['params'])
        if not ok_params:
            continue
        ok_return, base_return, is_promise = return_info(e['returnType'])
        if not ok_return:
            continue
        target = e['kit'] + '.' + e['module'] + '.' + e['name']
        if target in excluded:
            continue
        candidates.append({
            'target': target,
            'kit': e['kit'],
            'module': e['module'],
            'name': e['name'],
            'file': e['file'],
            'params': params,          # [(name, type, optional), ...]
            'returnType': base_return,
            'isPromise': is_promise,
            'description': e['description'],
            'score': recognizability_score(e),
        })

    print(f'{len(candidates)} candidates after filtering (namespace-level, '
          f'<= {MAX_PARAMS} simple params, primitive/void return, no new permission, '
          f'not deprecated)', file=sys.stderr)

    # An overloaded function (same kit.module.name, different signatures)
    # produces one candidate per overload here, but the generator's ADAPTERS
    # map has room for exactly one entry per target string -- a duplicate key
    # would just silently lose one overload when the map literal is built.
    # Keep the simplest overload (fewest parameters; ties broken by which one
    # was scanned first, so re-running is stable).
    by_target = {}
    for c in candidates:
        prev = by_target.get(c['target'])
        if prev is None or len(c['params']) < len(prev['params']):
            by_target[c['target']] = c
    if len(by_target) != len(candidates):
        print(f'{len(candidates) - len(by_target)} overload duplicates '
              f'collapsed to their simplest signature', file=sys.stderr)
    candidates = list(by_target.values())

    # Highest recognisability first; stable tie-break by target so re-running
    # with a few --exclude entries doesn't reshuffle everything else.
    candidates.sort(key=lambda c: (-c['score'], c['target']))

    per_kit = Counter()
    selected = []
    for c in candidates:
        if len(selected) >= args.limit:
            break
        if per_kit[c['kit']] >= PER_KIT_CAP:
            continue
        per_kit[c['kit']] += 1
        selected.append(c)

    with open(args.out_json, 'w', encoding='utf-8') as f:
        json.dump(selected, f, indent=1)

    by_kit = defaultdict(list)
    for c in selected:
        by_kit[c['kit']].append(c)

    lines = [
        f'# {len(selected)} real sdk.call targets',
        '',
        f'Selected by `tools/select-sdk-backend-candidates.py` from '
        f'{len(candidates)} candidates that a generator can safely turn into a '
        f'real backend call: a namespace-level function (not a class/interface '
        f'method needing an instance), at most {MAX_PARAMS} simple-typed '
        f'parameters, a primitive or void return. Implemented by '
        f'`tools/generate-sdk-backend.py` into `VeraSdkBackend.ets`.',
        '',
        f'**{len(selected)} selected**, across {len(by_kit)} kits.',
        '',
    ]
    for kit in sorted(by_kit, key=lambda k: -len(by_kit[k])):
        entries = by_kit[kit]
        lines.append(f'## {kit} ({len(entries)})')
        lines.append('')
        for c in sorted(entries, key=lambda c: c['name']):
            param_str = ', '.join(f'{n}: {t}' + ('?' if opt else '')
                                   for n, t, opt in c['params'])
            ret = ('Promise<' + c['returnType'] + '>') if c['isPromise'] else c['returnType']
            desc = c['description'] or '(no description)'
            lines.append(f'- `{c["target"]}({param_str}): {ret}` -- {desc}')
        lines.append('')

    with open(args.out_doc, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))

    print(f'selected {len(selected)} across {len(by_kit)} kits', file=sys.stderr)
    print(f'wrote {args.out_json} and {args.out_doc}', file=sys.stderr)


if __name__ == '__main__':
    main()
