import SwiftUI
import Charts
import TapeCore

/// Everything here reads by `symbol`, never by `model.selected`, so the page cannot show
/// another name's numbers while a selection change is in flight (Kimi review M7).
@MainActor
struct DetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let symbol: String

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if model.isQuarantined(symbol) { quarantineNotice }
                    priceBlock
                    timeframePicker
                    PriceChart(symbol: symbol)
                        .frame(height: 290)
                        .padding(.horizontal, 4)
                    stats
                    Text(model.footerText)
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.dim)
                        .padding(.top, 14)
                }
                .padding(16)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
                .padding(16)
            }
            .refreshable { await model.refresh() }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.bg, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(symbol).font(Theme.mono(15, weight: .semibold)).foregroundStyle(Theme.text)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: model.removeArmed == symbol ? ButtonRole.destructive : nil) {
                    model.armOrRemove(symbol)
                } label: {
                    Text(model.removeArmed == symbol ? "Remove \(symbol)?" : "Remove")
                        .font(Theme.sans(13, weight: .medium))
                        .foregroundStyle(model.removeArmed == symbol ? Theme.red : Theme.muted)
                }
                .accessibilityHint(model.removeArmed == symbol ? "Tap again to remove" : "Tap twice to remove from the tape")
            }
        }
        .onAppear { if model.selected != symbol { model.select(symbol, userInitiated: true) } }
        .onDisappear { model.disarmRemove() }
        // The page belongs to a name on the tape; when that name goes (swipe on the list,
        // undo, or the toolbar button) the page goes with it (Kimi review U7).
        .onChange(of: model.symbols) { _, now in
            if !now.contains(symbol) { dismiss() }
        }
        .sensoryFeedback(.selection, trigger: model.hover) { old, new in old != nil && new != nil && old != new }
    }

    private var quote: Quote? { model.quotes[symbol] }
    private var currentSeries: PriceSeries? { model.displaySeries(for: symbol, model.timeframe) }

    private var header: some View {
        let inst = model.instrument(for: symbol)
        let q = quote
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(symbol).font(Theme.mono(15, weight: .semibold)).foregroundStyle(Theme.text)
                    if inst.type != .other { TypeBadge(type: inst.type) }
                    if let c = q?.currency, !c.isEmpty, c != "USD" {
                        Text(c).font(Theme.mono(10, weight: .medium)).tracking(0.8).foregroundStyle(Theme.muted)
                    }
                }
                Text(subtitle(inst: inst, quote: q))
                    .font(Theme.sans(12)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer()
        }
    }

    private func subtitle(inst: Instrument, quote q: Quote?) -> String {
        if let err = model.quoteErrors[symbol] { return err }
        let name = inst.name.isEmpty ? (q?.name ?? "") : inst.name
        if let ex = q?.exchange, !ex.isEmpty { return name.isEmpty ? ex : name + " · " + ex }
        return name.isEmpty ? (model.apiKey.isEmpty ? "Add a key to load prices" : "Loading…") : name
    }

    private var quarantineNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "pause.circle").foregroundStyle(Theme.warn)
            Text("Paused after \(PollSchedule.quarantineThreshold) failed lookups. Each retry costs a credit.")
                .font(Theme.sans(12)).foregroundStyle(Theme.muted)
            Spacer()
            Button("Resume") { model.resume(symbol) }
                .font(Theme.sans(13, weight: .semibold)).foregroundStyle(Theme.text)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
        }
        .padding(10)
        .background(Theme.bg, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.warn.opacity(0.5), lineWidth: 1))
        .padding(.top, 12)
    }

    private var priceBlock: some View {
        let q = quote
        let s = currentSeries
        let ref = model.referenceValue(for: symbol)
        let live = q?.last ?? s?.last
        var shown = live
        var label = model.sessionLabel(for: symbol)
        if let h = model.hover, let s, h < s.points.count { shown = s.points[h].value; label = s.points[h].label }
        let change: Double? = {
            guard let shown, let ref, ref != 0 else { return nil }
            return shown - ref
        }()
        let pct: Double? = change.flatMap { c in ref.map { c / $0 * 100 } }
        let ext: Double? = {
            guard let q, model.instrument(for: symbol).session == .regularHours, q.isMarketOpen == false,
                  let e = q.extendedPrice?.value, let l = live, abs(e - l) > 1e-9 else { return nil }
            return e
        }()
        let currency = (q?.currency).flatMap { $0.isEmpty || $0 == "USD" ? nil : $0 }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Format.price(shown))
                    .font(Theme.mono(40, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText())
                if let currency { Text(currency).font(Theme.mono(14)).foregroundStyle(Theme.muted) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Price \(Format.price(shown)) \(currency ?? "US dollars")")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let change {
                    ChangeText(change: change,
                               text: Format.signed(change, precision: Format.precision(for: shown ?? change)) + " (" + Format.signedPercent(pct) + ")",
                               convention: model.upColor,
                               font: Theme.mono(14))
                }
                Text(label).font(Theme.mono(14)).foregroundStyle(Theme.muted)
            }
            if let ext {
                Text("After hours \(Format.price(ext))" + (q?.extendedPercentChange?.value.map { " (\(Format.signedPercent($0)))" } ?? ""))
                    .font(Theme.mono(12)).foregroundStyle(Theme.muted)
            }
        }
        .padding(.top, 14)
    }

    private var timeframePicker: some View {
        HStack(spacing: 8) {
            ForEach(Timeframe.allCases) { tf in
                Button { model.setTimeframe(tf) } label: {
                    Text(tf.rawValue)
                        .font(Theme.mono(14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .foregroundStyle(model.timeframe == tf ? Theme.text : Theme.muted)
                        .background(model.timeframe == tf ? Theme.selected : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.timeframe == tf ? [.isSelected] : [])
            }
        }
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    /// Always eight cells so the grid never reflows between timeframes (Kimi review U15).
    private var stats: some View {
        let q = quote
        let s = currentSeries
        let live = q?.last ?? s?.last
        let none = "—"
        var cells: [(String, String)]
        if model.timeframe == .day {
            cells = [("OPEN", Format.price(q?.open?.value)), ("HIGH", Format.price(q?.dayHigh)),
                     ("LOW", Format.price(q?.dayLow)), ("PREV CLOSE", Format.price(q?.prevClose))]
        } else {
            let first = s?.first
            cells = [("OPEN", Format.price(first)), ("HIGH", Format.price(s?.high)), ("LOW", Format.price(s?.low)),
                     ("CHANGE", (live != nil && first != nil) ? Format.signed(live! - first!, precision: Format.precision(for: live!)) : none)]
        }
        cells += [("VOLUME", Format.compact(q?.volume?.value)), ("AVG VOLUME", Format.compact(q?.averageVolume?.value)),
                  ("52W LOW", Format.price(q?.fiftyTwoWeek?.low?.value)), ("52W HIGH", Format.price(q?.fiftyTwoWeek?.high?.value))]
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(Array(cells.enumerated()), id: \.offset) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.element.0).font(Theme.mono(10, weight: .medium)).tracking(0.8).foregroundStyle(Theme.muted)
                    Text(item.element.1).font(Theme.mono(16)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.7)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.bg, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.element.0.capitalized) \(item.element.1)")
            }
        }
        .padding(.top, 14)
    }
}

