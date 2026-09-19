import SwiftUI
import TapeCore

@MainActor
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""
    @State private var confirmClear = false
    @FocusState private var keyFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        keySection
                        Divider().overlay(Theme.line).padding(.vertical, 6)
                        displaySection
                        Divider().overlay(Theme.line).padding(.vertical, 6)
                        Text("Data by Twelve Data. Prices can be delayed; nothing here is investment advice.")
                            .font(Theme.sans(12)).foregroundStyle(Theme.dim)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .confirmationDialog("Remove the key from this device?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear key", role: .destructive) { model.clearKey(); draft = "" }
                Button("Keep it", role: .cancel) {}
            } message: {
                Text("Prices stop refreshing until a key is added again. Your list stays.")
            }
            .onAppear {
                draft = model.apiKey
                if model.apiKey.isEmpty { keyFocused = true }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var keySection: some View {
        Text("Connect price data")
            .font(Theme.sans(20, weight: .semibold)).foregroundStyle(Theme.text)
        Text("Tape pulls prices from Twelve Data. Grab a free key at twelvedata.com/pricing (Basic plan: 8 calls a minute, 800 a day) and paste it here. The key is checked with one call before it is saved.")
            .font(Theme.sans(14)).foregroundStyle(Theme.muted)
        Link("Open twelvedata.com/pricing", destination: URL(string: "https://twelvedata.com/pricing")!)
            .font(Theme.sans(14, weight: .medium)).foregroundStyle(Theme.text)

        Text("API KEY").font(Theme.mono(11, weight: .medium)).tracking(0.8).foregroundStyle(Theme.muted)
        HStack(spacing: 8) {
            SecureField("paste your key", text: $draft)
                .font(Theme.mono(14))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.password)
                .focused($keyFocused)
                .submitLabel(.go)
                .onSubmit(save)
                .disabled(model.keyValidating)
            if model.keyValidating { ProgressView().tint(Theme.muted) }
        }
        .padding(.horizontal, 12).frame(height: 44)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(model.keyMessage == nil ? Theme.border : Theme.red.opacity(0.7), lineWidth: 1))

        if let message = model.keyMessage {
            Text(message).font(Theme.sans(13)).foregroundStyle(Theme.red)
                .accessibilityAddTraits(.updatesFrequently)
        }

        Text("Used today (estimated): \(model.creditsUsedToday) of 800 credits · resets 00:00 UTC · 40 reserved for your own taps.")
            .font(Theme.sans(12)).foregroundStyle(Theme.muted)
        Text("The key is kept in this device's Keychain, sent only to api.twelvedata.com, and only as a request header, never in a URL.")
            .font(Theme.sans(12)).foregroundStyle(Theme.muted)
        keyButtons
    }

    private var keyButtons: some View {
        HStack(spacing: 8) {
            Button(action: save) {
                Text(model.keyValidating ? "Checking…" : "Save and connect")
                    .font(Theme.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.bg)
                    .frame(height: 44).padding(.horizontal, 18)
                    .background(Theme.text, in: RoundedRectangle(cornerRadius: 10))
            }
            .disabled(model.keyValidating)
            Button(model.apiKey.isEmpty ? "Not now" : "Cancel") { dismiss() }
                .font(Theme.sans(15, weight: .semibold)).foregroundStyle(Theme.text)
                .frame(height: 44).padding(.horizontal, 18)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
            if !model.apiKey.isEmpty {
                Button(role: .destructive) { confirmClear = true } label: {
                    Text("Clear key").font(Theme.sans(15, weight: .semibold)).foregroundStyle(Theme.red)
                        .frame(height: 44).padding(.horizontal, 18)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                }
            }
        }
        .padding(.top, 4)
    }

    /// Red-up or green-up (Kimi review U3). Colour is never the only cue: see `ChangeText`.
    @ViewBuilder
    private var displaySection: some View {
        Text("DISPLAY").font(Theme.mono(11, weight: .medium)).tracking(0.8).foregroundStyle(Theme.muted)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(UpColorConvention.allCases) { c in
                Button { model.setUpColor(c) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: model.upColor == c ? "checkmark.circle.fill" : "circle").foregroundStyle(model.upColor == c ? Theme.text : Theme.dim)
                        Text(c.label).font(Theme.sans(14)).foregroundStyle(Theme.text)
                        Spacer()
                        HStack(spacing: 6) {
                            Text("▲").foregroundStyle(Theme.up(c))
                            Text("▼").foregroundStyle(Theme.down(c))
                        }.font(Theme.mono(13))
                    }
                    .padding(10)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(model.upColor == c ? Theme.text.opacity(0.5) : Theme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.upColor == c ? [.isSelected] : [])
            }
        }
        Text("Changes also carry a ▲ or ▼ and a sign, so colour is never the only cue. Tape is dark-only in this version.")
            .font(Theme.sans(12)).foregroundStyle(Theme.muted)
    }

    private func save() {
        model.saveKey(draft)
    }
}
