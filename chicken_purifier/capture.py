"""Capture the native installer's selected graph and exact source responses."""

import base64
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile
import urllib.parse

from .common import STATE, clean_env, inputs, load, native, run, versions


def capture(root, companion, update=False, extra=(), name=None):
    if companion.exists() and not update:
        previous = load(root, companion)
        if extra and sorted(set(extra)) != previous["extraInputs"]:
            raise ValueError("Changed --input requires lock --update")
        if name and name != previous["project"]["name"]:
            raise ValueError("Changed --name requires lock --update")
        return
    old = json.loads(companion.read_text()) if companion.exists() else {}
    extra = sorted(set(extra or old.get("extraInputs", [])))
    recorded = inputs(root, extra)
    eggs = list(root.glob("*.egg"))
    if len(eggs) != 1 or list(root.glob("chicken/*.egg")):
        raise ValueError("Use one native .egg description at the project root")
    project_name = eggs[0].stem
    if name and name != project_name:
        raise ValueError("--name must match the native .egg filename")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.+-]*", project_name):
        raise ValueError("Invalid egg name")
    state = root / STATE
    state.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="capture-", dir=state) as temporary:
        work = Path(temporary).resolve()
        source = work / "project"
        source.mkdir()
        for filename, info in recorded.items():
            path = source / filename
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(info["content"])
        env = clean_env(work)
        for key, leaf in [
            ("CHICKEN_EGG_CACHE", "eggs"),
            ("CHICKEN_INSTALL_PREFIX", "prefix"),
            ("CHICKEN_INSTALL_REPOSITORY", "repository"),
        ]:
            path = work / leaf
            path.mkdir()
            env[key] = str(path)
        env["CHICKEN_REPOSITORY_PATH"] = os.environ["CHICKEN_PURIFIER_CORE_REPOSITORY"]
        env["CHICKEN_PURIFIER_CAPTURE"] = str(work / "native.json")
        defaults = work / "setup.defaults"
        original_defaults = Path(os.environ["CHICKEN_PURIFIER_DEFAULTS"]).read_text()
        defaults.write_text(
            "\n".join(
                line
                for line in original_defaults.splitlines()
                if not line.startswith("(server ")
            )
            + '\n(server "http://code.call-cc.org/cgi-bin/henrietta.cgi")\n'
        )
        run(
            [
                native("chicken-install"),
                "-r",
                "-recursive",
                "-test",
                "-defaults",
                defaults,
            ],
            cwd=source,
            env=env,
        )
        selected = json.loads((work / "native.json").read_text())
        project = next(e for e in selected["eggs"] if e[0] == project_name)
        if not project[2]:
            raise ValueError("The project .egg needs a version")
        entries, nodes = [], []
        responses = {}
        for url, filename in selected["responses"]:
            query = urllib.parse.parse_qs(urllib.parse.urlsplit(url).query)
            if "listversions" not in query:
                responses[query["name"][0]] = (url, Path(filename))
        try:
            for egg, directory, version in selected["eggs"]:
                if egg == project_name:
                    continue
                if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.+-]*", egg) or not version:
                    raise ValueError("Native resolver returned invalid identity")
                url, filename = responses[egg]
                url += "&version=" + urllib.parse.quote(version, safe="")
                payload = filename.read_bytes()
                digest = (
                    "sha256-"
                    + base64.b64encode(hashlib.sha256(payload).digest()).decode()
                )
                path = "eggs/" + egg + ".henrietta"
                entries.append(
                    {"path": path, "url": url, "hash": digest, "mirrors": []}
                )
                nodes.append({"name": egg, "version": version, "path": path})
        finally:
            for _, filename in selected["responses"]:
                Path(filename).unlink(missing_ok=True)
        data = {
            "version": 1,
            "purifier": "chicken",
            "toolVersions": versions(),
            "inputs": recorded,
            "extraInputs": extra,
            "project": {"name": project_name, "version": project[2]},
            "nodes": sorted(nodes, key=lambda e: e["name"]),
            "dependencies": selected["dependencies"],
            "order": [e for e in selected["order"] if e != project_name],
            "entries": sorted(entries, key=lambda e: e["path"]),
        }
    companion.parent.mkdir(parents=True, exist_ok=True)
    pending = companion.with_name(companion.name + ".tmp")
    pending.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
    pending.replace(companion)
