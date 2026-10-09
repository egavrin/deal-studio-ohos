/**
 * Harness stub for VeraSdkIndex.ets.
 *
 * VeraCompiler.ts needs exactly one export from the real module --
 * isValidSdkTarget, used only to validate an std/sdk.call target string. The
 * real module pulls in @ohos.resourceManager, @ohos.hilog, LlamaEngine.ets
 * (which itself pulls in @ohos.file.fs and libllama.so) and
 * VeraIntentRegistry.ets (@ohos.app.ability.insightIntentDriver) -- none of
 * it reachable under plain Node, and none of it exercised by a std/ui-only
 * program, which is all this harness compiles.
 *
 * A std/ui-only program never calls std/sdk, so this function's real
 * behaviour is never on the path being checked here. Returning true for
 * anything of the right shape is enough to keep the compiler's own
 * std/sdk.call diagnostic (VeraCompiler.ts, the isValidSdkTarget call site)
 * from firing on a program this harness was never asked to validate that
 * part of.
 */
export function isValidSdkTarget(target: string): boolean {
  return typeof target === 'string' && target.length > 0
}
