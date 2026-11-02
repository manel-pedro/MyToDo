# Codebase review

This refactor keeps the app's four-day/month views, local storage format, Markdown
source, and unfinished-task workflows. It concentrates changes around shared UI,
clear ownership, failure recovery, and checks that run with Command Line Tools.

## Findings and changes

| Area | Finding | Change |
| --- | --- | --- |
| Board controller | Calendar cells, task rows, popover coordination, and event monitors lived in one controller. | Extracted `DayCardView`, `TaskRowView`, and `TaskPopoverCoordinator`. The board renders dates and delegates interactions. |
| Positioning | Offscreen/stale positioning rectangles could make AppKit silently refuse to show a popover. | Shared presentation clamps both editor and review anchors to visible content and cleans up failed presentations. |
| Shared task controls | Task actions were repeatedly wired in day cards and unfinished rows. | `TaskActions` binds the same opening, completion, deletion, and drag callbacks to the shared row. |
| Shared layout | Popovers repeated stacks, labels, spacers, date controls, constraints, and list scrolling. | Added `AppUI`, `StackScrollView`, and `ReviewTaskView`. Lists share a flipped, width-tracking document view. |
| Popover lifecycle | Both popovers separately implemented ownership and animation rules. | `AppPopover` centralizes initialization and notification after closing. The animation-crash workaround remains in one place. |
| Draft recovery | Switching editors force-dismissed the old editor; closing the window/app could bypass autosave. | Close requests validate and save before switching, navigation, window close, and app termination. Failed saves keep the editor and draft. Cancel explicitly discards. |
| Nested editing | Outside-click and drag behavior were mixed with calendar rendering. | Coordinator owns the popover group and retains drag sources until drag completion. Event monitoring ends when review closes. |
| Outside-app clicks | A global mouse monitor tracked clicks in other apps. | App-deactivation notifications cover this case; only a local click monitor is needed. |
| Review controls | Changing a menu rebuilt the entire unfinished list, replacing controls and losing focus. | A review row owns its menu/date picker and updates in place. The review list refreshes only when task data changes. |
| Review planning | Scheduling choices and task-update construction were embedded in the popover. | `ReviewPlan` is a model with explicit choices, selection retention, and date clamping. |
| Calendar | Repeated month addition drifted from January 31 to February 28 and then March 28. | `BoardCalendar` remembers the preferred day: January 31 → February 28 → March 31. Calendar and clock can be injected. |
| Visible tasks | Every day card filtered the whole visible task list. | Store groups tasks by day on reload. |
| Repository writes | Unchanged task edits still wrote JSON and updated sync timestamps. | No-op edits and unchanged candidate snapshots skip persistence. |
| Validation | Invalid date keys and repeated task IDs in plans could enter the mutation path. | Shared validation checks dates, persisted identity uniqueness, finite sort orders, and duplicate plan entries. Batch writes remain atomic. |
| Review Undo | Undo converted persisted `Double` sort orders to `Int`, which can trap or restore the wrong position. | Undo captures actual within-day positions and remains available after failed writes. |
| Ordering | Normalizing a day's order repeatedly scanned the entire task collection. | Build one ID-to-index lookup per normalization. |
| Persistence diagnostics | A malformed task array was retried as a legacy envelope, masking the original field error. | Only a root-container mismatch triggers legacy decoding. Field-level errors propagate unchanged. |
| Date serialization | ISO-8601 formatter objects were repeatedly created for individual dates. | Encoding/decoding uses reusable value-based format styles per coder, accepting fractional and whole seconds. |
| Notes ownership | The editor directly configured a text view and held a separate renderer. The unused HTML renderer remained. | `MarkdownNotesView` owns its text editor, focus behavior, plain-text paste, and inline renderer. Removed the obsolete HTML-preview renderer. |
| Markdown fences | Any line starting with three backticks toggled code mode, including shorter delimiters within longer fences. | Track matching marker type and length; support backticks and tildes. Cache parsed lines with a bounded cache. |
| Task interactions | Small pointer movements began drags, and drag completion reset the click guard. Controls lacked task-specific accessibility labels. | Added a drag threshold, a separate dragged/click guard, an accessibility open action, and descriptive labels. |
| Appearance | Today borders lost their accent after dragging, and cached layer colors could remain from the old appearance. | Recompute border/background colors after drag exit and appearance changes. |
| Window sizing | Default cards required a height that exceeded the minimum window's available space. | Default cards follow the board height; UI checks include minimum and normal window sizes. |
| App entry point | Menu construction and duplicated test-launch branches obscured app lifecycle. | Menu setup is separate; lifecycle handles validation and refreshes data on activation/day change. |
| Test isolation | Self-test code was compiled into the app and run under its app identity. | Tests live under `Tests/` and compile into a separate runner. No test windows run as the production bundle. |
| Build tooling | Packaging assumed one compiler-specific binary path and disabled SwiftPM subprocess sandboxing. | Compile the dependency-free app directly under the existing execution sandbox with explicit SDK/target and local caches. Preserve debug symbols, sign with Hardened Runtime, verify the signature, and refresh the bundle modification date. |

## Verification scope

`./scripts/test-app.sh` covers the previous storage migration, persistence-failure,
reordering, soft-delete, calendar, review, Undo, and Markdown scenarios, together
with focused checks for the problems above. `./scripts/test-app.sh --ui` adds
48 popover open/close cycles, nested unfinished-task editing, autosizing notes, outside clicks,
save failures during switching, monitor cleanup, and layout sizes. Optional
light/dark captures allow visual inspection.

The UI runner exercises native AppKit windows and popovers with temporary task data.
It checks the drag-related ownership and ordering code; it does not automate a
physical pointer drag between windows. It excludes the app entry point/delegate;
window/app close validation delegates to the same coordinator path tested by the runner.

## Boundaries

This remains a small local app. The refactor does not introduce a remote service,
change the data schema, add an external UI framework, or claim full CommonMark
support. Sync metadata is retained for future work. The native popover-animation
workaround remains because the earlier crash's exact AppKit segmentation fault
was not deterministically reproduced, although unsafe close timing was confirmed.
