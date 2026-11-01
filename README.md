# Seven Day Todo

A small, local-first macOS to-do app that shows yesterday, today,
tomorrow, and the day after tomorrow in one window, with a calendar month overview.

## Current features

- Four day cards from yesterday through the day after tomorrow, with one-day navigation and a Today reset
- A Default / Month switch with a full month grid, month navigation, and editable tasks on each date
- Compact Calendar-style popover with a prominent title, date and completion rows, and Notes that expand as you write; click outside to save, or Cancel to discard
- One Notes field with Markdown rendered by default; the line at the insertion cursor reveals its source, and raw Markdown remains saved
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

Run the isolated AppKit popover regression checks with:

```sh
"dist/Seven Day Todo.app/Contents/MacOS/SevenDayTodo" --ui-self-test
```

These checks open a temporary window and use disposable task storage. They exercise
creating, cancelling, and closing popovers in Default and Month views.

## Architecture

`BoardViewController` and `TaskEditorPopover` render AppKit controls and call `TaskStore`.
The store owns the visible date range, editor draft, selected task, and errors.
`MarkdownCompiler` parses note lines, and `MarkdownLivePreview` applies formatting
without replacing the underlying text. Only the line at the insertion cursor shows
Markdown source; the rest stays formatted. Headings, emphasis, blockquotes, lists,
inline code, links, and fenced code are styled in the same Notes field.
It depends on the `TaskRepository` interface.
`LocalTaskRepository` implements it; `JSONFileTaskStorage` handles JSON encoding, migration,
and atomic file writes through `TaskPersistence`. The repository only updates its
in-memory snapshot after a successful file write.

Tasks carry stable UUIDs, update timestamps, soft-deletion markers, and a sync state
for future PocketBase synchronization. The app writes task-only JSON and can read
both the original task array and the intermediate object format.
