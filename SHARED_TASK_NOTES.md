# DuoBee Development Notes

**DuoBee** is a native macOS application for managing Duo authentication keys, inspired by the original [DuoBreak](https://github.com/JesseNaser/DuoBreak) Python CLI tool.

## Project Status: All Features Complete & Working ✅

All primary features have been successfully implemented and tested:
1. ✅ Native macOS SwiftUI interface
2. ✅ Full Duo activation protocol (RSA keys + iOS device emulation)
3. ✅ AES-GCM encrypted database with keychain integration
4. ✅ Auto-unlock database on launch setting
5. ✅ Database management (import/export with security-scoped resources)
6. ✅ Settings as standalone window
7. ✅ Help system with keyboard shortcuts
8. ✅ Clean build scripts with multiple options
9. ✅ **HOTP code generation (FIXED - base32 encoding)**
10. ✅ Click-to-copy HOTP codes with visual feedback
11. ✅ Selectable table rows with Command+Delete support
12. ✅ **Duo Push notifications (FIXED - RSA SHA-512 auth)**
13. ✅ Auto-confirm all pushes (global setting)
14. ✅ Per-key auto-confirm push setting

## Quick Start

```bash
./scripts/build.sh           # Normal build
./scripts/build.sh --clean   # Clean build
./scripts/test.sh            # Run 40 unit tests (all passing)
./scripts/run.sh             # Launch app
./scripts/run.sh --kill      # Kill, clean build, and launch
```

## Project Changes from Original DuoBreak

**Removed:**
- Python CLI tool (duobreak.py)
- Python dependencies (requirements.txt)
- Python-specific .gitignore entries

**Added:**
- Native Swift/SwiftUI macOS app
- Xcode project with XcodeGen
- Build and test scripts
- macOS-specific features (Keychain, Settings window, etc.)

**Credits:**
- Original DuoBreak protocol implementation by Jesse Naser
- DuoBee is a native macOS reimplementation using Apple frameworks

## Key Technical Details

- **Database**: AES-GCM encrypted JSON in `~/Library/Application Support/DuoBee/duo.db`
- **HOTP**: CryptoKit HMAC-SHA1 with base32-encoded secrets (matches Python implementation)
- **Keychain**: Password stored in macOS Keychain, auto-unlock optional
- **Activation**: Full iOS Duo Mobile device emulation (v4.73.0.873.1)
- **RSA Keys**: 2048-bit keys in PEM format for Duo Push support
- **Push Auth**: RSA SHA-512 signatures with RFC 2822 timestamps (matches Python)
- **Import/Export**: Security-scoped resources for file access permissions
- **Settings**: Native macOS Settings window (⌘,)

## Architecture

```
DuoBee/Sources/
├── DuoBeeApp.swift          # App entry, menu commands
├── Models/
│   ├── DuoKey.swift         # Key model with RSA support
│   ├── DuoDatabase.swift    # Database model
│   └── DuoDatabaseManager.swift  # Database operations
├── Services/
│   ├── CryptoService.swift      # AES-GCM encryption
│   ├── HOTPGenerator.swift      # HOTP code generation
│   ├── KeychainService.swift    # Keychain integration
│   ├── DuoAPIService.swift      # Duo activation & push API
│   └── DuoPushService.swift     # Push notification polling & management
└── Views/
    ├── ContentView.swift        # Main UI
    ├── SettingsView.swift       # Settings window
    ├── HelpView.swift           # Help window
    └── ChangePasswordView.swift # Password change
```

## Key Features

**HOTP Code Generation:**
- Click HOTP codes to copy to clipboard
- Visual feedback when copied (green background)
- Auto-incrementing counter

**Duo Push:**
- 5-second polling for incoming push requests
- Visual notifications in-app with approve/deny buttons
- Global auto-confirm setting in Settings
- Per-key auto-confirm toggle (accessible via key context menu)
- RSA SHA-512 signature-based authentication (matches Python implementation)
- Proper message signing: time + method + host + path + params

**UI/UX:**
- Selectable table rows
- Command+Delete to delete selected key
- Context menu per key (Rename, Settings, Delete)
- Settings window with Duo Push section

## Critical Fixes Applied

### HOTP Code Generation Fix (2026-01-05)
**Problem**: Generated HOTP codes were failing authentication with "Incorrect passcode" error.

**Root Cause**: The Duo API returns a plain ASCII `hotp_secret` that must be base32-encoded before storage. The Swift implementation was incorrectly trying to decode it as if it were already base32-encoded, resulting in wrong key bytes and completely invalid codes.

**Solution**:
- Added `base32Encode()` function to DuoAPIService
- Encode `hotp_secret` to base32 when storing in ActivationResult
- HOTP codes now match Python implementation and authenticate successfully

### Duo Push Authentication Fix (2026-01-05)
**Problem**: Duo server rejected push requests with "device cannot currently receive notification" error.

**Root Cause**: The Python implementation uses RSA SHA-512 signature-based authentication, not simple Basic Auth with `pkey:akey`. The authentication header format is: `Basic base64(pkey + ":" + base64(RSA_SHA512_signature))`

**Solution**:
- Implemented `rfc2822Date()` for proper timestamp formatting
- Implemented `generateSignature()` to create signature message: `time + "\n" + method + "\n" + host + "\n" + path + "\n" + params`
- Implemented `signWithRSA()` using SecKey with SHA-512
- Updated both `checkForPushRequests()` and `respondToPush()` to use RSA-signed auth
- Added 9 new unit tests covering RSA signing, date formatting, and signature generation
- All 40 tests now passing

**Result**: Duo Push notifications now work correctly and can receive/respond to push requests.

### Push Response Transaction ID Fix (2026-02-14)
**Problem**: Clicking Approve or Deny on push notifications returned HTTP 404 "Unknown transaction" error from Duo servers.

**Root Cause**: The Duo API uses `urgid` (not `txid`) as the field name for transaction identifiers in push notification responses. The Swift implementation was parsing `txid` which doesn't exist in the API response, causing the server to reject the response with "Unknown transaction".

**Solution**:
- Changed `PushTransaction.txid` to `PushTransaction.urgid`
- Updated JSON parsing to look for `urgid` field
- Updated `respondToPush()` parameter from `txid` to `urgid`
- Updated all references in DuoPushService, ContentView, and tests
- Added required HTTP headers: `host` and `txId` (which receives the urgid value)

**Reference**: Verified against [DuoBreak](https://github.com/JesseNaser/DuoBreak) and [synackDUO](https://github.com/dinosn/synackDUO) Python implementations which both use `tx["urgid"]` for transaction identification.

**Result**: Push notification approve/deny should now correctly communicate with Duo servers.

### Database Initialization Refactoring (2026-01-07)
**Problem**: When the database file was deleted externally, the app could get stuck showing "Unlock Database" prompt instead of "Create Database" prompt, especially when auto-unlock was enabled with an orphaned keychain entry.

**Improvements Made**:
1. **State Management**:
   - Reset all state flags (`showPasswordPrompt`, `showCreateDatabasePrompt`, `errorMessage`) at the start of `checkAndLoadDatabase()`
   - Properly clean up orphaned keychain entries when database is missing
   - Added comprehensive state updates in all database operations

2. **Missing Database Handling**:
   - `checkAndLoadDatabase()` now immediately detects missing database and shows create prompt
   - `loadDatabase()` re-checks if database still exists (handles race conditions)
   - `createDatabase()` cleans up any orphaned keychain entries before creating new database
   - `deleteDatabase()` properly resets all state flags

3. **Error Recovery**:
   - Added `handleDatabaseLoadError()` for better error messaging
   - Distinguish between decryption failures and file-not-found errors
   - Added `recheckDatabaseState()` for manual state recovery

4. **UnlockDatabaseView**:
   - Added specific handling for `DatabaseError.fileNotFound`
   - Gracefully transitions to create prompt when database disappears

**Result**: The app now robustly handles missing databases, corrupted files, and state recovery scenarios. Users will always see the appropriate prompt (create vs unlock) regardless of cached settings or keychain state.

## Remaining Optional Enhancements

- About window (placeholder exists)
- Full Launch at Login via SMAppService (preference stored but not active)
- Custom app icon
- Mac App Store distribution
