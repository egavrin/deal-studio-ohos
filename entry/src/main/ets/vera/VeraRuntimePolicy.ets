/**
 * The generated-code capability policy.
 *
 * The VM can reach the platform only through sdk.call/intent targets. This
 * file decides what a generated program may do without asking, what it must
 * ask about, and what it may not do at all. It is deliberately separate from
 * the generated adapter table (VeraSdkBackend.ets) so re-running the adapter
 * generator cannot silently widen the security policy.
 *
 * ALLOW: a read-only, transient or user-visible local action that a normal
 *        app UI would not need to interrupt for (torch, vibration, sound,
 *        getters). It runs immediately.
 * ASK:   a state-changing, privacy-sensitive, paid or otherwise consequential
 *        action. The consent sheet shows the exact target and values; the
 *        grant is remembered for that program, target and parameter set.
 * DENY:  a destructive or system-level action that generated programs should
 *        not exercise at all. It is not offered by find_sdk_function and the
 *        runtime returns an error instead of executing it.
 */

import { isCuratedIntentTarget } from './VeraIntentCatalog'

export const POLICY_ALLOW: string = 'allow'
export const POLICY_ASK: string = 'ask'
export const POLICY_DENY: string = 'deny'

/** The largest single phone call a generated program may build. */
export const MAX_SDK_TARGET_CHARS: number = 512
export const MAX_SDK_PARAM_ITEMS: number = 64
export const MAX_SDK_PARAM_CHARS: number = 32768
/** The largest encoded program state saved or snapshotted. */
export const MAX_STATE_CHARS: number = 262144
/** A generated app screen may hold this many nodes and this many live tickers. */
export const MAX_APP_NODES: number = 3000
export const MAX_APP_TIMERS: number = 8

/** Why a screen's live node count is too large, or '' when it fits. */
export function screenNodeProblem(count: number): string {
  return count > MAX_APP_NODES ? 'this screen has more than ' + MAX_APP_NODES.toString() + ' elements' : ''
}

/** Why this encoded state is too large to persist, or '' when it fits. */
export function stateSizeProblem(chars: number): string {
  return chars > MAX_STATE_CHARS ? 'program state is larger than ' + MAX_STATE_CHARS.toString() + ' characters' : ''
}

/**
 * Why this call is too large to queue, or '' when it fits. `items` are the
 * flattened name/value strings the program passed to sdk.call.
 */
export function sdkParamProblem(target: string, items: string[]): string {
  if (target.length > MAX_SDK_TARGET_CHARS) {
    return 'sdk.call target is longer than ' + MAX_SDK_TARGET_CHARS.toString() + ' characters'
  }
  if (items.length > MAX_SDK_PARAM_ITEMS) {
    return 'sdk.call takes at most ' + (MAX_SDK_PARAM_ITEMS / 2).toString() + ' name/value pairs'
  }
  let chars = target.length
  for (let item of items) { chars += item.length }
  if (chars > MAX_SDK_PARAM_CHARS) {
    return 'sdk.call parameters are larger than ' + MAX_SDK_PARAM_CHARS.toString() + ' characters'
  }
  return ''
}

/**
 * Targets that a generated program may never execute. Keep this list explicit:
 * a prefix rule that catches a whole kit also catches the harmless getters in
 * it, and a generated utility app is allowed to read what it can safely read.
 */
