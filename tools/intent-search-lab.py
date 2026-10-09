#!/usr/bin/env python3
"""
Does the summary help intent search? Embeds every callable intent twice -- the
text the app used before (address + "IntentName (bundle)") and the text it uses
now (IntentName + summary) -- and asks the same needs against both with the
same model, host-side, no phone. Reports hit@1/3/5 and mean reciprocal rank.

The needs are written the way the model words them to find_intent_function;
the expected answer is an intentName (any app) or a bundle/intentName.

    python3 tools/intent-search-lab.py --db ~/work/celia/insight_intent.db \\
        --model <embeddinggemma-300m-q4_k_m.gguf> \\
        --llama-embedding entry/src/main/cpp/llama.cpp/build-host/bin/llama-embedding
"""
import argparse
import importlib.util
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


imp = load('intent_import', 'intent-import.py')
bse = load('bse', 'build-sdk-embeddings.py')

GOLD = [
    ('set an alarm for 7am', ['CreateAlarm']),
    ('start a countdown timer', ['CreateTimer', 'StartTimer']),
    ('navigate to a place', ['StartNavigate']),
    ('play some music', ['PlayMusic']),
    ('create a new note', ['CreateNote']),
    ('take a photo with the camera', ['TakePhoto', 'OpenCamera']),
    ('add a new contact', ['AddContact']),
    ('show a calendar event', ['ViewCalendarEvent']),
    ('change the wallpaper', ['SetSpecificWallpaper', 'SetWallpaperFromThemeEditor', 'SetWallpaperAndArtSignature']),
    ('call a taxi', ['StartTaxi']),
    ('delete an alarm', ['DeleteAlarm']),
    ('stop the alarm that is ringing', ['StopAlarmRing']),
    ('how much time is left on the timer', ['GetRemainTimer']),
    ('send a photo in a chat message', ['SendPhotoMessage']),
    ('share a note with someone', ['ShareNote']),
    ('open the navigation settings', ['OpenNavigationSettingsPage']),
    ('edit a music file', ['EditMusic']),
    ('pause the timer', ['PauseTimer']),
    ('snooze the alarm', ['DelayAlarmRing']),
    ('change the default payment app', ['SetDefaultPayApp']),
    ('turn off call recording', ['SetCallRecordSwitch']),
    ('how long may an app be used under parental controls', ['GetAppsLimitTime']),
    ('reset the screen reader voice pitch', ['ResetScreenReadingTone']),
    ('open the photo editor', ['EnterMediaEditUiExtension']),
]


# Worded the way a person says it, not the way the intent is named: none of
# these shares its key words with the answer's name, so only a description can
# connect them. The first list above is the easy case and is saturated.
HARD = [
    ('wake me up tomorrow morning', ['CreateAlarm']),
    ('put the phone on mute', ['SetSettingOption']),
    ('does the app icon show a red dot', ['GetAppNotifyDisplayOnIconMark']),
    ('choose which app pays when I tap my phone', ['SetDefaultPayApp']),
    ('pick the tune my alarm plays', ['OpenAlarmRingtoneSettingPage']),
    ('make the voice reader talk at its normal pitch again', ['ResetScreenReadingTone']),
    ('record phone calls automatically', ['SetCallRecordSwitch']),
    ('how long can my kid use apps', ['GetAppsLimitTime']),
    ('find a way to get to a destination', ['StartNavigate', 'ViewRoutes']),
    ('jot something down', ['CreateNote']),
    ('make the screen brighter', ['SetSettingSeekBar']),
    ('let me retouch a picture', ['EnterMediaEditUiExtension']),
    ('remind me in ten minutes', ['CreateTimer', 'StartTimer', 'CreateAlarm']),
    ('is the setting switched on', ['GetSettingSwitch']),
]


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def rank(model_args, texts, keys, queries):
    exe, model, threads = model_args
    vecs = []
    for i in range(0, len(texts), 64):
        vecs += bse.embed_chunk(exe, model, texts[i:i + 64], threads)
    qv = bse.embed_chunk(exe, model, queries, threads)
    out = []
    for q in qv:
        out.append([keys[j] for j in sorted(range(len(keys)), key=lambda j: -dot(q, vecs[j]))])
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--db', required=True, type=Path)
    ap.add_argument('--model', required=True, type=Path)
    ap.add_argument('--llama-embedding', required=True, type=Path)
    ap.add_argument('--summaries', default=HERE / 'intent-summaries.json', type=Path)
    ap.add_argument('--threads', type=int, default=8)
    args = ap.parse_args()

    summaries = json.loads(args.summaries.read_text())
    device = imp.load_device(args.db.expanduser())
    keys, old, new = [], [], []
    for (bundle, intent), records in sorted(device.items()):
        rec = next((r for r in records if r['uiAbility']['ability']), None)
        if rec is None:
            continue
        key = f'{bundle}/{intent}'
        keys.append(key)
        address = f"{bundle}/{rec['moduleName']}/{rec['uiAbility']['ability']}/{intent}"
        old.append(f'{address} {intent} ({bundle})')
        new.append(f"{intent} {summaries[key]['summary']}")
    margs = (args.llama_embedding, args.model, args.threads)
    for group, gold in (('easy', GOLD), ('hard', HARD)):
        queries = [q for q, _ in gold]
        for label, texts in (('old  address + name', old), ('new  name + summary', new)):
            ranked = rank(margs, [t.replace('\n', ' ') for t in texts], keys, queries)
            pos = []
            for (q, want), order in zip(gold, ranked):
                hit = next((i for i, k in enumerate(order) if k.rsplit('/', 1)[1] in want), 10**6)
                pos.append(hit + 1)
            n = len(gold)
            mrr = sum(1 / p for p in pos) / n
            print(f'{group} {label}:  hit@1 {sum(p <= 1 for p in pos)}/{n}  hit@3 {sum(p <= 3 for p in pos)}/{n}  '
                  f'hit@5 {sum(p <= 5 for p in pos)}/{n}  hit@8 {sum(p <= 8 for p in pos)}/{n}  MRR {mrr:.3f}')
            print('   ranks:', ' '.join(str(p) if p < 10**6 else '-' for p in pos))
    return 0


if __name__ == '__main__':
    sys.exit(main())
