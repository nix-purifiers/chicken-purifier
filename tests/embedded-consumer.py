import json
import os
from pathlib import Path
import subprocess
import sys

catalog = json.loads(Path(sys.argv[1]).read_text())
environment = {**os.environ, "CHICKEN_REPOSITORY_PATH": catalog["targets"]["example"]["repository"]}
library = catalog["libraries"]["example"]
programs = [
    """import ctypes
p = ctypes.CDLL(LIBRARY)
p.purifier_initialize.restype = ctypes.c_int
assert p.purifier_initialize() == 1
p.purifier_answer.argtypes = [ctypes.c_int]
p.purifier_answer.restype = ctypes.c_int
for i in range(100): assert p.purifier_answer(i) == i + EXPECTED
from pathlib import Path
import os
mapped = {Path(line.split()[-1]).resolve() for line in Path('/proc/self/maps').read_text().splitlines()
          if '/' in line.split()[-1]}
repositories = [Path(path) for path in os.environ['CHICKEN_REPOSITORY_PATH'].split(':')]
for name in ['purifier-example.so', 'srfi-13.so', 'srfi-14.so']:
    expected = next((root / name).resolve() for root in repositories if (root / name).is_file())
    assert expected in mapped, (name, expected)
print('ctypes native egg dependency + embedded callbacks + GC PASS')
""",
    """from cffi import FFI
f = FFI()
f.cdef('int purifier_initialize(void); int purifier_answer(int);')
p = f.dlopen(LIBRARY)
assert p.purifier_initialize() == 1
for i in range(100): assert p.purifier_answer(i) == i + EXPECTED
print('CFFI native egg dependency + embedded callbacks + GC PASS')
""",
]
for program in programs:
    subprocess.run([sys.executable, "-c", "LIBRARY = " + repr(library) + "\nEXPECTED = " + str(int(sys.argv[2])) + "\n" + program],
                   env=environment, check=True)
