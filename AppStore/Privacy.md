# Sunday: privacy answers and the two web pages

## App Privacy label (App Store Connect › App Privacy)

Answer **"No, we do not collect data from this app."** The label reads **Data Not Collected**.

Why that is accurate:

- Dinners, photos, notes, recordings and family names are stored in the family owner's private iCloud database and shared through Apple's iCloud sharing. Star ratings are stored in each person's own private iCloud database. The developer has no access to either. Apple's definition of "collect" is data sent off the device in a way the developer can access; this is not.
- Photo naming and captions, food tags, speech-to-text and recipe tidying all run on the device.
- There is no analytics SDK, no ads, no account, and no third-party code.
- The app makes one request of its own: it reads `https://www.sunday.cooking/api/app.json` on launch. It sends no identifier and no content. Keep that true on the server side: don't log anything beyond what the host logs by default, and never join those logs to anything else.

Tracking: **No.** The privacy manifest (`Sunday/PrivacyInfo.xcprivacy`) declares no tracking, no collected data, and one required-reason API (UserDefaults, reason `CA92.1`).

## Age rating questionnaire

Answered in App Store Connect on October 5, 2026. Calculated rating: **4+**.

| Step | Answer |
|---|---|
| In-app controls (parental controls, age assurance) | No |
| Unrestricted web access | No |
| User-generated content | No. Apple's question is about "broad distribution" of user content; Sunday's dinners go only to a private family group the owner invites by link |
| Social media | No |
| Messaging and chat | No. "Tell the table" opens the system share sheet; there is no in-app messaging |
| Advertising | No |
| Mature themes, medical, sexuality, violence, chance-based activities | None |
| Age categories and override | Not Applicable (not "Made for Kids") |

## Permission prompts already in the app

| Permission | Text shown |
|---|---|
| Camera | Sunday uses the camera to take pictures of family dinners. |
| Microphone | Sunday records the cook telling how they make a family recipe. |
| Speech recognition | Sunday turns recorded recipes into text on your iPhone so you can read and search them. |
| Notifications | Asked only when you turn on the Sunday reminder or join a family. |

Photos are added through the system photo picker, which needs no permission.

---

## Page: https://www.sunday.cooking/privacy

```
Privacy Policy

Last updated: October 5, 2026

Sunday is a private album of your family's Sunday dinners, made by Kirk Ouimet LLC. This page says what happens to your information. The short version: we don't collect it.

What Sunday stores, and where
Your dinners, photos, notes, recipes, recordings and the names of people at your table are stored in your iCloud account, using Apple's iCloud service. When you invite your family, those dinners are shared with the people you invite through Apple's iCloud sharing. Your star ratings are stored only in your own iCloud account and are never shared with anyone, including your family.

We do not have access to any of this. It is not sent to us, and we could not read it if we wanted to.

What happens on your device
Naming a dinner from its photo, writing a caption, tagging food, turning a spoken recipe into text and sorting it into steps all happen on your iPhone or iPad using Apple's on-device features. Your photos and recordings are not sent to us or to anyone else for this.

What we collect
Nothing. Sunday has no accounts, no ads, no analytics and no tracking.

When the app opens, it downloads a small settings file from our website to check whether your version is still supported. That request contains no information about you or your dinners. Like any website, our host may briefly log the network address a request came from; we do not use those logs to identify anyone.

Children
Sunday is a general family app. We do not knowingly collect information from anyone, including children, because we do not collect information at all.

Deleting your data
Delete a dinner in the app and it is removed from iCloud for everyone it was shared with. To remove everything, delete the app's data under Settings › your name › iCloud › Manage Account Storage › Sunday. If you started the family, choosing Stop Sharing in the invite sheet removes the shared dinners from everyone you invited.

Apple
iCloud is provided by Apple and covered by Apple's privacy policy: https://www.apple.com/legal/privacy/

Changes
If this policy changes, we will update this page and the date above.

Contact
Kirk Ouimet LLC
contact@sunday.cooking
```

## Page: https://www.sunday.cooking/support

```
Sunday Support

Email contact@sunday.cooking and a person will answer.

Getting started
Open Sunday, tap +, take or choose a photo, name the dinner, and save. On Sundays the app opens straight to the camera.

Do I need an account?
No. Sunday uses the iCloud account already on your iPhone or iPad. Make sure you're signed in to iCloud and that iCloud Drive is on in Settings.

How do I add my family?
Open the Family tab and tap Invite family. Send the link by Messages or Mail. Whoever invites first starts the family; everyone who accepts sees the same dinners and can add photos.

Who can see my stars?
Only you. Your ratings are kept in your own iCloud and are never shared, not even with the cook.

My dinners aren't showing up on another device
Check that both devices are signed in to iCloud, have a connection, and have iCloud turned on for Sunday. Opening the app on both devices usually brings them up to date within a minute.

The app didn't suggest a name for my photo
Photo names and captions need an iPhone or iPad that supports Apple Intelligence, on iOS 27 or later, with Apple Intelligence turned on. Everything else works without it.

How do I delete a dinner?
Open the dinner, tap the menu at the top, and choose Delete. It is removed for everyone in your family.

How do I delete everything?
Go to Settings › your name › iCloud › Manage Account Storage › Sunday and delete the data.

Privacy
Sunday doesn't collect your information. Read the full policy at https://www.sunday.cooking/privacy
```

## File: https://www.sunday.cooking/api/app.json

Serve this as `application/json`. Leave `minimumVersion` at `1.0` until a version actually has to be retired; raise it and old builds show "Time to update Sunday". Put the App Store link in `updateURL` once the app has one.

```json
{ "minimumVersion": "1.0" }
```
