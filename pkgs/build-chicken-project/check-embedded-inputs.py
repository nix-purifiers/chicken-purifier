"""Keep caller-authored embedding inputs distinct from generated compiler output."""
import hashlib
import json
from pathlib import Path
import sys

original, working, header, destination, *sources = map(Path, sys.argv[1:])
records = {}
for relative in [header, *sources]:
    source = original / relative
    current = working / relative
    if not source.resolve(strict=True).is_relative_to(original.resolve()):
        raise ValueError("embedding source escapes the original producer")
    if not current.resolve(strict=True).is_relative_to(working.resolve()):
        raise ValueError("embedding source escapes the working producer")
    data = source.read_bytes()
    if current.read_bytes() != data:
        raise ValueError("authored embedding source changed during native build")
    records[str(relative)] = hashlib.sha256(data).hexdigest()
installed = destination / header.name
if installed.read_bytes() != (original / header).read_bytes():
    raise ValueError("installed caller header changed")
(destination / "authored-inputs.json").write_text(json.dumps(records, sort_keys=True) + "\n")
