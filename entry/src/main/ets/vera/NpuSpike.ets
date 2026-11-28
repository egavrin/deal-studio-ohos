/**
 * Phase 0/1 NPU-feasibility spike.
 *
 * Enumerates the MindSpore Lite NNRT devices, then loads the openJev decision
 * model (`jev.ms`, converted from the ONNX with IsNaN stripped and the two
 * Einsums rewritten to MatMul) on the CPU and on NNRT, resizes its dynamic
 * inputs to 1x256, runs one predict with zeroed inputs, and logs the result.
 *
 * Answers: is the Kirin NPU reachable (§7.1 Phase 0) and does the decision
 * model's converted graph build and run on it (Phase 1 operator coverage).
 *
 * Triggered by `hdc shell aa start ... --ps npuSpike 1`; the model is pushed to
 * `{filesDir}/npu/jev.ms`.
 */
import { mindSporeLite } from '@kit.MindSporeLiteKit'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN = 0x0000

function log(s: string): void {
  hilog.info(DOMAIN, 'VERA-NPUSPIKE', s)
  console.info('VERA-NPUSPIKE ' + s)
}

async function runOne(label: string, path: string, ctx: mindSporeLite.Context, dim: number[]): Promise<void> {
  let t0 = Date.now()
  try {
    let model = await mindSporeLite.loadModelFromFile(path, ctx)
    log(label + ' load OK')
    let inputs = model.getInputs()
    if (inputs === undefined || inputs === null) {
      log(label + ' getInputs undefined (ms=' + (Date.now() - t0).toString() + ')')
      return
    }
    let dims: Array<Array<number>> = []
    for (let i = 0; i < inputs.length; i++) { dims.push(dim) }
    try { model.resize(inputs, dims) } catch (e) { log(label + ' resize failed: ' + ((e as Error).message || String(e))) }
    let names: string[] = []
    for (let inp of inputs) {
      names.push(inp.name + '[' + inp.shape.join('x') + ']')
      try { inp.setData(new ArrayBuffer(inp.dataSize)) } catch (_e) {}
    }
    let outs = await model.predict(inputs)
    log(label + ' OK inputs=' + inputs.length.toString() + ' (' + names.join(',') + ') outputs=' +
      outs.length.toString() + ' ms=' + (Date.now() - t0).toString())
  } catch (e) {
    log(label + ' FAILED ms=' + (Date.now() - t0).toString() + ' err=' + ((e as Error).message || String(e)))
  }
}

export async function runNpuSpike(filesDir: string): Promise<void> {
  log('start filesDir=' + filesDir)

  // 1) Enumerate NNRT devices — is an accelerator (NPU) exposed?
  try {
    let descs = mindSporeLite.getAllNNRTDeviceDescriptions()
    log('nnrtDevices=' + descs.length.toString())
    for (let d of descs) {
      log('  dev id=' + d.deviceID().toString() + ' type=' + d.deviceType().toString() + ' name=' + d.deviceName())
    }
  } catch (e) {
    log('getAllNNRTDeviceDescriptions FAILED: ' + ((e as Error).message || String(e)))
  }

  let path = filesDir + '/npu/jev.ms'

  // 2) CPU baseline — does the converted decision model load and predict?
  let cpuCtx: mindSporeLite.Context = { target: ['cpu'], cpu: { threadNum: 4 } }
  await runOne('CPU', path, cpuCtx, [1, 256])

  // 3) NNRT (NPU path) — bind the accelerator device; NNRT needs nnrt:{deviceID,...}
  //    (with only {target:['nnrt']} the model has no device and getInputs is undefined).
  let nnrtCtx: mindSporeLite.Context = { target: ['nnrt'] }
  try {
    let descs = mindSporeLite.getAllNNRTDeviceDescriptions()
    let chosen = false
    for (let d of descs) {
      if (!chosen && d.deviceType() === mindSporeLite.NNRTDeviceType.NNRTDEVICE_ACCELERATOR) {
        nnrtCtx = { target: ['nnrt'], nnrt: { deviceID: d.deviceID(),
          performanceMode: mindSporeLite.PerformanceMode.PERFORMANCE_HIGH,
          priority: mindSporeLite.Priority.PRIORITY_HIGH } }
        chosen = true
        log('NNRT device bound id=' + d.deviceID().toString() + ' name=' + d.deviceName())
      }
    }
  } catch (e) {
    log('NNRT device bind failed: ' + ((e as Error).message || String(e)))
  }
  await runOne('NNRT', path, nnrtCtx, [1, 256])

  log('done')
}