# DoppelBee 3.0.0

This release renames the application from **DuoBee** to **DoppelBee**. There
are no feature or security changes, but it is a breaking release: it cannot be
installed as an upgrade over any DuoBee version.

## Renamed to DoppelBee

The name "DuoBee" was close enough to the Duo product from Cisco Systems, Inc.
to invite the inference of an affiliation that has never existed. This project
is not affiliated with, endorsed by, or connected to Duo Security, Inc. or
Cisco Systems, Inc., and the new name puts distance between the two.

Nothing else changed with the name: the copyright holder, the derivation from
[DuoBreak](https://github.com/JesseNaser/DuoBreak), and the
AGPL-3.0-or-later license are all unaffected. See the `NOTICE` file for the
full record, including the former name.

The app still speaks the Duo authentication protocol and still refers to Duo
where it must in order to describe what it does — Duo keys, Duo Push, and so
on. Those references name the service the app authenticates against, not the
app itself.

## What changes for you

The bundle identifier moved from `io.bino.duobee` to `io.bino.doppelbee`, and
the update feed moved with the repository. As a consequence:

- **No DuoBee build will ever be offered this update automatically.** macOS
  and Sparkle treat DoppelBee 3.0.0 as a different application. Install it
  manually and delete your old copy.

- **The DuoBee update feed stops working.** The repository has been renamed, so
  `https://binoio.github.io/duobee/appcast.xml` no longer resolves. Installed
  copies of DuoBee 2.x will simply stop finding updates; they keep working
  otherwise.

- **Your database does not carry over automatically.** Either export it from
  DuoBee (**Database → Export**) and import it in DoppelBee, or move the file
  by hand:

  ```
  from: ~/Library/Containers/io.bino.duobee/Data/Library/Application Support/DuoBee/duo.db
  to:   ~/Library/Containers/io.bino.doppelbee/Data/Library/Application Support/DoppelBee/duo.db
  ```

  (Launch DoppelBee once first so the destination folder exists, or create it
  yourself.)

- **Your saved database password does not carry over.** Keychain items are
  namespaced to the app; enter your database password once in DoppelBee and it
  is saved again.

- **The verbose-logging default changed name.** If you had set it, use
  `defaults write io.bino.doppelbee duoVerboseLogging -bool YES`.

Once DoppelBee 3.0.0 is installed and your database is in place, updates are
automatic again.

## Uninstalling DuoBee

After you have confirmed your keys are present in DoppelBee, remove the old
app and its data:

```
rm -rf /Applications/DuoBee.app
rm -rf ~/Library/Containers/io.bino.duobee
```

The old keychain item is named `com.duobee.app`; delete it in Keychain Access
if you want it gone.
