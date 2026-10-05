# Sunday: App Review notes

## App Review Information (App Store Connect › version page)

| Field | Value |
|---|---|
| Sign-in required | **No** (untick). There is no account. |
| Contact first name / last name | Kirk Ouimet |
| Contact email | `contact@sunday.cooking` |
| Contact phone | [YOUR PHONE NUMBER] |

## Notes (4000 bytes): paste this

```
Thank you for reviewing Sunday.

WHAT IT IS
A private album of a family's Sunday dinners: take a photo, name the dish, rate it. There is no account and no login. The app uses the iCloud account already on the device.

HOW TO TEST
1. Make sure the device is signed in to iCloud with iCloud Drive on. (Signed out, the app still opens and explains that iCloud is needed to sync and share.)
2. Tap + (top right), choose or take a photo, type a name, tap Save.
3. Open the dinner to rate it with stars, add notes, or add a recipe.
4. Tap the ideas button on the Dinners tab for "What's for dinner?" suggestions. These appear once there are a few dinners.
5. Family tab: "Invite family" creates a standard iCloud share (CKShare) and opens Apple's sharing sheet. Testing an accepted invite needs a second Apple Account on a second device; the app is fully usable by one person without it.

DATA AND PRIVACY
All content is stored in the user's private iCloud database (CloudKit) and, when shared, in Apple's CloudKit shared database. Star ratings are stored only in each person's private database. We operate no server that receives user data, and we collect nothing. The only network request to our own domain is a GET of a small JSON settings file (https://www.sunday.cooking/api/app.json) used to tell very old versions to update; it carries no identifiers.

PERMISSIONS
Camera: photographing dinner. Microphone and Speech Recognition: optional, only when recording a cook telling a recipe; transcription is on device. Notifications: optional Sunday reminder and "new dinner posted" alerts. Photos are picked with the system photo picker.

BACKGROUND MODE
Remote notifications are used only for CloudKit's silent pushes that keep the family's dinners in sync.

ON-DEVICE INTELLIGENCE
On devices with Apple Intelligence (iOS 27 or later), the app uses Apple's Foundation Models framework on device to suggest a dish name from the photo, write a one-line caption, and tidy a dictated recipe. On other devices these features simply do not appear. Nothing is sent off the device and no third-party AI service is used.

LIVE ACTIVITIES AND WIDGET
"Sunday Live" shows a Live Activity while a dinner is in progress. The home screen widget shows last Sunday's dinner and a streak.

There are no purchases, ads, or external links to purchases.
```

## Guideline check

| Guideline | Status |
|---|---|
| 2.1 App completeness | Works signed out of iCloud (shows guidance), with no dinners (empty state), and with no family. |
| 2.3 Accurate metadata | Screenshots are the real app with sample dinners. Stock photos, not a real family. |
| 2.5.4 Background modes | `remote-notification` only, for CloudKit sync. |
| 4.2 Minimum functionality | Native capture, sharing, widget, Live Activity. |
| 5.1.1 Data collection | No account, nothing collected, purpose strings present, privacy policy linked. |
| 5.1.2 Data use and sharing | No third-party SDKs, no tracking. |
| 5.1.4 Kids | General audience, not in the Kids Category. |
| 1.2 User-generated content | Content is visible only to a private, invite-only family group, so public UGC moderation requirements do not apply. If a reviewer asks: any member can delete a dinner they posted, and the owner can stop sharing or remove a participant from Apple's sharing sheet. |

## Before pressing Submit

- [ ] Program License Agreement and Free Apps Agreement show Active.
- [ ] `www.sunday.cooking/legal/privacy-policy`, `/support` and `/api/app.json` are live.
- [ ] CloudKit schema deployed to Production (CloudKit Console › `iCloud.cooking.sunday.Sunday` › Deploy Schema Changes), after one run with `SUNDAY_INIT_CLOUDKIT_SCHEMA=1`.
- [ ] Family sharing tested with two Apple Accounts on two devices, on a TestFlight build.
- [ ] iPhone 6.9" and iPad 13" screenshots uploaded (`AppStore/Screenshots/`).
- [ ] App Privacy label answered (`Privacy.md`) and age rating answered.
- [ ] EU availability decided (trader status).
