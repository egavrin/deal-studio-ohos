# Intents: how VERA uses them, what can go wrong, how the model learns them

A generated program reaches other apps through `std/intent`. This note says how
that mechanism works on the device, what the device actually offers, why it is
not safe on its own, and how the model is told which intents exist and what
they take. It is a design, not a description of what is built: section 8 lists
what the current code already does and what is still to do.

Decided so far:

- **Any intent may be offered**, but **every call that changes something asks
  the person first**, in a dialog the program cannot draw, alter or answer.
- **The model never sees an intent without a contract.** An intent with no
  known parameters is either launched without parameters or left out.

## 1. What an intent is and how it is called

An *insight intent* is a named entry point an app declares so that the system,
or a privileged caller, can make it do one thing: `PlayMusicList`,
`StartNavigate`, `CreateAlarm`. It is addressed by four strings:

```
bundleName / moduleName / abilityName / intentName
```

and called with `insightIntentDriver.execute(ExecuteParam)`
(`@ohos.app.ability.insightIntentDriver`, `execute` at line 432 of the SDK
declaration), which takes a free-form `insightIntentParam` record and an
`executeMode`:

| mode | what happens | needs |
|---|---|---|
| `UI_ABILITY_FOREGROUND` | the target comes to the front | — |
| `UI_ABILITY_BACKGROUND` | the target runs through the Call mechanism, off screen | `ABILITY_BACKGROUND_COMMUNICATION` |
| `UI_EXTENSION_ABILITY`, `SERVICE_EXTENSION_ABILITY` | the target runs in an extension | not used by VERA yet |

The system checks the mode against the modes the target declares, and refuses
the call if the target does not declare it
(`insight_intent_execute_manager.cpp:240`).

**Who may call.** `execute` is a system API. The one check is
`InsightIntentExecuteManager::CheckCallerPermission`
(`foundation/ability/ability_runtime/services/abilitymgr/src/insight_intent/insight_intent_execute_manager.cpp:704`):

1. a shell caller — let through with no check at all;
2. a system app calling its own intent — let through;
3. otherwise: the caller must be a system app (`202` if not) **and** hold
   `ohos.permission.EXECUTE_INSIGHT_INTENT` (`201` if not).

For VERA that means a `hos_system_app` profile with the permission in
`acls.allowed-acls`. `sign-system.sh` produces that, and `module.json5` lists
the four permissions and explains each. An app signed the ordinary way cannot
call `execute` at all. An app store will not grant this to a third-party app,
so this is a product decision as much as a technical one (section 9).

**The cheaper path.** When the request is only "show me that app", VERA does not
need an intent at all: `context.startAbility({bundleName, abilityName})` is
public API. A catalogue row with `via: 'launch'` does exactly this
(`VeraIntents.ets`, `launchTarget`).

**What a result means.** `ExecuteResult.code` is chosen by the target's
developer. A non-zero code is the target saying no (`PlayMusicList` answers
`100060202` for a delisted playlist). **A zero proves nothing.** On this
device, Maps answers `ViewSearchPageLocal` with 0 and ignores the query, and
answers `StartNavigate` with 0 while ignoring `srcLocation`. Only probing on a
real device says whether a parameter is honoured.

## 2. What the device has

The system keeps every installed intent in `insight_intent.db`, which has one
table:

```sql
CREATE TABLE insight_intent_table (INTENT_KEY TEXT PRIMARY KEY, INTENT_VALUE TEXT);
-- key: userId/bundleName/moduleName/intentName/versionCode
--      100/com.huawei.hmsapp.music/phone/JumpFunctionPage/10022350
```

A copy pulled from the test phone is at `~/Desktop/hdc/insight_intent.db`. What
is in it:

| | count |
|---|---|
| rows | 810 |
| apps | 83 |
| declared in `insight_intent.json` (`insightIntents`) | 747 |
| declared with decorators (`extractInsightIntents`) | 63 (`@InsightIntentEntry` 47, `@InsightIntentLink` 16) |
| **profile intents with any `inputParams`** | **13 of 747** |
| profile intents with `displayName` / `keywords` | 7 |
| decorator intents with a `parameters` schema | 24 of 63 |
| decorator intents with `llmDescription` | 62 of 63 |
| execute modes (profile) | background only 485, foreground only 144, both 11, no UIAbility 107 (service extension 78, UI extension 24, form 6) |

