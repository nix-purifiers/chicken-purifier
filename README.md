# chicken-purifier

Locked, Nix-resolved eggs for CHICKEN Scheme 5.

## Quickstart

Start in a project with a native `.egg` description that includes a version.

```sh
nix shell 'github:nix-purifiers/chicken-purifier'
chicken-purifier lock
chicken-install -test
csi -s tests/run.scm
```

The shell supplies wrappers for `chicken-install`, `csi`, `csc`,
`chicken-status` and `chicken-uninstall`. Dependencies are compiled in Nix;
your application builds in the working tree. Each project gets a private egg
repository under `.chicken-purifier/`, beside readonly dependency repositories.
No global egg installation is required.

Without a companion lockfile, wrappers warn and run the ordinary native tool.
A stale or invalid lock fails; refresh it after changing dependency metadata:

```sh
chicken-purifier lock --update
```

Commit `chicken-purifier.lock.json`. Source edits do not require relocking.
Use `lock --input path` to track other files that affect dependency selection.
`prefetch` prepares the immutable dependency environment without installing the
application. Wrappers can also be installed using your normal Nix configuration.

## What is locked

The pinned native installer selects dependencies, build dependencies and test
dependencies recursively, including native conditional metadata and version
requirements. The companion records that graph, selected versions, the SDK
identity, and SHA-256 hashes of the exact versioned HTTPS Henrietta responses.
Nix verifies those bytes and the SDK's native reader extracts them. The native
installer builds the selected eggs without network access and checks installed
versions against the lock.

This integration targets CHICKEN 5.4 and the canonical `code.call-cc.org` egg
registry. Arbitrary download servers, local overrides and custom installer
resolution flags are outside its current scope. Native C libraries required
by an egg must be supplied as Nix build inputs. SDK changes require relocking.

## Other commands

```sh
chicken-purifier exec -- csi -s tests/run.scm
chicken-purifier release
chicken-purifier publish \
  --repo owner/project --tag v0.1.0
```

`release` produces a reproducible source tarball containing the companion lock.
An ordinary CHICKEN user can unpack it and run `chicken-install` from that
source directory. `publish` creates or updates a GitHub release with those
same bytes.

An external companion can be selected with `--project` and `--lock-file`, or
`CHICKEN_PURIFIER_PROJECT` and `CHICKEN_PURIFIER_LOCK` for native commands.
The environment profile retains both the dependencies and the wrapper SDK as
Nix garbage collector roots.

## Building with Nix

An optional project Nix definition can use the overlay's
`chicken-purifier.buildChickenProject` through `callPackage`:

```nix
pkgs.chicken-purifier.buildChickenProject {
  src = ./.;
  nativeBuildInputs = [ pkgs.zlib ];
}
```

It exposes evaluation-known `packages`, `tests`, `release` and `fetches`.
`packages.environment` contains the compiled dependency repository;
`packages.project` builds and tests the application. Override `buildCommand`,
`checkCommand`, `installCommand` or `doCheck` for the project's native workflow.
The default test command is `csi -s tests/run.scm`.

## Embedded native libraries

`embeddedLibraries` compiles caller-authored Scheme and C host sources with the
selected native `csc -embedded -shared`. Ordinary egg extension files are not
treated as foreign libraries. For example:

```nix
embeddedLibraries.example = {
  source = "embedded.scm";
  hostSources = [ "host.c" ];
  header = "embedded.h";
  initializeSymbol = "purifier_initialize";
  exports = [ "purifier_answer" ];
};
```

The host implementation initializes the original CHICKEN runtime and runs the
Scheme toplevel until its authored `return-to-host`. The Scheme source defines
its public callbacks with native `define-external`. The purifier supplies no
generated initialization functions or inferred C signatures. It verifies the
actual embedded entry point, declared symbols and selected linked runtime.

The result exposes `projections.native`, `projections.python-ffi` and
`projections.java-ffi`, including a catalog, lazy ctypes loader and Java library
path arguments. Installed caller headers remain under `include/<name>`.
Before initialization, set `CHICKEN_REPOSITORY_PATH` to the catalog target's
`repository` value so native imports resolve the project's installed eggs and
captured dependencies.

The host must choose a CHICKEN nursery size compatible with its native thread's
available stack. The tested host selects 64 KiB explicitly: the SDK default
crashed in the Java FFM consumer, while that explicit size passed its repeated
callbacks and garbage collections. This is a tested fixture setting, not a
universal stack-size guarantee. Java validation uses JDK 21's preview FFM API.

Initialize once, then invoke callbacks on that same native thread. Keep the
library loaded for the process lifetime. Foreign threads, unloading, multiple
independent embedded runtimes and calling before initialization are outside
this API's contract. Callers provide matching C signatures and handle ownership
of their API's data. C, ctypes, CFFI and Java FFM consumers pass on the native
x86_64 Linux host; ARM support still requires its native CI execution.

## Credits

The purifier idea was inspired by nixcloud's
[cargo (libnix)](https://github.com/nixcloud/cargo).
