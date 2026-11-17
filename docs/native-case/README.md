# One minute, two deadlines

This historical case used `SliderPanel`, `MenuBarPanel`, `ManualLidSession` and `SessionManager` from source `6588f67464fe0d66b2b6bef320d0e927c72f3ecc`, plus the two-line login-default repair. Its stored captures, journals and 47-second timeline are unchanged. The 0.3.1 preview now includes the separately reviewed recovery changes from `1d90ee50568c0010f04b3b8c8946ed2aef1c9646`; the recorded panel run predates those changes. The native host injects the repository’s existing fake sleep, power, audio, display, process and backstop services. It never creates the live `AppDelegate`, registers a login item, runs pmset or launchctl, changes system settings or moves the lid.

## What was actually observed

Actual computer-use input selected one minute in the shipping AppKit panel. The panel reported **Ready**. Escape dismissed it to the separately labeled preview controls. The explicit **Simulate close** control delivered a lid event; reopening the panel showed **Keeping awake until 8:58 AM**. The one-minute range and 67% battery are injected test values, not product defaults or measured hardware telemetry.

[Ready panel](recorded/ready.png) · [Running panel](recorded/running.png) · [recorded transitions](recorded/journey.json).

The first [saved session](recorded/ready-session.json) has a 13:56:52Z start and 13:57:52Z arming deadline. The [post-event session](recorded/running-session.json) has a 13:58:39Z deadline. Both use the source’s whole-second serialization. The deadline shifts by 47 seconds and schedules a full 60 seconds from the injected event. The two [journals](recorded/ready-journal.json) and [post-event journal](recorded/running-journal.json) retain `sleepDisabledByUs:true` only in the fake service boundary. They are not observations of the Mac’s actual power settings.

[Wide source-derived timeline](deadline.svg) · [portrait timeline](deadline-mobile.svg) · [exact values](figure-data.json). Horizontal distance represents stored seconds with one common scale; open endpoints mean scheduled deadlines, not observed completion.

The Mac locked before the expiry read. No further native input was attempted. **Expiry, cancellation and reopening were not visually verified in this bounded pass.** The raw record remains Running. This does not establish whether a live installed app would expire correctly while sleeping or locked. The existing controlled unit suite covers its deadline/cancel/recovery behavior under fake services; that is a separate claim.

## Reproduce the safe native host

On macOS 26+ with Swift 6.2+, from the full 0.3.1 source checkout, choose a NEW private runtime outside the repository:

```sh
python3 -B docs/native-case/build-preview.py /tmp/my-new-wideawake-case
```

Open the resulting `WideAwakeCase.app`. The preview has no install step or privileged commands. It starts with a one-minute test range, writes only disposable state and preview records, and labels its separate controls **no system effects**. The public host uses a fresh PID-specific temporary output folder, or a new path supplied through `WIDEAWAKE_CASE_OUTPUT`. An existing output directory is refused.

Use + in the shipping panel, Escape to dismiss it, **Simulate close** in the separate helper and **Show panel** to inspect it. The helper’s **Simulate open** and **Quit preview** are explicit simulation/cleanup operations, not hardware actions. Keep the desktop unlocked for any interactive timer observation. Do not infer physical behavior from this host.

The current builder copies the combined 0.3.1 application sources. It disables the application’s `@main` annotation, strips test-only XCTest/module imports from copied fake support, and adds the unchanged [NativeCase.swift](NativeCase.swift) entrypoint. It also requires exactly one sampled `clock: { c.now },` closure in that copied support and replaces it with `clock: { Date() },` in the private fixture only. Shipping sources and the public unit-test clock remain unchanged. `SOURCE.json` records these private changes, the source version/build and every application-source hash. The current builder was compiled without launching the host; a new live GUI run of the combined recovery implementation has not been performed.

The original deadline capture used the earlier sampled clock. The [later controlled follow-up in the owning repository](https://github.com/nazeeh111/WideAwake/blob/main/docs/native-followup/README.md) documents its failed expiry observation and separate direct-Date-clock success on the earlier manager. Rebuilding the current host does not recreate historical timestamps or establish physical behavior. To inspect the exact older host source, use the [pinned pre-recovery revision](https://github.com/nazeeh111/WideAwake/tree/54afee92ad57d82a9cdef4bbf4a8f2620ca8548d).

## First-use login repair

New `Config()` and decoded configurations without `launchAtLogin` now default to false. The original source defaulted both to true, causing live launch to request Open at Login without a UI opt-in. Explicitly saved true and false values retain their meaning. Four focused tests cover default, missing, explicit true round-trip and explicit false. The original code fails the default/missing checks; the historical repaired 157-test suite passed. The combined 0.3.1 source passes 207 release-configuration tests, including the separately accepted recovery controls.

This is a source repair. Existing saved true can still request registration, and the already-published 0.3.0 binary predates the repair. Neither live registration nor a real Login Items change was tested. The 0.3.1 source incorporates the reviewed recovery work from `1d90ee50568c0010f04b3b8c8946ed2aef1c9646`, preserves the explicit login-choice repair and adds a read-only recovery inspector. The historical captures are not a new GUI verification of that combined implementation.

## Reader and limits

Extract [native-control-reader.zip from the owning repository](https://github.com/nazeeh111/WideAwake/blob/main/docs/native-case/native-control-reader.zip) into a fresh folder and run `python3 -B verify.py`. It checks every included hash, the two 60-second session relations, the 47-second deadline shift and the fake journal boundary. It cannot establish physical closed-lid operation, sleep prevention, battery/thermal behavior, audio/display restoration, launchd recovery or concurrent-state safety. Original research/verification limits and the [MIT license](LICENSE) remain.
