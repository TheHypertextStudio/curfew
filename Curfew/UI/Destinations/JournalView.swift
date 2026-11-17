import AppKit
import CurfewKit
import SwiftUI
import UniformTypeIdentifiers

/// The Journal destination: what the person did, scoped by a week, month or
/// year range in the window toolbar. When they stopped against curfew,
/// whether they did the one thing, what extra time they took and why, and
/// how ready they felt, from the per-day records CurfewKit builds.
struct JournalView: View {
    @Environment(CurfewAppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var range: JournalRange
    /// A date inside the shown period; `nil` follows today.
    @State private var anchor: Date?
    @State private var records: [JournalDayRecord] = []
    @State private var reflections: [Reflection] = []
    @State private var today: Date?
    @State private var expanded: Set<Date>
    @State private var showsAll = false
    @State private var isEditingPrompts = false
    private let initiallyActive: Date?

    init(
        range: JournalRange = .month,
        anchor: Date? = nil,
        expanded: Set<Date> = [],
        initiallyActive: Date? = nil
    ) {
        _range = State(initialValue: range)
        _anchor = State(initialValue: anchor)
        _expanded = State(initialValue: expanded)
        self.initiallyActive = initiallyActive
    }

    private var calendar: Calendar {
        .current
    }

    private var format: JournalFormat {
        JournalFormat(calendar: calendar)
    }

    private var workingWeekdays: Set<Weekday> {
        let rules = model.settings.schedule.rules
        return Set(Weekday.allCases.filter { rules[$0]?.isDayOff == false })
    }

    var body: some View {
        let today = today ?? Date()
        let period = JournalPeriod.containing(anchor ?? today, range: range, calendar: calendar)
        let screen = JournalScreen(
            records: records,
            reflections: reflections,
            period: period,
            today: today,
            workingWeekdays: workingWeekdays,
            format: format
        )
        ScrollView {
            JournalPage(
                screen: screen,
                format: format,
                expanded: $expanded,
                showsAll: $showsAll,
                initiallyActive: initiallyActive,
                editPrompts: { isEditingPrompts = true }
            )
            .id(period)
            .transition(.opacity)
            .frame(maxWidth: JournalStyle.contentWidth, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 64)
            .frame(maxWidth: .infinity)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: period)
        .background(JournalStyle.page.ignoresSafeArea())
        .toolbar { toolbar(screen: screen) }
        .background(JournalRefreshTrigger(reload: reload))
        .onAppear(perform: reload)
        .sheet(isPresented: $isEditingPrompts) {
            JournalPromptsSheet()
                .environment(model)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func toolbar(screen: JournalScreen) -> some ToolbarContent {
        let noun = screen.period.range.rawValue
        ToolbarItem(placement: .navigation) {
            ControlGroup {
                Button { step(-1, from: screen.period) } label: {
                    Label("Previous \(noun)", systemImage: "chevron.left")
                }
                .disabled(!screen.canGoBack)
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .help("Previous \(noun)")
                Button { step(1, from: screen.period) } label: {
                    Label("Next \(noun)", systemImage: "chevron.right")
                }
                .disabled(!screen.canGoForward)
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .help("Next \(noun)")
            }
            .disabled(screen.state == .noHistory)
        }
        ToolbarItem(placement: .principal) {
            Picker("Range", selection: Binding(
                get: { range },
                set: { change(to: $0, from: screen.period) }
            )) {
                Text("Week").tag(JournalRange.week)
                Text("Month").tag(JournalRange.month)
                Text("Year").tag(JournalRange.year)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .disabled(screen.state == .noHistory)
            .help("Show a week, a month or a year")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { isEditingPrompts = true } label: {
                Label("Edit prompts", systemImage: "text.bubble")
            }
            .accessibilityIdentifier("journal-edit-prompts")
            .help("Edit the questions Curfew asks in the morning and evening")
            Menu {
                Button("Reflections as Markdown…") { export(.markdown, period: screen.period) }
                Button("Reflections as JSON…") { export(.json, period: screen.period) }
                Button("Activity as CSV…") { export(.csv, period: screen.period) }
                Divider()
                Button("Copy reflections") { copyReflections(period: screen.period) }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export \(screen.label)")
        }
    }

    // MARK: - Navigation

    private func step(_ count: Int, from period: JournalPeriod) {
        let target = period.offset(by: count, calendar: calendar)
        let today = today ?? model.currentTime
        anchor = target.interval.contains(today) ? nil : target.interval.start
        expanded = []
        showsAll = false
    }

    /// Finer ranges land on the latest part of the shown period; coarser
    /// ranges keep the period that contains it.
    private func change(to newRange: JournalRange, from period: JournalPeriod) {
        guard newRange != range else { return }
        let order: [JournalRange] = [.week, .month, .year]
        let today = calendar.startOfDay(for: today ?? model.currentTime)
        let finer = (order.firstIndex(of: newRange) ?? 0) < (order.firstIndex(of: range) ?? 0)
        if finer {
            let last = calendar.date(byAdding: .day, value: -1, to: period.interval.end)
                ?? period.interval.start
            let target = min(last, today)
            anchor = target == today ? nil : target
        } else if anchor != nil {
            anchor = period.interval.start
        }
        range = newRange
        expanded = []
        showsAll = false
    }

    // MARK: - Data

    private func reload() {
        let now = model.currentTime
        today = now
        let start = calendar.date(
            byAdding: .day,
            value: -JournalRetention.minimumDays,
            to: calendar.startOfDay(for: now)
        ) ?? now
        records = model.journalDayRecords(in: start ... now, calendar: calendar)
        reflections = model.reflectionState.recorder.reflections(in: start ... now)
    }

    // MARK: - Export

    private enum ExportFormat {
        case markdown
        case json
        case csv
    }

    private func range(of period: JournalPeriod) -> ClosedRange<Date> {
        period.interval.start ... period.interval.end
    }

    private func export(_ kind: ExportFormat, period: JournalPeriod) {
        let label = format.periodLabel(period, workingWeekdays: workingWeekdays)
        let span = range(of: period)
        let text: String
        let hasContent: Bool
        switch kind {
        case .markdown, .json:
            let entries = model.reflectionState.recorder.reflections(in: span)
            hasContent = !entries.isEmpty
            text = kind == .json ? ReflectionExport.json(entries) : ReflectionExport
                .markdown(entries)
        case .csv:
            text = model.exportActivityCSV(in: span)
            hasContent = text.split(separator: "\n", omittingEmptySubsequences: true).count > 1
        }
        guard hasContent else {
            let alert = NSAlert()
            alert.messageText = "Nothing to export for \(label)"
            alert.informativeText = kind == .csv
                ? "Curfew recorded no activity in \(label)."
                : "There are no reflections in \(label)."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        let panel = NSSavePanel()
        let slug = label.lowercased().replacingOccurrences(of: " ", with: "-")
        switch kind {
        case .markdown:
            panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
            panel.nameFieldStringValue = "curfew-reflections-\(slug).md"
        case .json:
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "curfew-reflections-\(slug).json"
        case .csv:
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.nameFieldStringValue = "curfew-activity-\(slug).csv"
        }
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSApp.presentError(error)
            }
        }
    }

    private func copyReflections(period: JournalPeriod) {
        let entries = model.reflectionState.recorder.reflections(in: range(of: period))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ReflectionExport.markdown(entries), forType: .string)
    }
}

/// Reloads the Journal when the day turns over or the lock begins or ends,
/// without making the page itself follow the once-a-second clock.
private struct JournalRefreshTrigger: View {
    @Environment(CurfewAppModel.self) private var model
    let reload: () -> Void

    var body: some View {
        Color.clear
            .onChange(of: Calendar.current.startOfDay(for: model.currentTime)) { reload() }
            .onChange(of: model.state.phase) { reload() }
            .accessibilityHidden(true)
    }
}

/// The prompt editor, opened from the toolbar.
private struct JournalPromptsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ReflectionPromptsView()
                .navigationTitle("Prompts")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .frame(minWidth: 620, idealWidth: 720, minHeight: 520, idealHeight: 680)
        .background(CurfewTheme.canvas)
    }
}
