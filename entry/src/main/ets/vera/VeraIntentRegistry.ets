/**
 * Every intent installed on this phone, as the system itself records them.
 *
 * The catalogue in VeraIntentCatalog is what has been checked: contracts read,
 * calls watched working, values translated. This is the other thing -- the
 * phone's own list, all of it, checked by nobody. It exists so a generated
 * program can reach something the catalogue never described, through
 * intent.call, and the two are kept apart on purpose:
 *
 *   the catalogue says "this works, and here is what to write"
 *   the registry says "this exists here, at this address"
 *
 * Neither the model nor the program can turn the second into the first. What
 * the registry gives a model is an address it would otherwise have to invent,
 * and inventing addresses is how a generated program ends up calling nothing at
 * all: the platform accepts a wrong bundle name with the same silence it gives
 * a right one.
 *
 * Reading it needs ohos.permission.GET_BUNDLE_INFO_PRIVILEGED and a system
 * signature, the same pair execute() needs (see module.json5). Without them the
 * list is simply empty and everything here degrades to "the catalogue only",
 * which is what the app did before this file existed.
 */

import insightIntentDriver from '@ohos.app.ability.insightIntentDriver'
import hilog from '@ohos.hilog'

const DOMAIN = 0x0000

/** One installed intent, flattened to what a prompt can use. */
export class RegistryEntry {
  /** bundle/module/ability/IntentName -- exactly what intent.call takes. */
  target: string = ''
  intentName: string = ''
  bundle: string = ''
  /** 'background', 'foreground', or both separated by a space. */
  modes: string = ''
  /** Our own grouping, from the bundle name; the platform's domain field is mostly empty. */
  domain: string = ''
  /** Parameter names the app declares, if it declares any. Most declare none. */
  params: string[] = []
  /** displayName or keywords, when the app bothered to write them. */
  words: string = ''
}

/**
 * Which part of the phone a bundle belongs to.
 *
 * The platform has a domain field of its own and it is useless here: on this
 * device 394 of 747 intents call themselves ToolsDomain and 71 say nothing. So
 * the grouping is ours, by bundle name, and it only has to be good enough to
 * answer "does this request need that part of the phone".
 */
const DOMAIN_RULES: string[][] = [
  ['maps', 'maps|amap|navi|taxi'],
  ['calendar', 'calendar'],
  ['clock', 'clock|alarm'],
  ['music', 'music|himovie|audio'],
  ['notes', 'notepad|aidataservice|todo'],
  ['photos', 'photos|gallery|camera|screenshot'],
  ['messaging', 'meetime|mms|contacts|instantshare'],
  ['money', 'payment|wallet|alipay'],
  ['settings', 'settings|batterycare|communicationsetting|audioaccessorymanager|simcard'],
]

function domainOf(bundle: string): string {
  for (let rule of DOMAIN_RULES) {
    if (new RegExp(rule[1]).test(bundle)) { return rule[0] }
  }
  return 'system'
}

let cache: RegistryEntry[] = []
let loaded = false

/**
 * Reads the registry once and remembers it.
 *
 * Once, because it changes only when apps are installed, and the read is worth
 * hundreds of milliseconds that would otherwise sit in front of every
 * generation. Failure is not an error: an empty list means the prompt carries
 * the catalogue alone.
 */
export async function loadRegistry(): Promise<number> {
  if (loaded) { return cache.length }
  loaded = true
  try {
    let infos = await insightIntentDriver.getAllInsightIntentInfo(
      insightIntentDriver.GetInsightIntentFlag.GET_FULL_INSIGHT_INTENT)
    let entries: RegistryEntry[] = []
    for (let info of infos) {
      let entry = flatten(info)
      if (entry !== null) { entries.push(entry!) }
    }
    cache = entries
    hilog.info(DOMAIN, 'VERA', 'VERA-REGISTRY loaded ' + cache.length.toString() +
      ' of ' + infos.length.toString() + ' installed intents')
  } catch (e) {
    hilog.warn(DOMAIN, 'VERA', 'VERA-REGISTRY unavailable: ' + (e as Error).message)
    cache = []
  }
  return cache.length
}

/**
 * One record, or null when we could not call it anyway.
 *
 * Dropped here rather than filtered later: an intent that runs in a service or
 * UI extension cannot be reached by insightIntentDriver.execute as this app
 * calls it, and an address a program cannot use has no business in a prompt.
 */
function flatten(info: insightIntentDriver.InsightIntentInfo): RegistryEntry | null {
  let entry = new RegistryEntry()
  entry.bundle = info.bundleName
  entry.intentName = info.intentName
  let ability = ''
  let modes: string[] = []
  let configured = info.subIntentInfoForConfiguration
  if (configured !== undefined && configured !== null && configured!.uiAbility !== undefined) {
    let ui = configured!.uiAbility!
    ability = ui.abilityName
    for (let mode of ui.executeMode) { modes.push(modeName(mode as number)) }
  }
  if (ability.length === 0) { return null }
  entry.target = info.bundleName + '/' + info.moduleName + '/' + ability + '/' + info.intentName
  entry.modes = modes.join(' ')
  entry.domain = domainOf(info.bundleName)
  let names: string[] = []
  let declared = info.parameters
  if (declared !== undefined && declared !== null) {
    // The parameter names, not their shapes: a prompt can use a name, and the
    // shape is a JSON schema the program has no way to read anyway.
    for (let key of Object.keys(declared as Record<string, Object>)) { names.push(key) }
  }
  entry.params = names
  let words: string[] = []
  if (info.displayName.length > 0) { words.push(info.displayName) }
  for (let keyword of info.keywords) { words.push(keyword) }
  entry.words = words.join(' ')
  return entry
}

