# Cutover Implementation Plan

## Pre-Deletion Checklist

- [ ] Run complete Swift tests and focused backend/manager/transfer suites.
- [ ] Run Debug and Release builds with Swift provider selected.
- [ ] Run and record the full Android hardware matrix.
- [ ] Run sequential normalized Go/Swift parity comparison.
- [ ] Run and record Go normal/race/vet plus native build/header/ABI checks before deleting `Native/`.
- [ ] Record the pre-cutover Git commit for rollback.

## Removal Checklist

- [ ] Make Swift provider the sole backend and simplify dependency wiring.
- [ ] Remove all direct/indirect `Kalam_*` calls and migration Go adapter.
- [ ] Delete `Native/`, Go/vendor/tests and libkalam artifacts.
- [ ] Remove `Scripts/build_kalam.sh` and Go test/setup branches.
- [ ] Update Xcode embed/link/search/bridging settings; retain explicit CLibUSB/libusb integration.
- [ ] Update README, wiki, diagrams, testing docs and localized credits.
- [ ] Search for stale Go/CGO/libkalam references and classify any Trellis-history-only matches.
- [ ] Write final `verification.md` with all AC, command/test counts, hardware matrix, build/Analyze/static-audit/dylib evidence and rollback commit.

## Verification

```bash
MIGRATION_PATH="/usr/bin:/bin:/usr/sbin:/sbin"
MIGRATION_DERIVED_DATA="$(mktemp -d)"
MIGRATION_BUILD_SETTINGS="$(mktemp)"
! env PATH="$MIGRATION_PATH" /usr/bin/which go
env PATH="$MIGRATION_PATH" \
  xcodebuild -project SwiftMTP.xcodeproj -scheme SwiftMTP -configuration Debug -derivedDataPath "$MIGRATION_DERIVED_DATA" clean build
env PATH="$MIGRATION_PATH" \
  xcodebuild -project SwiftMTP.xcodeproj -scheme SwiftMTP -configuration Release -derivedDataPath "$MIGRATION_DERIVED_DATA" clean build
env PATH="$MIGRATION_PATH" \
  xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP -destination 'platform=macOS' -derivedDataPath "$MIGRATION_DERIVED_DATA" CODE_SIGNING_ALLOWED=NO
env PATH="$MIGRATION_PATH" ./Scripts/create_dmg_simple.sh
env PATH="$MIGRATION_PATH" xcodebuild -project SwiftMTP.xcodeproj -scheme SwiftMTP -showBuildSettings > "$MIGRATION_BUILD_SETTINGS"
! rg '/opt/homebrew|pkg-config' "$MIGRATION_BUILD_SETTINGS"
otool -L <built-app>/Contents/MacOS/SwiftMTP
codesign --verify --deep --strict --verbose=2 <built-app>
find <built-app>/Contents/Frameworks -maxdepth 1 -type f -print
! git grep -nE 'Kalam_|libkalam|CGO|go-mtpx|build_kalam|go build|go test' -- SwiftMTP SwiftMTPTests SwiftMTP.xcodeproj Scripts docs README.md CLAUDE.md AGENTS.md
git diff --check
```

The build-settings command must succeed, then the negated `rg` and scoped grep must succeed by finding no matches. Record the restricted PATH, fresh DerivedData path and built binary linkage in `verification.md` as AC10 evidence.

## Quality Gate

- Full tests, Debug/Release/Analyze, DMG/link/sign, static absence checks, and
  `git diff --check` pass with exact evidence recorded.
- `.app` includes libusb and excludes libkalam.
- No clean-build command invokes Go or Homebrew.
- Hardware and simulated evidence are clearly distinguished.
- Worktree diff contains only migration/task artifacts.

## Commit

Use the dedicated `commit` agent with the exact authorized migration scope and completed validation facts. Do not push.

## Rollback

If any final gate fails, restore the pre-cutover verified commit and reopen the failing child rather than weakening acceptance criteria.
