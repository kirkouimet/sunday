import SundayKit
import SwiftUI

/// Sunday Live on the feed: the dinner as it happens. Who's at the table,
/// everyone's photos so far, and the two things you might do: check in,
/// or snap a photo of your own.
struct LiveDinnerCard: View {
    @ObservedObject var meal: Meal
    let cooks: [String]
    var onSnap: () -> Void

    @EnvironmentObject private var store: MealStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isChoosingMe = false
    @State private var pulse = false

    private var people: [String] { Attendance.decode(meal.attendees) }

    var body: some View {
        let checkedIn = store.isCheckedIn(meal)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .opacity(pulse ? 0.35 : 1)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 1).repeatForever(), value: pulse)
                    .accessibilityHidden(true)
                Text("Live · Sunday dinner")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.sundayAccent)
                Spacer()
                if let start = meal.liveAt {
                    Text("since \(start.formatted(date: .omitted, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Text(meal.displayName)
                .font(.title2.bold())
                .keepsake()
                .lineLimit(2)
            let status = LiveDinner.status(cook: meal.cook, people: people.count, photos: meal.sortedPhotos.count)
            if !status.isEmpty {
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !people.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(people, id: \.self) { person in
                            NavigationLink(value: PersonRoute(name: person)) {
                                VStack(spacing: 4) {
                                    CookAvatar(name: person, size: 40)
                                    Text(person)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .frame(maxWidth: 64)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("At the table: \(people.joined(separator: ", "))")
            }

            if !meal.sortedPhotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(meal.sortedPhotos) { photo in
                            PhotoThumbnail(photo: photo)
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
                .accessibilityLabel("\(meal.sortedPhotos.count) photos so far")
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { actions(checkedIn: checkedIn) }
                VStack(alignment: .leading, spacing: 8) { actions(checkedIn: checkedIn) }
            }

            Button("That's dinner") { store.endLive(meal) }
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .accessibilityHint("Ends Sunday Live for everyone.")
        }
        .onAppear { pulse = true }
        .confirmationDialog("Which one are you?", isPresented: $isChoosingMe, titleVisibility: .visible) {
            ForEach(cooks.prefix(8), id: \.self) { name in
                Button(name) {
                    store.setMyName(name)
                    store.checkIn(meal, as: name)
                }
            }
        } message: {
            Text("So this phone checks you in from now on.")
        }
    }

    @ViewBuilder
    private func actions(checkedIn: Bool) -> some View {
        if !checkedIn {
            Button {
                if store.myName == nil, !cooks.isEmpty {
                    isChoosingMe = true
                } else {
                    store.checkIn(meal)
                }
            } label: {
                Label("I'm here", systemImage: "hand.wave.fill").fixedSize()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button(action: onSnap) {
                Label("Snap", systemImage: "camera.fill").fixedSize()
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
