import ActivityKit
import AppIntents
import SundayKit
import SwiftUI
import WidgetKit

private let liveAccent = Color(red: 0.851, green: 0.392, blue: 0.212)

/// Sunday Live on the Lock Screen and in the Dynamic Island: the dish, the
/// cook, the faces at the table, "I'm here" without opening the app, and a
/// tap anywhere opens the camera to add your photo.
struct LiveDinnerActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveDinnerAttributes.self) { context in
            LiveDinnerLockScreen(context: context)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(DeepLink.live)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SUNDAY DINNER")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(liveAccent)
                        Text(context.state.dish)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Faces(people: context.state.people, size: 24, limit: 4)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(LiveDinner.status(cook: context.state.cook, people: context.state.people.count,
                                               photos: context.state.photoCount))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        CheckInButton(mealID: context.attributes.mealID, isCheckedIn: context.state.isMeCheckedIn,
                                      knowsMe: context.state.me != nil)
                    }
                }
            } compactLeading: {
                Image(systemName: "fork.knife")
                    .foregroundStyle(liveAccent)
            } compactTrailing: {
                Label("\(context.state.people.count)", systemImage: "person.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(liveAccent)
            } minimal: {
                Image(systemName: "fork.knife")
                    .foregroundStyle(liveAccent)
            }
            .widgetURL(DeepLink.live)
            .keylineTint(liveAccent)
        }
    }
}

private struct LiveDinnerLockScreen: View {
    let context: ActivityViewContext<LiveDinnerAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(Color.red).frame(width: 7, height: 7)
                Text("SUNDAY DINNER")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(liveAccent)
                Spacer()
                if context.isStale {
                    Text("Wrapped up · tap to rate")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            Text(context.state.dish)
                .font(.system(.title3, design: .serif).weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
            HStack(alignment: .center, spacing: 12) {
                if let data = WidgetStorage.imageData(named: context.state.photoFile), let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 58, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Faces(people: context.state.people, size: 26, limit: 6)
                    Text(LiveDinner.status(cook: context.state.cook, people: context.state.people.count,
                                           photos: context.state.photoCount))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    CheckInButton(mealID: context.attributes.mealID, isCheckedIn: context.state.isMeCheckedIn,
                                  knowsMe: context.state.me != nil)
                    Link(destination: DeepLink.snap) {
                        Label("Snap a photo", systemImage: "camera.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .padding(16)
    }
}

private struct CheckInButton: View {
    let mealID: String
    let isCheckedIn: Bool
    let knowsMe: Bool

    var body: some View {
        if isCheckedIn {
            Label("At the table", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(liveAccent)
        } else if let id = UUID(uuidString: mealID) {
            Group {
                if knowsMe {
                    Button(intent: CheckInIntent(mealID: id)) { label }
                } else {
                    Button(intent: CheckInAndAskIntent(mealID: id)) { label }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(liveAccent)
        }
    }

    private var label: some View {
        Label("I'm here", systemImage: "hand.wave.fill")
            .font(.caption.weight(.semibold))
    }
}

/// Initial circles, overlapping, like the app's avatars.
private struct Faces: View {
    let people: [String]
    let size: CGFloat
    let limit: Int


    var body: some View {
        HStack(spacing: -size * 0.25) {
            ForEach(Array(people.prefix(limit).enumerated()), id: \.offset) { _, person in
                Text(AvatarPalette.initial(for: person))
                    .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(Self.color(for: person), in: Circle())
                    .overlay(Circle().strokeBorder(.black.opacity(0.4), lineWidth: 1.5))
            }
            if people.count > limit {
                Text("+\(people.count - limit)")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.leading, size * 0.35)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(people.isEmpty ? "No one checked in yet" : "At the table: \(people.joined(separator: ", "))")
    }

    private static func color(for name: String) -> Color {
        let c = AvatarPalette.colors[AvatarPalette.index(for: name)]
        return Color(red: c.red, green: c.green, blue: c.blue)
    }
}
