'use strict'
const fs = require('node:fs')
const path = require('node:path')
const crypto = require('node:crypto')
const {execFileSync} = require('node:child_process')
const {performance} = require('node:perf_hooks')

const ROOT = path.resolve(__dirname, '../..')
const DEFAULT_GOLD = path.join(ROOT, 'docs/prompts/coverage-gold.json')
const REQUIRED_DOMAINS = ['health/fitness', 'personal finance', 'productivity/tasks', 'home/chores', 'travel/places', 'education/learning', 'games/scores', 'social/contacts', 'shopping/inventory', 'time/scheduling']
const OUTCOMES = ['template', 'complete', 'scratch']
const RESULTS = ['success', 'http_error', 'timeout', 'network_error', 'response_error', 'invalid_response', 'secret_echo']
const hash = value => crypto.createHash('sha256').update(value).digest('hex')
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value)
const text = value => typeof value === 'string' && value.trim().length > 0
const digest = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value)
class EvalError extends Error {}
function fail(message) { throw new EvalError(message) }

function validateGold(rows) {
  if (!Array.isArray(rows)) fail('Gold must be an array')
  const ids = new Set(), intents = new Map(), domains = new Set()
  for (const [index, row] of rows.entries()) {
    const prefix = 'Gold row ' + (index + 1) + ': '
    if (!object(row)) fail(prefix + 'expected an object')
    for (const field of ['id', 'intentId', 'prompt', 'domain', 'split', 'phrasing']) {
      if (!text(row[field])) fail(prefix + 'invalid ' + field)
    }
    if (row.label !== 'coverage') fail(prefix + 'label must be coverage')
    if (!['dev', 'heldout'].includes(row.split)) fail(prefix + 'invalid split')
    if (typeof row.negative !== 'boolean') fail(prefix + 'negative must be boolean')
    if (row.note !== undefined && typeof row.note !== 'string') fail(prefix + 'invalid note')
    if (!object(row.expect) || !Array.isArray(row.expect.roles) || !row.expect.roles.every(text) ||
        new Set(row.expect.roles).size !== row.expect.roles.length || !OUTCOMES.includes(row.expect.outcome)) fail(prefix + 'invalid expect')
    if (!row.negative && row.expect.roles.length === 0) fail(prefix + 'nonnegative expectations need roles')
    if (row.negative && row.expect.outcome !== 'scratch') fail(prefix + 'negative expectation must be scratch')
    if (ids.has(row.id)) fail(prefix + 'duplicate id')
    ids.add(row.id)
    domains.add(row.domain)
    const signature = JSON.stringify([row.split, row.domain, row.negative, [...row.expect.roles].sort(), row.expect.outcome])
    if (!intents.has(row.intentId)) intents.set(row.intentId, {signature, split: row.split, phrasings: new Set(), prompts: new Set()})
    const intent = intents.get(row.intentId)
    if (intent.signature !== signature) fail(prefix + 'intent split/domain/expect/negative mismatch')
    if (intent.phrasings.has(row.phrasing)) fail(prefix + 'duplicate intent phrasing type')
    if (intent.prompts.has(row.prompt)) fail(prefix + 'duplicate intent prompt')
    intent.phrasings.add(row.phrasing)
    intent.prompts.add(row.prompt)
  }
  if (rows.length < 150) fail('Gold needs at least 150 rows')
  if (REQUIRED_DOMAINS.some(domain => !domains.has(domain))) fail('Gold is missing required domains')
  if ([...intents.values()].some(intent => intent.phrasings.size < 3)) fail('Every intent needs at least three unique phrasing types')
  const heldoutIntents = [...intents.values()].filter(intent => intent.split === 'heldout').length
  const devIntents = intents.size - heldoutIntents
  if (heldoutIntents < Math.floor(intents.size / 3) || devIntents === 0) fail('Gold needs approximately one third heldout intents and a dev split')
  if (!rows.some(row => row.negative)) fail('Gold needs negative examples')
  return {rows: rows.length, intents: intents.size, domains: domains.size, devIntents, heldoutIntents,
    splits: {dev: rows.filter(row => row.split === 'dev').length, heldout: rows.filter(row => row.split === 'heldout').length}}
}

