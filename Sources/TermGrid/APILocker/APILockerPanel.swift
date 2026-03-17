import SwiftUI
import AppKit
import Combine

// MARK: - Auto-lock countdown timer view

struct AutoLockTimer: View {
    let vault: APIKeyVault

    @State private var remaining: TimeInterval = 0

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(formatted)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(remaining < 60 ? Theme.accent : Theme.notesSecondary)
            .onReceive(timer) { _ in
                remaining = vault.timeRemaining
            }
            .onAppear {
                remaining = vault.timeRemaining
            }
    }

    private var formatted: String {
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - PIN field with eye toggle

struct PINField: View {
    let placeholder: String
    @Binding var text: String
    @State private var isVisible = false

    var body: some View {
        HStack(spacing: 6) {
            if isVisible {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(Theme.headerText)
            } else {
                SecureField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(Theme.headerText)
            }

            Button {
                isVisible.toggle()
            } label: {
                Image(systemName: isVisible ? "eye.slash" : "eye")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.headerIcon)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Theme.cellBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Theme.cellBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Color swatch picker

private let presetColors = [
    "#10A37F", "#D4A574", "#635BFF", "#4285F4",
    "#FF9900", "#0078D4", "#8B5CF6", "#F6821F",
]

struct ColorSwatchRow: View {
    @Binding var selected: String

    var body: some View {
        HStack(spacing: 8) {
            ForEach(presetColors, id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: selected == hex ? 2 : 0)
                    )
                    .onTapGesture {
                        selected = hex
                    }
            }
        }
    }
}

// MARK: - Main panel

struct APILockerPanel: View {
    @Bindable var vault: APIKeyVault

    @State private var pin = ""
    @State private var confirmPIN = ""
    @State private var showAddForm = false

    // Add-key form fields
    @State private var newName = ""
    @State private var newKey = ""
    @State private var newEnvVar = ""
    @State private var newDocsURL = ""
    @State private var newAgentNotes = ""
    @State private var newColor = presetColors[0]

    var body: some View {
        VStack(spacing: 0) {
            switch vault.state {
            case .noVault:
                noVaultView
            case .locked:
                lockedView
            case .unlocked:
                unlockedView
            }
        }
        .frame(width: 320)
        .background(Theme.appBackground)
    }

    // MARK: - No Vault (Set PIN)

    private var noVaultView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "lock.rectangle.fill")
                .font(.system(size: 48))
                .foregroundColor(Theme.accent)

            Text("API Locker")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Theme.headerText)

            Text("Set a PIN to protect your keys")
                .font(.system(size: 12))
                .foregroundColor(Theme.notesSecondary)

            VStack(spacing: 10) {
                PINField(placeholder: "Enter PIN", text: $pin)
                PINField(placeholder: "Confirm PIN", text: $confirmPIN)
            }
            .padding(.horizontal, 24)

            Button {
                vault.errorMessage = nil
                guard !pin.isEmpty else {
                    vault.errorMessage = "PIN cannot be empty"
                    return
                }
                guard pin == confirmPIN else {
                    vault.errorMessage = "PINs do not match"
                    return
                }
                if vault.setPIN(pin) {
                    pin = ""
                    confirmPIN = ""
                }
            } label: {
                Text("Set PIN")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .padding(.horizontal, 24)

            if let error = vault.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .padding(.horizontal, 24)
            }

            Spacer()
        }
    }

    // MARK: - Locked

    private var lockedView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "lock.rectangle.fill")
                .font(.system(size: 48))
                .foregroundColor(Theme.accent)

            Text("API Locker")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Theme.headerText)

            Text("Enter PIN to unlock keys")
                .font(.system(size: 12))
                .foregroundColor(Theme.notesSecondary)

            PINField(placeholder: "PIN", text: $pin)
                .padding(.horizontal, 24)

            Button {
                vault.errorMessage = nil
                if vault.unlock(pin: pin) {
                    pin = ""
                }
            } label: {
                Text("Unlock")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .padding(.horizontal, 24)

            if let error = vault.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .padding(.horizontal, 24)
            }

            Spacer()
        }
    }

    // MARK: - Unlocked

    private var unlockedView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("API Locker")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.headerText)

                Spacer()

                AutoLockTimer(vault: vault)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.headerBackground)

            Divider().background(Theme.cellBorder)

            // Key list
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(vault.entries) { entry in
                        APIKeyCard(
                            entry: entry,
                            onCopy: {
                                if let key = vault.copyKey(id: entry.id) {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(key, forType: .string)
                                }
                            },
                            onReveal: {
                                vault.revealKey(id: entry.id)
                            },
                            onDelete: {
                                vault.removeKey(id: entry.id)
                            }
                        )
                    }
                }
                .padding(12)
            }

            Divider().background(Theme.cellBorder)

            // Add key toggle
            VStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAddForm.toggle()
                    }
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add API Key")
                    }
                    .foregroundColor(Theme.accent)
                    .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)

                if showAddForm {
                    addKeyForm
                }

                // Lock vault button
                Button {
                    vault.lock()
                    pin = ""
                } label: {
                    HStack {
                        Image(systemName: "lock.fill")
                        Text("Lock Vault")
                    }
                    .font(.system(size: 12))
                    .foregroundColor(Theme.notesSecondary)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 10)
            }
        }
    }

    // MARK: - Add key form

    private var addKeyForm: some View {
        VStack(spacing: 8) {
            TextField("Service name", text: $newName)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(8)
                .background(Theme.cellBackground)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.cellBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onChange(of: newName) { _, name in
                    newEnvVar = APIKeyEntry.suggestEnvVarName(from: name)
                    if let color = APIKeyEntry.suggestBrandColor(for: name) {
                        newColor = color
                    }
                }

            PINField(placeholder: "API key", text: $newKey)

            TextField("ENV_VAR_NAME", text: $newEnvVar)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(8)
                .background(Theme.cellBackground)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.cellBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            TextField("Docs URL (optional)", text: $newDocsURL)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(8)
                .background(Theme.cellBackground)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.cellBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            TextField("Agent notes (optional)", text: $newAgentNotes)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(8)
                .background(Theme.cellBackground)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.cellBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            ColorSwatchRow(selected: $newColor)
                .padding(.vertical, 4)

            HStack(spacing: 12) {
                Button("Cancel") {
                    resetAddForm()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(Theme.notesSecondary)

                Button {
                    vault.errorMessage = nil
                    guard !newName.isEmpty, !newKey.isEmpty, !newEnvVar.isEmpty else {
                        vault.errorMessage = "Name, key, and env var are required"
                        return
                    }
                    let success = vault.addKey(
                        name: newName,
                        key: newKey,
                        envVarName: newEnvVar,
                        brandColor: newColor,
                        docsURL: newDocsURL.isEmpty ? nil : newDocsURL,
                        agentNotes: newAgentNotes.isEmpty ? nil : newAgentNotes
                    )
                    if success {
                        resetAddForm()
                    }
                } label: {
                    Text("Add")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }

            if let error = vault.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func resetAddForm() {
        showAddForm = false
        newName = ""
        newKey = ""
        newEnvVar = ""
        newDocsURL = ""
        newAgentNotes = ""
        newColor = presetColors[0]
        vault.errorMessage = nil
    }
}
