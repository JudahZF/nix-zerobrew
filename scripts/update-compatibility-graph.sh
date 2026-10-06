#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
nix build .#nix-homebrew-compatibility-report -o result-compat
python3 - <<'PY'
import json
from datetime import date
from pathlib import Path

summary = json.loads(Path("result-compat/summary.json").read_text())
path = Path("docs/compatibility-history.json")
history = json.loads(path.read_text())
last = history["series"][-1]
keys = ("pass", "gap", "fail", "total")
if any(last[key] != summary[key] for key in keys):
    history["series"].append({
        "date": date.today().isoformat(),
        "label": "",
        "pass": summary["pass"],
        "gap": summary["gap"],
        "fail": summary["fail"],
        "total": summary["total"],
    })
    path.write_text(json.dumps(history, indent=2) + "\n")
    print(f"Appended compatibility history point for {date.today().isoformat()}")
else:
    print("Compatibility history already matches the suite")
PY
nix build .#nix-homebrew-compatibility-report -o result-compat
cp result-compat/nix-homebrew-compatibility.svg docs/nix-homebrew-compatibility.svg
if [ -e result-compat/STALE ]; then
  echo "History still does not match the suite:" >&2
  cat result-compat/STALE >&2
  exit 1
fi
echo "Updated docs/nix-homebrew-compatibility.svg"
