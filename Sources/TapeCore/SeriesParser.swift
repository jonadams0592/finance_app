import Foundation

/// Turns Twelve Data bars (newest first) into a drawable series. Same rules as the web build:
/// - Regular hours 1D: 78 five-minute slots from 09:30 to 16:00, only the latest session's bars.
/// - Regular hours 1W: five sessions of 13 half-hour slots; a 16:00 bar is clamped onto slot 12.
/// - Regular hours 1M: one slot per daily bar.
/// - 24-hour instruments: one slot per bar, axis labels derived from the bar clock/date.
public enum SeriesParser {
    private static let sessionStart = 570   // 09:30 in minutes
    private static let sessionLength = 390  // to 16:00

    public static func parse(bars newestFirst: [Bar], timeframe: Timeframe, session: SessionProfile, fetchedAt: Date = Date()) -> PriceSeries? {
        let asc = Array(newestFirst.reversed())
        guard !asc.isEmpty else { return nil }
        switch session {
        case .regularHours: return parseRegular(asc, timeframe: timeframe, fetchedAt: fetchedAt)
        case .allDay: return parseAllDay(asc, timeframe: timeframe, fetchedAt: fetchedAt)
        }
    }

    private static func parseRegular(_ asc: [Bar], timeframe: Timeframe, fetchedAt: Date) -> PriceSeries? {
        var points: [SeriesPoint] = []
        var days: [String] = []
        var slots: Double
        var sessionDate: String? = nil

        switch timeframe {
        case .day:
            guard let lastBar = asc.last else { return nil }
            let date = BarTime.date(of: lastBar.datetime)
            sessionDate = date
            slots = 78
            for b in asc where BarTime.date(of: b.datetime) == date {
                let m = BarTime.minutes(of: b.datetime) - sessionStart
                guard m >= 0, m <= sessionLength, let v = b.close?.value, v.isFinite else { continue }
                points.append(SeriesPoint(slot: Double(m) / 5, value: v, label: Format.clock24(minutes: BarTime.minutes(of: b.datetime))))
            }
            days = [date]
        case .week:
            var distinct: [String] = []
            var seen = Set<String>()
            for b in asc.reversed() {
                let d = BarTime.date(of: b.datetime)
                if !seen.contains(d) { seen.insert(d); distinct.insert(d, at: 0) }
            }
            days = Array(distinct.suffix(5))
            var index: [String: Int] = [:]
            for (i, d) in days.enumerated() { index[d] = i }
            slots = Double(days.count * 13)
            for b in asc {
                let d = BarTime.date(of: b.datetime)
                guard let di = index[d] else { continue }
                let m = BarTime.minutes(of: b.datetime) - sessionStart
                guard m >= 0, m <= sessionLength, let v = b.close?.value, v.isFinite else { continue }
                let slot = Double(di) * 13 + min(Double(m) / 30, 12)
                points.append(SeriesPoint(slot: slot, value: v, label: Format.weekday(d) + " " + Format.clock24(minutes: BarTime.minutes(of: b.datetime))))
            }
        case .month:
            slots = Double(max(1, asc.count - 1))
            for (k, b) in asc.enumerated() {
                let d = BarTime.date(of: b.datetime)
                days.append(d)
                guard let v = b.close?.value, v.isFinite else { continue }
                points.append(SeriesPoint(slot: Double(k), value: v, label: Format.shortDate(d)))
            }
        }
        return PriceSeries(profile: .regularHours, timeframe: timeframe, points: points, slots: slots, days: days,
                           sessionDate: sessionDate, lastSlot: points.last?.slot ?? 0, axis: nil, fetchedAt: fetchedAt)
    }

    private static func parseAllDay(_ asc: [Bar], timeframe: Timeframe, fetchedAt: Date) -> PriceSeries? {
        struct Raw { let slot: Int; let value: Double; let date: String; let minutes: Int }
        var raw: [Raw] = []
        for (k, b) in asc.enumerated() {
            guard let v = b.close?.value, v.isFinite else { continue }
            raw.append(Raw(slot: k, value: v, date: BarTime.date(of: b.datetime), minutes: BarTime.minutes(of: b.datetime)))
        }
        guard !raw.isEmpty else { return nil }
        let n = raw.count
        let slots = Double(max(1, n - 1))
        var axis: [AxisLabel] = []
        switch timeframe {
        case .day:
            for k in 0...4 {
                let i = Int((Double(k) * Double(n - 1) / 4).rounded())
                if i < n { axis.append(AxisLabel(slot: Double(raw[i].slot), text: Format.clock24(minutes: raw[i].minutes))) }
            }
        case .week:
            var lastDate: String? = nil
            for r in raw {
                if r.date != lastDate {
                    if lastDate != nil { axis.append(AxisLabel(slot: Double(r.slot), text: Format.weekday(r.date))) }
                    lastDate = r.date
                }
            }
            if axis.count > 7 { axis = axis.enumerated().filter { $0.offset % 2 == 0 }.map { $0.element } }
        case .month:
            for k in 0...4 {
                let i = Int((Double(k) * Double(n - 1) / 4).rounded())
                if i < n { axis.append(AxisLabel(slot: Double(raw[i].slot), text: Format.shortDate(raw[i].date))) }
            }
        }
        let points = raw.map { r -> SeriesPoint in
            let label: String
            switch timeframe {
            case .day: label = Format.clock24(minutes: r.minutes)
            case .week: label = Format.weekday(r.date) + " " + Format.clock24(minutes: r.minutes)
            case .month: label = Format.shortDate(r.date)
            }
            return SeriesPoint(slot: Double(r.slot), value: r.value, label: label)
        }
        return PriceSeries(profile: .allDay, timeframe: timeframe, points: points, slots: slots, days: raw.map(\.date),
                           sessionDate: nil, lastSlot: slots, axis: axis, fetchedAt: fetchedAt)
    }

    /// Axis labels for a regular-hours series at render time. `slots` may be shrunk for an
    /// early close (see `PollSchedule.effectiveSlots`).
    public static func regularAxis(for series: PriceSeries, slots: Double) -> [AxisLabel] {
        switch series.timeframe {
        case .day:
            var out: [AxisLabel] = []
            for sl in [0.0, 18, 36, 54] where sl < slots - 6 {
                out.append(AxisLabel(slot: sl, text: Format.clock24(minutes: sessionStart + Int(sl) * 5)))
            }
            out.append(AxisLabel(slot: slots, text: Format.clock24(minutes: sessionStart + Int(slots) * 5)))
            return out
        case .week:
            return series.days.enumerated().map { AxisLabel(slot: Double($0.offset) * 13, text: Format.weekday($0.element)) }
        case .month:
            let n = series.days.count
            guard n > 1 else { return [] }
            return (0...4).map { k in
                let i = Int((Double(k) * Double(n - 1) / 4).rounded())
                return AxisLabel(slot: Double(i), text: Format.shortDate(series.days[min(i, n - 1)]))
            }
        }
    }

    /// The x-axis width to draw. A completed regular-hours session that ended early
    /// (13:00 half day) shrinks the axis so the afternoon is not an empty stretch.
    public static func effectiveSlots(for series: PriceSeries, sessionComplete: Bool) -> Double {
        if series.profile == .regularHours, series.timeframe == .day, sessionComplete, series.lastSlot < 70 {
            return max(series.lastSlot, 42)
        }
        return series.slots
    }
}
