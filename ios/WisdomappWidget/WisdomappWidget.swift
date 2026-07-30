import WidgetKit
import SwiftUI

private let widgetBrandName = "EQUIPE WISDOM APP"
private let appGroupId = "group.com.wisdomapp.widget"
private let jsonKey = "widget_events_json"

// Margens internas alinhadas ao Android (widget_calendar_*.xml / widget_list_container).
private let widgetInsetSmall = EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
private let widgetInsetMedium = EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
// Topo extra no large: cantos arredondados do widget cortam logo + marca se padding for baixo.
private let widgetInsetLarge = EdgeInsets(top: 18, leading: 12, bottom: 10, trailing: 12)

// Mesma cor do Android @drawable/widget_bg_dark (#151B28).
private let bgColor = Color(red: 21.0 / 255.0, green: 27.0 / 255.0, blue: 40.0 / 255.0)
private let brandColor = Color(red: 0.83, green: 0.69, blue: 0.22)

// MARK: - JSON v2 (só strings — Flutter mastiga tudo na isolate)

struct WidgetNativeRow: Decodable {
    let k: String
    let dn: String?
    let wd: String?
    let ws: String?
    let td: String?
    let dc: String?
    let sy: String?
    let ti: String?
    let tm: String?
    let bc: String?
    let tx: String?

    init(
        k: String,
        dn: String? = nil,
        wd: String? = nil,
        ws: String? = nil,
        td: String? = nil,
        dc: String? = nil,
        sy: String? = nil,
        ti: String? = nil,
        tm: String? = nil,
        bc: String? = nil,
        tx: String? = nil
    ) {
        self.k = k
        self.dn = dn
        self.wd = wd
        self.ws = ws
        self.td = td
        self.dc = dc
        self.sy = sy
        self.ti = ti
        self.tm = tm
        self.bc = bc
        self.tx = tx
    }
}

struct WidgetPayload: Decodable {
    let brand: String?
    let hint: String?
    let updated: String?
    let updatedAt: String?
    let horizonStartMs: Int64?
    let rows: [WidgetNativeRow]?
}

// MARK: - Virada de dia (meia-noite) + CAIXA ALTA

private let horizonDays = 5
private let weekdayNames = [
    "", "SEGUNDA-FEIRA", "TERÇA-FEIRA", "QUARTA-FEIRA", "QUINTA-FEIRA",
    "SEXTA-FEIRA", "SÁBADO", "DOMINGO",
]
private let monthAbbr = ["JAN", "FEV", "MAR", "ABR", "MAI", "JUN", "JUL", "AGO", "SET", "OUT", "NOV", "DEZ"]

private func widgetCaps(_ raw: String) -> String {
    raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(with: Locale(identifier: "pt_BR"))
}

private func startOfDayMs(_ date: Date) -> Int64 {
    let cal = Calendar.current
    let comps = cal.dateComponents([.year, .month, .day], from: date)
    let day = cal.date(from: comps) ?? date
    return Int64(day.timeIntervalSince1970 * 1000)
}

