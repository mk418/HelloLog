# HelloLog — Design Notes

## Ideas to explore

### Chronological event view

A timeline view of a recording that interleaves every captured event in
order: loot, kills, deaths, zone changes, consumable use, rep changes,
disenchants, trades. The detail panel currently aggregates everything
into per-section summaries; a chronological view would let you replay a
session and see how it unfolded over time.

Open questions:

- Do all event paths already record a timestamp? Loot/kills/rep do not
  yet — they'd need one added at capture time.
- Where does it live in the detail panel? Separate "Timeline" toggle, or
  a new section alongside Items/Consumables/etc.?
- Density: do we collapse bursts (e.g. "looted 5 items from Defias
  Marauder") or show every line?
- Should historical (closed) sessions support it too, or only the live
  session?
