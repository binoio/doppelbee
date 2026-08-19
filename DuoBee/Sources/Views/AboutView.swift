//
//  AboutView.swift
//  DuoBee
//
//  Created on 2026-02-14.
//  SPDX-License-Identifier: AGPL-3.0-or-later
//

import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            // App Icon
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)

            // App Name
            Text("DuoBee")
                .font(.largeTitle)
                .fontWeight(.bold)

            // Version
            Text(AppVersion.displayString)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Divider()
                .frame(width: 200)

            // Description
            Text("A native macOS Duo Mobile authenticator")
                .font(.body)
                .multilineTextAlignment(.center)

            // Appropriate Legal Notices (AGPL §5(d)): copyright, license,
            // warranty disclaimer, and where to obtain source.
            VStack(spacing: 4) {
                Text("Copyright © 2026 Michael Bino")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Based on DuoBreak by Jesse Naser")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Licensed under the GNU AGPL v3 or later. This is free software: you may change and redistribute it under the terms of that license. It comes with ABSOLUTELY NO WARRANTY.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Link("Source Code", destination: URL(string: "https://github.com/binoio/duobee")!)
                        .font(.caption)
                    Link("License", destination: URL(string: "https://www.gnu.org/licenses/agpl-3.0.html")!)
                        .font(.caption)
                }
                .padding(.top, 4)
            }
            .padding(.top, 8)

            Spacer()

            // Close button
            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(24)
        .frame(width: 320, height: 440)
    }
}
