#!/usr/bin/env python3
"""
Flattens tools/intent-summaries.json ({key: {summary, source}}) into the
rawfile the app reads: entry/src/main/resources/rawfile/intent-summaries.json,
{ "bundle/IntentName": "summary" }. The source flag stays here -- the phone has
no use for it -- so audits can still tell a summary written from celia's facts
from one written from a name alone.

Order: build-intent-summaries.py -> review-intent-summaries.py -> this ->
build-intent-embeddings.py (writes rawfile intent-embeddings.json from the same
summaries; rerun it whenever a summary changes).

Run after tools/build-intent-summaries.py. Which intents exist is decided on
the phone at run time (VeraIntentRegistry); this only supplies words for them.
"""
import json
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
src = root / 'tools/intent-summaries.json'
out = root / 'entry/src/main/resources/rawfile/intent-summaries.json'
rows = json.loads(src.read_text())
flat = {k: v['summary'] for k, v in sorted(rows.items())}
out.write_text(json.dumps(flat, ensure_ascii=False, indent=0, sort_keys=True))
print(f'{len(flat)} summaries -> {out.relative_to(root)}', file=sys.stderr)