private func maybeRolloverWidgetJson(_ raw: String, now: Date = Date()) -> String? {
    guard let data = raw.data(using: .utf8),
          var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let events = root["events"] as? [[String: Any]],
          !events.isEmpty else { return nil }

    let todayStart = startOfDayMs(now)
    let horizonStart = (root["horizonStartMs"] as? NSNumber)?.int64Value ?? 0
    let nowMs = Int64(now.timeIntervalSince1970 * 1000)
    let hasExpired = events.contains { ev in
        let until = (ev["visibleUntilMs"] as? NSNumber)?.int64Value ?? 0
        return until > 0 && nowMs >= until
    }
    if horizonStart == todayStart && !hasExpired { return nil }

    let cal = Calendar.current
  var filtered = events.filter { ev in
        let dayMs = (ev["dayMs"] as? NSNumber)?.int64Value ?? 0
        if dayMs < todayStart { return false }
        let until = (ev["visibleUntilMs"] as? NSNumber)?.int64Value ?? 0
        if until > 0 && nowMs >= until { return false }
        return true
    }
    filtered.sort {
        let a = ($0["sortMs"] as? NSNumber)?.int64Value ?? 0
        let b = ($1["sortMs"] as? NSNumber)?.int64Value ?? 0
        return a < b
    }

    var rows: [[String: Any]] = []
    var hasAnyEvent = false
    let oldRows = root["rows"] as? [[String: Any]] ?? []
    let financeRows = oldRows.filter { ($0["k"] as? String) == "f" }

    for i in 0..<horizonDays {
        let dayMs = todayStart + Int64(i) * 86_400_000
        let dayDate = Date(timeIntervalSince1970: TimeInterval(dayMs) / 1000)
        let isToday = i == 0
        let dayKey = "\(startOfDayMs(dayDate))"
        let weekdayIdx = cal.component(.weekday, from: dayDate)
        let mapped = weekdayIdx == 1 ? 7 : weekdayIdx - 1
        let wd = (mapped >= 1 && mapped <= 7) ? weekdayNames[mapped] : ""
        let headerWd: String
        if isToday {
            headerWd = wd
        } else {
            let month = monthAbbr[max(0, min(11, cal.component(.month, from: dayDate) - 1))]
            headerWd = widgetCaps("\(wd), \(cal.component(.day, from: dayDate)) DE \(month).")
        }

        rows.append([
            "k": "h",
            "dn": "\(cal.component(.day, from: dayDate))",
            "wd": headerWd,
            "td": isToday ? "1" : "0",
            "dc": isToday ? "#FFFF8A50" : "#FFFFFFFF",
        ])

        let dayEvents = filtered.filter { ev in
            let eDay = (ev["dayMs"] as? NSNumber)?.int64Value ?? 0
            return "\(startOfDayMs(Date(timeIntervalSince1970: TimeInterval(eDay) / 1000)))" == dayKey
        }
        let maxEv = isToday ? 8 : 6
        let slice = Array(dayEvents.prefix(maxEv))
        let extra = dayEvents.count - slice.count

        if slice.isEmpty {
            rows.append([
                "k": "x",
                "tx": isToday ? "SEM COMPROMISSOS PARA HOJE" : "SEM COMPROMISSOS",
            ])
        } else {
            for ev in slice {
                hasAnyEvent = true
                let title = (ev["title"] as? String) ?? "EVENTO"
                let accent = (ev["accentHex"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                rows.append([
                    "k": "e",
                    "sy": (ev["symbol"] as? String) ?? "🚔",
                    "ti": widgetCaps(title),
                    "tm": widgetCaps((ev["timeRange"] as? String) ?? ""),
                    "bc": accent.isEmpty ? (isToday ? "#FF00BCD4" : "#FF2563EB") : (accent.hasPrefix("#") ? accent : "#\(accent)"),
                    "ag": (ev["type"] as? String) ?? "scale",
                ])
            }
            if extra > 0 {
                rows.append(["k": "m", "tx": "+\(extra) EVENTO(S)"])
            }
        }
    }

    for financeRow in financeRows { rows.append(financeRow) }

    let financeRaw = (root["financeRaw"] as? String) ?? ""
    let hasFinance = !financeRows.isEmpty || !financeRaw.isEmpty
    let hint: String
    if !hasAnyEvent && !hasFinance {
        hint = "SEM COMPROMISSOS PARA HOJE — TOQUE PARA ABRIR"
    } else {
        hint = "TOQUE PARA ABRIR O WISDOM APP"
    }

    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "pt_BR")
    fmt.dateFormat = "dd/MM HH:mm"
    let updated = fmt.string(from: now)

    root["rev"] = Int64(now.timeIntervalSince1970 * 1000)
    root["horizonStartMs"] = todayStart
    root["brand"] = widgetCaps((root["brand"] as? String) ?? widgetBrandName)
    root["hint"] = hint
    root["updated"] = updated
    root["events"] = filtered
    root["rows"] = rows

    guard let out = try? JSONSerialization.data(withJSONObject: root),
          let json = String(data: out, encoding: .utf8) else { return nil }
    return json
}

struct WisdomAppEntry: TimelineEntry {
    let date: Date
    let brand: String
    let hint: String
    let updated: String
    let rows: [WidgetNativeRow]
}

// MARK: - Provider (leitura síncrona imediata — zero rede, zero transformação)

struct WisdomAppProvider: TimelineProvider {
    func placeholder(in context: Context) -> WisdomAppEntry {
        failSafeEntry()
    }

    func getSnapshot(in context: Context, completion: @escaping (WisdomAppEntry) -> Void) {
        completion(loadEntrySync(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WisdomAppEntry>) -> Void) {
        let now = Date()
        // Persiste rollover se o dia civil já mudou (ex.: abriu o widget após 00:00).
        var entries = [loadEntrySync(at: now, persist: true)]
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: now)

        // Até 7 meias-noites — virada automática do dia + horizonte de 5 dias (app fechado).
        // Paridade com Android (AlarmManager 00:00). persist=false: não gravar o futuro antes da hora.
        for offset in 1...7 {
            if let midnight = cal.date(byAdding: .day, value: offset, to: dayStart) {
                entries.append(loadEntrySync(at: midnight, persist: false))
            }
        }
        for expiry in nextWidgetExpiryDates(after: now) {
            entries.append(loadEntrySync(at: expiry, persist: false))
        }
        entries.sort { $0.date < $1.date }
        var unique: [WisdomAppEntry] = []
        var seen = Set<Int64>()
        for entry in entries {
            let key = Int64(entry.date.timeIntervalSince1970)
            if seen.insert(key).inserted {
                unique.append(entry)
            }
        }
        completion(Timeline(entries: unique, policy: .atEnd))
    }

    /// Próximos horários em que um plantão some do widget (fim + 2h).
    private func nextWidgetExpiryDates(after now: Date) -> [Date] {
        guard let defaults = UserDefaults(suiteName: appGroupId),
              let raw = defaults.string(forKey: jsonKey),
              let data = raw.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = root["events"] as? [[String: Any]] else { return [] }
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        var out: [Date] = []
        for ev in events {
            let until = (ev["visibleUntilMs"] as? NSNumber)?.int64Value ?? 0
            if until <= nowMs { continue }
            let d = Date(timeIntervalSince1970: TimeInterval(until) / 1000)
            if d > now { out.append(d) }
        }
        out.sort()
        // Máx. 8 refreshes extras (plantões do dia).
        return Array(out.prefix(8))
    }

    private func loadEntrySync(at date: Date = Date(), persist: Bool = true) -> WisdomAppEntry {
        do {
            let rawJson = resolveJson(at: date, persist: persist)
            guard let raw = rawJson,
                  let data = raw.data(using: .utf8) else {
                return failSafeEntry()
            }
            let payload = try JSONDecoder().decode(WidgetPayload.self, from: data)
            let rows = payload.rows ?? []
            if rows.isEmpty {
                return failSafeEntry(
                    brand: payload.brand ?? widgetBrandName,
                    hint: payload.hint ?? "Toque para abrir",
                    updated: payload.updated ?? payload.updatedAt ?? ""
                )
            }
            return WisdomAppEntry(
                date: date,
                brand: widgetCaps(payload.brand ?? widgetBrandName),
                hint: widgetCaps(payload.hint ?? "Toque para abrir"),
                updated: payload.updated ?? payload.updatedAt ?? "",
                rows: Array(rows.prefix(14))
            )
        } catch {
            return failSafeEntry()
        }
    }

    private func resolveJson(at date: Date, persist: Bool) -> String? {
        guard let defaults = UserDefaults(suiteName: appGroupId),
              let raw = defaults.string(forKey: jsonKey),
              !raw.isEmpty else { return nil }
        guard let updated = maybeRolloverWidgetJson(raw, now: date) else { return raw }
        if persist {
            defaults.set(updated, forKey: jsonKey)
            defaults.synchronize()
        }
        return updated
    }

    private func failSafeEntry(
        brand: String = widgetBrandName,
        hint: String = "Toque para abrir",
        updated: String = ""
    ) -> WisdomAppEntry {
        WisdomAppEntry(
            date: Date(),
            brand: brand,
            hint: hint,
            updated: updated,
            rows: [
                WidgetNativeRow(
                    k: "x",
                    tx: "SEM COMPROMISSOS PARA HOJE"
                )
            ]
        )
    }
}

// MARK: - Compact parser (widget pequeno 2×2)

private struct CompactWidgetSlice {
    let dayNum: String
    let weekday: String
    let dayColor: String
    let todayEvents: [WidgetNativeRow]
    let tomorrowEvent: WidgetNativeRow?
    let emptyText: String?
    let financeRows: [WidgetNativeRow]
}

private func parseCompactRows(_ rows: [WidgetNativeRow]) -> CompactWidgetSlice {
    var dayIndex = -1
    var todayHeader: WidgetNativeRow?
    var todayEvents: [WidgetNativeRow] = []
    var tomorrowEvents: [WidgetNativeRow] = []
    var emptyText: String?
    var financeRows: [WidgetNativeRow] = []

    for row in rows {
        switch row.k {
        case "h":
            dayIndex += 1
            if dayIndex == 0 { todayHeader = row }
        case "e":
            if dayIndex == 0, todayEvents.count < 2 {
                todayEvents.append(row)
            } else if dayIndex == 1, tomorrowEvents.isEmpty {
                tomorrowEvents.append(row)
            }
        case "f":
            financeRows.append(row)
        case "x", "m":
            if dayIndex == 0, todayEvents.isEmpty {
                let tx = row.tx?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !tx.isEmpty { emptyText = tx }
            }
        default:
            break
        }
    }

    let cal = Calendar.current
    let now = Date()
    let fallbackDay = "\(cal.component(.day, from: now))"

    return CompactWidgetSlice(
        dayNum: todayHeader?.dn ?? fallbackDay,
        weekday: todayHeader?.wd ?? "HOJE",
        dayColor: todayHeader?.dc ?? "#FFFF8A50",
        todayEvents: todayEvents,
        tomorrowEvent: tomorrowEvents.first,
        emptyText: todayEvents.isEmpty ? (emptyText ?? "SEM COMPROMISSOS HOJE") : nil,
        financeRows: Array(financeRows.prefix(2))
    )
}

// MARK: - Views (árvore achatada — só Text/HStack/VStack, sem sombras)

struct WisdomAppWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: WisdomAppProvider.Entry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                WisdomAppSmallWidgetView(entry: entry)
            case .systemMedium:
                WisdomAppMediumWidgetView(entry: entry)
            default:
                WisdomAppLargeWidgetView(entry: entry)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Widget pequeno — estilo Calendários iOS (dia + compromissos + amanhã).
struct WisdomAppSmallWidgetView: View {
    var entry: WisdomAppProvider.Entry
    private let tomorrowRed = Color(red: 0.94, green: 0.33, blue: 0.31)

    var body: some View {
        let slice = parseCompactRows(entry.rows)
        VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(slice.dayNum)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(colorFromHex(slice.dayColor, fallback: .white))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text(slice.weekday)
                        .font(.system(size: 9.5, weight: .bold))
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(2)
                        .minimumScaleFactor(0.65)
                }

                ForEach(Array(slice.todayEvents.enumerated()), id: \.offset) { _, row in
                    compactEventPill(row)
                }

                if let empty = slice.emptyText {
                    Text(empty)
                        .font(.system(size: 9.5))
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(2)
                }

                if let tomorrow = slice.tomorrowEvent {
                    Text("AMANHÃ")
                        .font(.system(size: 9.5, weight: .bold))
                        .textCase(.uppercase)
                        .foregroundStyle(tomorrowRed)
                        .padding(.top, 1)
                    compactEventPill(tomorrow, compact: true)
                }

                ForEach(Array(slice.financeRows.enumerated()), id: \.offset) { _, row in
                    compactFinancePill(row)
                }

                Spacer(minLength: 0)
            }
            .padding(widgetInsetSmall)
    }

    @ViewBuilder
    private func compactEventPill(_ row: WidgetNativeRow, compact: Bool = false) -> some View {
        let accent = colorFromHex(row.bc, fallback: Color(red: 0.15, green: 0.39, blue: 0.92))
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(accent)
                .frame(width: 3, height: compact ? 22 : 24)
            Text(row.sy ?? "🚔")
                .font(.system(size: compact ? 12 : 13))
            VStack(alignment: .leading, spacing: 0) {
                Text(row.ti ?? "EVENTO")
                    .font(.system(size: compact ? 10 : 10.5, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let time = row.tm, !time.isEmpty, !compact {
                    Text(time)
                        .font(.system(size: 8))
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, compact ? 3 : 4)
        .background(accent.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func compactFinancePill(_ row: WidgetNativeRow) -> some View {
        let accent = colorFromHex(row.bc, fallback: .orange)
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(accent)
                .frame(width: 3, height: 20)
            Text(row.sy ?? "💳")
                .font(.system(size: 11))
            Text(row.tx ?? "")
                .font(.system(size: 9, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(accent.opacity(0.9))
                .lineLimit(1)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(accent.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Medium parser (hoje à esquerda + próximos dias à direita)

private struct MediumFutureSection {
    let header: String
    let events: [WidgetNativeRow]
}

private struct MediumWidgetSlice {
    let todayWeekday: String
    let todayDayNum: String
    let todayDayColor: String
    let todayEvents: [WidgetNativeRow]
    let futureSections: [MediumFutureSection]
    let financeRows: [WidgetNativeRow]
}

private func parseMediumSlice(_ rows: [WidgetNativeRow]) -> MediumWidgetSlice {
    var dayIndex = -1
    var todayHeader: WidgetNativeRow?
    var todayEvents: [WidgetNativeRow] = []
    var futureSections: [MediumFutureSection] = []
    var currentHeader = ""
    var currentEvents: [WidgetNativeRow] = []
    var financeRows: [WidgetNativeRow] = []

    func flushFuture() {
        guard !currentHeader.isEmpty, !currentEvents.isEmpty else { return }
        futureSections.append(MediumFutureSection(header: currentHeader, events: currentEvents))
        currentEvents = []
    }

    for row in rows {
        switch row.k {
        case "h":
            dayIndex += 1
            if dayIndex == 0 {
                todayHeader = row
            } else if futureSections.count < 3 {
                flushFuture()
                currentHeader = row.wd ?? ""
            }
        case "e":
            if dayIndex == 0 {
                if todayEvents.count < 2 { todayEvents.append(row) }
            } else if futureSections.count < 3, currentEvents.count < 2 {
                currentEvents.append(row)
            }
        case "f":
            financeRows.append(row)
        default:
            break
        }
    }
    flushFuture()

    let cal = Calendar.current
    let now = Date()
    let fallbackDay = "\(cal.component(.day, from: now))"

    return MediumWidgetSlice(
        todayWeekday: todayHeader?.wd ?? "HOJE",
        todayDayNum: todayHeader?.dn ?? fallbackDay,
        todayDayColor: todayHeader?.dc ?? "#FFFF8A50",
        todayEvents: todayEvents,
        futureSections: futureSections,
        financeRows: Array(financeRows.prefix(2))
    )
}

struct WisdomAppMediumWidgetView: View {
    var entry: WisdomAppProvider.Entry
    private let weekdayRed = Color(red: 0.94, green: 0.33, blue: 0.31)

    var body: some View {
        let slice = parseMediumSlice(entry.rows)
        HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(slice.todayWeekday)
                        .font(.system(size: 11, weight: .bold))
                        .textCase(.uppercase)
                        .foregroundStyle(weekdayRed)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text(slice.todayDayNum)
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(colorFromHex(slice.todayDayColor, fallback: .white))
                        .lineLimit(1)
                    ForEach(Array(slice.todayEvents.enumerated()), id: \.offset) { _, row in
                        mediumEventPill(row)
                    }
                    if slice.todayEvents.isEmpty {
                        Text("SEM COMPROMISSOS HOJE")
                            .font(.system(size: 9))
                            .textCase(.uppercase)
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(slice.futureSections.enumerated()), id: \.offset) { _, section in
                        Text(section.header)
                            .font(.system(size: 8, weight: .bold))
                            .textCase(.uppercase)
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(2)
                            .minimumScaleFactor(0.65)
                        ForEach(Array(section.events.enumerated()), id: \.offset) { _, row in
                            mediumEventPill(row, compact: true)
                        }
                    }
                    if !slice.financeRows.isEmpty {
                        ForEach(Array(slice.financeRows.enumerated()), id: \.offset) { _, finance in
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(colorFromHex(finance.bc, fallback: .orange))
                                    .frame(width: 3, height: 18)
                                Text(finance.sy ?? "💳")
                                    .font(.system(size: 10))
                                Text(finance.tx ?? "")
                                    .font(.system(size: 8.5, weight: .semibold))
                                    .foregroundStyle(colorFromHex(finance.bc, fallback: .orange).opacity(0.9))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(colorFromHex(finance.bc, fallback: .orange).opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(widgetInsetMedium)
    }

    @ViewBuilder
    private func mediumEventPill(_ row: WidgetNativeRow, compact: Bool = false) -> some View {
        let accent = colorFromHex(row.bc, fallback: Color(red: 0.15, green: 0.39, blue: 0.92))
        HStack(alignment: .top, spacing: 4) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(accent)
                .frame(width: 3, height: compact ? 22 : 26)
            Text(row.sy ?? "🚔")
                .font(.system(size: compact ? 11 : 13))
            VStack(alignment: .leading, spacing: 1) {
                Text(row.ti ?? "EVENTO")
                    .font(.system(size: compact ? 9.5 : 11, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let time = row.tm, !time.isEmpty {
                    Text(time)
                        .font(.system(size: compact ? 8 : 9))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, compact ? 3 : 4)
        .background(accent.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Large (lista completa — brand + dias + eventos)

struct WisdomAppLargeWidgetView: View {
    var entry: WisdomAppProvider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 6)
                .layoutPriority(3)
            listSection
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .layoutPriority(1)
            footer
                .padding(.top, 4)
                .layoutPriority(3)
        }
        .padding(widgetInsetLarge)
    }

    private var displayBrand: String {
        let raw = entry.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = raw.isEmpty ? widgetBrandName : raw
        return widgetCaps(base)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 6) {
            widgetLogo
            Text(displayBrand)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(brandColor)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Spacer(minLength: 4)
            if !entry.updated.isEmpty {
                Text(entry.updated)
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(minHeight: 24)
    }

    @ViewBuilder
    private var widgetLogo: some View {
        if UIImage(named: "WidgetLogo") != nil {
            Image("WidgetLogo")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 22, height: 22, alignment: .center)
                .clipped()
        } else {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(brandColor)
                .frame(width: 22, height: 22, alignment: .center)
        }
    }

    @ViewBuilder
    private var listSection: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(entry.rows.enumerated()), id: \.offset) { _, row in
                    rowView(row)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
        }
    }

    @ViewBuilder
    private func rowView(_ row: WidgetNativeRow) -> some View {
        switch row.k {
        case "h":
            HStack(spacing: 6) {
                Text(row.dn ?? "")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(colorFromHex(row.dc, fallback: .white))
                Text(row.wd ?? "")
                    .font(.system(size: 9, weight: .bold))
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            .padding(.top, 3)
        case "e":
            HStack(alignment: .top, spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(colorFromHex(row.bc, fallback: .cyan))
                    .frame(width: 3, height: 26)
                Text(row.sy ?? "🚔")
                    .font(.system(size: 13))
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.ti ?? "EVENTO")
                        .font(.system(size: 11, weight: .semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let time = row.tm, !time.isEmpty {
                        Text(time)
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
            }
        case "f":
            HStack(alignment: .top, spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(colorFromHex(row.bc, fallback: .orange))
                    .frame(width: 3, height: 24)
                Text(row.sy ?? "💳")
                    .font(.system(size: 13))
                Text(row.tx ?? "")
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(colorFromHex(row.bc, fallback: .orange).opacity(0.85))
                    .lineLimit(2)
            }
        default:
            Text(row.tx ?? "")
                .font(.system(size: 10))
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(2)
        }
    }

    private var footer: some View {
        Text(entry.hint)
            .font(.system(size: 9))
            .textCase(.uppercase)
            .foregroundStyle(.white.opacity(0.35))
            .frame(maxWidth: .infinity, alignment: .center)
            .lineLimit(1)
    }
}

private func colorFromHex(_ raw: String?, fallback: Color) -> Color {
    guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
          raw.hasPrefix("#"),
          raw.count == 9 || raw.count == 7 else {
        return fallback
    }
    let hex = String(raw.dropFirst())
    var value: UInt64 = 0
    guard Scanner(string: hex).scanHexInt64(&value) else { return fallback }
    if hex.count == 8 {
        let a = Double((value >> 24) & 0xFF) / 255.0
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b, opacity: a)
    }
    let r = Double((value >> 16) & 0xFF) / 255.0
    let g = Double((value >> 8) & 0xFF) / 255.0
    let b = Double(value & 0xFF) / 255.0
    return Color(red: r, green: g, blue: b)
}

// MARK: - Widget

struct WisdomappWidget: Widget {
    let kind: String = "WisdomappWidget"

    private func openModuleUrl() -> URL {
        let defaults = UserDefaults(suiteName: appGroupId)
        var module = defaults?.integer(forKey: "widget_open_module") ?? -1
        if module < 0 || module > 9 {
            module = defaults?.integer(forKey: "home_start_mod_idx_v1") ?? 0
        }
        if module < 0 || module > 9 { module = 0 }
        return URL(string: "wisdomapp://module/\(module)")!
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WisdomAppProvider()) { entry in
            WisdomAppWidgetEntryView(entry: entry)
                .widgetFullBleedBackground(bgColor)
                .widgetURL(openModuleUrl())
        }
        .configurationDisplayName("Equipe Wisdom APP")
        .description("Calendário compacto, semana ou lista completa — escalas e compromissos.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct WisdomappWidgetBundle: WidgetBundle {
    var body: some Widget {
        WisdomappWidget()
    }
}
