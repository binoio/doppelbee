# Relicense and identifier change — plan

**Status: complete (2026-08-19). All parts done. 2.0.0 was published and
verified end to end: feed reachable, EdDSA signature validates, a tampered
archive is rejected, and a 1.9.9 → 2.0.0 install completed through Sparkle's
sandboxed installer (installed copy is the notarized Developer ID build,
stapled, strict codesign passes). Distribution is live.**

This repository was reset to a single commit. The prior history, both GitHub
repositories, and all published releases were deleted on 2026-08-18 because the
project was distributed with an incorrect copyright holder and an institutional
bundle identifier, for work that is individually owned.

Nothing may be published again until the work below is complete.

---

## Background

DuoBee derives from [DuoBreak](https://github.com/JesseNaser/DuoBreak) by Jesse
Naser, which is licensed **AGPL-3.0-or-later**. DuoBee was distributed under MIT.
AGPL does not permit that: §5(c) requires the entire derived work to be licensed
under AGPL, and only the copyright holder of the original can grant other terms.

Evidence that DuoBee is a derived work rather than an independent implementation:

- `readme.md` — "inspired by and **based on** the protocol implementation from
  DuoBreak", "reimplements ... **from** the original DuoBreak Python tool"
- `DuoBee/Sources/Views/AboutView.swift` — "Based on DuoBreak by Jesse Naser",
  shipped in the UI of every released build
- `DuoBee/Sources/Services/DuoAPIService.swift` — `// Base32 encode the secret
  (matching Python implementation)`, indicating work from the original source
  rather than from observed protocol behaviour

Do not remove or soften these statements. They are accurate, AGPL requires the
attribution regardless, and editing them now would look like concealment.

Two paths remain open. Either resolves the licensing question:

1. **Adopt AGPL-3.0-or-later** — the compliant path if DuoBee is derived. This
   plan assumes it.
2. **Obtain a licence grant from Jesse Naser** — the copyright holder may
   dual-licence. If granted in writing, MIT becomes viable and most of Part A
   below falls away. Worth asking in parallel; it costs one email.

---

## Part A — Licensing

- [x] Replace `LICENSE.md` with the full **AGPL-3.0-or-later** text. Not a
      reference or summary — the complete text.
- [x] Set the copyright line to the correct individual holder. The prior
      "Copyright (c) 2026 The Trustees of Princeton University" was wrong.
- [x] Preserve Jesse Naser's upstream copyright. The repository currently
      carries attribution but **no upstream copyright notice and no mention of
      AGPL anywhere**. Both are required.
- [x] Add a `NOTICE` file recording: that DuoBee is a modified work derived from
      DuoBreak, what was derived, the date of modification (AGPL §5(a) requires
      a date), and that releases before this change carried an incorrect
      copyright attribution.
- [x] Change `SPDX-License-Identifier: MIT` to `AGPL-3.0-or-later` in **all 24
      Swift files**. Leaving any as MIT creates a contradictory grant a
      downstream user could rely on — worse than being simply wrong.
- [x] Update `NSHumanReadableCopyright` in `DuoBee/Resources/Info.plist`. It
      currently reads "Copyright © 2026. All rights reserved." — no holder
      named, and "all rights reserved" sits badly beside a copyleft licence.
- [x] Add Appropriate Legal Notices to the About window (AGPL §5(d)): copyright,
      licence, warranty disclaimer, and where to obtain source.
- [x] Reword the "educational and research purposes only" and "only use with
      systems you own" clauses. As **licence conditions** these are further
      restrictions, which AGPL §7 and §10 forbid — §2 grants the right to run
      the work for any purpose. Keep them as advisory warnings about legal
      exposure, and keep them out of `LICENSE.md`.
- [x] Update `readme.md`: correct copyright, state the AGPL licence, keep the
      DuoBreak attribution.

## Part B — Bundle identifier

The identifier `edu.princeton.orfe.duobee` claims an institutional reverse-DNS
namespace for an individually-owned project, and must change.

Changing it is disruptive, which is why it happens **now**, while nothing is
published and there are no users to migrate:

- The sandbox container path changes, orphaning any existing
  `~/Library/Containers/edu.princeton.orfe.duobee/.../duo.db`
- Keychain items are namespaced to the app; saved passwords stop resolving
- Sparkle treats it as a different application entirely

- [x] Choose a namespace you control. Avoid `edu.*` and any institutional
      domain.
- [x] Update `PRODUCT_BUNDLE_IDENTIFIER` for both targets in `project.yml`
      (currently `edu.princeton.orfe.duobee` and `...duobee.tests`).
- [x] Update the hardcoded `BUNDLE_ID` in `scripts/notarize.sh`.
- [x] Update the `defaults write` example in `DuoBee/Sources/Services/DuoAPIService.swift`
      (the `duoVerboseLogging` documentation comment).
- [x] Verify the Sparkle sandbox entitlements still substitute correctly. They
      derive from `$(PRODUCT_BUNDLE_IDENTIFIER)`, so `-spks` / `-spki` should
      follow automatically — confirm in the signed bundle, do not assume.
- [x] Decide whether to migrate any local database from the old container path,
      or document a manual move for anyone still running an old build.

## Part C — Infrastructure

- [x] Recreate the source repository on personally-owned infrastructure.
- [x] **Public**, as AGPL §6 requires Corresponding Source to accompany every
      binary. A private source repository with public binaries is the
      configuration that caused the original problem.
- [ ] ~~Scan the full history for secrets **before** making it public~~
      **Skipped by owner decision on 2026-08-18** — the repository was made
      public without a gitleaks scan. History was two commits at the time.
      The earlier manual verification stands: no Duo `akey` appeared in any
      commit, and no `.db` / `.duo` files were ever tracked.
- [x] Recreate the releases repository if the split hosting is kept. Note the
      original reason for splitting (private source, public artifacts) no longer
      applies once source is public; a single public repository may be simpler.
- [x] Reapply branch protection. Making a repository private silently drops
      protection rules, which is how the previous ones were lost.
- [x] ~~Generate a **new Sparkle EdDSA signing key**~~ Resolved differently by
      owner decision on 2026-08-18: DuoBee now uses the maintainer's shared
      Sparkle key (the default login-Keychain item, also used by Kona and
      other projects). That key never signed any DuoBee release, so the
      old-identity key (`aLqfo…VEik=`) is retired regardless — the intent of
      this item. The shared key must be backed up once for all projects; do
      not rotate it per-project (see RELEASING.md).
- [x] Set `SUPublicEDKey` in `Info.plist` to the new key (`SUFeedURL` already
      points at the new feed). `scripts/release.sh` refuses to publish if the key in the login
      Keychain does not match the plist — that guard is what caught the previous
      mismatch and should not be weakened.
- [x] Add a source archive to each release. AGPL §6 requires Corresponding
      Source for **that specific build**; `release.sh` already stamps the source
      commit SHA into the release body, which is a good foundation but relies on
      the repository remaining reachable at that URL.

## Part D — Release

- [x] Version as **2.0.0**. The bundle identifier change means no upgrade path
      from any earlier build; that is a breaking change and should be numbered
      like one.
- [x] Write release notes stating plainly: the licence changed to AGPL, the
      copyright attribution was corrected, the bundle identifier changed, and
      existing installations must be replaced manually and will not carry over
      their database automatically.
- [x] Run the full test suite (80 tests at time of writing).
- [x] Verify end to end before announcing: feed reachable, signature validates,
      a tampered archive is rejected, and an actual install completes through
      Sparkle's sandboxed installer. The install step is the one that fails
      quietly if entitlements are wrong — do not infer it from a successful
      download. Verified 2026-08-19: a 1.9.9 test build offered, downloaded,
      installed, and relaunched as 2.0.0 through the sandboxed installer.
      (Note: the install step fails silently if the app sits in a
      TCC-protected folder such as Desktop — test from an unprotected
      location like /Applications.)

---

## Do not skip

- **Nothing is published until Part A is complete.** Every download and every
  Sparkle auto-update is a distribution event under AGPL.
- **A full archive of the deleted history exists** at
  `~/Desktop/duobee-full-archive-*.tar.gz`. Keep it until the licensing question
  with the upstream author is settled. It is evidence of what existed and when,
  and of prompt remediation. Delete it afterwards if you wish.
- **Deletion did not reach anyone who already downloaded a build.** Copies of
  1.0.0 through 1.3.0 exist outside your control and still display "Based on
  DuoBreak by Jesse Naser" with an MIT licence. This plan fixes what is
  published going forward; it does not retract the past.
