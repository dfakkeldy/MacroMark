import SwiftUI
import MacroMarkKit

struct DailyLogView: View {
    @Binding var selectedDate: Date
    @State private var logContent: String?
    @State private var isLoading = true
    @FocusState private var focusedDateField: DailyLogDateField?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                DailyLogDateSelector(
                    selectedDate: $selectedDate,
                    focusedField: $focusedDateField
                )

                DailyLogBody(isLoading: isLoading, logContent: logContent) {
                    focusedDateField = nil
                }
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle("Daily Log")
        .task(id: selectedDate) {
            await loadLog(for: selectedDate)
        }
    }

    private func loadLog(for date: Date) async {
        isLoading = true
        var content = await WatchConnectivityProvider.shared.fetchDailyFile(for: date)
        guard !Task.isCancelled else { return }
        
        let pending = LocalStore.shared.pendingNotes.filter { note in
            DaySelection.contains(note.timestamp, inSelectedDay: date)
        }
        if !pending.isEmpty {
            content += "\n\n**Pending Offline Notes:**\n"
            for note in pending {
                let timeString = note.timestamp.formatted(date: .omitted, time: .shortened)
                content += "\n\n\(timeString)\n\n\(note.text)\n\n"
            }
        }

        let pendingAudio = LocalStore.shared.pendingAudio.filter { audio in
            DaySelection.contains(audio.timestamp, inSelectedDay: date)
        }
        if !pendingAudio.isEmpty {
            content += "\n\n**Pending Offline Recordings:**\n"
            for audio in pendingAudio {
                let timeString = audio.timestamp.formatted(date: .omitted, time: .shortened)
                content += "\n\n\(timeString)\n\nAudio recording waiting to sync.\n\n"
            }
        }
        
        guard !Task.isCancelled else { return }
        logContent = content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : content
        isLoading = false
    }
}

private enum DailyLogDateField: Hashable {
    case day
    case month
    case year
}

private struct DailyLogBody: View {
    let isLoading: Bool
    let logContent: String?
    let reclaimCrownFocus: () -> Void

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Fetching from iPhone...")
                    .padding()
            } else if let logContent = logContent {
                Text(logContent)
                    .padding()
            } else {
                Text("No content found.")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .onTapGesture(perform: reclaimCrownFocus)
    }
}

private struct DailyLogDateComponentButton: View {
    let value: String
    let label: String
    let field: DailyLogDateField
    let minWidth: CGFloat
    @FocusState.Binding var focusedField: DailyLogDateField?

    private var isFocused: Bool {
        focusedField == field
    }

    var body: some View {
        Button {
            focusedField = field
        } label: {
            DailyLogDateComponentLabel(
                value: value,
                minWidth: minWidth,
                isFocused: isFocused
            )
        }
        .buttonStyle(.plain)
        .focusable(interactions: .edit)
        .focused($focusedField, equals: field)
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .accessibilityHint("Tap to edit with the Digital Crown.")
    }
}

private struct DailyLogDateComponentLabel: View {
    let value: String
    let minWidth: CGFloat
    let isFocused: Bool

    private var fillColor: Color {
        isFocused ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.14)
    }

    private var strokeColor: Color {
        isFocused ? Color.accentColor : Color.clear
    }

    var body: some View {
        Text(value)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .monospacedDigit()
            .frame(minWidth: minWidth, minHeight: 30)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(fillColor)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            }
    }
}

private struct DailyLogDateSelector: View {
    @Binding var selectedDate: Date
    @FocusState.Binding var focusedField: DailyLogDateField?

    @State private var dayValue = 1.0
    @State private var monthValue = 1.0
    @State private var yearValue = 2_026.0
    @State private var isSyncingDateComponents = false

    private let calendar = Calendar.autoupdatingCurrent
    private let yearRange = 2_000.0...2_100.0

    var body: some View {
        HStack(spacing: 4) {
            dateComponentButton(
                value: day,
                label: "Day",
                field: .day,
                minWidth: 34
            )
            .digitalCrownRotation(
                $dayValue,
                from: 1,
                through: Double(daysInSelectedMonth),
                by: 1,
                sensitivity: .medium,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )

            dateComponentButton(
                value: monthName,
                label: "Month",
                field: .month,
                minWidth: 48
            )
            .digitalCrownRotation(
                $monthValue,
                from: 1,
                through: 12,
                by: 1,
                sensitivity: .medium,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )

            dateComponentButton(
                value: year,
                label: "Year",
                field: .year,
                minWidth: 52
            )
            .digitalCrownRotation(
                $yearValue,
                from: yearRange.lowerBound,
                through: yearRange.upperBound,
                by: 1,
                sensitivity: .medium,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .onAppear(perform: syncValuesFromDate)
        .onChange(of: selectedDate) { _, _ in
            syncValuesFromDate()
        }
        .onChange(of: dayValue) { _, _ in
            updateSelectedDate()
        }
        .onChange(of: monthValue) { _, _ in
            updateSelectedDate()
        }
        .onChange(of: yearValue) { _, _ in
            updateSelectedDate()
        }
    }

    private var day: String {
        Int(dayValue.rounded()).formatted(.number.grouping(.never))
    }

    private var year: String {
        Int(yearValue.rounded()).formatted(.number.grouping(.never))
    }

    private var monthName: String {
        guard let monthDate = calendar.date(from: DateComponents(month: Int(monthValue.rounded()))) else {
            return Int(monthValue.rounded()).formatted(.number.grouping(.never))
        }
        return monthDate.formatted(.dateTime.month(.abbreviated))
    }

    private var daysInSelectedMonth: Int {
        let components = DateComponents(
            year: Int(yearValue.rounded()),
            month: Int(monthValue.rounded())
        )
        guard
            let date = calendar.date(from: components),
            let range = calendar.range(of: .day, in: .month, for: date)
        else {
            return 31
        }
        return range.count
    }

    private func dateComponentButton(
        value: String,
        label: String,
        field: DailyLogDateField,
        minWidth: CGFloat
    ) -> some View {
        DailyLogDateComponentButton(
            value: value,
            label: label,
            field: field,
            minWidth: minWidth,
            focusedField: $focusedField
        )
    }

    private func syncValuesFromDate() {
        isSyncingDateComponents = true
        let components = calendar.dateComponents([.day, .month, .year], from: selectedDate)
        dayValue = Double(components.day ?? 1)
        monthValue = Double(components.month ?? 1)
        yearValue = Double(components.year ?? Int(yearRange.lowerBound))
        isSyncingDateComponents = false
    }

    private func updateSelectedDate() {
        guard !isSyncingDateComponents else { return }

        let roundedMonth = Int(monthValue.rounded()).clamped(to: 1...12)
        let roundedYear = Int(yearValue.rounded()).clamped(to: Int(yearRange.lowerBound)...Int(yearRange.upperBound))
        let roundedDay = Int(dayValue.rounded()).clamped(to: 1...daysInSelectedMonth)

        let existingTime = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: selectedDate)
        let updatedComponents = DateComponents(
            calendar: calendar,
            year: roundedYear,
            month: roundedMonth,
            day: roundedDay,
            hour: existingTime.hour,
            minute: existingTime.minute,
            second: existingTime.second,
            nanosecond: existingTime.nanosecond
        )

        guard let updatedDate = calendar.date(from: updatedComponents), updatedDate != selectedDate else {
            return
        }

        if roundedDay != Int(dayValue.rounded()) {
            dayValue = Double(roundedDay)
        }
        selectedDate = updatedDate
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

#Preview {
    DailyLogView(selectedDate: .constant(Date()))
}
