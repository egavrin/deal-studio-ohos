# The demo prompts

Typed into the Generate screen as they stand. Each is a plain description of an
app, with no mention of intents, modules or APIs — what the program reaches for
is the model's decision, made from the catalogue the prompt carries.

## 1. Layover planner, Istanbul

```
Istanbul layover: I land at Istanbul Airport at 08:00 with 12 hours before my
next flight. Plan the day hour by hour around the sights worth seeing, each stop
with its name, how long to spend there and its coordinates, a button that starts
navigation to it from the last stop I reached, a button that puts the stop in my
phone's calendar with a reminder, and the latest time I must leave for the
airport. Keep a note of which stops I actually reached, and give me a button that
wipes every calendar event this app added and one that opens the phone's
calendar.
```

Exercises `std/intent` → `navigateTo`, the row that carries an object parameter
through a flat record.

**Why the city is in the prompt rather than in a text field.** A VERA-L program
has no network: `ui.Image` can name an https URL and nothing else can reach out.
So the itinerary — which sights, in what order, at what coordinates — has to be
in the program, and it gets there when the model writes it. Changing the city
means generating again, which is the tool working as intended: the prompt is the
input.

**What to check, and it is not the result code.** `ExecuteResult.code` is chosen
by the target's developer; Petal Maps answers 0 to `ViewSearchPageLocal` while
ignoring the query. So: tap a stop's navigation button and look at the screen.
A route to the right place, or it did not work. Then check the coordinates
landed in Istanbul rather than somewhere the model imagined — a wrong latitude
is a plausible failure here, and the only one that a green route on screen will
not reveal.

## 2. Pill tracker

```
Pill tracker: let me add a medicine with a name, the hour and minute to take it
and whether it repeats every day; each one goes into the phone's calendar with a
reminder, and the list below shows what is scheduled and what the calendar
answered.
```

Exercises `std/calendar`, which is Calendar Kit rather than an intent — the
device's `CreateCalendarEvent` and its relatives declare no parameters and are
not standard intent names, so their contract would have to be invented.

**What to check.** Open the phone's Calendar app afterwards. The event is either
there at the right time, repeating or not as asked, or it is not. The program's
own log only repeats what the host told it.

**The permission is a real branch.** `WRITE_CALENDAR` is user_grant: the dialog
appears once at startup and can be refused, and every call then answers with an
error. That is a legitimate outcome and the program is told to show it, so a
screen full of errors after a refusal is the app working, not failing.

## 3. Layover planner, Shanghai

The same app as the first prompt in a different city, kept because one city is
not evidence. The itinerary is written by the model, so a plan that comes out
right for Istanbul says nothing about whether the coordinates were recalled or
invented — a second city that also lands on the map is the check.

```
Shanghai layover: I land at Pudong International Airport at 09:00 with 11 hours
before my next flight. Plan the day hour by hour around the sights worth seeing,
each stop with its name, how long to spend there and its coordinates, a button
that starts navigation to it from the last stop I reached, a button that puts the
stop in my phone's calendar with a reminder, and the latest time I must leave for
the airport. Keep a note of which stops I actually reached, and give me a button
that wipes every calendar event this app added and one that opens the phone's
calendar.
```

Exercises everything the device can reach at once: `navigateTo` for each leg,
`calendar.addEvent` for each stop, `calendar.clearEvents` for the run before
this one, and `openCalendar`, which launches the app rather than sending it an
intent.

What the model actually wrote for it is kept verbatim in
[`examples/shanghai-layover.vera`](examples/shanghai-layover.vera) — useful for
seeing which components it reaches for without being told, and worth re-recording
whenever the catalogue or the prompt changes.

**What to check.** The stops should sit within Shanghai — roughly 31.2° north,
121.4–121.5° east; Pudong airport itself is out at 121.81. A tap on a stop's
navigation button draws a route on Petal Maps or it does not; the result code
will not tell you, because the target's developer chooses it. Then open the
calendar and count: one event per stop that was added, at the hour the plan
names.

**The first leg starts from the phone, not the airport.** Petal Maps accepts
`srcLocation`, answers 0 and routes from wherever the phone actually is; this
was pinned down twice, the second time without a confound. The program is still
right to say where each leg begins, and every leg after the first is correct as
soon as you are standing at the stop it starts from.

## What none of the prompts say

None of them mentions `intent`, `calendar`, a bundle name or a parameter. The model
is given the catalogue in its prompt and picks from it. That is the whole point
of the arrangement: a generated program cannot name a platform parameter,
because it never sees one.