const DENIED_SDK_TARGETS: string[] = [
  // Process and host availability.
  'ArkTS.process.abort',
  'ArkTS.process.chdir',
  // Lock screen / user keys / protected content.
  'BasicServicesKit.screenLock.unlock',
  'CoreFileKit.keyManager.deactivateUserKey',
  'UniversalKeystoreKit.huksExternalCrypto.clearUkeyPinAuthState',
  'DataProtectionKit.dlpPermission.cleanSandboxAppConfig',
  'DataProtectionKit.dlpPermission.setSandboxAppConfig',
  // Private selection / arbitrary local file hashing (read oracle).
  'BasicServicesKit.selectionManager.getSelectionContent',
  'CoreFileKit.hash.hash',
  // Network / radio resets and telephony control.
  'ConnectivityKit.wifiManager.factoryReset',
  'ConnectivityKit.wifiManager.removeAllNetwork',
  'ConnectivityKit.wifiManager.removeDevice',
  'ConnectivityKit.wifiManager.deletePersistentGroup',
  'TelephonyKit.radio.factoryReset',
  'TelephonyKit.radio.stopManualNetworkScan',
  'TelephonyKit.data.enableCellularDataRoaming',
  'TelephonyKit.data.disableCellularDataRoaming',
  'TelephonyKit.call.makeCall',
  'TelephonyKit.call.hangUpCall',
  'TelephonyKit.call.combineConference',
  'TelephonyKit.call.separateConference',
  'TelephonyKit.call.setCallWaiting',
  'TelephonyKit.call.disableImsSwitch',
  'TelephonyKit.sms.setSmscAddr',
  'TelephonyKit.sms.setDefaultSmsSlotId'
]

/** Local, transient or read-only actions that do not need a consent sheet. */
const ALLOW_SDK_TARGETS: string[] = [
  'CameraKit.CameraManager.setTorchMode',
  'SensorServiceKit.vibrator.startVibration',
  'SensorServiceKit.vibrator.vibrate',
  'SensorServiceKit.vibrator.stopVibration',
  'AudioKit.audio.createTonePlayer',
  'AudioKit.AudioRenderer.start',
  'AudioKit.AudioRenderer.write',
  'AudioKit.AudioRenderer.stop',
  'AudioKit.AudioRenderer.release',
  'Vera.Source.fetch'
]

/** Sensitive reads that the read-only heuristic must not auto-allow. */
const ASK_SDK_TARGETS: string[] = [
  'Vera.Ask.text',
  'Vera.Live.fetch',
  'MediaKit.AVPlayer.play',
  'MediaKit.AVRecorder.start',
  'CameraKit.PhotoOutput.capture',
  'TelephonyKit.radio.getIMEI',
  'TelephonyKit.radio.getIMEISV',
  'TelephonyKit.radio.getMEID',
  'TelephonyKit.radio.getUniqueDeviceId',
  'PerformanceAnalysisKit.hidebug.getPss',
  'PerformanceAnalysisKit.hidebug.getVss',
  'PerformanceAnalysisKit.hidebug.getPrivateDirty',
  'PerformanceAnalysisKit.hidebug.getSharedDirty',
  'PerformanceAnalysisKit.hidebug.getGraphicsMemory',
  'PerformanceAnalysisKit.hidebug.getGraphicsMemorySync',
  'PerformanceAnalysisKit.hidebug.getNativeHeapSize',
  'PerformanceAnalysisKit.hidebug.getNativeHeapAllocatedSize',
  'PerformanceAnalysisKit.hidebug.getNativeHeapFreeSize',
  'PerformanceAnalysisKit.hidebug.getAppVMObjectUsedSize',
  'PerformanceAnalysisKit.hidebug.getCpuUsage',
  'PerformanceAnalysisKit.hidebug.getSystemCpuUsage',
  'PerformanceAnalysisKit.hidebug.getVMRuntimeStat'
]

/**
 * Targets whose leaf name is a pure read: get*, is*, has*, can*, query*,
 * find*, list*, read*, count*, size*, check*. The deny/ask lists above win.
 */
function readOnlyLeaf(target: string): boolean {
  let dot = target.lastIndexOf('.')
  let leaf = dot >= 0 ? target.substring(dot + 1) : target
  return /^(get|is|has|can|query|find|list|read|count|size|check)/i.test(leaf)
}

/** What a generated program may do with an SDK target. */
export function sdkTargetPolicy(target: string): string {
  let t = target.trim()
  if (DENIED_SDK_TARGETS.indexOf(t) >= 0) { return POLICY_DENY }
  if (ASK_SDK_TARGETS.indexOf(t) >= 0) { return POLICY_ASK }
  if (ALLOW_SDK_TARGETS.indexOf(t) >= 0) { return POLICY_ALLOW }
  if (readOnlyLeaf(t)) { return POLICY_ALLOW }
  return POLICY_ASK
}

