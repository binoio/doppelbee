//
//  AppVersion.swift
//  DuoBee
//
//  Created on 2026-08-07.
//  SPDX-License-Identifier: AGPL-3.0-or-later
//

import Foundation

/// Version shown in About and Help, read from the bundle so it tracks
/// CFBundleShortVersionString instead of being hardcoded and drifting.
enum AppVersion {
    static var short: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    static var displayString: String {
        "Version \(short)"
    }
}
