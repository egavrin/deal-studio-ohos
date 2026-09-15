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
  constructor(name: string, kind: string, platformName: string, values: string[] = [],
      valueMap: Map<string, string> = new Map<string, string>(), summary: string = '') {
    this.name = name; this.kind = kind; this.platformName = platformName
    this.values = values; this.valueMap = valueMap; this.summary = summary
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
  constructor(name: string, paramsClass: string, bundle: string, moduleName: string,
      ability: string, intentName: string, params: IntentParam[], summary: string,
      tier: string, mode: string) {
    this.name = name; this.paramsClass = paramsClass; this.bundle = bundle
    this.moduleName = moduleName; this.ability = ability; this.intentName = intentName
    this.params = params; this.summary = summary; this.tier = tier; this.mode = mode
  }
}

/** The twelve sceneType values the PlayMusicList specification enumerates. */
const MUSIC_SCENES: string[] = ['MORNING_SCENE', 'MIDDAY_SCENE', 'EVENING_SCENE', 'NIGHT_SCENE',
  'WEEKEND_SCENE', 'FESTIVAL_SCENE', 'BIRTHDAY_SCENE', 'ANNIVERSARY_SCENE', 'DRIVE_SCENE',
  'SUBWAY_SCENE', 'TRAVEL_SCENE', 'CITY_SCENE']

/**
 * dstLocationType is prose in the specification -- "家", "公司" -- so the
 * program says home and work and the translation happens here. A Chinese
 * literal in a generated program would be a parameter value invented by the
 * model in all but name.
 */
const DESTINATIONS: Map<string, string> = new Map<string, string>([
  ['home', '家'],
  ['work', '公司'],
])

