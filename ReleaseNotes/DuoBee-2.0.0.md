# DuoBee 2.0.0

This release corrects the project's licensing and identity. It contains no
feature changes, but it is a breaking release: it cannot be installed as an
upgrade over any earlier version.

## License changed to AGPL-3.0-or-later

DuoBee is derived from [DuoBreak](https://github.com/JesseNaser/DuoBreak) by
Jesse Naser, which is licensed under the GNU Affero General Public License,
version 3 or later. Earlier DuoBee releases were incorrectly distributed under
an MIT license; from 2.0.0 the project is licensed **AGPL-3.0-or-later**, as
the upstream license requires. A source archive of the exact commit each
release is built from is attached to every release.

## Copyright attribution corrected

Releases 1.0.0–1.3.0 named "The Trustees of Princeton University" as the
copyright holder. That was incorrect: DuoBee is individually owned. The
copyright holder is now correctly stated as Michael Bino. See the `NOTICE`
file for the full record.

## Bundle identifier changed

The app's bundle identifier moved from an institutional namespace to
`io.bino.duobee`. As a consequence:

- **No earlier build will ever be offered this update automatically.** macOS
  and Sparkle treat 2.0.0 as a different application. Install it manually and
  delete your old copy.
- **Your database does not carry over automatically.** Either export your
  database from the old app (**Database → Export**) and import it in 2.0.0,
  or move the file by hand:

  ```
  from: ~/Library/Containers/edu.princeton.orfe.duobee/Data/Library/Application Support/DuoBee/duo.db
  to:   ~/Library/Containers/io.bino.duobee/Data/Library/Application Support/DuoBee/duo.db
  ```

  (Create the destination folder if 2.0.0 has not been launched yet, or launch
  it once first.)
- **Your saved database password does not carry over.** Keychain items are
  namespaced to the app; enter your database password once in 2.0.0 and it is
  saved again.

## New update feed and signing key

Updates are now published from the project's public repository and signed with
a new key. From 2.0.0 onward, updates are automatic again.
