# 75

Track the **75 Soft**, **75 Medium** or **75 Hard** challenge, with progress
photos as a first-class feature.

Two builds share one set of rules:

- **`web/`** — the web app. Runs anywhere, deploys to Replit, stores everything
  on the device. This is what ships today.
- **`SeventyFive/`** — the native iOS app (SwiftUI). Builds on a Mac with Xcode
  and ships through TestFlight / the App Store.

## Running the web app

```sh
npm start          # http://localhost:3000
```

No dependencies and no build step — plain HTML, CSS and JavaScript served by a
small Node file server.

### Deploying on Replit

Import this repository into Replit. The committed `.replit` sets Node 20 and
`npm start`, so **Run** works immediately and **Deploy** (autoscale) publishes
it. Port 3000 is mapped to 80.

The camera needs a secure context: it works on Replit's HTTPS URL and on
`localhost`, and falls back to picking a photo from the device anywhere it
isn't available.

## The three tiers

The tiers differ in more than difficulty — they have genuinely different rules,
different units, and different failure semantics. Both builds model all three
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

## Progress photos

- **Ghost overlay** — your last photo of the same pose is superimposed on the
  viewfinder at adjustable opacity, so you can match framing day to day.
- **Align mode** — switches to a difference blend; the outline fades toward
  black as your pose matches, which is faster than judging opacity by eye.
- **Poses** — Front / Side / Back tracked separately, each with its own
  overlay history and timeline.
- **Timeline** — every photo per pose, tap through to a full-screen viewer.
- **Before / After** — pick any two days and drag a divider between them. The
  web build writes a side-by-side image to your downloads; iOS uses the share
  sheet.
- Photos never leave the device on their own. The web build keeps them in
  IndexedDB; iOS writes JPEGs to the app's private Application Support
  directory — not the photo library, not iCloud.

## Where your data lives

Everything is stored on the device and nowhere else. There is no account, no
server, and no analytics.

The web build uses `localStorage` for your challenge and `IndexedDB` for
photos, which means clearing the browser's site data erases it, and it doesn't
follow you to another browser or device. Settings → Start over erases it
deliberately.

**Friends are device-local too.** You can add people by phone number and keep
the list, but nothing is transmitted: connecting two phones needs a server this
build doesn't have. The in-app copy says so plainly rather than implying an
invite was sent.

Adding real sharing would need:
- Phone verification (Firebase Phone Auth or Twilio Verify)
- A datastore for friend graphs and daily progress snapshots (Firebase or
  Supabase are the fastest paths)
- Push notifications for invites and nudges

## Counting days

A day boundary is a civil date — year, month, day — resolved in the device's
current time zone, never an absolute instant. That keeps the count correct
across a daylight-saving change and across travel: an instant that was midnight
where you started is not midnight anywhere else, and comparing against it
silently drops or repeats a day. The count is also clamped so it can never run
backwards, since crossing the date line westward repeats a local date.

Both builds re-check the day when they come back to the foreground, so leaving
the app open past midnight rolls over correctly.

## Building the iOS app

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
.replit                Replit run + deploy config
package.json           npm start -> web/server.js
web/
  index.html           App shell
  app.css              Theme tokens, light and dark
  app.js               Rules, storage, screens, camera
  server.js            Static file server
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
