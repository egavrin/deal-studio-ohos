#!/usr/bin/env python3
"""
Turns the phone's own intent metadata into a worklist of catalogue candidates.

Nothing here edits VeraIntentCatalog.ets. A row enters the catalogue by hand,
after a person has read the contract and called the intent on a phone, because
a declaration is not a behaviour: the platform validates no parameters and a
result code of 0 is chosen by the target's developer. See docs/intents-design.md.

Two inputs, neither of which lives in this repository:

  $INTENT_DB       insight_intent.db pulled from the device. The registry the
                   OS itself keeps: what is installed, where to send it, in
                   which execute modes, at which versionCode.
  $CELIA_RAWFILES  a directory holding insight_intent_tools.json and
                   insight_intent_execute_map.json, unpacked by the operator
                   from the assistant's own HAP. This is where contracts come
                   from -- parameter names, constants, enum values -- because
                   only 13 of the 747 intents the device declares describe
                   their parameters at all.

                   It is proprietary firmware. Parameter names and values are
                   facts about the interface and are used as leads to probe;
                   its descriptions are not copied, and no file from it is
                   committed here. Summaries in the catalogue are written in
                   English, by us.

Usage:
    INTENT_DB=~/Desktop/hdc/insight_intent.db CELIA_RAWFILES=~/work/celia/rawfile \\
        python3 tools/intent-import.py --out /tmp/intent-candidates [--classify]

--classify sends each candidate to Jev (TypeSafe's System One model) for its
risk class and domain. Without it, the same fields are filled by the verb and
target rules below, which are cruder and never promote a row to a safer class.
"""

import argparse
import json
import os
import re
import sqlite3
import sys
from pathlib import Path

# ---------------------------------------------------------------- rules

# The verb an intent name starts with suggests what calling it does. It only
# suggests: the target decides the class as much as the verb does, which is why
# BUNDLE_CRITICAL below can raise a row and nothing can lower one.
VERB_RISK = [
    (r'^(Get|Check|Query|Load|Is|Search|Read|View|Detect)', 'read'),
    (r'^(Open|Jump|Enter|Entry|Display|Show|Redirect|Navigate|Preview)', 'navigate'),
    (r'^(Pay|Cashier|Recharge|Send|Share|Call|Delete|Remove|Clear|Reset|Restore|'
     r'Unlock|Lock|Disconnect|End|Cancel|Agree|Encrypted)', 'critical'),
]

# Targets where even a Set or a Get is critical: money, other people, the
# phone's own defences, and anything a parent set up for a child.
BUNDLE_CRITICAL = re.compile(
    r'(payment|wallet|parentcontrol|privacycenter|spamshield|advsecmode|applock|'
    r'dlpcredmgr|callsetting|simcardmanagement|meetimeservice|contacts|mms|instantshare)')

DOMAIN_BY_BUNDLE = [
    (r'maps|amap|navi', 'maps'),
    (r'calendar', 'calendar'),
    (r'clock', 'clock'),
    (r'music', 'music'),
    (r'notepad|aidataservice', 'notes'),
    (r'photos|gallery|camera', 'photos'),
    (r'settings|batterycare|audioaccessorymanager|communicationsetting', 'settings'),
    (r'meetimeservice|mms|contacts', 'messaging'),
    (r'payment|wallet', 'money'),
]

RISK_ORDER = {'read': 0, 'navigate': 1, 'act': 2, 'critical': 3}


def rule_risk(bundle: str, intent: str) -> str:
    risk = 'act'
    for pattern, value in VERB_RISK:
        if re.match(pattern, intent):
            risk = value
            break
    if BUNDLE_CRITICAL.search(bundle):
        risk = 'critical'
    return risk


def rule_domain(bundle: str) -> str:
    for pattern, value in DOMAIN_BY_BUNDLE:
        if re.search(pattern, bundle):
            return value
    return 'system'


# ---------------------------------------------------------------- inputs

def load_device(db_path: Path) -> dict:
    """Every intent the phone has, keyed by (bundle, intentName)."""
    rows = {}
    with sqlite3.connect(f'file:{db_path}?mode=ro', uri=True) as db:
        for key, value in db.execute('select INTENT_KEY, INTENT_VALUE from insight_intent_table'):
            record = json.loads(value)
            version = key.rsplit('/', 1)[-1]
            for intent in record.get('insightIntents', []):
                intent['versionCode'] = version
                rows.setdefault((intent['bundleName'], intent['intentName']), []).append(intent)
    return rows


