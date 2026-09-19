import SwiftUI
import TapeCore

/// Search field with an attached suggestions list. Curated matches appear as you type;
/// Twelve Data results (one credit per settled query) merge in after a short pause.
@MainActor
struct SearchBar: View {
    @Environment(AppModel.self) private var model
    var focused: FocusState<Bool>.Binding

    private var rawCandidate: String { SymbolSearch.rawSymbol(model.searchText) }

    /// Zero results after the network search settled: offer to track the typed symbol
    /// as-is instead of a dead end (Kimi review U9).
    private var offerRaw: Bool {
        !rawCandidate.isEmpty && model.searchResults.isEmpty && !model.searchLoading && !model.symbols.contains(rawCandidate)
    }

    private var showDropdown: Bool {
        focused.wrappedValue && (!model.searchResults.isEmpty || model.searchLoading || model.searchNote != nil || offerRaw)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.dim)
                    TextField("Search a ticker or name, e.g. gold", text: Binding(
                        get: { model.searchText },
                        set: { model.updateSearch($0) }
                    ))
                    .font(Theme.mono(14))
                    .foregroundStyle(Theme.text)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused(focused)
                    .onSubmit(commit)
                    .accessibilityLabel("Search a ticker or name")
                    if !model.searchText.isEmpty {
                        Button { model.updateSearch("") } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.dim)
                        }
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(focused.wrappedValue ? Theme.text.opacity(0.6) : Theme.border, lineWidth: 1))

                Button("Add", action: commit)
                    .font(Theme.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(height: 44)
                    .padding(.horizontal, 16)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                    .disabled(model.searchText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if showDropdown {
                VStack(spacing: 0) {
                    ForEach(model.searchResults) { r in
                        Button {
                            model.add(r)
                            focused.wrappedValue = false
                        } label: {
                            HStack(spacing: 10) {
                                Text(r.symbol).font(Theme.mono(14, weight: .semibold)).foregroundStyle(Theme.text)
                                    .frame(width: 92, alignment: .leading).lineLimit(1)
                                Text(r.name).font(Theme.sans(13)).foregroundStyle(Theme.muted).lineLimit(1)
                                Spacer(minLength: 6)
                                TypeBadge(type: r.type)
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 48)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(r.symbol), \(r.name), \(r.type.rawValue)")
                        Divider().overlay(Theme.line)
                    }
                    if offerRaw {
                        Button {
                            model.addRaw(rawCandidate)
                            focused.wrappedValue = false
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus.circle").foregroundStyle(Theme.muted)
                                Text("Track \"\(rawCandidate)\" anyway").font(Theme.sans(13)).foregroundStyle(Theme.text)
                                Spacer(minLength: 6)
                                Text("unverified").font(Theme.mono(10, weight: .medium)).tracking(0.8).foregroundStyle(Theme.dim)
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 48)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Track \(rawCandidate) anyway, unverified")
                        Divider().overlay(Theme.line)
                    }
                    if model.searchLoading || model.searchNote != nil {
                        Text(model.searchNote ?? "Searching Twelve Data…")
                            .font(Theme.sans(12)).foregroundStyle(Theme.dim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14).frame(minHeight: 40)
                    }
                }
                .background(Color(red: 0x16 / 255, green: 0x1d / 255, blue: 0x27 / 255), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
                .padding(.top, 6)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: model.searchResults.count)
    }

    private func commit() {
        if let first = model.searchResults.first { model.add(first) } else { model.addRaw(model.searchText) }
        focused.wrappedValue = false
    }
}
