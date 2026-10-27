"""Exercise permission reuse and first-install paths with a fake sudo only."""
from pathlib import Path
import os
import shlex
import subprocess
import tempfile

source = (Path(__file__).resolve().parents[1] / "install.sh").read_text()
section = source[source.index("# Reuse the same four grants"):source.index("# 3. Bundle")]
for mode in ("existing", "cached-password", "missing", "denied"):
    with tempfile.TemporaryDirectory(prefix="wideawake-permissions-") as directory:
        root = Path(directory)
        sudo = root / "sudo"
        sudo.write_text('''#!/bin/bash
printf '%s\\n' "$*" >> "$FIXTURE_ROOT/calls"
if [[ "$1" == -n ]]; then
  if [[ "$FIXTURE_MODE" == existing || -f "$FIXTURE_ROOT/installed" ]]; then
    printf 'Sudoers entry: fixture\\n    RunAsUsers: root\\n    Options: !authenticate\\n    Commands:\\n        %s\\n' "${*:3}"
    exit 0
  fi
  if [[ "$FIXTURE_MODE" == cached-password ]]; then
    printf 'Sudoers entry: fixture\\n    RunAsUsers: root\\n    Options: authenticate\\n    Commands:\\n        %s\\n' "${*:3}"
    exit 0
  fi
  [[ "$*" == *"lowpowermode 1" ]] && exit 1
  exit 0
fi
if [[ "$1" == visudo ]]; then
  [[ "$FIXTURE_MODE" != denied ]]
elif [[ "$1" == install ]]; then
  touch "$FIXTURE_ROOT/installed"
else
  exit 99
fi
''')
        sudo.chmod(0o700)
        setup = "set -euo pipefail\nstep() { :; }\n"
        setup += "SUDO=" + shlex.quote(str(sudo)) + "\n"
        setup += "SUDOERS=" + shlex.quote(str(root / "rule")) + "\n"
        result = subprocess.run(
            ["/bin/bash"], input=setup + section, text=True, capture_output=True,
            env={**os.environ, "FIXTURE_ROOT": str(root), "FIXTURE_MODE": mode},
        )
        assert result.returncode == (1 if mode == "denied" else 0), result.stderr
        calls = (root / "calls").read_text().splitlines()
        expected = {f"-n -ll /usr/bin/pmset {command}" for command in
                    ("-a disablesleep 0", "-a disablesleep 1", "-b lowpowermode 0", "-b lowpowermode 1")}
        if mode != "denied":
            assert expected <= set(calls), calls
        if mode == "existing":
            assert set(calls) == expected, calls
            assert not (root / "installed").exists()
        elif mode in ("missing", "cached-password"):
            assert (root / "installed").exists()
        else:
            assert not (root / "installed").exists()
        print(mode, "permissions passed")
