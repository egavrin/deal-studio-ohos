/**
 * The one description of the std/intent vocabulary.
 *
 * Same arrangement as VeraUiCatalog and for the same reason: the compiler's
 * module interface, the host's call to the platform, and the prose in
 * vera-skill.txt all read this table, so adding an intent is one row rather
 * than four edits that nothing cross-checks.
 *
 * It also settles a question the intent framework makes unavoidable. On a real
 * device roughly 95% of installed intents declare no parameter contract
 * anywhere machine-readable, so an agent that fills the gap from imagination
 * writes plausible code that fails at runtime. Here the contract lives in this
 * table, taken from the standard-intent catalogue, and the generated program
 * only picks values. It cannot name a parameter, because it never sees one:
 * `platformName` and `valueMap` keep the platform's own spelling -- and its
 * Chinese literals -- on this side of the bridge.
 *
 * Pure data. Carries kinds as strings rather than compiler types, so it does
 * not import the compiler and there is no cycle.
 */

export class IntentParam {
  /** Field name in the record the program writes. */
  name: string
  /** 'string' | 'int' */
  kind: string
  /** Closed set of accepted values; empty when unconstrained. */
  values: string[]
  /** Key this field becomes in insightIntentParam. */
  platformName: string
  /** Value translation on the way out; empty map means identity. */
  valueMap: Map<string, string>
  /** One line for the prompt. */
  summary: string
  /**
   * Sent when the program leaves this field empty.
   *
   * An empty string means "omit", which is how a language with no optional
   * record fields spells an optional parameter -- but some parameters are
   * optional to the program and mandatory to the target. GetSettingSeekBar
   * wants an itemName whether or not the person named a kind of volume, so the
   * row carries the sensible one and the program may honestly write "".
   *
   * Empty here keeps the old behaviour: an empty field is not sent.
   */
  defaultValue: string
  constructor(name: string, kind: string, platformName: string, values: string[] = [],
      valueMap: Map<string, string> = new Map<string, string>(), summary: string = '',
      defaultValue: string = '') {
    this.name = name; this.kind = kind; this.platformName = platformName
    this.values = values; this.valueMap = valueMap; this.summary = summary
    this.defaultValue = defaultValue
  }
}

export class IntentSpec {
  /** Name in the language: intent.<name> */
  name: string
  /** Name of the generated parameter class: intent.<paramsClass> */
  paramsClass: string
  /** Where the intent lives, read from the device -- never guessed. */
  bundle: string
  moduleName: string
  ability: string
  /** The platform's own intent name. */
  intentName: string
  params: IntentParam[]
  summary: string
  /**
   * How the contract was established, in the vocabulary of the caller
   * workflow: 'catalog' -- the standard-intent specification; 'probed' -- the
   * target answered; 'schema' -- the device record declared it.
   */
  tier: string
  /**
   * 'foreground' or 'background'.
   *
   * Not a preference -- the target declares which modes it supports and asking
   * for one it does not is an error. Within what it supports, the choice is
   * about whether the person should be looking at that app: navigation is
   * useless off-screen, music is worse on it, because coming to the front tears
   * the calling app away for something the user only wanted to hear.
   *
   * Background dispatch goes through the Call mechanism rather than starting a
   * page, and needs ohos.permission.ABILITY_BACKGROUND_COMMUNICATION.
   */
  mode: string
  /**
   * How the target is reached: 'intent' through insightIntentDriver, or
   * 'launch' by simply starting its ability.
   *
   * Launching is the honest answer when a target has nothing to be told. The
   * calendar app's ViewCalendarEvent declares no parameters and refuses an
   * empty payload with its own code 10020012, so there is a contract there that
   * cannot be guessed -- while "open the calendar" needs no contract at all.
   * startAbility is public API and needs no system signature.
   */
  via: string
  /**
   * Platform parameters this row always sends, which the program never writes
   * and the model never sees.
   *
   * The device has no "turn Bluetooth on" intent. It has one SetSettingSwitch
   * in the settings app, and itemName says which switch: bluetooth,
   * personal_hotspot, battery_saving_mode. Holding itemName here is what turns
   * one generic intent into several named functions a model can choose between
   * without inventing a platform string -- and inventing one is exactly the
   * failure this catalogue exists to prevent, because the platform does not
   * validate parameters and an unknown itemName fails silently.
   *
   * Keyed by platform name, like platformName on a parameter, so a dotted key
   * nests the same way.
   */
  fixed: Map<string, string>
  /**
   * What calling this row does to the phone: 'read', 'navigate', 'act' or
   * 'critical'.
   *
   * Recorded when the row is added, while the contract and the probe are in
   * front of whoever adds it. Nothing enforces it yet -- the confirmation
   * dialog is the next step -- so for now safety comes from which rows are
   * admitted at all. A row is never given a milder class than its verb and its
   * target suggest.
   */
  risk: string
  /** One word, used to pick the rows a request needs: maps, calendar, clock... */
  domain: string
  /** The line a person reads in the confirmation dialog: "Turn Bluetooth on". */
  titleForUser: string
  /** The target's versionCode when the row was last probed; '' when unknown. */
  verifiedVersion: string
  /**
   * The one field of the target's answer the program is given, by platform name.
   *
   * A reading intent is pointless unless its answer comes back, and the answer
   * arrives as an object: GetSettingSeekBar replies
   * {"itemName":"media_volume","seekBarValue":32,"targetValue":32}. The language
   * cannot take an object apart -- there is no JSON in it and no way to add one
   * -- so the row names the field that matters and the host hands over that
   * value alone, as a string. Empty means the handler gets 'ok', as before.
   */
  resultField: string
  /**
   * Platform answer -> the word the program uses, the reverse of valueMap.
   *
   * Without it a reading row would leak the platform's own spelling back into
   * the program: bluetooth answers switchFlag 0 for ON, and a generated program
   * comparing against "0" would be writing platform values in all but name.
   */
  resultMap: Map<string, string>
  constructor(name: string, paramsClass: string, bundle: string, moduleName: string,
      ability: string, intentName: string, params: IntentParam[], summary: string,
      tier: string, mode: string, via: string = 'intent',
      fixed: Map<string, string> = new Map<string, string>(), risk: string = '',
      domain: string = '', titleForUser: string = '', verifiedVersion: string = '',
      resultField: string = '', resultMap: Map<string, string> = new Map<string, string>()) {
    this.name = name; this.paramsClass = paramsClass; this.bundle = bundle
    this.moduleName = moduleName; this.ability = ability; this.intentName = intentName
    this.params = params; this.summary = summary; this.tier = tier; this.mode = mode
    this.via = via; this.fixed = fixed; this.risk = risk; this.domain = domain
    this.titleForUser = titleForUser; this.verifiedVersion = verifiedVersion
    this.resultField = resultField; this.resultMap = resultMap
  }
}

