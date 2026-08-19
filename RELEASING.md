# Releasing DuoBee

DuoBee auto-updates via [Sparkle](https://sparkle-project.org). Releases are cut
**locally** — there is no CI that builds or publishes. Everything below runs on
one designated release Mac.

## How distribution is arranged

Everything lives in **one public repository**:

| | |
|---|---|
| Source + Artifacts | `binoio/duobee` (public) |
| Update feed | `https://binoio.github.io/duobee/appcast.xml` (Pages, `main` `/docs`) |
| Downloads | GitHub Releases on `binoio/duobee` |

The repository **must remain public**: Sparkle fetches the feed and the app
archive without credentials, and AGPL §6 requires Corresponding Source to be
available for every published binary. To make that survive any future hosting
change, `release.sh` also attaches a source archive of the tagged commit to
each release, and stamps the commit SHA into the release body.

`scripts/release.sh` tags this repo, uploads assets to its Releases, and
commits the regenerated appcast to `docs/` on `main`.

### Threat model for the public repo

DuoBee holds Duo authentication secrets, so its update channel is a path to
every installed copy of a credential store. Worth being explicit about what
protects it.

**What write access to the repo does *not* get an attacker.** Trust
comes from the EdDSA signature, not from the transport or the hosting. Every
archive is signed with a private key that exists only in the login Keychain of
the release Mac, and each installed app verifies against the `SUPublicEDKey`
baked into its own bundle. Someone who fully controlled the public repo could
serve a modified appcast or swap the assets, but could not produce a valid
signature — clients reject the update. Notarization and Developer ID signing are
a second, independent check.

**What it does get them.** Three things the signature does not prevent:

- **Denial of updates.** Deleting or corrupting `docs/appcast.xml` stops every
  client from learning about new versions. Failures are quiet — background
  checks surface nothing — so users could sit on an old build indefinitely
  without noticing.
- **Rollback to an older signed release.** Past archives carry valid signatures
  forever. An attacker who kept an old asset could re-advertise it to steer
  users onto a version with a known flaw. Sparkle does not refuse a downgrade on
  its own; `minimumSystemVersion` and pulling superseded assets are the levers.
- **Metadata and release-note content.** Notes are embedded in the appcast and
  rendered in the update dialog, so they are attacker-controlled text shown
  inside the app. It is not a code path, but it is a phishing surface.

**Where the real risk sits: the signing key.** Compromise of that key is the
break that matters — it would let an attacker sign a malicious DuoBee that every
installed copy accepts and installs, with access to the decrypted key database.
It never leaves the release Mac's Keychain, is never exported to CI, and there
is deliberately no automated path that can sign a release. Keep it that way: a
signing key in a CI secret is a signing key one repo compromise away from
shipping malware to a credential manager.

**Practical consequences.** Limit write access to the repo to the same
people who could publish from the release Mac — it is not just source hosting,
it is the distribution channel. Protect the default branch.
Treat unexpected commits to `docs/` as an incident, not a mistake. And since a
lost key is unrecoverable while a leaked key is catastrophic, back it up
somewhere that is itself encrypted, and nowhere else.

---

## One-time setup on the release Mac

Work through these in order. `scripts/release.sh` checks every one of them in
preflight and stops with a specific message, so it is safe to just run it and
follow what it says.

### 1. Tools

```zsh
brew install xcodegen gh
xcode-select -p            # Xcode 15+ required; 26.6 was used to build 1.3.0
```

### 2. GitHub access

```zsh
gh auth login
gh repo view binoio/duobee    # must succeed
```

### 3. Developer ID Application certificate

```zsh
security find-identity -v -p codesigning | grep "Developer ID Application"
```

If nothing prints, create one: **Xcode → Settings → Accounts → select the team →
Manage Certificates → + → Developer ID Application**. Being signed into Xcode is
*not* sufficient — an Apple ID grants *Apple Development* certs, which cannot
sign for distribution outside the App Store. Creating a Developer ID cert
requires the Account Holder or Admin role on the team.

### 4. Notarization credentials

```zsh
xcrun notarytool store-credentials notary \
    --apple-id <apple-id> --team-id 43L352U8Y8
xcrun notarytool history --keychain-profile notary   # must succeed
```

The profile name must be `notary`, or pass `NOTARY_PROFILE=<name>`.

### 5. Sparkle signing key

**This is the one that cannot be recovered if lost.** It is the root of trust for
every future update: without it, no installed copy of DuoBee can ever be updated
again. It is not the same thing as the Developer ID certificate, and Apple has no
copy of it.

DuoBee uses the maintainer's **shared** Sparkle key — the default login-Keychain
item that also signs updates for other projects (Kona, etc.). Do not delete or
regenerate that item to "rotate" DuoBee's key: it would silently break updates
for every other project signed with it. If DuoBee ever needs its own key, give
it a separate item via `generate_keys --account DuoBee` and pass the same
`--account` to `generate_appcast` in `release.sh`.

The tools live in the resolved package artifacts, so resolve first:

```zsh
xcodebuild -resolvePackageDependencies -project DuoBee.xcodeproj \
    -scheme DuoBee -derivedDataPath build/DerivedData
BIN=build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin
```

Then pick **one** of:

**A. Generate a fresh key on the release Mac (recommended while nothing has shipped).**
No key is ever transferred between machines.

```zsh
"$BIN/generate_keys"          # prints the public key
```

Paste the printed value into `SUPublicEDKey` in `DuoBee/Resources/Info.plist`,
commit it, and you are done. Valid only *before* the first Sparkle-enabled
release — after that, changing the key orphans everyone already running DuoBee.

**B. Import an existing key** (required once 1.3.0 has shipped, or to release
from more than one Mac). On the Mac that has the key:

```zsh
"$BIN/generate_keys" -x duobee-sparkle-key.txt
```

Transfer it over a secure channel, then on the release Mac:

```zsh
"$BIN/generate_keys" -f duobee-sparkle-key.txt
```

Delete the exported file afterward — its contents are equivalent to the key
itself.

Either way, verify the app and the Keychain agree:

```zsh
"$BIN/generate_keys" -p
/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" DuoBee/Resources/Info.plist
```

These two **must** print the same string. `release.sh` refuses to proceed if they
differ, because a mismatch produces updates that every client silently rejects,
with no error anywhere until users report that updates stopped working.

### 6. Back the key up

```zsh
"$BIN/generate_keys" -x /path/to/secure/duobee-sparkle-key.txt
```

Store it in a password manager or an encrypted volume, then delete the file.
Do this once, now — not after the Mac fails.

---

## Cutting a release

### 1. Bump the version

Both keys in `DuoBee/Resources/Info.plist`, kept identical:

```zsh
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 1.4.0" DuoBee/Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 1.4.0" DuoBee/Resources/Info.plist
```

Sparkle compares `CFBundleVersion` and displays `CFBundleShortVersionString`.
`release.sh` requires they match and that the version is `X.Y.Z`.

### 2. Write release notes

Both files are required, named to match the version exactly:

- `ReleaseNotes/DuoBee-<version>.md` — becomes the GitHub Release body
- `ReleaseNotes/DuoBee-<version>.html` — embedded in the appcast and shown
  inside Sparkle's update dialog

Copy the 1.3.0 pair as a starting point. The `.html` basename must match the zip
basename, which is how `generate_appcast --embed-release-notes` attaches it.

### 3. Commit

The working tree must be clean — `release.sh` will not tag an uncommitted state.

### 4. Dry run

```zsh
TEAM_ID=43L352U8Y8 ./scripts/release.sh --dry-run
```

This runs everything — preflight, tests, build, notarize, staple, all bundle
assertions, appcast generation and signing — and stops before publishing.

Check the generated appcast at `build/releases-repo/docs/appcast.xml`. In
particular, if it contains `<sparkle:hardwareRequirements>arm64</...>`, the build
came out Apple-silicon-only and Intel Macs will never be offered the update.

### 5. Publish

```zsh
TEAM_ID=43L352U8Y8 ./scripts/release.sh
```

Ordering is deliberate: the GitHub Release (and its asset) is created *before*
the appcast is committed, so Pages never advertises a download that 404s.

### 6. Verify

```zsh
curl -sI https://binoio.github.io/duobee/appcast.xml | head -1   # 200
curl -s  https://binoio.github.io/duobee/appcast.xml | grep enclosure
```

Pages takes a minute or two to redeploy. Then confirm the enclosure URL
downloads **unauthenticated** — in a private browser window, or with `curl` and
no token. That silently breaks if the repo is ever flipped to private — which
would also strip Pages and violate the AGPL source requirement.

---

## What `release.sh` checks before publishing

Worth knowing, since these are the failure modes that are expensive to discover
after the fact:

- Working tree clean; tag does not exist; version is newer than the latest tag
- `CFBundleShortVersionString` == `CFBundleVersion`, both `X.Y.Z`
- Release notes present in both formats
- Developer ID identity present; `gh` authenticated; releases repo reachable
- **Keychain signing key matches `SUPublicEDKey`**
- Full test suite passes
- `SUFeedURL` present and `https`; `SUPublicEDKey` not the placeholder
- `SUEnableInstallerLauncherService` set (required for the sandbox)
- `SUEnableAutomaticChecks` **absent** — setting it suppresses Sparkle's
  first-run consent prompt
- `Sparkle.framework` and `Installer.xpc` embedded
- Entitlements contain the substituted `<bundle-id>-spks` / `-spki` mach-lookup
  names — an unsubstituted `$(PRODUCT_BUNDLE_IDENTIFIER)` signs and notarizes
  fine, then fails at install time
- `codesign --verify --deep --strict` passes
- Generated appcast references the new zip and carries an `edSignature`

## Notes

- The app is **sandboxed**, and stays that way. Sparkle installs updates through
  its sandboxed installer XPC service rather than by relaxing the app.
- The framework and its XPC services are embedded and signed automatically by
  `xcodebuild archive`/`-exportArchive`. No manual embedding or inside-out
  codesigning is needed.
- `scripts/notarize.sh` notarizes and staples the `.app` itself, then optionally
  builds a DMG with `--dmg`. The stapled app is what gets zipped as the Sparkle
  enclosure — the zip must be created *after* stapling or the ticket is not
  inside it.
- No build earlier than 2.0.0 can update into 2.0.0: the bundle identifier
  changed, so Sparkle treats it as a different application. 1.x users install
  2.0.0 manually (a DMG is attached for that path) and move their database by
  hand — see the 2.0.0 release notes.