def load_celia(raw: Path):
    tools = {t['name']: t for t in json.loads((raw / 'insight_intent_tools.json').read_text())['tools']}
    execute_map = json.loads((raw / 'insight_intent_execute_map.json').read_text())
    return tools, execute_map


# ---------------------------------------------------------------- the funnel

def candidates(tools: dict, execute_map: dict, device: dict):
    """
    Everything we cannot use, dropped with a reason, so the shape of the gap is
    visible rather than guessed. On the phone this was written against: 337 not
    installed, 111 dynamic bundle, 60 object/array parameters, 58 extension
    only, 1 conditional template, 276 left.
    """
    kept, dropped = [], {}

    def drop(reason):
        dropped[reason] = dropped.get(reason, 0) + 1

    for name, tool in tools.items():
        entry = execute_map.get(name)
        if entry is None:
            drop('no execute map entry')
            continue
        bundle = entry.get('bundleName', '')
        if bundle.startswith('${'):
            # The assistant lets its model choose the app. We do not: a row
            # names one target, probed once.
            drop('dynamic bundle')
            continue
        records = device.get((bundle, entry['insightIntentName']))
        if not records:
            drop('not installed here')
            continue
        record = next((r for r in records if r['uiAbility']['ability']), None)
        if record is None:
            # Service and UI extensions: insightIntentDriver.execute as we call
            # it goes to a UIAbility, so these are out of reach for now.
            drop('no UIAbility')
            continue
        template = entry.get('intentParam') or {}
        if not isinstance(template, dict):
            # A handful of rows template the whole payload as one string. There
            # is no key-by-key contract to read out of that.
            drop('payload is one template string')
            continue
        rendered = json.dumps(template, ensure_ascii=False)
        if '?' in rendered and '${' in rendered:
            drop('conditional template')
            continue
        properties = (tool.get('parameters') or {}).get('properties') or {}
        if any(p.get('type') in ('object', 'array') for p in properties.values()):
            # The language holds a flat record of scalars. An object parameter
            # can still be reached, one field per leaf through a dotted
            # platformName, but that is a row written by hand, not imported.
            drop('object or array parameter')
            continue
        kept.append(build(name, tool, entry, record, template, properties))
    return kept, dropped


def build(name, tool, entry, record, template, properties):
    """One candidate: where to send it, what it takes, what is constant."""
    fixed, params = {}, []
    for platform_name, value in template.items():
        if not isinstance(value, str):
            continue
        match = re.fullmatch(r'\$\{([\w.]+)(?:\|([^}]*))?\}', value)
        if match is None:
            # No placeholder: the assistant always sends this exact value, and
            # it is usually what makes the row specific -- itemName "bluetooth".
            fixed[platform_name] = value
            continue
        field, default = match.group(1), match.group(2) or ''
        schema = properties.get(field, {})
        params.append({
            'name': field,
            'platformName': platform_name,
            'kind': 'int' if schema.get('type') == 'integer' else 'string',
            'values': [v for v in schema.get('enum', []) if isinstance(v, str)],
            'defaultValue': default,
        })
    # A parameter the schema declares but the template never places still
    # travels under its own name: the assistant passes such payloads through.
    placed = {p['name'] for p in params}
    for field, schema in properties.items():
        if field in placed:
            continue
        params.append({
            'name': field,
            'platformName': field,
            'kind': 'int' if schema.get('type') == 'integer' else 'string',
            'values': [v for v in schema.get('enum', []) if isinstance(v, str)],
            'defaultValue': '',
        })
    bundle = entry['bundleName']
    # The assistant's mode is a preference; the device's list is the law. Asking
    # for a mode the target does not declare is refused by the framework before
    # the target ever sees the call, so the declared list wins, and background
    # wins inside it -- coming to the front is for what the person should look at.
    declared = record['uiAbility']['executeMode']
    wanted = entry.get('executeMode') or ''
    if wanted in declared:
        mode = wanted
    elif 'background' in declared:
        mode = 'background'
    else:
        mode = declared[0]
    return {
        'tool': name,
        'bundle': bundle,
        'module': record['moduleName'],
        'ability': record['uiAbility']['ability'],
        'intentName': entry['insightIntentName'],
        'mode': mode,
        'modeAsked': wanted,
        'modesDeclared': declared,
        'versionCode': record['versionCode'],
        'fixed': fixed,
        'params': params,
        'risk': rule_risk(bundle, entry['insightIntentName']),
        'domain': rule_domain(bundle),
        'source': 'rules',
    }


