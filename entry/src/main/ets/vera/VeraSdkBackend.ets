/**
 * A small, curated set of real adapters for sdk.call's sdk-style targets --
 * the same relationship VeraIntentCatalog has to the raw intent registry.
 * This is deliberately not "the rest of interface_sdk-js": it is the
 * handful of rows someone has actually read the real signature of, written a
 * binding for, and probed on a phone. Everything else sdk.call can address
 * (the full closed set VeraSdkIndex.isValidSdkTarget checks a target
 * against) still compiles -- it answers with the same "not implemented yet"
 * stub it always has, until a row is added here too.
 *
 * Why a curated table rather than generic reflection dispatch: ArkTS gives
 * no safe way to resolve a module and call a named export by a runtime
 * string the way dynamic JavaScript could, and even if it did, that would
 * only solve half the problem. sdk.call's own parameters are plain name/
 * value strings (the language has no other way to write a call argument),
 * while an arbitrary interface_sdk-js function takes enums, numbers,
 * booleans and nested objects -- there is no generic rule for turning
 * ["mode", "0"] into the right typed argument for a function nobody has
 * looked at. Only a person who has read that one function's actual
 * signature can bridge that gap, which is exactly the process
 * docs/intents-design.md section 7 already describes for adding a row to
 * VeraIntentCatalog -- this is the same idea, for the sdk surface.
 *
 * Adding a row: read the real signature in interface_sdk-js, write a
 * function that turns `params` into the right typed call and its answer
 * back into one string, and add it below keyed by the exact
 * "Kit.module.name" target VeraSdkIndex uses. Probe it on a phone before
 * trusting it -- the same rule every other row in this codebase follows.
 */

import storageStatistics from '@ohos.file.storageStatistics'
import { AbilityContext } from './VeraPermissions'
import calendarManager from '@ohos.calendarManager'
import camera from '@ohos.multimedia.camera'
import audio from '@ohos.multimedia.audio'
import fs from '@ohos.file.fs'
import abilityAccessCtrl from '@ohos.abilityAccessCtrl'
import partnerAgent from '@ohos.FusionConnectivity.partnerAgent'
import ranging from '@ohos.FusionConnectivity.ranging'
import PiPWindow from '@ohos.PiPWindow'
import accessibility from '@ohos.accessibility'
import osAccount from '@ohos.account.osAccount'
import abilityManager from '@ohos.app.ability.abilityManager'
import appManager from '@ohos.app.ability.appManager'
import appRecovery from '@ohos.app.ability.appRecovery'
import application from '@ohos.app.ability.application'
import autoStartupManager from '@ohos.app.ability.autoStartupManager'
import childProcessManager from '@ohos.app.ability.childProcessManager'
import dataUriUtils from '@ohos.app.ability.dataUriUtils'
import hyperSnapManager from '@ohos.app.ability.hyperSnapManager'
import quickFixManager from '@ohos.app.ability.quickFixManager'
import wantAgent from '@ohos.app.ability.wantAgent'
import startupManager from '@ohos.app.appstartup.startupManager'
import formHost from '@ohos.app.form.formHost'
import formProvider from '@ohos.app.form.formProvider'
import uriPermissionManager from '@ohos.application.uriPermissionManager'
import performanceMonitor from '@ohos.arkui.performanceMonitor'
import batteryInfo from '@ohos.batteryInfo'
import batteryStats from '@ohos.batteryStatistics'
import access from '@ohos.bluetooth.access'
import bluetoothConnection from '@ohos.bluetooth.connection'
import socket from '@ohos.bluetooth.socket'
import brightness from '@ohos.brightness'
import buffer from '@ohos.buffer'
import bundleManager from '@ohos.bundle.bundleManager'
import defaultAppManager from '@ohos.bundle.defaultAppManager'
import distributedBundleManager from '@ohos.bundle.distributedBundleManager'
import freeInstall from '@ohos.bundle.freeInstall'
import overlay from '@ohos.bundle.overlay'
import shortcutManager from '@ohos.bundle.shortcutManager'
import serial from '@ohos.busManager.serial'
import commonEventManager from '@ohos.commonEventManager'
import configPolicy from '@ohos.configPolicy'
import customConfig from '@ohos.customization.customConfig'
import distributedDataObject from '@ohos.data.distributedDataObject'
import relationalStore from '@ohos.data.relationalStore'
import uniformTypeDescriptor from '@ohos.data.uniformTypeDescriptor'
import display from '@ohos.display'
import mechanicManager from '@ohos.distributedHardware.mechanicManager'
import abilityConnectionManager from '@ohos.distributedsched.abilityConnectionManager'
import dlpPermission from '@ohos.dlpPermission'
import adminManager from '@ohos.enterprise.adminManager'
import applicationManager from '@ohos.enterprise.applicationManager'
import browser from '@ohos.enterprise.browser'
import emitter from '@ohos.events.emitter'
import fastbuffer from '@ohos.fastbuffer'
import cloudSync from '@ohos.file.cloudSync'
import cloudSyncManager from '@ohos.file.cloudSyncManager'
import Environment from '@ohos.file.environment'
import fileUri from '@ohos.file.fileuri'
import hash from '@ohos.file.hash'
import keyManager from '@ohos.file.keyManager'
import securityLabel from '@ohos.file.securityLabel'
import statfs from '@ohos.file.statvfs'
import geoLocationManager from '@ohos.geoLocationManager'
import hiTraceChain from '@ohos.hiTraceChain'
import hiTraceMeter from '@ohos.hiTraceMeter'
import hichecker from '@ohos.hichecker'
import hidebug from '@ohos.hidebug'
import hilog from '@ohos.hilog'
import hiAppEvent from '@ohos.hiviewdfx.hiAppEvent'
import hiRetrieval from '@ohos.hiviewdfx.hiRetrieval'
import jsLeakWatcher from '@ohos.hiviewdfx.jsLeakWatcher'
import i18n from '@ohos.i18n'
import identifier from '@ohos.identifier.oaid'
import inputMethod from '@ohos.inputMethod'
import avSession from '@ohos.multimedia.avsession'
import drm from '@ohos.multimedia.drm'
import media from '@ohos.multimedia.media'
import videoProcessingEngine from '@ohos.multimedia.videoProcessingEngine'
import metadataBinding from '@ohos.multimodalAwareness.metadataBinding'
import inputDevice from '@ohos.multimodalInput.inputDevice'
import pointer from '@ohos.multimodalInput.pointer'
import shortKey from '@ohos.multimodalInput.shortKey'
import netConnection from '@ohos.net.connection'
import ethernet from '@ohos.net.ethernet'
import networkSecurity from '@ohos.net.networkSecurity'
import statistics from '@ohos.net.statistics'
import nfcController from '@ohos.nfc.controller'
import notificationManager from '@ohos.notificationManager'
import notificationSubscribe from '@ohos.notificationSubscribe'
import power from '@ohos.power'
import process from '@ohos.process'
import promptAction from '@ohos.promptAction'
import reminderAgentManager from '@ohos.reminderAgentManager'
import cacheDownload from '@ohos.request.cacheDownload'
import backgroundProcessManager from '@ohos.resourceschedule.backgroundProcessManager'
import backgroundTaskManager from '@ohos.resourceschedule.backgroundTaskManager'
import workScheduler from '@ohos.resourceschedule.workScheduler'
import screen from '@ohos.screen'
import screenLock from '@ohos.screenLock'
import certificateManagerDialog from '@ohos.security.certManagerDialog'
import huksExternalCrypto from '@ohos.security.huksExternalCrypto'
import selectionManager from '@ohos.selectionInput.selectionManager'
import sensor from '@ohos.sensor'
import settings from '@ohos.settings'
import systemCapability from '@ohos.systemCapability'
import systemDateTime from '@ohos.systemDateTime'
import systemParameterEnhance from '@ohos.systemParameterEnhance'
import systemTimer from '@ohos.systemTimer'
import taskpool from '@ohos.taskpool'
import call from '@ohos.telephony.call'
import data from '@ohos.telephony.data'
import eSIM from '@ohos.telephony.esim'
import radio from '@ohos.telephony.radio'
import sim from '@ohos.telephony.sim'
import sms from '@ohos.telephony.sms'
import usbManager from '@ohos.usbManager'
import serialManager from '@ohos.usbManager.serial'
import util from '@ohos.util'
import vibrator from '@ohos.vibrator'
import wallpaper from '@ohos.wallpaper'
import wifiManager from '@ohos.wifiManager'
import window from '@ohos.window'
import floatView from '@ohos.window.floatView'
import floatingBall from '@ohos.window.floatingBall'
import zlib from '@ohos.zlib'

/** One row's real implementation: sdk.call's parameters in, its answer string out. */
export type SdkAdapter = (params: Map<string, string>) => Promise<string>

// Not @ohos.multimedia.camera's own module -- CameraManager is a class, not a
// namespace, so its methods need an instance, which is exactly what every
// other row here avoids needing (see the header comment on ADAPTERS below).
// This is the one hand-written exception: setTorchMode is common enough a
// request (it's the vera-skill.txt example, in fact) that it earns the extra
// code a class-based API costs. Not placed in the "generated helpers" block
// below because tools/generate-sdk-backend.py rewrites that block wholesale
// on every run and would delete this along with it.
// An enum value as a program writes it: "ON", "TorchMode.ON", "TORCH_MODE_ON"
// and "ToneType.TONE_TYPE_DIAL_1" all come back from the model, depending on
// the run. Keeps the member name: upper case, nothing before the last dot.
function enumMemberName(raw: string): string {
  let v = raw.trim().toUpperCase()
  let dot = v.lastIndexOf('.')
  return dot >= 0 ? v.substring(dot + 1) : v
}

// camera.TorchMode by number or by the name the SDK documents; -1 for anything
// else. A program writes "ON" as readily as "1", and parseInt("ON") is NaN.
function torchModeFrom(raw: string | undefined): number {
  if (raw === undefined) { return 0 }
  let v = enumMemberName(raw)
  if (v.startsWith('TORCH_MODE_')) { v = v.substring(11) }
  if (v === 'OFF') { return 0 }
  if (v === 'ON') { return 1 }
  if (v === 'AUTO') { return 2 }
  if (v === 'ALWAYS_OPEN') { return 3 }
  let n = Number.parseInt(v, 10)
  return Number.isNaN(n) || n < 0 || n > 3 ? -1 : n
}

let cameraManagerInstance: camera.CameraManager | null = null
function cameraManagerOnce(): camera.CameraManager | null {
  if (cameraManagerInstance !== null) { return cameraManagerInstance }
  let context = AbilityContext.value
  if (context === null) { return null }
  cameraManagerInstance = camera.getCameraManager(context)
  return cameraManagerInstance
}

let audioManagerInstance: audio.AudioManager | null = null
function audioManagerOnce(): audio.AudioManager {
  if (audioManagerInstance === null) {
    audioManagerInstance = audio.getAudioManager()
  }
  return audioManagerInstance
}

let avPlayerInstance: media.AVPlayer | null = null
let avPlayerFile: fs.File | null = null
let avPlayerUrl: string = ''
let avPlayerError: string = ''
let avPlayerBusy: boolean = false
let avPlayerPreparationReject: ((error: Error) => void) | null = null

async function avPlayerOnce(): Promise<media.AVPlayer> {
  if (avPlayerInstance !== null) { return avPlayerInstance }
  let player = await media.createAVPlayer()
  player.on('error', (error: Error): void => {
    avPlayerError = error.message
    let rejectPreparation = avPlayerPreparationReject
    if (rejectPreparation !== null) { rejectPreparation(error) }
  })
  avPlayerInstance = player
  return player
}

async function resetAvPlayer(player: media.AVPlayer): Promise<void> {
  try {
    await player.reset()
  } catch (e) {
    avPlayerInstance = null
    try {
      await player.release()
    } catch (releaseError) {
      hilog.error(0x0000, 'VERA', 'VERA-AUDIO player release failed: ' + (releaseError as Error).message)
    }
  } finally {
    let file = avPlayerFile
    avPlayerFile = null
    avPlayerUrl = ''
    avPlayerError = ''
    if (file !== null) { fs.closeSync(file) }
  }
}

async function prepareAvPlayerSource(player: media.AVPlayer, source: string): Promise<void> {
  let timer: number = -1
  let stateListener: (state: string, reason: media.StateChangeReason) => void =
    (_state: string, _reason: media.StateChangeReason): void => {}
  try {
    await new Promise<void>((resolve, reject) => {
      let preparing: boolean = false
      stateListener = (state: string, _reason: media.StateChangeReason): void => {
        if (state === 'initialized' && !preparing) {
          preparing = true
          player.prepare().catch((error: Error): void => { reject(error) })
        } else if (state === 'prepared') {
          resolve()
        } else if (state === 'error' || state === 'released') {
          reject(new Error('player entered ' + state))
        }
      }
      avPlayerPreparationReject = (error: Error): void => { reject(error) }
      player.on('stateChange', stateListener)
      timer = setTimeout((): void => { reject(new Error('audio preparation timed out')) }, 30000)
      player.url = source
    })
  } finally {
    if (timer !== -1) { clearTimeout(timer) }
    player.off('stateChange', stateListener)
    avPlayerPreparationReject = null
  }
}

async function playAudio(params: Map<string, string>): Promise<string> {
  if (avPlayerBusy) { return 'error: player operation in progress' }
  let url = paramString(params, 'url', avPlayerUrl).trim()
  if (url.length === 0) { return 'error: missing url' }
  avPlayerBusy = true
  try {
    let player = await avPlayerOnce()
    try {
      if (url === avPlayerUrl && avPlayerError.length === 0) {
        if (player.state === 'playing') { return 'ok' }
        if (player.state === 'paused' || player.state === 'prepared' || player.state === 'completed') {
          await player.play()
          return 'ok'
        }
      }
      await resetAvPlayer(player)
      player = await avPlayerOnce()
      let source = url
      if (!url.startsWith('https://') && !url.startsWith('http://')) {
        let context = AbilityContext.value
        if (context === null) { return 'error: no ability context yet' }
        let path = url.startsWith('file://') ? new fileUri.FileUri(url).path : url
        if (!path.startsWith(context.filesDir + '/') || path.split('/').includes('..')) {
          return 'error: local audio must be under app filesDir'
        }
        avPlayerFile = fs.openSync(path, fs.OpenMode.READ_ONLY)
        source = 'fd://' + avPlayerFile.fd.toString()
      }
      await prepareAvPlayerSource(player, source)
      await player.play()
      if (avPlayerError.length > 0) { throw new Error(avPlayerError) }
      avPlayerUrl = url
      return 'ok'
    } catch (e) {
      await resetAvPlayer(player)
      throw e as Error
    }
  } finally {
    avPlayerBusy = false
  }
}

async function stopAudio(): Promise<string> {
  if (avPlayerBusy) { return 'error: player operation in progress' }
  let player = avPlayerInstance
  if (player === null || avPlayerUrl.length === 0) { return 'error: nothing playing' }
  avPlayerBusy = true
  try {
    if (avPlayerError.length > 0) {
      let message = avPlayerError
      await resetAvPlayer(player)
      return 'error: ' + message
    }
    try {
      if (player.state === 'prepared' || player.state === 'playing' ||
          player.state === 'paused' || player.state === 'completed') {
        await player.stop()
      }
    } finally {
      await resetAvPlayer(player)
    }
    return 'ok'
  } finally {
    avPlayerBusy = false
  }
}

async function pauseAudio(): Promise<string> {
  if (avPlayerBusy) { return 'error: player operation in progress' }
  let player = avPlayerInstance
  if (player === null || avPlayerUrl.length === 0) { return 'error: nothing playing' }
  if (avPlayerError.length > 0) { return 'error: ' + avPlayerError }
  if (player.state === 'paused') { return 'ok' }
  if (player.state !== 'playing') { return 'error: nothing playing' }
  avPlayerBusy = true
  try {
    await player.pause()
    return 'ok'
  } finally {
    avPlayerBusy = false
  }
}

class AudioRecordingProfile implements media.AVRecorderProfile {
  audioBitrate: number = 128000
  audioChannels: number = 1
  audioCodec: media.CodecMimeType = media.CodecMimeType.AUDIO_AAC
  audioSampleRate: number = 48000
  fileFormat: media.ContainerFormatType = media.ContainerFormatType.CFT_MPEG_4A
}

class AudioRecordingConfig implements media.AVRecorderConfig {
  audioSourceType: media.AudioSourceType = media.AudioSourceType.AUDIO_SOURCE_TYPE_MIC
  profile: media.AVRecorderProfile = new AudioRecordingProfile()
  url: string = ''
}

let avRecorderInstance: media.AVRecorder | null = null
let avRecorderFile: fs.File | null = null
let avRecorderPath: string = ''
let avRecorderError: string = ''
let avRecorderBusy: boolean = false

async function avRecorderOnce(): Promise<media.AVRecorder> {
  if (avRecorderInstance !== null) { return avRecorderInstance }
  let recorder = await media.createAVRecorder()
  recorder.on('error', (error: Error): void => {
    avRecorderError = error.message
  })
  avRecorderInstance = recorder
  return recorder
}

async function resetAvRecorder(recorder: media.AVRecorder): Promise<void> {
  try {
    await recorder.reset()
  } catch (e) {
    avRecorderInstance = null
    try {
      await recorder.release()
    } catch (releaseError) {
      hilog.error(0x0000, 'VERA', 'VERA-AUDIO recorder release failed: ' + (releaseError as Error).message)
    }
  } finally {
    let file = avRecorderFile
    avRecorderFile = null
    avRecorderPath = ''
    avRecorderError = ''
    if (file !== null) { fs.closeSync(file) }
  }
}

function removeFailedRecording(path: string): void {
  if (path.length === 0) { return }
  try {
    fs.unlinkSync(path)
  } catch (e) {
    hilog.error(0x0000, 'VERA', 'VERA-AUDIO failed recording cleanup: ' + (e as Error).message)
  }
}

async function startAudioRecording(): Promise<string> {
  if (avRecorderBusy) { return 'error: recorder operation in progress' }
  let context = AbilityContext.value
  if (context === null) { return 'error: no ability context yet' }
  avRecorderBusy = true
  try {
    let status = await abilityAccessCtrl.createAtManager().checkAccessToken(
      context.applicationInfo.accessTokenId, 'ohos.permission.MICROPHONE')
    if (status !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
      return 'error: microphone permission not granted'
    }
    let recorder = await avRecorderOnce()
    if (recorder.state === 'started' || recorder.state === 'paused') {
      return 'error: already recording'
    }
    try {
      await resetAvRecorder(recorder)
      recorder = await avRecorderOnce()
      let directory = context.filesDir + '/vera'
      if (!fs.accessSync(directory)) { fs.mkdirSync(directory, true) }
      avRecorderPath = directory + '/recording-' + Date.now().toString() + '.m4a'
      avRecorderFile = fs.openSync(avRecorderPath,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC)
      let config = new AudioRecordingConfig()
      config.url = 'fd://' + avRecorderFile.fd.toString()
      await recorder.prepare(config)
      await recorder.start()
      if (avRecorderError.length > 0) { throw new Error(avRecorderError) }
      return 'ok'
    } catch (e) {
      let path = avRecorderPath
      try {
        await resetAvRecorder(recorder)
      } finally {
        removeFailedRecording(path)
      }
      throw e as Error
    }
  } finally {
    avRecorderBusy = false
  }
}

async function stopAudioRecording(): Promise<string> {
  if (avRecorderBusy) { return 'error: recorder operation in progress' }
  let recorder = avRecorderInstance
  if (recorder === null || avRecorderPath.length === 0) { return 'error: nothing recording' }
  avRecorderBusy = true
  try {
    let path = avRecorderPath
    let completed: boolean = false
    try {
      if (avRecorderError.length > 0) { return 'error: ' + avRecorderError }
      if (recorder.state !== 'started' && recorder.state !== 'paused') {
        return 'error: recorder is not recording'
      }
      await recorder.stop()
      if (avRecorderError.length > 0) { return 'error: ' + avRecorderError }
      completed = true
    } finally {
      try {
        await resetAvRecorder(recorder)
      } finally {
        if (!completed) { removeFailedRecording(path) }
      }
    }
    return path
  } finally {
    avRecorderBusy = false
  }
}

// AudioRenderer.write takes a raw ArrayBuffer (interface_sdk-js). The adapter
// accepts it as comma-separated signed 16-bit samples (see parseSamples below),
// since sdk.call only carries strings and the generated program can only build
// integers. Fixed to 48kHz mono 16-bit PCM, matching ToneStreamInfo below.

class ToneStreamInfo implements audio.AudioStreamInfo {
  samplingRate: audio.AudioSamplingRate = audio.AudioSamplingRate.SAMPLE_RATE_48000
  channels: audio.AudioChannel = audio.AudioChannel.CHANNEL_1
  sampleFormat: audio.AudioSampleFormat = audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE
  encodingType: audio.AudioEncodingType = audio.AudioEncodingType.ENCODING_TYPE_RAW
}

class ToneRendererInfo implements audio.AudioRendererInfo {
  usage: audio.StreamUsage = audio.StreamUsage.STREAM_USAGE_MEDIA
  rendererFlags: number = 0
}

class ToneRendererOptions implements audio.AudioRendererOptions {
  streamInfo: audio.AudioStreamInfo = new ToneStreamInfo()
  rendererInfo: audio.AudioRendererInfo = new ToneRendererInfo()
}

let audioRendererInstance: audio.AudioRenderer | null = null

