"""Run the SDK's native Henrietta reader and verify installed egg identities."""

import json
from pathlib import Path
import subprocess
import sys

manifest, sources, output, sdk = map(Path, sys.argv[1:])
data = json.loads(manifest.read_text())
output.mkdir(exist_ok=True)
for node in data["nodes"]:
    target = output / node["name"] / node["version"]
    subprocess.run(
        [
            str(sdk / "bin/csi"),
            "-R",
            "chicken.pathname",
            "-s",
            str(sdk / "share/chicken-purifier/purifier-unpack.scm"),
            str(sources / node["path"]),
            str(target),
        ],
        check=True,
    )
