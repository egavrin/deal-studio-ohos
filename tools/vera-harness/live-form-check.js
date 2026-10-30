// Actual form service and stores, with only filesystem/platform boundaries mocked.
const assert = require('node:assert/strict')
const fs = require('node:fs'), path = require('node:path')
const ts = require(process.env.VERA_TYPESCRIPT_PATH || 'typescript')
const { loadVera } = require('./source-loader')
const disk = new Map(), cache = new Map()
const filesystem = {
  OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 }, mkdirSync() {},
  openSync(file) { return { fd: file } },
  writeSync(file, value) { disk.set(file, value) }, closeSync() {},
  statSync(file) { if (!disk.has(file)) throw Error('absent'); return { size: disk.get(file).length } },
  readTextSync(file) { if (!disk.has(file)) throw Error('absent'); return disk.get(file) },
  renameSync(from, to) { assert(disk.has(from)); disk.set(to, disk.get(from)); disk.delete(from) },
  unlinkSync(file) { disk.delete(file) },
  listFileSync(dir) { return [...disk.keys()].filter(file => path.dirname(file) === dir).map(file => path.basename(file)) }
}
const base = path.join(__dirname, '../../entry/src/main/ets/vera')
function load(name) {
  if (cache.has(name)) return cache.get(name).exports
  if (name === 'VeraLiveWidget' || name === 'VeraStateStamp') return loadVera(name)
  const module = { exports: {} }; cache.set(name, module)
  const source = fs.readFileSync(path.join(base, name + '.ets'), 'utf8')
  const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020, esModuleInterop: true } }).outputText
  new Function('require','module','exports', compiled)(dep => {
    if (dep === '@ohos.file.fs') return filesystem
    if (dep === '@ohos.app.form.formBindingData') return { createFormBindingData: value => value }
    if (dep.startsWith('./')) return load(dep.slice(2))
    throw Error(dep)
  }, module, module.exports)
  return module.exports
}
const {store} = load('ProjectStore'), {formBindings} = load('FormBindings')
store.init('/fixture'); formBindings.init('/fixture')
const project = store.createProject('Counter','🔢')
const source = fs.readFileSync(path.join(__dirname,'../../entry/src/main/resources/rawfile/widget-counter.vera'),'utf8')
const version = store.createVersion(project.id,source,loadVera('VeraCompiler').compileVeraSource(source).vbc2,'Counter')
formBindings.bind('form-1',project.id); formBindings.bind('form-2',project.id)
assert.deepEqual(formBindings.formsFor(project.id), ['form-1','form-2'])
const {FormBindings} = load('FormBindings'), other = new FormBindings(); other.init('/fixture')
assert.equal(other.projectFor('form-1'), project.id)
const service = load('LiveFormService'), {veraStateStamp} = load('VeraStateStamp')
const initial = service.liveFrame(project.id)
assert(initial.live)
assert(store.loadState(project.id,version.id,veraStateStamp(version.vbc2)))
const tap = (token, value) => service.liveFormTap('form-1', JSON.stringify({action:'message',handler:'change',token,value}))
const updated = tap(initial.token,1)
assert(updated.live); assert.equal(updated.formId,'form-1'); assert.notEqual(updated.token,initial.token)
const saved = store.loadState(project.id,version.id,veraStateStamp(version.vbc2))
const stale = tap(initial.token,1)
assert.match(stale.status,/changed/)
assert.equal(store.loadState(project.id,version.id,veraStateStamp(version.vbc2)),saved)
const forged = tap(updated.token,999)
assert.match(forged.status,/not available/)
assert.equal(store.loadState(project.id,version.id,veraStateStamp(version.vbc2)),saved)
assert.equal(store.listVersions(project.id).length,1)
assert(![...disk.keys()].some(file=>file.endsWith('.tmp')))
// A second widget sees the same commit and its previous token becomes stale.
assert.equal(service.liveBinding(project.id,'form-2').token, updated.token)
const second = service.liveFormTap('form-2', JSON.stringify({handler:'change',token:updated.token,value:-1}))
assert.notEqual(second.token,updated.token)
assert.match(tap(updated.token,1).status,/changed/)
// Additive refinement publishes saved state before the new version is discoverable.
const nextSource = source + '\nfunction widgetHelper(): number { return 1; }'
const nextCode = loadVera('VeraCompiler').compileVeraSource(nextSource).vbc2
const carried = store.loadState(project.id,version.id,veraStateStamp(version.vbc2))
const nextVersion = store.createVersion(project.id,nextSource,nextCode,'Make widget','','','','','',null,carried,veraStateStamp(nextCode))
assert.equal(store.loadState(project.id,nextVersion.id,veraStateStamp(nextCode)),carried)
assert.equal(store.loadState(project.id,version.id,veraStateStamp(version.vbc2)),carried)
formBindings.bind('form-1','missing-project')
assert.equal(service.liveFrame(formBindings.projectFor('form-1')).title,'App removed')
formBindings.bind('form-1',project.id)
assert.equal(service.liveBinding(project.id,'form-1').formId,'form-1')
other.unbind('form-1'); assert.equal(formBindings.projectFor('form-1'),''); assert.equal(formBindings.projectFor('form-2'),project.id)
assert.equal(service.liveBinding('', 'unbound').formId, 'unbound')
console.log('PASS live forms: binding persistence/removal, shared state, first render commit, transport, stale/forged rejection, atomic writes')
