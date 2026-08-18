#!/bin/zsh
# Cut a DuoBee release: build, notarize, sign the appcast, and publish.
#
# DuoBee's source repo is private, but Sparkle fetches the appcast and the
# update archive with no credentials. So artifacts are published to a separate
# PUBLIC repo (pubino/duobee-releases): GitHub Pages serves docs/appcast.xml and
# the release assets are downloaded from its GitHub Releases.
#
# Everything runs locally. The Sparkle EdDSA private key lives in the login
# Keychain and generate_appcast reads it implicitly — it is never exported, and
# there is deliberately no CI path that could ship a signed update.
#
# One-time setup:
#   1. Sparkle EdDSA key pair in the login Keychain:
#        build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
#      then paste the printed public key into DuoBee/Resources/Info.plist.
#   2. Notary credentials (profile name must match NOTARY_PROFILE below):
#        xcrun notarytool store-credentials notary \
#          --apple-id <id> --team-id <team>
#   3. gh auth login, with access to both duobee and duobee-releases.
#   4. The public releases repo exists, with docs/ published via
#      Settings -> Pages -> source: main /docs.
#
# Usage:
#   TEAM_ID=<team> ./scripts/release.sh
#   TEAM_ID=<team> ./scripts/release.sh --dry-run   # stop before publishing

set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="DuoBee"
RELEASES_REPO="${DUOBEE_RELEASES_REPO:-pubino/duobee-releases}"
NOTARY_PROFILE="${NOTARY_PROFILE:-notary}"
BUILD_DIR="build"
APP_PATH="$BUILD_DIR/export/$APP_NAME.app"
RELEASES_CLONE="$BUILD_DIR/releases-repo"
APPCAST_WORK="$BUILD_DIR/appcast-work"
DRY_RUN=false

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        -h|--help) sed -n '2,27p' "$0"; exit 0 ;;
        *) echo "error: unknown option '$arg'" >&2; exit 1 ;;
    esac
done

die() { echo "error: $*" >&2; exit 1 }

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
echo "==> Preflight"

[[ -n "${TEAM_ID:-}" ]] || die "TEAM_ID environment variable not set"

# Regenerate first: a stale pbxproj would silently build the wrong sources.
command -v xcodegen >/dev/null || die "xcodegen not found"
xcodegen generate >/dev/null

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" DuoBee/Resources/Info.plist)
BUILD_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" DuoBee/Resources/Info.plist)
TAG="v${VERSION}"
ZIP_NAME="${APP_NAME}-${VERSION}.zip"
ZIP_PATH="$BUILD_DIR/$ZIP_NAME"
NOTES_MD="ReleaseNotes/${APP_NAME}-${VERSION}.md"
NOTES_HTML="ReleaseNotes/${APP_NAME}-${VERSION}.html"

