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

There is no `std/calendar` any more: a program reaches the calendar only through
`sdk.call`, and only for what `find_sdk_function` or `find_intent_function`
returns. Whether the phone's calendar is reachable that way is the thing this
prompt checks.

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

Shanghai layover: I land at Pudong International Airport at 09:00 with 11 hours before my next flight. Plan the day hour by hour around the sights worth seeing, each stop with its name, how long to spend there and its coordinates, a button that starts navigation to it from the last stop I reached, a button that puts the stop in my phone's calendar with a reminder, and the latest time I must leave for the airport. Keep a note of which stops I actually reached, and give me a button that wipes every calendar event this app added and one that opens the phone's calendar.

Exercises everything the device can reach at once: `navigateTo` for each leg,
a calendar write for each stop and for clearing the run before this one (found
through `find_sdk_function`), and `openCalendar`, which launches the app rather than sending it an
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

## 4. Blink melody, flashlight in time

```
A button that plays an 8-second melody in C major at 120 BPM, four notes per bar,
built from sine tones computed sample by sample with math.sin at 8000 samples per
second, sent as comma-separated 16-bit samples to the platform audio renderer
write call with sampleRate 8000. On every beat the flashlight turns on, and it
turns off 80 milliseconds later, in time with the melody. When the melody ends,
the flashlight is off and the app shows how many beats it blinked.
```

Exercises the audio renderer and the torch together. The first version was
generated at 8 seconds and exceeded the interpreter's step budget (5 000 000 steps
for one action), so it was asked for 5 seconds with "What to change?". The first
version also omitted `sampleRate`, so the melody played about six times too fast
until it was asked for explicitly.

**What to check.** The melody lasts about 5 seconds at 120 BPM, which is ten beats.
The flashlight flashes on each beat and goes off 80 ms later. The flashes are driven
by the program's tick, not by the audio clock, so they can drift against the sound;
check by ear and by eye. It is one button press, not a loop.

## 5. Chat with widgets (a separate screen)

Unlike the four above this is not typed into the Generate screen. It is the
**Chat** button on the project list (`pages/ChatPage`): an ordinary assistant
conversation in which a reply can carry a live mini-application, generated while
the person waits and drawn inside the conversation, the way a chat answer can
embed an interactive component instead of describing one.

Messages to type, in one conversation:

```
We are four people and the bill is 187.40, we want to leave 12% tip. Who pays what?
```
```
What is a good way to learn 20 Spanish words a week?
```
```
I need to boil an egg, soft, the way I like it.
```
```
My room is pitch dark and I cannot find my keys. Give me a button to turn the flashlight on and one to turn it off.
```

**How it works.** Each turn is a streamed chat completion (`vera/VeraChat.ets`
`chatReply`: the words appear as they arrive) whose system prompt lets the assistant end a reply with
`<<app: ...>>`, a one-line English description of a widget, anywhere in the
reply: before the text, between two parts of it, or after it. The text streams in
and the widget starts building the moment its line is closed, while the rest of
the reply is still arriving. The description then goes through the same pipeline as the Generate screen
(skill prompt plus `rawfile/vera-widget.txt`, a widget-mode section that asks
for one purpose, no title block, results first and no scrolling, and shows money
through a `money()` helper rather than as raw cents; `find_sdk_function` /
`find_intent_function`, compiler with up to three attempts) and the resulting program is rendered by `VeraPreview` in a
fixed-height (420 vp) card under the message. Widget builds are queued, one at a time.

**What to check, and what a phone run showed.**
- The first message gives a text answer and a split-the-bill widget with 187.40,
  four people and 12% already in it (total 209.88, 52.47 each, matching the
  text). Tapping "+" on people moved 4 to 5 and the figures redrew. One build
  failed to compile on the first attempt and passed on the second, so expect
  about a minute.
- The second is expected to get text, and a widget is acceptable: the model
  usually adds a weekly tracker (Learned 0/20, four sets to tick off). The system
  prompt says "never for something a sentence answers" and it does not reliably
  hold; it was left as it is, as good enough for a demo.
- The third gets a soft-boiled egg timer with presets and a countdown that really
  ticks (337 s, then 321 s sixteen seconds later).
- The fourth uses a system intent. The assistant answers briefly and offers a
  widget with Turn On / Turn Off buttons and a "Last platform answer" panel; the
  buttons reach the phone's torch through `sdk.call` (found with
  `find_intent_function`, `sceneboard/OpenFlashlight` and `CloseFlashlight`).
  Confirmed on a phone by watching the torch light and go out, which is the only
  check that counts: the panel says `ok` either way. The widget also shows
  counters ("Times switched on 10") that the model seeded rather than measured.
  Without the capability sentence in the chat system prompt the assistant
  refused ("I can't control your phone's flashlight"), and an alarm prompt ("flight
  at 08:40, help me not oversleep") built a planner that told the person to set
  the alarms by hand; the sentence that lets widgets act on the phone is what
  changed that.
- A fifth, with web search and a photo: "Show me the Pushkin Museum of Fine Arts in
  Moscow with a photo of it and its opening hours." Needs an Exa key
  (`--ps exaKey ...`) and a network Exa does not block (it blocks Russian
  addresses). The assistant searches (once for the hours, once for a photo), cites
  the source in its text, and the widget shows the photo through `ui.Image` with
  the address, hours and a Directions button. The image address must be one the
  search returned; the one in the run above was checked against Exa's own
  results. Without the key there is no search and no photo.
- **Saved chats and stats.** The Chat button opens the list of saved chats (newest
  first, with message count, widgets and estimated cost; swipe a row to delete
  it) and a New chat button. A chat is saved as it goes, including each widget's
  program and its own state (`{filesDir}/vera/chats`, and `chat-<id>/` for widget
  state), so reopening it, even after the app was stopped, shows the same
  conversation and the same widgets. A widget that was still being built when
  the chat was closed comes back marked as not finished. The **Stats** switch on
  the chat screen shows the numbers the Generate screen's metrics pane shows,
  for the whole chat at the top and under each reply: time, estimated cost, LLM
  wall time against on-device compile time, input / cached / fresh / output
  tokens, web searches, and for each widget build attempt its wait, think,
  write, compile and speed. Cost uses DeepSeek's published rates and is an
  estimate.
- A failed build shows the error under the reply instead of leaving a spinner;
  this was seen when the phone lost Wi-Fi mid-build. The conversation continues.
- The conversation is not saved, and neither is a widget's state: leaving the
  screen discards both.
- The widget scrolls inside its 520 vp card, which sits inside the message list;
  no fight between the two was seen on ordinary use, but drags were not stressed.
  Generated layouts are not checked for fit, so a label can wrap badly ("Thursd /
  ay" in a half-width tile).

Run on a phone (debug-signed as a system app, DeepSeek key stored): the Chat
button on the project list opens the screen.

## What none of the prompts say

None of them mentions `intent`, `calendar`, a bundle name or a parameter. The model
is given the catalogue in its prompt and picks from it. That is the whole point
of the arrangement: a generated program cannot name a platform parameter,
because it never sees one.