Leading verbs across the profile intents: Get 168, Set 108, Check 72, View 47,
Open 38, Jump 31, Load 23, Delete 20, Turn 17, Query 13, Modify 12. The most
common names are the generic settings family (`CheckSettingItem`,
`GetSettingSwitch`, `SetSettingSwitch`, `LoadSettingCard` — about 20 apps each).
Those declare no parameters anywhere.

**Metadata comes in three formats.** Any tool that reads the database has to
normalise all three into one:

```jsonc
// A. profile, JSON-schema style (JumpFunctionPage, ViewSearchPageLocal)
"inputParams": [{ "properties": { "pageId": { "type": "string",
    "enum": [{ "value": "localSongs", "displayName": "本地音乐", "keywords": [...] }] } } }]

// B. profile, list style (com.huawei.hmos.instantshare)
"inputParams": [{ "name": "deviceIdList", "type": "array", "description": "目标设备ID列表（必需）" }]

// C. decorator (com.huawei.hmos.dlpcredmgr EnableAntiPeepMainSwitch)
"parameters": { "type": "object", "required": ["mainSwitchEnabled", "isControlScreen"],
                "properties": { "mainSwitchEnabled": { "type": "string", "description": "..." } } },
"llmDescription": "用于打开或关闭防窥保护功能。…仅当有明确的打开或关闭指令时才调用…"
```

Format C was written with an LLM in mind, but in Chinese. Its `llmDescription`
often carries usage conditions ("only call this when…"), and those belong in
the catalogue's own description.

**The same data is available at runtime.** `getAllInsightIntentInfo`,
`getInsightIntentInfoByBundleName`, `getInsightIntentInfoByIntentName` and
`getInsightIntentInfoByFilter` (SDK line 1380 onward) return it, and
`queryEntityInfo` returns entities. They need `GET_BUNDLE_INFO_PRIVILEGED` and a
system app (`CheckGetInsightIntenInfoPermission`, same file, line 750). The OS
also carries `function_call_convert.cpp`, which turns an intent into a
function-call description (its schema plus an `ohos.insightIntent.options`
block). So the platform itself treats "an intent is a tool for a model" as the
intended use.

Reading the pulled database:

```bash
DB=~/Desktop/hdc/insight_intent.db
# profile intents that declare parameters
sqlite3 $DB "select t.INTENT_KEY from insight_intent_table t,
  json_each(t.INTENT_VALUE,'$.insightIntents') i
  where json_array_length(i.value,'$.inputParams') > 0"
# everything one app declares
sqlite3 $DB "select INTENT_VALUE from insight_intent_table
  where INTENT_KEY like '100/com.huawei.hmsapp.music/%'" |
  python3 -c 'import sys,json; [print(json.dumps(json.loads(l),ensure_ascii=False,indent=1)) for l in sys.stdin]'
```

## 3. Are they safe? No — and the OS does not help

**One permission opens everything.** `EXECUTE_INSIGHT_INTENT` is not scoped.
Once VERA holds it, a generated program can reach every intent of every app on
the phone. The OS has no per-intent permission, no risk marking and no
confirmation step.

**The OS does not validate parameters.** Nothing in the execute path compares
the payload with `inputParams` or `parameters`: `insight_intent_utils.cpp:218`
only copies them into query results. Whatever VERA sends reaches the target's
executor unchanged, so how a malformed or hostile payload is handled depends
entirely on that app.

**What is on this phone.** A first pass by verb and by app (section 4) puts
about **140 intents** in the critical class. Grouped, with examples:

