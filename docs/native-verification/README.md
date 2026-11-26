# Native panel check for the combined 0.3.1 source

The shipping AppKit panel was exercised on an unlocked Mac in the effects-disabled preview host, built from [source 42f826c](https://github.com/nazeeh111/WideAwake/tree/42f826c439c9bde0ce092c6b701b56f45b94d54d), version 0.3.1 build 4. That revision and the default branch at verification had identical tracked files. The [sanitized fixture record](record.json) preserves the ordered state changes, omitting wall-clock values. The same source passed 207 Swift release tests.

1. Press **+** in the panel to select one minute. The panel reads **Ready**.
2. Press **Escape** to dismiss the panel. Use **Simulate close**, then **Show panel**. The panel displays a running deadline.
3. Dismiss the panel, use **Simulate open**, then **Show panel**. The panel reads **Off**, and **Turn off** is disabled. The fake-effects journal is clean.

## Reproduce the host

On macOS 26+ with Swift 6.2+, run this from the source checkout with a new temporary path:

```sh
python3 -B docs/native-case/build-preview.py /tmp/my-new-wideawake-case
open /tmp/my-new-wideawake-case/WideAwakeCase.app
```

The [host instructions](../native-case/README.md#reproduce-the-safe-native-host) describe the helper controls and disposable output. The fixture uses one-minute steps and existing service doubles. The signed release app was not installed or operated in this check. The lid events and all effects were simulated, so this run leaves physical closed-lid operation, expiry, and real power restoration unverified. The [earlier deadline case](../native-case/README.md) and [earlier expiry follow-up](../native-followup/README.md) retain their own scope and records.
