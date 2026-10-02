# Design loop log

An experiment: 10 rounds of *implement → screenshot on a real iOS 26 simulator → fresh design critique*.
Each critique rates maturity (1–10) and tags findings 🚀 leap (new concept/interaction),
🧱 structural (layout/flow), 🎨 polish. The question: do we plateau into marginal gains,
or do leaps keep appearing?

Canvas with screenshots and pinned critiques: claude.ai/design ("Sunday Design Review").

| Loop | Maturity | 🚀 | 🧱 | 🎨 | Biggest idea |
|---|---|---|---|---|---|
| 0 (baseline) | – | 3 | 6 | 8 | "Tonight" moment; cooks as people; Ideas as a decision tool |
| 9 | 8/10 | 0 | 2 | 6 | **The finish pass**: "ready to ship once it is trimmed". Concept count about 22 → about 14 (Ideas had 4 labels, Snap 6, the Live ending 3) · 5 bugs (identity leaks, two live dinners, unnamed start) · 5 ✂️. Critic, looking back: "the curve stopped producing leaps at round 6… every round since has rightly been subtraction and truth-telling" |
| 8 | 8/10 | 0 | 2 | 2 | **A four-phone rehearsal, walked through the code** (owner, offline phone, unnamed phone, force-quit phone at large text): "a different class of bug from the screenshot reviews… none are layout problems. They are about time and identity" · 7 bugs · 2 ✂️ |
| 7 | 8/10 | 0 | 3 | 2 | **Is Live multiplayer now? "Mostly yes, at the data layer"**, but "multiplayer for the person who started dinner; everyone else gets eventually consistent" · 7 bugs at the edges where a 2nd/3rd phone joins · 1 ✂️. Critic: "flat part of the curve, and that's the right place to be… if a loop proposes a new screen, the answer should be no" |
| 6 | 8/10 | 0 new (Live judged "partly a leap") | 6 | 2 | **Was loop 6 a leap? Partly**: "biggest step since loop 3… the app now has a present tense", but "single-player plumbing underneath" · 6 bugs, all in the new multiplayer core. Critic: "one step-change left: make Live actually multiplayer; then hardening, no new concepts" |
| 5 | 8/10 | 2 | 3 | 2 | **Sunday Live** (multiplayer, real-time: Live Activity, "I'm here", everyone's photos); talk instead of type (on-device model) · subtraction "worked" · 4 ✂️ · 4 bugs. Critic: "if loop 6 builds that, expect a genuine leap; if it builds screens, marginal gains" |
| 4 | 8/10 | 2 | 3 | 2 | 5 ✂️ cuts recommended (new) · Sunday Book (printed yearbook); voice → text · 3 bugs incl. data loss. Critic: "marginal value is now negative" |
| 3 | 8/10 | 3 | 3 | 4 | Interactive Lock Screen (rate/snap without opening the app); people as pages; heirloom voice · 3 bugs. Critic: "almost all refinement… screens at marginal gains" |
| 2 | 7/10 | 3 | 4 | 2 | Who was at the table (attendance); Sunday on the Lock Screen; heirloom recipe card · 5 bugs (mostly wiring of round-1 behaviors) |
| 1 | 6/10 | 2 (+2 public) | 4 (+2 public) | 4 (+1 public) | "The table remembers" (private insight); Sunday as a ritual (plan the cook ahead) · 3 bugs |

## Loop 0 → 1 (implemented)

Critique: "a beautifully styled record list more than a family keepsake."

- 🚀 **Tonight card** on the feed: "It's Sunday. What's cooking?" → after logging, "How was tonight's dinner?" with inline stars; "Missed last Sunday?" midweek.
- 🚀 **Cooks are people**: tinted initial avatars everywhere, a cook picker of known people (past cooks + share participants) with "Someone else".
- 🚀 **Ideas as a decision tool**: Surprise is a big shuffling photo card ("Tonight, how about…", *Let's make it* / *Another*); rows show "had 6×" instead of identical ★5; favorites sorted by longest-missed; duplicate "past years" section removed.
- 🧱 Keepsake type: New York serif for large titles, dish names, notes, the Family number.
- 🧱 Feed: latest dinner big (4:3), older dinners as a 2-column photo grid by year; no hard pinned header band; quiet streak; neutral season chips (less orange).
- 🧱 Detail: one meta line (date · [M] Mom · 🍂 Fall), outlined food tags, album-style serif notes, timeline with 32pt thumbnails and the average in its subtitle.
- 🧱 Editor: compact "Already posted" banner with two equal buttons; material photo tile; sheet titled with the date; order photo → name → stars → details.
- 🧱 Family: member avatar row with invite "+", superlatives (Most made, Head chef, Where it started), flame spacing fix, copy trimmed.
- 🎨 One rating language: interactive stars only in Detail/Editor/Tonight; compact ★ elsewhere; bounce + 5★ success haptic.

## Loop 1 → 2 (implemented)

Critique: "reads as a keepsake now, but still behaves like a logging tool — once the family has eaten, the app says nothing."

- 🚀 **The table remembers**: a private, own-stars-only line after rating: "Your 3rd lemon chicken. You liked it more than in August 2025." On Detail, and on the feed the morning after.
- 🚀 **Sunday as a ritual**: "Make it Sunday" from Ideas plans the dinner; the Tonight card shows "This Sunday: Lemon chicken" with a *Who's cooking?* picker; on Sunday, *Snap it* opens the camera and the photo joins the plan automatically. Logging becomes one photo.
- 🧱 Feed order Tonight → hero → memory → chips → grid; one rating prompt; avatars only with 2+ cooks.
- 🐛 Name suggestions moved above the keyboard; tab bar hidden on Detail; large-text timeline fixed.
- 🧱 Ideas: prominent *Make it Sunday*, quiet dice, current pick excluded, weekday copy. (Also fixed a flicker: the pick re-randomized each render.)
- 🧱 Family: superlatives only with contrast; invite first for a family of one.
- Public layer (design only): Star → **Save**; publish = fresh copy without family notes/faces; consented credits; tip after cooking.

Observation: round 1 produced the first *behavioral* leaps (the app talks back; the ritual starts before dinner), where round 0's leaps were about presence and identity.

## Loop 2 → 3 (implemented)

Critique: "the ritual loop exists, but its state machine hides its own best moments, and the family still isn't present." **Novelty check:** "diminishing returns on the screens themselves… genuinely new ideas are in a different category: new data and new places for the app to appear."

- 🚀 **Who was at the table**: one-tap faces in the editor (+ guests); Detail shows *At the table* with moments ("First Sunday with Grandma June", "Grandma's 25th Sunday"); Family gets *Sundays with* (Attendance in SundayKit, tested).
- 🚀 **Sunday leaves the app**: Lock Screen widgets (rectangular + inline) show "Tonight: Chili · Dad's cooking" from the plan, else a memory.
- 🚀 **Heirloom recipe**: after the 2nd time, "How do you make it?"; *How we make it — Mom's way* appears on every dinner of that dish (seed for the public layer).
- 🐛 State machine rebuilt: rating moved onto the hero card ("How was it?"); the Tonight card is only what's next — follow-up, plan, *remembered* (any weekday, dismissible), log, missed.
- 🐛 Plans are explicit (`isPlan`), never history: "Did you have Chili?" → *Add the photo / Yes, no photo / We didn't*; excluded from streak, counts, ideas, widget.
- 🧱 New-dinner form collapses until "already posted?" is answered; Save can't duplicate.
- 🐛 Large-text meta without orphan separators; capture harness taps a dedicated hero ID.
- 🎨 Ideas scrim; holiday emoji off grid tiles; "Sundays logged" for a family of one; cook picker includes share participants.

## Loop 3 → 4 (implemented)

Critique (8/10): "almost all refinement… the screens are at marginal gains. A step-change will come from making the person the primary object, and from moving core actions out of the app so Sunday needs zero app launches."

- 🚀 **Zero-launch Sunday**: interactive widgets. Monday morning the home and Lock Screen widgets ask "How was Chili?" with five tappable stars (AppIntent → App Group queue → saved as your private rating next time the app runs; `PendingRatings`, tested). On Sunday, the Lock Screen plan taps straight into the camera (`sunday://snap`).
- 🚀 **People as pages**: tapping any face (At the table, Family avatars, Sundays with) opens that person: Sundays at the table, first Sunday, what they cook, their recipes, a grid of their dinners.
- 🚀 **Heirloom voice**: the recipe sheet records the cook telling it (≤90s AAC on the dinner); the recipe card plays "Hear Mom tell it". A first-time guest prompts "Ask Grandma June how they make something".
- 🧱 Plan card *is* the memory ("A year ago this week · Chili. Again this Sunday?" → Make it Sunday / Other ideas); the separate memory card hides then. Streak moved into the Tonight card.
- 🐛 The private insight now sits under your stars on the hero card (no longer hijacks the Tonight card, survives relaunch); "Different dinner" + same name offers "Same dinner? Add your photos".
- 🧱 Detail: unrated stars move under the facts; recipe collapses to "How we make it · Mom's way ›"; fixed-width faces.
- 🎨 Large text: hero rating stacks, Ideas keeps its title (inline), Ideas words sit below the photo; hero 5:3 under a Tonight card; bottom content margin for the floating tab bar; season chips only after 24+ dinners.

## Loop 4 → 5: the subtraction loop (implemented)

Critique (8/10): "the marginal value is now negative: each round adds a concept without removing one… a step-change now means leaving the phone screen: **the Sunday Book**." First round to recommend cuts (✂️).

- 🐛 **Data loss fixed**: "Ask Grandma June" now records *her story* on that dinner (`story` / `storyAudio` / `storyBy`), never over the dish's recipe; the recipe keeps its teller (`recipeBy`), so "Hear Mom tell it" plays Mom.
- ✂️ **Cut**: the Ideas tab (now a sheet behind ✨ and "Other ideas", so 2 tabs: Dinners, Family); food-tag chips on Detail (tags still power search); season chip on the hero (holidays only); the streak flame on the Tonight card; Head chef / Most made superlatives; the second full star block (rated dinners show "Your stars ★4 · Change").
- 🚀 **Voice → text**: on-device Speech transcribes recordings into the recipe text (never leaves the phone).
- 🚀 **The Sunday Book**: Family tab makes a printable PDF yearbook: cover with who was around the table, then a page per dinner (photo, cook, at the table, notes, *How we make it · Mom's way*, guest stories). Share or print.
- 🐛 Family avatar row uses buttons (no stray chevrons) and keeps faces individually accessible; plan buttons wrap at large text; names in At the table wrap to two lines; timeline uses short dates without "Not rated".

## Loop 5 → 6: Sunday Live (implemented)

Critique (8/10): "Subtraction worked: the first round where the app feels lighter than the one before." But "the screens are definitively on the flat part of the curve. A step-change is still available, but not on a screen: Sunday as a live, multiplayer moment."

- 🚀 **Sunday Live.** On Sunday the plan card offers *We're sitting down*. The dinner goes live for the family (`liveAt` / `liveBy` / `liveEndedAt` sync through the share):
  - The feed shows a Live card: a pulsing dot, the dish, "Dad's cooking · 4 at the table · 2 photos", faces, everyone's photos so far, *I'm here*, *Snap*, and *That's dinner*.
  - A **Live Activity** runs on the Lock Screen and in the Dynamic Island, with faces, status, an *I'm here* button (a `LiveActivityIntent`, queued in the App Group so it survives a cold launch), and a tap anywhere to open the camera.
  - Other family phones get "🍽️ Sunday dinner is on · Dad's cooking Chili. At the table?" with *I'm here* / *Snap a photo* right on the notification. Their own Live Activity starts the moment they open the app (CloudKit can't push-to-start without a server).
  - Attendance reports itself: nobody taps faces in the editor any more. Each phone learns who it belongs to once ("Which one are you?").
- 🚀 **Talk instead of type.** After a recording is transcribed, *Sort into ingredients & steps* runs Apple's on-device model (Foundation Models, `@Generable`), keeping the cook's words, with a one-tap *Back to what was said*.
- 🐛 Transcription is on-device or nothing (no server fallback); it runs whenever a recording finishes (Stop, the time limit, or Save mid-recording); recordings run up to 10 minutes so Grandma can finish.
- 🐛 Detail: the bar takes the dish name once the big title scrolls under the glass buttons.
- 🐛 Sunday Book: each recipe prints once, in full, on its own page; the cover is a collage of the year; making it no longer freezes the UI.
- 🧱 The Book moved to the top of Family as an event (cover thumbnail, "N Sundays", "Ready to print for the holidays" in December).
- 🧱 *+* on a weekday after a logged Sunday starts a dinner for today instead of opening a clash.
- ✂️ The ✨ button is gone: Ideas lives in context ("Other ideas", "Still deciding?", "Change the plan"). Cut "Where it started", "Sundays with" when everyone ties, the hemisphere picker (the region decides), the season in Detail and the timeline, and the privacy line after your first rating.
- 🎨 Name suggestions are solid chips on the keyboard bar; the photo tile shrinks to a row while you type; *Another idea* uses a shuffle icon; the story sheet's placeholder fits stories.
- Public layer: follower and fork counts are cut from the profile; Requests puts *From your family* first (names shown, "Tell it" to record), with strangers' anonymous counts below.

## Loop 6 → 7: Live, for real (implemented)

Critique (8/10), on the question of the whole experiment: **"Was loop 6 a leap? Partly."** "As a concept it is the biggest step since loop 3's zero-launch widgets. The app now has a present tense… The implementation undercuts it": with a real family of four it "would likely show '2 at the table' and a 'Kirk' next to 'Dad'." Every bug was in the new core, so loop 7 is about making it true.

- 🐛 **Check-ins are records, not a string.** A `CheckIn` entity (name, time) lives in the dinner's zone like a photo; nothing is edited, so four phones tapping at once all count. `Meal.tablePeople` is the union; "That's dinner" folds it into `attendees`.
- 🐛 **Identity is the family's word for you.** No more iCloud-name fallback ("Kirk"): every phone is asked once, *Which one are you?*, from the family's names or "Someone else". A queued "I'm here" from an unnamed phone opens the app to ask (a foreground notification action and an `openAppWhenRun` intent), and then applies. No more false "Checked in".
- 🧱 **Live on any Sunday.** *We're sitting down* also appears when nothing was planned (name it later on the card: "What's cooking?"), and a dinner snapped on a Sunday evening offers *Go live* so the rest of the table can add theirs.
- 🧱 **The live moment is the hero.** The newest photo is big, with LIVE, the dish, status and faces over it; one primary action (*I'm here*, then *Snap a photo*); other photos below with their photographer's face.
- 🧱 **Photos have authors** (`Photo.by`): "Ellie's photo" on Detail, faces on the Live card's thumbnails.
- 🧱 **Tell the table**: a share sheet with a `sunday://live` link for anyone whose phone didn't buzz. This is the honest fallback, since CloudKit can't push-to-start a Live Activity without a server.
- 🐛 **Only the starter or the cook wraps up**, with a confirmation, and *Undo* for 6 seconds. Live also ends on its own (five hours, or 11:30 pm; tested).
- 🧱 **Structured recipes**: the on-device model's ingredients and steps are stored as `StructuredRecipe` JSON beside the text (tested). The Book lays them out as "You'll need" beside numbered steps. Over the model's context, the app says "Too long to sort in one go" instead of a silent nil.
- 🎨 The Live Activity shows the newest photo, *Snap* is its own button, and a tap opens the live card. "Who was at the table" is hidden in the editor while Live; the "since 6:10" line is gone.
- 🐛 **Found while building**: every widget refresh deleted everything in the App Group folder that wasn't a current thumbnail, *including the pending-ratings queue* (stars tapped on the Lock Screen could vanish before the app applied them). Now only stale thumbnails are removed (tested).
- Public layer: the post's Save/Fork counts are gone ("Save", "Make it yours"); the publish button now matches Requests ("Send to Ellie and Sam").

## Loop 7 → 8: the second phone (implemented)

Critique (8/10): "Live is structurally multiplayer. The remaining failures are no longer conceptual. They sit where a second or third phone joins, which is exactly where a real family will find them." Novelty check: **"There is no honest leap left that fits the no-server constraint."** Its plan: loop 8, the edges; loop 9, a four-device rehearsal; loop 10, cuts and finish.

- 🐛 **Snap at the table is just a photo.** *Snap* on the Live card goes camera → straight onto the dinner, signed with your name (`addLivePhoto`), then "Added to Chili · Undo". No form, no "already posted?", no stars at the table.
- 🐛 **Wrong check-ins come off.** Long-press a face → *Not here*. The editor now edits `tablePeople`, and unticking someone deletes their check-in.
- 🐛 **Queued check-ins don't haunt next week.** Taps wait while their dinner hasn't synced to this phone yet, expire after the evening, apply only to a live dinner, and keep the time you actually tapped (tested).
- 🐛 **An unplanned live dinner is history, not a question.** "That's dinner", or the evening ending on its own, settles it: check-ins become who was at the table, and it stops being a plan, so there's no "Did you have Sunday dinner?" with *We didn't* deleting the evening.
- 🧱 **Other phones' Lock Screens stop lying.** The Live Activity goes stale at the evening's end ("Wrapped up · tap to rate"), ends with its final faces left up for 15 minutes, and a check-in from a notification gets background time so iCloud can send it before iOS suspends the app.
- 🐛 The notification no longer invents a cook ("Dad sat down to dinner. At the table?").
- 🧱 **Who's missing** is the multiplayer payoff: dimmed, dashed faces for regulars who haven't checked in ("Sam and Grandma June aren't here yet"), right above *Tell the table*. The status line stops repeating the count; the thumbnail strip appears only from 3 photos.
- 🐛 One avatar palette in SundayKit, so Ellie is the same colour in the app, the widgets and the Live Activity (tested).
- 🐛 **Grandma's ten minutes can be sorted**: long tellings are split at sentence ends, sorted a piece at a time and merged (ingredients once, steps in order); a typo fix reads the card back in instead of dropping the structure (tested).
- 🎨 No workout timer on the Lock Screen.
- Public layer: every leftover count is gone (Save · 1.2k, Fork · 84, "41 people asked", Follow, a second "Since"). The critic's flag stands: anything beyond *a card to share* needs a server, so it's a separate product decision, not a loop item.

## Loop 8 → 9: time and identity (implemented)

Round 8 changed method: with one simulator and no second family, the critic **rehearsed one Sunday across four phones through the code**: Mom (owner, cook), Dad (offline 6:00–6:20), Ellie (phone never named), Grandma June (force-quit, large text). It traced 14 beats. "On paper the Sunday works… five beats still go visibly wrong for a real family." Novelty check: **"Rehearsing beat by beat found a different class of bug from the screenshot reviews. None of these are layout problems. They are about time… and identity."** The screenshots found only the large-text contrast issue.

- 🐛 **iCloud names stop haunting the table.** A `Member` record (account → family name) is written into the family zone when a phone answers *Which one are you?* (also on joining or creating the family). Participant names resolve through it, and *who's missing* and the picker leave unmapped accounts out, so there's no more "Kirk and Eleanor aren't here yet" next to Dad and Ellie. (The owner is keyed by role, since the owner's own record name is a placeholder on their phone.)
- 🐛 **A wrong identity can be undone.** Long-press your own face → *That's not me* (clears the name, takes back the check-in, asks again). Family has *This phone is Ellie · Change*.
- 🐛 **Snap from the Lock Screen or the notification** goes straight to the live dinner's camera, not the full form. An unnamed phone asks *Which one are you?* before Snap, so photos are signed.
- 🐛 **Undo never leaves the phone.** *That's dinner* stays local while the 6-second Undo toast is up (or until you leave the app), then it's sent. The Live Activity sync only counts *active* activities, so a resumed dinner starts a fresh one instead of updating an ended one.
- 🐛 **A stale phone can't restart dinner.** The first starter wins (`startLive` on a live dinner just checks you in). Until the first import after opening (or 12 seconds), *We're sitting down* reads "Checking with the family…".
- 🐛 The widget doesn't ask "How was Chili?" while everyone's still at the table; it republishes when dinner ends.
- 🧱 Offline: a photo snapped in a dead spot says "Saved. Sends when you're back online".
- ✂️ *Not here* on other people only for whoever started dinner or is cooking (no stray long-press removes Grandma); no "dinner is on" banner while you're looking at the Live card.
- 🎨 Large text: status, faces and who's missing move under the photo, where they're readable. *Tell the table* is addressed to who's missing ("Grandma June, Sam, dinner's on: Chili…").
- Not fixable from here, and said plainly: a force-quit phone gets no silent push, so without a server *Tell the table* is the only way to reach Grandma. The critic also wants a real two-device check of the late-phone and Undo beats.

## Loop 9 → 10: one name per idea (implemented)

Critique (8/10): "Sunday is ready to ship once it is trimmed. Loop 10 should not add anything." It counted about 22 nouns and verbs a grandparent meets today and asked for about 14.

- ✂️ **One word each.** Snap → *Snap a photo* (it had six wordings, across the app, the Lock Screen and the reminder). Ideas → *Ideas* (it had four). Live starts with *We're sitting down* and ends with *That's dinner* ("Go live", "Wrap up" and "wrapped up" are gone). The guest button says *tell a story*, because it records a story, not the dish's recipe.
- ✂️ **No Live for a family of one**: no "I'm here" for yourself, no "Tell the table" with nobody at it.
- ✂️ *Sundays with* is gone (people pages do it). The *Sort into ingredients & steps* button is gone too: recipes sort themselves after transcription, with *Back to what was said* as the only control. Dead `resumeLive` removed.
- 🐛 **Family names everywhere**: the cook picker, the Family row and "Joined: Mom's family" use Member names; unmapped iCloud accounts are left out by default.
- 🐛 **One live dinner**: a second phone's unplanned *We're sitting down* joins the first, and every path (the card, the Lock Screen, the store) picks the earliest start.
- 🐛 **Dinner is started by a person**: an unnamed phone asks *Which one are you?* first (otherwise everyone could end it). New owners and joiners are asked once right after the family forms. The picker marks names already "On another phone".
- 🐛 **"That's dinner" can't be held back**: the 6-second commit has its own timer, so another toast or a tab switch can't hold it. A participant's "checking with the family" waits for the shared store's import specifically.
- 🎨 With a family, Sunday's card leads with *We're sitting down* (Snap is secondary, since Live has its own); *Ideas* disappears after 3 pm. "Sundays logged" says "dinners" once a Friday birthday is in it (and so does the Book). VoiceOver gets the face actions (*That's not me*, *Not here*); the Live footer clears the tab bar at large text.