/** Empty on purpose: intents come from the phone's own registry (VeraIntentRegistry).
 * Rows added at run time by VeraCatalogFile are the only way one gets in. */
export const INTENT_CATALOG: IntentSpec[] = []

/** The spec behind intent.<name>, or null when there is none. */
export function intentByName(name: string): IntentSpec | null {
  for (let spec of INTENT_CATALOG) { if (spec.name === name) { return spec } }
  return null
}

/** Accepted values for one field of one intent's record; empty if unconstrained. */
export function intentValuesFor(intentFunction: string, field: string): string[] {
  let spec = intentByName(intentFunction)
  if (spec === null) { return [] }
  for (let p of spec!.params) { if (p.name === field) { return p.values } }
  return []
}

/** Every domain the catalogue uses, in the order the rows were written. */
export function intentDomains(): string[] {
  let seen: string[] = []
  for (let spec of INTENT_CATALOG) {
    if (spec.domain.length === 0) { continue }
    if (seen.indexOf(spec.domain) < 0) { seen.push(spec.domain) }
  }
  return seen
}

/**
 * The intent section of the model's prompt, generated so it cannot drift from
 * what the compiler accepts and the host sends.
 *
 * With a list of domains, only those rows are described. That is how the
 * catalogue stays affordable as it grows: a request about a day out has no use
 * for sixty rows about phone settings, and every row costs about 185 characters
 * of a prompt that is 20 KB before any of them.
 *
 * An empty list means all of them, which is also what the caller falls back to
 * whenever the selection step cannot answer. Erring wide is deliberate: an
 * extra row wastes prompt, a missing one silently removes a feature from the
 * generated app, and the person cannot see which happened.
 *
 * A row with no domain is always described: it has not been sorted yet, and
 * dropping it would hide it for no reason anyone could act on.
 */
export function describeIntentsForPrompt(domains: string[] = []): string {
  let lines: string[] = []
  for (let spec of INTENT_CATALOG) {
    if (domains.length > 0 && spec.domain.length > 0 && domains.indexOf(spec.domain) < 0) {
      continue
    }
    let fields: string[] = []
    for (let p of spec.params) { fields.push(p.name) }
    lines.push('  intent.' + spec.name + '({ ' + fields.join(', ') + ' }, result)  -- ' + spec.summary)
    for (let p of spec.params) {
      let allowed = p.values.length > 0 ? p.values.join(' ') : 'any ' + p.kind
      lines.push('      ' + p.name + ': ' + allowed)
    }
  }
  return lines.join('\n')
}
