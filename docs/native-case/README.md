# One minute, two deadlines

This case uses the shipping `SliderPanel`, `MenuBarPanel`, `ManualLidSession` and `SessionManager` from current main `6588f67464fe0d66b2b6bef320d0e927c72f3ecc`, plus the two-line login-default repair. The native host injects the repository’s existing fake sleep, power, audio, display, process and backstop services. It never creates the live `AppDelegate`, registers a login item, runs pmset or launchctl, changes system settings or moves the lid.

## What was actually observed

Actual computer-use input selected one minute in the shipping AppKit panel. The panel reported **Ready**. Escape dismissed it to the separately labeled preview controls. The explicit **Simulate close** control delivered a lid event; reopening the panel showed **Keeping awake until 8:58 AM**. The one-minute range and 67% battery are injected test values, not product defaults or measured hardware telemetry.

[Ready panel](recorded/ready.png) · [Running panel](recorded/running.png) · [recorded transitions](recorded/journey.json).

The first [saved session](recorded/ready-session.json) has a 13:56:52Z start and 13:57:52Z arming deadline. The [post-event session](recorded/running-session.json) has a 13:58:39Z deadline. Both use the source’s whole-second serialization. The deadline shifts by47 seconds and schedules a full60 seconds from the injected event. The two [journals](recorded/ready-journal.json) and [post-event journal](recorded/running-journal.json) retain `sleepDisabledByUs:true` only in the fake service boundary. They are not observations of the Mac’s actual power settings.

[Wide source-derived timeline](deadline.svg) · [portrait timeline](deadline-mobile.svg) · [exact values](figure-data.json). Horizontal distance represents stored seconds with one common scale; open endpoints mean scheduled deadlines, not observed completion.

The Mac locked before the expiry read. No further native input was attempted. **Expiry, cancellation and reopening were not visually verified in this bounded pass.** The raw record remains Running. This does not establish whether a live installed app would expire correctly while sleeping or locked. The existing controlled unit suite covers its deadline/cancel/recovery behavior under fake services; that is a separate claim.

## Reproduce the safe native host

On macOS26+ with Swift6.2+, from a full current-source checkout, choose a NEW private runtime outside the repository:

```sh
python3 -B docs/native-case/build-preview.py /tmp/my-new-wideawake-case
```

Open the resulting `WideAwakeCase.app`. The preview has no install step or privileged commands. It starts with a one-minute test range, writes only disposable state and preview records, and labels its separate controls **no system effects**. The public host uses a fresh PID-specific temporary output folder, or a new path supplied through `WIDEAWAKE_CASE_OUTPUT`. An existing output directory is refused.

Use + in the shipping panel, Escape to dismiss it, **Simulate close** in the separate helper and **Show panel** to inspect it. The helper’s **Simulate open** and **Quit preview** are explicit simulation/cleanup operations, not hardware actions. Keep the desktop unlocked for any interactive timer observation. Do not infer physical behavior from this host.

The builder copies the full original application sources. It disables only the original `@main` annotation, strips test-only XCTest/module imports from the existing fake-support file, and adds [NativeCase.swift](NativeCase.swift) as the entrypoint. It records source hashes in its private `SOURCE.json`. AppKit views and lifecycle implementation remain unmodified. The first observed host used a fixed task-owned output path; the portable builder changes only artifact-path selection and no-clobber checking and was independently compiled after that capture.

## First-use login repair

New `Config()` and decoded configurations without `launchAtLogin` now default to false. The original source defaulted both to true, causing live launch to request Open at Login without a UI opt-in. Explicitly saved true and false values retain their meaning. Four focused tests cover default, missing, explicit true round-trip and explicit false. The original code fails the default/missing checks; the repaired full157-test suite passes.

This is a source repair. Existing saved true can still request registration, and the already-published0.3.0 binary predates the repair. Neither live registration nor a real Login Items change was tested. The held engineering descendant `1d90ee50568c0010f04b3b8c8946ed2aef1c9646` remains separate; its recovery work is not incorporated here.

## Reader and limits

Extract [native-control-reader.zip from the owning repository](https://github.com/nazeeh111/WideAwake/blob/main/docs/native-case/native-control-reader.zip) into a fresh folder and run `python3 -B verify.py`. It checks every included hash, the two60-second session relations, the47-second deadline shift and the fake journal boundary. It cannot establish physical closed-lid operation, sleep prevention, battery/thermal behavior, audio/display restoration, launchd recovery or concurrent-state safety. Original research/verification limits and the [MIT license](LICENSE) remain.
