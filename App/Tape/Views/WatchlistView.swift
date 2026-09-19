import SwiftUI
import TapeCore

@MainActor
struct WatchlistView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var searchFocused: Bool

    /// Curated names offered on an empty tape so the first screen shows the product, not a
    /// form (Kimi review U1). No prices are invented; each chip is a real add.
    private let starters = ["SPY", "QQQ", "AAPL", "NVDA", "BTC/USD", "XAU/USD"]

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                if model.apiKey.isEmpty { noKeyBanner }
                SearchBar(focused: $searchFocused)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .zIndex(2)
                list
            }
            if let toast = model.toast {
                ToastView(text: toast, undo: model.toastUndo ? { model.undoRemove() } : nil)
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.toast != nil)
        .navigationTitle("Tape")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 10) {
                    StatusChip()
                    Button { model.showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(Theme.text)
                    }
                    .accessibilityLabel("Settings and API key")
                }
            }
        }
        .toolbarBackground(Theme.bg, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(for: String.self) { symbol in
            DetailView(symbol: symbol)
        }
    }

    /// Shown instead of a modal wall when there is no key (Kimi review U1 / U2).
    private var noKeyBanner: some View {
        Button { model.showSettings = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "key.horizontal").foregroundStyle(Theme.warn)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No data key yet").font(Theme.sans(13, weight: .semibold)).foregroundStyle(Theme.text)
                    Text("Add a free Twelve Data key to load prices. Browsing and search work without one.")
                        .font(Theme.sans(12)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.dim)
            }
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.warn.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .accessibilityLabel("No data key yet. Open settings to add one.")
    }

    @ViewBuilder
    private var list: some View {
        if model.symbols.isEmpty {
            emptyState
        } else {
            List {
                ForEach(model.symbols, id: \.self) { symbol in
                    NavigationLink(value: symbol) {
                        InstrumentRow(symbol: symbol)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparatorTint(Theme.line)
                    .listRowBackground(rowBackground(symbol))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { model.remove(symbol) } label: { Label("Remove", systemImage: "trash") }
                    }
                    .swipeActions(edge: .leading) {
                        if model.isQuarantined(symbol) {
                            Button { model.resume(symbol) } label: { Label("Resume", systemImage: "arrow.clockwise") }.tint(Theme.warn)
                        }
                    }
                    .contextMenu {
                        if model.isQuarantined(symbol) { Button("Resume lookups") { model.resume(symbol) } }
                        Button("Remove \(symbol)", role: .destructive) { model.remove(symbol) }
                    }
                }
                Text(model.footerText)
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.dim)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .padding(.vertical, 4)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .refreshable { await model.refresh() }
            .animation(.easeOut(duration: 0.25), value: model.highlighted)
        }
    }

    private func rowBackground(_ symbol: String) -> Color {
        if model.highlighted == symbol { return Theme.highlight }
        if model.selected == symbol { return Color.white.opacity(0.05) }
        return Theme.bg
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 14) {
                Spacer(minLength: 28)
                Text("Nothing on the tape yet.")
                    .font(Theme.sans(15, weight: .medium))
                    .foregroundStyle(Theme.text)
                Text("Search above for a stock, ETF, commodity or crypto pair, or start with one of these.")
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                FlowChips(items: starters) { sym in
                    if let r = SearchResult.curated(sym) { model.add(r) } else { model.addRaw(sym) }
                }
                Text(model.footerText)
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.dim)
                    .padding(.top, 8)
                Spacer()
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.immediately)
        .onTapGesture { searchFocused = false }
    }
}

/// Wrapping row of tappable chips.
@MainActor
struct FlowChips: View {
    let items: [String]
    let action: (String) -> Void

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 92), spacing: 8)]
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button { action(item) } label: {
                    Text(item)
                        .font(Theme.mono(13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Theme.surface, in: Capsule())
                        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(item) to the tape")
            }
        }
    }
}

