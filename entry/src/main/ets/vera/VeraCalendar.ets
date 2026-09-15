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
 * The ability context, needed both to ask for the permissions and to get the
 * manager. EntryAbility fills it in; until it does, a calendar call reports
 * that rather than throwing.
 */
export class CalendarContext {
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
  CalendarContext.value = context
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
 * Adds one event and describes the outcome in a line a person can read.
 *
 * `repeat` is 'once' or 'daily'; `remindBefore` is minutes ahead of the start,
 * which is what Calendar Kit's reminderTime means, and 0 asks for a reminder at
 * the moment itself rather than for no reminder at all.
 */
export async function addCalendarEvent(title: string, hour: number, minute: number,
    durationMinutes: number, remindBefore: number, repeat: string): Promise<string> {
  let context = CalendarContext.value
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