export const INTENT_CATALOG: IntentSpec[] = [
  // Contract: the standard-intent catalogue (sceneType is a closed set there);
  // the device record declares inputParams empty, so the catalogue is the only
  // source and the tier is 'catalog'.
  // Target: the device's own intent record --
  //   uiAbility { ability: "MainAbility", executeMode: ["foreground","background"] }
  // and the bundle is installed here (`bm dump -n com.huawei.hmsapp.music`).
  // Background, because it supports it: nobody asking for driving music wants
  // the music app to take over the screen.
  new IntentSpec('playMusicList', 'MusicParams',
    'com.huawei.hmsapp.music', 'phone', 'MainAbility', 'PlayMusicList',
    [new IntentParam('scene', 'string', 'sceneType', MUSIC_SCENES,
      new Map<string, string>(), 'which moment of the day the music is for')],
    'puts on a playlist chosen for a moment of the day', 'catalog', 'background'),

  // Contract: the standard-intent catalogue. Parameters are all optional there,
  // so the record carries the two that need no coordinates -- a destination by
  // name and a mode of travel.
  //
  // Target: the device's own intent record --
  //   uiAbility { ability: "EntryAbility", executeMode: ["foreground"] }
  // Foreground is the only mode it declares, and the right one anyway -- a
  // route the driver cannot see is no route. com.amap.hmapp declares the same
  // intent on entry/EntryAbility and is installed too, so a second row pointing
  // there is a one-line change if the Huawei one refuses.
  new IntentSpec('startNavigate', 'NavigateParams',
    'com.huawei.hmos.maps.app', 'entry', 'EntryAbility', 'StartNavigate',
    [new IntentParam('destination', 'string', 'dstLocationType', ['home', 'work'],
      DESTINATIONS, 'where to go'),
     new IntentParam('traffic', 'string', 'trafficType',
      ['Drive', 'Walk', 'Cycle', 'Bus', 'Subway'], new Map<string, string>(),
      'how to travel')],
    'starts navigation to a named place', 'catalog', 'foreground'),

  // The same intent as startNavigate, aimed at a place instead of at "home".
  //
  // startNavigate fails on a device with no Huawei ID, and the reason is the
  // parameter rather than the intent: dstLocationType "家" is a place only a
  // signed-in profile knows. The specification's other destination parameter
  // asks for nothing of the sort -- dstLocation carries the place itself:
  //
  //   { locationSystem, poiId, locationName, longitude, latitude, address }
  //
  // It is an object, which the scalar record cannot hold, so the row spreads it
  // into one field per leaf and lets the dotted platformName reassemble it in
  // VeraIntents. No part of the language or the compiler is involved.
  //
  // Coordinates are strings in the specification's own example, so they are
  // strings here. They come from the person using the program, never from the
  // model: a made-up latitude is a made-up parameter value.
  //
  // Contract: the standard-intent catalogue. Tier was 'catalog' and that was
  // the whole risk, since com.huawei.hmos.maps.app declares inputParams empty
  // exactly as it does for ViewSearchPageLocal, which it answers with 0 while
  // ignoring the query. The probe came out the other way: sent
  // dstLocation.locationName "北京西站" with its latitude and longitude, and
  // Petal Maps drew a real route to those coordinates -- turn-by-turn screen,
  // speedometer, distance and ETA. Tier is therefore 'probed', which outranks
  // the catalogue guess it started from.
  //
  // Worth keeping straight: the map app ignoring `query` was about that one
  // intent, not about the app. Given parameters it understands, it acts on
  // them.
  new IntentSpec('navigateTo', 'NavigateToParams',
    'com.huawei.hmos.maps.app', 'entry', 'EntryAbility', 'StartNavigate',
    [new IntentParam('place', 'string', 'dstLocation.locationName', [],
      new Map<string, string>(), 'name of the place to go to'),
     new IntentParam('latitude', 'string', 'dstLocation.latitude', [],
      new Map<string, string>(), 'latitude, or "" to leave it out'),
     new IntentParam('longitude', 'string', 'dstLocation.longitude', [],
      new Map<string, string>(), 'longitude, or "" to leave it out'),
     // Where the journey starts. Leave all three empty and the map uses wherever
     // the phone is, which is right for one-off navigation and wrong for a
     // planned day: the second leg starts where the first one ended, not where
     // the person happened to be when they opened the app.
     //
     // NOT HONOURED by com.huawei.hmos.maps.app. It accepts the parameter,
     // answers 0, and routes from the phone's current position anyway.
     //
     // Established twice, the second time without the confound. The first try
     // sent srcLocation {"Istanbul Airport", 41.2753, 28.7519} with an Istanbul
     // destination and got a route starting near Moscow -- suggestive, but a
     // route across a continent might have failed for its own reasons. So the
     // second try kept both ends a few kilometres apart and next to the phone:
     //   src {"Red Square", 55.7539, 37.6208} -> dst {"Gorky Park", 55.7298, 37.6019}
     // Petal Maps entered turn-by-turn navigation to Gorky Park from where the
     // phone actually was, not from Red Square. Short, routable, still ignored.
     //
     // dstLocation in the same call is honoured, so this is one parameter
     // ignored rather than the app ignoring parameters.
     //
     // com.amap.hmapp declares the same intent and may well honour it, but it
     // cannot be tested without accepting its first-run privacy agreement,
     // which is the device owner's decision to make.
     //
     // Sent regardless: the program is right to say where the leg begins, and
     // the day it describes stays correct even when the map redraws the first
     // leg from wherever the phone happens to be.
     new IntentParam('fromPlace', 'string', 'srcLocation.locationName', [],
      new Map<string, string>(), 'name of the place to start from, or "" for where the phone is'),
     new IntentParam('fromLatitude', 'string', 'srcLocation.latitude', [],
      new Map<string, string>(), 'latitude of the starting place, or ""'),
     new IntentParam('fromLongitude', 'string', 'srcLocation.longitude', [],
      new Map<string, string>(), 'longitude of the starting place, or ""'),
     new IntentParam('traffic', 'string', 'trafficType',
      ['Drive', 'Walk', 'Cycle', 'Bus', 'Subway'], new Map<string, string>(),
      'how to travel')],
    'starts navigation between two places given by name and coordinates', 'probed', 'foreground'),

  // Opens one section of the music app.
  //
  // The strongest row in this table on the evidence: the device record declares
  // the pageId values itself, with a display name for each, so this is 'schema'
  // tier rather than a name match against the catalogue. That is the same tier
  // as searchInMusic, which worked, and a tier above navigateTo.
  //
  // localSongs is the one that matters here -- music already on the phone, no
  // account and no network. The rest of the declared set is kept because a row
  // costs nothing and the values are the device's own.
  new IntentSpec('openMusicPage', 'MusicPageParams',
    'com.huawei.hmsapp.music', 'phone', 'MainAbility', 'JumpFunctionPage',
    [new IntentParam('page', 'string', 'pageId',
      ['localSongs', 'recentPlay', 'favoriteSongs', 'privateFM', 'heartBeat',
       'daily30', 'hotSongs', 'newSongs', 'ringTone'],
      new Map<string, string>(),
      'which section: localSongs is music already on the phone')],
    'opens a section of the music app', 'schema', 'foreground'),

  // The one target here that needs no account, which is why it exists.
  //
  // StartNavigate and PlayMusicList both fail on a device with no Huawei ID --
  // Maps logs AuthorizationWithHuaweiID 1001502001, Music logs "token is null"
  // -- and neither failure is about the intent framework. It is about the
  // parameters: "home" is a place only a signed-in profile knows, and a
  // playlist picked for a moment of the day is a server-side recommendation.
  //
  // ViewSearchPageLocal asks for none of that. Its one parameter is the text to
  // search for, the specification marks it mandatory, and searching a map is
  // anonymous.
  //
  // Contract: the standard-intent catalogue, which documents `query` as a
  // required string and nothing else.
  // Target: the device's own intent record --
  //   uiAbility { ability: "EntryAbility", executeMode: ["foreground"] }
  // Foreground because the point is to look at the results.
  //
  // WARNING: this target answers 0 and comes to the front, but does not act on
  // the query -- it lands on whatever page it was last on. Verified with three
  // different queries from a cold start. The same intent on com.huawei.hmsapp.music
  // does honour it (see searchInMusic below), so the key is right and this
  // implementation is the problem. Kept as a row because the failure is worth
  // having on record, not because it is useful.
  new IntentSpec('searchOnMap', 'MapSearchParams',
    'com.huawei.hmos.maps.app', 'entry', 'EntryAbility', 'ViewSearchPageLocal',
    [new IntentParam('query', 'string', 'query', [], new Map<string, string>(),
      'what to look for')],
    'opens the map search page for a place', 'catalog', 'foreground'),

  // The same standard intent, implemented by a second app -- which is the point
  // of the row, because it is the only way left to find out whether `query` is
  // the right key at all.
  //
  // Maps answers ViewSearchPageLocal with code 0 and comes to the front, but
  // lands on its trip planner with the search text nowhere in sight. Its record
  // declares inputParams empty, so `query` came from the standard catalogue
  // matched on the intent NAME, and a name match is inference: an app may
  // implement a custom intent that happens to share the name and takes its own
  // keys. The executor would settle it -- srcEntry points at
  // ./ets/insightIntents/IntentExecutorImpl.ets -- but the HAP is not readable
  // without root.
  //
  // Answered: it lands. Searching "Beatles" opens the music app's search page
  // with "Beatles" in the field and real results under it -- Artist: The
  // Beatles, 1701 songs, 57 albums -- and no Huawei ID signed in. So `query` is
  // the right key, the payload travels correctly, and Maps simply does not act
  // on it. Two apps, one standard intent, one honours the contract and one
  // reports success without doing the work.
  //
  // Which is the standing warning about this tier made concrete: a result code
  // is chosen by the target's developer, so a zero is the target talking, not
  // proof that the call did anything.
  new IntentSpec('searchInMusic', 'MusicSearchParams',
    'com.huawei.hmsapp.music', 'phone', 'MainAbility', 'ViewSearchPageLocal',
    [new IntentParam('query', 'string', 'query', [], new Map<string, string>(),
      'what to look for')],
    'opens the music search page for a song or artist', 'catalog', 'foreground'),
]

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

/**
 * The intent section of the model's prompt, generated so it cannot drift from
 * what the compiler accepts and the host sends.
 */
export function describeIntentsForPrompt(): string {
  let lines: string[] = []
  for (let spec of INTENT_CATALOG) {
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
