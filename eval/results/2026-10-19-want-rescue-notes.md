# Independent yes/no "does the request ask for this block" as a rescue (2026-10-19)

Change: every block now has its own yes/no question (include.* for the layout kinds, new want.* for the rest). When no section
cleared its 0.5 bar, the best block that can stand alone (not a reader) above WANT_ABOVE = 0.5 is built (vetoes still apply, a
soft veto makes it a `complete`). A 26-way section choice splits probability between overlapping blocks; a yes/no does not.

Cake prompt, 10 runs each: "Birthday cake list for 10 people" 0 -> 10 built; "List for 10 people for birthday cake" 0 -> 1 built
(include.checklist 0.46 to 0.53 around the bar). Jev time unchanged (median 0.6 s).

Phone sweep, selection only, 127 prompts (all 80 that picked nothing in the baseline plus 47 that did):
- baseline picked nothing (80): 33 built now (32 of 62 positive, 1 of 18 negative: pt-04-computation, a music player got `metrics`);
  47 still nothing (30 positive, 17 negative).
- baseline picked blocks (47): 6 lost all blocks (hf-03-terse, pf-02-descriptive, pt-01-computation, pt-04-terse, hc-04-computation,
  hc-06-terse), the rest kept or changed blocks. The control re-run of unchanged code moved 2 of 10, so about 4 of 47 is noise;
  not shown to be a regression, not shown to be none.
- Bar sweep on the 80 (best stand-alone yes/no): 0.40 -> 36 of 62 positive / 5 of 18 negative; 0.45 -> 32 / 4; 0.50 -> 30 / 3;
  0.55 -> 24 / 3; 0.60 -> 16 / 2. Raising the bar above 0.5 loses positives and barely removes negatives, so 0.5 stays.

Quality of what was built, read by hand: sensible for staged lists (checklist for call-backs, guests, books, tools), record keeping
(record_log), schedules (timeline). Doubtful: `key_facts` was built for six calculation prompts (BMI-like, fuel economy, suitcase
weight, date difference) and `metrics` for several non-counter prompts; these have no block that computes, so they depend on the
needs_logic veto to hand them to the model. Not checked on the phone: what the built screens show, and that a rescued key_facts
screen is better than generation from scratch.
