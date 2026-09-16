/**
 * The std/calendar vocabulary, kept as data for the same reason std/intent is:
 * the compiler's signatures, the host's call and the prompt's prose all read
 * one table and cannot drift apart.
 *
 * IntentParam is reused as the field description. It is not intent-specific --
 * name, kind, accepted values, the platform's own spelling and a value map is
 * exactly what a host-backed field needs, whoever the host is talking to.
 */

import { IntentParam } from './VeraIntentCatalog'

export class CalendarFn {
  /** Name in the language: calendar.<name> */
  name: string
  /** Name of the generated parameter class: calendar.<paramsClass> */
  paramsClass: string
  params: IntentParam[]
  summary: string
  constructor(name: string, paramsClass: string, params: IntentParam[], summary: string) {
    this.name = name; this.paramsClass = paramsClass; this.params = params; this.summary = summary
  }
}

export const CALENDAR_CATALOG: CalendarFn[] = [
  new CalendarFn('addEvent', 'EventParams', [
    new IntentParam('title', 'string', 'title', [], new Map<string, string>(),
      'what the event is called'),
    new IntentParam('hour', 'int', 'hour', [], new Map<string, string>(),
      'hour of the day, 0 to 23'),
    new IntentParam('minute', 'int', 'minute', [], new Map<string, string>(),
      'minute of the hour, 0 to 59'),
    new IntentParam('durationMinutes', 'int', 'durationMinutes', [], new Map<string, string>(),
      'how long the event lasts, in minutes'),
    new IntentParam('remindBefore', 'int', 'remindBefore', [], new Map<string, string>(),
      'minutes before the start to remind; 0 reminds at the moment itself'),
    new IntentParam('repeat', 'string', 'repeat', ['once', 'daily'], new Map<string, string>(),
      'once, or every day at the same time'),
  ], 'puts one event in the phone’s calendar'),

  // Removes only what this app wrote: Calendar Kit gives each app its own
  // calendar account, and getCalendar() returns that one rather than the
  // person's own. Without it a demo run leaves yesterday's events behind and
  // the next run is impossible to read.
  new CalendarFn('clearEvents', 'ClearParams', [],
    'removes every event this app added, and nothing else'),
]

/** The function behind calendar.<name>, or null when there is none. */
export function calendarFnByName(name: string): CalendarFn | null {
  for (let fn of CALENDAR_CATALOG) { if (fn.name === name) { return fn } }
  return null
}

/**
 * The calendar section of the model's prompt, generated so it cannot drift from
 * what the compiler accepts and the host sends.
 */
export function describeCalendarForPrompt(): string {
  let lines: string[] = []
  for (let fn of CALENDAR_CATALOG) {
    let fields: string[] = []
    for (let p of fn.params) { fields.push(p.name) }
    lines.push('  calendar.' + fn.name + '({ ' + fields.join(', ') + ' }, result)  -- ' + fn.summary)
    for (let p of fn.params) {
      let allowed = p.values.length > 0 ? p.values.join(' ') : 'any ' + p.kind
      lines.push('      ' + p.name + ': ' + allowed + '  -- ' + p.summary)
    }
  }
  return lines.join('\n')
}