/** Whether an SDK target is permanently unavailable to generated programs. */
export function sdkTargetDenied(target: string): boolean {
  return sdkTargetPolicy(target) === POLICY_DENY
}

/**
 * High-risk intents. The last path segment is the intent name. These are the
 * payment, messaging, sharing and installation operations that a generated
 * program should not be able to trigger without a dedicated capability.
 */
const DENIED_INTENT_NAMES: string[] = [
  'pay',
  'requestpayment',
  'sendredpacket',
  'cashierpicker',
  'rechargesubwaycard',
  'addsubwaycard',
  'sendtextmessage',
  'sendmessage',
  'sendphotomessage',
  'sendlocationmessage',
  'makeaicall',
  'callmeetime',
  'huaweisharesend',
  'sendcurrentcontent',
  'uninstall',
  'factoryreset'
]

/** Whether an intent-style target is blocked for generated programs. */
export function intentTargetDenied(target: string): boolean {
  let parts = target.split('/')
  let name = parts[parts.length - 1].trim().toLowerCase()
  return DENIED_INTENT_NAMES.indexOf(name) >= 0
}

/**
 * What a generated program may do with an intent target. Only curated
 * catalogue rows are available; a raw device-registry intent has no reviewed
 * contract and is denied. Curated intents still ask for consent.
 */
export function intentTargetPolicy(target: string): string {
  if (intentTargetDenied(target)) { return POLICY_DENY }
  return isCuratedIntentTarget(target) ? POLICY_ASK : POLICY_DENY
}

/**
 * The pure part of the image-source policy: only https:// public hosts and
 * app-sandbox file:// paths. The host is still resolved by ArkUI's image
 * loader, so this does not replace an asynchronous public-address check; it
 * blocks cleartext, credentials, numeric/local hosts and path traversal.
 */
export function imageSourceError(source: string): string {
  let s = source.trim()
  if (s.startsWith('file://')) {
    return s.indexOf('..') >= 0 ? 'an image file path may not contain ..' : ''
  }
  if (!/^https:\/\/[^\s]+$/i.test(s)) { return 'an image source must use https:// or an app file:// path' }
  if (/^https:\/\/[^\/?#]*@/i.test(s)) { return 'an image source must not carry a user name or password' }
  if (/^https:\/\/\[/i.test(s)) { return 'an image source must name a public host, not a number' }
  let rest = s.substring('https://'.length)
  // The authority ends at the first path, query or fragment marker; anything
  // after a colon inside it is a port. The host is validated on its own: a
  // port (or a query before the path) must not smuggle a numeric or local
  // host past the checks that follow.
  let cut = rest.search(/[\/?#]/)
  let authority = cut >= 0 ? rest.substring(0, cut) : rest
  let colon = authority.indexOf(':')
  if (colon >= 0 && !/^[0-9]+$/.test(authority.substring(colon + 1))) {
    return 'an image source port must be a number'
  }
  let host = (colon >= 0 ? authority.substring(0, colon) : authority).toLowerCase().replace(/\.+$/, '')
  if (host.length === 0 || host.indexOf('.') < 0) { return 'an image source must name a public internet host' }
  if (host.split('.').every((label: string): boolean => /^(0x[0-9a-f]*|[0-9]+)$/i.test(label))) {
    return 'an image source must name a public host, not a number'
  }
  if (host === 'localhost' || LOCAL_SUFFIXES.some((suffix: string): boolean => host.endsWith(suffix))) {
    return 'an image source must name a public internet host'
  }
  return ''
}

/** Host names that never mean the public internet, whatever they resolve to. */
const LOCAL_SUFFIXES: string[] = ['.localhost', '.local', '.internal', '.lan', '.home.arpa', '.intranet', '.corp']

/**
 * The exact call a consent grant covers: target, mode and every parameter
 * name/value, with parameter order made stable. Two calls to the same target
 * with different values produce different keys and ask again.
 */
export function consentKeyFor(target: string, mode: string, values: Map<string, string>): string {
  let pairs: string[] = []
  values.forEach((value: string, key: string) => { pairs.push(key + '\u0001' + value) })
  pairs.sort()
  return JSON.stringify([target, mode, pairs])
}