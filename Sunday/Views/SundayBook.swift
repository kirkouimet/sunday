import CoreData
import SundayKit
import SwiftUI

/// The Sunday Book: a year of dinners as a printable cookbook-yearbook.
/// Every dish, who cooked, who was at the table, and the family's own recipe
/// in the cook's words. A gift for the people who never open the app.
@MainActor
enum SundayBook {
    static let pageSize = CGSize(width: 612, height: 792) // US Letter, points

    static func years(in meals: [Meal]) -> [Int] {
        Array(Set(meals.filter { !$0.isPlan }.compactMap { $0.date.map { Calendar.current.component(.year, from: $0) } }))
            .sorted(by: >)
    }

    /// Renders the book for `year` to a PDF file and returns its URL.
    static func make(year: Int, from meals: [Meal]) -> URL? {
        let calendar = Calendar.current
        let dinners = meals
            .filter { !$0.isPlan && $0.date.map { calendar.component(.year, from: $0) == year } == true }
            .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        guard !dinners.isEmpty else { return nil }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("The Sunday Book \(year).pdf")
        var box = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return nil }

        func draw<V: View>(_ page: V) {
            let renderer = ImageRenderer(content: page.frame(width: pageSize.width, height: pageSize.height))
            renderer.render { _, render in
                context.beginPDFPage(nil)
                render(context)
                context.endPDFPage()
            }
        }

        let recipes = recipesByDish(meals)
        draw(BookCover(year: year, dinners: dinners))
        // Each family recipe is printed once, on its own page, after the
        // first dinner of that dish this year. Chili four times is one recipe.
        var printed = Set<String>()
        for meal in dinners {
            draw(BookPage(meal: meal))
            let key = MealName.normalize(meal.displayName)
            if let recipe = recipes[key], printed.insert(key).inserted {
                draw(RecipePage(dish: meal.displayName, text: recipe.text, by: recipe.by, structure: recipe.structure))
            }
        }
        context.closePDF()
        return url
    }

    /// Each dish's written recipe (from whichever dinner holds it).
    private static func recipesByDish(_ meals: [Meal]) -> [String: (text: String, by: String?, structure: StructuredRecipe?)] {
        var result: [String: (text: String, by: String?, structure: StructuredRecipe?)] = [:]
        for meal in meals {
            guard let text = meal.recipe, !text.isEmpty else { continue }
            let key = MealName.normalize(meal.displayName)
            if result[key] == nil {
                result[key] = (text, meal.recipeBy ?? meal.cook, StructuredRecipe.decode(meal.recipeStructure))
            }
        }
        return result
    }
}

private let bookInk = Color(red: 0.16, green: 0.13, blue: 0.11)
private let bookAccent = Color(red: 0.60, green: 0.27, blue: 0.13)
private let bookPaper = Color(red: 0.99, green: 0.97, blue: 0.94)

private struct BookCover: View {
    let year: Int
    let dinners: [Meal]

    var body: some View {
        let people = Attendance.counts(in: dinners.compactMap { m -> Attendance.Dinner? in
            guard let id = m.id, let date = m.date else { return nil }
            return Attendance.Dinner(id: id, date: date, people: m.tablePeople)
        })
        let photos = dinners.compactMap { $0.sortedPhotos.first?.thumbnailData }.prefix(6).compactMap(UIImage.init(data:))
        VStack(spacing: 18) {
            Spacer()
            if !photos.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(150), spacing: 8), count: min(3, photos.count)), spacing: 8) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { _, image in
                        Color.clear
                            .frame(width: 150, height: 150)
                            .overlay { Image(uiImage: image).resizable().scaledToFill() }
                            .clipped()
                    }
                }
                .padding(.bottom, 12)
            }
            Text("The Sunday Book")
                .font(.system(size: 48, weight: .bold, design: .serif))
            Text(String(year))
                .font(.system(size: 30, weight: .regular, design: .serif))
                .foregroundStyle(bookAccent)
            Text("\(dinners.count) Sunday dinners")
                .font(.system(size: 16, design: .serif))
                .padding(.top, 12)
            if !people.isEmpty {
                Text("Around the table: " + people.map(\.name).joined(separator: ", "))
                    .font(.system(size: 13, design: .serif))
                    .italic()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 80)
            }
            Spacer()
            Text("Made with Sunday")
                .font(.system(size: 10))
                .foregroundStyle(bookInk.opacity(0.5))
        }
        .foregroundStyle(bookInk)
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bookPaper)
    }
}

private struct BookPage: View {
    let meal: Meal

