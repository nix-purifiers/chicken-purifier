"""Exercise native development, frozen dependencies and source publication."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent.parent


def run(args, **kwargs):
    return subprocess.run(list(map(str, args)), check=True, **kwargs)


cli = Path(
    run(
        ["nix", "build", ".#default", "--no-link", "--print-out-paths"],
        capture_output=True,
        text=True,
    ).stdout.strip()
)
sdk = Path(
    run(
        ["nix", "build", ".#sdk", "--no-link", "--print-out-paths"],
        capture_output=True,
        text=True,
    ).stdout.strip()
)
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary) / "renamed-project"
    shutil.copytree(HERE / "examples/minimal", root)
    helper = cli / "bin/chicken-purifier"
    run([helper, "--project", root, "prefetch"])
    env = os.environ.copy()
    env["PATH"] = str(cli / "bin") + ":" + env["PATH"]
    env["CHICKEN_REPOSITORY_PATH"] = "/poisoned/repository"
    env["CHICKEN_INSTALL_REPOSITORY"] = "/poisoned/install"
    env["CHICKEN_EGG_CACHE"] = "/poisoned/cache"
    run([cli / "bin/chicken-install", "-test"], cwd=root, env=env)
    run([cli / "bin/csi", "-s", "tests/run.scm"], cwd=root, env=env)
    traced = run(
        [
            cli / "bin/csi",
            "-quiet",
            "-e",
            "(import (chicken load)) (load-verbose #t) (import srfi-13)",
        ],
        cwd=root,
        env=env,
        capture_output=True,
    )
    profile_data = json.loads((root / ".chicken-purifier/environment.json").read_text())
    assert (
        profile_data["output"] + "/lib/chicken/11/srfi-13.so"
    ).encode() in traced.stdout + traced.stderr
    references = run(
        [
            "nix-store",
            "--query",
            "--references",
            root / ".chicken-purifier/environment.json",
        ],
        capture_output=True,
        text=True,
    ).stdout.splitlines()
    assert profile_data["output"] in references and profile_data["sdk"] in references
    assert not list((root / ".chicken-purifier").rglob("srfi-13.so"))
    source = root / "purifier-example.scm"
    original = source.read_text()
    source.write_text(original.replace("answer=42", "answer=43"))
    for suffix in (".so", ".static.o", ".import.so"):
        (root / ("purifier-example" + suffix)).unlink(missing_ok=True)
    changed = subprocess.run(
        [cli / "bin/chicken-install", "-test"], cwd=root, env=env, capture_output=True
    )
    assert changed.returncode, (
        "Native application tests must fail on a real source error"
    )
    source.write_text(original)
    for suffix in (".so", ".static.o", ".import.so"):
        (root / ("purifier-example" + suffix)).unlink(missing_ok=True)
    run([cli / "bin/chicken-install", "-test"], cwd=root, env=env)
    companion = root / "chicken-purifier.lock.json"
    before = companion.read_bytes()
    run([helper, "--project", root, "lock"])
    assert companion.read_bytes() == before
    release = Path(
        run(
            [helper, "--project", root, "release"], capture_output=True, text=True
        ).stdout.strip()
    )
    archive = release / "purifier-example-0.1.0.tar.gz"
    consumer = Path(temporary) / "consumer"
    consumer.mkdir()
    run(
        [sdk / "bin/tar", "-xzf", archive, "-C", consumer],
        env={**env, "PATH": str(sdk / "bin") + ":" + env["PATH"]},
    )
    profile = json.loads((root / ".chicken-purifier/environment.json").read_text())
    prefix = Path(temporary) / "native-prefix"
    repository = prefix / "lib/chicken/11"
    repository.mkdir(parents=True)
    native_env = os.environ.copy()
    native_env.update(
        PATH=str(sdk / "bin") + ":" + native_env["PATH"],
        CHICKEN_INSTALL_PREFIX=str(prefix),
        CHICKEN_INSTALL_REPOSITORY=str(repository),
        CHICKEN_REPOSITORY_PATH=":".join(
            [
                str(repository),
                profile["output"] + "/lib/chicken/11",
                str(sdk / "lib/chicken/11"),
            ]
        ),
        CHICKEN_EGG_CACHE=str(Path(temporary) / "native-eggs"),
    )
    Path(native_env["CHICKEN_EGG_CACHE"]).mkdir()
    run([sdk / "bin/chicken-install", "-test"], cwd=consumer, env=native_env)
    fake = Path(temporary) / "gh"
    log = Path(temporary) / "gh.jsonl"
    uploaded = Path(temporary) / "uploaded.tar.gz"
    fake.write_text(
        "#!/usr/bin/env python3\n"
        + "import json,os,sys,shutil\n"
        + "with open(os.environ['GH_TEST_LOG'],'a') as f: f.write(json.dumps(sys.argv[1:])+'\\n')\n"
        + "if sys.argv[1:3] == ['release','view']: sys.exit(1 if os.environ.get('GH_TEST_CREATE') else 0)\n"
        + "for arg in sys.argv[3:]:\n if arg.endswith('.tar.gz'): shutil.copyfile(arg,os.environ['GH_TEST_BYTES'])\n"
    )
    fake.chmod(0o755)
    for create in (True, False):
        publish_env = {
            **os.environ,
            "CHICKEN_PURIFIER_GH": str(fake),
            "GH_TEST_LOG": str(log),
            "GH_TEST_BYTES": str(uploaded),
        }
        if create:
            publish_env["GH_TEST_CREATE"] = "1"
        run(
            [
                helper,
                "--project",
                root,
                "publish",
                "--repo",
                "example/project",
                "--tag",
                "v0.1.0",
            ],
            env=publish_env,
        )
        assert uploaded.read_bytes() == archive.read_bytes()
    assert [json.loads(line)[1] for line in log.read_text().splitlines()] == [
        "view",
        "create",
        "view",
        "upload",
    ]
    published_identity = json.loads(companion.read_text())
    published_identity["project"]["version"] = "9.9.9"
    companion.write_text(json.dumps(published_identity))
    mismatch = subprocess.run(
        [helper, "--project", root, "release"], capture_output=True
    )
    assert mismatch.returncode and b"differs from lock" in mismatch.stderr
    companion.write_bytes(before)
    # Explicit external locks propagate through child native commands.
    external = Path(temporary) / "external.json"
    companion.rename(external)
    external_env = {
        **env,
        "CHICKEN_PURIFIER_PROJECT": str(root),
        "CHICKEN_PURIFIER_LOCK": str(external),
    }
    run([cli / "bin/csi", "-s", "tests/run.scm"], cwd=root, env=external_env)
    external.rename(companion)
    (root / "purifier-example.egg").write_text(
        (root / "purifier-example.egg").read_text() + "\n; metadata changed\n"
    )
    stale = subprocess.run(
        [cli / "bin/csi", "-e", "(exit 0)"], cwd=root, env=env, capture_output=True
    )
    assert stale.returncode and b"metadata changed" in stale.stderr
    plain = Path(temporary) / "plain"
    plain.mkdir()
    fallback = subprocess.run(
        [
            cli / "bin/csi",
            "-quiet",
            "-e",
            "(import (chicken io) (chicken process-context)) (display (read-line)) (exit 7)",
        ],
        cwd=plain,
        input=b"ordinary-input\n",
        capture_output=True,
    )
    assert fallback.returncode == 7 and fallback.stdout == b"ordinary-input"
    assert b"ordinary impure resolution" in fallback.stderr
print("CHICKEN native conformance passed")
