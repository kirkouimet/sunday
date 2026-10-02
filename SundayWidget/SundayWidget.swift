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
        // One entry per day for a week, so "Tonight", "Last Sunday", the streak
        // and the memory stay true even if the app isn't opened. The app also
        // reloads timelines whenever dinners change.
        let snapshot = WidgetStorage.read()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var entries = [SnapshotEntry(date: .now, snapshot: snapshot)]
        for offset in 1...7 {
            if let day = calendar.date(byAdding: .day, value: offset, to: today) {
                entries.append(SnapshotEntry(date: day, snapshot: snapshot))
            }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

extension WidgetSnapshot {
    static let sample = WidgetSnapshot(
        latest: .init(title: "Lemon chicken", date: .now.addingTimeInterval(-86_400 * 3), imageFileName: nil, mealID: UUID()),
        memories: [.init(title: "Chili", date: Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .now,
                         imageFileName: nil, mealID: UUID())],
        recentDates: [],
        totalDinners: 48
    )
}

/// What a tile shows on a given day.
struct TileContent {
    let item: WidgetSnapshot.Item
    let caption: String
}

private let accent = Color(red: 0.851, green: 0.392, blue: 0.212)

struct DinnerTile: View {
    let content: TileContent
    var compact = false

    private var item: WidgetSnapshot.Item { content.item }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let data = WidgetStorage.imageData(named: item.imageFileName), let image = UIImage(data: data) {
                Color.clear.overlay {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
            } else {
                LinearGradient(colors: [accent, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "fork.knife")
                    .font(.largeTitle)
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(content.caption.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(item.title)
                    .font(compact ? .footnote.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
            .padding(compact ? 10 : 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

struct SundayWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            lockScreen.containerBackground(for: .widget) { Color.clear }
        case .accessoryInline:
            Text(entry.snapshot.planLine(on: entry.date) ?? lockScreenFallback)
                .containerBackground(for: .widget) { Color.clear }
        case .systemMedium:
            medium.containerBackground(for: .widget) { Color.black }
        default:
            small.containerBackground(for: .widget) { Color.black }
        }
    }

    /// Lock Screen: tonight's plan and the cook, so Sunday is on every
    /// family phone before anyone opens the app.
    private var lockScreen: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let toRate {
                let pending = PendingRatings.stars(for: toRate.mealID) ?? 0
                Text(pending > 0 ? "Saved, just for you" : "How was \(toRate.title)?")
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    ForEach(1...5, id: \.self) { value in
                        Button(intent: RateDinnerIntent(mealID: toRate.mealID, stars: value)) {
                            Image(systemName: value <= pending ? "star.fill" : "star")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .font(.title3)
            } else if let line = entry.snapshot.planLine(on: entry.date) {
                Label("Sunday dinner", systemImage: "fork.knife")
                    .font(.caption2.weight(.semibold))
                Text(line)
                    .font(.headline)
                    .lineLimit(2)
            } else {
                Label("Sunday", systemImage: "fork.knife")
                    .font(.caption2.weight(.semibold))
                Text(lockScreenFallback)
                    .font(.headline)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // On Sunday with a plan, tapping goes straight to the camera.
        .widgetURL(entry.snapshot.planLine(on: entry.date)?.hasPrefix("Tonight") == true ? DeepLink.snap : URL(string: "sunday://feed"))
    }

    private var lockScreenFallback: String {
        if let memory = entry.snapshot.memory(on: entry.date) {
            return "\(WidgetSnapshot.memoryCaption(for: memory.date, on: entry.date)): \(memory.title)"
        }
        if let latest = entry.snapshot.latest {
            return "\(WidgetSnapshot.latestCaption(for: latest.date, on: entry.date)): \(latest.title)"
        }
        return "What's for Sunday?"
    }

    private var latest: TileContent? {
        entry.snapshot.latest.map {
            TileContent(item: $0, caption: WidgetSnapshot.latestCaption(for: $0.date, on: entry.date))
        }
    }

    private var memory: TileContent? {
        entry.snapshot.memory(on: entry.date).map {
            TileContent(item: $0, caption: WidgetSnapshot.memoryCaption(for: $0.date, on: entry.date))
        }
    }

    /// Monday morning: rate last Sunday's dinner right here.
    private var toRate: WidgetSnapshot.Item? { entry.snapshot.toRate }

    private func rateRow(_ item: WidgetSnapshot.Item, size: CGFloat) -> some View {
        let pending = PendingRatings.stars(for: item.mealID) ?? 0
        return HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { value in
                Button(intent: RateDinnerIntent(mealID: item.mealID, stars: value)) {
                    Image(systemName: value <= pending ? "star.fill" : "star")
                        .font(.system(size: size))
                        .foregroundStyle(value <= pending ? Color(red: 1, green: 0.8, blue: 0.25) : .white.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityLabel(pending > 0 ? "Your rating, \(pending) of 5" : "Rate \(item.title)")
    }

    private func rateTile(_ item: WidgetSnapshot.Item, compact: Bool) -> some View {
        let pending = PendingRatings.stars(for: item.mealID) ?? 0
        return ZStack(alignment: .bottomLeading) {
            DinnerTile(content: TileContent(item: item, caption: ""), compact: compact)
                .overlay(Color.black.opacity(0.35))
            VStack(alignment: .leading, spacing: 6) {
                Text(pending > 0 ? "Saved, just for you" : "How was \(item.title)?")
                    .font(compact ? .footnote.weight(.semibold) : .headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                rateRow(item, size: compact ? 17 : 22)
            }
            .padding(compact ? 10 : 14)
        }
        .widgetURL(DeepLink.url(forMeal: item.mealID))
    }

    @ViewBuilder
    private var small: some View {
        if let toRate {
            rateTile(toRate, compact: true)
        } else if let tile = memory ?? latest {
            DinnerTile(content: tile, compact: true)
                .widgetURL(DeepLink.url(forMeal: tile.item.mealID))
        } else {
            empty
        }
    }

    @ViewBuilder
    private var medium: some View {
        let tiles = [latest, memory].compactMap { $0 }
        let streak = entry.snapshot.streak(on: entry.date)
        if let toRate {
            rateTile(toRate, compact: false)
        } else if tiles.isEmpty {
            empty
        } else {
            HStack(spacing: 2) {
                ForEach(tiles, id: \.item.mealID) { tile in
                    Link(destination: DeepLink.url(forMeal: tile.item.mealID)) {
                        DinnerTile(content: tile, compact: tiles.count > 1)
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if streak >= 2 {
                    Label("\(streak)", systemImage: "flame.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(accent, in: Capsule())
                        .padding(8)
                        .accessibilityLabel("\(streak) Sundays in a row")
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
        .description("Tonight's plan, last Sunday's dinner to rate, and what you ate this time in years past.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

@main
struct SundayWidgetBundle: WidgetBundle {
    var body: some Widget {
        SundayWidget()
        LiveDinnerActivity()
    }
}