/// Line-plus-area chart with a dashed reference line, live-price marker and drag-to-scrub.
@MainActor
struct PriceChart: View {
    @Environment(AppModel.self) private var model
    let symbol: String

    var body: some View {
        let series = model.displaySeries(for: symbol, model.timeframe)
        let ref = model.referenceValue(for: symbol)
        let drawable = (series?.points.count ?? 0) >= 2
        ZStack {
            if let s = series, drawable {
                chart(s, ref: ref)
            } else {
                Rectangle().fill(Color.clear)
            }
            if !drawable, model.selected == symbol {
                VStack(spacing: 10) {
                    if let msg = model.chartMessage {
                        if msg == "Loading…" { ProgressView().tint(Theme.muted) }
                        Text(msg).font(Theme.sans(13)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).padding(.horizontal, 24)
                        if msg != "Loading…" && !model.apiKey.isEmpty {
                            Button("Try again") { model.retryChart() }
                                .font(Theme.sans(13, weight: .semibold)).foregroundStyle(Theme.text)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                        }
                    } else if model.apiKey.isEmpty {
                        Text("Add a Twelve Data key to load the chart.").font(Theme.sans(13)).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
    }

    private func chart(_ s: PriceSeries, ref: Double?) -> some View {
        let slots = SeriesParser.effectiveSlots(for: s, sessionComplete: model.sessionComplete(for: symbol))
        let last = s.points.last!
        let rising = (ref.map { last.value - $0 } ?? (last.value - s.points[0].value)) >= 0
        let color = rising ? Theme.up(model.upColor) : Theme.down(model.upColor)
        var lo = s.low ?? last.value, hi = s.high ?? last.value
        if let ref { lo = min(lo, ref); hi = max(hi, ref) }
        var span = (hi - lo)
        if span == 0 { span = max(abs(hi) * 0.01, 1) }
        lo -= span * 0.06; hi += span * 0.06
        let axis: [AxisLabel] = s.profile == .allDay ? (s.axis ?? []) : SeriesParser.regularAxis(for: s, slots: slots)
        let hoverPoint: SeriesPoint? = model.hover.flatMap { $0 < s.points.count ? s.points[$0] : nil }

        return Chart {
            ForEach(s.points) { p in
                AreaMark(x: .value("Time", p.slot), yStart: .value("Floor", lo), yEnd: .value("Price", p.value))
                    .foregroundStyle(color.opacity(0.12))
                    .interpolationMethod(.linear)
                LineMark(x: .value("Time", p.slot), y: .value("Price", p.value))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.linear)
            }
            if let ref {
                RuleMark(y: .value("Reference", ref))
                    .foregroundStyle(Color(red: 0x3a / 255, green: 0x47 / 255, blue: 0x54 / 255))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
            PointMark(x: .value("Time", last.slot), y: .value("Price", last.value))
                .symbolSize(180).foregroundStyle(color.opacity(0.22))
            PointMark(x: .value("Time", last.slot), y: .value("Price", last.value))
                .symbolSize(40).foregroundStyle(color)
            if let hp = hoverPoint {
                RuleMark(x: .value("Time", hp.slot))
                    .foregroundStyle(Theme.muted)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                PointMark(x: .value("Time", hp.slot), y: .value("Price", hp.value))
                    .symbolSize(60).foregroundStyle(Theme.bg)
                PointMark(x: .value("Time", hp.slot), y: .value("Price", hp.value))
                    .symbolSize(24).foregroundStyle(color)
            }
        }
        .chartXScale(domain: 0...max(slots, 1))
        .chartYScale(domain: lo...hi)
        .chartXAxis {
            AxisMarks(values: axis.map(\.slot)) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self), let label = axis.first(where: { abs($0.slot - v) < 0.001 }) {
                        Text(label.text).font(Theme.mono(11)).foregroundStyle(Theme.dim)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: [lo, (lo + hi) / 2, hi]) { value in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(Format.price(v)).font(Theme.mono(11)).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { g in
                                guard let frame = proxy.plotFrame else { return }
                                let origin = geo[frame].origin
                                if let slot: Double = proxy.value(atX: g.location.x - origin.x) {
                                    var best = 0; var bestDist = Double.infinity
                                    for (i, p) in s.points.enumerated() {
                                        let d = abs(p.slot - slot)
                                        if d < bestDist { bestDist = d; best = i }
                                    }
                                    if model.hover != best { model.hover = best }
                                }
                            }
                            .onEnded { _ in model.hover = nil }
                    )
            }
        }
        .accessibilityLabel("Price chart for \(symbol), \(s.points.count) points, \(rising ? "up" : "down") over the period, from \(Format.price(s.first)) to \(Format.price(last.value))")
    }
}
