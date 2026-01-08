//
//  ContentView.swift
//  WeeklyFive
//
//  Created by Jaka Slekovec on 8. 1. 26.
//

import SwiftUI
import UserNotifications

enum NotificationManager {
    static let weeklyReminderId = "weekly_five_monday_reminder"

    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // Ignore for MVP.
        }
    }

    static func scheduleWeeklyMondayReminder(hour: Int = 8, minute: Int = 0) async {
        let center = UNUserNotificationCenter.current()

        // Remove any existing scheduled reminder so we don't duplicate.
        center.removePendingNotificationRequests(withIdentifiers: [weeklyReminderId])

        var dateComponents = DateComponents()
        // In Apple's weekday indexing, 1 = Sunday, 2 = Monday, ...
        dateComponents.weekday = 2
        dateComponents.hour = hour
        dateComponents.minute = minute

        let content = UNMutableNotificationContent()
        content.title = "Weekly Five"
        content.body = "New week, clean slate. Pick up to 5 priorities."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: weeklyReminderId, content: content, trigger: trigger)

        do {
            try await center.add(request)
        } catch {
            // Ignore for MVP.
        }
    }

    static func ensureWeeklyReminderScheduled() async {
        await requestAuthorizationIfNeeded()

        // Only schedule if authorization is granted.
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        await scheduleWeeklyMondayReminder(hour: 8, minute: 0)
    }
}

struct PriorityItem: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var isDone: Bool

    init(id: UUID = UUID(), title: String, isDone: Bool = false) {
        self.id = id
        self.title = title
        self.isDone = isDone
    }
}

struct ContentView: View {

    // Lokalni state – seznam prioritet (za zdaj samo v RAM-u)
    @State private var items: [PriorityItem] = []

    // Kontrolira prikaz "Add" ekrana
    @State private var isShowingAdd = false

    // Kratek "celebration" overlay, ko uporabnik dokonča vseh 5
    @State private var showCompletionOverlay = false

    @AppStorage("didScheduleWeeklyReminder") private var didScheduleWeeklyReminder: Bool = false
    @AppStorage("lastWeekKey") private var lastWeekKey: String = ""

    @Environment(\.scenePhase) private var scenePhase

    private let isoCalendar = Calendar(identifier: .iso8601)

    private let itemsStorageKey = "weeklyFive.items"

    private func loadItems() {
        guard let data = UserDefaults.standard.data(forKey: itemsStorageKey) else { return }
        do {
            items = try JSONDecoder().decode([PriorityItem].self, from: data)
        } catch {
            items = []
        }
    }

    private func saveItems() {
        do {
            let data = try JSONEncoder().encode(items)
            UserDefaults.standard.set(data, forKey: itemsStorageKey)
        } catch {
            // Ignore for MVP.
        }
    }

    private func weekKey(for date: Date) -> String {
        let comps = isoCalendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let year = comps.yearForWeekOfYear ?? 0
        let week = comps.weekOfYear ?? 0
        // e.g. 2026-W02
        return String(format: "%04d-W%02d", year, week)
    }

    private func resetIfNeeded(now: Date = Date()) {
        let current = weekKey(for: now)

        // First run: initialize without wiping anything.
        if lastWeekKey.isEmpty {
            lastWeekKey = current
            return
        }

        guard current != lastWeekKey else { return }

        // New week detected → reset.
        items.removeAll()
        saveItems()
        showCompletionOverlay = false
        isShowingAdd = false
        lastWeekKey = current
    }

    private func nextWeeklyResetDate(from date: Date) -> Date {
        // ISO week starts on Monday. Reset happens at the start of the *next* ISO week.
        let startOfThisWeek = isoCalendar.dateInterval(of: .weekOfYear, for: date)!.start
        return isoCalendar.date(byAdding: .day, value: 7, to: startOfThisWeek)!
    }

    private func countdownText(now: Date) -> String {
        let resetDate = nextWeeklyResetDate(from: now)
        let comps = isoCalendar.dateComponents([.day, .hour], from: now, to: resetDate)

        let d = max(0, comps.day ?? 0)
        let h = max(0, comps.hour ?? 0)

        if d == 0 && h == 0 {
            return "Resetting soon"
        }
        if d == 0 {
            return "Resets in \(h)h"
        }
        return "Resets in \(d)d \(h)h"
    }

    private var isWeekComplete: Bool {
        items.count == 5 && items.allSatisfy { $0.isDone }
    }

    private func triggerCompletionCelebration() {
        // Haptic
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        // Overlay
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            showCompletionOverlay = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.2)) {
                showCompletionOverlay = false
            }
        }
    }

    private func toggleDone(for item: PriorityItem) {
        let wasComplete = isWeekComplete

        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].isDone.toggle()

        let nowComplete = isWeekComplete
        if !wasComplete && nowComplete {
            triggerCompletionCelebration()
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    VStack(spacing: 16) {
                        Spacer(minLength: 0)

                        VStack(spacing: 8) {
                            Text("Focus on what actually matters this week.")
                            Text("Pick up to 5 priorities for this week.")
                            Text("Less tasks. More mental space.")
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                        Spacer(minLength: 0)
                    }
                } else {
                    List {
                        Section {
                            ForEach(items) { item in
                                Button {
                                    toggleDone(for: item)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                        Text(item.title)
                                            .strikethrough(item.isDone)
                                    }
                                    .foregroundStyle(item.isDone ? .secondary : .primary)
                                    .contentShape(Rectangle())
                                }
                            }
                            .onDelete { indexSet in
                                items.remove(atOffsets: indexSet)
                            }
                        } header: {
                            HStack {
                                Text("This Week")
                                Spacer()
                                Text("\(items.count)/5")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        HStack {
                            Text(isWeekComplete ? "All 5 done. Enjoy the rest of the week." : countdownText(now: context.date))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                    }
                }
                .background(.thinMaterial)
            }
            .overlay {
                if showCompletionOverlay {
                    VStack {
                        Spacer()

                        VStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 44))
                            Text("Week complete")
                                .font(.headline)
                            Text("You picked 5. You finished 5.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 18)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal, 24)
                        .transition(.scale.combined(with: .opacity))

                        Spacer()
                    }
                    .allowsHitTesting(false)
                }
            }
            .navigationTitle("Weekly Five")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(items.count >= 5)
                }
            }
            .sheet(isPresented: $isShowingAdd) {
                AddItemView { newTitle in
                    items.append(PriorityItem(title: newTitle))
                }
            }
            .task {
                // Load persisted items first.
                loadItems()

                // Ensure week reset logic runs on launch.
                resetIfNeeded()

                // Persist (in case reset happened or we loaded successfully).
                saveItems()

                // Schedule the weekly Monday reminder once.
                guard !didScheduleWeeklyReminder else { return }
                await NotificationManager.ensureWeeklyReminderScheduled()
                didScheduleWeeklyReminder = true
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    resetIfNeeded()
                }
            }
            .onChange(of: items) { _, _ in
                saveItems()
            }
        }
    }
}

struct AddItemView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @FocusState private var isTitleFocused: Bool

    let onAdd: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Priority") {
                    TextField("e.g. Finish report", text: $title)
                        .textInputAutocapitalization(.sentences)
                        .focused($isTitleFocused)
                }
            }
            .onAppear {
                // Auto-focus so typing works immediately (and helps show the keyboard).
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    isTitleFocused = true
                }
            }
            .navigationTitle("Add")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onAdd(trimmed)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
