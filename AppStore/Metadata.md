# Sunday: App Store metadata, English (U.S.)

Paste-ready copy for every App Store Connect field. Limits are Apple's; `AppStore/check.py` measures every field below against them.

## App information

| Field | Limit | Value |
|---|---|---|
| Name | 30 | `Sunday: Family Dinners` |
| Subtitle | 30 | `Your family's dinner album` |
| Bundle ID | | `cooking.sunday.Sunday` |
| SKU | | `sunday-ios-1` |
| Primary language | | English (U.S.) |
| Primary category | | Food & Drink |
| Secondary category | | Lifestyle |
| Content rights | | Does not contain third-party content |
| Age rating | | 4+ (answers in `Privacy.md`) |
| Copyright | | `2026 Kirk Ouimet LLC` |
| Price | | Free, no in-app purchases |

The name on the home screen stays `Sunday`. Plain "Sunday" is almost certainly taken as a store name; if `Sunday: Family Dinners` is taken too, use `Sunday Dinner Album`.

Spare subtitles, all within 30: `Snap it, name it, remember it` · `Dinner photos, kept for years`

## URLs and contact

| Field | Value |
|---|---|
| Support URL | `https://www.sunday.cooking/support` |
| Marketing URL | `https://www.sunday.cooking` |
| Privacy Policy URL | `https://www.sunday.cooking/legal/privacy-policy` |
| Contact email | `contact@sunday.cooking` |
| Seller | Kirk Ouimet LLC (the App Store shows the legal entity name on the developer account; it currently reads "Kirk Ouimet", ask Apple Developer Support to match it to the D-U-N-S record if you want "LLC" shown) |

## Promotional text (170)

```
Snap a photo of Sunday dinner, name the dish, and give it your private stars. Years from now it's your family's own record of what you ate and what you loved.
```

## Description (4000)

```
Sunday is a private album of your family's Sunday dinners.

Take a picture, name the dish, and give it your stars. That's it. Week after week it becomes something no recipe site can give you: your family's own record of what you ate, when, in which season, and what everyone loved.

MADE FOR ONE QUICK MOMENT
On Sundays the app opens straight to the camera. Photo, then name, then save. If you forgot, add it later from your camera roll and the date comes from the photo.

STARS ONLY YOU CAN SEE
Rate every dinner from one to five. Your stars stay in your own iCloud. Nobody else sees them, not even the cook.

ONE ALBUM FOR THE WHOLE FAMILY
Invite your family with a link. Everyone adds photos to the same timeline, grouped by year. If someone already posted tonight's dinner, your photos join theirs.

IT KNOWS WHAT'S FOR DINNER
On iPhones with Apple Intelligence, Sunday looks at the photo on your device, offers a name while you type, and writes one line about what's on the table so you can search for it later. Your photos never leave your phone for this.

WHAT SHOULD WE MAKE?
Ideas come from your own table: favorites you haven't had in a while, what you ate this week in past years, what suits the season, and what you made last Thanksgiving.

THE FAMILY RECIPE, IN THEIR OWN VOICE
Record the cook telling how they make it. Sunday turns the telling into ingredients and steps, on your device, and keeps the recording.

SUNDAY LIVE
Tap "We're sitting down" and everyone can check in and add photos while dinner is on the table.

MEMORIES THAT COME BACK
"A year ago this week", a Sunday streak, holiday badges, and a home screen widget with last Sunday's dinner.

PRIVATE BY DESIGN
Everything lives in iCloud. There is no account to create, no ads, and no tracking. We can't see your dinners, your photos or your stars.

Sunday needs iCloud to sync and share with your family.
```

## Keywords (100 bytes)

```
meal,journal,food,diary,recipe,photo,tradition,supper,cook,memories,rating,log,table,kids,grandma
```

Words already in the name and subtitle (sunday, family, dinner, album) are left out on purpose: Apple indexes those already.

## What's New (4000)

Not shown for version 1.0. For the first update, lead with one sentence saying what changed.

## Pricing and availability

- Price: Free.
- Availability: all countries and regions, **except** hold the European Union until the Digital Services Act trader status is declared in App Store Connect (Business section). Declaring as a trader publishes a contact address and phone number on the listing.
- Devices: iPhone and iPad. Not offered on Mac or Apple Vision Pro for version 1 (untick "Make this app available" for both under Pricing and Availability).

## Build

- Version `1.0`, build `1` (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml`).
- Export compliance is already answered in the Info.plist (`ITSAppUsesNonExemptEncryption` = false): the app uses only Apple's standard encryption.