| group | examples |
|---|---|
| money | `Pay`, `CashierPicker` (vassistant), `SendRedPacket` (hms.payment), `RechargeSubwayCard`, `AddSubwayCard` (wallet) |
| talking to people | `SendTextMessage`, `SendPhotoMessage`, `SendLocationMessage`, `CallMeeTime` (meetimeservice), `SendMessage`, `MakeAiCall` (vassistant), `HuaweiShareSend`, `SendCurrentContent` (instantshare) |
| deleting data | `DeleteContact`, `DeleteNote`, `DeleteCalendarEvent`, `DeleteAlarm`, `ClearCallBlockRecords`, `DeleteAllCallRecordNumbers` |
| permissions and security | `SetAppAccessPermissions`, `SetCameraSettingSwicth`, `SetHookInputEventSwitch` (privacycenter), `RemoveFromBlockList` (spamshield), `EnableAntiPeepMainSwitch` (dlpcredmgr), `JumpAppLockEntryPage` |
| parental control | `SetAppsForbidUse`, `DeleteAllAppLimitTime`, `DeleteAwayTime` (parentcontrol) — 36 intents |
| phone and network | `SetCallForwardingOff`, `SetDataRoamingSwitch`, `SetImsSwitch` (callsetting) |
| the system itself | `EndRunningApp`, `CreateCloneApp`, `DeleteCloneApp` (settings), `LockScreenOrientation` (sceneboard), `AgreeGrantOperations` (huaweicast) |

**Reading is not harmless either.** `GetRecentNotification`,
`GetCallRecordNumbers` and `QueryCallForwarding` return private data. VERA's
`runIntent` currently gives the program only `ok` / `declined` / `error`, never
the target's payload. That should stay so until read results have a reason to
reach the program and a rule for where they may go.

**Threats specific to VERA:**

1. **The model writes the parameters.** A recipient, an amount or a contact
   name typed by the model is a guess presented as fact.
2. **Prompt injection.** A program's data can steer the model: a note's text, a
   search result, a request that quotes a web page. It can also steer the
   program's own logic into asking for an intent the person never meant.
3. **Calls with nobody watching.** Today a timer handler runs through
   `dispatch` exactly like a tap (`VeraPreview.ets:291`), and so does the
   handler that receives an intent's answer (`runEffect`, around line 515).
   Both may queue further intents. So a program can call intents on a timer,
   or chain intents indefinitely, with nobody touching the screen. Only `view`
   is fenced off (`effectsAllowed`, around line 368).
4. **A zero proves nothing** (section 1), so "the program says it worked" does
   not mean it did.
5. **Targets change.** An app update can change what an intent takes or does
   while keeping its name. The database key carries `versionCode`, and the
   catalogue should record which version was probed.

**Conclusion.** Every protection has to live in VERA: in the catalogue, the
compiler and the host. Nothing in the prompt counts as a protection. It only
makes the right program more likely.

## 4. Risk classes

Each catalogue row carries a class. **A person assigns it** when the row is
added. The model never assigns it, and the program never sees it as something
it can change.

| class | what it covers | the call |
|---|---|---|
| `read` | Get / Check / Query / Load / Search with no side effect | runs; only a status reaches the program |
| `navigate` | Open / Jump / Enter / View a page; `via: 'launch'` | runs without asking, **only from a tap** |
| `act` | Play / Create / Add / Save / Start / Set / Turn / Modify / Take | **asks first** |
| `critical` | money; messages and calls; Delete / Clear / Reset / Restore; permissions, security, parental control, telephony, anything in the groups above | **asks every time**, with the exact values shown and "Cancel" as the default; never remembered |

The verb suggests the class, and the app can raise it: `SetSettingSwitch` is
`act` in `batterycare` and `critical` in `advsecmode`. A first automatic pass
over this phone gives read 305, navigate 165, act 199, critical 141. Those
numbers only size the job. A row enters the catalogue after a person has
looked at it.

A row may be **raised** to a stricter class after probing, and **never
lowered** by anything automatic.

## 5. Confirmation and the rest of the host-side rules

All of the following is enforced in the host (`VeraIntents.ets` /
`VeraPreview.ets`). None of it depends on the prompt.

1. **The dialog belongs to VeraPreview.** It is a native ArkUI dialog drawn
   over the program. The program cannot draw it, style it, change its text or
   press its buttons. It shows:
   - the target app's name and icon (from BMS, not from the catalogue or the
     program);
   - `titleForUser` from the row, in plain words ("Send a text message");
   - every value that will be sent, after `valueMap`, labelled with the
     program-side field names;
   - for `critical`: the class stated plainly, and Cancel as the default
     button.
