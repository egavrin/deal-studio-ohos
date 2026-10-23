# The agent: how a new screen is built

A new screen (the Generate screen, or a widget in the chat) is built by the **route**
(`agent/VeraBuildRoute.ets`): the **agent** first, the **blocks** after it, then the **whole screen as one hole**.
What none of them builds is handed to the model to write from scratch on the Generate screen (the chat reports it as
*not built*, with the reason). A change to an existing program goes to the model (refine), as before.

The idea: planning and building each have a fast path, where Jev picks something ready, and a slow path, where the
model writes it. A simple request is built from Jev's picks alone; the more a request asks that nothing ready does,
the more of it the model writes, down to the whole screen.

## Terms

| term | what it is | where |
|---|---|---|
| **sketch** | the plan, as DeepSeek (no thinking) writes it: a JSON object of inputs, constants, values with formulas, a countdown or stopwatch, a list, events (what the phone does, and when), *ready* needs (things a catalogue section does whole), other items, and at most two questions | `VeraCompose.ets` (`SKETCH_BASE`, `parseSketch`) |
| **Jev's choices** | one Jev call over the sketch: a formula for each value, a widget for each input, an effect and a moment for each event, a catalogue section for each ready need, what is covered or left out | `buildComposeRequest`, `readComposition` |
| **block** | one piece of a program in the one format (`FragmentSpec`): state fields, handlers, a view, and tokens for content, ports and holes. The catalogue's **sections** (checklist, itinerary, timeline, charts, timer, reminders, ...) and the composer's **parts** (inputs, figures, clock, list, effects) are both blocks | `VeraTemplates.ets`, `compositionParts` |
| **ScreenPlan** | the one plan format both paths give: the screen's *state* (named values), its *slots* (each thing it does, with what it reads and writes, and whether it is a phone action) and the *components* that fill them. A slot is *open* until something fills it; a plan with an open slot is not served | `ScreenPlan.ets` |
| **effect** | one of six phone actions the composer wires itself: vibrate, beep, add to calendar, navigate, clear calendar, open calendar | `EFFECTS` in `VeraCompose.ets` |
| **hole** | what the model writes for slots nothing ready fills. A *catalogue hole* is one function body inside a section; a **section hole** is a whole section for the open slots; the **whole-screen hole** is the screen as one section | `VeraHoles.ets`, `agent/AgentHole.ets`, `agent/AgentCustom.ets` |
| **blocks** (the fast path) | Jev picks a layout and sections straight from the request, without a sketch; the model fills their text | `VeraTemplatePipeline.ets` |
| **notice** | a warning banner in place of what could not be built: "Not available on this phone" with the writer's own sentence, or "Part of this app could not be built" | `noticeBlock` in `agent/AgentHole.ets` |

## The algorithm

1. **Plan.** DeepSeek writes the sketch. One that is missing or does not parse is asked for again with what was wrong,
   then once with thinking on. (The blocks' own Jev pick is made only if the blocks are reached: it used to start beside
   the plan on every request and was thrown away whenever the agent served.)
2. **Questions.** Jev keeps only the sketch's questions a default cannot stand in for; the person answers on a card,
   and an answer other than the default has the plan drawn again.
3. **Choices.** One Jev call (asked twice if it does not answer) decides how each item is built. What the plan leaves
   open is settled, not refused:
   - a countdown nothing sets the length of, or a figure the parts read that no formula works out, becomes an input
     the person sets, starting from the plan's own number, and the person is told;
   - an event no effect does as asked, the person's own records, a figure nothing works out, an item of "other",
     a ready need with no section: a slot for the written section;
   - an input nothing uses is left out, with a note.
3a. **Align** (`--ps veraAlign 1`, off by default; `AgentAlign.ets`). What the choices leave for the model to write -- a ready
   need no section was chosen for, an event no effect does, an item of "other" -- is offered to the catalogue once more:
   one Jev question per such need, whose answers are a ready-made section (the plan's ready kinds, `reminders`,
   `calendar_event`) or none. A section at 0.5 or more is added once, whatever number of needs it does, and takes those
   needs out of what is written; what Jev finds none for is still written. The person's own records and the figures
   worked out by a written formula are never offered, and a section the screen already has does not stand in for a need.
   When nothing is left to write, the inputs the composer kept only for the written section are dropped. Measured so far:
   8 prompts live, one changed (`set an alarm for my medication every day` is a `reminders` section instead of a notice)
   and none given a section wrongly; not yet run on the 121 prompts or on a phone.
4. **Fill.** The catalogue sections' content is written (from a web search when it must be real) and their holes
   filled, by the one fill both the agent and the blocks use (`SectionFill.ets`): a trend chart or a live-facts block is
   always grounded in a search whatever the plan said (the chart with the longer results), a live-facts block shows only
   the figures and the source that search contains, and with no search the sections are refused.
