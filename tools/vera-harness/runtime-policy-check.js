// Unit checks for the generated-code capability policy and the consent key.
// No ArkUI, no device, no platform calls.
'use strict'
const assert = require('node:assert/strict')
const path = require('node:path')
const {loadVera} = require('./source-loader')

const policy = loadVera('VeraRuntimePolicy')
const stamp = loadVera('VeraStateStamp')

const allow = target => assert.equal(policy.sdkTargetPolicy(target), policy.POLICY_ALLOW, target + ' should be ALLOW')
const ask = target => assert.equal(policy.sdkTargetPolicy(target), policy.POLICY_ASK, target + ' should be ASK')
const deny = target => assert.equal(policy.sdkTargetPolicy(target), policy.POLICY_DENY, target + ' should be DENY')

// Safe local/read-only actions do not interrupt the person.
allow('CameraKit.CameraManager.setTorchMode')
allow('SensorServiceKit.vibrator.vibrate')
allow('AudioKit.AudioRenderer.write')
allow('Vera.Source.fetch')
allow('AudioKit.AudioManager.getVolume')
allow('NetworkKit.connection.hasDefaultNet')
allow('LocalizationKit.System.getSystemLanguage')

// Consequential actions ask, even when their leaf name looks harmless.
ask('CameraKit.PhotoOutput.capture')
ask('MediaKit.AVPlayer.play')
ask('MediaKit.AVRecorder.start')
ask('Vera.Ask.text')
ask('Vera.Live.fetch')
ask('AudioKit.AudioManager.setVolume')
ask('NotificationKit.notificationManager.publish')
ask('ConnectivityKit.wifiManager.enableWifi')
ask('TelephonyKit.call.setMuted')
// Sensitive device-identifier reads ask: the implemented IMEISV target, whose
// ASK entry was once misspelled (getMEISV) and fell through the get* heuristic
// to ALLOW -- a device identifier read without consent.
ask('TelephonyKit.radio.getIMEISV')
ask('TelephonyKit.radio.getIMEI')
ask('TelephonyKit.radio.getUniqueDeviceId')

// Destructive/system actions are never available to generated code.
for (const target of [
  'ArkTS.process.abort',
  'ArkTS.process.chdir',
  'BasicServicesKit.screenLock.unlock',
  'CoreFileKit.keyManager.deactivateUserKey',
  'UniversalKeystoreKit.huksExternalCrypto.clearUkeyPinAuthState',
  'BasicServicesKit.selectionManager.getSelectionContent',
  'CoreFileKit.hash.hash',
  'ConnectivityKit.wifiManager.factoryReset',
  'ConnectivityKit.wifiManager.removeAllNetwork',
  'TelephonyKit.call.makeCall',
  'TelephonyKit.radio.factoryReset',
  'TelephonyKit.sms.setSmscAddr'
]) deny(target)

// Intent policy: payment/messaging/sharing/install targets are denied; ordinary
// intents still ask rather than silently running.
assert.equal(policy.intentTargetDenied('com.example/phone/MainAbility/Pay'), true)
assert.equal(policy.intentTargetDenied('com.example/phone/MainAbility/SendTextMessage'), true)
assert.equal(policy.intentTargetDenied('com.example/phone/MainAbility/RequestPayment'), true)
assert.equal(policy.intentTargetDenied('com.example/phone/MainAbility/OpenCamera'), false)
// Only curated catalogue targets are available; a raw target is denied even
// when its name is not on the payment/messaging deny list.
assert.equal(policy.intentTargetPolicy('com.example/phone/MainAbility/OpenCamera'), policy.POLICY_DENY)
const catalogue = loadVera('VeraIntentCatalog')
const curated = catalogue.intentTargets()
assert.ok(curated.length > 0)
assert.equal(catalogue.isCuratedIntentTarget(curated[0]), true)
assert.equal(policy.intentTargetPolicy(curated[0]), policy.POLICY_ASK)
assert.equal(policy.intentTargetPolicy('com.example/phone/MainAbility/Pay'), policy.POLICY_DENY)

