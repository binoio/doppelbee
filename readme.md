# DuoBee

DuoBee is a native macOS app that provides a macOS interface for managing your Duo Mobile authentication keys. It allows you to securely store and generate HOTP codes for Duo two-factor authentication without relying on your mobile device.

---

## ⚠️ Important Notice

DuoBee is free software; the AGPL places no restrictions on what you may use
it for. The warnings below are advisory — they describe legal and policy
exposure you take on, not conditions of the license:

- DuoBee is **NOT affiliated with Duo Security, Inc. or Cisco Systems, Inc.**
- Using it may violate Duo's Terms of Service or your organization's security policies
- Using it against systems you do not own or lack authorization to test may be illegal
- You are solely responsible for compliance with applicable laws and policies

It was built for personal backup of your own keys, academic research, and
authorized security testing — not for unauthorized access, bypassing security
controls, or policy violations.

---

## Quick Start

Download the latest release from [the Releases page](https://github.com/binoio/duobee/releases).

DuoBee updates itself: it checks for new versions on a schedule and via
**DuoBee → Check for Updates…**, with the behavior configurable under
Settings → Updates.

> **Upgrading from 1.x:** version 2.0.0 changed the app's bundle identifier,
> so it is a fresh install, not an upgrade — no earlier build will ever be
> offered 2.0.0 automatically. Install 2.0.0 manually, then move your database
> if you had one; see the 2.0.0 release notes for the exact steps. Saved
> keychain passwords do not carry over; re-enter your database password once.

## Features

- **HOTP Code Generation**: Generate time-based one-time passwords for Duo authentication
- **Duo Activation**: Add keys directly via Duo activation URLs
- **Duo Push**: Approve or deny push requests, with optional auto-confirm for standard pushes
- **Verified Duo Push**: Prompts for the verification code shown on the device you are logging in from; never auto-confirmed
- **AES-GCM Encryption**: Military-grade encryption for your authentication database
- **Keychain Integration**: Secure password storage using macOS Keychain
- **Auto-unlock**: Optionally unlock database automatically on launch
- **Database Management**: Import, export, change password, and lock database
- **Portable**: Database files can be backed up and restored

## Installation

### Building from Source

**Requirements:**
- macOS 14.0 (Sonoma) or later
- Xcode 15.0 or later
- Swift 5.9 or later

**Build and run:**

```bash
# Clone the repository
git clone https://github.com/binoio/duobee.git
cd duobee

# Build the app
./scripts/build.sh

# Run the app
./scripts/run.sh
```

**Build options:**
```bash
./scripts/build.sh          # Normal build
./scripts/build.sh --clean  # Clean build

./scripts/run.sh            # Run existing build
./scripts/run.sh --build    # Build then run
./scripts/run.sh --clean    # Clean build then run
./scripts/run.sh --kill     # Kill app, clean build, then run
```

### Running Tests

```bash
./scripts/test.sh
```

The test suite includes 80 unit tests covering encryption, HOTP generation, key management, keychain integration, and updater configuration.

## Usage

### First Launch

1. **Create Database**: On first launch, create a new encrypted database with a secure password
2. **Add Keys**: Add Duo keys via activation URL or QR code
3. **Generate Codes**: Click the refresh icon to generate HOTP codes for authentication

### Settings

Access Settings via **⌘,** or **DuoBee menu → Settings**:

- **Launch at Login**: Start DuoBee automatically when you log in
- **Auto-unlock Database on Launch**: Automatically unlock using saved keychain password
- **Database Location**: View and reveal your database file in Finder
- **Change Password**: Update database encryption password
- **Delete All Keys**: Remove all stored keys
- **Delete Database**: Completely remove the database

### Keyboard Shortcuts

- **⌘K**: Add New Key
- **⌘⇧I**: Import Database
- **⌘⇧E**: Export Database
- **⌘⇧L**: Lock Database
- **⌘,**: Settings
- **⌘?**: Help

## Security

- **Database Encryption**: AES-256-GCM encryption with password-based key derivation
- **Keychain Storage**: Database password securely stored in macOS Keychain
- **HOTP Generation**: Standards-compliant HMAC-SHA1 implementation using CryptoKit
- **Database Location**: `~/Library/Application Support/DuoBee/duo.db`

### Verified Duo Push

Verified Duo Push exists to defeat MFA-fatigue and prompt-bombing attacks: it requires you to read a short code off the device you are logging in from and type it into the authenticator. DuoBee preserves that property.

- Verification codes are **never** auto-confirmed, regardless of the "Auto-confirm Standard Pushes" setting or a key's per-key auto-confirm toggle. Auto-confirm applies to standard pushes only.
- Codes are never guessed, prefilled, or derived — DuoBee has no access to the access device's screen, and approval requires you to enter the code by hand.
- Codes are validated locally for length and digits, then sent as part of the signed approval request. They are redacted from log output.

**Entering the code.** You can respond without leaving whatever you are doing: click **Enter Code** on the notification, type the digits, then **Approve**. If your notification style is set to Banners, hover the banner to reveal the buttons; Alerts style always shows them. The push also appears in the DuoBee window with a code field, if you would rather answer there.

Each request shows the integration being logged into along with the username, IP address, and location behind it. Check these before approving — they are what distinguish your own login from one an attacker triggered.

**Important Security Notes:**
- Always use a strong, unique password for your database
- Database files are only secure when encrypted with a strong password
- The keychain password provides convenience but relies on your Mac's security
- Store backup copies in secure locations

## Activation

To add a Duo key:

1. Go to your Duo enrollment page and select "Add a new device"
2. Choose "Tablet" → "Android"
3. Click "I have Duo Mobile installed"
4. Copy the activation URL (format: `https://m-xxx.duosecurity.com/activate/xxx`)
5. In DuoBee, click "Add New Key" (⌘K)
6. Paste the activation URL
7. Optionally provide a custom name
8. Click "Activate"


## Project Structure

```
DuoBee/
├── DuoBee/
│   ├── Sources/
│   │   ├── DuoBeeApp.swift      # App entry point
│   │   ├── UpdaterViewModel.swift # Sparkle updater UI bindings
│   │   ├── Models/              # Data models and database manager
│   │   ├── Services/            # Crypto, keychain, HOTP, Duo API
│   │   └── Views/               # SwiftUI views
│   ├── Resources/               # Info.plist, entitlements
│   └── Tests/                   # Unit tests
├── ReleaseNotes/                # Per-version notes (.md and .html)
├── scripts/
│   ├── build.sh                 # Build the app
│   ├── test.sh                  # Run test suite
│   ├── run.sh                   # Launch the app
│   ├── notarize.sh              # Build, sign, notarize, staple
│   └── release.sh               # Cut and publish a release
├── project.yml                  # XcodeGen project configuration
├── RELEASING.md                 # Release runbook and one-time setup
└── README.md                    # This file
```

## Releasing

See [RELEASING.md](RELEASING.md). Releases are cut locally — there is no CI that
builds or publishes. Source, releases, and the Sparkle update feed all live in
this public repository; every release also carries a source archive of the
exact commit it was built from, as the AGPL requires.

## Credits

DuoBee is inspired by and based on the protocol implementation from [DuoBreak](https://github.com/JesseNaser/DuoBreak) by Jesse Naser.

**Original Work:**
- [DuoBreak](https://github.com/JesseNaser/DuoBreak) - Python CLI tool by Jesse Naser
- Duo activation protocol reverse engineering and HOTP implementation

**DuoBee Implementation:**
- Native macOS Swift reimplementation using Apple frameworks
- SwiftUI interface and macOS-specific features
- CryptoKit-based encryption and HOTP generation

DuoBee reimplements the Duo activation protocol and HOTP generation from the original DuoBreak Python tool using Apple's native frameworks (CryptoKit, Security, SwiftUI) for a native macOS experience.

## License

Copyright (c) 2026 Michael Bino

DuoBee is licensed under the **GNU Affero General Public License, version 3 or
(at your option) any later version** (AGPL-3.0-or-later). See
[LICENSE.md](LICENSE.md) for the full text and [NOTICE](NOTICE) for the
derivation and attribution record.

DuoBee is a modified work derived from
[DuoBreak](https://github.com/JesseNaser/DuoBreak), Copyright (C) 2023 Jesse
Naser, also licensed AGPL-3.0-or-later.

Releases 1.0.0–1.3.0 were distributed under an MIT license with an incorrect
copyright holder; both were corrected in 2.0.0. See [NOTICE](NOTICE).

## Disclaimer

DuoBee was developed by studying the Duo Mobile authentication protocol (via
DuoBreak's reverse engineering). It was built for personal backup of your own
authentication keys, academic research into authentication protocols, and
security testing with proper authorization.

**Important warnings** (advisory — not license conditions):

- This project is **NOT affiliated with, endorsed by, or sponsored by** Duo Security, Inc. or Cisco Systems, Inc.
- Use of this software may **violate Duo's Terms of Service** or your organization's security policies
- Unauthorized access to computer systems is **illegal** under applicable laws including the Computer Fraud and Abuse Act (CFAA)
- You are **solely responsible** for ensuring lawful and ethical use
- The software comes with **no warranty**, and the copyright holders assume **no liability** for misuse, as stated in the license