@MainActor
struct ToastView: View {
    let text: String
    let undo: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Text(text)
                .font(Theme.sans(13))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            if let undo {
                Button("Undo", action: undo)
                    .font(Theme.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.selected, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Status chip. Tapping opens a plain-language explanation of the state (Kimi review U5).
@MainActor
struct StatusChip: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        let status = model.status
        Button { model.showStatusInfo = true } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(dotColor(status))
                    .frame(width: 7, height: 7)
                    .opacity(status == .open && !reduceMotion ? (pulse ? 0.35 : 1) : 1)
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
                    }
                Text(text(status))
                    .font(Theme.mono(11, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(text(status))")
        .accessibilityHint("Explains what this status means")
    }

    private func dotColor(_ s: AppModel.Status) -> Color {
        switch s {
        case .open: return Theme.green
        case .limited, .stale, .dead: return Theme.warn
        case .noKey, .keyInvalid: return Theme.red
        default: return Theme.dim
        }
    }

    private func text(_ s: AppModel.Status) -> String {
        var t = s.rawValue
        if let last = model.lastUpdate, !model.symbols.isEmpty, s != .noKey, s != .keyInvalid {
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            t += " · " + f.string(from: last)
        }
        return t
    }
}

/// Sheet body behind the status chip.
@MainActor
struct StatusInfoView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    private static let stamp: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()

    var body: some View {
        let e = model.statusExplanation
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text(model.status.rawValue).font(Theme.mono(11, weight: .medium)).tracking(0.8).foregroundStyle(Theme.muted)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                        Spacer()
                    }
                    Text(e.title).font(Theme.sans(20, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(e.detail).font(Theme.sans(14)).foregroundStyle(Theme.muted)
                    if let last = model.lastUpdate, !model.symbols.isEmpty {
                        Text("Last refresh \(Self.stamp.string(from: last)).")
                            .font(Theme.sans(12)).foregroundStyle(Theme.dim)
                    }
                    Text("Used today (estimated): \(model.creditsUsedToday) of 800 credits · resets 00:00 UTC · 40 reserved for your taps.")
                        .font(Theme.sans(12)).foregroundStyle(Theme.dim)
                    if model.status == .noKey || model.status == .keyInvalid {
                        Button("Open settings") { dismiss(); model.showSettings = true }
                            .font(Theme.sans(15, weight: .semibold)).foregroundStyle(Theme.bg)
                            .frame(height: 44).padding(.horizontal, 18)
                            .background(Theme.text, in: RoundedRectangle(cornerRadius: 10))
                            .padding(.top, 6)
                    }
                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.foregroundStyle(Theme.text) } }
        }
        .preferredColorScheme(.dark)
    }
}

@MainActor
struct InstrumentRow: View {
    @Environment(AppModel.self) private var model
    let symbol: String

    var body: some View {
        let q = model.quotes[symbol]
        let err = model.quoteErrors[symbol]
        let inst = model.instrument(for: symbol)
        let quarantined = model.isQuarantined(symbol)
        let spark = model.displaySeries(for: symbol, .day)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(symbol)
                    .font(Theme.mono(15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(subtitle(inst: inst, quote: q, error: err, quarantined: quarantined))
                    .font(Theme.sans(12))
                    .foregroundStyle(quarantined ? Theme.warn : Theme.muted)
                    .lineLimit(1)
            }
            .frame(width: 104, alignment: .leading)

            if quarantined {
                Spacer()
            } else if let s = spark, s.points.count >= 2 {
                Sparkline(series: s, reference: model.referenceValue(for: symbol, timeframe: .day), convention: model.upColor)
            } else if let q, err == nil {
                DayRangeBar(quote: q, convention: model.upColor)
            } else {
                Spacer()
            }

            VStack(alignment: .trailing, spacing: 4) {
                if quarantined {
                    Text("paused").font(Theme.sans(12, weight: .medium)).foregroundStyle(Theme.warn)
                    Text("swipe to resume").font(Theme.sans(11)).foregroundStyle(Theme.dim)
                } else if let q, err == nil {
                    Text(Format.price(q.last))
                        .font(Theme.mono(15))
                        .foregroundStyle(Theme.text)
                        .contentTransition(.numericText())
                    ChangePill(change: q.changeValue, percent: q.percentChangeValue, convention: model.upColor)
                } else if err != nil {
                    Text("not found").font(Theme.sans(12)).foregroundStyle(Theme.red)
                    Text("costs a credit each refresh").font(Theme.sans(10)).foregroundStyle(Theme.dim).lineLimit(1).minimumScaleFactor(0.8)
                } else {
                    Text("…").font(Theme.mono(15)).foregroundStyle(Theme.dim)
                }
            }
            .frame(width: 112, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 72)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(q: q, err: err, quarantined: quarantined))
    }