let audioRendererRate: number = 0

function samplingRateEnum(rate: number): audio.AudioSamplingRate {
  if (rate === 8000) { return audio.AudioSamplingRate.SAMPLE_RATE_8000 }
  if (rate === 16000) { return audio.AudioSamplingRate.SAMPLE_RATE_16000 }
  if (rate === 44100) { return audio.AudioSamplingRate.SAMPLE_RATE_44100 }
  return audio.AudioSamplingRate.SAMPLE_RATE_48000
}

async function audioRendererOnce(rate: number): Promise<audio.AudioRenderer> {
  if (audioRendererInstance !== null && audioRendererRate === rate) { return audioRendererInstance }
  if (audioRendererInstance !== null) {
    let old = audioRendererInstance
    audioRendererInstance = null
    await old.release()
  }
  let options = new ToneRendererOptions()
  options.streamInfo.samplingRate = samplingRateEnum(rate)
  let renderer = await audio.createAudioRenderer(options)
  audioRendererInstance = renderer
  audioRendererRate = rate
  return renderer
}

// Renderer calls from one program run back to back: a program may fire several
// writes at once, and they must all land, in order, instead of being rejected.
let audioQueue: Promise<string> = Promise.resolve('ok')
function queueAudio(op: () => Promise<string>): Promise<string> {
  let run: Promise<string> = audioQueue.then((): Promise<string> => op())
  audioQueue = run.catch((): string => 'ok')
  return run
}
function startAudioRenderer(): Promise<string> { return queueAudio((): Promise<string> => startAudioRendererNow()) }
function writeAudioRenderer(params: Map<string, string>): Promise<string> {
  return queueAudio((): Promise<string> => writeAudioRendererNow(params))
}
function stopAudioRenderer(): Promise<string> { return queueAudio((): Promise<string> => stopAudioRendererNow()) }
function releaseAudioRenderer(): Promise<string> { return queueAudio((): Promise<string> => releaseAudioRendererNow()) }

async function startAudioRendererNow(): Promise<string> {
  try {
    let renderer = await audioRendererOnce(48000)
    if (renderer.state !== audio.AudioState.STATE_RUNNING) { await renderer.start() }
    return 'ok'
  } catch (e) {
    audioRendererInstance = null
    return 'error: ' + (e as Error).message
  } finally {
  }
}

// The `buffer` parameter arrives as one string of comma-separated signed
// 16-bit samples (-32768..32767, 48kHz mono, ToneStreamInfo above). That is
// the binary form a generated program can actually produce: VERA has int and
// string but no byte type. frequencyHz/durationMs is a fallback that makes a
// sine wave here instead.
const MAX_TONE_DURATION_MS = 10000
function parseSamples(text: string): ArrayBuffer | null {
  let parts = text.split(',')
  let out = new ArrayBuffer(parts.length * 2)
  let view = new Int16Array(out)
  for (let i = 0; i < parts.length; i++) {
    let v = Number.parseInt(parts[i].trim(), 10)
    if (Number.isNaN(v)) { return null }
    view[i] = Math.max(-32768, Math.min(32767, v))
  }
  return out
}

function synthesizeTone(frequencyHz: number, durationMs: number, volume: number): ArrayBuffer {
  let sampleRate = 48000
  let clampedMs = Math.max(0, Math.min(durationMs, MAX_TONE_DURATION_MS))
  let n = Math.floor(sampleRate * clampedMs / 1000)
  let amp = Math.max(0, Math.min(1, volume)) * 32767
  let out = new ArrayBuffer(n * 2)
  let view = new Int16Array(out)
  for (let i = 0; i < n; i++) {
    let t = i / sampleRate
    view[i] = Math.round(amp * Math.sin(2 * Math.PI * frequencyHz * t))
  }
  return out
}

async function writeAudioRendererNow(params: Map<string, string>): Promise<string> {
  let samples = paramString(params, 'buffer', '')
  let sampleRate = paramInt(params, 'sampleRate', 48000)
  let frequencyHz = paramFloat(params, 'frequencyHz', 0)
  let durationMs = paramInt(params, 'durationMs', 0)
  if (samples.length === 0 && (frequencyHz <= 0 || durationMs <= 0)) {
    return 'error: pass buffer (comma-separated 16-bit samples), or frequencyHz and durationMs'
  }
  let bytes: ArrayBuffer | null = samples.length > 0
    ? parseSamples(samples)
    : synthesizeTone(frequencyHz, durationMs, paramFloat(params, 'volume', 0.3))
  if (bytes === null) { return 'error: buffer must be comma-separated integers' }
  try {
    let renderer = await audioRendererOnce(sampleRate)
    if (renderer.state !== audio.AudioState.STATE_RUNNING) { await renderer.start() }
    let written = await renderer.write(bytes)
    return written.toString()
  } catch (e) {
    return 'error: ' + (e as Error).message
  } finally {
  }
}

async function stopAudioRendererNow(): Promise<string> {
  if (audioRendererInstance === null) { return 'ok' }
  try {
    await audioRendererInstance.stop()
    return 'ok'
  } catch (e) {
    return 'error: ' + (e as Error).message
  } finally {
  }
}

async function releaseAudioRendererNow(): Promise<string> {
  if (audioRendererInstance === null) { return 'ok' }
  try {
    let renderer = audioRendererInstance
    audioRendererInstance = null
    await renderer.release()
    return 'ok'
  } catch (e) {
    return 'error: ' + (e as Error).message
  } finally {
  }
}

// -- TonePlayer: the platform's own tone generator (dial tones, beep, ack, ...).
// A class API: nothing works until a TonePlayer exists and a tone is loaded, so
// one instance is created on first use and kept, the way AudioRenderer is.
// Every operation goes through queueAudio, so a program that fires start and
// stop back to back (a blinking pattern) gets them in order.
let tonePlayerInstance: audio.TonePlayer | null = null
let tonePlayerLoaded: number = -1

class ToneEntry {
  name: string = ''
  value: number = 0
  constructor(name: string, value: number) { this.name = name; this.value = value }
}

// audio.ToneType, by the names @ohos.multimedia.audio.d.ts documents.
const TONE_TYPES: ToneEntry[] = [
  new ToneEntry('DIAL_0', 0), new ToneEntry('DIAL_1', 1), new ToneEntry('DIAL_2', 2),
  new ToneEntry('DIAL_3', 3), new ToneEntry('DIAL_4', 4), new ToneEntry('DIAL_5', 5),
  new ToneEntry('DIAL_6', 6), new ToneEntry('DIAL_7', 7), new ToneEntry('DIAL_8', 8),
  new ToneEntry('DIAL_9', 9), new ToneEntry('DIAL_S', 10), new ToneEntry('DIAL_P', 11),
  new ToneEntry('DIAL_A', 12), new ToneEntry('DIAL_B', 13), new ToneEntry('DIAL_C', 14),
  new ToneEntry('DIAL_D', 15),
  new ToneEntry('COMMON_SUPERVISORY_DIAL', 100), new ToneEntry('COMMON_SUPERVISORY_BUSY', 101),
  new ToneEntry('COMMON_SUPERVISORY_CONGESTION', 102), new ToneEntry('COMMON_SUPERVISORY_RADIO_ACK', 103),
  new ToneEntry('COMMON_SUPERVISORY_RADIO_NOT_AVAILABLE', 104),
  new ToneEntry('COMMON_SUPERVISORY_CALL_WAITING', 106), new ToneEntry('COMMON_SUPERVISORY_RINGTONE', 107),
  new ToneEntry('COMMON_SUPERVISORY_CALL_HOLDING', 108),
  new ToneEntry('COMMON_PROPRIETARY_BEEP', 200), new ToneEntry('COMMON_PROPRIETARY_ACK', 201),
  new ToneEntry('COMMON_PROPRIETARY_PROMPT', 203), new ToneEntry('COMMON_PROPRIETARY_DOUBLE_BEEP', 204)
]
const DEFAULT_TONE = 200 // COMMON_PROPRIETARY_BEEP: a plain beep

/** A tone by number, by full name ("TONE_TYPE_DIAL_1", "DIAL_1") or by the short
 * name of a common tone ("BEEP", "DOUBLE_BEEP", "BUSY"); nothing at all means a
 * beep. -1 for anything else. */
function toneTypeFrom(raw: string | undefined): number {
  if (raw === undefined || raw.trim().length === 0) { return DEFAULT_TONE }
  let v = enumMemberName(raw)
  if (v.startsWith('TONE_TYPE_')) { v = v.substring(10) }
  for (let t of TONE_TYPES) {
    let short = t.name.replace('COMMON_PROPRIETARY_', '').replace('COMMON_SUPERVISORY_', '')
    if (v === t.name || v === short) { return t.value }
  }
  let n = Number.parseInt(v, 10)
  if (Number.isNaN(n)) { return -1 }
  for (let t of TONE_TYPES) { if (t.value === n) { return n } }
  return -1
}

async function tonePlayerOnce(): Promise<audio.TonePlayer> {
  if (tonePlayerInstance !== null) { return tonePlayerInstance }
  let player = await audio.createTonePlayer(new ToneRendererInfo())
  if (player === null) { throw new Error('could not create a tone player') }
  tonePlayerInstance = player
  tonePlayerLoaded = -1
  return player
}

// load() every time, never "already loaded": a tone that has played out or been
// stopped is spent, and start() on it plays nothing (the platform logs
// "CheckToneStopped true ... OnWriteData SequenceGen error"). With a cached
// load only the first beep of a blinking pattern was ever heard.
async function toneLoaded(player: audio.TonePlayer, type: number): Promise<void> {
  await player.load(type as audio.ToneType)
  tonePlayerLoaded = type
}

function toneFailed(e: Error): string {
  // A failed call leaves the player in an unknown state: start over next time.
  tonePlayerInstance = null
  tonePlayerLoaded = -1
  return 'error: ' + e.message
}

function toneBadType(raw: string | undefined): string {
  return 'error: type must be a tone number or name (DIAL_0..DIAL_D, BEEP, DOUBLE_BEEP, ACK, PROMPT, BUSY, ...), got "' +
    (raw ?? '') + '"'
}

function loadTone(params: Map<string, string>): Promise<string> {
  return queueAudio(async (): Promise<string> => {
    let type = toneTypeFrom(params.get('type'))
    if (type < 0) { return toneBadType(params.get('type')) }
    try {
      await toneLoaded(await tonePlayerOnce(), type)
      return 'ok'
    } catch (e) { return toneFailed(e as Error) }
  })
}

function startTone(params: Map<string, string>): Promise<string> {
  return queueAudio(async (): Promise<string> => {
    let given = params.get('type')
    let type = toneTypeFrom(given)
    if (type < 0) { return toneBadType(given) }
    try {
      let player = await tonePlayerOnce()
      // An explicit type wins; with none, the last one used, else a beep.
      let want = given !== undefined && given.trim().length > 0 ? type
        : (tonePlayerLoaded >= 0 ? tonePlayerLoaded : DEFAULT_TONE)
      await toneLoaded(player, want)
      await player.start()
      return 'ok'
    } catch (e) { return toneFailed(e as Error) }
  })
}

function stopTone(): Promise<string> {
  return queueAudio(async (): Promise<string> => {
    let player = tonePlayerInstance
    if (player === null) { return 'ok' }
    try {
      await player.stop()
      return 'ok'
    } catch (e) { return toneFailed(e as Error) }
  })
}

function releaseTone(): Promise<string> {
  return queueAudio(async (): Promise<string> => {
    let player = tonePlayerInstance
    tonePlayerInstance = null
    tonePlayerLoaded = -1
    if (player === null) { return 'ok' }
    try {
      await player.release()
      return 'ok'
    } catch (e) { return 'error: ' + (e as Error).message }
  })
}

// -- Vibration: vibrator.startVibration / stopVibration, and the older
// vibrator.vibrate a generated program reaches for just as often. The effect and
// the attribute are objects, which sdk.call cannot carry, so they are built here
// from flat parameters: `duration` (ms) for a timed buzz, or `effectId` (a preset
// such as "haptic.clock.timer") with an optional `count`; `usage` is optional and
// defaults to "alarm", which is not muted by the ringer setting.
const VIBRATE_USAGES: string[] = ['unknown', 'alarm', 'ring', 'notification', 'communication', 'touch',
  'media', 'physicalFeedback', 'simulateReality']

function vibrateUsageFrom(raw: string | undefined): string {
  if (raw === undefined || raw.trim().length === 0) { return 'alarm' }
  let v = enumMemberName(raw)
  for (let u of VIBRATE_USAGES) { if (u.toUpperCase() === v) { return u } }
  return ''
}

async function vibrateNow(params: Map<string, string>): Promise<string> {
  let usage = vibrateUsageFrom(params.get('usage'))
  if (usage.length === 0) {
    return 'error: usage must be one of ' + VIBRATE_USAGES.join(', ') + ', got "' + (params.get('usage') ?? '') + '"'
  }
  let effectJson = ''
  let preset = params.get('effectId')
  if (preset !== undefined && preset.trim().length > 0) {
    effectJson = '{"type":"preset","effectId":' + JSON.stringify(preset.trim()) + ',"count":' +
      Math.max(1, paramInt(params, 'count', 1)).toString() + '}'
  } else {
    let duration = paramInt(params, 'duration', 0)
    if (duration <= 0) { return 'error: pass duration (milliseconds, more than 0) or effectId' }
    effectJson = '{"type":"time","duration":' + duration.toString() + '}'
  }
  try {
    // JSON.parse, not an object literal: the effect and the attribute are
    // interfaces with literal-typed members, which ArkTS will not build inline.
    let effect = JSON.parse(effectJson) as vibrator.VibrateEffect
    let attribute = JSON.parse('{"id":0,"usage":"' + usage + '"}') as vibrator.VibrateAttribute
    await vibrator.startVibration(effect, attribute)
    return 'ok'
  } catch (e) {
    return 'error: ' + (e as Error).message
  }
}

// Calendar. The app's own default calendar (the one `requestCalendarPermissions`
// in VeraPermissions.ets already asks READ_CALENDAR/WRITE_CALENDAR for at
// startup, before any program runs) is fetched once and reused -- a generated
// program has no way to hold a Calendar object between two sdk.call's, since
// its parameters are plain strings, so every adapter below is self-contained
// and resolves the calendar itself rather than expecting one passed in.
//
// Event id travels through a VERA program as an opaque decimal string
// (addEvent's answer, stored in state, passed back to deleteEvent/deleteEvents)
// rather than an int: VERA-L has no string-to-int conversion, so the id is
// never parsed by the generated program, only by this file.
//
// title/hour/minute/durationMinutes/remindBefore/repeat/location mirrors the
// dropped std/calendar module's own addEvent shape (see
// docs/examples/shanghai-layover.vera) -- hour and minute-of-day, not a raw
// timestamp, because that is what a VERA program actually has (time.hourOfDay/
// time.minuteOfHour, or arithmetic on them); VERA-L has no Date type and could
// not build the real API's 13-digit millisecond timestamp itself.

let cachedCalendar: calendarManager.Calendar | null = null

async function defaultCalendar(): Promise<calendarManager.Calendar> {
  if (cachedCalendar !== null) { return cachedCalendar }
  let context = AbilityContext.value
  if (context === null) { throw new Error('no ability context yet') }
  let manager = calendarManager.getCalendarManager(context)
  let found = await manager.getCalendar()
  cachedCalendar = found
  return found
}

// Local midnight, in epoch milliseconds, so hour/minute-of-today can become
// the real API's timestamp without a Date(year, month, day) constructor --
// matches the millisOfDay math VeraUi.ets's std/time already uses.
function localMidnightMs(now: Date): number {
  let millisOfDay = ((now.getHours() * 60 + now.getMinutes()) * 60 + now.getSeconds()) * 1000 +
    now.getMilliseconds()
  return now.getTime() - millisOfDay
}

function recurrenceFrequencyFor(repeat: string): calendarManager.RecurrenceFrequency | undefined {
  let v = repeat.trim().toLowerCase()
  if (v.length === 0 || v === 'once' || v === 'none') { return undefined }
  if (v === 'daily') { return calendarManager.RecurrenceFrequency.DAILY }
  if (v === 'weekly') { return calendarManager.RecurrenceFrequency.WEEKLY }
  if (v === 'monthly') { return calendarManager.RecurrenceFrequency.MONTHLY }
  if (v === 'yearly') { return calendarManager.RecurrenceFrequency.YEARLY }
  throw new Error('parameter repeat must be once, daily, weekly, monthly or yearly, got "' + repeat + '"')
}

function parseEventIds(text: string): number[] {
  let parts = text.split(',')
  let ids: number[] = []
  for (let i = 0; i < parts.length; i++) {
    let trimmed = parts[i].trim()
    if (trimmed.length === 0) { continue }
    let n = Number.parseInt(trimmed, 10)
    if (Number.isNaN(n)) { throw new Error('parameter ids must be comma-separated integers, got "' + trimmed + '"') }
    ids.push(n)
  }
  if (ids.length === 0) { throw new Error('parameter ids is required (comma-separated event ids)') }
  return ids
}

class CalendarNewAccount implements calendarManager.CalendarAccount {
  readonly name: string
  type: calendarManager.CalendarType = calendarManager.CalendarType.LOCAL
  displayName?: string

  constructor(name: string, displayName: string) {
    this.name = name
    this.displayName = displayName.length > 0 ? displayName : undefined
  }
}

class CalendarEventLocation implements calendarManager.Location {
  location: string
  constructor(location: string) { this.location = location }
}

class CalendarEventRecurrence implements calendarManager.RecurrenceRule {
  recurrenceFrequency: calendarManager.RecurrenceFrequency
  constructor(frequency: calendarManager.RecurrenceFrequency) { this.recurrenceFrequency = frequency }
}

class CalendarNewEvent implements calendarManager.Event {
  type: calendarManager.EventType = calendarManager.EventType.NORMAL
  title: string
  startTime: number
  endTime: number
  reminderTime?: number[]
  recurrenceRule?: calendarManager.RecurrenceRule
  location?: calendarManager.Location

  constructor(title: string, startTime: number, endTime: number) {
    this.title = title
    this.startTime = startTime
    this.endTime = endTime
  }
}

// -- generated helpers below (tools/generate-sdk-backend.py) --

function paramString(params: Map<string, string>, name: string, fallback: string): string {
  let v = params.get(name)
  return v !== undefined ? v : fallback
}

// A value that is not a number is an error the program can see, not a NaN that
// the platform quietly reads as 0: a generated program passed ["mode", "OFF"]
// to setTorchMode, got "ok", and the flashlight never lit. runSdkAdapter turns
// the throw into "error: ..." as the answer.
function paramInt(params: Map<string, string>, name: string, fallback: number): number {
  let v = params.get(name)
  if (v === undefined) { return fallback }
  let n = Number.parseInt(v, 10)
  if (Number.isNaN(n)) { throw new Error('parameter ' + name + ' must be an integer, got "' + v + '"') }
  return n
}

function paramFloat(params: Map<string, string>, name: string, fallback: number): number {
  let v = params.get(name)
  if (v === undefined) { return fallback }
  let n = Number.parseFloat(v)
  if (Number.isNaN(n)) { throw new Error('parameter ' + name + ' must be a number, got "' + v + '"') }
  return n
}

function paramBoolean(params: Map<string, string>, name: string, fallback: boolean): boolean {
  let v = params.get(name)
  return v !== undefined ? v === 'true' : fallback
}

function paramBigInt(params: Map<string, string>, name: string, fallback: bigint): bigint {
  let v = params.get(name)
  return v !== undefined ? BigInt(v) : fallback
}

class SdkLocaleInfo {
  locale: string
  baseName: string
  language: string
  script: string | undefined
  region: string | undefined

  constructor(value: Intl.Locale) {
    this.locale = value.toString()
    this.baseName = value.baseName
    this.language = value.language
    this.script = value.script
    this.region = value.region
  }
}

class SdkDisplayInfo {
  id: number
  name: string
  width: number
  height: number
  rotation: number
  orientation: number
  state: number
  refreshRate: number
  densityDPI: number
  densityPixels: number
  scaledDensity: number
  xDPI: number
  yDPI: number

  constructor(value: display.Display) {
    this.id = value.id
    this.name = value.name
    this.width = value.width
    this.height = value.height
    this.rotation = value.rotation
    this.orientation = value.orientation
    this.state = value.state
    this.refreshRate = value.refreshRate
    this.densityDPI = value.densityDPI
    this.densityPixels = value.densityPixels
    this.scaledDensity = value.scaledDensity
    this.xDPI = value.xDPI
    this.yDPI = value.yDPI
  }
}

class SdkDisplayPhysicalResolutionInfo {
  foldDisplayMode: number
  physicalWidth: number
  physicalHeight: number

  constructor(value: display.DisplayPhysicalResolution) {
    this.foldDisplayMode = value.foldDisplayMode
    this.physicalWidth = value.physicalWidth
    this.physicalHeight = value.physicalHeight
  }
}

class SdkDisplayRectInfo {
  left: number
  top: number
  width: number
  height: number

  constructor(value: display.Rect) {
    this.left = value.left
    this.top = value.top
    this.width = value.width
    this.height = value.height
  }
}

class SdkFoldCreaseRegionInfo {
  displayId: number
  creaseRects: Array<SdkDisplayRectInfo>

  constructor(value: display.FoldCreaseRegion) {
    this.displayId = value.displayId
    this.creaseRects = value.creaseRects.map((rect: display.Rect): SdkDisplayRectInfo => {
      return new SdkDisplayRectInfo(rect)
    })
  }
}

