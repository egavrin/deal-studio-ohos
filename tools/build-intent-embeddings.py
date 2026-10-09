#!/usr/bin/env python3
"""
Precomputes EmbeddingGemma vectors for every intent in tools/intent-summaries.json,
host-side, and writes the rawfile VeraIntentEmbeddingCache.ets seeds its cache
from, so a fresh install does not spend ~90 s embedding ~640 intents on the
phone. The intent counterpart of tools/build-sdk-embeddings.py, with the same
host llama-embedding and the same GGUF.

Differences from the SDK file, on purpose: the set of intents is per-phone (the
registry is read off the device), so the output is a key -> vector map, not an
ordered binary block. Keys are exactly what VeraIntentEmbeddingCache.entryKey()
builds for a registry intent: "raw:<bundle>/<IntentName>#<fnv1a hex of text>".
The text hash means a reworded summary is a different key and gets embedded
again; a key the phone does not need is simply never looked up.

The embedded text must match entryEmbeddingText in the .ets file exactly:
"<IntentName> <summary>". The model hash is the same FNV-1a over the GGUF
filename that the SDK header carries.

Run after tools/build-intent-summaries.py / review-intent-summaries.py:
    python3 tools/build-intent-embeddings.py \\
        --model ~/path/to/embeddinggemma-300m-q4_k_m.gguf \\
        --llama-embedding entry/src/main/cpp/llama.cpp/build-host/bin/llama-embedding
"""

import argparse
import importlib.util
import json
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('build_sdk_embeddings', HERE / 'build-sdk-embeddings.py')
sdk = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sdk)


def text_hash(s: str) -> str:
    """VeraIntentEmbeddingCache.textHash: FNV-1a over UTF-16 code units, hex."""
    h = 0x811c9dc5
    data = s.encode('utf-16-le')
    for i in range(0, len(data), 2):
        h = (h ^ (data[i] | data[i + 1] << 8)) & 0xFFFFFFFF
        h = (h * 0x01000193) & 0xFFFFFFFF
    return format(h, 'x')


def embedding_text(key: str, summary: str) -> str:
    name = key.split('/', 1)[1]
    return (name + ' ' + summary).replace('\n', ' ').replace('\r', ' ')


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--model', required=True, type=Path)
    ap.add_argument('--llama-embedding', required=True, type=Path)
    ap.add_argument('--summaries', default=HERE / 'intent-summaries.json', type=Path)
    ap.add_argument('--out', default=HERE.parent / 'entry/src/main/resources/rawfile/intent-embeddings.json', type=Path)
    ap.add_argument('--chunk-size', default=400, type=int)
    ap.add_argument('--threads', default=8, type=int)
    args = ap.parse_args()

    rows = json.loads(args.summaries.read_text())
    keys = sorted(rows)
    texts = [embedding_text(k, rows[k]['summary']) for k in keys]
    print(f'{len(keys)} intents from {args.summaries}', file=sys.stderr)

    vecs = []
    started = time.time()
    for i in range(0, len(texts), args.chunk_size):
        vecs.extend(sdk.embed_chunk(args.llama_embedding, args.model, texts[i:i + args.chunk_size], args.threads))
        print(f'{len(vecs)}/{len(texts)} ({time.time() - started:.1f}s)', file=sys.stderr)
    dim = len(vecs[0])
    assert all(len(v) == dim for v in vecs)

    out = {'dimension': dim, 'modelHash': sdk.model_hash(),
           'vectors': {f'raw:{k}#{text_hash(t)}': [round(x, 5) for x in v] for k, t, v in zip(keys, texts, vecs)}}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(out, separators=(',', ':')))
    print(f'wrote {args.out} ({args.out.stat().st_size} bytes, dim={dim})', file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
