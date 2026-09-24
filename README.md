# Seven Day Todo

A small, local-first macOS to-do app that shows the three previous days, today,
and the next three days in one window.

## Current features

- Seven day cards centered on today, with one-day navigation and a Today reset
- Floating editor for task titles, long notes, dates, and completion
- Live Markdown formatting in Notes; syntax is shown on the line being edited, while raw Markdown remains saved
- Drag tasks between visible days or within a day to reorder them
- Soft-delete tasks with the trash button
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

Run the local persistence checks after building the app with:

```sh
"dist/Seven Day Todo.app/Contents/MacOS/SevenDayTodo" --self-test
```

## Architecture

`BoardViewController` and `TaskEditorPanel` render AppKit controls and call `TaskStore`.
The store owns the visible date range, editor draft, selected task, and errors.
`MarkdownCompiler` parses note lines, and `MarkdownLivePreview` applies formatting
without replacing the underlying text. Headings, emphasis, links, quotes, lists,
inline code, and fenced code blocks are supported.
It depends on the `TaskRepository` interface.
`LocalTaskRepository` implements it; `JSONFileTaskStorage` handles JSON encoding, migration,
and atomic file writes through `TaskPersistence`. The repository only updates its
in-memory snapshot after a successful file write.

Tasks carry stable UUIDs, update timestamps, soft-deletion markers, and a sync state
for future PocketBase synchronization. The app writes task-only JSON and can read
both the original task array and the intermediate object format.
