## Summary
Feature request: for multi-language repositories, `desloppify` should generate **per-language score panels/scorecard images** in addition to the aggregate codebase score.

## Context
This project contains multiple languages (Swift + Go). We run language-specific scans such as:

```bash
desloppify --lang go scan --path Native
```

But in day-to-day workflow, teams also run whole-repo scans (`--path .`). In mixed-language repos, a single aggregate score can hide debt in one language while another language remains healthy.

## Why this matters (aligned with current tool guidance)
`desloppify` scan output includes the instruction block for agents:
- "ALWAYS present ALL scores to the user after a scan"
- show overall/objective/strict/verified
- show all mechanical + subjective dimensions

For multi-language repositories, this same principle should apply **per language**, not only globally.

## Current behavior
- Aggregate scorecard is generated (for current scan state).
- Users can force one language via `--lang`, but there is no first-class multi-language breakdown artifact from one run.

## Expected behavior
When scanning a mixed-language repo, provide language-separated reporting artifacts, for example:

1. Per-language score sections in CLI output (Swift/Go/TypeScript/etc), each with:
   - overall/objective/strict/verified
   - mechanical + subjective dimensions
2. Per-language scorecard image files, e.g.:
   - `scorecard-go.png`
   - `scorecard-swift.png`
3. Optional aggregate image remains available (`scorecard.png`).
4. `status` should expose the same per-language breakdown without requiring separate manual runs per language.

## Suggested CLI shape (example)
- `desloppify scan --path . --by-language`
- `desloppify status --by-language`
- `desloppify scan --path . --badge-path scorecard-{lang}.png --by-language`

## Acceptance criteria
- In a repo with >=2 detected languages, `--by-language` outputs distinct score blocks and artifacts per language.
- Each language block follows current score-reporting contract (overall/objective/strict/verified + all dimensions).
- Aggregate + per-language outputs are both available and clearly labeled.
- State interactions are deterministic (no ambiguity between global state and language-scoped state).

## Notes
Related reliability friction we also observed while running language-focused review batches is tracked separately in issue #139.