# ---------------------------------------------------------------- Jev

def classify(rows, model='jev-latest'):
    """
    Risk and domain for each candidate, from Jev.

    A typed decision is exactly what this step needs: the answer cannot fall
    outside the set, and it carries a confidence, so the person reads the
    uncertain rows instead of classifying every one from scratch. Jev never
    makes a row safer than the rules did -- disagreement in that direction is
    recorded and flagged, not applied.
    """
    try:
        from typesafe import Jev, Choice, Noul  # typesafe-sdk
    except ImportError:
        sys.exit('--classify needs the TypeSafe SDK: pip install typesafe-sdk')
    if not os.environ.get('TYPESAFE_API_KEY'):
        sys.exit('--classify needs TYPESAFE_API_KEY in the environment')

    jev = Jev(model=model)
    questions = {
        'risk': Choice(
            'How much can one call of this change?',
            criteria={
                'read': 'reads or displays something, changes nothing',
                'navigate': 'opens a page or an app, changes no data',
                'act': 'changes a setting or creates something the user can undo',
                'critical': 'money, a message or call to another person, deleting '
                            'user data, permissions, security, parental control',
                'other': 'none of these',
            }),
        'domain': Choice(
            'Which part of the phone is this about?',
            criteria={d: d for d in ['maps', 'calendar', 'clock', 'music', 'notes',
                                     'photos', 'settings', 'messaging', 'money', 'system']}
            | {'other': 'none of these'}),
        'changes_state': Noul('Does one call change something on the phone?'),
        'needs_account': Noul('Does it need the user signed in to a cloud account?'),
        'reversible': Noul('Can the user undo the effect afterwards?'),
    }

    for row in rows:
        state = {
            'app': row['bundle'],
            'intent': row['intentName'],
            'tool': row['tool'],
            'constant_parameters': row['fixed'],
            'parameters': [{'name': p['name'], 'values': p['values']} for p in row['params']],
        }
        answer = jev.decide(state=state, questions=questions)
        jev_risk = answer['risk'].value
        if jev_risk not in RISK_ORDER:
            jev_risk = row['risk']
        row['jev'] = {
            'risk': jev_risk,
            'risk_confidence': answer['risk'].confidence,
            'domain': answer['domain'].value,
            'changes_state': answer['changes_state'].probability,
            'needs_account': answer['needs_account'].probability,
            'reversible': answer['reversible'].probability,
        }
        # Strictest wins, whoever said it.
        row['risk'] = max(row['risk'], jev_risk, key=lambda r: RISK_ORDER[r])
        if answer['domain'].value != 'other':
            row['domain'] = answer['domain'].value
        row['source'] = 'jev+rules'
        row['review'] = review_reason(row, answer, jev_risk)
    return rows


def review_reason(row, answer, jev_risk):
    """Why a person should look at this row before it is trusted."""
    if answer['risk'].confidence < 0.7:
        return 'low confidence on risk'
    if jev_risk != row['risk']:
        return 'Jev and the rules disagree on risk'
    if answer['changes_state'].probability > 0.5 and row['risk'] == 'read':
        return 'called read, but said to change state'
    return ''


# ---------------------------------------------------------------- output

def arkts(row):
    """A paste-ready row, with what is still missing marked as TODO."""
    def literal(values):
        return '[' + ', '.join(f"'{v}'" for v in values) + ']'

    params = []
    for p in row['params']:
        values = literal(p['values'])
        default = f", '{p['defaultValue']}'" if p['defaultValue'] else ''
        params.append(
            f"    new IntentParam('{p['name']}', '{p['kind']}', '{p['platformName']}', {values},\n"
            f"      new Map<string, string>(), 'TODO: what this field is'{default})")
    fixed = ', '.join(f"['{k}', '{v}']" for k, v in row['fixed'].items())
    name = row['tool'][0].lower() + row['tool'][1:]
    return (
        f"  // TODO: where the contract came from, what the probe showed, and what the\n"
        f"  // target ignored. Declared modes: {row['modesDeclared']}, versionCode {row['versionCode']}.\n"
        f"  new IntentSpec('{name}', '{row['tool'][0].upper() + row['tool'][1:]}Params',\n"
        f"    '{row['bundle']}', '{row['module']}', '{row['ability']}', '{row['intentName']}',\n"
        f"    [\n" + ',\n'.join(params) + "\n    ],\n"
        f"    'TODO: one line for the prompt', 'schema', '{row['mode']}', 'intent',\n"
        f"    new Map<string, string>([{fixed}]),\n"
        f"    '{row['risk']}', '{row['domain']}', 'TODO: the line a person reads', "
        f"'{row['versionCode']}'),\n")


