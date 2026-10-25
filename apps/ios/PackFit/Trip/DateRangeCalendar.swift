import SwiftUI

/// Depart/return selection rules, kept apart from the view so they can be tested.
/// Works like Airbnb's picker: the first tap sets the depart day, the next later tap sets
/// the return day, and any tap after a full range starts a new one.
struct DateRangeSelection: Equatable {
    var start: Date?
    var end: Date?

    static let maxNights = 60

    /// Which end the next tap sets.
    var isPickingReturn: Bool { start != nil && end == nil }

    var nights: Int? {
        guard let start, let end else { return nil }
        return Calendar.current.dateComponents([.day], from: start, to: end).day
    }

    mutating func tap(_ day: Date, calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: day)
        if let start, end == nil, day > start {
            end = day
        } else {
            start = day
            end = nil
        }
    }

    /// Past days are never selectable. While picking the return day, days past the
    /// 60-night limit are blocked too; earlier days stay open because they restart the range.
    func isDisabled(_ day: Date, today: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: day)
        if day < calendar.startOfDay(for: today) { return true }
        if isPickingReturn, let start,
           let limit = calendar.date(byAdding: .day, value: Self.maxNights, to: start),
           day > limit {
            return true
        }
        return false
    }
}

/// Itinerary-style "Dates" row that drops down into a month calendar for picking the
/// depart and return days.
struct DateRangeCalendar: View {
    @Binding var selection: DateRangeSelection
    @Binding var isExpanded: Bool

    @State private var month: Date = Calendar.current.startOfMonth(.now)
    @State private var pagingForward = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let calendar = Calendar.current
    private let monthsAhead = 12