2. **When the dialog is shown.** `navigate` and `read` never show it. `act`
   shows it on every call; an "allow for this program" option may be
   remembered per program and per row, and is cleared whenever the program is
   regenerated. `critical` shows it on every call and never remembers.
3. **Only a tap may start a chain.** The host tags each dispatch with its
   origin: `tap`, `timer`, `answer` or `init`. Intents of class `navigate`,
   `act` and `critical` are accepted only from `tap`, or from `answer` within
   the same chain, up to a fixed number of calls per tap (for example 3).
   A refused call is answered with `error: not allowed here`, so the program
   sees why.
4. **Rate limits.** At most one open dialog at a time. At most N intent calls
   per tap. Every queued call beyond the limit is answered with an error, not
   left silently waiting.
5. **A log.** Every call is logged with the program ID, the row, the values,
   the class, the person's decision and the answer. The `VERA-INTENT` hilog
   line already covers most of this. The log is for the person first (a
   "what did this program do" view) and for debugging second.
6. **The payload is built from the row only.** Keys come from `platformName`
   and values pass through `valueMap` (as `buildParams` does now). Before the
   call, the host checks every value against the row's closed set and kind,
   even though the compiler already did: a saved program may predate a
   catalogue change.

## 6. How the model learns what exists and what it takes

There are three layers, and each one exists because the one before it cannot
be trusted on its own.

```
insight_intent.db ──► inventory (host script) ──► curated catalogue ──► filtered on the device ──► prompt + compiler
   800+ intents        normalised candidates        VeraIntentCatalog     rows present & verified     what the model sees
```

### 6.1 Inventory (offline, on the host)

A script reads the pulled database and writes one candidate per intent with
the following fields:

- the key, domain, execute modes and whether it goes through a UIAbility;
- parameters normalised from formats A, B and C into one shape: name, kind,
  required, closed set with display names, description;
- `llmDescription`, translated for the reviewer;
- a suggested class, from the verb and app rules in section 4;
- **a contract tier**: `schema` if the device declares the parameters,
  `catalog` if the intent name is a standard intent with published
  parameters, `none` otherwise.

The inventory is a worklist for a person. It is never a source the app loads.

### 6.2 The curated catalogue — the only source of truth

`VeraIntentCatalog.ets` stays what it is now: one table that the compiler
(`buildStdIntentModule`, `VeraCompiler.ets:1211`), the argument checker
(`checkIntentArguments`, `VeraCompiler.ets:1851`), the prompt
(`describeIntentsForPrompt`, spliced in at `GeneratePage.ets:253`) and the host
(`runIntent`) all read. A row is added only when:

- its contract tier is `schema`, `probed` or `catalog`, and it has been probed
  on a phone. Tier order, strongest first: `probed` > `schema` > `catalog`.
  `probed` outranks `schema` because a declaration is still only a promise
  (section 1). The comment on `openMusicPage` in the catalogue ranks `schema`
  above `probed`; one of the two should be brought in line with the other.
- or it is `via: 'launch'` and needs no contract.

Fields to add to `IntentSpec`:

| field | why |
|---|---|
| `risk` | `read` / `navigate` / `act` / `critical` (section 4) |
| `titleForUser` | the line in the confirmation dialog |
| `requiresAccount` | Maps and Music fail without a Huawei ID; the model should know, and the program should be able to say so |
| `verifiedVersion` | the target's `versionCode` when it was probed |

Rows keep what they already have: the program-side names, the closed sets, and
`platformName` / `valueMap`, which never leave the host. The model writes
`destination: "home"`, never `dstLocationType: "家"`.

**Intents with contract tier `none` are left out.** 734 of the 747 profile
intents declare nothing. Offering them would mean the model inventing their
parameters, and `ViewCalendarEvent` shows what happens then: it refused an
empty payload with its own code `10020012`.

### 6.3 Filtered on the device

At startup, VERA calls `getInsightIntentInfoByIntentName` for every row.

- The target is missing → the row is left out of both the prompt and the
  compiler's module, so a program that uses it fails to compile with a clear
  message instead of failing at run time.
- The target's `versionCode` differs from `verifiedVersion` → the row stays but
  is marked unverified, and its calls ask for confirmation regardless of class.
  The alternative, hiding it, is an open question (section 9).