def catalog_file(rows) -> dict:
    """
    The rows in the shape the app loads from {filesDir}/vera/intent-catalog.json.

    Written outside the repository on purpose: a row here names an ability and a
    versionCode belonging to one device and one firmware, which is the
    operator's material rather than the product's. See VeraCatalogFile.ets.

    Risk travels with the row but does not buy silence: the app treats anything
    from a file as 'act' or 'critical', so a file can name an intent and phrase
    it for a person, and cannot decide that it runs without asking.
    """
    out = []
    for row in rows:
        entry = {
            'name': row['tool'][0].lower() + row['tool'][1:],
            'target': f"{row['bundle']}/{row['module']}/{row['ability']}/{row['intentName']}",
            'mode': row['mode'],
            'risk': row['risk'],
            'domain': row['domain'],
            'summary': 'TODO: one line for the prompt',
            'titleForUser': 'TODO: the line a person reads before allowing it',
            'verifiedVersion': row['versionCode'],
        }
        if row['fixed']:
            entry['fixed'] = row['fixed']
        if row['params']:
            entry['params'] = [{
                'name': p['name'],
                'platformName': p['platformName'],
                'kind': p['kind'],
                'values': p['values'],
                'defaultValue': p['defaultValue'],
                'summary': 'TODO: what this field is',
            } for p in row['params']]
        out.append(entry)
    return {'rows': out}


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--out', default='intent-candidates',
                        help='directory for the candidate list and the ArkTS stubs')
    parser.add_argument('--classify', action='store_true', help='ask Jev for risk and domain')
    parser.add_argument('--domain', help='keep only this domain')
    parser.add_argument('--max-risk', default='critical',
                        choices=list(RISK_ORDER), help='drop rows riskier than this')
    args = parser.parse_args()

    db_path = Path(os.path.expanduser(os.environ.get('INTENT_DB', '')))
    raw = Path(os.path.expanduser(os.environ.get('CELIA_RAWFILES', '')))
    if not db_path.is_file():
        sys.exit('set INTENT_DB to insight_intent.db pulled from the phone')
    if not (raw / 'insight_intent_tools.json').is_file():
        sys.exit('set CELIA_RAWFILES to the directory holding the two rawfile JSONs')

    device = load_device(db_path)
    tools, execute_map = load_celia(raw)
    rows, dropped = candidates(tools, execute_map, device)

    print(f'{len(tools)} tools, {sum(len(v) for v in device.values())} intents on the phone')
    for reason, count in sorted(dropped.items(), key=lambda kv: -kv[1]):
        print(f'  dropped {count:4d}  {reason}')
    print(f'  usable  {len(rows):4d}')

    if args.classify:
        rows = classify(rows)
    if args.domain:
        rows = [r for r in rows if r['domain'] == args.domain]
    rows = [r for r in rows if RISK_ORDER[r['risk']] <= RISK_ORDER[args.max_risk]]
    rows.sort(key=lambda r: (r['domain'], r['bundle'], r['tool']))

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / 'intent-candidates.json').write_text(json.dumps(rows, ensure_ascii=False, indent=1))
    (out / 'rows.ets.txt').write_text('\n'.join(arkts(r) for r in rows))
    (out / 'intent-catalog.json').write_text(
        json.dumps(catalog_file(rows), ensure_ascii=False, indent=1))
    print(f'\n{len(rows)} candidates -> {out}/intent-candidates.json, rows.ets.txt, '
          f'intent-catalog.json')
    print('  the catalogue file goes to the phone, never into this repository:')
    print('    hdc file send intent-catalog.json '
          '/data/app/el2/100/base/com.vera.probe.dyn/haps/entry/files/vera/')

    by_domain = {}
    for row in rows:
        by_domain.setdefault(row['domain'], []).append(row)
    for domain, group in sorted(by_domain.items(), key=lambda kv: -len(kv[1])):
        risks = ', '.join(f'{r}:{sum(1 for g in group if g["risk"] == r)}'
                          for r in RISK_ORDER if any(g['risk'] == r for g in group))
        print(f'  {domain:10s} {len(group):3d}  ({risks})')
    review = [r for r in rows if r.get('review')]
    if review:
        print(f'\n{len(review)} rows flagged for review:')
        for row in review[:20]:
            print(f'  {row["tool"]:34s} {row["review"]}')


if __name__ == '__main__':
    main()
