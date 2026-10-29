# Preview verification

Version 0.3.0 · 26 October 2026

## Automated checks

- Original source: 141 Swift release tests passed before changes.
- Updated source: 153 Swift release tests passed, zero failures. Coverage includes custom battery boundaries, old-config migration, invalid stored values, preflight refusal without power mutations, plugging in and retrying, thermal refusal, persisted settings, failed saves, visible safety-stop reasons, manual recovery of a retained session file and native form validation.
- Four installer replacement scenarios passed: success, copy failure, signature failure and publish failure. Previous bundle bytes survived each failure case.
- Four permission scenarios passed with a fake sudo: existing passwordless grants, cached/password-required access, missing grants and denied authorization. A successful command listing alone is not accepted as proof of passwordless access.
- Shell syntax and bundle property-list validation passed. The package script assembles and verifies a locally signed app before publishing its archive.
- Native panels were rendered from the shipping AppKit views with disposable state and simulated hardware. Light and dark appearances, low-battery messaging, settings validation and recovery were inspected. Installed native controls were also visually inspected.

## Installed Mac check

- Installed version and bundle signature verified as 0.3.0. Previous app retained by the installer; support files and app also backed up, with a separate recovery copy verified byte for byte.
- At 7% battery while connected to power, selecting 15 minutes reached Ready. Turn off restored `SleepDisabled 0`; the journal was clean and no session file remained.
- The installed settings blocked a 45% stop limit with a 40% Low Power Mode limit. Custom 25% / 5% values saved and appeared in the main panel. Original 40% / 10% defaults were restored after the check.
- Existing passwordless power grants were verified through matching policy output and reused. No permission rules were rewritten. Recovery job installation was confirmed through launchctl.

## Limits

A physical closed-lid test was not performed. Unplugged battery boundaries and thermal events were tested with controlled hardware doubles. Cross-model behavior, external displays, other sleep utilities and physical closed-lid crash recovery still need hardware validation. This preview is locally signed and is not Apple notarized.
