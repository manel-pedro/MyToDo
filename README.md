# Seven Day Todo

A small, local-first macOS to-do app that shows the three previous days, today,
and the next three days in one window.

## Current features

- Seven always-current day cards with a highlighted Today card
- Add and complete tasks inline
- Drag tasks from one day to another
- Delete tasks from their context menu
- Local persistence with SwiftData
- A repository boundary and sync metadata ready for a future remote backend
- Native light and dark mode support

## Requirements

- macOS 14 or later
- Xcode with a matching macOS SDK and Swift toolchain

This Mac currently has standalone Command Line Tools whose compiler and SDK
versions do not match. Installing or updating Xcode resolves that local tooling
issue.

## Run

Open `Package.swift` in Xcode, select the `SevenDayTodo` executable, and press
Run. Once the local command-line toolchain is repaired, the app can also be run
from this directory with:

```sh
swift run SevenDayTodo
```

## Architecture

`ContentView` and `TaskStore` own the UI state. They communicate through the
`TaskRepository` protocol rather than depending directly on a remote service.
`SwiftDataTaskRepository` is the current local implementation.

Tasks already carry stable UUIDs, update timestamps, soft-deletion markers, and
a sync state. A future CloudKit or Supabase adapter can synchronize these local
records while keeping the app usable offline.