// The consent key binds target, mode and every parameter; order does not matter.
const a = new Map([['message', 'hello'], ['to', '123']])
const b = new Map([['to', '123'], ['message', 'hello']])
const c = new Map([['message', 'bye'], ['to', '123']])
assert.equal(policy.consentKeyFor('X/y/z/Send', 'background', a), policy.consentKeyFor('X/y/z/Send', 'background', b))
assert.notEqual(policy.consentKeyFor('X/y/z/Send', 'background', a), policy.consentKeyFor('X/y/z/Send', 'background', c))
assert.notEqual(policy.consentKeyFor('X/y/z/Send', 'background', a), policy.consentKeyFor('X/y/z/Send', 'foreground', a))
assert.notEqual(policy.consentKeyFor('X/y/z/Send', 'background', a), policy.consentKeyFor('X/y/z/Other', 'background', a))

// The in-app camera shutter is gated as an ASK target (verified above). Its
// consent key carries no program-supplied parameters -- the program hands the
// capture handler, not capture settings -- so two shutter taps in the same
// program share one grant, and a different target does not inherit it.
const camTarget = 'CameraKit.PhotoOutput.capture'
const camKey = policy.consentKeyFor(camTarget, '', new Map())
assert.equal(policy.consentKeyFor(camTarget, '', new Map()), camKey)
assert.notEqual(camKey, policy.consentKeyFor(camTarget, 'foreground', new Map()))
assert.notEqual(camKey, policy.consentKeyFor('CameraKit.CameraManager.setTorchMode', '', new Map()))

// sdk.call payload caps: target, pair count and total characters.
assert.equal(policy.sdkParamProblem('CameraKit.CameraManager.setTorchMode', ['mode', 'ON']), '')
assert.match(policy.sdkParamProblem('x'.repeat(policy.MAX_SDK_TARGET_CHARS + 1), []), /target is longer/)
assert.match(policy.sdkParamProblem('T', Array(policy.MAX_SDK_PARAM_ITEMS + 2).fill('v')), /at most 32 name\/value pairs/)
assert.match(policy.sdkParamProblem('T', ['k', 'v'.repeat(policy.MAX_SDK_PARAM_CHARS)]), /parameters are larger/)

