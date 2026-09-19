//
//  ChangePasswordView.swift
//  DoppelBee
//
//  Created on 2026-01-04.
//  SPDX-License-Identifier: AGPL-3.0-or-later
//

import SwiftUI

struct ChangePasswordView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var databaseManager: DuoDatabaseManager
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("Change Database Password")
                .font(.title)
                .padding(.top)

            Divider()

            VStack(alignment: .leading, spacing: 15) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Old Password:")
                    SecureField("Enter old password", text: $oldPassword)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("New Password:")
                    SecureField("Enter new password", text: $newPassword)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Confirm New Password:")
                    SecureField("Confirm new password", text: $confirmPassword)
                        .textFieldStyle(.roundedBorder)
                }

                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            .padding()

            Spacer()

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Change Password") {
                    changePassword()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(oldPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 300)
    }

    private func changePassword() {
        errorMessage = nil

        if newPassword != confirmPassword {
            errorMessage = "New passwords do not match"
            return
        }

        if newPassword.isEmpty {
            errorMessage = "Password cannot be empty"
            return
        }

        Task {
            do {
                try await databaseManager.changePassword(oldPassword: oldPassword, newPassword: newPassword)
                await MainActor.run {
                    isPresented = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to change password: \(error.localizedDescription)"
                }
            }
        }
    }
}
