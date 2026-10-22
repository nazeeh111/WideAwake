# Preview verification

Version 0.2.0 · 22 October 2026

- 141 Swift tests passed with zero failures in the release configuration. New checks cover custom multi-day ranges, exact steps, invalid limits, old configuration migration, restart persistence, bounded preparation and failed saves.
- Four installer replacement scenarios passed: success, copy failure, signature failure and publish failure. Existing bundle bytes survived each failure scenario.
- Installed settings exercised with two-hour increments and a three-day maximum. Invalid seven-hour increments / three-day maximum prevented Save. Settings were blocked while armed.
- Native keyboard entry, Select All, Return to save, unit menus, precise −/+ stepping and Turn off were exercised. Saved settings survived relaunch. Personal defaults were restored to 15-minute increments / six-hour maximum.
- macOS reported `ApplicationType=UIElement` while the panel was open. Only accessory activation exists in the app. Settings share the same panel. Light and dark native appearances were visually inspected.
- Power prevention enabled on selection and returned to `SleepDisabled 0` on Turn off. Final idle snapshot after settings editing: 0.0% CPU and 61,728 KiB resident memory. This observation is not a fixed resource guarantee.
- App bundle signature checked after assembly, prior-version backup restoration and installation.
- Demo: zero lint errors; nine layout samples without overflow findings. H.264, 1280×720, 21 seconds, 630 frames; full decode passed. Static cuts and intentional silence; motion checks are disabled because there is no animation.

Physical closed-lid behavior was not tested. Mac model compatibility, external displays, conflicts with other sleep utilities and crash recovery under a closed lid need hardware validation. Tests use controlled hardware doubles for event and failure scenarios. Battery and thermal protections can end a selected timer early.
