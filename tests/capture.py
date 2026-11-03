"""Exercise initial capture, native graph changes and empty dependency sets."""

import json
import os
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent.parent
cli = (
    Path(
        subprocess.run(
            ["nix", "build", ".#default", "--no-link", "--print-out-paths"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
    )
    / "bin/chicken-purifier"
)
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary) / "project"
    root.mkdir()
    egg = root / "empty.egg"
    egg.write_text(
        '((version "0.1.0") (components (extension empty)) (dependencies))\n'
    )
    extra = root / "selection.txt"
    extra.write_text("extra input\n")
    companion = Path(temporary) / "outside.json"

    def call(*args):
        return subprocess.run(
            [str(cli), "--project", str(root), "--lock-file", str(companion), *args],
            check=True,
            capture_output=True,
            text=True,
        )

    call("lock", "--input", "selection.txt")
    empty = json.loads(companion.read_text())
    assert empty["nodes"] == empty["entries"] == empty["order"] == []
    call("prefetch")
    before = companion.read_bytes()
    call("lock")
    assert companion.read_bytes() == before
    extra.write_text("updated selection\n")
    assert subprocess.run(
        [str(cli), "--project", str(root), "--lock-file", str(companion), "prefetch"],
        capture_output=True,
    ).returncode
    egg.write_text(egg.read_text().replace("(dependencies)", "(dependencies srfi-14)"))
    call("lock", "--update")
    updated = json.loads(companion.read_text())
    assert [e["name"] for e in updated["nodes"]] == ["srfi-14"]
    assert updated["extraInputs"] == ["selection.txt"]
    call("prefetch")
    env = {
        **os.environ,
        "CHICKEN_PURIFIER_PROJECT": str(root),
        "CHICKEN_PURIFIER_LOCK": str(companion),
    }
    subprocess.run(
        [
            str(cli.parent / "csi"),
            "-quiet",
            "-e",
            "(import srfi-14) (assert (char-set-contains? char-set:digit (integer->char 52)))",
        ],
        env=env,
        cwd=root,
        check=True,
    )
print("CHICKEN native capture/update and empty graph passed")
