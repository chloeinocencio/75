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
  IndexedDB. iOS writes them to the app's private Application Support directory with
  complete file protection (encrypted whenever the phone is locked), downscaled to
  2400 px. They're not in the photo library, but they *are* part of the user's own
  encrypted device backup — that's what lets them move to a new iPhone.
- Delete any photo from the full-screen viewer; under 75 Hard, deleting the day's only
  photo un-ticks the photo task.

## Where your data lives

**Web:** everything is on the device — `localStorage` for the challenge, `IndexedDB`
for photos. No account, no server-side storage, no analytics. Clearing site data
erases it; Settings → Start over erases it deliberately. Friends on the web are a
device-local list and the copy says so plainly.

**iOS:** the challenge and photos are on the device (SwiftData + protected files).
**Friends** is the one optional exception, and is built on CloudKit:

- Identity is the user's iCloud account (an anonymous, app-scoped record ID). No
  passwords, phone numbers or emails are stored. Sign in with Apple was deliberately
  *not* used: Apple requires its tokens be revoked server-side on account deletion,
  which would mean running a server.
- People connect with an 8-character invite code. A connection only shows progress
  once **both** people have added each other.
- Shared: display name, tier, day, streak, today's %. Never photos, notes or weight.
- Block (hides future requests), Report (emails support), and Delete my Friends
  profile (removes the profile and every connection the user created) are in the app.
- Anything fetched from CloudKit is treated as untrusted and clamped/sanitised.
- CloudKit is Apple-hosted and scales with no server bills on our side.

Privacy policy: `web/privacy.html` (served by the web deploy — use its URL in App
Store Connect).

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

Swift source plus an [XcodeGen](https://github.com/yonaskolb/XcodeGen) manifest, rather
than a checked-in `.xcodeproj` (those don't diff or merge well). On a Mac with Xcode 15+:

```sh
brew install xcodegen   # one-time
xcodegen generate
open SeventyFive.xcodeproj
```

In Xcode → target → Signing & Capabilities, pick your team (or set `DEVELOPMENT_TEAM`
in `project.yml`). Friends needs a **paid** developer team for iCloud.

The Simulator has no camera, so the capture screen offers the photo picker there.
Run on a real device to test the camera and Face ID.

### CloudKit setup (once)

1. Xcode → Signing & Capabilities → iCloud: make sure CloudKit is ticked and the
   container `iCloud.com.chloeinocencio.seventyfive` exists (Xcode creates it).
2. Run the app on a device signed into iCloud, turn on Friends, and add a friend once —
   this creates the `Profile` and `Connection` record types in the Development schema.
3. In [CloudKit Console](https://icloud.developer.apple.com) → Schema → Indexes, add
   **Queryable** indexes: `Profile.inviteCode`, `Connection.from`, `Connection.to`, and
   `recordName` on both types.
4. Before submitting: Schema → **Deploy Schema Changes** to Production.

### App Store checklist

- [ ] Team set, bundle ID `com.chloeinocencio.seventyfive` registered, iCloud container created
- [ ] CloudKit schema + indexes deployed to Production
- [ ] Web build deployed so `privacy.html` has a public URL; update `SupportInfo.privacyPolicyURL`
- [ ] App Store Connect privacy label matches `PrivacyInfo.xcprivacy`: Name, User ID,
      Fitness — linked to user, not used for tracking, App Functionality only
- [ ] Support URL + support email (`SupportInfo.email`)
- [ ] Age rating questionnaire (user-generated content: display names only, with block/report)
- [ ] Screenshots: 6.9" and 6.5" iPhone
- [ ] Archive → Validate → Distribute; TestFlight first

## Layout

```
.replit                Replit run + deploy config
package.json           npm start -> web/server.js
web/
  index.html           App shell (CSP: no inline script)
  app.css              Theme tokens, light and dark
  app.js               Rules, storage, screens, camera, validated backup import
  server.js            Hardened static file server
  privacy.html         Privacy policy (App Store needs a URL)
project.yml            XcodeGen manifest (target, Info.plist, entitlements)
SeventyFive/
  App/                 Entry point, tabs, privacy shield + app lock
  Design/              Theme tokens, living aura background
  Models/              Challenge, DailyEntry, ProgressPhoto, ChallengeMode
  Services/            Photo storage + image cache, reminders, app lock,
                       Social/ (CloudKit friends)
  Features/
    Onboarding/        Tier picker, locale-aware body weight, health note
    Today/             Checklist, 75-day mosaic, yesterday grace, finish card
    ProgressPhoto/     Capture (ghost overlay), timeline + delete, before/after
    Friends/           Invite codes, requests, block/report
    Settings/          Reminders, units, app lock, sharing, data
  Resources/           Asset catalog (icon, colours), PrivacyInfo.xcprivacy
```

The Swift module is named `SeventyFive` rather than `75` — a module name can't
begin with a digit.
