# 75

Native SwiftUI app for tracking the **75 Soft**, **75 Medium**, and **75 Hard**
challenges, with progress photos as a first-class feature.

## The three tiers, as implemented

The tiers differ in more than difficulty — they have genuinely different rules,
different units, and different failure semantics. The app models all three
rather than treating them as one checklist with a strictness dial.

| | 75 Soft | 75 Medium | 75 Hard |
|---|---|---|---|
| **Workout** | 45 min, 1×/day | 45 min, 1×/day | 45 min, 2×/day (1 outdoors) |
| **Rest days** | 1 active-recovery day/week | none | none |
| **Diet** | Eat well | On plan 90% of the time | Strict, zero cheat meals |
| **Alcohol** | Social occasions only | None | None |
| **Water** | 3 L | ½ body weight in oz | 1 gallon |
| **Reading** | 10 pages, any book | 10 minutes, incl. podcasts | 10 pages, non-fiction only |
| **Meditation** | — | 5 min/day | — |
| **Progress photo** | Day 1 + Day 75 | Day 1 + Day 75 | **Daily, required** |
| **Miss a day** | Continue, no penalty | Up to 7 misses (finish 68/75) | **Restart at Day 1** |

Those last two rows drive real behavior:

- **Photo cadence.** A daily progress photo is a 75 Hard rule, not a universal
  one. Soft and Medium put the photo on a milestone card (Day 1 and Day 75,
  optional in between) instead of in the daily checklist, so the checklist
  reflects what the tier actually requires.
- **Failure policy.** `FailurePolicy` is `.forgiving` / `.allowedMisses(7)` /
  `.restartFromDayOne`. Hard shows a restart banner after a missed day and
  keeps an attempt counter; Medium shows a "misses left" stat instead of an
  overall-percentage stat.
- **Water units.** Medium scales to body weight, so onboarding asks for it and
  `WaterGoal.resolvedLiters(bodyWeightPounds:)` resolves the goal per tier.

### On rule accuracy

75 Hard is a specific program with published rules
([andyfrisella.com](https://andyfrisella.com/blogs/articles/what-is-75-hard)) —
those are implemented as written.

75 Soft and 75 Medium are community variants with no owner, and published
versions disagree on details. The rules above follow the most widely repeated
consensus ([Cleveland Clinic](https://health.clevelandclinic.org/75-soft-challenge),
[Healthline](https://www.healthline.com/health/75-soft-challenge),
[Marathon Handbook](https://marathonhandbook.com/75-medium-challenge/)). Since
nobody owns them, per-user goal overrides are a reasonable future addition.

## Progress photo features

- **Ghost overlay** — your last photo of the same pose is superimposed at
  adjustable opacity so you can match framing day to day.
- **Align mode** — switches to a difference blend; the outline fades toward
  black as your pose matches, which is faster than judging opacity by eye.
- **Poses** — Front / Side / Back tracked separately, each with its own
  overlay history and timeline.
- **Timeline** — grid of every photo per pose, tap into a swipeable viewer.
- **Before/After compare** — pick any two days, drag a divider to reveal one
  over the other, share a flattened composite via the system share sheet.
- Photos are stored as JPEGs in the app's private Application Support
  directory — not the Photos library, not iCloud. SwiftData holds filenames,
  never image blobs.

## What's a stub, on purpose

Friends are stored **only on this device**. There's no backend, so adding a
friend doesn't notify or verify them, and the "Share My Progress" toggle
doesn't transmit anything yet.

Shipping real sharing needs:
- Phone verification (Firebase Phone Auth or Twilio Verify)
- A datastore for friend graphs and daily progress snapshots (Firebase or
  Supabase are the fastest paths for a solo iOS dev)
- Push notifications for invites and nudges (APNs)

Everything else works offline and on-device.

## Opening the project

Swift source plus an [XcodeGen](https://github.com/yonaskolb/XcodeGen)
manifest, rather than a checked-in `.xcodeproj` (those don't diff or merge
well). On a Mac with Xcode 15+:

```sh
brew install xcodegen   # one-time
xcodegen generate
open SeventyFive.xcodeproj
```

Run on a real device to test the camera — the Simulator has no camera, so the
capture screen shows its permission-denied state there.

## Layout

```
project.yml            XcodeGen manifest (target, Info.plist, permissions)
SeventyFive/
  App/                 Entry point + root tab navigation
  Models/              Challenge, DailyEntry, ProgressPhoto, Friend, ChallengeMode
  Services/            PhotoStorageService (on-disk JPEG storage)
  Features/
    Onboarding/        Tier picker (Soft/Medium/Hard) + body weight for Medium
    Today/             Daily checklist, streak, restart banner
    ProgressPhoto/     Capture, timeline, before/after compare
    Friends/           Friend list + sharing toggle (local-only, see above)
```

The Swift module is named `SeventyFive` rather than `75` — a module name can't
begin with a digit.