// Image sources: app files and public https are allowed; cleartext, local,
// numeric, credential-bearing and traversal sources are not.
assert.equal(policy.imageSourceError('https://example.org/photo.jpg'), '')
assert.equal(policy.imageSourceError('file://com.vera.probe.dyn/data/storage/el2/base/files/vera/photos/a.jpg'), '')
assert.match(policy.imageSourceError('http://example.org/a.jpg'), /https:\/\//)
assert.match(policy.imageSourceError('https://localhost/a.jpg'), /public internet host/)
assert.match(policy.imageSourceError('https://127.0.0.1/a.jpg'), /public host, not a number/)
assert.match(policy.imageSourceError('https://user:pass@example.org/a.jpg'), /user name or password/)
assert.match(policy.imageSourceError('file:///data/storage/../secret.jpg'), /\.\./)
// The host is parsed separately from an explicit port and from a query or
// fragment that appears before the path: a port must not smuggle a numeric or
// local host past the checks.
assert.match(policy.imageSourceError('https://127.0.0.1:443/private.png'), /not a number/)
assert.match(policy.imageSourceError('https://192.168.1.1:8443/private.png'), /not a number/)
assert.match(policy.imageSourceError('https://0x7f.0.0.1:443/a.png'), /not a number/)
assert.match(policy.imageSourceError('https://printer.local:443/photo.png'), /public internet host/)
assert.match(policy.imageSourceError('https://localhost:8443/a.png'), /public internet host/)
assert.match(policy.imageSourceError('https://printer.local?src=x'), /public internet host/)
assert.match(policy.imageSourceError('https://printer.local#frag'), /public internet host/)
assert.match(policy.imageSourceError('https://example.org:notaport/a.png'), /port must be a number/)
assert.equal(policy.imageSourceError('https://example.org:443/photo.jpg'), '')
assert.equal(policy.imageSourceError('https://example.org?size=large'), '')

// Source/live rate limits are bounded and reset for checks.
const source = loadVera('VeraSource')
assert.equal(source.sourceUrlError('https://example.org/data.json'), '')
assert.match(source.sourceUrlError('http://example.org/data.json'), /https:\/\//)
assert.match(source.sourceUrlError('https://127.0.0.1/data.json'), /name a host, not a number/)
assert.match(source.sourceUrlError('https://localhost/data.json'), /public internet host/)
source.resetSourceRate()
let sourceAllowedCount = 0
for (let i = 0; i < source.SOURCE_PER_MINUTE; i++) if (source.sourceRateAllowed(1000 + i)) sourceAllowedCount++
assert.equal(sourceAllowedCount, source.SOURCE_PER_MINUTE)
assert.equal(source.sourceRateAllowed(1000 + source.SOURCE_PER_MINUTE), false)
source.resetSourceRate()
const live = loadVera('VeraLive')
live.resetLiveRate()
let liveAllowedCount = 0
for (let i = 0; i < live.LIVE_PER_MINUTE; i++) if (live.liveRateAllowed(2000 + i)) liveAllowedCount++
assert.equal(liveAllowedCount, live.LIVE_PER_MINUTE)
assert.equal(live.liveRateAllowed(2000 + live.LIVE_PER_MINUTE), false)
live.resetLiveRate()

// Screen node ceiling.
assert.equal(policy.screenNodeProblem(policy.MAX_APP_NODES), '')
assert.match(policy.screenNodeProblem(policy.MAX_APP_NODES + 1), /more than 3000 elements/)
assert.equal(policy.MAX_APP_TIMERS, 8)

// Persisted state has a hard size ceiling.
assert.equal(policy.stateSizeProblem(policy.MAX_STATE_CHARS), '')
assert.match(policy.stateSizeProblem(policy.MAX_STATE_CHARS + 1), /larger than/)

// The program fingerprint is stable and distinguishes ordinary variants.
const p1 = '["VBC2",["view"],[["view",0,1,false,[["return"]]]] ]'
const p2 = '["VBC2",["view"],[["view",0,1,false,[["return"]]]],["different"]]'
assert.equal(stamp.stateDigest(p1), stamp.stateDigest(p1))
assert.notEqual(stamp.stateDigest(p1), stamp.stateDigest(p2))

// The runtime adapter refuses a denied target before any platform call.
const backend = loadVera('VeraSdkBackend')
assert.equal(backend.isSdkTargetImplemented('ArkTS.process.abort'), false)
assert.equal(backend.isSdkTargetImplemented('ConnectivityKit.wifiManager.factoryReset'), false)
assert.equal(backend.isSdkTargetImplemented('CameraKit.CameraManager.setTorchMode'), true)
assert.equal(backend.isSdkTargetImplemented('CameraKit.PhotoOutput.capture'), true)
;(async () => {
  const denied = await backend.runSdkAdapter('ArkTS.process.abort', new Map())
  assert.match(denied, /not available to generated apps/)
  const intent = loadVera('VeraIntents')
  const refused = await intent.runRawIntent('com.example/phone/MainAbility/Pay', new Map(), 'background')
  assert.match(refused, /not available to generated apps/)
  // A raw, non-curated target is refused even though it is not a payment name.
  const raw = await intent.runRawIntent('com.example/phone/MainAbility/OpenCamera', new Map(), 'background')
  assert.match(raw, /not available to generated apps/)
  console.log('runtime-policy-check: all checks passed')
})().catch(e => { console.error(e); process.exit(1) })