function inputFile(file) {
  if (!text(file)) fail('An input path is required')
  const resolved = fs.realpathSync(path.resolve(file))
  if (!fs.statSync(resolved).isFile()) fail('Input must be a regular file')
  return resolved
}

function outputFile(file, protectedFiles) {
  if (!text(file)) fail('An explicit output path is required')
  const absolute = path.resolve(file)
  const parent = fs.realpathSync(path.dirname(absolute))
  if (!fs.statSync(parent).isDirectory()) fail('Output parent must be an existing directory')
  const resolved = path.join(parent, path.basename(absolute))
  let stat
  try { stat = fs.lstatSync(resolved) } catch (error) { if (error.code !== 'ENOENT') throw error }
  if (stat && (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1)) fail('Output must be a regular, nonlinked file')
  for (const protectedFile of protectedFiles) {
    if (!protectedFile) continue
    const input = path.resolve(protectedFile)
    if (input === resolved) fail('Output must be distinct from inputs and protected files')
    if (fs.existsSync(input)) {
      const real = fs.realpathSync(input), other = fs.statSync(real)
      if (real === resolved || (stat && stat.dev === other.dev && stat.ino === other.ino)) fail('Output aliases an input or protected file')
    }
  }
  return resolved
}

function loadGold(file = DEFAULT_GOLD) {
  const goldPath = inputFile(file)
  const bytes = fs.readFileSync(goldPath)
  let rows
  try { rows = JSON.parse(bytes.toString('utf8')) } catch (_) { fail('Gold is not valid JSON') }
  return {path: goldPath, sha256: hash(bytes), rows, metadata: validateGold(rows)}
}

