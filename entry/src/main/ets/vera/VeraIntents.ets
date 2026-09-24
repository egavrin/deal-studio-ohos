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
import { AbilityContext } from './VeraCalendar'
import Want from '@ohos.app.ability.Want'

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
  // The row's own constants first: they are what makes this row a named
  // function rather than a generic intent, and the program cannot reach them.
  // Written before the program's values so the two never fight over a key;
  // a row that needs a key to be writable declares it as a parameter instead.
  spec.fixed.forEach((value: string, key: string) => { writeParam(params, key, value) })
  for (let p of spec.params) {
    let raw = values.get(p.name)
    let text = raw === undefined ? '' : raw as string
    // An empty field means "omit" -- unless the row has something sensible to
    // say in its place, which is how a parameter that is optional to the
    // program but mandatory to the target is spelled.
    if (text.length === 0) {
      if (p.defaultValue.length === 0) { continue }
      text = p.defaultValue
    }
    let mapped = p.valueMap.get(text)
    let out: string = mapped !== undefined ? mapped as string : text
    let value: Object = p.kind === 'int' ? Number.parseInt(out, 10) as Object : out as Object
    writeParam(params, p.platformName, value)
  }
  return params
}

/**
 * One key of the payload, where a dotted name means one level of nesting.
 *
 * Shared by the row's constants and the program's values, so both reach an
 * object parameter the same way -- a row may well fix dstLocation.locationSystem
 * while the program writes the coordinates.
 */
function writeParam(params: Record<string, Object>, platformName: string, value: Object): void {
  let dot = platformName.indexOf('.')
  if (dot < 0) {
    params[platformName] = value
    return
  }
  // One level is all the catalogue ever asks for, so this does not recurse.
  let group = platformName.substring(0, dot)
  let leaf = platformName.substring(dot + 1)
  let nested = params[group] as Record<string, Object> | undefined
  if (nested === undefined) {
    nested = {} as Record<string, Object>
    params[group] = nested as Object
  }
  nested![leaf] = value
}

/**
 * What the handler is told when the call succeeded.
 *
 * 'ok' for a row that asks for nothing back, which is every row that exists to
 * make something happen. A reading row names one field of the answer, and that
 * field's value comes back as a string, translated out of the platform's
 * spelling the same way the arguments were translated into it -- bluetooth
 * answers switchFlag 0 for ON, and the program should never see that 0.
 *
 * A field the target did not send is not an error: settings answer with
 * different shapes depending on what they know, and a program that asked for a
 * reading and got 'unknown' can say so. Guessing here would be worse.
 */
function readAnswer(spec: IntentSpec, result: insightIntent.ExecuteResult): string {
  if (spec.resultField.length === 0) { return 'ok' }
  let payload = result.result
  if (payload === undefined || payload === null) { return 'unknown' }
  let record = payload as Record<string, Object>
  let value = record[spec.resultField]
  if (value === undefined || value === null) { return 'unknown' }
  let text = typeof value === 'string' ? value as string : JSON.stringify(value)
  let mapped = spec.resultMap.get(text)
  return mapped !== undefined ? mapped as string : text
}

/**
 * An intent named by the program rather than by the catalogue.
 *
 * Everything the catalogue does for a row -- translate names, translate values,
 * fill constants, pick the mode, decide what comes back -- is the program's
 * problem here, because none of it can be known for an intent nobody has
 * written down. What this function still does is the part that is always true:
 * it refuses a malformed target, it reports what the platform said rather than
 * interpreting it, and it writes the whole call into the log so there is a
 * record of what a generated program asked the phone to do.
 *
 * The answer is the target's own result, as JSON, because a raw caller has no
 * row to say which field it wanted.
 */
export async function runRawIntent(target: string, values: Map<string, string>, mode: string): Promise<string> {
  let parts = target.split('/')
  if (parts.length !== 4) { return 'error: target must be bundle/module/ability/IntentName' }
  // The program wrote names and values; the object is built here, so a line
  // break or a quote in someone's shopping list cannot break the payload.
  let params: Record<string, Object> = {}
  values.forEach((value: string, key: string) => { writeParam(params, key, value as Object) })
  let param: insightIntentDriver.ExecuteParam = {
    bundleName: parts[0].trim(),
    moduleName: parts[1].trim(),
    abilityName: parts[2].trim(),
    insightIntentName: parts[3].trim(),
    insightIntentParam: params,
    executeMode: mode === 'foreground'
      ? insightIntent.ExecuteMode.UI_ABILITY_FOREGROUND
      : insightIntent.ExecuteMode.UI_ABILITY_BACKGROUND
  }
  hilog.info(DOMAIN, 'VERA', 'VERA-INTENT-RAW ' + target + ' mode=' + mode +
    ' params=' + JSON.stringify(params))
  try {
    let result: insightIntent.ExecuteResult = await insightIntentDriver.execute(param)
    let payload = result.result === undefined || result.result === null
      ? '' : JSON.stringify(result.result)
    hilog.info(DOMAIN, 'VERA', 'VERA-INTENT-RAW ' + target + ' code=' +
      result.code.toString() + ' result=' + (payload.length > 0 ? payload : '(none)'))
    if (result.code !== 0) { return 'declined code=' + result.code.toString() }
    // A zero is the target saying it accepted the call, and nothing more: on
    // this phone the clock answers 0 to CreateTimer and creates no timer. The
    // program is told 'ok' and should not claim more than that either.
    return payload.length > 0 ? payload : 'ok'
  } catch (e) {
    let err = e as BusinessError
    hilog.error(DOMAIN, 'VERA', 'VERA-INTENT-RAW ' + target + ' failed ' +
      err.code.toString() + ': ' + err.message)
    return 'error ' + err.code.toString() + ': ' + err.message
  }
}

/**
 * Opens the target's ability directly, for rows that have nothing to tell it.
 *
 * This is ordinary public API -- no intent framework, no system signature -- and
 * it is the right tool when the whole request is "show me that app".
 */
async function launchTarget(spec: IntentSpec): Promise<string> {
  let context = AbilityContext.value
  if (context === null) { return 'error: no ability context yet' }
  let want: Want = { bundleName: spec.bundle, abilityName: spec.ability }
  hilog.info(DOMAIN, 'VERA', 'VERA-LAUNCH ' + spec.bundle + '/' + spec.ability)
  try {
    await context.startAbility(want)
    return 'ok'
  } catch (e) {
    let err = e as BusinessError
    hilog.error(DOMAIN, 'VERA', 'VERA-LAUNCH failed ' + err.code.toString() + ': ' + err.message)
    return 'error ' + err.code.toString() + ': ' + err.message
  }
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
  if (spec.via === 'launch') { return launchTarget(spec) }
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
      let answer = readAnswer(spec, result)
      hilog.info(DOMAIN, 'VERA', 'VERA-INTENT ' + spec.intentName + ' ok -> ' + answer)
      return answer
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