function modeName(mode: number): string {
  // 0 foreground, 1 background, in the order the platform declares them.
  return mode === 0 ? 'foreground' : mode === 1 ? 'background' : 'other'
}

/** How many intents were found, for the log and the status line. */
export function registrySize(): number { return cache.length }

/** Everything the phone has and we can call, for the selection step. */
export function registryEntries(): RegistryEntry[] { return cache }

/**
 * The chosen addresses, then whatever lexical matches still fit.
 *
 * Chosen first because a model that was told "this one" should see it at the
 * top; the lexical tail is there because the chooser answers in the dark -- it
 * sees intent names and nothing else -- and a word the person actually typed is
 * a signal worth spending the rest of the budget on.
 *
 * Budget in characters, not lines: an address runs 70 to 110 characters
 * depending on the app, and a line count would quietly mean twice the prompt
 * for one request and half for another.
 */
export function describeTargetsForPrompt(chosen: string[], request: string,
    budgetChars: number = 2000): string {
  if (cache.length === 0) { return '' }
  let lines: string[] = []
  let used = 0
  let taken: string[] = []
  for (let target of chosen) {
    for (let entry of cache) {
      if (entry.target !== target || taken.indexOf(target) >= 0) { continue }
      let line = renderEntry(entry)
      if (used + line.length > budgetChars) { continue }
      lines.push(line); used = used + line.length; taken.push(target)
    }
  }
  // The lexical tail, ranked the way it always was.
  let words = request.toLowerCase().split(' ')
  let scored: RegistryEntry[] = []
  let scores: Map<string, number> = new Map<string, number>()
  for (let entry of cache) {
    if (taken.indexOf(entry.target) >= 0) { continue }
    let haystack = (entry.intentName + ' ' + entry.bundle).toLowerCase()
    let score = 0
    for (let word of words) {
      if (word.length < 4) { continue }
      if (haystack.indexOf(word) >= 0) { score = score + 1 }
    }
    if (score === 0) { continue }
    if (entry.params.length > 0) { score = score + 1 }
    scores.set(entry.target, score)
    scored.push(entry)
  }
  scored.sort((a: RegistryEntry, b: RegistryEntry) => {
    let sa = scores.get(a.target) as number
    let sb = scores.get(b.target) as number
    if (sa !== sb) { return sb - sa }
    return a.target < b.target ? -1 : 1
  })
  for (let entry of scored) {
    let line = renderEntry(entry)
    if (used + line.length > budgetChars) { break }
    lines.push(line); used = used + line.length
  }
  return lines.join('\n')
}

function renderEntry(entry: RegistryEntry): string {
  let line = '  ' + entry.target + '  [' + entry.modes + ']'
  if (entry.params.length > 0) { line = line + '  parameters: ' + entry.params.join(' ') }
  return line + '\n'
}

/** Every domain the registry has anything in, for the questions Jev is asked. */
export function registryDomains(): string[] {
  let seen: string[] = []
  for (let entry of cache) {
    if (seen.indexOf(entry.domain) < 0) { seen.push(entry.domain) }
  }
  return seen
}

/**
 * The intents worth showing for this request, as prompt lines.
 *
 * Two filters, cheapest first. The domains come from the selection step, which
 * asked a model one question per domain. Inside a domain the entries are ranked
 * by how many words of the request they echo -- a poor signal on its own, and a
 * perfectly good tiebreaker once the domain is already right.
 *
 * Capped, because the point of selecting was to keep the prompt affordable: 30
 * lines is about 3 KB against a prompt of 22 KB.
 */
export function describeRegistryForPrompt(domains: string[], request: string, limit: number = 30): string {
  if (cache.length === 0) { return '' }
  let wanted: RegistryEntry[] = []
  for (let entry of cache) {
    if (domains.length === 0 || domains.indexOf(entry.domain) >= 0) { wanted.push(entry) }
  }
  if (wanted.length === 0) { return '' }
  let words = request.toLowerCase().split(' ')
  let scored: RegistryEntry[] = []
  let scores: Map<string, number> = new Map<string, number>()
  for (let entry of wanted) {
    let haystack = (entry.intentName + ' ' + entry.bundle + ' ' + entry.words).toLowerCase()
    let score = 0
    for (let word of words) {
      if (word.length < 4) { continue }
      if (haystack.indexOf(word) >= 0) { score = score + 1 }
    }
    // A declared parameter list is worth more than a bare name: it is the only
    // contract the phone offers, and the 13 intents that have one are exactly
    // the ones a model can call correctly without being told anything else.
    if (entry.params.length > 0) { score = score + 1 }
    scores.set(entry.target, score)
    scored.push(entry)
  }
  scored.sort((a: RegistryEntry, b: RegistryEntry) => {
    let sa = scores.get(a.target) as number
    let sb = scores.get(b.target) as number
    if (sa !== sb) { return sb - sa }
    return a.target < b.target ? -1 : 1
  })
  let lines: string[] = []
  for (let i = 0; i < scored.length && i < limit; i++) {
    let entry = scored[i]
    let line = '  ' + entry.target + '  [' + entry.modes + ']'
    if (entry.params.length > 0) { line = line + '  parameters: ' + entry.params.join(' ') }
    lines.push(line)
  }
  return lines.join('\n')
}
