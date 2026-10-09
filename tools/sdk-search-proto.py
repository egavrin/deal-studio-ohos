#!/usr/bin/env python3
"""
A throwaway prototype of `find_sdk_function`'s scoring, to tune weights
against tools/sdk-index.json (16,511 real entries) before porting the
validated logic to ArkTS as VeraSdkIndex.ets. Not shipped, not imported by
anything -- delete once Phase 2 is ported and checked on the host under node
per CLAUDE.md's "Checking things without a device".

Scoring: a word of the query (lowercased, split on non-alphanumeric, length
>= 3) is matched as a WHOLE TOKEN, not a raw substring, against name/module
(camelCase-split: "setTorchMode" -> {set, torch, mode}) and description
(split on non-alphanumeric). Whole-token matching, not weight tuning, is the
load-bearing fix here: substring matching was tried first and let "turn"
match inside "reTURN" for every entry whose description happens to say
"uses a promise to return the result" (nearly all of them) -- the exact
false-positive class docs/prompts/intent-coverage.md already documents for
the intent registry ("came" matching "camera"). Exact-token matching against
name/module is weighted above description, plus a bonus if a query word
matches the kit name. A small penalty for @deprecated entries breaks ties in
favour of the current API without excluding the deprecated one outright.

Usage:
    python3 tools/sdk-search-proto.py "add an event to the calendar"
    python3 tools/sdk-search-proto.py "toggle bluetooth" -k 10
"""

import argparse
import json
import re

W_NAME = 3
W_MODULE = 2
W_DESCRIPTION = 1
KIT_BONUS = 2
DEPRECATED_PENALTY = 1
MIN_WORD_LEN = 3

# A length cutoff alone doesn't work at 3: "the" is exactly 3 characters and
# swamps every description the way "setting"/"switch" already do to the
# intent registry at length 7+ (docs/prompts/intent-coverage.md). What's
# actually wanted is short *verbs* (add/get/set/put/run/use), which this
# API's naming is full of -- so filter grammatical filler explicitly instead
# of raising the length bar back to 4 and losing "add" again.
STOPWORDS = frozenset('''
the and for are was her its but not you all can has had out who why how did
does own too any may say she his him our per via with from that this have
been were they them what when then than into onto over will would could
should about
'''.split())

CAMEL_RE = re.compile(r'[A-Z]+(?=[A-Z][a-z])|[A-Z]?[a-z0-9]+|[A-Z]+')


def words(text):
    """Query words: lowercase, split on non-alphanumeric, length >= 3 and not
    a stopword."""
    cleaned = re.sub(r'[^a-z0-9]+', ' ', text.lower())
    return [w for w in cleaned.split(' ')
            if len(w) >= MIN_WORD_LEN and w not in STOPWORDS]


def identifier_tokens(name):
    """camelCase/PascalCase -> whole lowercase words: "setTorchMode" ->
    {set, torch, mode}. Whole tokens, not substrings, so "turn" never matches
    inside "Return"."""
    return {t.lower() for t in CAMEL_RE.findall(name)}


def prose_tokens(text):
    return {w for w in re.split(r'[^a-zA-Z0-9]+', text.lower()) if w}


def score(entry, need_words, kit_words, name_tokens, module_tokens, desc_tokens):
    s = 0
    for w in need_words:
        if w in name_tokens:
            s += W_NAME
        if w in module_tokens:
            s += W_MODULE
        if w in desc_tokens:
            s += W_DESCRIPTION
    kit = entry['kit'].lower()
    for w in kit_words:
        if w in kit or kit in w:
            s += KIT_BONUS
            break
    if entry['deprecated']:
        s -= DEPRECATED_PENALTY
    return s


def find_sdk_function(index, need, limit=8):
    need_words = words(need)
    scored = []
    for e in index:
        name_tokens = identifier_tokens(e['name'])
        module_tokens = identifier_tokens(e['module'])
        desc_tokens = prose_tokens(e['description'])
        s = score(e, need_words, need_words, name_tokens, module_tokens, desc_tokens)
        if s > 0:
            scored.append((s, e))
    scored.sort(key=lambda t: (-t[0], t[1]['kit'], t[1]['module'], t[1]['name']))
    return scored[:limit]


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('need')
    ap.add_argument('-k', '--limit', type=int, default=8)
    ap.add_argument('--index', default='entry/src/main/resources/rawfile/sdk-index.json')
    args = ap.parse_args()

    index = json.load(open(args.index, encoding='utf-8'))
    results = find_sdk_function(index, args.need, args.limit)
    print(f'need: {args.need!r}  ({len(index)} candidates scanned)')
    print()
    for s, e in results:
        flag = ' [deprecated]' if e['deprecated'] else ''
        print(f'{s:3d}  {e["kit"]}.{e["module"]}.{e["name"]}{flag}')
        print(f'      ({e["params"][:80]}) -> {e["returnType"]}')
        print(f'      {e["description"][:100]}')
        print()


if __name__ == '__main__':
    main()
