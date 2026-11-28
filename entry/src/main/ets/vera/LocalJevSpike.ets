/**
 * On-device local-Jev inference spike: times Candle forward passes on the Kirin
 * CPU through the `localjev` native module — one diagnosticScores (real logits)
 * and one predict — on a small Jev body, and logs them under VERA-LOCALJEV.
 *
 * Triggered by `hdc shell aa start ... --ps localJevSpike 1`. Requires the build
 * with embedded Laya weights (cross-build with LAYA_BUNDLE_DIR); the public Laya
 * bundle is uncalibrated, so predict returns empty answers but diagnosticScores
 * still runs the model (that is the latency datum).
 */
import nativeLocalJev from 'liblocaljev.so'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN = 0x0000

function log(s: string): void {
  hilog.info(DOMAIN, 'VERA-LOCALJEV', s)
  console.info('VERA-LOCALJEV ' + s)
}

// A small, fixed Jev body (theme choice, a noul, an expr choice).
const BODY: string = '{"state":"Request: a simple tip calculator with bill, tip percent and people","questions":{' +
  '"theme":{"type":"choice","instructions":"Which overall look fits this app best?",' +
  '"criteria":{"clean":"clean and restrained","soft":"soft and rounded","expressive":"bold and expressive",' +
  '"technical":"precise and technical","playful":"playful and bright"}},' +
  '"unit.bill":{"type":"noul","instructions":"Is the bill amount measured in money?"},' +
  '"expr.total":{"type":"choice","instructions":"How is the total worked out?",' +
  '"criteria":{"formula":"a formula on the values","row":"a row of the values"}}}}'

export async function runLocalJevSpike(): Promise<void> {
  try {
    let abiVal: number = nativeLocalJev.abi() as number
    log('abi=' + abiVal)
    let t0: number = Date.now()
    let diag: string = (await nativeLocalJev.diagnosticScores(BODY)) as string
    log('diagnostic ' + (Date.now() - t0) + 'ms len=' + diag.length + ' head=' + diag.substring(0, 240))
    let t1: number = Date.now()
    let pred: string = (await nativeLocalJev.predict(BODY)) as string
    log('predict ' + (Date.now() - t1) + 'ms len=' + pred.length + ' head=' + pred.substring(0, 240))
  } catch (e) {
    hilog.error(DOMAIN, 'VERA-LOCALJEV', 'spike failed: ' + (e as Error).message)
  }
}