# Design loop log

An experiment: 10 rounds of *implement → screenshot on a real iOS 26 simulator → fresh design critique*.
Each critique rates maturity (1–10) and tags findings 🚀 leap (new concept/interaction),
🧱 structural (layout/flow), 🎨 polish. The question: do we plateau into marginal gains,
or do leaps keep appearing?

Canvas with screenshots and pinned critiques: claude.ai/design ("Sunday Design Review").

| Loop | Maturity | 🚀 | 🧱 | 🎨 | Biggest idea |
|---|---|---|---|---|---|
| 0 (baseline) | – | 3 | 6 | 8 | "Tonight" moment; cooks as people; Ideas as a decision tool |
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
