# Seven Day Todo

A small, local-first macOS to-do app that shows the three previous days, today,
and the next three days in one window.

## Current features

- Seven always-current day cards with a highlighted Today card
- Add and complete tasks inline
- Delete tasks with the trash button
- Local JSON persistence in Application Support
- A repository boundary and sync metadata ready for a future remote backend
- Native light and dark mode support

## Requirements

- macOS 14 or later
- Apple Command Line Tools with a matching macOS SDK and Swift toolchain

No full Xcode installation is required.

## Run

Build a signed personal-use `.app` bundle with:

```sh
./scripts/build-app.sh
```

The finished application is written to `dist/Seven Day Todo.app`.

## Architecture

`BoardViewController` and `TaskStore` own the UI state. They communicate through the
`TaskRepository` protocol rather than depending directly on a remote service.
`JSONTaskRepository` is the current local implementation.

Tasks already carry stable UUIDs, update timestamps, soft-deletion markers, and
a sync state. A future CloudKit or Supabase adapter can synchronize these local
records while keeping the app usable offline.
