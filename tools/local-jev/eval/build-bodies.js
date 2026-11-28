// Build the host-eval Jev bodies for the recorded compose fixtures, and pair
// each with its recorded cloud Jev answer. The body is rebuilt exactly as the
// pipeline builds it: buildComposeRequest(prompt, parseSketch(sketch.json)).
'use strict'
const fs = require('node:fs')
const path = require('node:path')
const REPO = path.resolve(__dirname, '..', '..', '..')
const H = REPO + '/tools/vera-harness'
const { loadVera } = require(H + '/source-loader')
const c = loadVera('VeraCompose')
c.setCustomSectionsEnabled(false)

function promptFor(name) {
  for (const f of ['compose-prompts.tsv', 'compose-fresh.tsv']) {
    const p = path.join(H, f)
    if (!fs.existsSync(p)) continue
    for (const line of fs.readFileSync(p, 'utf8').split('\n')) {
      if (line.startsWith('#') || !line.includes('\t')) continue
      const [label, ...rest] = line.split('\t')
      if (label === name) return rest.join('\t').trim()
    }
  }
  return ''
}

const fixtures = ['bmi', 'expenses', 'fuel', 'mortgage', 'soft-egg', 'stopwatch', 'tip', 'egg']
const OUT = '/tmp/eval'
fs.mkdirSync(OUT + '/bodies', { recursive: true })
fs.mkdirSync(OUT + '/cloud', { recursive: true })
for (const n of fixtures) {
  const dir = path.join(H, 'compose', n)
  if (!fs.existsSync(path.join(dir, 'sketch.json'))) { console.log(n, 'SKIP (no sketch)'); continue }
  let prompt = promptFor(n)
  const sketch = c.parseSketch(fs.readFileSync(path.join(dir, 'sketch.json'), 'utf8'))
  if (!prompt) prompt = (sketch.title || n) // fall back to the sketch title
  const body = c.buildComposeRequest(prompt, sketch)
  const q = Object.keys(JSON.parse(body).questions || {})
  fs.writeFileSync(path.join(OUT, 'bodies', n + '.json'), body)
  if (fs.existsSync(path.join(dir, 'jev-answer.json'))) fs.copyFileSync(path.join(dir, 'jev-answer.json'), path.join(OUT, 'cloud', n + '.json'))
  console.log(n, 'questions=' + q.length, 'prompt=' + JSON.stringify(prompt.slice(0, 40)))
}