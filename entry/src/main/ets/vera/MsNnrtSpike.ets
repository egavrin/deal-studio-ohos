/**
 * Trigger the MindSpore Lite C-NDK NNRT probe: `--ps nnrtSpike 1` runs
 * `msnnrt.run(jev.ms)` — a C++ NAPI that loads the converted model with an NNRT
 * accelerator device and predicts, bypassing the ArkTS mindSporeLite API (whose
 * getInputs() is undefined for NNRT). Results are logged under VERA-MSNNRT.
 */
import nativeMsnnrt from 'libmsnnrt.so'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { resourceManager } from '@kit.LocalizationKit'

const DOMAIN = 0x0000

export async function runMsNnrtSpike(filesDir: string, context?: Context): Promise<void> {
  let path = filesDir + '/npu/jev.ms'
  hilog.info(DOMAIN, 'VERA-MSNNRT', 'start path=' + path)
  try {
    // The converted model rides in the HAP's rawfile and lands in filesDir on
    // first run, so no host download is needed to probe a fresh phone.
    if (context !== undefined && !fs.accessSync(path)) {
      let rm: resourceManager.ResourceManager = context.resourceManager
      let data = await rm.getRawFileContent('jev-fill.ms')
      fs.mkdirSync(filesDir + '/npu', true)
      let f = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC)
      fs.writeSync(f.fd, data.buffer)
      fs.closeSync(f)
      hilog.info(DOMAIN, 'VERA-MSNNRT', 'rawfile -> file: ' + path + ' (' + data.byteLength + ')')
    }
    let r: string = (await nativeMsnnrt.run(path)) as string
    hilog.info(DOMAIN, 'VERA-MSNNRT', 'result ' + r)
  } catch (e) {
    hilog.error(DOMAIN, 'VERA-MSNNRT', 'failed: ' + (e as Error).message)
  }
}

/**
 * The HiAI Foundation probe: `--ps hiaiSpike 1` asks whether this app's process
 * can load the system libhiai.so (HiAI Model Runtime, the realistic NPU path —
 * NNRT's HDI service is not deployed on this device) and see the NPU. Logged
 * under VERA-HIAI.
 */
export async function runHiaiSpike(): Promise<void> {
  hilog.info(DOMAIN, 'VERA-HIAI', 'start')
  try {
    let r: string = (await nativeMsnnrt.hiaiProbe()) as string
    hilog.info(DOMAIN, 'VERA-HIAI', 'result ' + r)
  } catch (e) {
    hilog.error(DOMAIN, 'VERA-HIAI', 'failed: ' + (e as Error).message)
  }
}

/**
 * The HiAI end-to-end spike: `--ps hiaiE2E 1` builds a MatMul graph, compiles
 * it on-device, loads and runs it through the HiAI Model Runtime — the gate
 * test for the NPU path (the same flow as root was rejected by hiaiserver's
 * uid rule; this decides whether an app uid passes). Logged under VERA-HIAI.
 */
/**
 * The large-model HiAI test: --ps hiaiModel 1 downloads the generated model
 * (served on the host via hdc rport) and the input embedding, then builds and
 * runs it through the HiAI Model Runtime on the NPU.
 */
export async function runHiaiModelSpike(context: Context): Promise<void> {
  hilog.info(DOMAIN, 'VERA-HIAI', 'model test start')
  try {
    // Every hiai-model-<variant>.pb in rawfile (with its .input) is landed in
    // filesDir and built+run in turn, so one install bisects which graph
    // subset the runtime accepts.
    let rm: resourceManager.ResourceManager = context.resourceManager
    let filesDir: string = context.filesDir
    let variants: string[] = ['2l']
    for (let v of variants) {
      let modelPath: string = filesDir + '/hiai-model-' + v + '.pb'
      let inputPath: string = filesDir + '/hiai-model-' + v + '.input'
      try {
        let names: string[] = ['hiai-model-' + v + '.pb', 'hiai-model-' + v + '.input']
        let paths: string[] = [modelPath, inputPath]
        for (let i = 0; i < names.length; i++) {
          let data = await rm.getRawFileContent(names[i])
          let f = fs.openSync(paths[i], fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC)
          fs.writeSync(f.fd, data.buffer)
          fs.closeSync(f)
        }
        let r: string = (await nativeMsnnrt.hiaiModelTest(modelPath, inputPath)) as string
        hilog.info(DOMAIN, 'VERA-HIAI', 'model[' + v + '] result ' + r)
      } catch (e) {
        hilog.info(DOMAIN, 'VERA-HIAI', 'model[' + v + '] not in rawfile, skipped: ' + (e as Error).message.substring(0, 60))
      }
    }
  } catch (e) {
    hilog.error(DOMAIN, 'VERA-HIAI', 'model test failed: ' + (e as Error).message)
  }
}

export async function fileReadTestSpike(): Promise<void> {
  hilog.info(DOMAIN, 'VERA-HIAI', 'file read test start')
  try {
    let r: string = (await nativeMsnnrt.fileReadTest()) as string
    hilog.info(DOMAIN, 'VERA-HIAI', 'file read: ' + r)
  } catch (e) {
    hilog.error(DOMAIN, 'VERA-HIAI', 'file read failed: ' + (e as Error).message)
  }
}

export async function runHiaiOpsSpike(): Promise<void> {
  hilog.info(DOMAIN, 'VERA-HIAI', 'ops battery start')
  try {
    let r: string = (await nativeMsnnrt.hiaiOps()) as string
    hilog.info(DOMAIN, 'VERA-HIAI', 'ops battery ' + r)
  } catch (e) {
    hilog.error(DOMAIN, 'VERA-HIAI', 'ops battery failed: ' + (e as Error).message)
  }
}

export async function runHiaiE2ESpike(): Promise<void> {
  hilog.info(DOMAIN, 'VERA-HIAI', 'e2e start')
  try {
    let r: string = (await nativeMsnnrt.hiaiE2E()) as string
    hilog.info(DOMAIN, 'VERA-HIAI', 'e2e result ' + r)
  } catch (e) {
    hilog.error(DOMAIN, 'VERA-HIAI', 'e2e failed: ' + (e as Error).message)
  }
}