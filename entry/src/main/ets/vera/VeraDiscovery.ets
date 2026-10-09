/** Shared discovery indexes. VeraCapabilities owns background model and cache preparation. */
import resourceManager from '@ohos.resourceManager'
import { loadIntentSummaries } from './VeraIntentIndex'
import { loadRegistry } from './VeraIntentRegistry'
import { loadSdkIndex } from './VeraSdkIndex'

let discovery: Promise<void> | null = null

/** Concurrent screens share one load. Index readiness does not wait for the embedding model. */
export function loadDiscovery(_filesDir: string, mgr: resourceManager.ResourceManager): Promise<void> {
  if (discovery === null) {
    let intents = loadIntentSummaries(mgr).then(() => loadRegistry()).then((count: number): void => {
      console.info('VERA-REGISTRY ' + count.toString() + ' intents available to find_intent_function')
    })
    let sdk = loadSdkIndex(mgr).then((count: number): void => {
      console.info('VERA-SDK ' + count.toString() + ' sdk functions available to search')
    })
    discovery = Promise.all([intents, sdk]).then((): void => {})
  }
  return discovery!
}
