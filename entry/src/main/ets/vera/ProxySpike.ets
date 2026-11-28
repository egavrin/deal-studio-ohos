/**
 * Cloud (JevProxy) latency probe: `--ps proxySpike 1` times one `askJevViaCloud` call —
 * the on-device cloud decision path (settings.useJevProxy → the configured cloud model) —
 * on a small Jev body, so cloud per-decision time can be compared with the local CPU time.
 * Uses the app's stored key/settings; needs network (the USB-network path is up when set).
 * Logs under VERA-PROXYSPIKE.
 */
import { askJevViaCloud } from './JevProxy'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN = 0x0000

const BODY: string = '{"state":"Request: a simple tip calculator with bill, tip percent and people","questions":{' +
  '"theme":{"type":"choice","instructions":"Which overall look fits this app best?",' +
  '"criteria":{"clean":"clean and restrained","soft":"soft and rounded","expressive":"bold and expressive",' +
  '"technical":"precise and technical","playful":"playful and bright"}},' +
  '"unit.bill":{"type":"noul","instructions":"Is the bill amount measured in money?"},' +
  '"expr.total":{"type":"choice","instructions":"How is the total worked out?",' +
  '"criteria":{"formula":"a formula on the values","row":"a row of the values"}}}}'

export async function runProxySpike(): Promise<void> {
  hilog.info(DOMAIN, 'VERA-PROXYSPIKE', 'start (3 questions)')
  try {
    let t0 = Date.now()
    let r: string = (await askJevViaCloud(BODY)) as string
    let dt = Date.now() - t0
    hilog.info(DOMAIN, 'VERA-PROXYSPIKE', 'cloud ' + dt + 'ms len=' + r.length + ' head=' + r.substring(0, 200))
  } catch (e) {
    hilog.error(DOMAIN, 'VERA-PROXYSPIKE', 'failed: ' + (e as Error).message)
  }
}