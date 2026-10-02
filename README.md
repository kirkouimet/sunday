# Sunday

A private iPhone app for the family's Sunday dinners. Snap a picture, name the dish, and give it your private stars. Over the years it becomes the family's own record: what we ate, when, in which season, and what we loved.

## Features (v1)

- **Fast capture.** Opens straight to the camera. Add photos, a name, who cooked, and notes.
- **Private star ratings.** Your stars stay in your own iCloud and nobody else in the family sees them.
- **Family feed.** One shared timeline through iCloud sharing, with no accounts or servers.
- **History.** Search every dinner, filter by season, and see every time you've had a dish.
- **What's for dinner?** Suggests favorites you haven't had in a while, dinners from this time in past years, picks for the current season, and has a "Surprise me" button.
- **Sunday reminder.** A weekly nudge to take the picture, with a "a year ago this week" memory.

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

## Roadmap

- v2: "On this day" memories in the feed, holiday tags, and widgets.
- v3: Recipes and chef credits, a year-in-review recap, and a printed photo book.
