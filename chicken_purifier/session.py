"""Use immutable dependencies beside the application's private egg repository."""

import json
import os
from pathlib import Path
import sys

from .common import HERE, STATE, clean_env, load, native, run


def realize(root, companion, target="environment"):
    state = root / STATE
    state.mkdir(exist_ok=True)
    profile = state / (target + ".json")
    run(
        [
            "nix",
            "build",
            "--impure",
            "--file",
            HERE / "nix/realize.nix",
            "--argstr",
            "project",
            root,
            "--argstr",
            "companion",
            companion,
            "--argstr",
            "target",
            target,
            "--arg",
            "profile",
            "true",
            "--argstr",
            "sdk",
            os.environ["CHICKEN_PURIFIER_SDK"],
            "--out-link",
            profile,
        ],
        stdout=sys.stderr,
    )
    return Path(json.loads(profile.read_text())["output"])


def execute(root, companion, args, tool=None):
    command = [native(tool), *args] if tool else args
    if not companion.exists():
        if os.environ.get("CHICKEN_PURIFIER_LOCK"):
            raise ValueError("Selected lockfile does not exist")
        print(
            "warning: no chicken-purifier lockfile; using ordinary impure resolution",
            file=sys.stderr,
        )
        os.execvpe(str(command[0]), list(map(str, command)), os.environ.copy())
    load(root, companion)
    environment = realize(root, companion)
    state = root / STATE / "session"
    env = clean_env(state)
    repository = state / "repository"
    repository.mkdir(exist_ok=True)
    cache = state / "eggs"
    cache.mkdir(exist_ok=True)
    prefix = state / "prefix"
    prefix.mkdir(exist_ok=True)
    env.update(
        {
            "CHICKEN_INSTALL_REPOSITORY": str(repository),
            "CHICKEN_INSTALL_PREFIX": str(prefix),
            "CHICKEN_EGG_CACHE": str(cache),
            "CHICKEN_REPOSITORY_PATH": ":".join(
                [
                    str(repository),
                    str(environment / "lib/chicken/11"),
                    os.environ["CHICKEN_PURIFIER_CORE_REPOSITORY"],
                ]
            ),
            "CHICKEN_PURIFIER_FROZEN": "1",
            "CHICKEN_PURIFIER_PROJECT": str(root),
            "CHICKEN_PURIFIER_LOCK": str(companion),
        }
    )
    env["PATH"] = os.environ["CHICKEN_PURIFIER_SDK"] + "/bin:" + env["PATH"]
    # Never mutate the dependency repository. Native resolution must find every
    # dependency installed, or fail before transport in the scoped installer.
    if tool == "chicken-uninstall":
        raise ValueError(
            "Locked sessions do not remove dependencies; edit metadata and update the lock"
        )
    if tool == "chicken-install":
        blocked = (
            "-location",
            "-l",
            "-defaults",
            "-override",
            "-from-list",
            "-sudo",
            "-s",
            "-force",
            "-force-install",
        )
        if any(arg in blocked for arg in args):
            raise ValueError(
                "Locked installation uses only the current project and locked dependencies"
            )
        if any(not arg.startswith("-") for arg in args):
            raise ValueError(
                "Use chicken-install in the project root; edit metadata and update the lock to add eggs"
            )
        if Path.cwd().resolve() != root:
            raise ValueError("Run chicken-install from the project root")
    os.execvpe(str(command[0]), list(map(str, command)), env)