- The row's modes are no longer declared → left out.

A saved program that refers to a row which has since disappeared shows a
compile error when it opens, like any other stale program.

### 6.4 What the model sees

For each row that survives, the prompt gets one entry in the same shape as
now, plus a class note:

```
intent.playMusicList({ scene }, result)  -- puts on a playlist chosen for a moment of the day  [asks first]
    scene: MORNING_SCENE MIDDAY_SCENE EVENING_SCENE ...
intent.openCalendar({ }, result)  -- opens the phone's calendar app
```

With it go two rules, stated once:

- values for free-text fields (a place, a query, a recipient) come from what
  the person types into the program, never from the model's own knowledge;
- the result handler receives a status, and a status of `ok` means only that
  the target accepted the call.

The compiler rejects any name, field or value outside the catalogue. That
already works; it is the reason a hallucinated intent fails at generation time
and never reaches the phone.

### 6.5 When the catalogue outgrows the prompt

Once there are a few dozen rows, the whole table stops fitting comfortably in
the prompt. The next step is to select rows before generating: tag each row
with a domain (music, maps, clock, calendar, messages…), pick domains from the
person's request (with a small classification call, or by letting the model
ask for a domain's rows through a tool), and splice in only those. The
compiler still knows every row, so a program never depends on what the prompt
happened to include.

## 7. Adding an intent

1. Find it in the inventory. Note the modes, the contract tier and the
   suggested class.
2. Settle the contract: the device's schema, else the standard-intent
   specification. If neither exists, stop, or add it as `via: 'launch'`.
3. Probe it on the phone, from `~/work/ohos/intent_demo` or from VERA itself
   signed as a system app (a shell caller skips the permission check too, see
   section 1). Call it with every parameter the row will use, changing one at
   a time, and take a screenshot of what the target did. Record what was honoured and what was ignored, and the
   `versionCode`.
4. Assign the class and `titleForUser`, and write the row. Follow the existing
   rows' comment style: where the target is, where the contract came from, and
   what the probe showed.
5. Check it on the host: compile a program that uses the row under node
   (CLAUDE.md, "Checking things without a device"), including one with a value
   outside the closed set, which must be rejected.
6. On the device: generate one program that uses it, and check the dialog, the
   answer and the log line.

## 8. What exists today and what is left

| piece | today |
|---|---|
| one catalogue that the compiler, prompt and host all read | done — `VeraIntentCatalog.ets` |
| typed parameter classes, closed sets, compile-time rejection | done — `buildStdIntentModule`, `checkIntentArguments` |
| platform keys and values kept on the host | done — `platformName`, `valueMap`, `buildParams` |
| `via: 'launch'` | done — `openCalendar` |
| no intents from `view` | done — `effectsAllowed` |
| contract tiers on rows | done — `tier`: `catalog` / `probed` / `schema` |
| `risk`, `titleForUser`, `requiresAccount`, `verifiedVersion` | to do |
| confirmation dialog | to do |
| origin tagging: no intents from timers or unbounded answer chains | to do — **currently open** |
| per-tap limit, a check of values on the host side | to do |
| filtering rows against the device at startup | to do |
| inventory script | to do |
| selecting rows by domain for the prompt | later |

## 9. Open questions

- **Should `critical` be forbidden outright?** The current decision is "ask
  every time". The argument against: for `Pay` or `SendRedPacket` the amount
  and the recipient come from a program the model wrote, and people learn to
  click through dialogs they see often. A middle way is to allow `critical`
  only when every free-text value was typed by the person in this session.
- **Changed targets:** mark them unverified (section 6.3), or hide them until
  someone probes them again?
- **The 107 intents that do not go through a UIAbility** (service extension,
  UI extension, form). `runIntent` supports only the UIAbility modes.
- **`@InsightIntentLink` intents** (16) are URIs, not executors. They might be
  opened with `openLink` instead, without the system permission.
- **Read results.** Should a `read` intent's payload ever reach the program,
  and if so, what may the program do with it?
- **Distribution.** Everything above assumes VERA is a system app. A store
  build cannot be one, so the product needs either a platform partnership or
  a fallback that uses only `via: 'launch'` and public APIs (as `std/calendar`
  already does).
