import CloudKit
import CoreData
import SundayKit
import SwiftUI

struct FamilyView: View {
    @EnvironmentObject private var store: MealStore

    @AppStorage(Reminders.enabledKey) private var remindersEnabled = false
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
                accountWarning
                familySection
                remindersSection

                Section("Seasons") {
                    Picker("Hemisphere", selection: $hemisphere) {
                        Text("Northern").tag(Hemisphere.northern)
                        Text("Southern").tag(Hemisphere.southern)
                    }
                }

                Section {
                    LabeledContent("Dinners logged", value: "\(meals.count)")
                    if let first = meals.last?.date {
                        LabeledContent("Since", value: first.dinnerFormatted)
                    }
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
            .alert("Couldn't set up sharing", isPresented: .constant(shareError != nil)) {
                Button("OK") { shareError = nil }
            } message: {
                Text(shareError ?? "")
            }
            .task { await store.refreshAccountStatus() }
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
                Text("Your dinners are saved to your iCloud. Invite your family so everyone can add photos and see the history.")
                    .font(.subheadline)
            case .owner:
                LabeledContent("Family", value: familyMembersSummary)
            case .participant:
                LabeledContent("Joined", value: ownerName.map { "\($0)'s family" } ?? "Family")
            }

            if store.role != .participant {
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
            Text("Dinners and photos are shared with everyone you invite. Star ratings are always private: they stay in your own iCloud.")
        }
    }

    private var remindersSection: some View {
        Section {
            Toggle("Sunday dinner reminder", isOn: $remindersEnabled)
            if remindersEnabled {
                DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("A nudge every Sunday to snap dinner, with a memory from past years when we have one.")
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

extension CKShare: Identifiable {
    public var id: CKRecord.ID { recordID }
}
