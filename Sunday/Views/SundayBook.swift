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
        for meal in dinners {
            draw(BookPage(meal: meal, recipe: recipes[MealName.normalize(meal.displayName)]))
        }
        context.closePDF()
        return url
    }

    /// Each dish's written recipe (from whichever dinner holds it).
    private static func recipesByDish(_ meals: [Meal]) -> [String: (text: String, by: String?)] {
        var result: [String: (text: String, by: String?)] = [:]
        for meal in meals {
            guard let text = meal.recipe, !text.isEmpty else { continue }
            let key = MealName.normalize(meal.displayName)
            if result[key] == nil { result[key] = (text, meal.recipeBy ?? meal.cook) }
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
            return Attendance.Dinner(id: id, date: date, people: Attendance.decode(m.attendees))
        })
        VStack(spacing: 18) {
            Spacer()
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
    let recipe: (text: String, by: String?)?

    var body: some View {
        let people = Attendance.decode(meal.attendees)
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
            if let recipe {
                VStack(alignment: .leading, spacing: 6) {
                    Text(recipe.by.map { "How we make it · \($0)'s way" } ?? "How we make it")
                        .font(.system(size: 13, weight: .semibold, design: .serif))
                    Text(recipe.text)
                        .font(.system(size: 11, design: .serif))
                        .lineLimit(18)
                }
                .padding(.top, 4)
            }
            if let teller = meal.storyBy, let story = meal.story, !story.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(teller)'s story")
                        .font(.system(size: 13, weight: .semibold, design: .serif))
                    Text(story)
                        .font(.system(size: 11, design: .serif))
                        .italic()
                        .lineLimit(10)
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

/// Family tab entry: pick a year, make the book, share or print it.
struct SundayBookSection: View {
    let meals: [Meal]

    @State private var year: Int?
    @State private var bookURL: URL?
    @State private var isMaking = false

    var body: some View {
        let years = SundayBook.years(in: meals)
        if let latest = years.first {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("The Sunday Book")
                        .font(.title3.weight(.semibold))
                        .keepsake()
                    Text("Your year of Sunday dinners as a book to print or send: every dish, who cooked, who was at the table, and the recipes in your family's own words.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                if years.count > 1 {
                    Picker("Year", selection: Binding(get: { year ?? latest }, set: { year = $0; bookURL = nil })) {
                        ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                    }
                }
                if let bookURL {
                    ShareLink(item: bookURL) {
                        Label("Share or print the \(String(year ?? latest)) book", systemImage: "book.closed.fill")
                    }
                } else {
                    Button {
                        isMaking = true
                        bookURL = SundayBook.make(year: year ?? latest, from: meals)
                        isMaking = false
                    } label: {
                        HStack {
                            Label("Make the \(String(year ?? latest)) book", systemImage: "book")
                            if isMaking { Spacer(); ProgressView() }
                        }
                    }
                }
            }
        }
    }
}
