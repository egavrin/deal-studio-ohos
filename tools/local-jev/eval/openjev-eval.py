# Run the openJev decision model (ONNX via onnxruntime) over the host-eval Jev
# bodies and emit Jev-shaped answers. ORT is the correct reference runtime (it
# handles the masked/padded attention that MindSpore cannot). Uses the ORIGINAL
# fp16 ONNX (with the real IsNaN guard).
import json, os, glob
import numpy as np
import onnxruntime as ort
from tokenizers import Tokenizer

OJ = os.path.expanduser('~/vlj/openjev')
ABSTAIN = 'insufficient evidence'
tok = Tokenizer.from_file(OJ + '/tokenizer.json')
tok.enable_truncation(max_length=256)
tok.enable_padding(length=256)
sess = ort.InferenceSession(OJ + '/model_fp16.onnx', providers=['CPUExecutionProvider'])

def softmax(x):
    x = np.asarray(x, dtype=np.float64)
    e = np.exp(x - x.max())
    return e / e.sum()

def infer(question, context, labels):
    prompt = ''.join('<<LABEL>>' + l for l in labels) + '<<SEP>>' + 'Question: ' + question + '\n\nContext:\n' + context
    enc = tok.encode(prompt)
    ids = np.array([enc.ids], dtype=np.int64)
    mask = np.array([enc.attention_mask], dtype=np.int64)
    logits = sess.run(None, {'input_ids': ids, 'attention_mask': mask})[0][0]
    return np.asarray(logits[:len(labels)], dtype=np.float64)

def answer_question(state, q):
    t = q.get('type', 'choice')
    if t == 'noul':
        labels = ['true: ' + q.get('instructions', ''), 'false: not ' + q.get('instructions', ''), ABSTAIN]
        p = softmax(infer(q.get('instructions', ''), state, labels)[:2])
        return {'noul': float(p[0])}
    crit = q.get('criteria', {}) or {}
    opts = list(crit.keys())
    eff = opts[:24]
    labels = ['It is ' + str(crit[o]) for o in eff] + [ABSTAIN]
    lg = infer(q.get('instructions', ''), state, labels)
    optsm = softmax(lg[:len(eff)])
    i = int(np.argmax(optsm))
    full = softmax(lg)
    return {'choice': eff[i], 'confidence': float(optsm[i]), 'abstain': float(full[len(eff)]), 'capped': len(opts) > 24}

os.makedirs('/tmp/eval/openjev', exist_ok=True)
for bf in sorted(glob.glob('/tmp/eval/bodies/*.json')):
    name = os.path.basename(bf)[:-5]
    body = json.load(open(bf))
    state = body.get('state', '')
    answers = {}
    for key, q in body.get('questions', {}).items():
        answers[key] = answer_question(state, q)
    json.dump({'answers': answers}, open('/tmp/eval/openjev/%s.json' % name, 'w'))
    print(name, 'answered', len(answers))