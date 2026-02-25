## Summary
`desloppify review --run-batches --runner codex --parallel --scan-after-import` fails with all batches aborted due Codex backend stream disconnects, leaving subjective reviews unimported.

## Environment
- Repo: `SwiftMTP`
- Host: macOS (darwin/arm64)
- `gh version`: 2.87.3
- `go version`: go1.26.0 darwin/arm64
- `codex`: OpenAI Codex v0.104.0 (from batch logs)
- `desloppify`: installed from PyPI (`desloppify` CLI available)

## Repro Steps
1. Run:
   ```bash
   desloppify --lang go review --path Native --run-batches --runner codex --parallel --scan-after-import
   ```
2. Observe run artifacts/logs under:
   - `.desloppify/subagents/runs/20260225_190855/logs/batch-1.log`
   - `.desloppify/subagents/runs/20260225_190855/logs/batch-2.log`
   - `.desloppify/subagents/runs/20260225_190855/logs/batch-3.log`

## Expected
- Batches complete and produce JSON output.
- Import succeeds (or clear actionable error that preserves retryability without stale/reopened subjective state confusion).

## Actual
- All batches fail with repeated transport disconnects and empty raw outputs.
- Example errors from logs:
  - `stream disconnected before completion: error sending request for url (https://chatgpt.com/backend-api/codex/responses)`
  - `failed to refresh available models: ... /backend-api/codex/models`
  - `Warning: no last agent message; wrote empty content to .../batch-*.raw.txt`
- Command reports:
  - `Failed batches: [1, 2, 3]`
  - retry suggestion with immutable packet.

## Additional Notes
- This appears to be infra/runner-level transport instability, not user code defects.
- A robust fallback path or clearer "subjective state unchanged" handling would help avoid user confusion after repeated batch transport failures.

## Request
- Please advise whether this should auto-fallback to a local/manual import flow when Codex transport is unavailable.
- If possible, improve diagnostics to distinguish "tool infra failure" vs "review content/schema failure" in the final CLI output.
