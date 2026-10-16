#!/usr/bin/env python3
"""
Runs gold prompts through the installed app and records what Jev answered, read from the
`VERA-SECTIONS ms=.. picked=..` hilog line. The TypeSafe key stays on the phone; nothing here
needs it. A generation that falls back to DeepSeek is stopped right after Jev's answer.

Needs the phone unlocked with the Generate page open (see the driving-the-device notes).
Coordinates are device pixels on the 1280x2832 screen.

    python3 tools/device-jev-sweep.py docs/prompts/template-select-gold.json -o /tmp/sweep.json
"""
import argparse, json, os, re, subprocess, time

HDC = os.environ.get('HDC', os.path.expanduser('~/Desktop/hdc/hdc'))
FIELD, GENERATE, NEW = (640, 653), (341, 998), (905, 544)
LINE = re.compile(r'VERA-SECTIONS ms=(\d+) picked=(.*)$')


def hdc(*args):
    return subprocess.run([HDC, *args], capture_output=True, text=True).stdout


def sections_line():
    out = hdc('shell', 'hilog -x | grep "VERA-SECTIONS ms=" | tail -1')
    m = LINE.search(out.strip())
    return (int(m.group(1)), m.group(2).strip()) if m else None


def raw_line():
    out = hdc('shell', 'hilog -x | grep "VERA-SECTIONS raw" | tail -1')
    m = re.search(r'VERA-SECTIONS raw (.*)$', out.strip())
    return m.group(1).strip() if m else ''


def clean(prompt, limit):
    text = re.sub(r"[^\x20-\x7e]", ' ', prompt).replace("'", '').replace('"', '').replace('`', '')
    return re.sub(r'\s+', ' ', text).strip()[:limit]


def run_one(prompt, limit, wait):
    hdc('shell', 'hilog -r')
    # A composed result collapses the prompt field into a header row. New brings the field back; when
    # the field is already open this tap lands inside it and does nothing.
    hdc('shell', 'uitest', 'uiInput', 'click', *map(str, NEW))
    time.sleep(1.5)
    hdc('shell', 'uitest', 'uiInput', 'click', *map(str, FIELD))
    time.sleep(0.8)
    # select all, delete: without this each prompt is typed after the previous one
    hdc('shell', 'uitest uiInput keyEvent 2072 2017')
    time.sleep(0.3)
    hdc('shell', 'uitest uiInput keyEvent 2055')
    time.sleep(0.3)
    hdc('shell', "uitest uiInput inputText %d %d '%s'" % (*FIELD, clean(prompt, limit)))
    time.sleep(0.5)
    hdc('shell', 'uitest', 'uiInput', 'click', *map(str, GENERATE))
    deadline = time.time() + wait
    found = None
    while time.time() < deadline and found is None:
        time.sleep(1)
        found = sections_line()
    if found is None:
        return None
    note = found[1]
    if note.startswith('vetoed') or note.startswith('none') or 'logic=' in note:
        # falls back to DeepSeek, or hands the composed base to it: stop before the model call is paid for
        hdc('shell', 'uitest', 'uiInput', 'click', *map(str, GENERATE))  # the button is Stop now
    else:
        time.sleep(8)  # composed: let the content fill finish so the page is idle again
    time.sleep(1)
    return found + (raw_line(),)


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('gold')
    ap.add_argument('-o', '--out', required=True)
    ap.add_argument('--limit', type=int, default=400, help='characters of the prompt typed')
    ap.add_argument('--wait', type=int, default=20)
    ap.add_argument('--only', help='comma-separated ids')
    args = ap.parse_args()
    rows = json.load(open(args.gold))
    if args.only:
        keep = set(args.only.split(','))
        rows = [r for r in rows if r['id'] in keep]
    results = []
    for r in rows:
        got = run_one(r['prompt'], args.limit, args.wait)
        res = {'id': r['id'], 'label': r.get('label'), 'ms': got[0] if got else None, 'picked': got[1] if got else 'NO ANSWER', 'raw': got[2] if got else ''}
        results.append(res)
        print(res['id'], '|', res['label'], '|', res['picked'], '|', res['ms'], flush=True)
        json.dump(results, open(args.out, 'w'), indent=1)
