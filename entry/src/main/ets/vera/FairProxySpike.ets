/**
 * Fair cloud-side run: `--ps fairProxy 1` reads {filesDir}/npu/bodies.json (an array of
 * {name, body}), calls askJevViaCloud(body) for each (the JevProxy — the app's cloud Jev
 * path — the SAME bodies the local model was scored on), retries on empty/timeout, and
 * writes {filesDir}/npu/proxy-answers.json ({name:{answers,elapsedMs,attempts,qAnswered}}).
 * This makes the local-vs-cloud comparison like-for-like: same bodies, same cloud the app
 * uses, same machine. Needs network (USB net); logs under VERA-FAIRPROXY.
 */
import { fileIo as fs } from '@kit.CoreFileKit'
import { askJevViaCloud } from './JevProxy'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN = 0x0000

function answersCount(s: string): number {
  try {
    let o = JSON.parse(s) as Record<string, Object>
    let a = o['answers'] as Record<string, Object>
    return (a === undefined || a === null) ? 0 : Object.keys(a).length
  } catch (_e) {
    return 0
  }
}

export async function runFairProxy(filesDir: string): Promise<void> {
  let inp = filesDir + '/npu/bodies.json'
  let out = filesDir + '/npu/proxy-answers.json'
  hilog.info(DOMAIN, 'VERA-FAIRPROXY', 'start read=' + inp)
  let arr: Array<Record<string, string>> = []
  try {
    let txt = fs.readTextSync(inp)
    arr = JSON.parse(txt) as Array<Record<string, string>>
  } catch (e) {
    hilog.error(DOMAIN, 'VERA-FAIRPROXY', 'read failed: ' + (e as Error).message)
    return
  }
  hilog.info(DOMAIN, 'VERA-FAIRPROXY', 'bodies=' + arr.length)
  let results: Record<string, Object> = {}
  for (let b of arr) {
    let name = b['name']
    let body = b['body']
    let qTotal = 0
    try {
      let bo = JSON.parse(body) as Record<string, Object>
      qTotal = Object.keys(bo['questions'] as Record<string, Object>).length
    } catch (_e) {}
    let t0 = Date.now()
    let ans = ''
    let best = 0
    let att = 0
    for (att = 1; att <= 3; att++) {
      try {
        let r = (await askJevViaCloud(body)) as string
        let c = answersCount(r)
        if (c > best) { best = c; ans = r }
        if (c >= qTotal) { break }
      } catch (e) {
        hilog.error(DOMAIN, 'VERA-FAIRPROXY', name + ' attempt ' + att + ' err ' + (e as Error).message)
      }
    }
    let dt = Date.now() - t0
    let entry: Record<string, Object> = {}
    entry['answers'] = ans
    entry['elapsedMs'] = dt
    entry['attempts'] = att
    entry['qTotal'] = qTotal
    entry['qAnswered'] = best
    results[name] = entry
    hilog.info(DOMAIN, 'VERA-FAIRPROXY', name + ' ' + dt + 'ms answered=' + best + '/' + qTotal + ' attempts=' + att)
  }
  try {
    let f = fs.openSync(out, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC)
    fs.writeSync(f.fd, JSON.stringify(results))
    fs.closeSync(f)
    hilog.info(DOMAIN, 'VERA-FAIRPROXY', 'done written ' + out)
  } catch (e) {
    hilog.error(DOMAIN, 'VERA-FAIRPROXY', 'write failed: ' + (e as Error).message)
  }
}