    private func subtitle(inst: Instrument, quote q: Quote?, error: String?, quarantined: Bool) -> String {
        if quarantined { return "Paused after repeated failures" }
        if error != nil { return "No data" }
        if !inst.name.isEmpty { return inst.name }
        if let n = q?.name, !n.isEmpty { return n }
        return model.apiKey.isEmpty ? "" : "Loading…"
    }

    private func accessibilityText(q: Quote?, err: String?, quarantined: Bool) -> String {
        if quarantined { return "\(symbol), paused after repeated failed lookups. Swipe right to resume." }
        if err != nil { return "\(symbol), not found" }
        guard let q else { return "\(symbol), loading" }
        let dir = (q.changeValue ?? 0) > 0 ? "up" : ((q.changeValue ?? 0) < 0 ? "down" : "unchanged")
        return "\(symbol), \(Format.price(q.last)), \(dir) \(Format.signedPercent(q.percentChangeValue))"
    }
}

/// Tiny line drawn from the cached 1D series (Kimi review U6, cache-only variant: no extra credits).
@MainActor
struct Sparkline: View {
    let series: PriceSeries
    let reference: Double?
    let convention: UpColorConvention

    /// Plain arithmetic kept out of the view builder so the type-checker stays fast.
    struct Layout {
        let lo: Double
        let span: Double
        let maxSlot: Double
        let rising: Bool
        init(series: PriceSeries, reference: Double?) {
            let pts = series.points
            var lo = series.low ?? 0
            var hi = series.high ?? 0
            if let r = reference { lo = min(lo, r); hi = max(hi, r) }
            self.lo = lo
            self.span = (hi - lo) == 0 ? 1 : (hi - lo)
            self.maxSlot = max(series.slots, 1)
            let last = pts.last?.value ?? 0
            let base = reference ?? (pts.first?.value ?? 0)
            self.rising = (last - base) >= 0
        }
        func x(_ slot: Double, width: CGFloat) -> CGFloat { CGFloat(slot / maxSlot) * width }
        func y(_ value: Double, height: CGFloat) -> CGFloat { height - CGFloat((value - lo) / span) * height }
    }

    var body: some View {
        let layout = Layout(series: series, reference: reference)
        let color = layout.rising ? Theme.up(convention) : Theme.down(convention)
        GeometryReader { geo in
            ZStack {
                if let r = reference {
                    referenceLine(layout: layout, value: r, size: geo.size)
                }
                line(layout: layout, size: geo.size)
                    .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: 28)
        .accessibilityHidden(true)
    }

    private func referenceLine(layout: Layout, value: Double, size: CGSize) -> some View {
        let y = layout.y(value, height: size.height)
        return Path { p in
            p.move(to: CGPoint(x: 0, y: y))
            p.addLine(to: CGPoint(x: size.width, y: y))
        }
        .stroke(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
    }

    private func line(layout: Layout, size: CGSize) -> Path {
        var path = Path()
        for (i, pt) in series.points.enumerated() {
            let point = CGPoint(x: layout.x(pt.slot, width: size.width), y: layout.y(pt.value, height: size.height))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

@MainActor
struct DayRangeBar: View {
    let quote: Quote
    let convention: UpColorConvention
    var body: some View {
        GeometryReader { geo in
            let lo = quote.dayLow, hi = quote.dayHigh, last = quote.last
            let width = geo.size.width
            let span: Double? = {
                guard let lo, let hi, hi > lo else { return nil }
                return hi - lo
            }()
            let pos: CGFloat = {
                guard let lo, let last, let span else { return 0.5 }
                return CGFloat(max(0, min(1, (last - lo) / span)))
            }()
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.border).frame(height: 3)
                if let lo, let span, let pc = quote.prevClose {
                    let gp = (pc - lo) / span
                    Rectangle()
                        .fill(Theme.dim.opacity(gp < 0 || gp > 1 ? 0.3 : 0.7))
                        .frame(width: 1, height: 9)
                        .offset(x: CGFloat(max(0, min(1, gp))) * width - 0.5)
                }
                Circle()
                    .fill(Theme.changeColor(quote.changeValue, convention: convention))
                    .frame(width: 9, height: 9)
                    .offset(x: pos * width - 4.5)
            }
            .frame(height: 9)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 20)
        .accessibilityHidden(true)
    }
}

@MainActor
struct ChangePill: View {
    let change: Double?
    let percent: Double?
    let convention: UpColorConvention
    var body: some View {
        let color = Theme.changeColor(change, convention: convention)
        ChangeText(change: change, text: Format.signedPercent(percent), convention: convention)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }
}
