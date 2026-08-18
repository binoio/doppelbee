# DuoBee 1.3.0

## Automatic updates

DuoBee now updates itself using [Sparkle](https://sparkle-project.org). New
versions are signed with an EdDSA key and verified before installation, so an
update is only applied if it genuinely came from us.

- **DuoBee → Check for Updates…** checks on demand.
- **Settings → Updates** controls whether DuoBee checks automatically and
  whether it downloads updates in the background.
- The first time DuoBee launches it asks once whether to check automatically.
  Nothing is sent anywhere until you answer.

DuoBee stays sandboxed. Updates install through Sparkle's sandboxed installer
service rather than by relaxing the app's protections.

## Upgrading from 1.2.1 or earlier

Earlier builds have no updater and cannot upgrade themselves, so this one must
be installed manually — download it below and replace your existing copy.
Updates are automatic from here on.

Your database, keychain entries, and settings are unaffected.
