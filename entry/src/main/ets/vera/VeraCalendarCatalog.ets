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

/** What the program may ask for when adding an event. */
export const CALENDAR_EVENT_PARAMS: IntentParam[] = [
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
]

/** Accepted values for one field, so the compiler can reject an invented one. */
export function calendarValuesFor(field: string): string[] {
  for (let p of CALENDAR_EVENT_PARAMS) { if (p.name === field) { return p.values } }
  return []
}

/**
 * The calendar section of the model's prompt, generated so it cannot drift from
 * what the compiler accepts and the host sends.
 */
export function describeCalendarForPrompt(): string {
  let fields: string[] = []
  for (let p of CALENDAR_EVENT_PARAMS) { fields.push(p.name) }
  let lines: string[] = []
  lines.push('  calendar.addEvent({ ' + fields.join(', ') + ' }, result)  -- ' +
    'puts one event in the phone’s calendar')
  for (let p of CALENDAR_EVENT_PARAMS) {
    let allowed = p.values.length > 0 ? p.values.join(' ') : 'any ' + p.kind
    lines.push('      ' + p.name + ': ' + allowed + '  -- ' + p.summary)
  }
  return lines.join('\n')
}
