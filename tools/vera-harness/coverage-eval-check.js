'use strict'
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const os = require('node:os')
const {execFileSync} = require('node:child_process')
const {loadVera} = require('./source-loader')
const {validateGold, loadGold, createRuntime, collect, replay, parseArgs, readCaptures, hash, main, REQUIRED_DOMAINS} = require('./coverage-eval')
const production = loadVera('VeraSectionCompose')
const runtime = createRuntime()
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'vera-coverage-eval-check-'))
const goldPath = path.join(dir, 'synthetic-gold.json')
const rawPath = path.join(dir, 'captures.jsonl')
const outPath = path.join(dir, 'report.json')
const savedKey = process.env.TYPESAFE_API_KEY
const key = 'synthetic-coverage-test-secret-not-a-credential'
let assertions = 0
const check = fn => { fn(); assertions++ }
const copy = value => JSON.parse(JSON.stringify(value))
const save = (file, value) => fs.writeFileSync(file, JSON.stringify(value))
function syntheticGold() {
  return Array.from({length: 50}, (_, intent) => ['terse', 'descriptive', 'computation'].map(phrasing => ({
    id: 'synthetic-' + intent + '-' + phrasing, intentId: 'synthetic-' + intent, label: 'coverage',
    prompt: 'Synthetic intent ' + intent + ' ' + phrasing, domain: REQUIRED_DOMAINS[intent % REQUIRED_DOMAINS.length],
    split: intent < 33 ? 'dev' : 'heldout', phrasing, negative: intent % 5 === 0,
    expect: {roles: intent % 5 === 0 ? [] : ['source:synthetic', 'reader:synthetic'], outcome: intent % 5 === 0 ? 'scratch' : 'template'}
  }))).flat()
}
function body(kinds = ['checklist'], vetoes = {}) {
  const answers = {__THEME__: {choice: 'playful', confidence: 0.99}, __HEADER_STYLE__: {choice: 'center', confidence: 0.99}}
  kinds.forEach((kind, index) => { answers['section' + (index + 1)] = {choice: kind, confidence: 0.99} })
  for (const veto of loadVera('VeraTemplates').vetoes()) answers['veto.' + veto.key] = {noul: vetoes[veto.key] || 0}
  return JSON.stringify({answers, fullResponseEvidence: 'not a log summary\n' + 'long-body-'.repeat(500)})
}
const response = (rawBody = body(), status = 200) => ({status, text: async () => rawBody})
function captureLines(file = rawPath) { return fs.readFileSync(file, 'utf8').trim().split('\n').map(line => JSON.parse(line)) }
function rewrite(records, file = rawPath) { fs.writeFileSync(file, records.map(record => JSON.stringify(record)).join('\n') + '\n') }
function changedBody(record, rawBody) { return {...copy(record), rawBody, rawBodySha256: hash(rawBody)} }
function assertInvalid(change) {
  const rows = syntheticGold()
  change(rows)
  check(() => assert.throws(() => validateGold(rows)))
}