    private typealias P = Tokens.Palette
    private typealias T = Tokens.TypeScale

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(motion(Tokens.Motion.standard)) { isExpanded.toggle() }
            } label: {
                header
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 14) {
                    endpointTiles
                    monthHeader
                    weekdayRow
                    monthGrid
                    footer
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onAppear {
            if let start = selection.start { month = calendar.startOfMonth(start) }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    // MARK: Collapsed row

    private var header: some View {
        HStack(spacing: 12) {
            IconBubble(systemImage: "calendar")
            VStack(alignment: .leading, spacing: 1) {
                Text(Copy.Trip.datesField).eyebrow()
                Text(summary ?? Copy.Trip.addDates)
                    .font(T.bodyBold)
                    .foregroundStyle(summary == nil ? P.textSecondary : P.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.down")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(P.textSecondary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(isExpanded ? Copy.Trip.hideCalendarHint : Copy.Trip.showCalendarHint)
    }

    private var summary: String? {
        guard let start = selection.start else { return nil }
        guard let end = selection.end, let nights = selection.nights else {
            return "\(start.formatted(Self.dayStyle)) – \(Copy.Trip.pickReturn)"
        }
        return "\(start.formatted(Self.dayStyle)) – \(end.formatted(Self.dayStyle)) · \(Copy.Trip.nights(nights))"
    }

    // MARK: Depart / return tiles

    private var endpointTiles: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            endpointTile(Copy.Trip.departLabel, selection.start, active: !selection.isPickingReturn)
            endpointTile(Copy.Trip.returnLabel, selection.end, active: selection.isPickingReturn)
        }
    }

    private func endpointTile(_ label: String, _ date: Date?, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).eyebrow(active ? P.pink700 : P.textSecondary)
            Text(date?.formatted(Self.tileStyle) ?? Copy.Trip.addDate)
                .font(T.bodyBold)
                .foregroundStyle(date == nil ? P.textSecondary : P.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(active ? P.surface : P.pink100, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(active ? P.pink700 : .clear, lineWidth: 1.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    // MARK: Month paging

    private var monthHeader: some View {
        HStack {
            pageButton("chevron.left", Copy.Trip.previousMonth, by: -1, enabled: month > firstMonth)
            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(T.h3)
                .foregroundStyle(P.textPrimary)
                .contentTransition(.numericText())
            Spacer()
            pageButton("chevron.right", Copy.Trip.nextMonth, by: 1, enabled: month < lastMonth)
        }
    }

    private func pageButton(_ icon: String, _ label: String, by delta: Int, enabled: Bool) -> some View {
        Button {
            guard let next = calendar.date(byAdding: .month, value: delta, to: month) else { return }
            pagingForward = delta > 0
            withAnimation(motion(Tokens.Motion.standard)) { month = next }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(P.pink700)
                .frame(width: 36, height: 36)
                .background(P.pink100, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }

    private var firstMonth: Date { calendar.startOfMonth(.now) }
    private var lastMonth: Date { calendar.date(byAdding: .month, value: monthsAhead, to: firstMonth) ?? firstMonth }

    // MARK: Grid

    private var weekdayRow: some View {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        let ordered = Array(symbols[shift...] + symbols[..<shift])
        return HStack(spacing: 0) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(T.label)
                    .foregroundStyle(P.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private var monthGrid: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 4) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                GridRow {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day { dayCell(day) } else { Color.clear.frame(height: 44) }
                    }
                }
            }
        }
        .id(month)
        .transition(.push(from: pagingForward ? .trailing : .leading))
        .clipped()
    }

    /// Always six rows so the card height does not jump between months.
    private var weeks: [[Date?]] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let lead = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: lead)
        cells += range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
        cells += Array(repeating: nil, count: 42 - cells.count)
        return stride(from: 0, to: 42, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    private func dayCell(_ day: Date) -> some View {
        let isStart = selection.start.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let isEnd = selection.end.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let inRange = selection.start.flatMap { s in selection.end.map { e in day > s && day < e } } ?? false
        let disabled = selection.isDisabled(day, today: .now, calendar: calendar)
        let isToday = calendar.isDateInToday(day)
        let hasRange = selection.end != nil

        return Button {
            selection.tap(day, calendar: calendar)
        } label: {
            Text(day.formatted(.dateTime.day()))
                .font(isStart || isEnd ? T.bodyBold : T.body)
                .strikethrough(disabled && !isToday, color: P.textSecondary.opacity(0.5))
                .foregroundStyle(
                    isStart || isEnd ? P.surface
                        : disabled ? P.textSecondary.opacity(0.45)
                        : inRange ? P.pink800 : P.textPrimary
                )
                .frame(width: 40, height: 40)
                .background {
                    if isStart || isEnd {
                        Circle().fill(P.pink800)
                    } else if isToday {
                        Circle().strokeBorder(P.pink300, lineWidth: 1.5)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .background {
                    // The band joins start to end; the endpoints get half a band on the inside.
                    HStack(spacing: 0) {
                        P.pink100.opacity(inRange || (isEnd && hasRange) ? 1 : 0)
                        P.pink100.opacity(inRange || (isStart && hasRange) ? 1 : 0)
                    }
                    .frame(height: 40)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(isStart || isEnd ? .isSelected : [])
        .accessibilityValue(isStart ? Copy.Trip.departLabel : isEnd ? Copy.Trip.returnLabel : "")
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button(Copy.Trip.clearDates) {
                withAnimation(motion(Tokens.Motion.quick)) { selection = DateRangeSelection() }
            }
            .font(T.bodyBold)
            .foregroundStyle(selection.start == nil ? P.textSecondary : P.pink700)
            .underline(selection.start != nil)
            .disabled(selection.start == nil)
            Spacer()
            Text(selection.isPickingReturn ? Copy.Trip.pickReturnHint : Copy.Trip.pickDepartHint)
                .font(T.caption)
                .foregroundStyle(P.textSecondary)
                .opacity(selection.end == nil ? 1 : 0)
            Spacer()
            Button {
                withAnimation(motion(Tokens.Motion.standard)) { isExpanded = false }
            } label: {
                PillLabel(title: Copy.Trip.doneDates, systemImage: "checkmark")
            }
            .buttonStyle(.plain)
        }
    }

    private func motion(_ seconds: Double) -> Animation? {
        reduceMotion ? nil : .snappy(duration: seconds)
    }

    private static let dayStyle = Date.FormatStyle().month(.abbreviated).day()
    private static let tileStyle = Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day()
}

extension Calendar {
    func startOfMonth(_ date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? startOfDay(for: date)
    }
}