const ADAPTERS: Map<string, SdkAdapter> = new Map<string, SdkAdapter>([
  // Both zero-argument and synchronous in the real API -- about as simple as
  // this surface gets, which is why they're first. Needs
  // ohos.permission.STORAGE_MANAGER (module.json5), system_basic APL
  // (signing/UnsgnedReleasedProfileTemplate.json) -- both already true of
  // this app.
  // CameraManager is a class (VeraSdkIndex scopeKind: interface), not a
  // namespace -- the one shape excluded from tools/select-sdk-backend-
  // candidates.py wholesale, because most classes need an instance built in
  // a way no script can read off the declaration. This one is the exception:
  // camera.getCameraManager(context) is itself a plain namespace function
  // that only needs the ability context every handler already has, cached
  // once above (cameraManagerOnce). mode arrives as sdk.call's usual string
  // ("0"/"1"/"2"), which happens to already be TorchMode's own numeric
  // encoding (OFF/ON/AUTO), so parsing it as int and casting is exact rather
  // than a guess.
  ['CameraKit.CameraManager.setTorchMode', async (params: Map<string, string>): Promise<string> => {
    let manager = cameraManagerOnce()
    if (manager === null) { return 'error: no ability context yet' }
    if (!manager.isTorchSupported()) { return 'error: torch not supported on this device' }
    let mode = torchModeFrom(params.get('mode'))
    if (mode < 0) {
      return 'error: mode must be 0 (OFF), 1 (ON), 2 (AUTO) or 3 (ALWAYS_OPEN), got "' + (params.get('mode') ?? '') + '"'
    }
    manager.setTorchMode(mode as camera.TorchMode)
    return 'ok'
  }],
  ['AudioKit.AudioManager.setVolume', async (params: Map<string, string>): Promise<string> => {
    let volumeType = paramInt(params, 'volumeType', audio.AudioVolumeType.MEDIA)
    let volume = paramInt(params, 'volume', 0)
    await audioManagerOnce().setVolume(volumeType as audio.AudioVolumeType, volume)
    return 'ok'
  }],
  ['AudioKit.AudioManager.getVolume', async (params: Map<string, string>): Promise<string> => {
    let volumeType = paramInt(params, 'volumeType', audio.AudioVolumeType.MEDIA)
    let result = await audioManagerOnce().getVolume(volumeType as audio.AudioVolumeType)
    return result.toString()
  }],
  ['AudioKit.AudioManager.getMaxVolume', async (params: Map<string, string>): Promise<string> => {
    let volumeType = paramInt(params, 'volumeType', audio.AudioVolumeType.MEDIA)
    let result = await audioManagerOnce().getMaxVolume(volumeType as audio.AudioVolumeType)
    return result.toString()
  }],
  ['AudioKit.AudioManager.getMinVolume', async (params: Map<string, string>): Promise<string> => {
    let volumeType = paramInt(params, 'volumeType', audio.AudioVolumeType.MEDIA)
    let result = await audioManagerOnce().getMinVolume(volumeType as audio.AudioVolumeType)
    return result.toString()
  }],
  ['AudioKit.AudioManager.mute', async (params: Map<string, string>): Promise<string> => {
    let volumeType = paramInt(params, 'volumeType', audio.AudioVolumeType.MEDIA)
    let mute = paramBoolean(params, 'mute', false)
    await audioManagerOnce().mute(volumeType as audio.AudioVolumeType, mute)
    return 'ok'
  }],
  ['AudioKit.AudioManager.isMute', async (params: Map<string, string>): Promise<string> => {
    let volumeType = paramInt(params, 'volumeType', audio.AudioVolumeType.MEDIA)
    let result = await audioManagerOnce().isMute(volumeType as audio.AudioVolumeType)
    return result.toString()
  }],
  ['AudioKit.AudioManager.setMicrophoneMute', async (params: Map<string, string>): Promise<string> => {
    let mute = paramBoolean(params, 'mute', false)
    await audioManagerOnce().setMicrophoneMute(mute)
    return 'ok'
  }],
  ['AudioKit.AudioManager.isMicrophoneMute', async (_params: Map<string, string>): Promise<string> => {
    let result = await audioManagerOnce().isMicrophoneMute()
    return result.toString()
  }],
  ['AudioKit.AudioManager.setRingerMode', async (params: Map<string, string>): Promise<string> => {
    let mode = paramInt(params, 'mode', audio.AudioRingMode.RINGER_MODE_NORMAL)
    await audioManagerOnce().setRingerMode(mode as audio.AudioRingMode)
    return 'ok'
  }],
  ['AudioKit.AudioManager.getRingerMode', async (_params: Map<string, string>): Promise<string> => {
    let result = await audioManagerOnce().getRingerMode()
    return result.toString()
  }],
  ['MediaKit.AVPlayer.play', async (params: Map<string, string>): Promise<string> => {
    return await playAudio(params)
  }],
  ['MediaKit.AVPlayer.stop', async (_params: Map<string, string>): Promise<string> => {
    return await stopAudio()
  }],
  ['MediaKit.AVPlayer.pause', async (_params: Map<string, string>): Promise<string> => {
    return await pauseAudio()
  }],
  ['MediaKit.AVRecorder.start', async (_params: Map<string, string>): Promise<string> => {
    return await startAudioRecording()
  }],
  ['MediaKit.AVRecorder.stop', async (_params: Map<string, string>): Promise<string> => {
    return await stopAudioRecording()
  }],
  // Sound generation, not file playback: `buffer` is comma-separated 16-bit
  // samples (48kHz, mono -- ToneStreamInfo above) that the generated program
  // computed itself, or frequencyHz/durationMs for a built-in sine wave.
  // start()/write() both lazily create the renderer and start it if it
  // isn't already running, so a program can just call write() directly in
  // the common case; start/stop/release are still exposed separately for a
  // program that wants to hold the stream open across several writes rather
  // than pay renderer startup latency each time.
  // Vibration. startVibration and the deprecated vibrate share one implementation:
  // `duration` in milliseconds (or `effectId` for a preset), optional `usage`.
  ['SensorServiceKit.vibrator.startVibration', async (params: Map<string, string>): Promise<string> => {
    return await vibrateNow(params)
  }],
  ['SensorServiceKit.vibrator.vibrate', async (params: Map<string, string>): Promise<string> => {
    return await vibrateNow(params)
  }],
  ['SensorServiceKit.vibrator.stopVibration', async (_params: Map<string, string>): Promise<string> => {
    try {
      await vibrator.stopVibration()
      return 'ok'
    } catch (e) { return 'error: ' + (e as Error).message }
  }],
  // The platform's tone generator. createTonePlayer takes an AudioRendererInfo,
  // which a program cannot build, so it is created with the same media-usage info
  // the AudioRenderer adapter uses; load takes `type` (a number or a ToneType
  // name), and start with no `type` plays whatever is loaded, a beep if nothing is.
  ['AudioKit.audio.createTonePlayer', async (_params: Map<string, string>): Promise<string> => {
    return await queueAudio(async (): Promise<string> => {
      try { await tonePlayerOnce(); return 'ok' } catch (e) { return toneFailed(e as Error) }
    })
  }],
  ['AudioKit.TonePlayer.load', async (params: Map<string, string>): Promise<string> => {
    return await loadTone(params)
  }],
  ['AudioKit.TonePlayer.start', async (params: Map<string, string>): Promise<string> => {
    return await startTone(params)
  }],
  ['AudioKit.TonePlayer.stop', async (_params: Map<string, string>): Promise<string> => {
    return await stopTone()
  }],
  ['AudioKit.TonePlayer.release', async (_params: Map<string, string>): Promise<string> => {
    return await releaseTone()
  }],
  ['AudioKit.AudioRenderer.start', async (_params: Map<string, string>): Promise<string> => {
    return await startAudioRenderer()
  }],
  ['AudioKit.AudioRenderer.write', async (params: Map<string, string>): Promise<string> => {
    return await writeAudioRenderer(params)
  }],
  ['AudioKit.AudioRenderer.stop', async (_params: Map<string, string>): Promise<string> => {
    return await stopAudioRenderer()
  }],
  ['AudioKit.AudioRenderer.release', async (_params: Map<string, string>): Promise<string> => {
    return await releaseAudioRenderer()
  }],
  ['CalendarKit.CalendarManager.getCalendar', async (_params: Map<string, string>): Promise<string> => {
    let calendar = await defaultCalendar()
    return calendar.id.toString()
  }],
  ['CalendarKit.CalendarManager.createCalendar', async (params: Map<string, string>): Promise<string> => {
    let context = AbilityContext.value
    if (context === null) { throw new Error('no ability context yet') }
    let name = paramString(params, 'name', '')
    if (name.trim().length === 0) { throw new Error('parameter name is required') }
    let displayName = paramString(params, 'displayName', '')
    let manager = calendarManager.getCalendarManager(context)
    let created = await manager.createCalendar(new CalendarNewAccount(name, displayName))
    return created.id.toString()
  }],
  // hour/minute are today's hour-of-day and minute-of-hour, the values a
  // VERA program actually has; durationMinutes defaults to an hour,
  // remindBefore (minutes before the start) is omitted unless given,
  // repeat is once/daily/weekly/monthly/yearly. Answers with the new
  // event's id (a plain decimal string) so the program can keep it for a
  // later deleteEvent/deleteEvents.
  ['CalendarKit.Calendar.addEvent', async (params: Map<string, string>): Promise<string> => {
    let title = paramString(params, 'title', '')
    if (title.trim().length === 0) { throw new Error('parameter title is required') }
    let hour = paramInt(params, 'hour', -1)
    let minute = paramInt(params, 'minute', -1)
    if (hour < 0 || hour > 23) { throw new Error('parameter hour must be 0-23, got ' + hour.toString()) }
    if (minute < 0 || minute > 59) { throw new Error('parameter minute must be 0-59, got ' + minute.toString()) }
    let durationMinutes = paramInt(params, 'durationMinutes', 60)
    if (durationMinutes <= 0) { throw new Error('parameter durationMinutes must be more than 0') }
    let remindBefore = paramInt(params, 'remindBefore', -1)
    let frequency = recurrenceFrequencyFor(paramString(params, 'repeat', 'once'))
    let location = paramString(params, 'location', '')
    let start = localMidnightMs(new Date()) + (hour * 60 + minute) * 60000
    let event = new CalendarNewEvent(title, start, start + durationMinutes * 60000)
    if (remindBefore >= 0) { event.reminderTime = [remindBefore] }
    if (frequency !== undefined) { event.recurrenceRule = new CalendarEventRecurrence(frequency) }
    if (location.trim().length > 0) { event.location = new CalendarEventLocation(location) }
    let calendar = await defaultCalendar()
    let id = await calendar.addEvent(event)
    return id.toString()
  }],
  ['CalendarKit.Calendar.deleteEvent', async (params: Map<string, string>): Promise<string> => {
    let id = paramInt(params, 'id', -1)
    if (id < 0) { throw new Error('parameter id is required') }
    let calendar = await defaultCalendar()
    await calendar.deleteEvent(id)
    return 'ok'
  }],
  ['CalendarKit.Calendar.deleteEvents', async (params: Map<string, string>): Promise<string> => {
    let ids = parseEventIds(paramString(params, 'ids', ''))
    let calendar = await defaultCalendar()
    await calendar.deleteEvents(ids)
    return 'ok'
  }],
  ['CoreFileKit.storageStatistics.getFreeSizeSync', async (_params: Map<string, string>): Promise<string> => {
    return storageStatistics.getFreeSizeSync().toString()
  }],
  ['CoreFileKit.storageStatistics.getTotalSizeSync', async (_params: Map<string, string>): Promise<string> => {
    return storageStatistics.getTotalSizeSync().toString()
  }],
  ['LocalizationKit.System.getSystemLanguages', async (_params: Map<string, string>): Promise<string> => {
    return JSON.stringify(i18n.System.getSystemLanguages())
  }],
  ['LocalizationKit.System.getSystemLanguage', async (_params: Map<string, string>): Promise<string> => {
    return i18n.System.getSystemLanguage()
  }],
  ['LocalizationKit.System.getSystemRegion', async (_params: Map<string, string>): Promise<string> => {
    return i18n.System.getSystemRegion()
  }],
  ['LocalizationKit.System.getSystemLocaleInstance', async (_params: Map<string, string>): Promise<string> => {
    return JSON.stringify(new SdkLocaleInfo(i18n.System.getSystemLocaleInstance()))
  }],
  ['LocalizationKit.System.is24HourClock', async (_params: Map<string, string>): Promise<string> => {
    return i18n.System.is24HourClock().toString()
  }],
  ['LocalizationKit.System.getPreferredLanguageList', async (_params: Map<string, string>): Promise<string> => {
    return JSON.stringify(i18n.System.getPreferredLanguageList())
  }],
  ['LocalizationKit.System.getFirstPreferredLanguage', async (_params: Map<string, string>): Promise<string> => {
    return i18n.System.getFirstPreferredLanguage()
  }],
  ['LocalizationKit.System.getAppPreferredLanguage', async (_params: Map<string, string>): Promise<string> => {
    return i18n.System.getAppPreferredLanguage()
  }],
  ['LocalizationKit.System.getUsingLocalDigit', async (_params: Map<string, string>): Promise<string> => {
    return i18n.System.getUsingLocalDigit().toString()
  }],
  ['LocalizationKit.System.getTemperatureType', async (_params: Map<string, string>): Promise<string> => {
    return i18n.System.getTemperatureType().toString()
  }],
  ['LocalizationKit.System.getFirstDayOfWeek', async (_params: Map<string, string>): Promise<string> => {
    return i18n.System.getFirstDayOfWeek().toString()
  }],
  ['ArkUI.display.getDefaultDisplaySync', async (_params: Map<string, string>): Promise<string> => {
    return JSON.stringify(new SdkDisplayInfo(display.getDefaultDisplaySync()))
  }],
  ['ArkUI.display.getPrimaryDisplaySync', async (_params: Map<string, string>): Promise<string> => {
    return JSON.stringify(new SdkDisplayInfo(display.getPrimaryDisplaySync()))
  }],
  ['ArkUI.display.getAllDisplays', async (_params: Map<string, string>): Promise<string> => {
    let result = await display.getAllDisplays()
    return JSON.stringify(result.map((value: display.Display): SdkDisplayInfo => {
      return new SdkDisplayInfo(value)
    }))
  }],
  ['ArkUI.display.getAllDisplayPhysicalResolution', async (_params: Map<string, string>): Promise<string> => {
    let result = await display.getAllDisplayPhysicalResolution()
    return JSON.stringify(result.map((value: display.DisplayPhysicalResolution): SdkDisplayPhysicalResolutionInfo => {
      return new SdkDisplayPhysicalResolutionInfo(value)
    }))
  }],
  ['ArkUI.display.getFoldStatus', async (_params: Map<string, string>): Promise<string> => {
    return display.getFoldStatus().toString()
  }],
  ['ArkUI.display.getFoldDisplayMode', async (_params: Map<string, string>): Promise<string> => {
    return display.getFoldDisplayMode().toString()
  }],
  ['ArkUI.display.getCurrentFoldCreaseRegion', async (_params: Map<string, string>): Promise<string> => {
    return JSON.stringify(new SdkFoldCreaseRegionInfo(display.getCurrentFoldCreaseRegion()))
  }],
  // generated by tools/generate-sdk-backend.py -- do not hand-edit below this line
  ['AVSessionKit.avSession.isDesktopLyricSupported', async (params: Map<string, string>): Promise<string> => {
    let result = await avSession.isDesktopLyricSupported()
    return result.toString()
  }],
  ['AVSessionKit.avSession.setDiscoverable', async (params: Map<string, string>): Promise<string> => {
    let enable = paramBoolean(params, 'enable', false)
    await avSession.setDiscoverable(enable)
    return 'ok'
  }],
  ['AVSessionKit.avSession.startDeviceLogging', async (params: Map<string, string>): Promise<string> => {
    let url = paramString(params, 'url', '')
    let maxSize = paramInt(params, 'maxSize', 0)
    await avSession.startDeviceLogging(url, maxSize)
    return 'ok'
  }],
  ['AVSessionKit.avSession.stopCastDeviceDiscovery', async (params: Map<string, string>): Promise<string> => {
    await avSession.stopCastDeviceDiscovery()
    return 'ok'
  }],
  ['AVSessionKit.avSession.stopDeviceLogging', async (params: Map<string, string>): Promise<string> => {
    await avSession.stopDeviceLogging()
    return 'ok'
  }],
  ['AbilityKit.abilityManager.isEmbeddedUIExtensionSupported', async (params: Map<string, string>): Promise<string> => {
    let result = abilityManager.isEmbeddedUIExtensionSupported()
    return result.toString()
  }],
  ['AbilityKit.abilityManager.setResidentProcessEnabled', async (params: Map<string, string>): Promise<string> => {
    let bundleName = paramString(params, 'bundleName', '')
    let enable = paramBoolean(params, 'enable', false)
    await abilityManager.setResidentProcessEnabled(bundleName, enable)
    return 'ok'
  }],
  ['AbilityKit.appManager.getAppMemorySize', async (params: Map<string, string>): Promise<string> => {
    let result = await appManager.getAppMemorySize()
    return result.toString()
  }],
  ['AbilityKit.appManager.getProcessMemoryByPid', async (params: Map<string, string>): Promise<string> => {
    let pid = paramInt(params, 'pid', 0)
    let result = await appManager.getProcessMemoryByPid(pid)
    return result.toString()
  }],
  ['AbilityKit.appManager.isRamConstrainedDevice', async (params: Map<string, string>): Promise<string> => {
    let result = await appManager.isRamConstrainedDevice()
    return result.toString()
  }],
  ['AbilityKit.appManager.isRunningInStabilityTest', async (params: Map<string, string>): Promise<string> => {
    let result = await appManager.isRunningInStabilityTest()
    return result.toString()
  }],
  ['AbilityKit.appRecovery.restartApp', async (params: Map<string, string>): Promise<string> => {
    appRecovery.restartApp()
    return 'ok'
  }],
  ['AbilityKit.appRecovery.saveAppState', async (params: Map<string, string>): Promise<string> => {
    let result = appRecovery.saveAppState()
    return result.toString()
  }],
  ['AbilityKit.application.demoteCurrentFromCandidateMasterProcess', async (params: Map<string, string>): Promise<string> => {
    await application.demoteCurrentFromCandidateMasterProcess()
    return 'ok'
  }],
  ['AbilityKit.application.exitMasterProcessRole', async (params: Map<string, string>): Promise<string> => {
    await application.exitMasterProcessRole()
    return 'ok'
  }],
  ['AbilityKit.application.promoteCurrentToCandidateMasterProcess', async (params: Map<string, string>): Promise<string> => {
    let insertToHead = paramBoolean(params, 'insertToHead', false)
    await application.promoteCurrentToCandidateMasterProcess(insertToHead)
    return 'ok'
  }],
  ['AbilityKit.autoStartupManager.getAutoStartupStatusForSelf', async (params: Map<string, string>): Promise<string> => {
    let result = await autoStartupManager.getAutoStartupStatusForSelf()
    return result.toString()
  }],
  ['AbilityKit.autoStartupManager.isAutoStartupSupported', async (params: Map<string, string>): Promise<string> => {
    let result = autoStartupManager.isAutoStartupSupported()
    return result.toString()
  }],
  ['AbilityKit.bundleManager.canOpenLink', async (params: Map<string, string>): Promise<string> => {
    let link = paramString(params, 'link', '')
    let result = bundleManager.canOpenLink(link)
    return result.toString()
  }],
  ['AbilityKit.bundleManager.cleanBundleCacheFilesForSelf', async (params: Map<string, string>): Promise<string> => {
    await bundleManager.cleanBundleCacheFilesForSelf()
    return 'ok'
  }],
  ['AbilityKit.bundleManager.getAdditionalInfo', async (params: Map<string, string>): Promise<string> => {
    let bundleName = paramString(params, 'bundleName', '')
    let result = bundleManager.getAdditionalInfo(bundleName)
    return result.toString()
  }],
  ['AbilityKit.bundleManager.getAllBundleCacheSize', async (params: Map<string, string>): Promise<string> => {
    let result = await bundleManager.getAllBundleCacheSize()
    return result.toString()
  }],
  ['AbilityKit.bundleManager.getApplicationLabel', async (params: Map<string, string>): Promise<string> => {
    let bundleName = paramString(params, 'bundleName', '')
    let appIndex = paramInt(params, 'appIndex', 0)
    let result = await bundleManager.getApplicationLabel(bundleName, appIndex)
    return result.toString()
  }],
  ['AbilityKit.bundleManager.getBundleNameByUid', async (params: Map<string, string>): Promise<string> => {
    let uid = paramInt(params, 'uid', 0)
    let result = await bundleManager.getBundleNameByUid(uid)
    return result.toString()
  }],
  ['AbilityKit.bundleManager.getBundleNameByUidSync', async (params: Map<string, string>): Promise<string> => {
    let uid = paramInt(params, 'uid', 0)
    let result = bundleManager.getBundleNameByUidSync(uid)
    return result.toString()
  }],
  ['AbilityKit.bundleManager.getDynamicIcon', async (params: Map<string, string>): Promise<string> => {
    let bundleName = paramString(params, 'bundleName', '')
    let result = await bundleManager.getDynamicIcon(bundleName)
    return result.toString()
  }],
  ['AbilityKit.bundleManager.getPluginBundlePathForSelf', async (params: Map<string, string>): Promise<string> => {
    let pluginBundleName = paramString(params, 'pluginBundleName', '')
    let result = bundleManager.getPluginBundlePathForSelf(pluginBundleName)
    return result.toString()
  }],
  ['AbilityKit.bundleManager.getSandboxDataDir', async (params: Map<string, string>): Promise<string> => {
    let bundleName = paramString(params, 'bundleName', '')
    let appIndex = paramInt(params, 'appIndex', 0)
    let result = bundleManager.getSandboxDataDir(bundleName, appIndex)
    return result.toString()
  }],
  ['AbilityKit.bundleManager.getSpecifiedDistributionType', async (params: Map<string, string>): Promise<string> => {
    let bundleName = paramString(params, 'bundleName', '')
    let result = bundleManager.getSpecifiedDistributionType(bundleName)
    return result.toString()
  }],
  ['AbilityKit.bundleManager.isApplicationEnabled', async (params: Map<string, string>): Promise<string> => {
    let bundleName = paramString(params, 'bundleName', '')
    let result = await bundleManager.isApplicationEnabled(bundleName)
    return result.toString()
  }],
  ['AbilityKit.bundleManager.isApplicationEnabledSync', async (params: Map<string, string>): Promise<string> => {
    let bundleName = paramString(params, 'bundleName', '')
    let result = bundleManager.isApplicationEnabledSync(bundleName)
    return result.toString()
  }],
  ['AbilityKit.bundleManager.setAdditionalInfo', async (params: Map<string, string>): Promise<string> => {
    let bundleName = paramString(params, 'bundleName', '')
    let additionalInfo = paramString(params, 'additionalInfo', '')
    bundleManager.setAdditionalInfo(bundleName, additionalInfo)
    return 'ok'
  }],
  ['AbilityKit.bundleManager.setAlternateIcon', async (params: Map<string, string>): Promise<string> => {
    let alternateIconName = paramString(params, 'alternateIconName', '')
    await bundleManager.setAlternateIcon(alternateIconName)
    return 'ok'
  }],
  ['AbilityKit.childProcessManager.isArkChildProcessSupported', async (params: Map<string, string>): Promise<string> => {
    let result = childProcessManager.isArkChildProcessSupported()
    return result.toString()
  }],
  ['AbilityKit.childProcessManager.isNativeChildProcessSupported', async (params: Map<string, string>): Promise<string> => {
    let result = childProcessManager.isNativeChildProcessSupported()
    return result.toString()
  }],
  ['AbilityKit.dataUriUtils.attachId', async (params: Map<string, string>): Promise<string> => {
    let uri = paramString(params, 'uri', '')
    let id = paramFloat(params, 'id', 0)
    let result = dataUriUtils.attachId(uri, id)
    return result.toString()
  }],
  ['AbilityKit.dataUriUtils.deleteId', async (params: Map<string, string>): Promise<string> => {
    let uri = paramString(params, 'uri', '')
    let result = dataUriUtils.deleteId(uri)
    return result.toString()
  }],
  ['AbilityKit.dataUriUtils.getId', async (params: Map<string, string>): Promise<string> => {
    let uri = paramString(params, 'uri', '')
    let result = dataUriUtils.getId(uri)
    return result.toString()
  }],
  ['AbilityKit.dataUriUtils.updateId', async (params: Map<string, string>): Promise<string> => {
    let uri = paramString(params, 'uri', '')
    let id = paramFloat(params, 'id', 0)
    let result = dataUriUtils.updateId(uri, id)
    return result.toString()
  }],
  ['AbilityKit.defaultAppManager.isDefaultApplication', async (params: Map<string, string>): Promise<string> => {
    let type = paramString(params, 'type', '')
    let result = await defaultAppManager.isDefaultApplication(type)
    return result.toString()
  }],
  ['AbilityKit.defaultAppManager.isDefaultApplicationSync', async (params: Map<string, string>): Promise<string> => {
    let type = paramString(params, 'type', '')
    let result = defaultAppManager.isDefaultApplicationSync(type)
    return result.toString()
  }],
  ['AbilityKit.distributedBundleManager.getRemoteBundleVersionCode', async (params: Map<string, string>): Promise<string> => {
    let deviceId = paramString(params, 'deviceId', '')
    let bundleName = paramString(params, 'bundleName', '')
    let result = await distributedBundleManager.getRemoteBundleVersionCode(deviceId, bundleName)
    return result.toString()
  }],
  ['AbilityKit.freeInstall.isHapModuleRemovable', async (params: Map<string, string>): Promise<string> => {
    let bundleName = paramString(params, 'bundleName', '')
    let moduleName = paramString(params, 'moduleName', '')
    let result = await freeInstall.isHapModuleRemovable(bundleName, moduleName)
    return result.toString()
  }],
  ['AbilityKit.hyperSnapManager.requestRebuildHyperSnap', async (params: Map<string, string>): Promise<string> => {
    hyperSnapManager.requestRebuildHyperSnap()
    return 'ok'
  }],
  ['AbilityKit.hyperSnapManager.setHyperSnapEnabled', async (params: Map<string, string>): Promise<string> => {
    let enableFlag = paramBoolean(params, 'enableFlag', false)
    hyperSnapManager.setHyperSnapEnabled(enableFlag)
    return 'ok'
  }],
  ['AbilityKit.overlay.setOverlayEnabled', async (params: Map<string, string>): Promise<string> => {
    let moduleName = paramString(params, 'moduleName', '')
    let isEnabled = paramBoolean(params, 'isEnabled', false)
    await overlay.setOverlayEnabled(moduleName, isEnabled)
    return 'ok'
  }],
  ['AbilityKit.quickFixManager.revokeQuickFix', async (params: Map<string, string>): Promise<string> => {
    let bundleName = paramString(params, 'bundleName', '')
    await quickFixManager.revokeQuickFix(bundleName)
    return 'ok'
  }],
  ['AbilityKit.shortcutManager.isShortcutSupported', async (params: Map<string, string>): Promise<string> => {
    let result = shortcutManager.isShortcutSupported()
    return result.toString()
  }],
  ['AbilityKit.shortcutManager.setShortcutVisibleForSelf', async (params: Map<string, string>): Promise<string> => {
    let id = paramString(params, 'id', '')
    let visible = paramBoolean(params, 'visible', false)
    await shortcutManager.setShortcutVisibleForSelf(id, visible)
    return 'ok'
  }],
  ['AbilityKit.startupManager.isStartupTaskInitialized', async (params: Map<string, string>): Promise<string> => {
    let startupTask = paramString(params, 'startupTask', '')
    let result = startupManager.isStartupTaskInitialized(startupTask)
    return result.toString()
  }],
  ['AbilityKit.startupManager.removeAllStartupTaskResults', async (params: Map<string, string>): Promise<string> => {
    startupManager.removeAllStartupTaskResults()
    return 'ok'
  }],
  ['AbilityKit.startupManager.removeStartupTaskResult', async (params: Map<string, string>): Promise<string> => {
    let startupTask = paramString(params, 'startupTask', '')
    startupManager.removeStartupTaskResult(startupTask)
    return 'ok'
  }],
  ['AbilityKit.uriPermissionManager.revokeUriPermission', async (params: Map<string, string>): Promise<string> => {
    let uri = paramString(params, 'uri', '')
    let targetBundleName = paramString(params, 'targetBundleName', '')
    await uriPermissionManager.revokeUriPermission(uri, targetBundleName)
    return 'ok'
  }],
  ['AbilityKit.wantAgent.setWantAgentMultithreading', async (params: Map<string, string>): Promise<string> => {
    let isMultithreadingSupported = paramBoolean(params, 'isMultithreadingSupported', false)
    wantAgent.setWantAgentMultithreading(isMultithreadingSupported)
    return 'ok'
  }],
  ['AccessibilityKit.accessibility.getSeniorModeStateForSelf', async (params: Map<string, string>): Promise<string> => {
    let result = await accessibility.getSeniorModeStateForSelf()
    return result.toString()
  }],
  ['AccessibilityKit.accessibility.getTouchModeSync', async (params: Map<string, string>): Promise<string> => {
    let result = accessibility.getTouchModeSync()
    return result.toString()
  }],
  ['AccessibilityKit.accessibility.isAnimationReduceEnabled', async (params: Map<string, string>): Promise<string> => {
    let result = await accessibility.isAnimationReduceEnabled()
    return result.toString()
  }],
  ['AccessibilityKit.accessibility.isAnimationReduceEnabledSync', async (params: Map<string, string>): Promise<string> => {
    let result = accessibility.isAnimationReduceEnabledSync()
    return result.toString()
  }],
  ['AccessibilityKit.accessibility.isAudioMonoEnabled', async (params: Map<string, string>): Promise<string> => {
    let result = await accessibility.isAudioMonoEnabled()
    return result.toString()
  }],
  ['AccessibilityKit.accessibility.isAudioMonoEnabledSync', async (params: Map<string, string>): Promise<string> => {
    let result = accessibility.isAudioMonoEnabledSync()
    return result.toString()
  }],
  ['AccessibilityKit.accessibility.isFlashReminderEnabled', async (params: Map<string, string>): Promise<string> => {
    let result = await accessibility.isFlashReminderEnabled()
    return result.toString()
  }],
  ['AccessibilityKit.accessibility.isFlashReminderEnabledSync', async (params: Map<string, string>): Promise<string> => {
    let result = accessibility.isFlashReminderEnabledSync()
    return result.toString()
  }],
  ['AccessibilityKit.accessibility.isOpenAccessibilitySync', async (params: Map<string, string>): Promise<string> => {
    let result = accessibility.isOpenAccessibilitySync()
    return result.toString()
  }],
  ['AccessibilityKit.accessibility.isOpenTouchGuideSync', async (params: Map<string, string>): Promise<string> => {
    let result = accessibility.isOpenTouchGuideSync()
    return result.toString()
  }],
  ['AccessibilityKit.accessibility.isScreenReaderOpenSync', async (params: Map<string, string>): Promise<string> => {
    let result = accessibility.isScreenReaderOpenSync()
    return result.toString()
  }],
  ['AccessibilityKit.accessibility.isSeniorModeEnabled', async (params: Map<string, string>): Promise<string> => {
    let result = await accessibility.isSeniorModeEnabled()
    return result.toString()
  }],
  ['AccessibilityKit.accessibility.setSeniorModeStateForSelf', async (params: Map<string, string>): Promise<string> => {
    let state = paramBoolean(params, 'state', false)
    await accessibility.setSeniorModeStateForSelf(state)
    return 'ok'
  }],
  ['AdsKit.identifier.resetOAID', async (params: Map<string, string>): Promise<string> => {
    identifier.resetOAID()
    return 'ok'
  }],
  ['ArkData.distributedDataObject.genSessionId', async (params: Map<string, string>): Promise<string> => {
    let result = distributedDataObject.genSessionId()
    return result.toString()
  }],
  ['ArkData.relationalStore.isVectorSupported', async (params: Map<string, string>): Promise<string> => {
    let result = relationalStore.isVectorSupported()
    return result.toString()
  }],
  ['ArkData.uniformTypeDescriptor.getUniformDataTypeByFilenameExtension', async (params: Map<string, string>): Promise<string> => {
    let filenameExtension = paramString(params, 'filenameExtension', '')
    let belongsTo = paramString(params, 'belongsTo', '')
    let result = uniformTypeDescriptor.getUniformDataTypeByFilenameExtension(filenameExtension, belongsTo)
    return result.toString()
  }],
  ['ArkData.uniformTypeDescriptor.getUniformDataTypeByMIMEType', async (params: Map<string, string>): Promise<string> => {
    let mimeType = paramString(params, 'mimeType', '')
    let belongsTo = paramString(params, 'belongsTo', '')
    let result = uniformTypeDescriptor.getUniformDataTypeByMIMEType(mimeType, belongsTo)
    return result.toString()
  }],
  ['ArkTS.buffer.isEncoding', async (params: Map<string, string>): Promise<string> => {
    let encoding = paramString(params, 'encoding', '')
    let result = buffer.isEncoding(encoding)
    return result.toString()
  }],
  ['ArkTS.fastbuffer.isEncoding', async (params: Map<string, string>): Promise<string> => {
    let encoding = paramString(params, 'encoding', '')
    let result = fastbuffer.isEncoding(encoding)
    return result.toString()
  }],
  ['ArkTS.process.abort', async (params: Map<string, string>): Promise<string> => {
    process.abort()
    return 'ok'
  }],
  ['ArkTS.process.chdir', async (params: Map<string, string>): Promise<string> => {
    let dir = paramString(params, 'dir', '')
    process.chdir(dir)
    return 'ok'
  }],
  ['ArkTS.process.cwd', async (params: Map<string, string>): Promise<string> => {
    let result = process.cwd()
    return result.toString()
  }],
  ['ArkTS.process.getPastCpuTime', async (params: Map<string, string>): Promise<string> => {
    let result = process.getPastCpuTime()
    return result.toString()
  }],
  ['ArkTS.process.getStartRealtime', async (params: Map<string, string>): Promise<string> => {
    let result = process.getStartRealtime()
    return result.toString()
  }],
  ['ArkTS.process.is64Bit', async (params: Map<string, string>): Promise<string> => {
    let result = process.is64Bit()
    return result.toString()
  }],
  ['ArkTS.process.isIsolatedProcess', async (params: Map<string, string>): Promise<string> => {
    let result = process.isIsolatedProcess()
    return result.toString()
  }],
  ['ArkTS.process.off', async (params: Map<string, string>): Promise<string> => {
    let type = paramString(params, 'type', '')
    let result = process.off(type)
    return result.toString()
  }],
  ['ArkTS.process.uptime', async (params: Map<string, string>): Promise<string> => {
    let result = process.uptime()
    return result.toString()
  }],
  ['ArkTS.taskpool.cancel', async (params: Map<string, string>): Promise<string> => {
    let taskId = paramFloat(params, 'taskId', 0)
    taskpool.cancel(taskId)
    return 'ok'
  }],
  ['ArkTS.util.errnoToString', async (params: Map<string, string>): Promise<string> => {
    let errno = paramFloat(params, 'errno', 0)
    let result = util.errnoToString(errno)
    return result.toString()
  }],
  ['ArkTS.util.generateRandomUUID', async (params: Map<string, string>): Promise<string> => {
    let entropyCache = paramBoolean(params, 'entropyCache', false)
    let result = util.generateRandomUUID(entropyCache)
    return result.toString()
  }],
  ['ArkTS.util.getMainThreadStackTrace', async (params: Map<string, string>): Promise<string> => {
    let result = util.getMainThreadStackTrace()
    return result.toString()
  }],
  ['ArkUI.PiPWindow.isPiPEnabled', async (params: Map<string, string>): Promise<string> => {
    let result = PiPWindow.isPiPEnabled()
    return result.toString()
  }],
  ['ArkUI.display.hasPrivateWindow', async (params: Map<string, string>): Promise<string> => {
    let displayId = paramInt(params, 'displayId', 0)
    let result = display.hasPrivateWindow(displayId)
    return result.toString()
  }],
  ['ArkUI.display.isCaptured', async (params: Map<string, string>): Promise<string> => {
    let result = display.isCaptured()
    return result.toString()
  }],
  ['ArkUI.display.isFoldable', async (params: Map<string, string>): Promise<string> => {
    let result = display.isFoldable()
    return result.toString()
  }],
  ['ArkUI.display.removeVirtualScreenSurface', async (params: Map<string, string>): Promise<string> => {
    let screenId = paramInt(params, 'screenId', 0)
    let surfaceId = paramString(params, 'surfaceId', '')
    await display.removeVirtualScreenSurface(screenId, surfaceId)
    return 'ok'
  }],
  ['ArkUI.display.setFoldStatusLocked', async (params: Map<string, string>): Promise<string> => {
    let locked = paramBoolean(params, 'locked', false)
    display.setFoldStatusLocked(locked)
    return 'ok'
  }],
  ['ArkUI.floatView.isFloatViewEnabled', async (params: Map<string, string>): Promise<string> => {
    let result = floatView.isFloatViewEnabled()
    return result.toString()
  }],
  ['ArkUI.floatingBall.isFloatingBallEnabled', async (params: Map<string, string>): Promise<string> => {
    let result = floatingBall.isFloatingBallEnabled()
    return result.toString()
  }],
  ['ArkUI.performanceMonitor.end', async (params: Map<string, string>): Promise<string> => {
    let scene = paramString(params, 'scene', '')
    performanceMonitor.end(scene)
    return 'ok'
  }],
  ['ArkUI.promptAction.closeToast', async (params: Map<string, string>): Promise<string> => {
    let toastId = paramFloat(params, 'toastId', 0)
    promptAction.closeToast(toastId)
    return 'ok'
  }],
  ['ArkUI.screen.destroyVirtualScreen', async (params: Map<string, string>): Promise<string> => {
    let screenId = paramInt(params, 'screenId', 0)
    await screen.destroyVirtualScreen(screenId)
    return 'ok'
  }],
  ['ArkUI.screen.isScreenRotationLocked', async (params: Map<string, string>): Promise<string> => {
    let result = await screen.isScreenRotationLocked()
    return result.toString()
  }],
  ['ArkUI.screen.setScreenRotationLocked', async (params: Map<string, string>): Promise<string> => {
    let isLocked = paramBoolean(params, 'isLocked', false)
    await screen.setScreenRotationLocked(isLocked)
    return 'ok'
  }],
  ['ArkUI.window.getGlobalWindowMode', async (params: Map<string, string>): Promise<string> => {
    let displayId = paramInt(params, 'displayId', 0)
    let result = await window.getGlobalWindowMode(displayId)
    return result.toString()
  }],
  ['ArkUI.window.getTopNavDestinationName', async (params: Map<string, string>): Promise<string> => {
    let windowId = paramInt(params, 'windowId', 0)
    let result = await window.getTopNavDestinationName(windowId)
    return result.toString()
  }],
  ['ArkUI.window.minimizeAll', async (params: Map<string, string>): Promise<string> => {
    let id = paramInt(params, 'id', 0)
    await window.minimizeAll(id)
    return 'ok'
  }],
  ['ArkUI.window.minimizeAllWithExclusion', async (params: Map<string, string>): Promise<string> => {
    let displayId = paramInt(params, 'displayId', 0)
    let excludeWindowId = paramInt(params, 'excludeWindowId', 0)
    await window.minimizeAllWithExclusion(displayId, excludeWindowId)
    return 'ok'
  }],
  ['ArkUI.window.setGestureNavigationEnabled', async (params: Map<string, string>): Promise<string> => {
    let enable = paramBoolean(params, 'enable', false)
    await window.setGestureNavigationEnabled(enable)
    return 'ok'
  }],
  ['ArkUI.window.shiftAppWindowFocus', async (params: Map<string, string>): Promise<string> => {
    let sourceWindowId = paramInt(params, 'sourceWindowId', 0)
    let targetWindowId = paramInt(params, 'targetWindowId', 0)
    await window.shiftAppWindowFocus(sourceWindowId, targetWindowId)
    return 'ok'
  }],
  ['ArkUI.window.shiftAppWindowPointerEvent', async (params: Map<string, string>): Promise<string> => {
    let sourceWindowId = paramInt(params, 'sourceWindowId', 0)
    let targetWindowId = paramInt(params, 'targetWindowId', 0)
    await window.shiftAppWindowPointerEvent(sourceWindowId, targetWindowId)
    return 'ok'
  }],
  ['ArkUI.window.toggleShownStateForAllAppWindows', async (params: Map<string, string>): Promise<string> => {
    await window.toggleShownStateForAllAppWindows()
    return 'ok'
  }],
  ['BackgroundTasksKit.backgroundProcessManager.resetProcessPriority', async (params: Map<string, string>): Promise<string> => {
    let pid = paramInt(params, 'pid', 0)
    await backgroundProcessManager.resetProcessPriority(pid)
    return 'ok'
  }],
  ['BackgroundTasksKit.backgroundTaskManager.cancelSuspendDelay', async (params: Map<string, string>): Promise<string> => {
    let requestId = paramInt(params, 'requestId', 0)
    backgroundTaskManager.cancelSuspendDelay(requestId)
    return 'ok'
  }],
  ['BackgroundTasksKit.backgroundTaskManager.getRemainingDelayTime', async (params: Map<string, string>): Promise<string> => {
    let requestId = paramInt(params, 'requestId', 0)
    let result = await backgroundTaskManager.getRemainingDelayTime(requestId)
    return result.toString()
  }],
  ['BackgroundTasksKit.backgroundTaskManager.resetAllEfficiencyResources', async (params: Map<string, string>): Promise<string> => {
    backgroundTaskManager.resetAllEfficiencyResources()
    return 'ok'
  }],
  ['BackgroundTasksKit.reminderAgentManager.cancelAllReminders', async (params: Map<string, string>): Promise<string> => {
    await reminderAgentManager.cancelAllReminders()
    return 'ok'
  }],
  ['BackgroundTasksKit.reminderAgentManager.cancelReminder', async (params: Map<string, string>): Promise<string> => {
    let reminderId = paramInt(params, 'reminderId', 0)
    await reminderAgentManager.cancelReminder(reminderId)
    return 'ok'
  }],
  ['BackgroundTasksKit.reminderAgentManager.cancelReminderOnDisplay', async (params: Map<string, string>): Promise<string> => {
    let reminderId = paramInt(params, 'reminderId', 0)
    await reminderAgentManager.cancelReminderOnDisplay(reminderId)
    return 'ok'
  }],
  ['BackgroundTasksKit.reminderAgentManager.deleteExcludeDates', async (params: Map<string, string>): Promise<string> => {
    let reminderId = paramInt(params, 'reminderId', 0)
    await reminderAgentManager.deleteExcludeDates(reminderId)
    return 'ok'
  }],
  ['BackgroundTasksKit.workScheduler.isLastWorkTimeOut', async (params: Map<string, string>): Promise<string> => {
    let workId = paramInt(params, 'workId', 0)
    let result = await workScheduler.isLastWorkTimeOut(workId)
    return result.toString()
  }],
  ['BackgroundTasksKit.workScheduler.stopAndClearWorks', async (params: Map<string, string>): Promise<string> => {
    workScheduler.stopAndClearWorks()
    return 'ok'
  }],
  ['BasicServicesKit.batteryInfo.getBatteryConfig', async (params: Map<string, string>): Promise<string> => {
    let sceneName = paramString(params, 'sceneName', '')
    let result = batteryInfo.getBatteryConfig(sceneName)
    return result.toString()
  }],
  ['BasicServicesKit.batteryInfo.isBatteryConfigSupported', async (params: Map<string, string>): Promise<string> => {
    let sceneName = paramString(params, 'sceneName', '')
    let result = batteryInfo.isBatteryConfigSupported(sceneName)
    return result.toString()
  }],
  ['BasicServicesKit.batteryInfo.setBatteryConfig', async (params: Map<string, string>): Promise<string> => {
    let sceneName = paramString(params, 'sceneName', '')
    let sceneValue = paramString(params, 'sceneValue', '')
    let result = batteryInfo.setBatteryConfig(sceneName, sceneValue)
    return result.toString()
  }],
  ['BasicServicesKit.batteryStats.getAppPowerPercent', async (params: Map<string, string>): Promise<string> => {
    let uid = paramInt(params, 'uid', 0)
    let result = batteryStats.getAppPowerPercent(uid)
    return result.toString()
  }],
  ['BasicServicesKit.batteryStats.getAppPowerValue', async (params: Map<string, string>): Promise<string> => {
    let uid = paramInt(params, 'uid', 0)
    let result = batteryStats.getAppPowerValue(uid)
    return result.toString()
  }],
  ['BasicServicesKit.brightness.setValue', async (params: Map<string, string>): Promise<string> => {
    let value = paramInt(params, 'value', 0)
    brightness.setValue(value)
    return 'ok'
  }],
  ['BasicServicesKit.cacheDownload.cancel', async (params: Map<string, string>): Promise<string> => {
    let url = paramString(params, 'url', '')
    cacheDownload.cancel(url)
    return 'ok'
  }],
  ['BasicServicesKit.cacheDownload.clearFileCache', async (params: Map<string, string>): Promise<string> => {
    cacheDownload.clearFileCache()
    return 'ok'
  }],
  ['BasicServicesKit.cacheDownload.clearMemoryCache', async (params: Map<string, string>): Promise<string> => {
    cacheDownload.clearMemoryCache()
    return 'ok'
  }],
  ['BasicServicesKit.cacheDownload.setDownloadInfoListSize', async (params: Map<string, string>): Promise<string> => {
    let size = paramInt(params, 'size', 0)
    cacheDownload.setDownloadInfoListSize(size)
    return 'ok'
  }],
  ['BasicServicesKit.cacheDownload.setFileCacheSize', async (params: Map<string, string>): Promise<string> => {
    let bytes = paramInt(params, 'bytes', 0)
    cacheDownload.setFileCacheSize(bytes)
    return 'ok'
  }],
  ['BasicServicesKit.cacheDownload.setMemoryCacheSize', async (params: Map<string, string>): Promise<string> => {
    let bytes = paramInt(params, 'bytes', 0)
    cacheDownload.setMemoryCacheSize(bytes)
    return 'ok'
  }],
  ['BasicServicesKit.commonEventManager.setStaticSubscriberState', async (params: Map<string, string>): Promise<string> => {
    let enable = paramBoolean(params, 'enable', false)
    await commonEventManager.setStaticSubscriberState(enable)
    return 'ok'
  }],
  ['BasicServicesKit.configPolicy.getOneCfgFile', async (params: Map<string, string>): Promise<string> => {
    let relPath = paramString(params, 'relPath', '')
    let result = await configPolicy.getOneCfgFile(relPath)
    return result.toString()
  }],
  ['BasicServicesKit.customConfig.getChannelId', async (params: Map<string, string>): Promise<string> => {
    let result = customConfig.getChannelId()
    return result.toString()
  }],
  ['BasicServicesKit.emitter.emit', async (params: Map<string, string>): Promise<string> => {
    let eventId = paramString(params, 'eventId', '')
    emitter.emit(eventId)
    return 'ok'
  }],
  ['BasicServicesKit.emitter.off', async (params: Map<string, string>): Promise<string> => {
    let eventId = paramInt(params, 'eventId', 0)
    emitter.off(eventId)
    return 'ok'
  }],
  ['BasicServicesKit.osAccount.isDomainAccountSupported', async (params: Map<string, string>): Promise<string> => {
    let result = await osAccount.isDomainAccountSupported()
    return result.toString()
  }],
  ['BasicServicesKit.power.isActive', async (params: Map<string, string>): Promise<string> => {
    let result = power.isActive()
    return result.toString()
  }],
  ['BasicServicesKit.power.isStandby', async (params: Map<string, string>): Promise<string> => {
    let result = power.isStandby()
    return result.toString()
  }],
  ['BasicServicesKit.screenLock.isDeviceLocked', async (params: Map<string, string>): Promise<string> => {
    let userId = paramInt(params, 'userId', 0)
    let result = screenLock.isDeviceLocked(userId)
    return result.toString()
  }],
  ['BasicServicesKit.screenLock.isLocked', async (params: Map<string, string>): Promise<string> => {
    let result = screenLock.isLocked()
    return result.toString()
  }],
  ['BasicServicesKit.screenLock.unlock', async (params: Map<string, string>): Promise<string> => {
    let result = await screenLock.unlock()
    return result.toString()
  }],
  ['BasicServicesKit.selectionManager.getSelectionContent', async (params: Map<string, string>): Promise<string> => {
    let result = await selectionManager.getSelectionContent()
    return result.toString()
  }],
  ['BasicServicesKit.serial.addPortAuthorization', async (params: Map<string, string>): Promise<string> => {
    let tokenId = paramString(params, 'tokenId', '')
    let deviceId = paramString(params, 'deviceId', '')
    await serial.addPortAuthorization(tokenId, deviceId)
    return 'ok'
  }],
  ['BasicServicesKit.serialManager.cancelSerialRight', async (params: Map<string, string>): Promise<string> => {
    let portId = paramInt(params, 'portId', 0)
    serialManager.cancelSerialRight(portId)
    return 'ok'
  }],
  ['BasicServicesKit.serialManager.close', async (params: Map<string, string>): Promise<string> => {
    let portId = paramInt(params, 'portId', 0)
    serialManager.close(portId)
    return 'ok'
  }],
  ['BasicServicesKit.serialManager.hasSerialRight', async (params: Map<string, string>): Promise<string> => {
    let portId = paramInt(params, 'portId', 0)
    let result = serialManager.hasSerialRight(portId)
    return result.toString()
  }],
  ['BasicServicesKit.serialManager.open', async (params: Map<string, string>): Promise<string> => {
    let portId = paramInt(params, 'portId', 0)
    serialManager.open(portId)
    return 'ok'
  }],
  ['BasicServicesKit.serialManager.requestSerialRight', async (params: Map<string, string>): Promise<string> => {
    let portId = paramInt(params, 'portId', 0)
    let result = await serialManager.requestSerialRight(portId)
    return result.toString()
  }],
  ['BasicServicesKit.settings.isDoubleClickAppForSelf', async (params: Map<string, string>): Promise<string> => {
    let result = await settings.isDoubleClickAppForSelf()
    return result.toString()
  }],
  ['BasicServicesKit.systemCapability.querySystemCapabilities', async (params: Map<string, string>): Promise<string> => {
    let result = await systemCapability.querySystemCapabilities()
    return result.toString()
  }],
  ['BasicServicesKit.systemDateTime.getAutoTimeStatus', async (params: Map<string, string>): Promise<string> => {
    let result = systemDateTime.getAutoTimeStatus()
    return result.toString()
  }],
  ['BasicServicesKit.systemDateTime.getNtpTime', async (params: Map<string, string>): Promise<string> => {
    let result = systemDateTime.getNtpTime()
    return result.toString()
  }],
  ['BasicServicesKit.systemDateTime.getTime', async (params: Map<string, string>): Promise<string> => {
    let isNanoseconds = paramBoolean(params, 'isNanoseconds', false)
    let result = systemDateTime.getTime(isNanoseconds)
    return result.toString()
  }],
  ['BasicServicesKit.systemDateTime.getTimezone', async (params: Map<string, string>): Promise<string> => {
    let result = await systemDateTime.getTimezone()
    return result.toString()
  }],
  ['BasicServicesKit.systemDateTime.getTimezoneSync', async (params: Map<string, string>): Promise<string> => {
    let result = systemDateTime.getTimezoneSync()
    return result.toString()
  }],
  ['BasicServicesKit.systemDateTime.updateNtpTime', async (params: Map<string, string>): Promise<string> => {
    await systemDateTime.updateNtpTime()
    return 'ok'
  }],
  ['BasicServicesKit.systemParameterEnhance.getSync', async (params: Map<string, string>): Promise<string> => {
    let key = paramString(params, 'key', '')
    let def = paramString(params, 'def', '')
    let result = systemParameterEnhance.getSync(key, def)
    return result.toString()
  }],
  ['BasicServicesKit.systemParameterEnhance.setSync', async (params: Map<string, string>): Promise<string> => {
    let key = paramString(params, 'key', '')
    let value = paramString(params, 'value', '')
    systemParameterEnhance.setSync(key, value)
    return 'ok'
  }],
  ['BasicServicesKit.systemTimer.destroyTimer', async (params: Map<string, string>): Promise<string> => {
    let timer = paramInt(params, 'timer', 0)
    await systemTimer.destroyTimer(timer)
    return 'ok'
  }],
  ['BasicServicesKit.systemTimer.startTimer', async (params: Map<string, string>): Promise<string> => {
    let timer = paramInt(params, 'timer', 0)
    let triggerTime = paramInt(params, 'triggerTime', 0)
    await systemTimer.startTimer(timer, triggerTime)
    return 'ok'
  }],
  ['BasicServicesKit.systemTimer.stopTimer', async (params: Map<string, string>): Promise<string> => {
    let timer = paramInt(params, 'timer', 0)
    await systemTimer.stopTimer(timer)
    return 'ok'
  }],
  ['BasicServicesKit.usbManager.hasRight', async (params: Map<string, string>): Promise<string> => {
    let deviceName = paramString(params, 'deviceName', '')
    let result = usbManager.hasRight(deviceName)
    return result.toString()
  }],
  ['BasicServicesKit.usbManager.removeRight', async (params: Map<string, string>): Promise<string> => {
    let deviceName = paramString(params, 'deviceName', '')
    let result = usbManager.removeRight(deviceName)
    return result.toString()
  }],
  ['BasicServicesKit.usbManager.requestRight', async (params: Map<string, string>): Promise<string> => {
    let deviceName = paramString(params, 'deviceName', '')
    let result = await usbManager.requestRight(deviceName)
    return result.toString()
  }],
  ['BasicServicesKit.wallpaper.getMinHeightSync', async (params: Map<string, string>): Promise<string> => {
    let result = wallpaper.getMinHeightSync()
    return result.toString()
  }],
  ['BasicServicesKit.wallpaper.getMinWidthSync', async (params: Map<string, string>): Promise<string> => {
    let result = wallpaper.getMinWidthSync()
    return result.toString()
  }],
  ['BasicServicesKit.zlib.getOriginalSize', async (params: Map<string, string>): Promise<string> => {
    let compressedFile = paramString(params, 'compressedFile', '')
    let result = await zlib.getOriginalSize(compressedFile)
    return result.toString()
  }],
  ['ConnectivityKit.access.convertUuid', async (params: Map<string, string>): Promise<string> => {
    let uuid = paramString(params, 'uuid', '')
    let result = access.convertUuid(uuid)
    return result.toString()
  }],
  ['ConnectivityKit.access.isBluetoothSupported', async (params: Map<string, string>): Promise<string> => {
    let result = access.isBluetoothSupported()
    return result.toString()
  }],
  ['ConnectivityKit.connection.getCarKeyDfxData', async (params: Map<string, string>): Promise<string> => {
    let result = bluetoothConnection.getCarKeyDfxData()
    return result.toString()
  }],
  ['ConnectivityKit.connection.getLastConnectionTime', async (params: Map<string, string>): Promise<string> => {
    let deviceId = paramString(params, 'deviceId', '')
    let result = await bluetoothConnection.getLastConnectionTime(deviceId)
    return result.toString()
  }],
  ['ConnectivityKit.nfcController.isNfcOpen', async (params: Map<string, string>): Promise<string> => {
    let result = nfcController.isNfcOpen()
    return result.toString()
  }],
  ['ConnectivityKit.partnerAgent.isPartnerAgentSupported', async (params: Map<string, string>): Promise<string> => {
    let result = partnerAgent.isPartnerAgentSupported()
    return result.toString()
  }],
  ['ConnectivityKit.ranging.isRangingSupported', async (params: Map<string, string>): Promise<string> => {
    let result = ranging.isRangingSupported()
    return result.toString()
  }],
  ['ConnectivityKit.socket.getDeviceId', async (params: Map<string, string>): Promise<string> => {
    let clientSocket = paramInt(params, 'clientSocket', 0)
    let result = socket.getDeviceId(clientSocket)
    return result.toString()
  }],
  ['ConnectivityKit.socket.getL2capPsm', async (params: Map<string, string>): Promise<string> => {
    let serverSocket = paramInt(params, 'serverSocket', 0)
    let result = socket.getL2capPsm(serverSocket)
    return result.toString()
  }],
  ['ConnectivityKit.socket.getMaxReceiveDataSize', async (params: Map<string, string>): Promise<string> => {
    let clientSocket = paramInt(params, 'clientSocket', 0)
    let result = socket.getMaxReceiveDataSize(clientSocket)
    return result.toString()
  }],
  ['ConnectivityKit.socket.getMaxTransmitDataSize', async (params: Map<string, string>): Promise<string> => {
    let clientSocket = paramInt(params, 'clientSocket', 0)
    let result = socket.getMaxTransmitDataSize(clientSocket)
    return result.toString()
  }],
  ['ConnectivityKit.socket.isConnected', async (params: Map<string, string>): Promise<string> => {
    let clientSocket = paramInt(params, 'clientSocket', 0)
    let result = socket.isConnected(clientSocket)
    return result.toString()
  }],
  ['ConnectivityKit.socket.sppCloseClientSocket', async (params: Map<string, string>): Promise<string> => {
    let socket_ = paramInt(params, 'socket', 0)
    socket.sppCloseClientSocket(socket_)
    return 'ok'
  }],
  ['ConnectivityKit.socket.sppCloseServerSocket', async (params: Map<string, string>): Promise<string> => {
    let socket_ = paramInt(params, 'socket', 0)
    socket.sppCloseServerSocket(socket_)
    return 'ok'
  }],
  ['ConnectivityKit.wifiManager.allowAutoConnect', async (params: Map<string, string>): Promise<string> => {
    let netId = paramInt(params, 'netId', 0)
    let isAllowed = paramBoolean(params, 'isAllowed', false)
    wifiManager.allowAutoConnect(netId, isAllowed)
    return 'ok'
  }],
  ['ConnectivityKit.wifiManager.connectToCandidateConfig', async (params: Map<string, string>): Promise<string> => {
    let networkId = paramInt(params, 'networkId', 0)
    wifiManager.connectToCandidateConfig(networkId)
    return 'ok'
  }],
  ['ConnectivityKit.wifiManager.connectToCandidateConfigWithUserAction', async (params: Map<string, string>): Promise<string> => {
    let networkId = paramInt(params, 'networkId', 0)
    await wifiManager.connectToCandidateConfigWithUserAction(networkId)
    return 'ok'
  }],
  ['ConnectivityKit.wifiManager.deletePersistentGroup', async (params: Map<string, string>): Promise<string> => {
    let netId = paramInt(params, 'netId', 0)
    wifiManager.deletePersistentGroup(netId)
    return 'ok'
  }],
  ['ConnectivityKit.wifiManager.disableNetwork', async (params: Map<string, string>): Promise<string> => {
    let netId = paramInt(params, 'netId', 0)
    wifiManager.disableNetwork(netId)
    return 'ok'
  }],
  ['ConnectivityKit.wifiManager.disableWifi', async (params: Map<string, string>): Promise<string> => {
    wifiManager.disableWifi()
    return 'ok'
  }],
  ['ConnectivityKit.wifiManager.disconnect', async (params: Map<string, string>): Promise<string> => {
    wifiManager.disconnect()
    return 'ok'
  }],
  ['ConnectivityKit.wifiManager.enableSemiWifi', async (params: Map<string, string>): Promise<string> => {
    wifiManager.enableSemiWifi()
    return 'ok'
  }],
  ['ConnectivityKit.wifiManager.enableWifi', async (params: Map<string, string>): Promise<string> => {
    wifiManager.enableWifi()
    return 'ok'
  }],
  ['ConnectivityKit.wifiManager.factoryReset', async (params: Map<string, string>): Promise<string> => {
    wifiManager.factoryReset()
    return 'ok'
  }],
  ['ConnectivityKit.wifiManager.getCountryCode', async (params: Map<string, string>): Promise<string> => {
    let result = wifiManager.getCountryCode()
    return result.toString()
  }],
  ['ConnectivityKit.wifiManager.getScanAlwaysAllowed', async (params: Map<string, string>): Promise<string> => {
    let result = wifiManager.getScanAlwaysAllowed()
    return result.toString()
  }],
  ['ConnectivityKit.wifiManager.getSignalLevel', async (params: Map<string, string>): Promise<string> => {
    let rssi = paramInt(params, 'rssi', 0)
    let band = paramInt(params, 'band', 0)
    let result = wifiManager.getSignalLevel(rssi, band)
    return result.toString()
  }],
  ['ConnectivityKit.wifiManager.getSupportedFeatures', async (params: Map<string, string>): Promise<string> => {
    let result = wifiManager.getSupportedFeatures()
    return result.toString()
  }],
  ['ConnectivityKit.wifiManager.isConnected', async (params: Map<string, string>): Promise<string> => {
    let result = wifiManager.isConnected()
    return result.toString()
  }],
  ['ConnectivityKit.wifiManager.isFeatureSupported', async (params: Map<string, string>): Promise<string> => {
    let featureId = paramInt(params, 'featureId', 0)
    let result = wifiManager.isFeatureSupported(featureId)
    return result.toString()
  }],
  ['ConnectivityKit.wifiManager.isHotspotActive', async (params: Map<string, string>): Promise<string> => {
    let result = wifiManager.isHotspotActive()
    return result.toString()
  }],
  ['ConnectivityKit.wifiManager.isHotspotDualBandSupported', async (params: Map<string, string>): Promise<string> => {
    let result = wifiManager.isHotspotDualBandSupported()
    return result.toString()
  }],
  ['ConnectivityKit.wifiManager.isMeteredHotspot', async (params: Map<string, string>): Promise<string> => {
    let result = wifiManager.isMeteredHotspot()
    return result.toString()
  }],
  ['ConnectivityKit.wifiManager.isOpenSoftApAllowed', async (params: Map<string, string>): Promise<string> => {
    let result = wifiManager.isOpenSoftApAllowed()
    return result.toString()
  }],
  ['ConnectivityKit.wifiManager.isRandomMacDisabled', async (params: Map<string, string>): Promise<string> => {
    let result = wifiManager.isRandomMacDisabled()
    return result.toString()
  }],
  ['ConnectivityKit.wifiManager.isWifiActive', async (params: Map<string, string>): Promise<string> => {
    let result = wifiManager.isWifiActive()
    return result.toString()
  }],
  ['ConnectivityKit.wifiManager.isWlanSupported', async (params: Map<string, string>): Promise<string> => {
    let result = wifiManager.isWlanSupported()
    return result.toString()
  }],
  ['ConnectivityKit.wifiManager.p2pCancelConnect', async (params: Map<string, string>): Promise<string> => {
    wifiManager.p2pCancelConnect()
    return 'ok'
  }],
  ['ConnectivityKit.wifiManager.reassociate', async (params: Map<string, string>): Promise<string> => {
    wifiManager.reassociate()
    return 'ok'
  }],
  ['ConnectivityKit.wifiManager.reconnect', async (params: Map<string, string>): Promise<string> => {
    wifiManager.reconnect()
    return 'ok'
  }],
  ['ConnectivityKit.wifiManager.removeAllNetwork', async (params: Map<string, string>): Promise<string> => {
    wifiManager.removeAllNetwork()
    return 'ok'
  }],
  ['ConnectivityKit.wifiManager.removeCandidateConfig', async (params: Map<string, string>): Promise<string> => {
    let networkId = paramInt(params, 'networkId', 0)
    await wifiManager.removeCandidateConfig(networkId)
    return 'ok'
  }],
  ['ConnectivityKit.wifiManager.removeDevice', async (params: Map<string, string>): Promise<string> => {
    let id = paramInt(params, 'id', 0)
    wifiManager.removeDevice(id)
    return 'ok'
  }],
  ['ConnectivityKit.wifiManager.removeGroup', async (params: Map<string, string>): Promise<string> => {
    wifiManager.removeGroup()
    return 'ok'
  }],
  ['ConnectivityKit.wifiManager.setDeviceName', async (params: Map<string, string>): Promise<string> => {
    let devName = paramString(params, 'devName', '')
    wifiManager.setDeviceName(devName)
    return 'ok'
  }],
  ['ConnectivityKit.wifiManager.setScanAlwaysAllowed', async (params: Map<string, string>): Promise<string> => {
    let isScanAlwaysAllowed = paramBoolean(params, 'isScanAlwaysAllowed', false)
    wifiManager.setScanAlwaysAllowed(isScanAlwaysAllowed)
    return 'ok'
  }],
  ['ConnectivityKit.wifiManager.startDiscoverDevices', async (params: Map<string, string>): Promise<string> => {
    wifiManager.startDiscoverDevices()
    return 'ok'
  }],
  ['ConnectivityKit.wifiManager.startPortalCertification', async (params: Map<string, string>): Promise<string> => {
    wifiManager.startPortalCertification()
    return 'ok'
  }],
  ['ConnectivityKit.wifiManager.startScan', async (params: Map<string, string>): Promise<string> => {
    wifiManager.startScan()
    return 'ok'
  }],
  ['ConnectivityKit.wifiManager.startWifiDetection', async (params: Map<string, string>): Promise<string> => {
    wifiManager.startWifiDetection()
    return 'ok'
  }],
  ['ConnectivityKit.wifiManager.stopDiscoverDevices', async (params: Map<string, string>): Promise<string> => {
    wifiManager.stopDiscoverDevices()
    return 'ok'
  }],
  ['CoreFileKit.Environment.getStorageDataDir', async (params: Map<string, string>): Promise<string> => {
    let result = await Environment.getStorageDataDir()
    return result.toString()
  }],
  ['CoreFileKit.Environment.getUserDataDir', async (params: Map<string, string>): Promise<string> => {
    let result = await Environment.getUserDataDir()
    return result.toString()
  }],
  ['CoreFileKit.cloudSync.unregisterChange', async (params: Map<string, string>): Promise<string> => {
    let uri = paramString(params, 'uri', '')
    cloudSync.unregisterChange(uri)
    return 'ok'
  }],
  ['CoreFileKit.cloudSyncManager.notifyDataChange', async (params: Map<string, string>): Promise<string> => {
    let accountId = paramString(params, 'accountId', '')
    let bundleName = paramString(params, 'bundleName', '')
    await cloudSyncManager.notifyDataChange(accountId, bundleName)
    return 'ok'
  }],
  ['CoreFileKit.fileUri.getUriFromPath', async (params: Map<string, string>): Promise<string> => {
    let path = paramString(params, 'path', '')
    let result = fileUri.getUriFromPath(path)
    return result.toString()
  }],
  ['CoreFileKit.hash.hash', async (params: Map<string, string>): Promise<string> => {
    let path = paramString(params, 'path', '')
    let algorithm = paramString(params, 'algorithm', '')
    let result = await hash.hash(path, algorithm)
    return result.toString()
  }],
  ['CoreFileKit.keyManager.deactivateUserKey', async (params: Map<string, string>): Promise<string> => {
    let userId = paramInt(params, 'userId', 0)
    keyManager.deactivateUserKey(userId)
    return 'ok'
  }],
  ['CoreFileKit.securityLabel.getSecurityLabel', async (params: Map<string, string>): Promise<string> => {
    let path = paramString(params, 'path', '')
    let result = await securityLabel.getSecurityLabel(path)
    return result.toString()
  }],
  ['CoreFileKit.securityLabel.getSecurityLabelSync', async (params: Map<string, string>): Promise<string> => {
    let path = paramString(params, 'path', '')
    let result = securityLabel.getSecurityLabelSync(path)
    return result.toString()
  }],
  ['CoreFileKit.statfs.getFreeSize', async (params: Map<string, string>): Promise<string> => {
    let path = paramString(params, 'path', '')
    let result = await statfs.getFreeSize(path)
    return result.toString()
  }],
  ['CoreFileKit.statfs.getFreeSizeSync', async (params: Map<string, string>): Promise<string> => {
    let path = paramString(params, 'path', '')
    let result = statfs.getFreeSizeSync(path)
    return result.toString()
  }],
  ['CoreFileKit.statfs.getTotalSize', async (params: Map<string, string>): Promise<string> => {
    let path = paramString(params, 'path', '')
    let result = await statfs.getTotalSize(path)
    return result.toString()
  }],
  ['CoreFileKit.statfs.getTotalSizeSync', async (params: Map<string, string>): Promise<string> => {
    let path = paramString(params, 'path', '')
    let result = statfs.getTotalSizeSync(path)
    return result.toString()
  }],
  ['CoreFileKit.storageStatistics.getCurrentBundleInodes', async (params: Map<string, string>): Promise<string> => {
    let result = await storageStatistics.getCurrentBundleInodes()
    return result.toString()
  }],
  ['CoreFileKit.storageStatistics.getFreeInodes', async (params: Map<string, string>): Promise<string> => {
    let result = await storageStatistics.getFreeInodes()
    return result.toString()
  }],
  ['CoreFileKit.storageStatistics.getFreeSize', async (params: Map<string, string>): Promise<string> => {
    let result = await storageStatistics.getFreeSize()
    return result.toString()
  }],
  ['CoreFileKit.storageStatistics.getFreeSizeOfVolume', async (params: Map<string, string>): Promise<string> => {
    let volumeUuid = paramString(params, 'volumeUuid', '')
    let result = await storageStatistics.getFreeSizeOfVolume(volumeUuid)
    return result.toString()
  }],
  ['CoreFileKit.storageStatistics.getFreeSizeSync', async (params: Map<string, string>): Promise<string> => {
    let result = storageStatistics.getFreeSizeSync()
    return result.toString()
  }],
  ['CoreFileKit.storageStatistics.getSystemDataSize', async (params: Map<string, string>): Promise<string> => {
    let result = await storageStatistics.getSystemDataSize()
    return result.toString()
  }],
  ['CoreFileKit.storageStatistics.getSystemSize', async (params: Map<string, string>): Promise<string> => {
    let result = await storageStatistics.getSystemSize()
    return result.toString()
  }],
  ['CoreFileKit.storageStatistics.getTotalInodes', async (params: Map<string, string>): Promise<string> => {
    let result = await storageStatistics.getTotalInodes()
    return result.toString()
  }],
  ['CoreFileKit.storageStatistics.getTotalSize', async (params: Map<string, string>): Promise<string> => {
    let result = await storageStatistics.getTotalSize()
    return result.toString()
  }],
  ['CoreFileKit.storageStatistics.getTotalSizeOfVolume', async (params: Map<string, string>): Promise<string> => {
    let volumeUuid = paramString(params, 'volumeUuid', '')
    let result = await storageStatistics.getTotalSizeOfVolume(volumeUuid)
    return result.toString()
  }],
  ['CoreFileKit.storageStatistics.getTotalSizeSync', async (params: Map<string, string>): Promise<string> => {
    let result = storageStatistics.getTotalSizeSync()
    return result.toString()
  }],
  ['DataProtectionKit.dlpPermission.cleanSandboxAppConfig', async (params: Map<string, string>): Promise<string> => {
    await dlpPermission.cleanSandboxAppConfig()
    return 'ok'
  }],
  ['DataProtectionKit.dlpPermission.getDLPSuffix', async (params: Map<string, string>): Promise<string> => {
    let result = dlpPermission.getDLPSuffix()
    return result.toString()
  }],
  ['DataProtectionKit.dlpPermission.getOriginalFileName', async (params: Map<string, string>): Promise<string> => {
    let fileName = paramString(params, 'fileName', '')
    let result = dlpPermission.getOriginalFileName(fileName)
    return result.toString()
  }],
  ['DataProtectionKit.dlpPermission.getSandboxAppConfig', async (params: Map<string, string>): Promise<string> => {
    let result = await dlpPermission.getSandboxAppConfig()
    return result.toString()
  }],
  ['DataProtectionKit.dlpPermission.isDLPFeatureProvided', async (params: Map<string, string>): Promise<string> => {
    let result = await dlpPermission.isDLPFeatureProvided()
    return result.toString()
  }],
  ['DataProtectionKit.dlpPermission.isDLPFile', async (params: Map<string, string>): Promise<string> => {
    let fd = paramFloat(params, 'fd', 0)
    let result = await dlpPermission.isDLPFile(fd)
    return result.toString()
  }],
  ['DataProtectionKit.dlpPermission.isInSandbox', async (params: Map<string, string>): Promise<string> => {
    let result = await dlpPermission.isInSandbox()
    return result.toString()
  }],
  ['DataProtectionKit.dlpPermission.setSandboxAppConfig', async (params: Map<string, string>): Promise<string> => {
    let configInfo = paramString(params, 'configInfo', '')
    await dlpPermission.setSandboxAppConfig(configInfo)
    return 'ok'
  }],
  ['DeviceCertificateKit.certificateManagerDialog.supportsCACertDialog', async (params: Map<string, string>): Promise<string> => {
    let result = certificateManagerDialog.supportsCACertDialog()
    return result.toString()
  }],
  ['DistributedServiceKit.abilityConnectionManager.acceptConnect', async (params: Map<string, string>): Promise<string> => {
    let sessionId = paramInt(params, 'sessionId', 0)
    let token = paramString(params, 'token', '')
    await abilityConnectionManager.acceptConnect(sessionId, token)
    return 'ok'
  }],
  ['DistributedServiceKit.abilityConnectionManager.destroyAbilityConnectionSession', async (params: Map<string, string>): Promise<string> => {
    let sessionId = paramInt(params, 'sessionId', 0)
    abilityConnectionManager.destroyAbilityConnectionSession(sessionId)
    return 'ok'
  }],
  ['DistributedServiceKit.abilityConnectionManager.destroyStream', async (params: Map<string, string>): Promise<string> => {
    let streamId = paramInt(params, 'streamId', 0)
    abilityConnectionManager.destroyStream(streamId)
    return 'ok'
  }],
  ['DistributedServiceKit.abilityConnectionManager.disconnect', async (params: Map<string, string>): Promise<string> => {
    let sessionId = paramInt(params, 'sessionId', 0)
    abilityConnectionManager.disconnect(sessionId)
    return 'ok'
  }],
  ['DistributedServiceKit.abilityConnectionManager.reject', async (params: Map<string, string>): Promise<string> => {
    let token = paramString(params, 'token', '')
    let reason = paramString(params, 'reason', '')
    abilityConnectionManager.reject(token, reason)
    return 'ok'
  }],
  ['DistributedServiceKit.abilityConnectionManager.sendMessage', async (params: Map<string, string>): Promise<string> => {
    let sessionId = paramInt(params, 'sessionId', 0)
    let msg = paramString(params, 'msg', '')
    await abilityConnectionManager.sendMessage(sessionId, msg)
    return 'ok'
  }],
  ['DistributedServiceKit.abilityConnectionManager.startStream', async (params: Map<string, string>): Promise<string> => {
    let streamId = paramInt(params, 'streamId', 0)
    abilityConnectionManager.startStream(streamId)
    return 'ok'
  }],
  ['DistributedServiceKit.abilityConnectionManager.stopStream', async (params: Map<string, string>): Promise<string> => {
    let streamId = paramInt(params, 'streamId', 0)
    abilityConnectionManager.stopStream(streamId)
    return 'ok'
  }],
  ['DrmKit.drm.getMediaKeySystemUuid', async (params: Map<string, string>): Promise<string> => {
    let name = paramString(params, 'name', '')
    let result = drm.getMediaKeySystemUuid(name)
    return result.toString()
  }],
  ['DrmKit.drm.isMediaKeySystemSupported', async (params: Map<string, string>): Promise<string> => {
    let name = paramString(params, 'name', '')
    let result = drm.isMediaKeySystemSupported(name)
    return result.toString()
  }],
  ['FormKit.formHost.isSystemReady', async (params: Map<string, string>): Promise<string> => {
    await formHost.isSystemReady()
    return 'ok'
  }],
  ['FormKit.formProvider.activateSceneAnimation', async (params: Map<string, string>): Promise<string> => {
    let formId = paramString(params, 'formId', '')
    await formProvider.activateSceneAnimation(formId)
    return 'ok'
  }],
  ['FormKit.formProvider.cancelOverflow', async (params: Map<string, string>): Promise<string> => {
    let formId = paramString(params, 'formId', '')
    await formProvider.cancelOverflow(formId)
    return 'ok'
  }],
  ['FormKit.formProvider.closeFormEditAbility', async (params: Map<string, string>): Promise<string> => {
    let isMainPage = paramBoolean(params, 'isMainPage', false)
    formProvider.closeFormEditAbility(isMainPage)
    return 'ok'
  }],
  ['FormKit.formProvider.deactivateSceneAnimation', async (params: Map<string, string>): Promise<string> => {
    let formId = paramString(params, 'formId', '')
    await formProvider.deactivateSceneAnimation(formId)
    return 'ok'
  }],
  ['FormKit.formProvider.isRequestPublishFormSupported', async (params: Map<string, string>): Promise<string> => {
    let result = await formProvider.isRequestPublishFormSupported()
    return result.toString()
  }],
  ['FormKit.formProvider.setFormNextRefreshTime', async (params: Map<string, string>): Promise<string> => {
    let formId = paramString(params, 'formId', '')
    let minute = paramInt(params, 'minute', 0)
    await formProvider.setFormNextRefreshTime(formId, minute)
    return 'ok'
  }],
  ['IMEKit.inputMethod.setSimpleKeyboardEnabled', async (params: Map<string, string>): Promise<string> => {
    let enable = paramBoolean(params, 'enable', false)
    inputMethod.setSimpleKeyboardEnabled(enable)
    return 'ok'
  }],
  ['ImageKit.videoProcessingEngine.deinitializeEnvironment', async (params: Map<string, string>): Promise<string> => {
    await videoProcessingEngine.deinitializeEnvironment()
    return 'ok'
  }],
  ['ImageKit.videoProcessingEngine.initializeEnvironment', async (params: Map<string, string>): Promise<string> => {
    await videoProcessingEngine.initializeEnvironment()
    return 'ok'
  }],
  ['InputKit.inputDevice.getIntervalSinceLastInput', async (params: Map<string, string>): Promise<string> => {
    let result = await inputDevice.getIntervalSinceLastInput()
    return result.toString()
  }],
  ['InputKit.inputDevice.getKeyboardRepeatDelay', async (params: Map<string, string>): Promise<string> => {
    let result = await inputDevice.getKeyboardRepeatDelay()
    return result.toString()
  }],
  ['InputKit.inputDevice.getKeyboardRepeatRate', async (params: Map<string, string>): Promise<string> => {
    let result = await inputDevice.getKeyboardRepeatRate()
    return result.toString()
  }],
  ['InputKit.inputDevice.setKeyboardRepeatDelay', async (params: Map<string, string>): Promise<string> => {
    let delay = paramInt(params, 'delay', 0)
    await inputDevice.setKeyboardRepeatDelay(delay)
    return 'ok'
  }],
  ['InputKit.inputDevice.setKeyboardRepeatRate', async (params: Map<string, string>): Promise<string> => {
    let rate = paramInt(params, 'rate', 0)
    await inputDevice.setKeyboardRepeatRate(rate)
    return 'ok'
  }],
  ['InputKit.pointer.getHoverScrollState', async (params: Map<string, string>): Promise<string> => {
    let result = await pointer.getHoverScrollState()
    return result.toString()
  }],
  ['InputKit.pointer.getMouseScrollRows', async (params: Map<string, string>): Promise<string> => {
    let result = await pointer.getMouseScrollRows()
    return result.toString()
  }],
  ['InputKit.pointer.getPointerColor', async (params: Map<string, string>): Promise<string> => {
    let result = await pointer.getPointerColor()
    return result.toString()
  }],
  ['InputKit.pointer.getPointerColorSync', async (params: Map<string, string>): Promise<string> => {
    let result = pointer.getPointerColorSync()
    return result.toString()
  }],
  ['InputKit.pointer.getPointerSize', async (params: Map<string, string>): Promise<string> => {
    let result = await pointer.getPointerSize()
    return result.toString()
  }],
  ['InputKit.pointer.getPointerSizeSync', async (params: Map<string, string>): Promise<string> => {
    let result = pointer.getPointerSizeSync()
    return result.toString()
  }],
  ['InputKit.pointer.getPointerSpeed', async (params: Map<string, string>): Promise<string> => {
    let result = await pointer.getPointerSpeed()
    return result.toString()
  }],
  ['InputKit.pointer.getPointerSpeedSync', async (params: Map<string, string>): Promise<string> => {
    let result = pointer.getPointerSpeedSync()
    return result.toString()
  }],
  ['InputKit.pointer.getTouchpadDoubleTapAndDragState', async (params: Map<string, string>): Promise<string> => {
    let result = await pointer.getTouchpadDoubleTapAndDragState()
    return result.toString()
  }],
  ['InputKit.pointer.getTouchpadPinchSwitch', async (params: Map<string, string>): Promise<string> => {
    let result = await pointer.getTouchpadPinchSwitch()
    return result.toString()
  }],
  ['InputKit.pointer.getTouchpadPointerSpeed', async (params: Map<string, string>): Promise<string> => {
    let result = await pointer.getTouchpadPointerSpeed()
    return result.toString()
  }],
  ['InputKit.pointer.getTouchpadScrollDirection', async (params: Map<string, string>): Promise<string> => {
    let result = await pointer.getTouchpadScrollDirection()
    return result.toString()
  }],
  ['InputKit.pointer.getTouchpadScrollSwitch', async (params: Map<string, string>): Promise<string> => {
    let result = await pointer.getTouchpadScrollSwitch()
    return result.toString()
  }],
  ['InputKit.pointer.getTouchpadSwipeSwitch', async (params: Map<string, string>): Promise<string> => {
    let result = await pointer.getTouchpadSwipeSwitch()
    return result.toString()
  }],
  ['InputKit.pointer.getTouchpadTapSwitch', async (params: Map<string, string>): Promise<string> => {
    let result = await pointer.getTouchpadTapSwitch()
    return result.toString()
  }],
  ['InputKit.pointer.isPointerVisible', async (params: Map<string, string>): Promise<string> => {
    let result = await pointer.isPointerVisible()
    return result.toString()
  }],
  ['InputKit.pointer.isPointerVisibleSync', async (params: Map<string, string>): Promise<string> => {
    let result = pointer.isPointerVisibleSync()
    return result.toString()
  }],
  ['InputKit.pointer.setHoverScrollState', async (params: Map<string, string>): Promise<string> => {
    let state = paramBoolean(params, 'state', false)
    await pointer.setHoverScrollState(state)
    return 'ok'
  }],
  ['InputKit.pointer.setMouseScrollRows', async (params: Map<string, string>): Promise<string> => {
    let rows = paramInt(params, 'rows', 0)
    await pointer.setMouseScrollRows(rows)
    return 'ok'
  }],
  ['InputKit.pointer.setPointerColor', async (params: Map<string, string>): Promise<string> => {
    let color = paramInt(params, 'color', 0)
    await pointer.setPointerColor(color)
    return 'ok'
  }],
  ['InputKit.pointer.setPointerColorSync', async (params: Map<string, string>): Promise<string> => {
    let color = paramInt(params, 'color', 0)
    pointer.setPointerColorSync(color)
    return 'ok'
  }],
  ['InputKit.pointer.setPointerSize', async (params: Map<string, string>): Promise<string> => {
    let size = paramInt(params, 'size', 0)
    await pointer.setPointerSize(size)
    return 'ok'
  }],
  ['InputKit.pointer.setPointerSizeSync', async (params: Map<string, string>): Promise<string> => {
    let size = paramInt(params, 'size', 0)
    pointer.setPointerSizeSync(size)
    return 'ok'
  }],
  ['InputKit.pointer.setPointerSpeed', async (params: Map<string, string>): Promise<string> => {
    let speed = paramInt(params, 'speed', 0)
    await pointer.setPointerSpeed(speed)
    return 'ok'
  }],
  ['InputKit.pointer.setPointerSpeedSync', async (params: Map<string, string>): Promise<string> => {
    let speed = paramInt(params, 'speed', 0)
    pointer.setPointerSpeedSync(speed)
    return 'ok'
  }],
  ['InputKit.pointer.setPointerVisible', async (params: Map<string, string>): Promise<string> => {
    let visible = paramBoolean(params, 'visible', false)
    await pointer.setPointerVisible(visible)
    return 'ok'
  }],
  ['InputKit.pointer.setPointerVisibleSync', async (params: Map<string, string>): Promise<string> => {
    let visible = paramBoolean(params, 'visible', false)
    pointer.setPointerVisibleSync(visible)
    return 'ok'
  }],
  ['InputKit.pointer.setTouchpadDoubleTapAndDragState', async (params: Map<string, string>): Promise<string> => {
    let isOpen = paramBoolean(params, 'isOpen', false)
    await pointer.setTouchpadDoubleTapAndDragState(isOpen)
    return 'ok'
  }],
  ['InputKit.pointer.setTouchpadPinchSwitch', async (params: Map<string, string>): Promise<string> => {
    let state = paramBoolean(params, 'state', false)
    await pointer.setTouchpadPinchSwitch(state)
    return 'ok'
  }],
  ['InputKit.pointer.setTouchpadPointerSpeed', async (params: Map<string, string>): Promise<string> => {
    let speed = paramInt(params, 'speed', 0)
    await pointer.setTouchpadPointerSpeed(speed)
    return 'ok'
  }],
  ['InputKit.pointer.setTouchpadScrollDirection', async (params: Map<string, string>): Promise<string> => {
    let state = paramBoolean(params, 'state', false)
    await pointer.setTouchpadScrollDirection(state)
    return 'ok'
  }],
  ['InputKit.pointer.setTouchpadScrollSwitch', async (params: Map<string, string>): Promise<string> => {
    let state = paramBoolean(params, 'state', false)
    await pointer.setTouchpadScrollSwitch(state)
    return 'ok'
  }],
  ['InputKit.pointer.setTouchpadSwipeSwitch', async (params: Map<string, string>): Promise<string> => {
    let state = paramBoolean(params, 'state', false)
    await pointer.setTouchpadSwipeSwitch(state)
    return 'ok'
  }],
  ['InputKit.pointer.setTouchpadTapSwitch', async (params: Map<string, string>): Promise<string> => {
    let state = paramBoolean(params, 'state', false)
    await pointer.setTouchpadTapSwitch(state)
    return 'ok'
  }],
  ['InputKit.shortKey.setKeyDownDuration', async (params: Map<string, string>): Promise<string> => {
    let businessKey = paramString(params, 'businessKey', '')
    let delay = paramInt(params, 'delay', 0)
    await shortKey.setKeyDownDuration(businessKey, delay)
    return 'ok'
  }],
  ['LocalizationKit.i18n.isRTL', async (params: Map<string, string>): Promise<string> => {
    let locale = paramString(params, 'locale', '')
    let result = i18n.isRTL(locale)
    return result.toString()
  }],
  ['LocationKit.geoLocationManager.isBeaconFenceSupported', async (params: Map<string, string>): Promise<string> => {
    let result = geoLocationManager.isBeaconFenceSupported()
    return result.toString()
  }],
  ['LocationKit.geoLocationManager.isCachedGnssServiceSupported', async (params: Map<string, string>): Promise<string> => {
    let result = geoLocationManager.isCachedGnssServiceSupported()
    return result.toString()
  }],
  ['LocationKit.geoLocationManager.isGeocoderAvailable', async (params: Map<string, string>): Promise<string> => {
    let result = geoLocationManager.isGeocoderAvailable()
    return result.toString()
  }],
  ['LocationKit.geoLocationManager.isGnssFenceServiceSupported', async (params: Map<string, string>): Promise<string> => {
    let result = geoLocationManager.isGnssFenceServiceSupported()
    return result.toString()
  }],
  ['LocationKit.geoLocationManager.isGnssServiceSupported', async (params: Map<string, string>): Promise<string> => {
    let result = geoLocationManager.isGnssServiceSupported()
    return result.toString()
  }],
  ['LocationKit.geoLocationManager.isLocationEnabled', async (params: Map<string, string>): Promise<string> => {
    let result = geoLocationManager.isLocationEnabled()
    return result.toString()
  }],
  ['LocationKit.geoLocationManager.isLocationEnabledByUserId', async (params: Map<string, string>): Promise<string> => {
    let userId = paramInt(params, 'userId', 0)
    let result = geoLocationManager.isLocationEnabledByUserId(userId)
    return result.toString()
  }],
  ['LocationKit.geoLocationManager.isPoiServiceSupported', async (params: Map<string, string>): Promise<string> => {
    let result = geoLocationManager.isPoiServiceSupported()
    return result.toString()
  }],
  ['MDMKit.adminManager.getEnterpriseManagedTips', async (params: Map<string, string>): Promise<string> => {
    let result = await adminManager.getEnterpriseManagedTips()
    return result.toString()
  }],
  ['MDMKit.applicationManager.isAppKioskAllowed', async (params: Map<string, string>): Promise<string> => {
    let appIdentifier = paramString(params, 'appIdentifier', '')
    let result = applicationManager.isAppKioskAllowed(appIdentifier)
    return result.toString()
  }],
  ['MDMKit.browser.getSelfManagedBrowserPolicyVersion', async (params: Map<string, string>): Promise<string> => {
    let result = browser.getSelfManagedBrowserPolicyVersion()
    return result.toString()
  }],
  ['MechanicKit.mechanicManager.getCameraTrackingEnabled', async (params: Map<string, string>): Promise<string> => {
    let result = mechanicManager.getCameraTrackingEnabled()
    return result.toString()
  }],
  ['MechanicKit.mechanicManager.getMaxRotationTime', async (params: Map<string, string>): Promise<string> => {
    let mechId = paramInt(params, 'mechId', 0)
    let result = mechanicManager.getMaxRotationTime(mechId)
    return result.toString()
  }],
  ['MechanicKit.mechanicManager.setCameraTrackingEnabled', async (params: Map<string, string>): Promise<string> => {
    let isEnabled = paramBoolean(params, 'isEnabled', false)
    mechanicManager.setCameraTrackingEnabled(isEnabled)
    return 'ok'
  }],
  ['MechanicKit.mechanicManager.stopMoving', async (params: Map<string, string>): Promise<string> => {
    let mechId = paramInt(params, 'mechId', 0)
    await mechanicManager.stopMoving(mechId)
    return 'ok'
  }],
  ['MediaKit.media.getAVScreenCaptureConfigurableParameters', async (params: Map<string, string>): Promise<string> => {
    let sessionId = paramInt(params, 'sessionId', 0)
    let result = await media.getAVScreenCaptureConfigurableParameters(sessionId)
    return result.toString()
  }],
  ['MediaKit.media.reportAVScreenCaptureUserChoice', async (params: Map<string, string>): Promise<string> => {
    let sessionId = paramInt(params, 'sessionId', 0)
    let choice = paramString(params, 'choice', '')
    await media.reportAVScreenCaptureUserChoice(sessionId, choice)
    return 'ok'
  }],
  ['MultimodalAwarenessKit.metadataBinding.notifyMetadataBindingEvent', async (params: Map<string, string>): Promise<string> => {
    let bundleName = paramString(params, 'bundleName', '')
    let result = await metadataBinding.notifyMetadataBindingEvent(bundleName)
    return result.toString()
  }],
  ['MultimodalAwarenessKit.metadataBinding.submitMetadata', async (params: Map<string, string>): Promise<string> => {
    let metadata = paramString(params, 'metadata', '')
    metadataBinding.submitMetadata(metadata)
    return 'ok'
  }],
  ['NetworkKit.connection.clearCustomDnsRules', async (params: Map<string, string>): Promise<string> => {
    await netConnection.clearCustomDnsRules()
    return 'ok'
  }],
  ['NetworkKit.connection.findProxyForUrl', async (params: Map<string, string>): Promise<string> => {
    let url = paramString(params, 'url', '')
    let result = netConnection.findProxyForUrl(url)
    return result.toString()
  }],
  ['NetworkKit.connection.getPacFileUrl', async (params: Map<string, string>): Promise<string> => {
    let result = netConnection.getPacFileUrl()
    return result.toString()
  }],
  ['NetworkKit.connection.getPacUrl', async (params: Map<string, string>): Promise<string> => {
    let result = netConnection.getPacUrl()
    return result.toString()
  }],
  ['NetworkKit.connection.hasDefaultNet', async (params: Map<string, string>): Promise<string> => {
    let result = await netConnection.hasDefaultNet()
    return result.toString()
  }],
  ['NetworkKit.connection.hasDefaultNetSync', async (params: Map<string, string>): Promise<string> => {
    let result = netConnection.hasDefaultNetSync()
    return result.toString()
  }],
  ['NetworkKit.connection.isDefaultNetMetered', async (params: Map<string, string>): Promise<string> => {
    let result = await netConnection.isDefaultNetMetered()
    return result.toString()
  }],
  ['NetworkKit.connection.isDefaultNetMeteredSync', async (params: Map<string, string>): Promise<string> => {
    let result = netConnection.isDefaultNetMeteredSync()
    return result.toString()
  }],
  ['NetworkKit.connection.removeCustomDnsRule', async (params: Map<string, string>): Promise<string> => {
    let host = paramString(params, 'host', '')
    await netConnection.removeCustomDnsRule(host)
    return 'ok'
  }],
  ['NetworkKit.ethernet.isIfaceActive', async (params: Map<string, string>): Promise<string> => {
    let iface = paramString(params, 'iface', '')
    let result = await ethernet.isIfaceActive(iface)
    return result.toString()
  }],
  ['NetworkKit.networkSecurity.isCleartextPermitted', async (params: Map<string, string>): Promise<string> => {
    let result = networkSecurity.isCleartextPermitted()
    return result.toString()
  }],
  ['NetworkKit.networkSecurity.isCleartextPermittedByHostName', async (params: Map<string, string>): Promise<string> => {
    let hostName = paramString(params, 'hostName', '')
    let result = networkSecurity.isCleartextPermittedByHostName(hostName)
    return result.toString()
  }],
  ['NetworkKit.statistics.getAllRxBytes', async (params: Map<string, string>): Promise<string> => {
    let result = await statistics.getAllRxBytes()
    return result.toString()
  }],
  ['NetworkKit.statistics.getAllTxBytes', async (params: Map<string, string>): Promise<string> => {
    let result = await statistics.getAllTxBytes()
    return result.toString()
  }],
  ['NetworkKit.statistics.getCellularRxBytes', async (params: Map<string, string>): Promise<string> => {
    let result = await statistics.getCellularRxBytes()
    return result.toString()
  }],
  ['NetworkKit.statistics.getCellularTxBytes', async (params: Map<string, string>): Promise<string> => {
    let result = await statistics.getCellularTxBytes()
    return result.toString()
  }],
  ['NetworkKit.statistics.getIfaceRxBytes', async (params: Map<string, string>): Promise<string> => {
    let nic = paramString(params, 'nic', '')
    let result = await statistics.getIfaceRxBytes(nic)
    return result.toString()
  }],
  ['NetworkKit.statistics.getIfaceTxBytes', async (params: Map<string, string>): Promise<string> => {
    let nic = paramString(params, 'nic', '')
    let result = await statistics.getIfaceTxBytes(nic)
    return result.toString()
  }],
  ['NetworkKit.statistics.getSockfdRxBytes', async (params: Map<string, string>): Promise<string> => {
    let sockfd = paramInt(params, 'sockfd', 0)
    let result = await statistics.getSockfdRxBytes(sockfd)
    return result.toString()
  }],
  ['NetworkKit.statistics.getSockfdTxBytes', async (params: Map<string, string>): Promise<string> => {
    let sockfd = paramInt(params, 'sockfd', 0)
    let result = await statistics.getSockfdTxBytes(sockfd)
    return result.toString()
  }],
  ['NotificationKit.notificationManager.cancel', async (params: Map<string, string>): Promise<string> => {
    let id = paramInt(params, 'id', 0)
    let label = paramString(params, 'label', '')
    await notificationManager.cancel(id, label)
    return 'ok'
  }],
  ['NotificationKit.notificationManager.cancelAll', async (params: Map<string, string>): Promise<string> => {
    await notificationManager.cancelAll()
    return 'ok'
  }],
  ['NotificationKit.notificationManager.cancelGroup', async (params: Map<string, string>): Promise<string> => {
    let groupName = paramString(params, 'groupName', '')
    await notificationManager.cancelGroup(groupName)
    return 'ok'
  }],
  ['NotificationKit.notificationManager.getActiveNotificationCount', async (params: Map<string, string>): Promise<string> => {
    let result = await notificationManager.getActiveNotificationCount()
    return result.toString()
  }],
  ['NotificationKit.notificationManager.getBadgeNumber', async (params: Map<string, string>): Promise<string> => {
    let result = await notificationManager.getBadgeNumber()
    return result.toString()
  }],
  ['NotificationKit.notificationManager.isDistributedEnabled', async (params: Map<string, string>): Promise<string> => {
    let deviceType = paramString(params, 'deviceType', '')
    let result = await notificationManager.isDistributedEnabled(deviceType)
    return result.toString()
  }],
  ['NotificationKit.notificationManager.isGeofenceEnabled', async (params: Map<string, string>): Promise<string> => {
    let result = await notificationManager.isGeofenceEnabled()
    return result.toString()
  }],
  ['NotificationKit.notificationManager.isNotificationEnabled', async (params: Map<string, string>): Promise<string> => {
    let result = await notificationManager.isNotificationEnabled()
    return result.toString()
  }],
  ['NotificationKit.notificationManager.isNotificationEnabledSync', async (params: Map<string, string>): Promise<string> => {
    let result = notificationManager.isNotificationEnabledSync()
    return result.toString()
  }],
  ['NotificationKit.notificationManager.isPriorityEnabled', async (params: Map<string, string>): Promise<string> => {
    let result = await notificationManager.isPriorityEnabled()
    return result.toString()
  }],
  ['NotificationKit.notificationManager.isPriorityIntelligentEnabled', async (params: Map<string, string>): Promise<string> => {
    let result = await notificationManager.isPriorityIntelligentEnabled()
    return result.toString()
  }],
  ['NotificationKit.notificationManager.isSmartReminderEnabled', async (params: Map<string, string>): Promise<string> => {
    let deviceType = paramString(params, 'deviceType', '')
    let result = await notificationManager.isSmartReminderEnabled(deviceType)
    return result.toString()
  }],
  ['NotificationKit.notificationManager.isSupportDoNotDisturbMode', async (params: Map<string, string>): Promise<string> => {
    let result = await notificationManager.isSupportDoNotDisturbMode()
    return result.toString()
  }],
  ['NotificationKit.notificationManager.isSupportTemplate', async (params: Map<string, string>): Promise<string> => {
    let templateName = paramString(params, 'templateName', '')
    let result = await notificationManager.isSupportTemplate(templateName)
    return result.toString()
  }],
  ['NotificationKit.notificationManager.offBadgeNumberQuery', async (params: Map<string, string>): Promise<string> => {
    notificationManager.offBadgeNumberQuery()
    return 'ok'
  }],
  ['NotificationKit.notificationManager.removeAllSlots', async (params: Map<string, string>): Promise<string> => {
    await notificationManager.removeAllSlots()
    return 'ok'
  }],
  ['NotificationKit.notificationManager.setBadgeNumber', async (params: Map<string, string>): Promise<string> => {
    let badgeNumber = paramInt(params, 'badgeNumber', 0)
    await notificationManager.setBadgeNumber(badgeNumber)
    return 'ok'
  }],
  ['NotificationKit.notificationManager.setDistributedEnabled', async (params: Map<string, string>): Promise<string> => {
    let enable = paramBoolean(params, 'enable', false)
    let deviceType = paramString(params, 'deviceType', '')
    await notificationManager.setDistributedEnabled(enable, deviceType)
    return 'ok'
  }],
  ['NotificationKit.notificationManager.setGeofenceEnabled', async (params: Map<string, string>): Promise<string> => {
    let enabled = paramBoolean(params, 'enabled', false)
    await notificationManager.setGeofenceEnabled(enabled)
    return 'ok'
  }],
  ['NotificationKit.notificationManager.setPriorityEnabled', async (params: Map<string, string>): Promise<string> => {
    let enable = paramBoolean(params, 'enable', false)
    await notificationManager.setPriorityEnabled(enable)
    return 'ok'
  }],
  ['NotificationKit.notificationManager.setPriorityIntelligentEnabled', async (params: Map<string, string>): Promise<string> => {
    let enable = paramBoolean(params, 'enable', false)
    await notificationManager.setPriorityIntelligentEnabled(enable)
    return 'ok'
  }],
  ['NotificationKit.notificationManager.setSmartReminderEnabled', async (params: Map<string, string>): Promise<string> => {
    let deviceType = paramString(params, 'deviceType', '')
    let enable = paramBoolean(params, 'enable', false)
    await notificationManager.setSmartReminderEnabled(deviceType, enable)
    return 'ok'
  }],
  ['NotificationKit.notificationManager.setTargetDeviceStatus', async (params: Map<string, string>): Promise<string> => {
    let deviceType = paramString(params, 'deviceType', '')
    let status = paramInt(params, 'status', 0)
    await notificationManager.setTargetDeviceStatus(deviceType, status)
    return 'ok'
  }],
  ['NotificationKit.notificationManager.snoozeNotification', async (params: Map<string, string>): Promise<string> => {
    let hashCode = paramString(params, 'hashCode', '')
    let delayTime = paramInt(params, 'delayTime', 0)
    await notificationManager.snoozeNotification(hashCode, delayTime)
    return 'ok'
  }],
  ['NotificationKit.notificationSubscribe.removeAll', async (params: Map<string, string>): Promise<string> => {
    let userId = paramInt(params, 'userId', 0)
    await notificationSubscribe.removeAll(userId)
    return 'ok'
  }],
  ['PerformanceAnalysisKit.hiAppEvent.addProcessorFromConfig', async (params: Map<string, string>): Promise<string> => {
    let processorName = paramString(params, 'processorName', '')
    let configName = paramString(params, 'configName', '')
    let result = await hiAppEvent.addProcessorFromConfig(processorName, configName)
    return result.toString()
  }],
  ['PerformanceAnalysisKit.hiAppEvent.clearData', async (params: Map<string, string>): Promise<string> => {
    hiAppEvent.clearData()
    return 'ok'
  }],
  ['PerformanceAnalysisKit.hiAppEvent.getUserId', async (params: Map<string, string>): Promise<string> => {
    let name = paramString(params, 'name', '')
    let result = hiAppEvent.getUserId(name)
    return result.toString()
  }],
  ['PerformanceAnalysisKit.hiAppEvent.getUserProperty', async (params: Map<string, string>): Promise<string> => {
    let name = paramString(params, 'name', '')
    let result = hiAppEvent.getUserProperty(name)
    return result.toString()
  }],
  ['PerformanceAnalysisKit.hiAppEvent.removeProcessor', async (params: Map<string, string>): Promise<string> => {
    let id = paramInt(params, 'id', 0)
    hiAppEvent.removeProcessor(id)
    return 'ok'
  }],
  ['PerformanceAnalysisKit.hiAppEvent.setUserId', async (params: Map<string, string>): Promise<string> => {
    let name = paramString(params, 'name', '')
    let value = paramString(params, 'value', '')
    hiAppEvent.setUserId(name, value)
    return 'ok'
  }],
  ['PerformanceAnalysisKit.hiAppEvent.setUserProperty', async (params: Map<string, string>): Promise<string> => {
    let name = paramString(params, 'name', '')
    let value = paramString(params, 'value', '')
    hiAppEvent.setUserProperty(name, value)
    return 'ok'
  }],
  ['PerformanceAnalysisKit.hiRetrieval.getLastParticipationTimestamp', async (params: Map<string, string>): Promise<string> => {
    let result = hiRetrieval.getLastParticipationTimestamp()
    return result.toString()
  }],
  ['PerformanceAnalysisKit.hiRetrieval.init', async (params: Map<string, string>): Promise<string> => {
    hiRetrieval.init()
    return 'ok'
  }],
  ['PerformanceAnalysisKit.hiRetrieval.isParticipant', async (params: Map<string, string>): Promise<string> => {
    let result = hiRetrieval.isParticipant()
    return result.toString()
  }],
  ['PerformanceAnalysisKit.hiRetrieval.quit', async (params: Map<string, string>): Promise<string> => {
    hiRetrieval.quit()
    return 'ok'
  }],
  ['PerformanceAnalysisKit.hiRetrieval.run', async (params: Map<string, string>): Promise<string> => {
    hiRetrieval.run()
    return 'ok'
  }],
  ['PerformanceAnalysisKit.hiTraceChain.clearId', async (params: Map<string, string>): Promise<string> => {
    hiTraceChain.clearId()
    return 'ok'
  }],
  ['PerformanceAnalysisKit.hiTraceMeter.finishTrace', async (params: Map<string, string>): Promise<string> => {
    let name = paramString(params, 'name', '')
    let taskId = paramInt(params, 'taskId', 0)
    hiTraceMeter.finishTrace(name, taskId)
    return 'ok'
  }],
  ['PerformanceAnalysisKit.hiTraceMeter.isTraceEnabled', async (params: Map<string, string>): Promise<string> => {
    let result = hiTraceMeter.isTraceEnabled()
    return result.toString()
  }],
  ['PerformanceAnalysisKit.hiTraceMeter.startTrace', async (params: Map<string, string>): Promise<string> => {
    let name = paramString(params, 'name', '')
    let taskId = paramInt(params, 'taskId', 0)
    hiTraceMeter.startTrace(name, taskId)
    return 'ok'
  }],
  ['PerformanceAnalysisKit.hiTraceMeter.traceByValue', async (params: Map<string, string>): Promise<string> => {
    let name = paramString(params, 'name', '')
    let count = paramInt(params, 'count', 0)
    hiTraceMeter.traceByValue(name, count)
    return 'ok'
  }],
  ['PerformanceAnalysisKit.hiTraceMeter.unregisterTraceListener', async (params: Map<string, string>): Promise<string> => {
    let index = paramInt(params, 'index', 0)
    let result = hiTraceMeter.unregisterTraceListener(index)
    return result.toString()
  }],
  ['PerformanceAnalysisKit.hichecker.addCheckRule', async (params: Map<string, string>): Promise<string> => {
    let rule = paramBigInt(params, 'rule', BigInt(0))
    hichecker.addCheckRule(rule)
    return 'ok'
  }],
  ['PerformanceAnalysisKit.hichecker.containsCheckRule', async (params: Map<string, string>): Promise<string> => {
    let rule = paramBigInt(params, 'rule', BigInt(0))
    let result = hichecker.containsCheckRule(rule)
    return result.toString()
  }],
  ['PerformanceAnalysisKit.hichecker.getRule', async (params: Map<string, string>): Promise<string> => {
    let result = hichecker.getRule()
    return result.toString()
  }],
  ['PerformanceAnalysisKit.hichecker.removeCheckRule', async (params: Map<string, string>): Promise<string> => {
    let rule = paramBigInt(params, 'rule', BigInt(0))
    hichecker.removeCheckRule(rule)
    return 'ok'
  }],
  ['PerformanceAnalysisKit.hidebug.disableGwpAsanGrayscale', async (params: Map<string, string>): Promise<string> => {
    hidebug.disableGwpAsanGrayscale()
    return 'ok'
  }],
  ['PerformanceAnalysisKit.hidebug.dumpJsHeapData', async (params: Map<string, string>): Promise<string> => {
    let filename = paramString(params, 'filename', '')
    hidebug.dumpJsHeapData(filename)
    return 'ok'
  }],
  ['PerformanceAnalysisKit.hidebug.dumpJsRawHeapData', async (params: Map<string, string>): Promise<string> => {
    let needGC = paramBoolean(params, 'needGC', false)
    let result = await hidebug.dumpJsRawHeapData(needGC)
    return result.toString()
  }],
  ['PerformanceAnalysisKit.hidebug.getAppVMObjectUsedSize', async (params: Map<string, string>): Promise<string> => {
    let result = hidebug.getAppVMObjectUsedSize()
    return result.toString()
  }],
  ['PerformanceAnalysisKit.hidebug.getCpuUsage', async (params: Map<string, string>): Promise<string> => {
    let result = hidebug.getCpuUsage()
    return result.toString()
  }],
  ['PerformanceAnalysisKit.hidebug.getGraphicsMemory', async (params: Map<string, string>): Promise<string> => {
    let result = await hidebug.getGraphicsMemory()
    return result.toString()
  }],
  ['PerformanceAnalysisKit.hidebug.getGraphicsMemorySync', async (params: Map<string, string>): Promise<string> => {
    let result = hidebug.getGraphicsMemorySync()
    return result.toString()
  }],
  ['PerformanceAnalysisKit.hidebug.getGwpAsanGrayscaleState', async (params: Map<string, string>): Promise<string> => {
    let result = hidebug.getGwpAsanGrayscaleState()
    return result.toString()
  }],
  ['PerformanceAnalysisKit.hidebug.getNativeHeapAllocatedSize', async (params: Map<string, string>): Promise<string> => {
    let result = hidebug.getNativeHeapAllocatedSize()
    return result.toString()
  }],
  ['PerformanceAnalysisKit.hidebug.getNativeHeapFreeSize', async (params: Map<string, string>): Promise<string> => {
    let result = hidebug.getNativeHeapFreeSize()
    return result.toString()
  }],
  ['PerformanceAnalysisKit.hidebug.getNativeHeapSize', async (params: Map<string, string>): Promise<string> => {
    let result = hidebug.getNativeHeapSize()
    return result.toString()
  }],
  ['PerformanceAnalysisKit.hidebug.getPrivateDirty', async (params: Map<string, string>): Promise<string> => {
    let result = hidebug.getPrivateDirty()
    return result.toString()
  }],
  ['PerformanceAnalysisKit.hidebug.getPss', async (params: Map<string, string>): Promise<string> => {
    let result = hidebug.getPss()
    return result.toString()
  }],
  ['PerformanceAnalysisKit.hidebug.getSharedDirty', async (params: Map<string, string>): Promise<string> => {
    let result = hidebug.getSharedDirty()
    return result.toString()
  }],
  ['PerformanceAnalysisKit.hidebug.getSystemCpuUsage', async (params: Map<string, string>): Promise<string> => {
    let result = hidebug.getSystemCpuUsage()
    return result.toString()
  }],
  ['PerformanceAnalysisKit.hidebug.getVMRuntimeStat', async (params: Map<string, string>): Promise<string> => {
    let item = paramString(params, 'item', '')
    let result = hidebug.getVMRuntimeStat(item)
    return result.toString()
  }],
  ['PerformanceAnalysisKit.hidebug.getVss', async (params: Map<string, string>): Promise<string> => {
    let result = hidebug.getVss()
    return result.toString()
  }],
  ['PerformanceAnalysisKit.hidebug.isDebugState', async (params: Map<string, string>): Promise<string> => {
    let result = hidebug.isDebugState()
    return result.toString()
  }],
  ['PerformanceAnalysisKit.hidebug.setProcDumpInSharedOOM', async (params: Map<string, string>): Promise<string> => {
    let enable = paramBoolean(params, 'enable', false)
    hidebug.setProcDumpInSharedOOM(enable)
    return 'ok'
  }],
  ['PerformanceAnalysisKit.hidebug.startJsCpuProfiling', async (params: Map<string, string>): Promise<string> => {
    let filename = paramString(params, 'filename', '')
    hidebug.startJsCpuProfiling(filename)
    return 'ok'
  }],
  ['PerformanceAnalysisKit.hidebug.stopAppTraceCapture', async (params: Map<string, string>): Promise<string> => {
    hidebug.stopAppTraceCapture()
    return 'ok'
  }],
  ['PerformanceAnalysisKit.hidebug.stopJsCpuProfiling', async (params: Map<string, string>): Promise<string> => {
    hidebug.stopJsCpuProfiling()
    return 'ok'
  }],
  ['PerformanceAnalysisKit.hilog.clean', async (params: Map<string, string>): Promise<string> => {
    hilog.clean()
    return 'ok'
  }],
  ['PerformanceAnalysisKit.hilog.flush', async (params: Map<string, string>): Promise<string> => {
    hilog.flush()
    return 'ok'
  }],
  ['PerformanceAnalysisKit.hilog.getOutputDir', async (params: Map<string, string>): Promise<string> => {
    let result = hilog.getOutputDir()
    return result.toString()
  }],
  ['PerformanceAnalysisKit.jsLeakWatcher.check', async (params: Map<string, string>): Promise<string> => {
    let result = jsLeakWatcher.check()
    return result.toString()
  }],
  ['PerformanceAnalysisKit.jsLeakWatcher.enable', async (params: Map<string, string>): Promise<string> => {
    let isEnable = paramBoolean(params, 'isEnable', false)
    jsLeakWatcher.enable(isEnable)
    return 'ok'
  }],
  ['SensorServiceKit.sensor.getDeviceAltitude', async (params: Map<string, string>): Promise<string> => {
    let seaPressure = paramFloat(params, 'seaPressure', 0)
    let currentPressure = paramFloat(params, 'currentPressure', 0)
    let result = await sensor.getDeviceAltitude(seaPressure, currentPressure)
    return result.toString()
  }],
  ['SensorServiceKit.vibrator.isHdHapticSupported', async (params: Map<string, string>): Promise<string> => {
    let result = vibrator.isHdHapticSupported()
    return result.toString()
  }],
  ['SensorServiceKit.vibrator.isSupportEffect', async (params: Map<string, string>): Promise<string> => {
    let effectId = paramString(params, 'effectId', '')
    let result = await vibrator.isSupportEffect(effectId)
    return result.toString()
  }],
  ['SensorServiceKit.vibrator.isSupportEffectSync', async (params: Map<string, string>): Promise<string> => {
    let effectId = paramString(params, 'effectId', '')
    let result = vibrator.isSupportEffectSync(effectId)
    return result.toString()
  }],
  ['TelephonyKit.call.canSetCallTransferTime', async (params: Map<string, string>): Promise<string> => {
    let slotId = paramInt(params, 'slotId', 0)
    let result = await call.canSetCallTransferTime(slotId)
    return result.toString()
  }],
  ['TelephonyKit.call.cancelMuted', async (params: Map<string, string>): Promise<string> => {
    await call.cancelMuted()
    return 'ok'
  }],
  ['TelephonyKit.call.closeUnfinishedUssd', async (params: Map<string, string>): Promise<string> => {
    let slotId = paramInt(params, 'slotId', 0)
    await call.closeUnfinishedUssd(slotId)
    return 'ok'
  }],
  ['TelephonyKit.call.combineConference', async (params: Map<string, string>): Promise<string> => {
    let callId = paramInt(params, 'callId', 0)
    await call.combineConference(callId)
    return 'ok'
  }],
  ['TelephonyKit.call.controlCamera', async (params: Map<string, string>): Promise<string> => {
    let callId = paramInt(params, 'callId', 0)
    let cameraId = paramString(params, 'cameraId', '')
    await call.controlCamera(callId, cameraId)
    return 'ok'
  }],
  ['TelephonyKit.call.disableImsSwitch', async (params: Map<string, string>): Promise<string> => {
    let slotId = paramInt(params, 'slotId', 0)
    await call.disableImsSwitch(slotId)
    return 'ok'
  }],
  ['TelephonyKit.call.getMainCallId', async (params: Map<string, string>): Promise<string> => {
    let callId = paramInt(params, 'callId', 0)
    let result = await call.getMainCallId(callId)
    return result.toString()
  }],
  ['TelephonyKit.call.hangUpCall', async (params: Map<string, string>): Promise<string> => {
    let callId = paramInt(params, 'callId', 0)
    await call.hangUpCall(callId)
    return 'ok'
  }],
  ['TelephonyKit.call.hasCall', async (params: Map<string, string>): Promise<string> => {
    let result = await call.hasCall()
    return result.toString()
  }],
  ['TelephonyKit.call.hasCallSync', async (params: Map<string, string>): Promise<string> => {
    let result = call.hasCallSync()
    return result.toString()
  }],
  ['TelephonyKit.call.hasVoiceCapability', async (params: Map<string, string>): Promise<string> => {
    let result = call.hasVoiceCapability()
    return result.toString()
  }],
  ['TelephonyKit.call.isImsSwitchEnabled', async (params: Map<string, string>): Promise<string> => {
    let slotId = paramInt(params, 'slotId', 0)
    let result = await call.isImsSwitchEnabled(slotId)
    return result.toString()
  }],
  ['TelephonyKit.call.isImsSwitchEnabledSync', async (params: Map<string, string>): Promise<string> => {
    let slotId = paramInt(params, 'slotId', 0)
    let result = call.isImsSwitchEnabledSync(slotId)
    return result.toString()
  }],
  ['TelephonyKit.call.isInEmergencyCall', async (params: Map<string, string>): Promise<string> => {
    let result = await call.isInEmergencyCall()
    return result.toString()
  }],
  ['TelephonyKit.call.isNewCallAllowed', async (params: Map<string, string>): Promise<string> => {
    let result = await call.isNewCallAllowed()
    return result.toString()
  }],
  ['TelephonyKit.call.isRinging', async (params: Map<string, string>): Promise<string> => {
    let result = await call.isRinging()
    return result.toString()
  }],
  ['TelephonyKit.call.makeCall', async (params: Map<string, string>): Promise<string> => {
    let phoneNumber = paramString(params, 'phoneNumber', '')
    await call.makeCall(phoneNumber)
    return 'ok'
  }],
  ['TelephonyKit.call.preloadCallUI', async (params: Map<string, string>): Promise<string> => {
    let result = await call.preloadCallUI()
    return result.toString()
  }],
  ['TelephonyKit.call.removeMissedIncomingCallNotification', async (params: Map<string, string>): Promise<string> => {
    await call.removeMissedIncomingCallNotification()
    return 'ok'
  }],
  ['TelephonyKit.call.sendCallUiEvent', async (params: Map<string, string>): Promise<string> => {
    let callId = paramInt(params, 'callId', 0)
    let eventName = paramString(params, 'eventName', '')
    await call.sendCallUiEvent(callId, eventName)
    return 'ok'
  }],
  ['TelephonyKit.call.separateConference', async (params: Map<string, string>): Promise<string> => {
    let callId = paramInt(params, 'callId', 0)
    await call.separateConference(callId)
    return 'ok'
  }],
  ['TelephonyKit.call.setCallWaiting', async (params: Map<string, string>): Promise<string> => {
    let slotId = paramInt(params, 'slotId', 0)
    let activate = paramBoolean(params, 'activate', false)
    await call.setCallWaiting(slotId, activate)
    return 'ok'
  }],
  ['TelephonyKit.call.setDisplaySurface', async (params: Map<string, string>): Promise<string> => {
    let callId = paramInt(params, 'callId', 0)
    let surfaceId = paramString(params, 'surfaceId', '')
    await call.setDisplaySurface(callId, surfaceId)
    return 'ok'
  }],
  ['TelephonyKit.call.setMuted', async (params: Map<string, string>): Promise<string> => {
    await call.setMuted()
    return 'ok'
  }],
  ['TelephonyKit.call.setPreviewSurface', async (params: Map<string, string>): Promise<string> => {
    let callId = paramInt(params, 'callId', 0)
    let surfaceId = paramString(params, 'surfaceId', '')
    await call.setPreviewSurface(callId, surfaceId)
    return 'ok'
  }],
  ['TelephonyKit.call.unloadCallUI', async (params: Map<string, string>): Promise<string> => {
    let result = await call.unloadCallUI()
    return result.toString()
  }],
  ['TelephonyKit.data.disableCellularDataRoaming', async (params: Map<string, string>): Promise<string> => {
    let slotId = paramInt(params, 'slotId', 0)
    await data.disableCellularDataRoaming(slotId)
    return 'ok'
  }],
  ['TelephonyKit.data.enableCellularDataRoaming', async (params: Map<string, string>): Promise<string> => {
    let slotId = paramInt(params, 'slotId', 0)
    await data.enableCellularDataRoaming(slotId)
    return 'ok'
  }],
  ['TelephonyKit.data.isCellularDataEnabled', async (params: Map<string, string>): Promise<string> => {
    let result = await data.isCellularDataEnabled()
    return result.toString()
  }],
  ['TelephonyKit.data.isCellularDataEnabledSync', async (params: Map<string, string>): Promise<string> => {
    let result = data.isCellularDataEnabledSync()
    return result.toString()
  }],
  ['TelephonyKit.data.isCellularDataRoamingEnabled', async (params: Map<string, string>): Promise<string> => {
    let slotId = paramInt(params, 'slotId', 0)
    let result = await data.isCellularDataRoamingEnabled(slotId)
    return result.toString()
  }],
  ['TelephonyKit.data.isCellularDataRoamingEnabledSync', async (params: Map<string, string>): Promise<string> => {
    let slotId = paramInt(params, 'slotId', 0)
    let result = data.isCellularDataRoamingEnabledSync(slotId)
    return result.toString()
  }],
  ['TelephonyKit.eSIM.isSupported', async (params: Map<string, string>): Promise<string> => {
    let slotId = paramInt(params, 'slotId', 0)
    let result = eSIM.isSupported(slotId)
    return result.toString()
  }],
  ['TelephonyKit.radio.factoryReset', async (params: Map<string, string>): Promise<string> => {
    let slotId = paramInt(params, 'slotId', 0)
    await radio.factoryReset(slotId)
    return 'ok'
  }],
  ['TelephonyKit.radio.getIMEI', async (params: Map<string, string>): Promise<string> => {
    let slotId = paramInt(params, 'slotId', 0)
    let result = await radio.getIMEI(slotId)
    return result.toString()
  }],
  ['TelephonyKit.radio.getIMEISV', async (params: Map<string, string>): Promise<string> => {
    let slotId = paramInt(params, 'slotId', 0)
    let result = radio.getIMEISV(slotId)
    return result.toString()
  }],
  ['TelephonyKit.radio.getISOCountryCodeForNetwork', async (params: Map<string, string>): Promise<string> => {
    let slotId = paramInt(params, 'slotId', 0)
    let result = await radio.getISOCountryCodeForNetwork(slotId)
    return result.toString()
  }],
  ['TelephonyKit.radio.getISOCountryCodeForNetworkSync', async (params: Map<string, string>): Promise<string> => {
    let slotId = paramInt(params, 'slotId', 0)
    let result = radio.getISOCountryCodeForNetworkSync(slotId)
    return result.toString()
  }],
  ['TelephonyKit.radio.getMEID', async (params: Map<string, string>): Promise<string> => {
    let slotId = paramInt(params, 'slotId', 0)
    let result = await radio.getMEID(slotId)
    return result.toString()
  }],
  ['TelephonyKit.radio.getUniqueDeviceId', async (params: Map<string, string>): Promise<string> => {
    let slotId = paramInt(params, 'slotId', 0)
    let result = await radio.getUniqueDeviceId(slotId)
    return result.toString()
  }],
  ['TelephonyKit.radio.isManualNetworkScanning', async (params: Map<string, string>): Promise<string> => {
    let slotId = paramInt(params, 'slotId', 0)
    let result = await radio.isManualNetworkScanning(slotId)
    return result.toString()
  }],
  ['TelephonyKit.radio.isNRSupported', async (params: Map<string, string>): Promise<string> => {
    let result = radio.isNRSupported()
    return result.toString()
  }],
  ['TelephonyKit.radio.isRadioOn', async (params: Map<string, string>): Promise<string> => {
    let slotId = paramInt(params, 'slotId', 0)
    let result = await radio.isRadioOn(slotId)
    return result.toString()
  }],
  ['TelephonyKit.radio.stopManualNetworkScan', async (params: Map<string, string>): Promise<string> => {
    let slotId = paramInt(params, 'slotId', 0)
    await radio.stopManualNetworkScan(slotId)
    return 'ok'
  }],
  ['TelephonyKit.sim.getMaxSimCount', async (params: Map<string, string>): Promise<string> => {
    let result = sim.getMaxSimCount()
    return result.toString()
  }],
  ['TelephonyKit.sim.hasOperatorPrivileges', async (params: Map<string, string>): Promise<string> => {
    let slotId = paramInt(params, 'slotId', 0)
    let result = await sim.hasOperatorPrivileges(slotId)
    return result.toString()
  }],
  ['TelephonyKit.sim.setShowName', async (params: Map<string, string>): Promise<string> => {
    let slotId = paramInt(params, 'slotId', 0)
    let name = paramString(params, 'name', '')
    await sim.setShowName(slotId, name)
    return 'ok'
  }],
  ['TelephonyKit.sms.getDefaultSmsSimId', async (params: Map<string, string>): Promise<string> => {
    let result = await sms.getDefaultSmsSimId()
    return result.toString()
  }],
  ['TelephonyKit.sms.getDefaultSmsSlotId', async (params: Map<string, string>): Promise<string> => {
    let result = await sms.getDefaultSmsSlotId()
    return result.toString()
  }],
  ['TelephonyKit.sms.getImsShortMessageFormat', async (params: Map<string, string>): Promise<string> => {
    let result = await sms.getImsShortMessageFormat()
    return result.toString()
  }],
  ['TelephonyKit.sms.getSmscAddr', async (params: Map<string, string>): Promise<string> => {
    let slotId = paramInt(params, 'slotId', 0)
    let result = await sms.getSmscAddr(slotId)
    return result.toString()
  }],
  ['TelephonyKit.sms.hasSmsCapability', async (params: Map<string, string>): Promise<string> => {
    let result = sms.hasSmsCapability()
    return result.toString()
  }],
  ['TelephonyKit.sms.isImsSmsSupported', async (params: Map<string, string>): Promise<string> => {
    let slotId = paramInt(params, 'slotId', 0)
    let result = await sms.isImsSmsSupported(slotId)
    return result.toString()
  }],
  ['TelephonyKit.sms.setDefaultSmsSlotId', async (params: Map<string, string>): Promise<string> => {
    let slotId = paramInt(params, 'slotId', 0)
    await sms.setDefaultSmsSlotId(slotId)
    return 'ok'
  }],
  ['TelephonyKit.sms.setSmscAddr', async (params: Map<string, string>): Promise<string> => {
    let slotId = paramInt(params, 'slotId', 0)
    let smscAddr = paramString(params, 'smscAddr', '')
    await sms.setSmscAddr(slotId, smscAddr)
    return 'ok'
  }],
  ['UniversalKeystoreKit.huksExternalCrypto.clearUkeyPinAuthState', async (params: Map<string, string>): Promise<string> => {
    let resourceId = paramString(params, 'resourceId', '')
    await huksExternalCrypto.clearUkeyPinAuthState(resourceId)
    return 'ok'
  }],
])

/**
 * Runs the real adapter for `target`, or answers with the same stub text
 * sdk.call has always used if this target doesn't have one yet -- callers
 * don't need to check first, and a target with no adapter is never the
 * reason a call hangs.
 */
export async function runSdkAdapter(target: string, params: Map<string, string>): Promise<string> {
  let adapter = ADAPTERS.get(target)
  if (adapter === undefined) {
    return 'error: sdk.call is not implemented yet'
  }
  try {
    return await adapter(params)
  } catch (e) {
    return 'error: ' + (e as Error).message
  }
}

/**
 * Whether `target` has a real row in ADAPTERS. Informational only -- the eval
 * and the sdk probe mark each result :impl/:stub with it. Search does not use
 * it: whether a target runs is not a relevance signal, and "sdk.call is not
 * implemented yet" is an acceptable answer.
 */
export function isSdkTargetImplemented(target: string): boolean {
  return ADAPTERS.has(target)
}