# Recorded in the published release body: the releases repo shares no history
# with source, so this is the only link back to what was built.
SOURCE_SHA=$(git rev-parse HEAD)
SOURCE_REPO=$(git config --get remote.origin.url \
    | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')

echo "    version ${VERSION} (build ${BUILD_VERSION}) -> ${TAG}"
echo "    source  ${SOURCE_REPO}@${SOURCE_SHA:0:12}"

[[ "$VERSION" == "$BUILD_VERSION" ]] || \
    die "CFBundleShortVersionString ($VERSION) != CFBundleVersion ($BUILD_VERSION)"

[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || \
    die "version '$VERSION' is not X.Y.Z"

[[ -z "$(git status --porcelain)" ]] || die "working tree is dirty; commit first"

if git rev-parse "$TAG" >/dev/null 2>&1; then
    die "tag $TAG already exists — bump the version in DuoBee/Resources/Info.plist"
fi

# Earlier releases used a bare '1.1.1' tag; keep the v-prefix consistent now.
LATEST_TAG=$(git tag --list 'v*' --sort=-v:refname | head -1)
if [[ -n "$LATEST_TAG" ]]; then
    NEWEST=$(printf '%s\n%s\n' "${LATEST_TAG#v}" "$VERSION" | sort -V | tail -1)
    [[ "$NEWEST" == "$VERSION" ]] || \
        die "version $VERSION is not newer than latest tag $LATEST_TAG"
fi

[[ -f "$NOTES_MD" ]]   || die "missing $NOTES_MD"
[[ -f "$NOTES_HTML" ]] || die "missing $NOTES_HTML"

security find-identity -v -p codesigning | grep -q "Developer ID Application" || \
    die "no Developer ID Application identity in the keychain"

gh auth status >/dev/null 2>&1 || die "gh is not authenticated (run: gh auth login)"
gh repo view "$RELEASES_REPO" >/dev/null 2>&1 || \
    die "cannot reach $RELEASES_REPO — create it (public) or check gh permissions"

# Resolve packages now so the Sparkle tools exist for the key check below,
# rather than discovering a key mismatch after a ten-minute notarization.
xcodebuild -resolvePackageDependencies \
    -project DuoBee.xcodeproj -scheme DuoBee \
    -derivedDataPath "$BUILD_DIR/DerivedData" >/dev/null 2>&1 || \
    die "failed to resolve Swift package dependencies"

SPARKLE_BIN="${SPARKLE_BIN:-$(find "$BUILD_DIR/DerivedData/SourcePackages/artifacts" -type d -name bin -path '*parkle*' 2>/dev/null | head -1)}"
[[ -x "${SPARKLE_BIN}/generate_appcast" ]] || \
    die "generate_appcast not found under '$SPARKLE_BIN' (set SPARKLE_BIN=)"

# generate_appcast signs with whatever private key is in THIS machine's login
# Keychain. If it does not match the SUPublicEDKey shipped in the app, every
# client rejects the update silently — no error surfaces until users report it.
KEYCHAIN_KEY=$("$SPARKLE_BIN/generate_keys" -p 2>/dev/null) || \
    die "no Sparkle signing key in this Mac's login Keychain.
       Either import the existing one:  $SPARKLE_BIN/generate_keys -f <key-file>
       or generate a new one:           $SPARKLE_BIN/generate_keys
       (a new key requires updating SUPublicEDKey in DuoBee/Resources/Info.plist)"

PLIST_KEY=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" DuoBee/Resources/Info.plist)
[[ "$PLIST_KEY" == "$KEYCHAIN_KEY" ]] || die "Sparkle key mismatch — updates signed here would be rejected.
       Info.plist SUPublicEDKey: $PLIST_KEY
       this Mac's Keychain key:  $KEYCHAIN_KEY
       Fix by importing the matching private key (generate_keys -f), or by
       setting SUPublicEDKey to this Mac's key if this is the release machine."

# The only gate that keeps a broken build from reaching users.
echo "==> Running tests"
./scripts/test.sh

# ---------------------------------------------------------------------------
# Build, notarize, staple
# ---------------------------------------------------------------------------
echo "==> Building and notarizing"
TEAM_ID="$TEAM_ID" NOTARY_PROFILE="$NOTARY_PROFILE" ./scripts/notarize.sh --dmg

# ---------------------------------------------------------------------------
# Verify the bundle before it is signed into an appcast users will trust
# ---------------------------------------------------------------------------
echo "==> Verifying bundle"
plist="$APP_PATH/Contents/Info.plist"

feed=$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$plist" 2>/dev/null) || \
    die "SUFeedURL missing from the built Info.plist"
[[ "$feed" == https://* ]] || die "SUFeedURL must be https, got '$feed'"

edkey=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$plist" 2>/dev/null) || \
    die "SUPublicEDKey missing from the built Info.plist"
[[ "$edkey" != "REPLACE_WITH_GENERATE_KEYS_OUTPUT" ]] || \
    die "SUPublicEDKey is still the placeholder — run generate_keys first"

/usr/libexec/PlistBuddy -c "Print :SUEnableInstallerLauncherService" "$plist" >/dev/null 2>&1 || \
    die "SUEnableInstallerLauncherService missing (required for the sandbox)"

# Setting this at all suppresses Sparkle's first-run consent prompt.
if /usr/libexec/PlistBuddy -c "Print :SUEnableAutomaticChecks" "$plist" >/dev/null 2>&1; then
    die "SUEnableAutomaticChecks must not be set (breaks the first-run prompt)"
fi

[[ -d "$APP_PATH/Contents/Frameworks/Sparkle.framework" ]] || \
    die "Sparkle.framework not embedded"
[[ -d "$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc" ]] || \
    die "Installer.xpc missing — sandboxed updates cannot install"

# An unsubstituted $(PRODUCT_BUNDLE_IDENTIFIER) here is the classic sandboxed
# Sparkle failure: it signs and notarizes fine, then updates die at install.
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist")
ents=$(codesign -d --entitlements - "$APP_PATH" 2>/dev/null)
for suffix in spks spki; do
    echo "$ents" | grep -q "${BUNDLE_ID}-${suffix}" || \
        die "entitlement mach-lookup ${BUNDLE_ID}-${suffix} missing or unsubstituted"
done

codesign --verify --deep --strict "$APP_PATH"
echo "    bundle OK"

# ---------------------------------------------------------------------------
# Package. Zip AFTER stapling, or the ticket is not inside the archive.
# ---------------------------------------------------------------------------
echo "==> Packaging $ZIP_NAME"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

# ---------------------------------------------------------------------------
# Appcast
# ---------------------------------------------------------------------------
echo "==> Generating appcast"
# SPARKLE_BIN and the key match were both established during preflight.

# Refresh the public repo clone. Reset rather than pull, so a half-finished
# previous run cannot leave stale edits that get committed with this release.
if [[ ! -d "$RELEASES_CLONE/.git" ]]; then
    rm -rf "$RELEASES_CLONE"
    gh repo clone "$RELEASES_REPO" "$RELEASES_CLONE" -- --quiet
fi
git -C "$RELEASES_CLONE" fetch --quiet origin
DEFAULT_BRANCH=$(git -C "$RELEASES_CLONE" remote show origin | sed -n 's/.*HEAD branch: //p')
[[ -n "$DEFAULT_BRANCH" ]] || die "cannot determine default branch of $RELEASES_REPO"
git -C "$RELEASES_CLONE" checkout --quiet "$DEFAULT_BRANCH"
git -C "$RELEASES_CLONE" reset --hard --quiet "origin/$DEFAULT_BRANCH"
# reset alone leaves untracked files, so a failed run's unpublished appcast
# would survive and be treated as the accumulator by the next one.
git -C "$RELEASES_CLONE" clean -fdq
mkdir -p "$RELEASES_CLONE/docs" "$RELEASES_CLONE/ReleaseNotes"

# generate_appcast reads every archive in the work dir, so it holds only this
# release. The existing docs/appcast.xml is the accumulator it appends to.
# The .html basename must match the zip for --embed-release-notes to attach it.
rm -rf "$APPCAST_WORK"
mkdir -p "$APPCAST_WORK"
cp "$ZIP_PATH" "$APPCAST_WORK/"
cp "$NOTES_HTML" "$APPCAST_WORK/${APP_NAME}-${VERSION}.html"

"$SPARKLE_BIN/generate_appcast" \
    --download-url-prefix "https://github.com/${RELEASES_REPO}/releases/download/${TAG}/" \
    --embed-release-notes \
    -o "$RELEASES_CLONE/docs/appcast.xml" \
    "$APPCAST_WORK"

grep -q "$ZIP_NAME" "$RELEASES_CLONE/docs/appcast.xml" || \
    die "appcast does not reference $ZIP_NAME"
grep -q 'sparkle:edSignature' "$RELEASES_CLONE/docs/appcast.xml" || \
    die "appcast has no EdDSA signature — is the private key in the login Keychain?"
echo "    appcast OK"

if [[ "$DRY_RUN" == true ]]; then
    echo ""
    echo "Dry run: stopping before publish."
    echo "  archive: $ZIP_PATH"
    echo "  appcast: $RELEASES_CLONE/docs/appcast.xml"
    exit 0
fi

# ---------------------------------------------------------------------------
# Publish. Order matters: the asset must exist before the feed advertises it,
# or Pages serves updaters a download URL that 404s.
# ---------------------------------------------------------------------------
echo "==> Publishing"

# Annotated with an explicit message: a bare `git tag` fails outright when
# tag.gpgsign is set, which it is on the release Mac.
git tag -a "$TAG" -m "${APP_NAME} ${VERSION}"
git push origin "$TAG"

DMG_PATH="$BUILD_DIR/${APP_NAME}-${VERSION}.dmg"
assets=("$ZIP_PATH")
[[ -f "$DMG_PATH" ]] && assets+=("$DMG_PATH")

# The tag created in the releases repo points at that repo's default branch, not
# at source — the two repos share no history. Stamp the source commit into the
# body so a published build can still be traced back to what produced it.
RELEASE_BODY="$BUILD_DIR/release-body-${VERSION}.md"
{
    cat "$NOTES_MD"
    echo ""
    echo "---"
    echo ""
    echo "Built from \`${SOURCE_REPO}\` at commit \`${SOURCE_SHA}\` (\`${TAG}\`)."
} > "$RELEASE_BODY"

gh release create "$TAG" "${assets[@]}" \
    --repo "$RELEASES_REPO" \
    --title "${APP_NAME} ${VERSION}" \
    --notes-file "$RELEASE_BODY"

cp "$NOTES_HTML" "$RELEASES_CLONE/ReleaseNotes/"

git -C "$RELEASES_CLONE" add docs/appcast.xml ReleaseNotes
git -C "$RELEASES_CLONE" commit -m "Publish appcast for ${VERSION}"
git -C "$RELEASES_CLONE" push origin HEAD

echo ""
echo "Released ${APP_NAME} ${VERSION}"
echo "  release: https://github.com/${RELEASES_REPO}/releases/tag/${TAG}"
echo "  appcast: $(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$plist")"
echo ""
echo "GitHub Pages takes a minute to redeploy. Verify with:"
echo "  curl -sI $(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$plist") | head -1"
