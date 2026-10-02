import CoreData
import SundayKit
import SwiftUI

/// Sunday Live on the feed, as the hero: the newest photo big with the
/// faces at the table over it, and one thing to do (check in, then snap).
struct LiveDinnerCard: View {
    @ObservedObject var meal: Meal
    var onSnap: () -> Void
    var onEnded: (Meal) -> Void

    @EnvironmentObject private var store: MealStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isChoosingMe = false
    @State private var isConfirmingEnd = false
    @State private var pulse = false
    @State private var dishName = ""
    @FocusState private var isNaming: Bool

    private var people: [String] { meal.tablePeople }

    /// Newest first: the table sees what was just taken.
    private var photos: [Photo] {
        meal.sortedPhotos.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    var body: some View {
        let checkedIn = store.isCheckedIn(meal)
        VStack(alignment: .leading, spacing: 0) {
            hero
            VStack(alignment: .leading, spacing: 12) {
                if (meal.name ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                    TextField("What's cooking?", text: $dishName)
                        .font(.title3.weight(.semibold))
                        .keepsake()
                        .focused($isNaming)
                        .submitLabel(.done)
                        .onSubmit { store.rename(meal, to: dishName) }
                        .padding(.top, 4)
                }
                if photos.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(photos.dropFirst()) { photo in
                                PhotoThumbnail(photo: photo)
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(alignment: .bottomTrailing) {
                                        if let by = photo.by { CookAvatar(name: by, size: 20).padding(3) }
                                    }
                                    .accessibilityLabel(photo.by.map { "\($0)'s photo" } ?? "Photo")
                            }
                        }
                    }
                }
                actions(checkedIn: checkedIn)
                footer
            }
            .padding(16)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.sundayAccent.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("liveCard")
        .onAppear { pulse = true }
        .sheet(isPresented: $isChoosingMe) {
            WhichOneAreYouView { name in
                store.setMyName(name)
                store.checkIn(meal)
            }
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Wrap up dinner for everyone?", isPresented: $isConfirmingEnd, titleVisibility: .visible) {
            Button("That's dinner") {
                store.endLive(meal)
                onEnded(meal)
            }
        } message: {
            Text("Check-ins become who was at the table, and everyone can rate it.")
        }
    }

    /// The newest photo, big, with who's here over it.
    private var hero: some View {
        Color.clear
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay {
                if let photo = photos.first {
                    PhotoThumbnail(photo: photo)
                } else {
                    ZStack {
                        LinearGradient(colors: [Color.sundayAccent.opacity(0.85), .orange.opacity(0.7)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        VStack(spacing: 8) {
                            Image(systemName: "camera.fill").font(.largeTitle)
                            Text("No photos yet. Be the first.").font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.bottom, 60)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 150)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .opacity(pulse ? 0.35 : 1)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 1).repeatForever(), value: pulse)
                    Text("LIVE")
                        .font(.caption.weight(.heavy))
                        .tracking(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.black.opacity(0.45), in: Capsule())
                .padding(12)
                .accessibilityLabel("Live now")
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(meal.displayName)
                        .font(.title2.bold())
                        .keepsake()
                        .lineLimit(2)
                    let status = LiveDinner.status(cook: meal.cook, people: people.count, photos: photos.count)
                    if !status.isEmpty {
                        Text(status).font(.subheadline)
                    }
                    if !people.isEmpty {
                        HStack(spacing: -8) {
                            ForEach(people.prefix(8), id: \.self) { person in
                                NavigationLink(value: PersonRoute(name: person)) {
                                    CookAvatar(name: person, size: 34)
                                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(person)
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .foregroundStyle(.white)
                .padding(16)
            }
            .clipped()
    }

    @ViewBuilder
    private func actions(checkedIn: Bool) -> some View {
        HStack(spacing: 10) {
            if !checkedIn {
                Button {
                    if store.myName == nil {
                        isChoosingMe = true
                    } else {
                        store.checkIn(meal)
                    }
                } label: {
                    Label("I'm here", systemImage: "hand.wave.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button(action: onSnap) {
                    Label("Snap", systemImage: "camera.fill")
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 28)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else {
                Button(action: onSnap) {
                    Label("Snap a photo", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    /// "Tell the table" (a text to anyone whose phone didn't buzz), and
    /// "That's dinner" for whoever started it or is cooking.
    private var footer: some View {
        HStack {
            ShareLink(item: DeepLink.live,
                      message: Text("Dinner's on: \(meal.displayName). Open Sunday and tap I'm here.")) {
                Label("Tell the table", systemImage: "message")
            }
            Spacer()
            if store.canEndLive(meal) {
                Button("That's dinner") { isConfirmingEnd = true }
            }
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
        .frame(minHeight: 44)
    }
}

/// "Which one are you?" Asked once per phone, so check-ins and photos use
/// the family's names ("Dad"), not whatever the iCloud account says.
struct WhichOneAreYouView: View {
    var onChoose: (String) -> Void

    @EnvironmentObject private var store: MealStore
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Meal.date, ascending: false)])
    private var meals: FetchedResults<Meal>
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.familyNames(from: Array(meals)).prefix(12), id: \.self) { name in
                        Button {
                            choose(name)
                        } label: {
                            HStack(spacing: 12) {
                                CookAvatar(name: name, size: 36)
                                Text(name).foregroundStyle(.primary)
                            }
                        }
                    }
                } footer: {
                    Text("This phone will check you in and sign your photos from now on.")
                }
                Section("Someone else") {
                    TextField("Your name at the table", text: $newName)
                        .submitLabel(.done)
                        .onSubmit { choose(newName) }
                }
            }
            .navigationTitle("Which one are you?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() } }
            }
        }
    }

    private func choose(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onChoose(trimmed)
        dismiss()
    }
}
