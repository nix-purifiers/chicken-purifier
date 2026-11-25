"""Check native compiler output, exported callbacks and the selected runtime."""

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

library, runtime, nm, *exports = sys.argv[1:]
library = Path(library)
runtime = Path(runtime).resolve(strict=True)
data = library.read_bytes()
if data[:4] != b"\x7fELF" or int.from_bytes(data[16:18], "little") != 3:
    raise ValueError("embedded output is not an ELF shared library")
defined = subprocess.check_output(
    [nm, "-D", "--defined-only", str(library)], text=True
)
symbols = {line.split()[-1] for line in defined.splitlines()
           if len(line.split()) >= 3 and line.split()[-2] in {"T", "W"}}
missing = set(exports + ["C_toplevel"]) - symbols
if missing or "main" in symbols:
    raise ValueError(f"not an embedded callback library: missing={sorted(missing)}")
environment = {k: v for k, v in os.environ.items() if not k.startswith("LD_")}
loaded = subprocess.check_output(["ldd", str(library)], env=environment, text=True)
if "not found" in loaded:
    raise ValueError("unresolved native runtime dependency")
paths = re.findall(r"=>\s+(/\S+)", loaded)
matches = [Path(p).resolve(strict=True) for p in paths if Path(p).name.startswith("libchicken.")]
if matches != [runtime]:
    raise ValueError("embedded library does not resolve the original selected CHICKEN runtime")
library.with_suffix(".json").write_text(json.dumps({
    "library": str(library),
    "sha256": hashlib.sha256(data).hexdigest(),
    "runtime": str(runtime),
    "runtimeSha256": hashlib.sha256(runtime.read_bytes()).hexdigest(),
    "exports": exports,
    "nativeDependencies": loaded,
}, sort_keys=True) + "\n")
