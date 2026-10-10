# Codebase Map

Quick orientation for agents working on the Flow State Tracker Flutter app. This map covers the application code in `lib/`; platform runner folders contain generated/platform-specific Flutter scaffolding.

## Start here

- [`main.dart`](main.dart) — app startup, theme, dashboard shell, tab selection, app lifecycle save behavior, and page composition.
- [`tracker_service.dart`](tracker_service.dart) — singleton state and live activity collection. This is the central source for current and daily metrics.
- [`../windows/runner/media_session_detector.cpp`](../windows/runner/media_session_detector.cpp) — Windows C++/WinRT helper for foreground-app media playback status, including muted playback.
- `media_session_detector.dll` also reads the foreground browser's address bar through Windows UI Automation; URL parsing and host normalization happen in `tracker_service.dart`.
- [`pages/today_page.dart`](pages/today_page.dart) — live “Today” dashboard, hourly chart, app breakdown, productivity metrics, and recent trends.
- [`pages/week_page.dart`](pages/week_page.dart) — weekly history and charts/metrics.
- [`pages/month_page.dart`](pages/month_page.dart) — monthly history and charts/metrics.

## Source layout

| File | Responsibility | Look here when… |
| --- | --- | --- |
| [`main.dart`](main.dart) | Entry point (`main`), `FocusTrackerApp`, `DashboardShell`; wires Today, Week, and Month into an `IndexedStack`. Saves tracker data on pause/inactive and shell disposal. | Changing app startup, navigation, global theme, or lifecycle behavior. |
| [`tracker_service.dart`](tracker_service.dart) | `TrackerService` singleton (`ChangeNotifier`) and `HourlyActivity`; samples foreground app/window, idle and keyboard activity, computes live metrics, aggregates hourly/daily values, restores/saves today, and notifies listeners. Contains Win32 FFI and media/audio detection. | Changing tracking, aggregation, live metrics, app identity, or Windows/native collection. |
| [`storage_service.dart`](storage_service.dart) | JSON persistence by calendar day; save/load one day and load a date range. Data files are stored in `%APPDATA%/FlowStateTracker/data` on Windows. | Changing persisted fields, serialization, storage location, or history loading. |
| [`startup_service.dart`](startup_service.dart) | Windows Registry Run-key check/enable/disable/toggle for launching at login. | Changing startup registration behavior. |
| [`widgets.dart`](widgets.dart) | Shared colors, app categorization, dashboard `HeaderBar`, breakdown list, and info tooltip widgets. | Changing shared dashboard styling or reusable UI components. |
| [`pages/today_page.dart`](pages/today_page.dart) | Live daily dashboard; listens to `TrackerService`, loads prior-day data for rolling comparisons. | Changing the current-day view or its charts. |
| [`pages/week_page.dart`](pages/week_page.dart) | Weekly summary/history; listens to the tracker and loads saved daily records. | Changing week-range calculations or weekly visualizations. |
| [`pages/month_page.dart`](pages/month_page.dart) | Monthly summary/history; supports daily and weekly chart views and loads saved daily records. | Changing month-range calculations or monthly visualizations. |

## Data and update flow

```text
main()
  └─ StartupService.enable() ──> Windows startup registration
  └─ FocusTrackerApp / DashboardShell
       ├─ TodayPage ─┐
       ├─ WeekPage  ─┼─> TrackerService.instance (ChangeNotifier)
       └─ MonthPage ─┘          ├─ native sampling and in-memory aggregates
                                └─ StorageService ──> per-day JSON under APPDATA
```

Pages subscribe to tracker updates for live state and use `StorageService` to read historical days. `DashboardShell` requests a save on app pause/inactive and disposal; the tracker also manages its own tracking and autosave lifecycle.

## Practical navigation notes

- For a metric change, trace its full path: sampling/aggregation in `tracker_service.dart` → saved payload in `storage_service.dart` if historical views need it → one or more dashboard pages.
- Persisted JSON field names are part of the history format. When changing them, account for older daily files as well as current saves.
- `tracker_service.dart` loads Windows DLLs and uses Win32 FFI. Tracking behavior depends on Windows APIs; startup registration also targets the Windows Registry.
- Weekly and monthly pages implement their own chart and date-range logic. Check both if a shared metric definition is changed.
- The current automated widget test is [`../test/widget_test.dart`](../test/widget_test.dart); project dependencies and SDK constraints are in [`../pubspec.yaml`](../pubspec.yaml).
