/**
 * The resources find_intent_function and find_sdk_function search, loaded the way
 * the Generate screen loads them: intent summaries first, then the phone's own
 * registry, then the bundled embeddings, and the same for the SDK index.
 *
 * A screen that lets the model call those tools has to run this. Without the
 * summaries the intent index is nearly empty -- a chat widget that asked for
 * "navigate to a place" got no candidate back and had to guess -- and the
 * Generate screen's copy of these steps is easy to leave behind when it grows.
 *
 * Fire and forget: the tools fall back to token search while anything here is
 * still loading, so nothing waits on it. The EmbeddingGemma model is used only if
 * it is already on the phone; downloading it stays the Generate screen's job.
 */

import resourceManager from '@ohos.resourceManager'
import { loadIntentSummaries } from './VeraIntentIndex'
import { loadRegistry } from './VeraIntentRegistry'
import { ensureIntentEmbeddings, intentEmbeddingsReady } from './VeraIntentEmbeddingCache'
import { loadSdkIndex } from './VeraSdkIndex'
import { ensureSdkEmbeddings, sdkEmbeddingsReady } from './VeraSdkEmbeddingCache'
import { embedModelExists, loadEmbeddingModel } from './VeraEmbeddings'

/**
 * Resolves once the intent pool (summaries and registry) and the SDK index are
 * loaded -- what a search needs to find anything. The embeddings keep loading
 * after that; until they are ready the searches use tokens.
 */
export function loadDiscovery(filesDir: string, mgr: resourceManager.ResourceManager): Promise<void> {
  let intents = loadIntentSummaries(mgr).then(() => loadRegistry()).then((count: number) => {
    console.info('VERA-REGISTRY ' + count.toString() + ' intents available to find_intent_function')
    ensureIntentEmbeddings(filesDir, mgr).then(() => {
      console.info('VERA-INTENT-EMBED ready=' + intentEmbeddingsReady().toString())
    })
  })
  let sdk = loadSdkIndex(mgr).then((count: number) => {
    console.info('VERA-SDK ' + count.toString() + ' sdk functions available to search')
    ensureSdkEmbeddings(filesDir, mgr).then(() => {
      console.info('VERA-SDK-EMBED ready=' + sdkEmbeddingsReady().toString())
    })
  })
  if (embedModelExists(filesDir)) {
    loadEmbeddingModel(filesDir).then((ok: boolean) => {
      if (!ok) { return }
      ensureSdkEmbeddings(filesDir, mgr)
      ensureIntentEmbeddings(filesDir, mgr)
    })
  }
  return Promise.all([intents, sdk]).then((): void => {})
}
