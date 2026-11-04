# SSH enrollment and settings sync implementation plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Connect the Studio without Screen Sharing and verify that both Macs share the chosen schedule through encrypted account sync.

**Architecture:** The Studio creates its own account credentials and device keys. A browser on the MacBook approves a short-lived OAuth request whose verifier stays on the Studio. Curfew exchanges signed encrypted settings through the existing coordinator protocol and applies incoming schedule changes through local policy. Connection status and settings synchronization remain separate facts.

**Tech Stack:** Swift, CurfewKit, macOS Keychain, OAuth with PKCE, Curfew Sync encrypted-record protocol, XCTest, GitHub Actions.

---

### Task 1: Establish a headless enrollment flow

- Add focused tests for remote browser approval, callback state, cancellation, recovery, and device-specific keys. Observe failures before changing production code.
- Reuse Curfew's existing enrollment and checkpoint services. Keep secrets out of arguments, logs, and unprotected files.
- Provide an SSH-accessible command and document the operator's recovery steps.
- Verify the installed app consumes the completed enrollment without disrupting protection.

### Task 2: Exchange encrypted settings

- Add failing tests for initial pull, first publication, conflict handling, offline retry, and malformed or unauthenticated records.
- Use the published encrypted-record contract and existing cryptography. Keep device-local settings and credentials local.
- Apply schedule changes through the existing cooldown and lockout policy. Do not report synchronization until the intended record is acknowledged and applied.
- Verify convergence between independently keyed devices and preserve offline operation.

### Task 3: Integrate and validate

- Update the account sync design, user guidance, backlog, and test matrix with actual behavior and limits.
- Run targeted tests, the required format and lint checks, the full unit suite, and Debug build. Run app-hosted tests and screenshots in isolated CI.
- Produce and verify signed matching builds before installing them. Preserve background protection and the existing schedule through replacement.
- Enroll the Studio, choose the MacBook schedule as authoritative, and verify both installed versions and the active schedule on each Mac. Check pending cooldowns and synchronization acknowledgements separately.
