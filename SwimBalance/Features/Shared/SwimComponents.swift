import SwiftUI

// Shared building blocks so every screen reads as one system: white background,
// system type at standard sizes, black and gray text, and the deep blue accent
// reserved for the focus stroke.

/// Level-2 information: a short fact in a capsule (time, distance, result, change).
/// Neutral for plain facts; accent for anything about the goal. `showsChevron`
/// marks a chip that can be tapped to change.
struct MetaChip: View {
    enum Style { case neutral, accent }

    let systemImage: String
    let text: String
    var style: Style = .neutral
    var showsChevron = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
            Text(text)
                .fontWeight(.medium)
                .monospacedDigit()
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .opacity(0.6)
            }
        }
        .font(.subheadline)
        .foregroundStyle(style == .accent ? Color.swimDeep : Color.secondary)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(style == .accent ? Color.swimDeep.opacity(0.12) : Color(.tertiarySystemFill))
        )
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// Level-4 information: the one takeaway inside a card, set on a lighter inner panel.
struct Callout: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.swimDeep)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.subheadline)
        .padding(14)
        .background(Color(.systemBackground).opacity(0.75),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Section title with optional trailing detail.
struct SectionHeader: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// One headline number with its label and unit.
struct MetricView: View {
    let label: String
    let value: String
    let unit: String
    var accent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                Text(unit)
                    .font(.subheadline)
                    .foregroundStyle(accent ? Color.swimDeep : Color.secondary)
            }
            .foregroundStyle(accent ? Color.swimDeep : Color.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Stroke allocation

/// One stroke's share of a distance.
struct StrokeShare: Identifiable {
    let stroke: StrokeStyle
    let meters: Int
    let percent: Int

    var id: StrokeStyle { stroke }

    /// Focus stroke first; unused strokes omitted; percentages always sum to 100.
    static func shares(_ metersByStroke: [StrokeStyle: Int], focus: StrokeStyle) -> [StrokeShare] {
        let total = metersByStroke.values.reduce(0, +)
        guard total > 0 else { return [] }

        let order = [focus] + StrokeStyle.allCases.filter { $0 != focus }
        let meters: [(stroke: StrokeStyle, meters: Int)] = order.compactMap { stroke in
            let distance = metersByStroke[stroke] ?? 0
            return distance > 0 ? (stroke, distance) : nil
        }

        // Largest-remainder rounding keeps the displayed percentages honest.
        let exact = meters.map { Double($0.meters) * 100 / Double(total) }
        let floors = exact.map { Int($0.rounded(.down)) }
        let byRemainder = exact.indices.sorted {
            exact[$0] - Double(floors[$0]) > exact[$1] - Double(floors[$1])
        }
        var percents = floors
        for index in byRemainder.prefix(100 - floors.reduce(0, +)) {
            percents[index] += 1
        }

        return meters.indices.map {
            StrokeShare(stroke: meters[$0].stroke, meters: meters[$0].meters, percent: percents[$0])
        }
    }

    static func shares(for sets: [TrainingSet], focus: StrokeStyle) -> [StrokeShare] {
        var byStroke: [StrokeStyle: Int] = [:]
        for set in sets { byStroke[set.stroke, default: 0] += set.totalDistanceMeters }
        return shares(byStroke, focus: focus)
    }
}

/// Compact horizontal bar of distance per stroke, with an optional legend.
struct StrokeAllocationView: View {
    let shares: [StrokeShare]
    let focus: StrokeStyle
    var showsLegend = true

    @Environment(\.distanceStyle) private var distance

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StrokeAllocationBar(shares: shares, focus: focus)
            if showsLegend {
                VStack(spacing: 8) {
                    ForEach(shares) { share in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(share.stroke.allocationColor(focus: focus))
                                .frame(width: 8, height: 8)
                            Text(share.stroke.rawValue)
                            Spacer()
                            Text(distance.format(share.meters))
                                .monospacedDigit()
                            Text("\(share.percent)%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 40, alignment: .trailing)
                        }
                        .font(.subheadline)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

private struct StrokeAllocationBar: View {
    let shares: [StrokeShare]
    let focus: StrokeStyle

    private let gap: CGFloat = 2

    private var totalMeters: Int {
        max(shares.reduce(0) { $0 + $1.meters }, 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let gaps = gap * CGFloat(max(shares.count - 1, 0))
            let available = max(proxy.size.width - gaps, 0)
            HStack(spacing: gap) {
                ForEach(shares) { share in
                    Rectangle()
                        .fill(share.stroke.allocationColor(focus: focus))
                        .frame(width: available * CGFloat(share.meters) / CGFloat(totalMeters))
                }
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

// MARK: - Workout sets

/// Stroke pictogram at a fixed size.
struct StrokeIcon: View {
    let stroke: StrokeStyle
    var size: CGFloat = 28

    var body: some View {
        stroke.icon
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A workout set with its phase symbol (warm-up, practice, main, cool-down).
/// A highlighted set gets a tinted row. On a past day, `swum` adds a row of
/// lane-rope beads — one per pool length — filled for lengths swum.
struct SetRow: View {
    let set: TrainingSet
    var isHighlighted = false
    var showsEstimate = false
    var swum: Int? = nil
    var isFocusStroke = false

    @Environment(\.distanceStyle) private var distance
    @State private var showsLengths = false

    /// Beads read well up to about a dozen; longer sets show a line until tapped.
    private var isLong: Bool {
        Int((Double(self.set.totalDistanceMeters) / Double(max(distance.poolLength, 1))).rounded()) > 12
    }

    private var detail: String {
        let stroke = self.set.stroke.rawValue
        return self.set.repetitions > 1
            ? "\(stroke) · \(distance.repeats(self.set.repetitions, of: self.set.distanceMeters))"
            : stroke
    }

    private var isComplete: Bool { (swum ?? 0) >= self.set.totalDistanceMeters }

    var body: some View {
        HStack(alignment: swum == nil ? .center : .top, spacing: 12) {
            Image(systemName: set.phase.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(set.phase.color)
                .frame(width: 32, height: 32)
                .background(Circle().fill(set.phase.color.opacity(0.18)))
                .padding(.top, swum == nil ? 0 : 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(set.title)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let swum {
                    if isLong && !showsLengths {
                        HStack(spacing: 8) {
                            ProgressLine(fraction: Double(swum) / Double(max(set.totalDistanceMeters, 1)),
                                         isFocus: isFocusStroke)
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.top, 6)
                    } else {
                        LengthBeads(planned: set.totalDistanceMeters, swum: swum,
                                    poolLength: distance.poolLength, isFocusStroke: isFocusStroke)
                            .padding(.top, 4)
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if let swum {
                    Image(systemName: isComplete ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(isComplete ? Color.swimDeep : Color.secondary)
                    Text(isComplete ? distance.format(set.totalDistanceMeters)
                                    : "\(distance.value(swum)) / \(distance.format(set.totalDistanceMeters))")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    Text(distance.format(set.totalDistanceMeters))
                        .monospacedDigit()
                    if showsEstimate {
                        Text("\(max(Int(SwimPace.estimatedMinutes(for: set).rounded()), 1)) min")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            guard swum != nil, isLong else { return }
            withAnimation(.easeInOut(duration: 0.25)) { showsLengths.toggle() }
        }
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.swimDeep.opacity(0.10))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(swum.map { isComplete ? "Done" : "\(distance.format($0)) of \(distance.format(set.totalDistanceMeters))" }
                            ?? (isHighlighted ? "Core goal" : ""))
    }
}

/// Sets separated by hairlines. Only the focus-stroke practice set is tinted,
/// and only when other sets use a different stroke. Pass `swumBySet` on a past
/// day to show what was actually swum, set by set.
struct SetList: View {
    let sets: [TrainingSet]
    let focus: StrokeStyle
    var showsEstimate = false
    var swumBySet: [UUID: Int]? = nil

    private func isHighlighted(_ set: TrainingSet) -> Bool {
        set.phase == .practice && set.stroke == focus && sets.contains { $0.stroke != focus }
    }

    var body: some View {
        // Rows are separated by space, not hairlines, so no row looks set apart
        // except the one that is meant to (the tinted focus practice).
        VStack(spacing: 4) {
            ForEach(sets) { set in
                SetRow(set: set, isHighlighted: isHighlighted(set), showsEstimate: showsEstimate,
                       swum: swumBySet.map { $0[set.id] ?? 0 }, isFocusStroke: set.stroke == focus)
            }
        }
    }
}

// MARK: - Beads

/// One colored-pencil lane-rope bead.
struct Bead: View {
    enum Kind { case focus, other, empty }

    let kind: Kind
    var size: CGFloat = 10

    var body: some View {
        Image(kind == .focus ? "Bead-blue" : (kind == .other ? "Bead-sand" : "Bead-empty"))
            .resizable()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// One bead per pool length of a set; filled for lengths swum, hollow for the rest.
struct LengthBeads: View {
    let planned: Int
    let swum: Int
    let poolLength: Int
    let isFocusStroke: Bool

    private var lengths: Int { max(Int((Double(planned) / Double(max(poolLength, 1))).rounded()), 1) }
    private var swumLengths: Int { min(Int((Double(swum) / Double(max(poolLength, 1))).rounded()), lengths) }

    var body: some View {
        WrapLayout(spacing: 3) {
            ForEach(0..<lengths, id: \.self) { index in
                Bead(kind: index < swumLengths ? (isFocusStroke ? .focus : .other) : .empty, size: 10)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Minimal wrapping layout (beads, chips).
struct WrapLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? (rows.map(\.width).max() ?? 0), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let last = rows[rows.count - 1]
            if !last.indices.isEmpty, last.width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

/// Small round arrow button used to page weeks (Swim) and months (History).
struct SoftArrowButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color(.tertiarySystemFill)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Seven weekday buttons to choose swim days directly. At least one stays selected.
struct WeekdayPicker: View {
    @Binding var selection: Set<Int>
    /// False shows the same row read-only (e.g. on the result page).
    var isEditable = true

    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 0) {
            ForEach(calendar.orderedWeekdays, id: \.self) { weekday in
                let isOn = selection.contains(weekday)
                Button {
                    toggle(weekday)
                } label: {
                    Text(calendar.veryShortWeekdaySymbols[weekday - 1])
                        .font(.body.weight(isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? Color(.systemBackground) : Color.primary)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(isOn ? Color.swimDeep : Color(.tertiarySystemFill)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .allowsHitTesting(isEditable)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(calendar.weekdayName(weekday))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func toggle(_ weekday: Int) {
        withAnimation(.snappy) {
            if selection.contains(weekday) {
                if selection.count > 1 { selection.remove(weekday) }
            } else {
                selection.insert(weekday)
            }
        }
    }
}

/// A month laid out in weekday columns; each day's look comes from `cell`.
struct MonthGrid<Cell: View>: View {
    let month: Date
    @ViewBuilder let cell: (Date) -> Cell

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    /// Padded to six weeks so every month has the same height.
    private var paddedDays: [Date?] {
        let days = calendar.monthGrid(containing: month)
        return days + Array(repeating: nil, count: max(42 - days.count, 0))
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(calendar.orderedWeekdays, id: \.self) { weekday in
                    Text(calendar.veryShortWeekdaySymbols[weekday - 1])
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
            }
            Divider()
                .padding(.horizontal, 8)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(paddedDays.enumerated()), id: \.offset) { _, day in
                    if let day {
                        cell(day)
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
        }
    }
}

/// Goal marker shared by the History calendar, its legend and the Swim tab.
/// Water drops fill up with how a swim went: full = both goals met,
/// half = one met, empty = neither. Gray waves = planned but not swum.
struct GoalMarker: View {
    enum Kind { case outcome(GoalOutcome), missed, extra }

    let kind: Kind
    var size: CGFloat = 12

    private var symbol: String {
        switch kind {
        case .outcome(.allMet): "drop.fill"
        case .outcome(.partlyMet): "drop.halffull"
        case .outcome(.notMet): "drop"
        case .missed: "water.waves"
        case .extra: "drop.fill"
        }
    }

    private var color: Color {
        switch kind {
        case .outcome(.allMet), .outcome(.partlyMet): Color.swimDeep
        case .outcome(.notMet): Color.secondary
        case .missed: Color(.systemGray3)
        case .extra: Color(.systemGray4)
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size + 4, height: size + 2)
            .accessibilityHidden(true)
    }
}

// MARK: - Day markers (Swim week strip and History calendar share this logic)

/// Past days only: how a planned swim went, or that it was missed.
/// Today, future days and unplanned days without a swim return nil.
func dayMarker(for day: Date, session: ScheduledSession?, workouts: [SwimmingWorkout],
               calendar: Calendar = .current) -> GoalMarker.Kind? {
    guard day < calendar.startOfDay(for: .now) else { return nil }
    let workout = workouts.first { calendar.isDate($0.date, inSameDayAs: day) }
    guard let session else { return workout == nil ? nil : .extra }
    guard let workout else { return .missed }
    return WorkoutReview(workout: workout, session: session).outcome.map { .outcome($0) } ?? .extra
}

/// The small mark under a day number. Every day reserves the same space so
/// rows stay aligned. Past: a water-drop goal marker. Today/future swim day: waves.
struct DayMarker: View {
    let kind: GoalMarker.Kind?
    let isUpcomingSwim: Bool

    var body: some View {
        Group {
            if let kind {
                GoalMarker(kind: kind, size: 10)
            } else if isUpcomingSwim {
                Image(systemName: "water.waves")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.7))
            } else {
                Color.clear
            }
        }
        .frame(width: 16, height: 12)
    }
}


// MARK: - Pace clock

/// Time picker drawn like a pool pace clock: a light face with minute ticks,
/// a progress arc and a colored-pencil bead as the handle. One lap is 60
/// minutes; going past the top continues into a second, deeper lap.
/// Snaps to `step` minutes with a light tick of haptics.
struct ClockDial: View {
    @Binding var minutes: Int
    let range: ClosedRange<Int>
    let step: Int
    var size: CGFloat = 280

    private let arcWidth: CGFloat = 14

    private var readout: String {
        minutes < 60 ? "\(minutes)" : (minutes % 60 == 0 ? "\(minutes / 60)" : "\(minutes / 60):\(String(format: "%02d", minutes % 60))")
    }

    private var readoutUnit: String {
        minutes < 60 ? "min" : (minutes % 60 == 0 ? (minutes == 60 ? "hour" : "hours") : "h : min")
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let arcRadius = side / 2 - arcWidth / 2 - 4
            let faceRadius = arcRadius - arcWidth / 2 - 6
            let angle = Angle.degrees(Double(minutes % 60) / 60 * 360 - 90)
            let firstLap = min(Double(minutes), 60) / 60
            let secondLap = max(Double(minutes) - 60, 0) / 60

            ZStack {
                // Face
                Circle()
                    .fill(Color.swimMist)
                    .frame(width: faceRadius * 2, height: faceRadius * 2)
                ForEach(0..<60, id: \.self) { tick in
                    let isMajor = tick % 5 == 0
                    Capsule()
                        .fill(isMajor ? Color(.systemGray2) : Color(.systemGray4))
                        .frame(width: isMajor ? 2 : 1, height: isMajor ? 9 : 5)
                        .offset(y: -(faceRadius - (isMajor ? 10 : 8)))
                        .rotationEffect(.degrees(Double(tick) * 6))
                }
                ForEach([0, 15, 30, 45], id: \.self) { mark in
                    let theta = Double(mark) * 6 * .pi / 180
                    let r = faceRadius - 30
                    Text("\(mark)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .position(x: center.x + sin(theta) * r, y: center.y - cos(theta) * r)
                }
                // Track and laps
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: arcWidth)
                    .frame(width: arcRadius * 2, height: arcRadius * 2)
                Circle()
                    .trim(from: 0, to: firstLap)
                    .stroke(secondLap > 0 ? Color.swimDeep.opacity(0.35) : Color.swimDeep,
                            style: SwiftUI.StrokeStyle(lineWidth: arcWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: arcRadius * 2, height: arcRadius * 2)
                if secondLap > 0 {
                    Circle()
                        .trim(from: 0, to: secondLap)
                        .stroke(Color.swimDeep, style: SwiftUI.StrokeStyle(lineWidth: arcWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: arcRadius * 2, height: arcRadius * 2)
                }
                // Handle: a pencil bead with a light centre
                ZStack {
                    Image("Bead-blue").resizable()
                    Circle().fill(.white).frame(width: 8, height: 8)
                }
                .frame(width: arcWidth + 16, height: arcWidth + 16)
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                .position(x: center.x + cos(angle.radians) * arcRadius,
                          y: center.y + sin(angle.radians) * arcRadius)
                // Readout
                VStack(spacing: 2) {
                    Text(readout)
                        .font(.system(size: 56, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(minutes)))
                    Text(readoutUnit)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .position(center)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in update(to: value.location, center: center) }
            )
        }
        // A fixed size gives the dial a real height, so sheets can fit to it.
        .frame(width: size, height: size)
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.selection, trigger: minutes)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time per swim")
        .accessibilityValue("\(minutes) minutes")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: minutes = min(minutes + step, range.upperBound)
            case .decrement: minutes = max(minutes - step, range.lowerBound)
            @unknown default: break
            }
        }
    }

    /// Converts the touch angle to minutes on the current lap, picking whichever
    /// lap keeps the value continuous, then snaps and clamps.
    private func update(to location: CGPoint, center: CGPoint) {
        var degrees = atan2(location.y - center.y, location.x - center.x) * 180 / .pi + 90
        if degrees < 0 { degrees += 360 }
        let lapMinutes = degrees / 6
        let nearest = [lapMinutes, lapMinutes + 60].min { abs($0 - Double(minutes)) < abs($1 - Double(minutes)) } ?? lapMinutes
        let snapped = Int((nearest / Double(step)).rounded()) * step
        let clamped = min(max(snapped, range.lowerBound), range.upperBound)
        if clamped != minutes {
            withAnimation(.snappy(duration: 0.15)) { minutes = clamped }
        }
    }
}


// MARK: - Progress

/// A thin rounded progress line for a set or a week.
struct ProgressLine: View {
    let fraction: Double
    var isFocus = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.swimDeep.opacity(0.1))
                Capsule()
                    .fill(isFocus ? Color.swimDeep : Color.swimDeep.opacity(0.45))
                    .frame(width: max(proxy.size.width * min(max(fraction, 0), 1), fraction > 0 ? 6 : 0))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

// MARK: - Stage bar

/// The swim as one bar of coloured stages in order, each as wide as its time.
/// The colours match the icons in the set list, which works as the key — so
/// no label ever has to squeeze into a short stage. On a past day each stage
/// fills as far as it was swum.
struct StageBar: View {
    let sets: [TrainingSet]
    let focus: StrokeStyle
    /// nil ahead of the day; on a past day, meters swum per set (empty when missed).
    var swumBySet: [UUID: Int]? = nil
    /// The session's length, written at the end of the bar.
    var totalMinutes: Int? = nil

    @Environment(\.distanceStyle) private var distance

    var body: some View {
        let minutes = sets.map { max(SwimPace.estimatedMinutes(for: $0), 1) }
        let total = minutes.reduce(0, +)
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { proxy in
                let gap: CGFloat = 3
                let width = max(proxy.size.width - gap * CGFloat(max(sets.count - 1, 0)), 0)
                HStack(spacing: gap) {
                    ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                        let segment = total > 0 ? max(width * CGFloat(minutes[index] / total), 0) : 0
                        let done = swumBySet.map { Double($0[set.id] ?? 0) / Double(max(set.totalDistanceMeters, 1)) } ?? 1
                        ZStack(alignment: .leading) {
                            Capsule().fill(set.phase.color.opacity(0.2))
                            Capsule()
                                .fill(set.phase.color)
                                .frame(width: segment * CGFloat(min(max(done, 0), 1)))
                        }
                        .frame(width: segment)
                    }
                }
            }
            .frame(height: 14)
        }
        .animation(.easeInOut(duration: 0.3), value: total)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sets.map { "\($0.title) \(distance.format($0.totalDistanceMeters))" }.joined(separator: ", then "))
    }
}

/// The key to the stage bar, right under it: each colour named, with its time.
struct PhaseLegend: View {
    let sets: [TrainingSet]

    private func name(_ set: TrainingSet) -> String {
        switch set.phase {
        case .warmUp: "Warm-up"
        case .coolDown: "Cool-down"
        case .main: "Main set"
        default: set.title
        }
    }

    var body: some View {
        WrapLayout(spacing: 14) {
            ForEach(sets) { set in
                HStack(spacing: 6) {
                    Circle()
                        .fill(set.phase.color)
                        .frame(width: 9, height: 9)
                    Text(name(set))
                        .foregroundStyle(set.phase == .practice ? Color.swimDeep : Color.primary)
                        .fontWeight(set.phase == .practice ? .semibold : .regular)
                    Text("\(max(Int(SwimPace.estimatedMinutes(for: set).rounded()), 1))′")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .font(.footnote)
                .fixedSize()
            }
        }
        .accessibilityHidden(true)
    }
}

/// Distance per stroke for the whole swim, with the hand-drawn stroke icons.
/// On a past day it reads swum / planned.
struct StrokeTotals: View {
    let sets: [TrainingSet]
    let focus: StrokeStyle
    var swum: [StrokeStyle: Int]? = nil

    @Environment(\.distanceStyle) private var distance

    var body: some View {
        WrapLayout(spacing: 18) {
            ForEach(StrokeShare.shares(for: sets, focus: focus)) { share in
                HStack(spacing: 6) {
                    StrokeIcon(stroke: share.stroke, size: 22)
                        .foregroundStyle(share.stroke == focus ? Color.swimDeep : Color.secondary)
                    Text(share.stroke.rawValue)
                    Text(swum.map { "\(distance.value($0[share.stroke] ?? 0)) / \(distance.format(share.meters))" }
                         ?? distance.format(share.meters))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .font(.subheadline)
                .fixedSize()
            }
        }
    }
}

// MARK: - Past swim

/// Everything about a finished swim, shared by the Swim tab and History:
/// conclusion and next step, the stages, the two goals, how it felt, the sets.
struct PastSwimSections: View {
    let review: WorkoutReview

    @Environment(\.distanceStyle) private var distance
    @Environment(\.reflections) private var reflections

    var body: some View {
        let reflection = reflections.reflection(on: review.workout.date)
        VStack(alignment: .leading, spacing: 32) {
            if let plan = review.session?.plan {
                VStack(alignment: .leading, spacing: 16) {
                    if let verdict = Coach.verdict(for: review, reflection: reflection, distance: distance) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(verdict.headline)
                                .font(.headline)
                            Text(verdict.nextStep)
                                .font(.subheadline)
                                .foregroundStyle(Color.swimDeep)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        StageBar(sets: plan.sets, focus: review.focusStroke, swumBySet: review.metersBySet)
                        PhaseLegend(sets: plan.sets)
                        Divider()
                        StrokeTotals(sets: plan.sets, focus: review.focusStroke,
                                     swum: review.workout.strokeMeters)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .sectionCard()
            }

            ReflectionCard(review: review, reflection: reflection) { reflections.save($0, review.workout.date) }

            if let plan = review.session?.plan {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Your swim")
                    SetList(sets: plan.sets, focus: review.focusStroke, swumBySet: review.metersBySet)
                        .sectionCard(padding: 12)
                }
            }
        }
    }
}

/// Two quick questions (three if the swim fell short). The answers feed the
/// next-step line above and History's patterns.
struct ReflectionCard: View {
    let review: WorkoutReview
    let reflection: SwimReflection
    let onChange: (SwimReflection) -> Void

    private var fellShort: Bool { review.distanceMet == false || review.focusMet == false }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "How it went")
            VStack(alignment: .leading, spacing: 16) {
                question("How tiring was it?", options: SwimReflection.Effort.allCases, title: \.title,
                         selection: reflection.effort) { var r = reflection; r.effort = $0; onChange(r) }
                question("\(review.focusStroke.rawValue) form", options: SwimReflection.Technique.allCases,
                         title: \.title, selection: reflection.technique) { var r = reflection; r.technique = $0; onChange(r) }
                if fellShort {
                    question("Why did it stop short?", options: SwimReflection.Shortfall.allCases, title: \.title,
                             selection: reflection.shortfall) { var r = reflection; r.shortfall = $0; onChange(r) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .sectionCard()
        }
    }

    private func question<Option: Hashable>(_ prompt: String, options: [Option], title: KeyPath<Option, String>,
                                            selection: Option?, choose: @escaping (Option?) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(prompt)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            WrapLayout(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    let isOn = option == selection
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { choose(isOn ? nil : option) }
                    } label: {
                        Text(option[keyPath: title])
                            .font(.subheadline.weight(isOn ? .semibold : .regular))
                            .foregroundStyle(isOn ? Color.white : Color.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(isOn ? Color.swimDeep : Color(.systemBackground).opacity(0.8)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}
