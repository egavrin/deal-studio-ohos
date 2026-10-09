# Chat widget context and capability verification

The change shares capability preparation between Chat and Generate. It adds structured handoffs, explicit revision targets, and saved source. Each revision appears in a new reply and starts from generated defaults. Earlier widgets retain their independent state.

## Method

The host harness reads current application sources. Platform services, model transport, and file storage use deterministic fixtures. Widget programs compile, initialize, render, and execute handlers through the actual compiler, VM, and UI decoder.

Fixture failures were defined before the corresponding production edits. The preparation baseline failed seven checks. Concurrent direct index callers completed early with an empty cache. The candidate waits for the active read. The cancellation baseline sent a model request after cancellation. The candidate sends none.

The renderer workflow compiles the counter fixture, records its initial value, changes it through a handler, saves the state, and reloads it. Snapshot values match the rendered state. Runtime snapshots provide reference data only. A revision does not receive the earlier widget's state-storage key.

## Evidence

Tested production and harness revision: `3a5affbac68c05ec4bcc991862b88ba21c14eb4e`.
Base revision: `b0a575d5aa98bee40368c3072be2ef531787dd6f`, which includes merged PR #14.
The following documentation commit only saves evidence.

| Workflow | Result | Report |
| --- | --- | --- |
| Chat handoff and revisions | 15/15 PASS | [handoff.json](chat-widget-evidence/handoff.json) |
| Prompts and generation | 23/23 PASS | [prompts.json](chat-widget-evidence/prompts.json) |
| Capability and renderer lifecycle | 7/7 PASS | [capabilities.json](chat-widget-evidence/capabilities.json) |
| Visual compatibility | 93/93 PASS | [visual.json.gz](chat-widget-evidence/visual.json.gz) |

Reports include source hashes, exact commands, and observed results. The checked-in harness defines the exact SSE chunks, request values, search results, and mock responses. The capability report includes decoded trees and runtime snapshots. Logs are stored beside the reports.

The handoff fixtures cover structured and legacy markers, quoted `>>`, duplicate fields and markers, invalid targets, incomplete and oversized content, exact request fields, conversation limits, current-turn search results, and send-start snapshots. They exercise source persistence, source-less recreation, fresh revision defaults, failed revision isolation, serialized queue recovery, compiler diagnostics, and tool continuation. Intent tool results are checked with embedding search and keyword fallback. Each application-source request retains enabled reasoning, 32,768 output tokens, and temperature 0.2. Ordinary chat retains its prior settings.

Pre-edit evidence: [capability baseline](chat-widget-evidence/capability-before.json) and [cancellation baseline](chat-widget-evidence/cancellation-before.json). These reports identify the original revision and failed checks. Their fixtures preceded the corresponding fixes.

Run from the repository root with an installed TypeScript module available. Set `VERA_TYPESCRIPT_PATH` when Node cannot resolve it:

```bash
node tools/vera-harness/chat-handoff-check.js . /tmp/vera-chat-handoff.json
node tools/vera-harness/prompt-check.js . /tmp/vera-prompts.json
node tools/vera-harness/capability-check.js /tmp/vera-capabilities.json
node tools/vera-harness/visual-check.js /tmp/vera-visual.json
```

The recorded run used:

```bash
export VERA_TYPESCRIPT_PATH=/Users/egavrin/.codex/worktrees/porting-guide-main/arkestr/.dexter-local/porting-baseline/nominal-edges-root-acceptance/54/published-e2e/.dexter-local/tests/coverage-controls/run-UvDYkQ/project/node_modules/typescript/lib/typescript.js
```

No package installation was necessary. The archived visual report is gzip-compressed JSON with its original command and revision.

## Limits

TypeScript transpilation and host workflows do not establish native ArkTS compatibility or device behavior. The capability fixture accelerates the 10-second readiness deadline to 20 milliseconds. Embedding tests use deterministic native boundaries rather than a downloaded model.

The repository tool discovery cannot find ArkTS Agent Kit, hdc, or hapsigner. Native build, installation, and device screenshot checks are unavailable. The user authorized work with the available tools. No live model quality evaluation was run.

## Implementation ownership

Claude Opus High was attempted through the claude-collab skill. The helper stopped its request after 900 seconds without meaningful model progress. The reported model was claude-opus-5-5. It returned no patch. One native Astra High owner received only the remaining handoff package. Codex owns integration and acceptance. This is not a delegated-route benchmark. The effective route is `sol-astra`, under the default Sol routing policy. The session exposes the GPT-6 root family, but not its specific variant, reasoning level, or service tier. [Coordination evidence](chat-widget-evidence/coordination.json) records the attempted companion and native fallback.