5. **Section hole.** One section is written for the open slots (`writeHole`, `writeSection`):
   - for each phone slot the app's own lookups run first (`find_intent_function`, keyword and embedding rankings
     together; `find_sdk_function`), and the section may call only targets they returned -- every `sdk.call` target is
     checked before serving;
   - it is compiled and run once with every handler tapped; failures are quoted back for a repair, at most twice;
   - Jev reads it against each need; a need it reads as not done is asked for again;
   - after the quick tries, one more with thinking on;
   - still failing: the best try that works and does part of it is served with a notice for what it misses; none, a
     notice in its place; `<cannot>` (nothing on this phone does it) is reported as the writer says and not retried.
6. **Check.** The assembled program is compiled, started, drawn and run with every handler tapped (`VeraSmoke.ets`); one
   that fails, or draws an empty screen, is repaired with SEARCH/REPLACE edits, at most twice (`settleProgram`). Every
   program served goes through it, whoever assembled it: the agent, the blocks, a written section or the whole screen.
   **Record.** A served screen that rebuilds exactly from its plan gets a record (`VeraComposition.ets`, `AgentResult.record`):
   the plan's components in order, the catalogue's blocks with their values and hole bodies, everything else (the composer's
   parts, a written section, a notice) as it is. A request to add a section, take one away, swap or move one is then
   answered without the model (`tryStructuralEdit`); it may point at the catalogue's blocks and the written section or
   notice, never at a part (the parts hold each other's state). No record when the repair edited the program, and none is
   kept that does not rebuild the served one. A chat widget is not edited this way.
7. **Blocks**, when the agent did not build it: a plain template is served; when the sections are right but the
   request needs more (a soft veto, an intent panel with no rows, buttons only), or the agent's plan names a phone
   action they do not do, the layout stays and a section hole is written into it.
8. **Whole screen**, when neither did: the sketch as one hole, with the same lookups and checks.
9. **Not built**, with what the agent and the blocks each said.

A request's holes share what they learned: a phone need one hole found nothing can do is reported by the next as it
said, and each lookup is made once.

## Results

Host runs (`tools/vera-harness/agent-run.js -r`, the 121 prompts of `compose-fresh.tsv`, `compose-prompts.tsv` and
`tools/vera-bench/prompts.tsv`), 2026-10-22. The host has no phone lookups, so a phone action there always ends in
a notice; on the phone the same prompts call the phone.

| how it was built | prompts | median | p90 |
|---|---|---|---|
| agent, composer parts only | 88 | 2.0 s | 2.5 s |
| agent + written section | 17 | 6.7 s | 14.4 s |
| agent + notice (phone actions, live data) | 13 | 5.8 s | 9.5 s |
| agent + catalogue sections | 3 | 5.6 s | 7.1 s |
| blocks, whole screen, not built | 0 | | |

Eight game-like requests (tic-tac-toe, hangman, memory, flashcards, ...): all written by the agent, 5-13 s.

On the phone: Shanghai layover 10-23 s, soft-egg timer 2.5 s, to-do list 14 s, hangman 20 s, contacts 6-9 s,
melody with the flashlight 22.6 s; "set an alarm" and "share my location" 6-7 s with a notice (the phone exposes no
target that does either). Generation from scratch, which these replace, took over 30 s for requests like Shanghai and
the melody.

## Switches and tools

- `--ps veraOrder blocks-first` puts the blocks before the agent; `--ps veraCustom 0` turns written sections off;
  `--ps veraWhole 0` the whole-screen hole; `--ps veraAlign 1` offers what would be written to the catalogue first.
- `tools/vera-harness/agent-run.js [-r] [-w]` runs the agent (or the whole route) live on the host: DeepSeek
  (`$ARKESTR_API_KEY`), Jev (`$TYPESAFE_API_KEY`), Exa (`$EXA_API_KEY`, optional).
- Every written hole is recorded: a `hole` event in the app's trace, `holes.jsonl` beside each host run.
  `tools/vera-harness/hole-report.py` groups the needs that recur -- the blocks the catalogue lacks.
- Host checks: `tools/vera-harness/{agent,plan,parts,compose,route,pipeline,section-fill,align,align-agent}-check.js`; fixtures in
  `tools/vera-harness/compose/`.

## Known limits

- This phone has no target that creates a Clock alarm, texts a phone number (MeeTime's `SendTextMessage` takes a
  MeeTime contact id) or shares the live location; such requests end with a notice.
- `contacts/AddContact` wants a vCard in `contactInfo`; the intent index does not say so, and the call is declined.
- Jev reads code, not behaviour: a melody section whose beats all fired at once was read as doing its job.
- Each live run of the 121 prompts makes several hundred Jev calls.
