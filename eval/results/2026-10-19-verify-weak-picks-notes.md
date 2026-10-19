# Second opinion on weak picks: measurement (2026-10-19)

Mechanism: when Jev picks no block but names one at 0.25 to 0.5 and nothing is vetoed, DeepSeek-flash (no tools, no thinking,
200 tokens) is asked whether the named block alone does what the request asks. It can only confirm kinds Jev named. Built as a
normal template when confirmed; any failure means generation as before. Code: `VeraPickVerify.ets`, host check `verify-check.js`.
Shipped switched OFF (`VERIFY_WEAK_PICKS = false`); the measurement below ran with it on.

Set: the 47 prompts (37 positive, 10 negative) that the baseline sweep left as scratch with a candidate at >= 0.25. Phone sweep,
selection only: the screens built after a confirmation were not inspected.

| | positive | negative |
|---|---|---|
| asked (Jev named a weak candidate in this run) | 29 | 4 |
| confirmed | 4 | 0 |
| rejected | 25 | 4 |
| not asked (Jev gave no weak candidate this time) | 8 | 6 |

Latency of the extra call: 0.83 to 1.78 s (median about 1.05 s). False accepts: 0 of 4 negatives asked (10 negatives in the zone, 6 not asked
because Jev's answer moved between runs).

Confirmed: hc-03-descriptive (record_log), tp-05-descriptive (record_log, number_strip), sc-02-terse (checklist), pt-05-computation (record_log).
The last looks wrong: hours times rate needs a calculation the block does not do, and the model's own `missing` field said so.

Rejected as too strict: si-04-terse (lent tools, a two-state list, rejected as "persistent tracking"), tp-01-terse (search_list), pt-03-terse and
hf-04-descriptive (note), si-02 x2 (data_table), pf-06-terse (master_list). Most other rejections are the calculation prompts, which is
right: a conversion, BMI, weighted grade, fuel economy, scaling by a number have no block (candidate 4.3-C `formula_form`).

Read: at most 3 right gains out of 37, one doubtful, and a strict prompt that also rejects some simple lists. The useful by-product is the
`missing` text for every rejection (in the json): a ready "prompt -> missing role" column from real requests.
Not measured: whether confirmed screens work on the phone, repeat runs, a looser question.
