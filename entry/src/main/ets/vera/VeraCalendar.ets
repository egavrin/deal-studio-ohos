/**
 * The calendar half of what a generated program can reach.
 *
 * Deliberately not an intent. The device does carry CreateCalendarEvent,
 * ModifyCalendarEvent and the rest on com.huawei.hmos.calendardata, but every
 * one of them declares `inputParams: []` and none is a standard intent name, so
 * their parameter contract is unknown and would have to be invented. Calendar
 * Kit is the documented alternative, and a documented contract with no system
 * signing beats a system-only intent with a guessed payload.
 *
 * Like an intent call this is an effect: the VM is synchronous and addEvent is
 * a promise, so the program queues a request and the answer arrives later
 * through its own handler.
 */

import calendarManager from '@ohos.calendarManager'
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl'
import common from '@ohos.app.ability.common'
import hilog from '@ohos.hilog'
import { BusinessError } from '@ohos.base'

const DOMAIN = 0x0000

/**
 * The ability context. Needed to ask for the permissions and to get the manager
 * here, and to launch another app from VeraIntents. EntryAbility fills it in; until it does, a calendar call reports
 * that rather than throwing.
 */
export class AbilityContext {
  static value: common.UIAbilityContext | null = null
}

let manager: calendarManager.CalendarManager | null = null

/**
 * READ_CALENDAR and WRITE_CALENDAR are user_grant, so declaring them in
 * module.json5 is not enough -- they have to be asked for at runtime, and the
 * person can say no. Asked once at startup rather than at the first call,
 * because a dialog appearing in the middle of a generated program's handler
 * would arrive with no explanation of what asked for it.
 */
export async function requestCalendarPermissions(context: common.UIAbilityContext): Promise<void> {
  AbilityContext.value = context
  let permissions: Permissions[] = ['ohos.permission.READ_CALENDAR', 'ohos.permission.WRITE_CALENDAR']
  try {
    await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, permissions)
    manager = calendarManager.getCalendarManager(context)
    hilog.info(DOMAIN, 'VERA', 'VERA-CALENDAR permissions requested, manager ready')
  } catch (e) {
    let err = e as BusinessError
    hilog.error(DOMAIN, 'VERA', 'VERA-CALENDAR permission request failed ' + err.code.toString())
  }
}

/**
 * The next occurrence of hour:minute, today if it is still ahead and tomorrow
 * otherwise.
 *
 * The program cannot compute this itself: a 13-digit epoch millisecond is
 * ~1.7e12 and the VM traps on anything outside int32. So the program says when
 * in the day, and the arithmetic that needs the big numbers happens here.
 */
function nextOccurrence(hour: number, minute: number): number {
  let now = new Date()
  let at = new Date(now.getFullYear(), now.getMonth(), now.getDate(), hour, minute, 0, 0)
  if (at.getTime() <= now.getTime()) {
    at = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, hour, minute, 0, 0)
  }
  return at.getTime()
}

/**
 * Removes every event this app put in the calendar, and nothing else.
 *
 * Calendar Kit gives each app its own calendar account and getCalendar()
 * returns that one, so getEvents() sees only what this app wrote -- the
 * person's own entries are in other accounts and are never touched.
 *
 * A demo that cannot be reset is a demo that gets less legible every run, so
 * this exists mainly to put the phone back to a known state.
 */
export async function clearCalendarEvents(): Promise<string> {
  let context = AbilityContext.value
  if (context === null) { return 'error: no ability context yet' }
  if (manager === null) { manager = calendarManager.getCalendarManager(context) }
  try {
    let calendar = await manager!.getCalendar()
    let events: calendarManager.Event[] = await calendar.getEvents()
    if (events.length === 0) { return 'ok, nothing to remove' }
    let ids: number[] = []
    for (let e of events) {
      let id = e.id
      if (id !== undefined) { ids.push(id as number) }
    }
    await calendar.deleteEvents(ids)
    hilog.info(DOMAIN, 'VERA', 'VERA-CALENDAR cleared ' + ids.length.toString() + ' events')
    return 'ok, removed ' + ids.length.toString()
  } catch (e) {
    let err = e as BusinessError
    hilog.error(DOMAIN, 'VERA', 'VERA-CALENDAR clear failed ' + err.code.toString())
    return 'error ' + err.code.toString() + ': ' + err.message
  }
}

/**
 * Adds one event and describes the outcome in a line a person can read.
 *
 * `repeat` is 'once' or 'daily'; `remindBefore` is minutes ahead of the start,
 * which is what Calendar Kit's reminderTime means, and 0 asks for a reminder at
 * the moment itself rather than for no reminder at all.
 */
export async function addCalendarEvent(title: string, hour: number, minute: number,
    durationMinutes: number, remindBefore: number, repeat: string): Promise<string> {
  let context = AbilityContext.value
  if (context === null) {
    return 'error: no ability context yet'
  }
  if (manager === null) {
    manager = calendarManager.getCalendarManager(context)
  }
  let start = nextOccurrence(hour, minute)
  let event: calendarManager.Event = {
    type: calendarManager.EventType.NORMAL,
    title: title,
    startTime: start,
    endTime: start + durationMinutes * 60 * 1000,
    reminderTime: [remindBefore]
  }
  if (repeat === 'daily') {
    event.recurrenceRule = {
      recurrenceFrequency: calendarManager.RecurrenceFrequency.DAILY
    }
  }
  hilog.info(DOMAIN, 'VERA', 'VERA-CALENDAR add "' + title + '" at ' +
    new Date(start).toString() + ' repeat=' + repeat + ' remind=' + remindBefore.toString())
  try {
    let calendar = await manager!.getCalendar()
    let id: number = await calendar.addEvent(event)
    hilog.info(DOMAIN, 'VERA', 'VERA-CALENDAR added id=' + id.toString())
    return 'ok, event ' + id.toString()
  } catch (e) {
    let err = e as BusinessError
    hilog.error(DOMAIN, 'VERA', 'VERA-CALENDAR failed ' + err.code.toString() + ': ' + err.message)
    // 201 here means the person declined the permission dialog, which is a
    // decision rather than a fault, so it is reported as it is.
    return 'error ' + err.code.toString() + ': ' + err.message
  }
}
