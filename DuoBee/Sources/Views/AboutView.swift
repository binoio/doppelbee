//
//  AboutView.swift
//  DuoBee
//
//  Created on 2026-02-14.
//  SPDX-License-Identifier: MIT
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

            // Credits
            VStack(spacing: 4) {
                Text("Based on DuoBreak by Jesse Naser")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("MIT License")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
        .frame(width: 300, height: 340)
    }
}
