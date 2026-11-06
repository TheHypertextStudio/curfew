# Verify a signed CLI beta with Homebrew

Curfew release maintainers can run both Homebrew install paths on disposable
Apple Silicon Macs. Run this check after the signed candidate workflow succeeds.
Use the exact run, commit and DMG checksum from the candidate manifest.

```sh
gh workflow run signed-installer-acceptance.yml \
  --repo TheHypertextStudio/curfew \
  --ref codex/homebrew-acceptance \
  -f mode=homebrew-candidate \
  -f candidate_version="$CANDIDATE_VERSION" \
  -f candidate_run_id="$CANDIDATE_RUN_ID" \
  -f candidate_source_commit="$CANDIDATE_SOURCE_COMMIT" \
  -f candidate_dmg_sha256="$CANDIDATE_DMG_SHA256"
```

The workflow verifies the selected candidate before Homebrew uses its DMG.
One Mac starts without Curfew. The other installs public 0.0.16 first.
Each Mac uses a local cask fixture for the candidate and checks signatures,
PATH, every beta help path, JSON reads, and an unchanged repeat.
The fixture stays on the runner. Public activation uses its own approval.
