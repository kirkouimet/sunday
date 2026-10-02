# Sunday

A private iPhone app for the family's Sunday dinners. Snap a picture, name the dish, and give it your private stars. Over the years it becomes the family's own record: what we ate, when, in which season, and what we loved.

## Features

- **Fast capture.** On Sundays it opens straight to the camera. Other days it defaults to last Sunday, or to the date the photo was taken. Photo, then name, then Return saves.
- **Private star ratings.** Your stars stay in your own iCloud and nobody else sees them, not even the cook.
- **Family feed.** One shared timeline through iCloud sharing, grouped by year, with search across names, cooks, notes and food tags, plus season filters.
- **No duplicate dinners.** If someone already posted tonight's dinner, you're offered "Add my photos to it".
- **History.** "Every time we've had this" timeline, with your average for each dish.
- **What's for dinner?** Favorites you haven't had in a while, this time in past years, good for the season, upcoming holidays ("🦃 Thanksgiving is coming. Here's what we made before"), and Surprise me.
- **Memories.** An "A year ago this week" card, a Sunday streak, holiday badges, and milestone celebrations.
- **Food tags.** Apple's on-device Vision tags the first photo ("pasta", "soup"). Nothing leaves the phone.
- **Notifications.** A Sunday reminder (with a memory), plus "📸 New dinner posted" when someone in the family posts.
- **Widget.** Small and medium widgets with last Sunday's dinner, "a year ago this week", and the streak.

## How the data works

Everything lives in iCloud through Core Data and `NSPersistentCloudKitContainer`:

| What | Where | Who sees it |
| --- | --- | --- |
| Dinners and photos | Family share zone (owner's private DB, participants' shared DB) | Everyone in the family |
| Star ratings | Each person's private DB, default zone | Only you |

Whoever taps **Family → Invite family** first becomes the owner. Their existing dinners move into the share, and invitees join through a standard iCloud link. Ratings point to a meal by UUID rather than a relationship, so they never ride along into the share.

Suggestion and season logic lives in `Packages/SundayKit`. It's plain Swift with no Core Data, and it's unit tested.

## Getting started

Requirements: Xcode 16+, an iPhone on iOS 17+, and an Apple Developer account (iCloud/CloudKit needs one).

```sh
brew install xcodegen
xcodegen generate
open Sunday.xcodeproj
```

1. In **Signing & Capabilities**, choose your team. If `com.kirkouimet.sunday` is taken, change the bundle ID and the iCloud container ID in `project.yml` and `PersistenceController.swift`.
2. Make sure the iCloud container `iCloud.com.kirkouimet.sunday` is checked under iCloud → CloudKit.
3. Run on a real device signed into iCloud. Simulators can sync too, but sharing works best on devices.
4. First run only: set the environment variable `SUNDAY_INIT_CLOUDKIT_SCHEMA=1` in the scheme to push the schema to CloudKit's development environment. Before TestFlight or the App Store, **deploy the schema to production** in the [CloudKit Console](https://icloud.developer.apple.com).

Run the logic tests on their own:

```sh
swift test --package-path Packages/SundayKit
```

## Before shipping to TestFlight

- [ ] Set your team, bundle ID, iCloud container (`iCloud.com.kirkouimet.sunday`) and App Group (`group.com.kirkouimet.sunday`) in `project.yml`
- [ ] Run once with `SUNDAY_INIT_CLOUDKIT_SCHEMA=1`, then **deploy the schema to production** in the CloudKit Console. Do this again whenever the model changes (e.g. `Meal.tags`).
- [ ] Test sharing with two Apple IDs on two devices: invite, accept (with the app closed and with it open), both posting the same night, deleting, and ratings staying private
- [ ] Test upgrading from an older build (lightweight migration of the code-built Core Data model)
- [ ] Real app icon and screenshots

## Screenshots

CI can boot an iPhone simulator, walk every screen with sample data in light, dark and accessibility-large text, and publish PNGs to the `ci-screenshots` branch. It's slow (about 8 macOS minutes), so it only runs for commits whose message contains `[shots]`, or when started manually from the Actions tab.

## Roadmap

- Recipes and chef credits
- A year-in-review recap (on-device Foundation Models)
- An optional family score that people opt into sharing
- A printed photo book