    var body: some View {
        let people = meal.tablePeople
        VStack(alignment: .leading, spacing: 14) {
            if let data = meal.sortedPhotos.first?.imageData ?? meal.sortedPhotos.first?.thumbnailData,
               let image = UIImage(data: data) {
                Color.clear
                    .frame(height: 300)
                    .overlay { Image(uiImage: image).resizable().scaledToFill() }
                    .clipped()
            }
            Text(meal.displayName)
                .font(.system(size: 28, weight: .bold, design: .serif))
            HStack(spacing: 6) {
                Text((meal.date ?? .now).formatted(.dateTime.weekday(.wide).month(.wide).day()))
                if let cook = meal.cook, !cook.isEmpty { Text("· cooked by \(cook)") }
            }
            .font(.system(size: 13, design: .serif))
            .foregroundStyle(bookAccent)
            if !people.isEmpty {
                Text("At the table: " + people.joined(separator: ", "))
                    .font(.system(size: 12, design: .serif))
            }
            if let notes = meal.notes, !notes.isEmpty {
                Text("“\(notes)”")
                    .font(.system(size: 14, design: .serif))
                    .italic()
            }
            if let teller = meal.storyBy, let story = meal.story, !story.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(teller)'s story")
                        .font(.system(size: 13, weight: .semibold, design: .serif))
                    Text(story)
                        .font(.system(size: 11, design: .serif))
                        .italic()
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(bookInk)
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(bookPaper)
    }
}

/// A family recipe, in full, on its own page.
private struct RecipePage: View {
    let dish: String
    let text: String
    let by: String?
    let structure: StructuredRecipe?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How we make it")
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .foregroundStyle(bookAccent)
            Text(dish)
                .font(.system(size: 28, weight: .bold, design: .serif))
            if let by, !by.isEmpty {
                Text("\(by)'s way")
                    .font(.system(size: 14, design: .serif))
                    .italic()
            }
            if let structure, !structure.isEmpty {
                // Sorted from what was said: a proper card, ingredients beside steps.
                HStack(alignment: .top, spacing: 28) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("You'll need").font(.system(size: 12, weight: .semibold, design: .serif))
                        ForEach(Array(structure.ingredients.enumerated()), id: \.offset) { _, item in
                            Text("• \(item)").font(.system(size: 11, design: .serif))
                        }
                    }
                    .frame(width: 170, alignment: .leading)
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(structure.steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("\(index + 1)").font(.system(size: 13, weight: .bold, design: .serif)).foregroundStyle(bookAccent)
                                Text(step).font(.system(size: 12, design: .serif))
                            }
                        }
                    }
                }
                .minimumScaleFactor(0.7)
                if !structure.note.isEmpty {
                    Text("“\(structure.note)”")
                        .font(.system(size: 13, design: .serif))
                        .italic()
                        .padding(.top, 6)
                }
            } else {
                Text(text)
                    .font(.system(size: 12, design: .serif))
                    .lineSpacing(3)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(bookInk)
        .padding(56)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(bookPaper)
    }
}

/// Family tab, near the top: this year's book as a thing you can hold.
/// A cover of the year's photos, how many Sundays are in it, and one tap
/// to make it (in December, it's the family's gift).
struct SundayBookSection: View {
    let meals: [Meal]

    @State private var year: Int?
    @State private var bookURL: URL?
    @State private var isMaking = false

    var body: some View {
        let years = SundayBook.years(in: meals)
        if let latest = years.first {
            let selected = year ?? latest
            let dinners = meals.filter { !$0.isPlan && $0.date.map { Calendar.current.component(.year, from: $0) == selected } == true }
            Section {
                HStack(alignment: .top, spacing: 14) {
                    BookThumbnail(dinners: dinners)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("The \(String(selected)) Sunday Book")
                            .font(.headline)
                            .keepsake()
                        Text("\(dinners.count) Sunday\(dinners.count == 1 ? "" : "s"), who cooked, who was at the table, and your recipes in your own words.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if selected == Calendar.current.component(.year, from: .now),
                           Calendar.current.component(.month, from: .now) == 12 {
                            Text("Ready to print for the holidays")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.sundayAccent)
                        }
                    }
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
                if years.count > 1 {
                    Picker("Year", selection: Binding(get: { selected }, set: { year = $0; bookURL = nil })) {
                        ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                    }
                }
                if let bookURL {
                    ShareLink(item: bookURL) {
                        Label("Share or print the book", systemImage: "book.closed.fill")
                    }
                } else {
                    Button {
                        isMaking = true
                        Task {
                            // Let the spinner show before rendering takes the main thread.
                            try? await Task.sleep(for: .milliseconds(80))
                            bookURL = SundayBook.make(year: selected, from: meals)
                            isMaking = false
                        }
                    } label: {
                        HStack {
                            Label(isMaking ? "Making your book…" : "Make the book", systemImage: "book")
                            if isMaking { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isMaking)
                }
            }
        }
    }
}

/// A tiny cover: the year's first photos, like the printed one.
private struct BookThumbnail: View {
    let dinners: [Meal]

    var body: some View {
        let photos = dinners.compactMap { $0.sortedPhotos.first }.prefix(4)
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(bookPaper)
            LazyVGrid(columns: [GridItem(.fixed(26), spacing: 3), GridItem(.fixed(26), spacing: 3)], spacing: 3) {
                ForEach(Array(photos.enumerated()), id: \.offset) { _, photo in
                    PhotoThumbnail(photo: photo)
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .padding(.bottom, 14)
            VStack {
                Spacer()
                Text("Sunday")
                    .font(.system(size: 9, weight: .bold, design: .serif))
                    .foregroundStyle(bookInk)
                    .padding(.bottom, 6)
            }
        }
        .frame(width: 66, height: 86)
        .shadow(color: .black.opacity(0.18), radius: 3, x: 1, y: 2)
        .accessibilityHidden(true)
    }
}
