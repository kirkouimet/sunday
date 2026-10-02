import SundayKit
import SwiftUI
import WidgetKit

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let snapshot = WidgetStorage.read()
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview && snapshot.latest == nil ? .sample : snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        // The app reloads timelines whenever dinners change; refresh daily so
        // captions like "Last Sunday" stay true.
        let tomorrow = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
        completion(Timeline(entries: [SnapshotEntry(date: .now, snapshot: WidgetStorage.read())], policy: .after(tomorrow)))
    }
}

extension WidgetSnapshot {
    static let sample = WidgetSnapshot(
        latest: .init(title: "Lemon chicken", caption: "Last Sunday", date: .now, imageFileName: nil, mealID: UUID()),
        memory: .init(title: "Chili", caption: "A year ago this week", date: .now, imageFileName: nil, mealID: UUID()),
        streak: 6,
        totalDinners: 48
    )
}

private let accent = Color(red: 0.851, green: 0.392, blue: 0.212)

struct DinnerTile: View {
    let item: WidgetSnapshot.Item
    var compact = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let data = WidgetStorage.imageData(named: item.imageFileName), let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(colors: [accent, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "fork.knife")
                    .font(.largeTitle)
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.caption.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(item.title)
                    .font(compact ? .footnote.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
            .padding(compact ? 10 : 12)
        }
    }
}

struct SundayWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                medium
            default:
                small
            }
        }
        .containerBackground(for: .widget) { Color.black }
    }

    @ViewBuilder
    private var small: some View {
        if let item = entry.snapshot.memory ?? entry.snapshot.latest {
            DinnerTile(item: item, compact: true)
                .widgetURL(DeepLink.url(forMeal: item.mealID))
        } else {
            empty
        }
    }

    @ViewBuilder
    private var medium: some View {
        let items = [entry.snapshot.latest, entry.snapshot.memory].compactMap { $0 }
        if items.isEmpty {
            empty
        } else {
            HStack(spacing: 2) {
                ForEach(items, id: \.mealID) { item in
                    Link(destination: DeepLink.url(forMeal: item.mealID)) {
                        DinnerTile(item: item, compact: items.count > 1)
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if entry.snapshot.streak >= 2 {
                    Label("\(entry.snapshot.streak)", systemImage: "flame.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(accent, in: Capsule())
                        .padding(8)
                        .accessibilityLabel("\(entry.snapshot.streak) Sundays in a row")
                }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "fork.knife")
                .font(.title2)
                .foregroundStyle(accent)
            Text("Snap this Sunday's dinner")
                .font(.footnote.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
        }
        .padding()
    }
}

struct SundayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SundayDinner", provider: SnapshotProvider()) { entry in
            SundayWidgetView(entry: entry)
        }
        .configurationDisplayName("Sunday dinner")
        .description("Last Sunday's dinner, and what you ate this time in years past.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

@main
struct SundayWidgetBundle: WidgetBundle {
    var body: some Widget {
        SundayWidget()
    }
}
