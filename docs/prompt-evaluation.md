# Prompt evaluation

This procedure checks generation, chat widgets, UI selection, refinement, and compile repair.
The cases define observable results. They do not establish a measured model-quality improvement.
Native builds and live model calls are separate from deterministic host checks.

## Record each run

1. Record the Git revision with `git rev-parse HEAD` and save the scoped prompt diff.
2. Record the provider, model identifier, UI selection mode, temperature, token limit, and date.
3. Save the exact input, assembled system prompt, tool replies, generated source, and compiler diagnostics.
4. Save the action sequence, expected result, observed result, and a screenshot or decoded UI tree.
5. Record compile attempts, truncation, and unavailable tools or adapters separately from incorrect output.
6. Mark each case PASS, FAIL, or NOT RUN, with the reason and evidence path.
7. Repeat live cases three times per prompt revision with the same settings and tool fixtures.
8. Compare baseline and candidate results without treating a single successful sample as a quality measurement.

Keep credentials out of artifacts. Use a private local evidence directory outside the repository.
For an uncommitted revision, include the diff because the commit identifier alone cannot identify the tested prompts.
For a host harness, record its exact command, input fixtures, harness revision or hash, and output artifact path.

## Cases

| Case | Exact input or fixture | Observable pass conditions |
| --- | --- | --- |
| Minimal generation | `Make a counter that starts at 7, with plus and minus buttons.` | Complete source compiles. Initial value is 7. Buttons change it by one. No invented history or metrics. |
| Log generation | `Track amounts I add toward a goal of 100. Start with an empty log and an editable amount of 25.` | Empty state renders. Two additions create two records. Earlier state snapshots remain unchanged. Repeated views have equal output. |
| Exact widget values | `Split a $187.40 bill with a 12% tip among four people. Let me edit all three values. Truncate the tip to cents.` | One self-contained English marker includes all values and the rounding rule. Initial tip is $22.48. Total is $209.88. Each share is $52.47. |
| Money helper | Execute the helper from `vera-widget.txt` with `0`, `2248`, `18740`, `-1`, and `-105`. | Results are `$0.00`, `$22.48`, `$187.40`, `-$0.01`, and `-$1.05`. |
| Invalid divisor | Change the split case to zero people. | The widget prevents zero or shows an invalid-input message. No division trap or fabricated share occurs. |
| Numeric bounds | Move each numeric control to its minimum and maximum. | Requested initial values remain exact. Calculations avoid overflow and invalid indexes. Labels identify units. |
| Timer widget | `Give me an editable 90-second countdown with start, pause, and reset.` | One compact widget uses a valid Ticker. Delayed callbacks use elapsed time. Countdown stops at zero. No system-alarm promise appears. |
| Plain answer | `What is 2 plus 2?` | Brief plain text answers 4. No widget marker appears. |
| Essential detail | `Convert 50 to my preferred unit.` | Chat asks which units are required. It does not invent the source or destination unit. |
| Phone action | `Give me buttons to turn the flashlight on and off.` | Chat offers request buttons without claiming execution. Generation discovers a suitable target. Results remain visible. |
| User data | `Create a button to request navigation to 12 Oak Street.` | Target and parameter names come from discovery. The permitted destination parameter uses `12 Oak Street`, not the tool example destination. |
| Unsupported SDK | Return a valid discovered target whose adapter answers `error: sdk.call is not implemented yet`. | The result handler shows the error. No success label replaces it. |
| SDK scalar | Return a discovered scalar result as plain text, such as `42`. | The result handler accepts string data without assuming every reply is JSON or `ok`. |
| Intent acceptance | Return `ok`, then a JSON payload such as `{"accepted":true}` in separate runs. | The UI reports the returned answer or acceptance. It does not claim the requested device outcome occurred. |
| Refusal and error | Return `declined by the person`, `declined code=1`, and `error 5: unavailable` in separate runs. | Every answer remains visible. None becomes a success message. |
| Pending device action | Delay a flashlight request callback, then return `declined by the person`. Repeat without a previously confirmed device state. | The UI shows pending until the callback. It preserves the prior confirmed state or shows unknown state. Refusal stays visible and does not change the confirmed state. |
| Unavailable tools | Generate a phone-action request with a provider that has no discovery tools. | The program preserves useful local behavior and shows the capability limitation. It invents no platform target. |
| Minimal UI needs | `Show the number 7.` | Output is a strict JSON array of short English phrases. It contains a numeric display need without invented controls or extra features. |
| Timer UI needs | `An editable countdown.` | Distinct phrases describe duration input, countdown display, and automatic updates. No duplicate phrases or unrelated features appear. |
| Refinement | Generate the counter, set it to 9, then request `Add a reset button that resets the counter to 7.` | Output is complete source. Compatible state fields retain their names and types. The value 9 survives state restoration. Reset produces 7. |
| Compile repair | Submit failed source with `==` and its actual compiler diagnostics. | Retry refers to that failed source and fixes the diagnosed operator. It returns a complete program and preserves requested behavior. |
| Truncation repair | Cut generated source inside a function and report the output token limit. | Retry returns a shorter complete replacement. It does not return only the missing suffix or remove required behavior. |
| Table widget | `Compare three phone plans: Basic is 10 dollars for 5 GB, Plus is 20 dollars for 20 GB, Max is 35 dollars for unlimited data.` | Chat offers one widget, not only a text list. It is a ui.Table with a header row and one ui.TableRow per plan, columns matching the header count. Values match the input. No editors appear. |
| Chart widget | `Show my steps this week as a chart: Mon 5200, Tue 7800, Wed 6400, Thu 9100, Fri 4300, Sat 11200, Sun 8000.` | One widget uses ui.Sparkline with the seven values in order and a label naming steps per day. The day names appear in text or a table. Any total or average is computed from the values. The widget fits without scrolling and has no per-day editors. |
| Marker parsing | Stream a reply with one complete `<<app: ...>>` marker, then repeat with the closing `>>` missing. | Complete marker yields one description. Partial marker remains incomplete. Visible prose contains no broken sentence around the marker. |

## Deterministic checks

1. Assemble the full-catalogue, selected-catalogue, and widget prompts through their existing paths.
2. Verify that no unresolved `{{UI_CATALOG}}` or `{{UI_TOOL_NOTE}}` remains in the assembled prompts.
3. Compile the complete example from `vera-skill.txt` with the actual compiler.
4. Run init, view, setSize, and add through the actual VM and decode the UI.
5. Compare state snapshots before and after each handler and repeated view call.
6. Compile and execute the money helper against the five values in the table.
7. Use deterministic provider responses to exercise refinement, compile repair, truncation, UI extraction, and marker parsing.
8. Save expected and observed results with the tested revision and exact harness command.

Host checks verify source contracts and transport behavior. They do not measure live model adherence or prove device actions.
For device cases, record the actual device outcome separately from the returned acceptance text.
The server provider owns a separate prompt outside this repository. Evaluate that prompt separately if its behavior is relevant.
