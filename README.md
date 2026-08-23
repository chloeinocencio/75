# 75

Native SwiftUI app for tracking the 75 Soft / 75 Hard challenge, with daily
progress photos as a first-class feature.

## What's built and working

- **Onboarding** — pick 75 Soft or 75 Hard, starts your 75-day countdown.
- **Today** — daily checklist generated from your mode's rules (workouts,
  diet, water with a live counter, reading pages, progress photo, no-alcohol
  for Hard mode), a completion ring, streak, and overall % complete. 75 Soft
  also exposes a weekly rest-day toggle; 75 Hard does not.
- **Progress Photo capture** — full-screen camera with:
  - A **ghost overlay** of your most recent photo (per pose) at adjustable
    opacity, so you can line up the same framing every day.
  - An **Align mode** that switches to a difference blend — the outline
    fades to black as your pose matches, which is faster than eyeballing
    opacity.
  - Front / Side / Back pose selector, front/back camera flip, retake flow.
  - Photos are saved as JPEGs in the app's private Application Support
    directory (not your Photos library, not iCloud) — referenced by
    filename from SwiftData, so the database itself never holds image blobs.
- **Photo Timeline** — grid of every day's photo per pose, tap into a
  swipeable full-screen viewer.
- **Before/After Compare** — pick any two days, drag a divider to reveal one
  photo over the other, and explicitly share a composited image via the
  share sheet.
- **Friends (local only, see below)** — add a friend by phone number, a
  single "Share My Progress" toggle. Progress *photos* are never shared by
  that toggle — only by the explicit Compare-view share action.

## What's a stub, on purpose

Friends today are stored **only on your device**. There is no backend, so:

- Adding a "friend" doesn't notify them or verify their number.
- The share toggle doesn't transmit anything anywhere yet.

Shipping real friend sharing needs a small backend, which we should scope
next:
- Phone number verification (e.g. Firebase Phone Auth or Twilio Verify).
- A server/datastore for friend graphs and daily progress snapshots
  (Firebase/Firestore or Supabase are the fastest paths for a solo iOS dev).
- Push notifications for invites and daily nudges (APNs).

None of that is required to use the app solo — everything else (checklist,
streaks, and the photo features you asked about) is fully functional
offline, on-device.

## Opening the project

This repo ships Swift source + an [XcodeGen](https://github.com/yonaskolb/XcodeGen)
manifest instead of a checked-in `.xcodeproj` (those don't diff or merge
well). On a Mac with Xcode 15+:

```sh
brew install xcodegen   # one-time
xcodegen generate
open 75SoftTracker.xcodeproj
```

Run on a real device to test the camera — the iOS Simulator has no camera
hardware, so the capture screen will show the "camera access needed" state
there.

## Project layout

```
project.yml                     XcodeGen manifest (targets, Info.plist, permissions)
75SoftTracker/
  App/                          App entry point + root tab navigation
  Models/                       SwiftData models: Challenge, DailyEntry, ProgressPhoto, Friend
  Services/                     PhotoStorageService (on-disk JPEG storage)
  Features/
    Onboarding/                 Mode picker (Soft/Hard)
    Today/                      Daily checklist
    ProgressPhoto/              Camera capture, timeline, before/after compare
    Friends/                    Friend list + sharing toggle (local-only, see above)
```
