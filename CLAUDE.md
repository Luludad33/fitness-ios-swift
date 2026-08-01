# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

健身训练手册（FitCoach）— iOS 17+ SwiftUI 健身训练 App。数据源自飞书文档《健身动作图解与训练手册 V2.0》：三分化训练（推日/拉日/腿日）、12 个力量动作详解、10 个拉伸动作。功能：动作图鉴、跟练流程（组间休息倒计时）、训练记录统计、灵动岛/锁屏实况活动。

## Build & Run

```bash
# Generate Xcode project from project.yml
xcodegen generate --project .

# Open in Xcode
open FitCoach.xcodeproj

# Build (unsigned, for sideloading)
xcodebuild build \
  -project FitCoach.xcodeproj \
  -scheme FitCoach \
  -sdk iphoneos \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

# Package .ipa
mkdir -p Payload && cp -r "build/Build/Products/Release-iphoneos/FitCoach.app" Payload/
zip -r "FitCoach.ipa" Payload/
```

CI builds run via GitHub Actions (`.github/workflows/build.yml`) on `macos-latest`, producing an unsigned `.ipa` artifact.

## Project structure

```text
project.yml                 — XcodeGen project spec (do NOT commit .xcodeproj)
gen_sounds.js               — Node.js script that generates rest_start.wav / rest_end.wav / done.wav
健身训练手册/
  App.swift                 — @main entry point, creates WorkoutManager environmentObject
  ContentView.swift         — Root view: TabView (训练/图鉴/记录) + session overlays; shared ExerciseThumb/SectionCard
  WorkoutViews.swift        — Training flow UI: DaySelectionView, ChecklistSheet, WorkoutFlowView,
                              RestOverlayView, WorkoutFinishedView
  LibraryViews.swift        — Exercise library: list (strength by day / stretches by group) + detail views
  RecordViews.swift         — Workout history + weekly stats
  Models.swift              — Exercise / WorkoutDay / StretchMove / DayRecord / SetLog / ExerciseLog
  TrainingData.swift        — All training content as static data (12 exercises, 10 stretches,
                              3 workout days, checklist, principles, rest tips)
  WorkoutManager.swift      — All business logic: workout state machine, notifications,
                              background/foreground handling, UserDefaults persistence, records
  FitnessAttributes.swift   — ActivityAttributes (SHARED with widget target via project.yml path)
  FitnessLiveActivityManager.swift — Live Activity singleton, 4s throttled updates
  Assets.xcassets/          — App icon + 11 exercise images (dumbbell_press.jpg … bulgarian_split_squat.jpg)
  rest_start.wav / rest_end.wav / done.wav — notification sounds (generated)
  Info.plist                — Bundle config (zh_CN, portrait only, iOS 17+, NSSupportsLiveActivities)
FitCoachWidget/
  FitCoachWidget.swift      — ActivityConfiguration: lock screen banner + Dynamic Island
  Info.plist                — WidgetKit extension config
```

## Architecture

**WorkoutManager** (`@MainActor`, `ObservableObject`) is the single source of truth. All views read from it via `@EnvironmentObject var wm: WorkoutManager`.

Four phases: `.idle`（选训练日）→ `.exercising`（逐组确认）→ `.resting`（组间休息倒计时）→ 循环至 `.finished`（庆祝 + 写记录）.

- Rest countdown tracks a `Date` deadline (not cumulative seconds) with a 0.2s tick, so it survives background suspend.
- `handleScenePhaseChange(.active)`: if the rest deadline passed while backgrounded, auto-advances to the next set; otherwise resumes ticking and re-schedules the local notification.
- Session state persisted via UserDefaults (phase/dayId/exerciseIndex/setNumber/deadline/logs) — survives force-quit.
- Workout records stored per-day: UserDefaults key `fit_records_yyyy-MM-dd` → JSON `[DayRecord]`.
- Notifications: `UNUserNotificationCenter` with custom `rest_end.wav`; rest-end notification body names the next exercise/set.

**ContentView** is a `ZStack`: TabView at the bottom layer, `WorkoutFlowView` full-screen while a session runs, `RestOverlayView` on top during rest, mirroring the overlay layering of the 20-20-20 eye-care project this app is modeled on.

## Key conventions

- All strings in Chinese (zh_CN)
- No `.xcodeproj` committed — regenerate via `xcodegen generate --project .`
- Custom sounds generated via `node gen_sounds.js` (writes into the source directory)
- `DEVELOPMENT_TEAM` intentionally empty (unsigned builds for sideloading)
- Bundle IDs: `com.luludad.fitness` (app) / `com.luludad.fitness.widget` (extension), iOS 17.0
- 腿举机（leg_press）has no photo in the source document — rendered with SF Symbol `figure.strengthtraining.traditional`
- Training content lives only in `TrainingData.swift`; to update content, edit that file (source of truth: 健身动作图解与训练手册 V2.0)