function createRuntime() {
  const {loadVera, sourceRoot} = require('./source-loader')
  const selector = path.join(sourceRoot, 'vera/VeraSectionCompose.ets')
  const sourceText = fs.readFileSync(selector, 'utf8')
  const endpoint = sourceText.match(/^const ENDPOINT:\s*string\s*=\s*'([^']+)'/m)
  if (!endpoint || !endpoint[1].startsWith('https://')) fail('Cannot resolve production selector endpoint')
  const files = new Map()
  function visit(file) {
    file = path.resolve(file)
    const name = path.relative(sourceRoot, file).split(path.sep).join('/')
    if (files.has(name)) return
    const bytes = fs.readFileSync(file)
    files.set(name, hash(bytes))
    for (const match of bytes.toString('utf8').matchAll(/\bfrom\s+['"](\.[^'"]+)['"]/g)) visit(path.resolve(path.dirname(file), match[1] + '.ets'))
  }
  visit(selector)
  files.set('host/source-loader.js', hash(fs.readFileSync(path.join(__dirname, 'source-loader.js'))))
  const sourceFiles = Object.fromEntries([...files].sort(([a], [b]) => a.localeCompare(b)))
  let revision = null
  try { revision = execFileSync('git', ['rev-parse', 'HEAD'], {cwd: sourceRoot, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore']}).trim() } catch (_) {}
  const {buildSectionRequest, readSectionPick} = loadVera('VeraSectionCompose')
  return {buildSectionRequest, readSectionPick, endpoint: endpoint[1], source: {revision, fingerprint: hash(JSON.stringify(sourceFiles)), files: sourceFiles},
    toolSha256: hash(fs.readFileSync(__filename)), nodeVersion: process.version}
}

function selectRows(rows, split) {
  if (!['dev', 'heldout', 'all'].includes(split)) fail('Split must be dev, heldout or all')
  return rows.filter(row => split === 'all' || row.split === split)
}

function requestFor(row, runtime) {
  const rawRequest = runtime.buildSectionRequest(row.prompt)
  const model = JSON.parse(rawRequest).model
  if (!text(model)) fail('Production request has no model string')
  return {rawRequest, requestSha256: hash(rawRequest), promptSha256: hash(row.prompt), model}
}

function validBody(rawBody, runtime) {
  try {
    const parsed = JSON.parse(rawBody)
    if (!object(parsed) || !object(parsed.answers)) return false
    runtime.readSectionPick(rawBody)
    return true
  } catch (_) { return false }
}

function validCapture(record) {
  if (!object(record) || record.schemaVersion !== 1 || record.kind !== 'coverage-selector-capture' ||
      !text(record.id) || !text(record.intentId) || !['dev', 'heldout'].includes(record.split) ||
      !text(record.domain) || !text(record.phrasing) || !text(record.model) || !text(record.endpoint) ||
      !text(record.timestamp) || !Number.isFinite(Date.parse(record.timestamp)) || !RESULTS.includes(record.result) ||
      !Number.isFinite(record.latencyMs) || record.latencyMs < 0 ||
      !(record.httpStatus === null || (Number.isInteger(record.httpStatus) && record.httpStatus >= 100 && record.httpStatus <= 599)) ||
      !object(record.source) || !digest(record.source.fingerprint) || !digest(record.goldSha256) ||
      typeof record.rawRequest !== 'string' || !digest(record.requestSha256) || record.requestSha256 !== hash(record.rawRequest) ||
      !digest(record.promptSha256)) return false
  try {
    const request = JSON.parse(record.rawRequest)
    if (typeof request.state !== 'string' || hash(request.state) !== record.promptSha256 || request.model !== record.model) return false
  } catch (_) { return false }
  if (record.rawBody !== null && (typeof record.rawBody !== 'string' || record.rawBodySha256 !== hash(record.rawBody))) return false
  if (record.result === 'success' && (record.httpStatus !== 200 || typeof record.rawBody !== 'string')) return false
  return true
}

function readCaptures(file, allowMissing = false) {
  if (allowMissing && !fs.existsSync(file)) return {records: [], invalidLines: [], sha256: null, needsNewline: false}
  const bytes = fs.readFileSync(inputFile(file))
  const raw = bytes.toString('utf8'), records = [], invalidLines = []
  for (const [index, line] of raw.split('\n').entries()) {
    if (line.trim() === '') continue
    try {
      const record = JSON.parse(line)
      if (!validCapture(record)) throw Error()
      records.push({record, line: index + 1})
    } catch (_) { invalidLines.push(index + 1) }
  }
  return {records, invalidLines, sha256: hash(bytes), needsNewline: raw.length > 0 && !raw.endsWith('\n')}
}

function matchingCaptures(captures, row, request) {
  return captures.records.filter(({record}) => record.id === row.id && record.intentId === row.intentId &&
    record.split === row.split && record.promptSha256 === request.promptSha256)
    .sort((a, b) => Date.parse(b.record.timestamp) - Date.parse(a.record.timestamp) || b.line - a.line)
}

function driftOf(record, request, runtime, gold) {
  return {request: record.rawRequest !== request.rawRequest || record.requestSha256 !== request.requestSha256,
    source: record.source.fingerprint !== runtime.source.fingerprint || record.source.revision !== runtime.source.revision,
    endpoint: record.endpoint !== runtime.endpoint || record.model !== request.model, gold: record.goldSha256 !== gold.sha256}
}
const requestDrift = drift => drift.request || drift.endpoint
const strictDrift = drift => requestDrift(drift) || drift.source

function safeJson(value, pretty = false) {
  const serialized = JSON.stringify(value, (_, item) => item instanceof Map ? Object.fromEntries(item) : item, pretty ? 2 : undefined)
  const key = process.env.TYPESAFE_API_KEY
  if (key && serialized.includes(key)) fail('Output blocked: API key appeared in data')
  return serialized
}

async function fetchRecord(request, row, gold, runtime, timeoutMs, fetchImpl) {
  const key = process.env.TYPESAFE_API_KEY
  if (!text(key)) fail('Set TYPESAFE_API_KEY for collect')
  if (request.rawRequest.includes(key)) fail('Request blocked: API key appeared in prompt data')
  const record = {schemaVersion: 1, kind: 'coverage-selector-capture', id: row.id, intentId: row.intentId,
    domain: row.domain, split: row.split, phrasing: row.phrasing, ...request, goldSha256: gold.sha256,
    timestamp: new Date().toISOString(), endpoint: runtime.endpoint, source: runtime.source, toolSha256: runtime.toolSha256,
    nodeVersion: runtime.nodeVersion, timeoutMs, latencyMs: 0, httpStatus: null, rawBody: null, rawBodySha256: null, result: 'network_error'}
  safeJson(record)
  const controller = new AbortController()
  let timer, expired = false, stage = 'fetch'
  const started = performance.now()
  try {
    const response = await Promise.race([
      (async () => {
        const response = await fetchImpl(runtime.endpoint, {method: 'POST', headers: {'Content-Type': 'application/json', Authorization: 'Bearer ' + key},
          body: request.rawRequest, signal: controller.signal, redirect: 'error'})
        record.httpStatus = response.status
        stage = 'body'
        const body = await response.text()
        return {body, status: response.status}
      })(),
      new Promise((_, reject) => { timer = setTimeout(() => { expired = true; controller.abort(); reject(Error()) }, timeoutMs) })
    ])
    if (response.body.includes(key)) {
      record.result = 'secret_echo'
    } else {
      record.rawBody = response.body
      record.rawBodySha256 = hash(response.body)
      record.result = response.status !== 200 ? 'http_error' : validBody(response.body, runtime) ? 'success' : 'invalid_response'
    }
  } catch (_) {
    record.result = expired ? 'timeout' : stage === 'body' ? 'response_error' : 'network_error'
  } finally {
    clearTimeout(timer)
    controller.abort()
    record.latencyMs = Math.round((performance.now() - started) * 1000) / 1000
  }
  return record
}

function protectedPaths(gold, runtime) {
  const {sourceRoot} = require('./source-loader')
  return [gold.path, __filename, path.join(__dirname, 'coverage-eval-check.js'), path.join(__dirname, 'source-loader.js'),
    ...Object.keys(runtime.source.files).filter(file => !file.startsWith('host/')).map(file => path.join(sourceRoot, file))]
}

async function collect(options, dependencies = {}) {
  const split = options.split || 'dev', timeoutMs = options.timeoutMs === undefined ? 15000 : options.timeoutMs
  const limit = options.limit === undefined ? Infinity : options.limit
  if (!Number.isInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 3600000) fail('Timeout must be 1..3600000 milliseconds')
  if (!(limit === Infinity || (Number.isInteger(limit) && limit >= 1))) fail('Limit must be a positive integer')
  const gold = loadGold(options.gold), runtime = createRuntime()
  const rows = selectRows(gold.rows, split)
  const rawPath = outputFile(options.raw, protectedPaths(gold, runtime))
  const captures = readCaptures(rawPath, true)
  if (!text(process.env.TYPESAFE_API_KEY)) fail('Set TYPESAFE_API_KEY for collect')
  const fetchImpl = dependencies.fetch || globalThis.fetch
  if (typeof fetchImpl !== 'function') fail('Collect requires Node 18 or newer with global fetch')
  const summary = {split, selected: rows.length, attempted: 0, skipped: 0, pending: 0, results: {}, invalidCaptureLines: captures.invalidLines}
  let fd
  try {
    for (const row of rows) {
      const request = requestFor(row, runtime)
      const reusable = matchingCaptures(captures, row, request).some(({record}) => record.result === 'success' &&
        !strictDrift(driftOf(record, request, runtime, gold)) && validBody(record.rawBody, runtime))
      if (reusable) { summary.skipped++; continue }
      if (summary.attempted >= limit) { summary.pending++; continue }
      const record = await fetchRecord(request, row, gold, runtime, timeoutMs, fetchImpl)
      const line = safeJson(record) + '\n'
      if (fd === undefined) {
        outputFile(rawPath, protectedPaths(gold, runtime))
        fd = fs.openSync(rawPath, fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_APPEND | fs.constants.O_NOFOLLOW, 0o600)
        if (!fs.fstatSync(fd).isFile() || fs.fstatSync(fd).nlink !== 1) fail('Capture output is not a regular nonlinked file')
        if (captures.needsNewline) fs.writeFileSync(fd, '\n')
      }
      fs.writeFileSync(fd, line)
      fs.fsyncSync(fd)
      summary.attempted++
      summary.results[record.result] = (summary.results[record.result] || 0) + 1
    }
  } finally { if (fd !== undefined) fs.closeSync(fd) }
  return summary
}

function summarize(rows) {
  const counts = Object.fromEntries([...OUTCOMES, 'missing', 'error'].map(outcome => [outcome, 0]))
  for (const row of rows) counts[row.selectorOutcome]++
  const evaluated = rows.filter(row => OUTCOMES.includes(row.selectorOutcome))
  const complete = rows.length > 0 && evaluated.length === rows.length
  const negatives = rows.filter(row => row.negative), evaluatedNegatives = negatives.filter(row => OUTCOMES.includes(row.selectorOutcome))
  const accepted = evaluatedNegatives.filter(row => row.selectorOutcome !== 'scratch').length
  const negativeComplete = negatives.length > 0 && evaluatedNegatives.length === negatives.length
  const latencies = evaluated.map(row => row.capture.latencyMs).sort((a, b) => a - b)
  return {total: rows.length, evaluated: evaluated.length, coverage: rows.length ? evaluated.length / rows.length : null, complete, counts,
    shares: Object.fromEntries(OUTCOMES.map(outcome => [outcome, complete ? counts[outcome] / rows.length : null])),
    falseAcceptRate: {value: negativeComplete ? accepted / negatives.length : null, denominator: negatives.length,
      evaluated: evaluatedNegatives.length, accepted, coverage: negatives.length ? evaluatedNegatives.length / negatives.length : null, complete: negativeComplete},
    p95LatencyMs: {value: latencies.length ? latencies[Math.ceil(latencies.length * 0.95) - 1] : null, samples: latencies.length,
      population: 'successfully replayed selected captures only', complete}}
}

function breakdown(rows, field) {
  return Object.fromEntries([...new Set(rows.map(row => row[field]))].sort().map(value => [value, summarize(rows.filter(row => row[field] === value))]))
}

function replay(options) {
  const split = options.split || 'dev', gold = loadGold(options.gold), runtime = createRuntime()
  const selected = selectRows(gold.rows, split), rawPath = inputFile(options.raw)
  if (rawPath === gold.path) fail('Capture input must be distinct from gold')
  const outPath = outputFile(options.out, [...protectedPaths(gold, runtime), rawPath])
  const captures = readCaptures(rawPath), rows = []
  for (const row of selected) {
    const request = requestFor(row, runtime)
    const matches = matchingCaptures(captures, row, request)
    const successes = matches.filter(({record}) => record.result === 'success' && validBody(record.rawBody, runtime))
    const exact = successes.filter(({record}) => !requestDrift(driftOf(record, request, runtime, gold)))
    const candidate = (exact.length ? exact : successes)[0]
    const entry = {id: row.id, intentId: row.intentId, domain: row.domain, split: row.split, phrasing: row.phrasing,
      prompt: row.prompt, negative: row.negative, expect: row.expect, promptSha256: request.promptSha256,
      currentRequestSha256: request.requestSha256, selectorOutcome: 'missing', blocks: [], sections: null, layout: null,
      globalValues: {}, note: null, needsRealData: null, needsLogic: null, capture: null, drift: null}
    const latest = candidate || matches[0]
    if (latest) {
      const record = latest.record
      entry.capture = {line: latest.line, timestamp: record.timestamp, result: record.result, httpStatus: record.httpStatus,
        latencyMs: record.latencyMs, model: record.model, endpoint: record.endpoint, requestSha256: record.requestSha256,
        rawBodySha256: record.rawBodySha256, goldSha256: record.goldSha256, source: record.source, toolSha256: record.toolSha256}
      entry.drift = driftOf(record, request, runtime, gold)
      if (!candidate) {
        entry.selectorOutcome = 'error'
        entry.note = record.result === 'success' ? 'invalid_response' : record.result
      } else if (options.strict && strictDrift(entry.drift)) {
        entry.selectorOutcome = 'error'
        entry.note = 'strict drift rejection; no selector projection'
      } else {
        const pick = runtime.readSectionPick(record.rawBody)
        entry.sections = pick.sections
        entry.blocks = (pick.sections || []).filter(section => section.kind !== 'none').map(section => section.kind)
        entry.selectorOutcome = entry.blocks.length === 0 ? 'scratch' : pick.needsLogic ? 'complete' : 'template'
        entry.layout = pick.layout
        entry.globalValues = pick.globalValues
        entry.note = pick.note
        entry.needsRealData = pick.needsRealData
        entry.needsLogic = pick.needsLogic
      }
    } else {
      entry.note = 'no capture matches current prompt and intent/split; stale prompts are never reused'
    }
    rows.push(entry)
  }
  const driftCounts = Object.fromEntries(['request', 'source', 'endpoint', 'gold'].map(field => [field, rows.filter(row => row.drift && row.drift[field]).length]))
  const warnings = ['SELECTOR PROJECTION ONLY, NOT ACTUAL PIPELINE OUTCOMES: template/complete/scratch reflect readSectionPick only; no content fill, real-data search, composition, holes, compiler, VM or pipeline execution.',
    'Missing-role rows list unfulfilled gold expectations, not causal attribution or inferred block-to-role equivalence. Per-role mapping requires human annotation.',
    'Incomplete groups have null outcome shares and null falseAcceptRate when negative coverage is incomplete. Latency is nearest-rank p95 of successfully replayed captures only.']
  if (driftCounts.request || driftCounts.source || driftCounts.endpoint) warnings.unshift('REQUEST/SOURCE DRIFT: recorded responses are being replayed against current production reader/criteria; this is NOT a fresh evaluation of current requests. See driftCounts and per-prompt drift. --strict rejects request/source/endpoint drift.')
  if (driftCounts.gold) warnings.push('GOLD DATASET DRIFT: selected captures were recorded against another full dataset hash; prompt hashes still match.')
  if (captures.invalidLines.length) warnings.push('Invalid or incomplete capture lines were ignored; see invalidCaptureLines. Captures were not modified.')
  const report = {schemaVersion: 1, kind: 'coverage-selector-replay', generatedAt: new Date().toISOString(), split, strict: Boolean(options.strict),
    interpretation: 'selector projection, NOT actual pipeline', warnings, driftCounts,
    currentRequestComparable: !(driftCounts.request || driftCounts.source || driftCounts.endpoint),
    metadata: {gold: {path: gold.path, sha256: gold.sha256, ...gold.metadata}, raw: {path: rawPath, sha256: captures.sha256},
      source: runtime.source, endpoint: runtime.endpoint, models: [...new Set(rows.filter(row => row.capture).map(row => row.capture.model))],
      toolSha256: runtime.toolSha256, nodeVersion: runtime.nodeVersion, split, strict: Boolean(options.strict), latencyQuantile: 'nearest-rank p95'},
    invalidCaptureLines: captures.invalidLines, summary: summarize(rows), byDomain: breakdown(rows, 'domain'), bySplit: breakdown(rows, 'split'),
    byDomainAndSplit: Object.fromEntries([...new Set(rows.map(row => row.domain))].sort().map(domain => [domain, breakdown(rows.filter(row => row.domain === domain), 'split')])),
    missingRoleTable: rows.filter(row => row.selectorOutcome === 'scratch').map(row => ({id: row.id, prompt: row.prompt, domain: row.domain,
      split: row.split, selectorOutcome: row.selectorOutcome, unfulfilledExpectations: row.expect.roles,
      attribution: 'unfulfilled expectations only; cause and block-to-role mapping unannotated', note: row.note})), rows}
  const serialized = safeJson(report, true) + '\n'
  outputFile(outPath, [...protectedPaths(gold, runtime), rawPath])
  const fd = fs.openSync(outPath, fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_TRUNC | fs.constants.O_NOFOLLOW, 0o600)
  try { fs.writeFileSync(fd, serialized) } finally { fs.closeSync(fd) }
  return report
}

const HELP = `Usage:
  node tools/vera-harness/coverage-eval.js collect --raw CAPTURES.jsonl [options]
  node tools/vera-harness/coverage-eval.js replay --raw CAPTURES.jsonl --out REPORT.json [options]

  --gold PATH       Gold JSON (default docs/prompts/coverage-gold.json)
  --split SPLIT     dev (default), heldout or all; only explicit heldout/all exposes heldout prompts
  --raw PATH        Explicit capture path; collect only appends, replay only reads
  --out PATH        Explicit replay report path; may overwrite, never gold/raw
  --limit N         Collect at most N pending requests, sequentially
  --timeout-ms N    Collect deadline including full response body (default 15000)
  --strict          Replay rejects request/source/endpoint drift (gold-only drift is reported)
  --help            Show this help without reading gold or loading sources

Requires Node 18+; collect uses only TYPESAFE_API_KEY and production source endpoint/model.
Set VERA_TYPESCRIPT_PATH if typescript is not resolvable. No key flags or endpoint overrides.
Resume skips successful current prompt/request/source captures; failures are retried on later collect.
Replay prefers latest successful exact request, otherwise latest successful unchanged prompt for offline criteria edits.
Reports are selector projections NOT pipeline outcomes. Incomplete rates are null; inspect coverage.
Invalid/partial capture lines are ignored and reported, never truncated. Single collector per capture file.
Full response bodies are retained; if the server echoes the key the body is omitted as secret_echo.
`

function parseArgs(argv) {
  if (argv.includes('--help')) return {help: true}
  const command = argv[0]
  if (!['collect', 'replay'].includes(command)) fail('Choose collect or replay; use --help')
  const options = {command, split: 'dev'}
  const names = {'--gold': 'gold', '--raw': 'raw', '--out': 'out', '--split': 'split', '--limit': 'limit', '--timeout-ms': 'timeoutMs'}
  for (let i = 1; i < argv.length; i++) {
    if (argv[i] === '--strict') {
      if (options.strict) fail('Duplicate option')
      options.strict = true
      continue
    }
    const name = names[argv[i]]
    if (!name || options[name] !== undefined && name !== 'split') fail('Unknown or duplicate option; use --help')
    const value = argv[++i]
    if (!text(value) || value.startsWith('--')) fail('Option requires a value')
    options[name] = value
  }
  selectRows([], options.split)
  if (!options.raw || command === 'replay' && !options.out) fail('Explicit --raw and replay --out paths are required')
  if (command === 'collect' && (options.out || options.strict)) fail('--out and --strict are replay-only')
  if (command === 'replay' && (options.limit !== undefined || options.timeoutMs !== undefined)) fail('--limit and --timeout-ms are collect-only')
  for (const name of ['limit', 'timeoutMs']) {
    if (options[name] !== undefined) {
      if (!/^[1-9][0-9]*$/.test(options[name]) || !Number.isSafeInteger(Number(options[name]))) fail('Numeric options must be positive integers')
      options[name] = Number(options[name])
    }
  }
  return options
}

async function main(argv = process.argv.slice(2), dependencies = {}) {
  const options = parseArgs(argv)
  if (options.help) { process.stdout.write(HELP); return }
  if (options.command === 'collect') {
    const summary = await collect(options, dependencies)
    process.stdout.write(safeJson(summary) + '\n')
  } else {
    const report = replay(options)
    process.stdout.write(safeJson({interpretation: report.interpretation, split: report.split, summary: report.summary,
      driftCounts: report.driftCounts, invalidCaptureLines: report.invalidCaptureLines, warnings: report.warnings}) + '\n')
  }
}

module.exports = {validateGold, loadGold, createRuntime, collect, replay, parseArgs, readCaptures, hash, main, REQUIRED_DOMAINS}
if (require.main === module) main().catch(error => {
  process.stderr.write(error instanceof EvalError ? error.message + '\n' : 'Coverage evaluation failed; check input files, output directories and source-loader dependencies.\n')
  process.exitCode = 1
})
