# Preview verification

Version 0.1.0 · 22 October 2026

- 135 Swift tests passed, zero failures, in the release configuration.
- Four installer replacement scenarios passed: success, copy failure, signature failure and publish failure. Existing bundle bytes survived each failure scenario.
- Installed native slider exercised at Off, 15 minutes, 90 minutes and 6 hours. Native Open at Login showed WideAwake.
- Power prevention enabled on selection and returned to `SleepDisabled 0` on cancellation.
- One idle resource snapshot: 0.0% CPU and 37,712 KiB resident memory. This is an observation, not a constant resource guarantee.
- App bundle signature checked after assembly, backup restoration and installation.
- Demo: no lint errors; nine layout samples without overflow findings. H.264, 1280×720, 18 seconds, 540 frames. Full decode passed. Intentional silence and static cuts; no motion validation was needed.

Physical closed-lid behavior was not tested. Model compatibility, display arrangements, conflicts with other sleep utilities and real crash recovery under a closed lid need hardware validation. Tests use controlled hardware doubles for event and failure scenarios.
