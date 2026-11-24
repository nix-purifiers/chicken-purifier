"""Exercise native rejection paths against real installed compiler products."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root, verify, check_inputs, runtime, nm = sys.argv[1:]
root = Path(root)

def reject(arguments, message):
    result = subprocess.run([sys.executable, *map(str, arguments)], capture_output=True, text=True)
    assert result.returncode != 0 and message in result.stderr, result.stderr

library = root / "lib/libexample.so"
reject([verify, library, runtime, nm, "missing_callback"], "not an embedded callback library")
reject([verify, root / "lib/chicken/11/purifier-example.so", runtime, nm, "purifier_answer"],
       "not an embedded callback library")
reject([verify, library, library, nm, "purifier_answer"], "original selected CHICKEN runtime")
with tempfile.TemporaryDirectory() as temporary:
    temporary = Path(temporary)
    original, working, installed = [temporary / name for name in ["original", "working", "installed"]]
    for directory in [original, working, installed]: directory.mkdir()
    for name in ["embedded.scm", "host.c", "embedded.h"]:
        shutil.copyfile(root / "source" / name, original / name)
        shutil.copyfile(root / "source" / name, working / name)
    shutil.copyfile(original / "embedded.h", installed / "embedded.h")
    (working / "embedded.scm").write_text("(error 'changed)\n")
    reject([check_inputs, original, working, "embedded.h", installed, "embedded.scm", "host.c"],
           "authored embedding source changed")
print("four actual native embedding rejection controls PASS")
