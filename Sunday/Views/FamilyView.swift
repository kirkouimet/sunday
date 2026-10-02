import CloudKit
import CoreData
import SundayKit
import SwiftUI

struct FamilyView: View {
    @EnvironmentObject private var store: MealStore

    @AppStorage(Reminders.enabledKey) private var remindersEnabled = false
    @AppStorage(FamilyNotifier.enabledKey) private var familyPostAlerts = true
    @AppStorage(Reminders.hourKey) private var reminderHour = 17
    @AppStorage(Reminders.minuteKey) private var reminderMinute = 30
    @AppStorage(Hemisphere.storageKey) private var hemisphere: Hemisphere = .northern

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Meal.date, ascending: false)])
    private var meals: FetchedResults<Meal>

    @State private var sharingShare: CKShare?
    @State private var isPreparingShare = false
    @State private var shareError: String?

    var body: some View {
        NavigationStack {
            Form {
                if !meals.isEmpty {
                    statsHero
                }
                // A family of one: the invite is the most important thing here.
                if store.role == .solo {
                    familySection
                }
                if !meals.isEmpty {
                    funStats
                }
                accountWarning
                if store.role != .solo {
                    familySection
                }
                remindersSection

                Section("Seasons") {
                    Picker("Hemisphere", selection: $hemisphere) {
                        Text("Northern").tag(Hemisphere.northern)
                        Text("Southern").tag(Hemisphere.southern)
                    }
                }

                Section {
                } footer: {
                    Text("Sunday stores everything in iCloud. There are no accounts or servers, and no ads.")
                }
            }
            .navigationTitle("Family")
            .sheet(item: $sharingShare) { share in
                CloudSharingView(share: share, container: store.persistence.ckContainer) {
                    store.refreshShare()
                }
                .ignoresSafeArea()
            }
            .alert("Couldn't set up sharing", isPresented: Binding(get: { shareError != nil }, set: { if !$0 { shareError = nil } })) {
                Button("OK") {}
            } message: {
                Text(shareError ?? "")
            }
            .task { await store.refreshAccountStatus() }
        }
    }

    /// The keepsake number: how many dinners this family has shared.
    private var statsHero: some View {
        let streak = SundayCalendar.streak(mealDates: meals.compactMap(\.date))
        return Section {
            VStack(spacing: 6) {
                Text("\(meals.count)")
                    .font(.system(size: 64, weight: .bold, design: .serif))
                    .foregroundStyle(Color.sundayAccent)
                    .contentTransition(.numericText())
                Text(meals.count == 1 ? "dinner together" : "dinners together")
                    .font(.headline)
                if let first = meals.last?.date {
                    Text("Since \(first.formatted(.dateTime.month(.wide).year()))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if streak >= 2 {
                    HStack(spacing: 5) {
                        Image(systemName: "flame.fill")
                        Text("\(streak) Sundays in a row")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.sundayAccent)
                    .padding(.top, 4)
                }
                memberRow
                    .padding(.top, 10)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .accessibilityElement(children: .combine)
        }
    }

    /// Everyone at the table: family members from the share (or the cooks
    /// we know), plus a spot for whoever is next.
    private var members: [String] {
        var seen = Set<String>()
        let fromShare = (store.share?.participants ?? []).compactMap { participant -> String? in
            guard participant.acceptanceStatus == .accepted || participant.role == .owner,
                  let components = participant.userIdentity.nameComponents else { return nil }
            let name = components.formatted(.name(style: .short))
            return name.isEmpty ? nil : name
        }
        let cooks = meals.compactMap { $0.cook?.trimmingCharacters(in: .whitespaces) }
        return (fromShare + cooks).filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }.prefix(6).map { $0 }
    }

    private var memberRow: some View {
        HStack(spacing: -6) {
            ForEach(members, id: \.self) { name in
                CookAvatar(name: name, size: 36)
                    .overlay(Circle().strokeBorder(Color(.secondarySystemGroupedBackground), lineWidth: 2))
            }
            if store.role != .participant {
                Button {
                    openSharing()
                } label: {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .background(Color.secondary.opacity(0.15), in: Circle())
                        .overlay(Circle().strokeBorder(Color(.secondarySystemGroupedBackground), lineWidth: 2))
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)
                .accessibilityLabel("Invite family")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Family: \(members.joined(separator: ", "))")
    }

    /// Little superlatives that make this tab a keepsake, not settings.
    @ViewBuilder
    private var funStats: some View {
        let dishes = Suggestions.group(meals.compactMap { m -> MealSummary? in
            guard let id = m.id, let date = m.date else { return nil }
            return MealSummary(id: id, name: m.displayName, date: date, stars: nil)
        })
        let mostMade = dishes.max { $0.timesEaten < $1.timesEaten }
        let cookCounts = Dictionary(grouping: meals.compactMap { $0.cook?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }) { $0.lowercased() }
        let topCook = cookCounts.max { $0.value.count < $1.value.count }
        let first = meals.last
        Section {
            // Superlatives only once there's something to compare.
            if let mostMade, mostMade.timesEaten >= 3 {
                LabeledContent("Most made") {
                    Text("\(mostMade.displayName) · \(mostMade.timesEaten)×").keepsake()
                }
            }
            if cookCounts.count >= 2, let topCook, let name = topCook.value.first {
                LabeledContent("Head chef") {
                    HStack(spacing: 6) {
                        CookAvatar(name: name, size: 20)
                        Text("\(name) · \(topCook.value.count) dinners")
                    }
                }
            }
            if let first, let date = first.date {
                NavigationLink {
                    MealDetailView(meal: first)
                } label: {
                    HStack(spacing: 12) {
                        PhotoThumbnail(photo: first.sortedPhotos.first)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Where it started").font(.subheadline.weight(.semibold))
                            Text("\(first.displayName), \(date.formatted(.dateTime.month(.abbreviated).day().year()))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var accountWarning: some View {
        if store.persistence.isCloudBacked, store.accountStatus == .noAccount || store.accountStatus == .restricted {
            Section {
                Label("Sign in to iCloud in Settings to sync dinners and share them with your family.",
                      systemImage: "exclamationmark.icloud")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var familySection: some View {
        Section {
            switch store.role {
            case .solo:
                Text("Invite your family so everyone can add photos and see the history.")
                    .font(.subheadline)
            case .owner:
                LabeledContent("Family", value: familyMembersSummary)
            case .participant:
                LabeledContent("Joined", value: ownerName.map { "\($0)'s family" } ?? "Family")
            }

            if store.role == .solo, store.persistence.isCloudBacked, !store.hasCompletedFirstImport {
                HStack {
                    ProgressView()
                    Text("Checking iCloud for your family…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if store.role != .participant {
                Button {
                    openSharing()
                } label: {
                    HStack {
                        Label(store.role == .solo ? "Invite family" : "Manage family", systemImage: "person.crop.circle.badge.plus")
                        if isPreparingShare {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isPreparingShare || !store.persistence.isCloudBacked)
            } else if let share = store.share {
                Button("Family members") { sharingShare = share }
            }
        } header: {
            Text("Family sharing")
        } footer: {
            Text("Star ratings are always private and stay in your own iCloud.")
        }
    }

    private var remindersSection: some View {
        Section {
            Toggle("Sunday dinner reminder", isOn: $remindersEnabled)
            if remindersEnabled {
                DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
            }
            if store.role != .solo {
                Toggle("When family posts a dinner", isOn: $familyPostAlerts)
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text(store.role == .solo
                 ? "A nudge every Sunday to snap dinner, with a memory from past years when we have one."
                 : "A nudge every Sunday to snap dinner, and a heads-up with the photo when someone posts one.")
        }
        .onChange(of: familyPostAlerts) { _, enabled in
            guard enabled else { return }
            Task {
                if !(await Reminders.requestAuthorization()) { familyPostAlerts = false }
            }
        }
        .onChange(of: remindersEnabled) { _, enabled in
            Task {
                if enabled, !(await Reminders.requestAuthorization()) {
                    remindersEnabled = false
                    return
                }
                await Reminders.rescheduleIfEnabled(store: store)
            }
        }
    }

    private var reminderTime: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: .now) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            reminderHour = parts.hour ?? 17
            reminderMinute = parts.minute ?? 30
            Task { await Reminders.rescheduleIfEnabled(store: store) }
        }
    }

    private var familyMembersSummary: String {
        let others = (store.share?.participants ?? []).filter { $0.role != .owner && $0.acceptanceStatus == .accepted }
        switch others.count {
        case 0: return "Waiting for people to join"
        case 1: return "You + 1 person"
        default: return "You + \(others.count) people"
        }
    }

    private var ownerName: String? {
        guard let components = store.share?.owner.userIdentity.nameComponents else { return nil }
        let name = components.formatted(.name(style: .short))
        return name.isEmpty ? nil : name
    }

    private func openSharing() {
        isPreparingShare = true
        Task {
            defer { isPreparingShare = false }
            do {
                sharingShare = try await store.familyShare()
            } catch {
                shareError = error.localizedDescription
            }
        }
    }
}

extension CKShare: @retroactive Identifiable {
    public var id: CKRecord.ID { recordID }
}
