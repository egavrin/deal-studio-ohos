/**
 * The in-app local Jev decision model: PR #62's Rust/Candle runner
 * (`native/local-jev`) built as `liblocaljev.so` (CMake target `localjev`) and
 * imported here. Kept in its own file — not in VeraLocalDecision.ets — so the
 * host TS checks (which load VeraCompose -> VeraLocalDecision) never try to
 * resolve the native module.
 *
 * `predict` returns the Jev-shaped {"answers":...} reply. For an uncalibrated
 * embedded model it is empty, which the hybrid route treats as "ask the cloud",
 * so this is safe before calibrated weights exist.
 *
 * The NPU serving graphs are packaged as rawfiles, one per fixed shape
 * (bucket). The first construction copies each to filesDir and registers it
 * with its (batch, seq); the engine compiles a bucket lazily on the first
 * group that fits it and picks the smallest bucket that fits. The candle CPU
 * path serves when no bucket is registered, fits, or builds.
 */
import nativeLocalJev from 'liblocaljev.so'
import { fileIo as fs } from '@kit.CoreFileKit'
import { resourceManager } from '@kit.LocalizationKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { LocalDecisionModel } from './VeraLocalDecision'
import { OperationCancellation } from './OperationCancellation'

const DOMAIN = 0x0000

let graphRegistered = false

/** The serving buckets, smallest first; a group takes the first that fits. */
const NPU_BUCKETS: [string, number, number][] = [
  ['hiai-graph-192.pb', 8, 192]
]

async function registerNpuGraph(context: Context): Promise<void> {
  if (graphRegistered) {
    return
  }
  graphRegistered = true
  try {
    let rm: resourceManager.ResourceManager = context.resourceManager
    let filesDir: string = context.filesDir
    for (let bucket of NPU_BUCKETS) {
      let name: string = bucket[0]
      let batch: number = bucket[1]
      let seq: number = bucket[2]
      let modelPath: string = filesDir + '/' + name
      let copy = false
      try {
        let stat = fs.statSync(modelPath)
        copy = stat.size < 1000
      } catch (_e) {
        copy = true
      }
      if (copy) {
        let data = await rm.getRawFileContent(name)
        let f = fs.openSync(modelPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC)
        fs.writeSync(f.fd, data.buffer)
        fs.closeSync(f)
      }
      nativeLocalJev.npuGraph(modelPath, batch, seq)
      hilog.info(DOMAIN, 'VERA-JEVLOCAL', 'npu bucket registered: ' + name + ' B=' + batch + ' S=' + seq)
    }
  } catch (e) {
    hilog.warn(DOMAIN, 'VERA-JEVLOCAL', 'no npu graph, cpu path: ' + (e as Error).message)
  }
}

export class NapiLocalDecision implements LocalDecisionModel {
  available(): boolean { return true }
  answer(body: string, _cancellation?: OperationCancellation): Promise<string> {
    return nativeLocalJev.predict(body)
  }
}

export class NpuNapiLocalDecision extends NapiLocalDecision {
  constructor(context: Context) {
    super()
    registerNpuGraph(context).catch((e: Error): void => {
      hilog.warn(DOMAIN, 'VERA-JEVLOCAL', 'graph registration failed: ' + e.message)
    })
  }
}