async function run() {
  process.env.TYPESAFE_API_KEY = key
  const rows = syntheticGold()
  save(goldPath, rows)
  const metadata = validateGold(rows)
  check(() => assert.deepEqual(metadata, {rows: 150, intents: 50, domains: 10, devIntents: 33, heldoutIntents: 17, splits: {dev: 99, heldout: 51}}))
  check(() => assert.equal(loadGold(goldPath).sha256, hash(fs.readFileSync(goldPath))))
  assertInvalid(rows => rows.pop())
  assertInvalid(rows => { rows[0].id = rows[1].id })
  assertInvalid(rows => { rows[0].split = 'heldout' })
  assertInvalid(rows => { rows[0].domain = 'unknown' })
  assertInvalid(rows => { rows[0].expect.roles = ['source:other'] })
  assertInvalid(rows => { rows[0].negative = false })
  assertInvalid(rows => { rows[0].phrasing = rows[1].phrasing })
  assertInvalid(rows => { rows[0].prompt = rows[1].prompt })
  assertInvalid(rows => rows.forEach(row => { if (row.split === 'heldout') row.split = 'dev' }))
  assertInvalid(rows => rows.forEach(row => { if (row.domain === REQUIRED_DOMAINS[0]) row.domain = REQUIRED_DOMAINS[1] }))
  assertInvalid(rows => { rows[3].expect.roles = [] })
  assertInvalid(rows => { rows[0].expect.outcome = 'template' })
  assertInvalid(rows => { rows[0].expect.roles = [7] })
  assertInvalid(rows => { rows[0].expect.roles = ['source:a', 'source:a'] })
  for (const [field, value] of Object.entries({id: 1, intentId: '', prompt: null, domain: [], split: 'test', phrasing: false,
    negative: 'false', label: 'other', expect: [], note: 1})) assertInvalid(rows => { rows[0][field] = value })
  check(() => assert.throws(() => validateGold({rows})))
  check(() => assert.deepEqual(parseArgs(['--help']), {help: true}))
  check(() => assert.equal(parseArgs(['replay', '--raw', rawPath, '--out', outPath]).split, 'dev'))
  for (const args of [[], ['collect'], ['replay', '--raw', rawPath], ['collect', '--raw', rawPath, '--key', 'no'],
    ['collect', '--raw', rawPath, '--limit', '0'], ['collect', '--raw', rawPath, '--limit', 'NaN'],
    ['collect', '--raw', rawPath, '--out', outPath], ['collect', '--raw', rawPath, '--strict'],
    ['replay', '--raw', rawPath, '--out', outPath, '--limit', '1'], ['collect', '--raw', rawPath, '--split', 'test']]) {
    check(() => assert.throws(() => parseArgs(args)))
  }
  const help = execFileSync(process.execPath, [path.join(__dirname, 'coverage-eval.js'), '--help'],
    {encoding: 'utf8', env: {...process.env, VERA_TYPESCRIPT_PATH: '/nonexistent/typescript'}})
  check(() => assert.match(help, /SELECTOR|selector projections/))
  check(() => assert.ok(!help.includes(key)))
  check(() => assert.equal(runtime.buildSectionRequest(rows[0].prompt), production.buildSectionRequest(rows[0].prompt)))
  check(() => assert.ok(runtime.endpoint.startsWith('https://')))
  check(() => assert.ok(runtime.source.files['vera/VeraTemplates.ets']))
  check(() => assert.ok(runtime.source.files['vera/VeraLayouts.ets']))
  check(() => assert.ok(runtime.source.files['vera/VeraSectionCompose.ets']))

  let calls = 0, active = 0, maximumActive = 0
  const actualRawBody = body()
  const mockFetch = async (endpoint, options) => {
    calls++
    active++
    maximumActive = Math.max(maximumActive, active)
    assert.equal(endpoint, runtime.endpoint)
    assert.equal(options.method, 'POST')
    assert.equal(options.headers.Authorization, 'Bearer ' + key)
    assert.equal(options.headers['Content-Type'], 'application/json')
    assert.equal(options.redirect, 'error')
    const prompt = JSON.parse(options.body).state
    assert.equal(options.body, production.buildSectionRequest(prompt))
    assert.ok(rows.filter(row => row.split === 'dev').some(row => row.prompt === prompt))
    await new Promise(resolve => setTimeout(resolve, 1))
    active--
    return response(actualRawBody)
  }
  let result = await collect({gold: goldPath, raw: rawPath, limit: 2}, {fetch: mockFetch})
  check(() => assert.equal(calls, 2))
  check(() => assert.equal(maximumActive, 1))
  check(() => assert.equal(result.pending, 97))
  let records = captureLines()
  check(() => assert.equal(records[0].rawBody, actualRawBody))
  check(() => assert.equal(records[0].rawRequest, production.buildSectionRequest(rows[0].prompt)))
  check(() => assert.equal(records[0].requestSha256, hash(records[0].rawRequest)))
  check(() => assert.equal(records[0].goldSha256, loadGold(goldPath).sha256))
  check(() => assert.equal(records[0].model, JSON.parse(records[0].rawRequest).model))
  check(() => assert.equal(records[0].httpStatus, 200))
  check(() => assert.equal(records[0].source.revision, runtime.source.revision))
  check(() => assert.ok(Number.isFinite(Date.parse(records[0].timestamp)) && records[0].latencyMs >= 0))
  check(() => assert.ok(!fs.readFileSync(rawPath, 'utf8').includes(key)))
  const firstPrefix = fs.readFileSync(rawPath, 'utf8')
  result = await collect({gold: goldPath, raw: rawPath, limit: 1}, {fetch: mockFetch})
  check(() => assert.equal(result.skipped, 2))
  check(() => assert.equal(calls, 3))
  check(() => assert.ok(fs.readFileSync(rawPath, 'utf8').startsWith(firstPrefix)))
  const baseline = captureLines()

  let report = replay({gold: goldPath, raw: rawPath, out: outPath})
  const decoded = JSON.parse(fs.readFileSync(outPath, 'utf8'))
  const realPick = production.readSectionPick(actualRawBody)
  check(() => assert.equal(report.split, 'dev'))
  check(() => assert.equal(report.rows.length, 99))
  check(() => assert.ok(report.rows.every(row => row.split === 'dev')))
  check(() => assert.ok(!fs.readFileSync(outPath, 'utf8').includes('Synthetic intent 33')))
  check(() => assert.deepEqual(decoded.rows[0].globalValues, Object.fromEntries(realPick.globalValues)))
  check(() => assert.deepEqual(decoded.rows[0].sections[0].slotValues, Object.fromEntries(realPick.sections[0].slotValues)))
  check(() => assert.deepEqual(decoded.rows[0].blocks, ['checklist']))
  check(() => assert.equal(report.summary.counts.missing, 96))
  check(() => assert.equal(report.summary.shares.template, null))
  check(() => assert.equal(report.summary.falseAcceptRate.value, null))
  check(() => assert.equal(report.summary.falseAcceptRate.denominator, 21))
  check(() => assert.equal(report.summary.falseAcceptRate.evaluated, 3))
  check(() => assert.equal(report.summary.falseAcceptRate.accepted, 3))
  check(() => assert.equal(report.summary.complete, false))
  check(() => assert.equal(report.summary.p95LatencyMs.samples, 3))
  check(() => assert.match(report.interpretation, /NOT actual pipeline/))
  check(() => assert.equal(report.byDomain[rows[0].domain].counts.template, 3))
  check(() => assert.equal(report.bySplit.dev.total, 99))
  check(() => assert.equal(report.byDomainAndSplit[rows[0].domain].dev.counts.template, 3))
  check(() => assert.equal(report.metadata.raw.sha256, hash(fs.readFileSync(rawPath))))

  report = replay({gold: goldPath, raw: rawPath, out: outPath, split: 'heldout'})
  check(() => assert.equal(report.rows.length, 51))
  check(() => assert.ok(report.rows.every(row => row.split === 'heldout' && row.selectorOutcome === 'missing')))
  report = replay({gold: goldPath, raw: rawPath, out: outPath, split: 'all'})
  check(() => assert.equal(report.rows.length, 150))
  check(() => assert.equal(report.bySplit.heldout.total, 51))
  const heldoutRaw = path.join(dir, 'heldout.jsonl')
  await collect({gold: goldPath, raw: heldoutRaw, split: 'heldout', limit: 1}, {fetch: async (_, options) => {
    check(() => assert.equal(JSON.parse(options.body).state, rows[99].prompt))
    return response()
  }})
  check(() => assert.equal(captureLines(heldoutRaw)[0].split, 'heldout'))

  let changed = copy(baseline[0])
  changed.rawRequest = changed.rawRequest.replace('What belongs', 'Changed criteria: what belongs')
  changed.requestSha256 = hash(changed.rawRequest)
  changed.source.fingerprint = hash('old source')
  rewrite([changed])
  report = replay({gold: goldPath, raw: rawPath, out: outPath})
  check(() => assert.equal(report.rows[0].selectorOutcome, 'template'))
  check(() => assert.equal(report.driftCounts.request, 1))
  check(() => assert.equal(report.driftCounts.source, 1))
  check(() => assert.equal(report.currentRequestComparable, false))
  check(() => assert.match(report.warnings[0], /REQUEST\/SOURCE DRIFT/))
  report = replay({gold: goldPath, raw: rawPath, out: outPath, strict: true})
  check(() => assert.equal(report.rows[0].selectorOutcome, 'error'))
  check(() => assert.equal(report.summary.counts.scratch, 0))
  result = await collect({gold: goldPath, raw: rawPath, limit: 1}, {fetch: mockFetch})
  check(() => assert.equal(result.skipped, 0))
  check(() => assert.equal(result.attempted, 1))
  report = replay({gold: goldPath, raw: rawPath, out: outPath})
  check(() => assert.equal(report.driftCounts.request, 0))
  changed = copy(baseline[0])
  changed.source.fingerprint = hash('source only drift')
  rewrite([changed])
  report = replay({gold: goldPath, raw: rawPath, out: outPath, strict: true})
  check(() => assert.equal(report.rows[0].selectorOutcome, 'error'))
  changed = copy(baseline[0])
  changed.endpoint = 'https://synthetic.invalid/not-used'
  rewrite([changed])
  result = await collect({gold: goldPath, raw: rawPath, limit: 1}, {fetch: mockFetch})
  check(() => assert.equal(result.skipped, 0))

  rewrite(baseline)
  const changedRows = copy(rows)
  changedRows[0].prompt += ' changed wording'
  save(goldPath, changedRows)
  report = replay({gold: goldPath, raw: rawPath, out: outPath})
  check(() => assert.equal(report.rows[0].selectorOutcome, 'missing'))
  check(() => assert.equal(report.rows[1].drift.gold, true))
  const changedResult = await collect({gold: goldPath, raw: rawPath, limit: 1}, {fetch: async (_, options) => {
    check(() => assert.equal(JSON.parse(options.body).state, changedRows[0].prompt))
    return response()
  }})
  check(() => assert.equal(changedResult.attempted, 1))
  check(() => assert.equal(changedResult.skipped, 2))
  save(goldPath, rows)
  rewrite(baseline)

  const errorCases = [
    {name: 'http_error', fetch: async () => response('full HTTP error response', 429), status: 429, raw: 'full HTTP error response'},
    {name: 'network_error', fetch: async () => { throw Error('Authorization: Bearer ' + key) }, status: null, raw: null},
    {name: 'timeout', fetch: async () => new Promise(() => {}), status: null, raw: null},
    {name: 'timeout', fetch: async () => ({status: 200, text: async () => new Promise(() => {})}), status: 200, raw: null},
    {name: 'response_error', fetch: async () => ({status: 200, text: async () => { throw Error(key) }}), status: 200, raw: null},
    {name: 'invalid_response', fetch: async () => response('not JSON'), status: 200, raw: 'not JSON'},
    {name: 'invalid_response', fetch: async () => response('{"answers":null}'), status: 200, raw: '{"answers":null}'},
    {name: 'invalid_response', fetch: async () => response('{"error":"server error"}'), status: 200, raw: '{"error":"server error"}'},
    {name: 'secret_echo', fetch: async () => response(body() + key), status: 200, raw: null}
  ]
  for (const [index, test] of errorCases.entries()) {
    const file = path.join(dir, 'failure-' + index + '.jsonl')
    let signal
    await collect({gold: goldPath, raw: file, limit: 1, timeoutMs: 10}, {fetch: (endpoint, options) => {
      signal = options.signal
      return test.fetch(endpoint, options)
    }})
    const record = captureLines(file)[0]
    check(() => assert.equal(record.result, test.name))
    check(() => assert.equal(record.httpStatus, test.status))
    check(() => assert.equal(record.rawBody, test.raw))
    check(() => assert.equal(signal.aborted, true))
    check(() => assert.ok(!fs.readFileSync(file, 'utf8').includes(key)))
    report = replay({gold: goldPath, raw: file, out: outPath})
    check(() => assert.equal(report.rows[0].selectorOutcome, 'error'))
    check(() => assert.equal(report.summary.counts.scratch, 0))
    check(() => assert.equal(report.summary.falseAcceptRate.value, null))
    const failedPrefix = fs.readFileSync(file, 'utf8')
    const retried = await collect({gold: goldPath, raw: file, limit: 1}, {fetch: async () => response()})
    check(() => assert.equal(retried.attempted, 1))
    check(() => assert.ok(fs.readFileSync(file, 'utf8').startsWith(failedPrefix)))
    report = replay({gold: goldPath, raw: file, out: outPath})
    check(() => assert.equal(report.rows[0].selectorOutcome, 'template'))
  }

  const fullRecords = rows.filter(row => row.split === 'dev').map((row, index) => {
    const rawRequest = production.buildSectionRequest(row.prompt)
    const rawBody = row.negative ? body(['none']) : index % 3 === 0 ? body(['checklist'], {needs_logic: 0.99}) : body(['checklist'])
    return {...changedBody(baseline[0], rawBody), id: row.id, intentId: row.intentId, domain: row.domain, split: row.split,
      phrasing: row.phrasing, rawRequest, requestSha256: hash(rawRequest), promptSha256: hash(row.prompt), latencyMs: index + 1}
  })
  rewrite(fullRecords)
  report = replay({gold: goldPath, raw: rawPath, out: outPath})
  check(() => assert.equal(report.summary.complete, true))
  check(() => assert.equal(report.summary.falseAcceptRate.value, 0))
  check(() => assert.equal(report.summary.falseAcceptRate.coverage, 1))
  check(() => assert.equal(report.summary.falseAcceptRate.denominator, 21))
  check(() => assert.equal(report.summary.p95LatencyMs.value, 95))
  check(() => assert.equal(report.summary.counts.scratch, 21))
  check(() => assert.ok(report.summary.counts.complete > 0))
  check(() => assert.equal(report.summary.shares.scratch, 21 / 99))
  result = await collect({gold: goldPath, raw: rawPath}, {fetch: async () => { throw Error('must not fetch resumed records') }})
  check(() => assert.equal(result.attempted, 0))
  check(() => assert.equal(result.skipped, 99))
  const nonnegativeIndex = fullRecords.findIndex(record => !rows.find(row => row.id === record.id).negative)
  fullRecords[nonnegativeIndex] = changedBody(fullRecords[nonnegativeIndex], body(['none']))
  rewrite(fullRecords)
  report = replay({gold: goldPath, raw: rawPath, out: outPath})
  const missingRoles = report.missingRoleTable.find(row => row.id === fullRecords[nonnegativeIndex].id)
  check(() => assert.deepEqual(missingRoles.unfulfilledExpectations, ['source:synthetic', 'reader:synthetic']))
  check(() => assert.match(missingRoles.attribution, /cause.*unannotated/))
  check(() => assert.ok(report.missingRoleTable.every(row => row.selectorOutcome === 'scratch')))

  const latest = changedBody(baseline[0], body(['checklist'], {needs_logic: 0.99}))
  latest.timestamp = new Date(Date.parse(baseline[0].timestamp) + 1000).toISOString()
  const laterFailure = {...copy(latest), timestamp: new Date(Date.parse(latest.timestamp) + 1000).toISOString(), result: 'http_error', httpStatus: 500}
  rewrite([latest, laterFailure, baseline[0]])
  report = replay({gold: goldPath, raw: rawPath, out: outPath})
  check(() => assert.equal(report.rows[0].selectorOutcome, 'complete'))
  check(() => assert.equal(report.rows[0].capture.line, 1))
  const driftedLatest = copy(latest)
  driftedLatest.rawRequest = driftedLatest.rawRequest.replace('What belongs', 'Different criteria')
  driftedLatest.requestSha256 = hash(driftedLatest.rawRequest)
  rewrite([baseline[0], driftedLatest])
  report = replay({gold: goldPath, raw: rawPath, out: outPath})
  check(() => assert.equal(report.rows[0].selectorOutcome, 'template'))
  check(() => assert.equal(report.rows[0].drift.request, false))
  const realData = changedBody(baseline[0], body(['checklist'], {needs_real_data: 0.99}))
  rewrite([realData])
  report = replay({gold: goldPath, raw: rawPath, out: outPath})
  check(() => assert.equal(report.rows[0].needsRealData, true))
  check(() => assert.equal(report.rows[0].selectorOutcome, 'template'))
  check(() => assert.match(report.warnings.join(' '), /NOT ACTUAL PIPELINE/))

  const tampered = copy(baseline[0])
  tampered.rawRequest += ' '
  rewrite([tampered])
  fs.appendFileSync(rawPath, '{incomplete')
  report = replay({gold: goldPath, raw: rawPath, out: outPath})
  check(() => assert.deepEqual(report.invalidCaptureLines, [1, 2]))
  check(() => assert.equal(report.rows[0].selectorOutcome, 'missing'))
  const tornPrefix = fs.readFileSync(rawPath, 'utf8')
  await collect({gold: goldPath, raw: rawPath, limit: 1}, {fetch: async () => response()})
  check(() => assert.ok(fs.readFileSync(rawPath, 'utf8').startsWith(tornPrefix + '\n')))
  check(() => assert.deepEqual(readCaptures(rawPath).invalidLines, [1, 2]))
  check(() => assert.equal(readCaptures(rawPath).records.length, 1))

  const goldBefore = fs.readFileSync(goldPath, 'utf8'), rawBefore = fs.readFileSync(rawPath, 'utf8')
  for (const out of [goldPath, rawPath, path.join(dir, 'absent/report.json'), dir, __filename, path.join(__dirname, 'coverage-eval.js')]) {
    check(() => assert.throws(() => replay({gold: goldPath, raw: rawPath, out})))
  }
  for (const raw of [goldPath, dir, path.join(dir, 'absent/captures.jsonl'), __filename]) {
    await assert.rejects(collect({gold: goldPath, raw, limit: 1}, {fetch: mockFetch}))
    assertions++
  }
  const symlink = path.join(dir, 'symlink.json'), hardlink = path.join(dir, 'hardlink.json')
  fs.symlinkSync(goldPath, symlink)
  fs.linkSync(rawPath, hardlink)
  check(() => assert.throws(() => replay({gold: goldPath, raw: rawPath, out: symlink})))
  check(() => assert.throws(() => replay({gold: goldPath, raw: rawPath, out: hardlink})))
  await assert.rejects(collect({gold: goldPath, raw: symlink, limit: 1}, {fetch: mockFetch}))
  assertions++
  await assert.rejects(collect({gold: goldPath, raw: hardlink, limit: 1}, {fetch: mockFetch}))
  assertions++
  fs.unlinkSync(hardlink)
  check(() => assert.equal(fs.readFileSync(goldPath, 'utf8'), goldBefore))
  check(() => assert.equal(fs.readFileSync(rawPath, 'utf8'), rawBefore))
  check(() => assert.ok(!fs.readFileSync(outPath, 'utf8').includes(key)))

  delete process.env.TYPESAFE_API_KEY
  await assert.rejects(collect({gold: goldPath, raw: rawPath, limit: 1}, {fetch: mockFetch}), /TYPESAFE_API_KEY/)
  assertions++
  process.env.OPENAI_API_KEY = 'another-synthetic-key'
  await assert.rejects(collect({gold: goldPath, raw: rawPath, limit: 1}, {fetch: mockFetch}), /TYPESAFE_API_KEY/)
  assertions++
  delete process.env.OPENAI_API_KEY
  process.env.TYPESAFE_API_KEY = key
  const secretGold = copy(rows)
  secretGold[0].prompt += key
  save(goldPath, secretGold)
  await assert.rejects(collect({gold: goldPath, raw: path.join(dir, 'secret.jsonl'), limit: 1}, {fetch: mockFetch}), /API key/)
  assertions++
  check(() => assert.equal(fs.existsSync(path.join(dir, 'secret.jsonl')), false))
  await assert.rejects(main(['collect', '--gold', goldPath, '--raw', path.join(dir, 'secret.jsonl'), '--limit', '1'], {fetch: mockFetch}), /API key/)
  assertions++
  save(goldPath, rows)
  console.log('coverage-eval-check: ok (' + assertions + ' checks; synthetic gold and mocked transport only)')
}

run().catch(error => { console.error(error); process.exitCode = 1 }).finally(() => {
  if (savedKey === undefined) delete process.env.TYPESAFE_API_KEY
  else process.env.TYPESAFE_API_KEY = savedKey
  fs.rmSync(dir, {recursive: true, force: true})
})
