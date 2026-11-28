// Dev-machine local Jev service.
//
// Runs the local Laya Q4 selector (native/local-jev, Candle) behind a small
// HTTP endpoint the Vera app can reach. It speaks the same body-in / answers-out
// contract as the cloud Jev (VeraCompose.askJev): POST a Jev body
// `{state, questions:{key:{type,instructions,criteria}}}` and get back
// `{answers:{key:{noul}|{choice,confidence}}, local:{...}}`.
//
// The model is the public, uncalibrated Laya bundle, so the answers are
// softmax-over-logits (diagnostic), not human-calibrated: `local.calibrated` is
// false. That is fine for exercising the pipeline; the app's own thresholds
// (PICK_ABOVE, ...) decide what to take.
//
// Configuration (env):
//   VERA_LAYA_CLI       path to the local-laya binary
//   VERA_LAYA_MANIFEST  path to the bundle's laya-manifest.json
//   PORT                listen port on 127.0.0.1 (default 8099)
'use strict'
const http = require('node:http')
const { LayaStream } = require('../vera-playground/laya-stream')

const stream = new LayaStream()
let warming = null
function warm() {
  if (warming === null) {
    warming = stream.warm().then(() => true).catch((e) => { warming = null; throw e })
  }
  return warming
}

// The local selector returns {type, choice|noul, probabilities}; the pipeline
// reads {choice, confidence} and {noul}. Map the one to the other.
function toJevAnswers(answers) {
  const out = {}
  for (const key of Object.keys(answers || {})) {
    const a = answers[key]
    if (!a || typeof a !== 'object') { out[key] = a; continue }
    if (a.type === 'noul') {
      out[key] = { noul: typeof a.noul === 'number' ? a.noul : 0 }
    } else if (a.type === 'choice') {
      const p = a.probabilities || {}
      const conf = typeof p[a.choice] === 'number' ? p[a.choice] : 1
      out[key] = { choice: a.choice, confidence: conf }
    } else {
      out[key] = a
    }
  }
  return out
}

function reply(res, code, obj) {
  const body = JSON.stringify(obj)
  res.writeHead(code, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) })
  res.end(body)
}

const server = http.createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/healthz') { res.writeHead(200); res.end('ok'); return }
  if (req.method !== 'POST' || !String(req.url).startsWith('/v1/systemone')) { reply(res, 404, { error: 'not found' }); return }
  let data = ''
  let overflow = false
  req.setEncoding('utf8')
  req.on('data', (c) => { data += c; if (data.length > 262144) { overflow = true; req.destroy() } })
  req.on('end', () => {
    if (overflow) { reply(res, 413, { error: 'request too large' }); return }
    const started = Date.now()
    Promise.resolve()
      .then(() => warm())
      .then(() => stream.query(data))
      .then((r) => {
        const local = r.response.local || {}
        const answers = toJevAnswers(r.response.answers)
        const totalMs = Date.now() - started
        console.log('POST ' + Buffer.byteLength(data) + 'B -> ' + Object.keys(answers).length +
          ' answers, ' + totalMs + 'ms' + (local.reason ? ' (' + local.reason + ')' : ''))
        reply(res, 200, {
          answers: answers,
          local: {
            model: r.source ? r.source.model : 'laya', calibrated: false, diagnostic: !!local.diagnostic,
            reason: local.reason || '', startupMs: r.timings ? r.timings.modelStartupMs : null,
            inferenceMs: r.timings ? r.timings.warmInferenceMs : null, totalMs: totalMs
          }
        })
      })
      .catch((e) => {
        console.error('POST failed: ' + String((e && e.message) || e))
        reply(res, 502, { answers: {}, local: { error: String((e && e.message) || e), totalMs: Date.now() - started } })
      })
  })
})

server.on('connection', (sock) => { console.log('conn ' + (sock.remoteAddress || '?') + ':' + (sock.remotePort || 0)) })
const port = Number(process.env.PORT || 8099)
server.listen(port, '127.0.0.1', () => {
  console.log('local-jev listening on http://127.0.0.1:' + port + '  (POST /v1/systemone)')
  warm().then(() => console.log('model warm')).catch((e) => console.error('model warm failed: ' + e.message))
})
process.on('SIGTERM', () => { stream.close(); server.close(() => process.exit(0)) })
process.on('SIGINT', () => { stream.close(); server.close(() => process.exit(0)) })