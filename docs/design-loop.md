# Design loop log

An experiment: 10 rounds of *implement → screenshot on a real iOS 26 simulator → fresh design critique*.
Each critique rates maturity (1–10) and tags findings 🚀 leap (new concept/interaction),
🧱 structural (layout/flow), 🎨 polish. The question: do we plateau into marginal gains,
or do leaps keep appearing?

Canvas with screenshots and pinned critiques: claude.ai/design ("Sunday Design Review").

| Loop | Maturity | 🚀 | 🧱 | 🎨 | Biggest idea |
|---|---|---|---|---|---|
| 0 (baseline) | – | 3 | 6 | 8 | "Tonight" moment; cooks as people; Ideas as a decision tool |
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
