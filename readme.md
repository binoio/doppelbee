# DuoBee

DuoBee is a native macOS app that provides a macOS interface for managing your Duo Mobile authentication keys. It allows you to securely store and generate HOTP codes for Duo two-factor authentication without relying on your mobile device.

---

## ⚠️ Important Notice

**This software is for educational and research purposes only.**

- **NOT affiliated with Duo Security, Inc. or Cisco Systems, Inc.**
- Use may violate Duo's Terms of Service or your organization's security policies
- Only use with systems you own or have explicit authorization to test
- Users are solely responsible for compliance with applicable laws and policies

**Intended for:** Personal backup of your own keys, academic research, authorized security testing
**Not intended for:** Unauthorized access, bypassing security controls, policy violations

---

## Quick Start

Download the latest release from [the Releases page](https://github.com/pubino/duobee-releases/releases).

From 1.3.0 onward DuoBee updates itself: it checks for new versions on a
schedule and via **DuoBee → Check for Updates…**, with the behavior configurable
under Settings → Updates.

> **Upgrading from 1.2.1 or earlier:** those builds predate the updater and
> cannot upgrade themselves. Download 1.3.0 manually once; updates are automatic
> after that. Your database and keychain entries are untouched by the upgrade.

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
git clone https://github.com/YOUR_USERNAME/DuoBee.git
cd DuoBee

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

The test suite includes 30+ unit tests covering encryption, HOTP generation, key management, and keychain integration.

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
builds or publishes. Update artifacts go to the public
[pubino/duobee-releases](https://github.com/pubino/duobee-releases) repository,
because Sparkle fetches the feed and the archive without credentials and this
repository is private.

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

Copyright (c) 2026 The Trustees of Princeton University

This project is licensed under the MIT License. See the [LICENSE.md](LICENSE.md) file for complete terms and important disclaimers.

## Disclaimer

**Educational and Research Use Only**

This software was developed through reverse engineering of the Duo Mobile authentication protocol for educational and research purposes. It is intended solely for:

- Personal backup of authentication keys you own
- Academic research into authentication protocols
- Security research with proper authorization
- Testing authentication systems you control

**Important Warnings:**

- This project is **NOT affiliated with, endorsed by, or sponsored by** Duo Security, Inc. or Cisco Systems, Inc.
- Use of this software may **violate Duo's Terms of Service** or your organization's security policies
- Unauthorized access to computer systems is **illegal** under applicable laws including the Computer Fraud and Abuse Act (CFAA)
- Users are **solely responsible** for ensuring lawful and ethical use
- The copyright holders assume **no liability** for misuse of this software

**By using this software, you acknowledge these warnings and agree to use it only for lawful and ethical purposes in compliance with all applicable terms of service, policies, and regulations.**
