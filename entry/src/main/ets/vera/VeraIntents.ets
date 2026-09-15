/**
 * The only place in the project that calls the platform's intent framework.
 *
 * Nothing here knows the name of any intent: the target, the parameter names
 * and the accepted values all arrive as an IntentSpec from VeraIntentCatalog.
 * Adding an intent therefore never touches this file.
 *
 * insightIntentDriver is a system API, gated twice over: the provision profile
 * must carry "app-feature": "hos_system_app" (otherwise every call is 202) and
 * ohos.permission.EXECUTE_INSIGHT_INTENT must be granted through the profile's
 * acls.allowed-acls (otherwise 201). Both are signing, not code, so the
 * failures are reported as they arrive rather than hidden -- the status string
 * is what the generated program shows its user.
 */

import insightIntentDriver from '@ohos.app.ability.insightIntentDriver'
import insightIntent from '@ohos.app.ability.insightIntent'
import hilog from '@ohos.hilog'
import { BusinessError } from '@ohos.base'
import { IntentSpec } from './VeraIntentCatalog'

const DOMAIN = 0x0000

/**
 * Field values as the program wrote them, translated into the payload the
 * platform expects: catalogue names become platform names, catalogue values
 * become platform values, and an empty string means "omit" -- which is how a
 * language with no optional record fields expresses an optional parameter.
 *
 * A platformName may be a dotted path, and that is what lets the scalar record
 * reach an object parameter. Eleven parameters in the standard catalogue are
 * objects -- StartNavigate's dstLocation and srcLocation among them -- and every
 * one of them is a flat bag of strings in the specification's own examples:
 *
 *   dstLocation = { locationSystem, poiId, locationName, longitude, latitude, address }
 *
 * So the program writes a flat record with a field per leaf, and the nesting
 * happens here. The language, the compiler and the bytecode never learn that
 * objects exist.
 */
function buildParams(spec: IntentSpec, values: Map<string, string>): Record<string, Object> {
  let params: Record<string, Object> = {}
  for (let p of spec.params) {
    let raw = values.get(p.name)
    if (raw === undefined) { continue }
    let text = raw as string
    if (text.length === 0) { continue }
    let mapped = p.valueMap.get(text)
    let out: string = mapped !== undefined ? mapped as string : text
    let value: Object = p.kind === 'int' ? Number.parseInt(out, 10) as Object : out as Object
    let dot = p.platformName.indexOf('.')
    if (dot < 0) {
      params[p.platformName] = value
      continue
    }
    // One level is all the catalogue ever asks for, so this does not recurse.
    let group = p.platformName.substring(0, dot)
    let leaf = p.platformName.substring(dot + 1)
    let nested = params[group] as Record<string, Object> | undefined
    if (nested === undefined) {
      nested = {} as Record<string, Object>
      params[group] = nested as Object
    }
    nested![leaf] = value
  }
  return params
}

/**
 * Runs one intent and describes the outcome in a line a person can read.
 *
 * The code in a resolved ExecuteResult is chosen by the target's developer, not
 * by the framework, so a non-zero code is the target talking -- PlayMusicList
 * answers 100060202 for a delisted playlist -- and is reported as such rather
 * than as a failed call.
 */
export async function runIntent(spec: IntentSpec, values: Map<string, string>): Promise<string> {
  let params = buildParams(spec, values)
  let param: insightIntentDriver.ExecuteParam = {
    bundleName: spec.bundle,
    moduleName: spec.moduleName,
    abilityName: spec.ability,
    insightIntentName: spec.intentName,
    insightIntentParam: params,
    // Which mode is on the row, not a fixed choice here: a target that declares
    // only foreground rejects a background call, and one that supports both
    // should not seize the screen for something the user only wanted to hear.
    executeMode: spec.mode === 'background'
      ? insightIntent.ExecuteMode.UI_ABILITY_BACKGROUND
      : insightIntent.ExecuteMode.UI_ABILITY_FOREGROUND
  }
  hilog.info(DOMAIN, 'VERA', 'VERA-INTENT ' + spec.intentName + ' -> ' + spec.bundle + '/' +
    spec.moduleName + '/' + spec.ability + ' mode=' + spec.mode +
    ' params=' + JSON.stringify(params))
  try {
    let result: insightIntent.ExecuteResult = await insightIntentDriver.execute(param)
    if (result.code === 0) {
      hilog.info(DOMAIN, 'VERA', 'VERA-INTENT ' + spec.intentName + ' ok')
      return 'ok'
    }
    hilog.info(DOMAIN, 'VERA', 'VERA-INTENT ' + spec.intentName + ' declined ' + result.code.toString())
    return 'declined code=' + result.code.toString()
  } catch (e) {
    let err = e as BusinessError
    hilog.error(DOMAIN, 'VERA', 'VERA-INTENT ' + spec.intentName + ' failed ' + err.code.toString() +
      ': ' + err.message)
    return 'error ' + err.code.toString() + ': ' + err.message
  }
}
