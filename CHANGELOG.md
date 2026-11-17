# Changes

## 0.3.1 preview · 17 November 2026

- Integrate the reviewed recovery ownership and session-generation checks. Preserve unreadable or conflicting saved sessions, observed external settings where distinguishable, and recovery entries whose observation, restoration or clearing failed. These checks do not prevent every uncooperative concurrent change.
- Add read-only `--inspect-recovery DIRECTORY` JSON reports with bounded regular-file reads and symlink refusal, without observing hardware or attempting effects. Use semantic native label colors for blocked, recovery and invalid-settings messages.
- Leave Open at Login off for new configurations and older files with no saved choice. Preserve an explicitly saved opt-in or opt-out. Existing timer ranges, battery defaults and safeguards are unchanged.
- Add the controlled native case and later unlocked follow-up: expiry, Turn off, injected-open reset, panel reopening and disposable-host relaunch. Hardware effects remain simulated; the private follow-up clock correction is not a shipping app change.
- Package the opt-in repair and its tests together with the source-bound case, follow-up documents and earlier evidence in a locally signed arm64 preview. The package is not Apple notarized and does not establish physical closed-lid operation.

## 0.3.0 · 26 October 2026

- Edit both battery limits in Settings: Low Power Mode below 40% and stop below 10% by default. Saved values survive relaunch; invalid combinations cannot be saved.
- Explain battery and heat refusals before starting a power guard. Reconnecting power allows another selection without relaunching.
- Keep the reason visible when a safeguard ends a timer. Show battery level, power source and configured limits in the main panel.
- Offer Retry when restoration is incomplete, including a session file that could not be removed.
- Use a distinct active menu bar symbol, clearer settings, current native panel captures and a reproducible release package.
- Reuse verified installation permissions on updates without rewriting the existing power-command rules.

## 0.2.0

Custom timer increments and maximum durations, precise stepping, in-panel settings, native light and dark appearances, bounded preparation and recovery checks.
