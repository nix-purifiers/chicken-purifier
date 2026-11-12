{
  lib,
  runCommand,
  fetchgit,
  python3,
  writeText,
  purifier,
  nativeChicken,
  toolchain,
  gcc,
  sdkVersion,
  makeWrapper,
}:
{
  src,
  lockFile ? src + "/chicken-purifier.lock.json",
  fetchers ? { },
  nativeBuildInputs ? [ ],
  doCheck ? true,
  buildCommand ? "chicken-install",
  checkCommand ? "csi -s tests/run.scm",
  installCommand ? "",
  srcFilter ?
    path: type:
    !(builtins.elem (baseNameOf path) [
      ".git"
      ".chicken-purifier"
      "result"
      "__pycache__"
    ])
    && !(lib.any (suffix: lib.hasSuffix suffix (baseNameOf path)) [
      ".so"
      ".o"
      ".build.sh"
      ".install.sh"
      ".import.scm"
      ".link"
    ]),
}:
let
  lock = purifier.checkLock (
    import ../../lib-overlays/default/read-lock.nix { inherit lib; } { inherit src lockFile; }
  );
  environment = import ./environment.nix {
    inherit
      lib
      runCommand
      fetchgit
      python3
      writeText
      purifier
      nativeChicken
      toolchain
      gcc
      sdkVersion
      ;
  } { inherit lock fetchers nativeBuildInputs; };
  source = lib.cleanSourceWith {
    inherit src;
    filter = srcFilter;
  };
  identity = writeText "chicken-project-identity.scm" (
    "((${builtins.toJSON lock.data.project.name} ${builtins.toJSON lock.data.project.version}))"
  );
  project =
    runCommand "purified-chicken-project"
      {
        nativeBuildInputs = [
          toolchain
          makeWrapper
        ]
        ++ nativeBuildInputs;
      }
      ''
        export PATH=${toolchain}/bin:$PATH HOME="$TMPDIR/home"
        export CHICKEN_INSTALL_REPOSITORY="$out/lib/chicken/11" CHICKEN_INSTALL_PREFIX="$out"
        export CHICKEN_REPOSITORY_PATH="$out/lib/chicken/11:${environment}/lib/chicken/11:${nativeChicken}/lib/chicken/11"
        export CHICKEN_EGG_CACHE="$TMPDIR/eggs" CHICKEN_PURIFIER_FROZEN=1
        mkdir -p "$HOME" "$CHICKEN_EGG_CACHE" "$CHICKEN_INSTALL_REPOSITORY" "$out/source" "$out/bin"
        cp -pr ${source}/. "$out/source/"
        chmod -R u+w "$out/source"
        cd "$out/source"
        csi -s ${../../chicken_purifier/check-installed.scm} "$PWD" ${identity} egg
        ${buildCommand}
        csi -s ${../../chicken_purifier/check-installed.scm} "$CHICKEN_INSTALL_REPOSITORY" ${identity}
        ${lib.optionalString doCheck checkCommand}
        ${installCommand}
        for tool in csi csc; do
          if [ ! -e "$out/bin/$tool" ]; then
            makeWrapper ${nativeChicken}/bin/$tool "$out/bin/$tool" \
              --set CHICKEN_REPOSITORY_PATH "$CHICKEN_REPOSITORY_PATH"
          fi
        done
      '';
  release = runCommand "chicken-source-release" { nativeBuildInputs = [ toolchain ]; } ''
    mkdir -p "$out" source
    cp -pr ${source}/. source/
    chmod -R u+w source
    cp ${lockFile} source/chicken-purifier.lock.json
    csi -s ${../../chicken_purifier/check-installed.scm} "$PWD/source" ${identity} egg
    tar --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner \
      -C source -cf - . | gzip -n > "$out/${lock.data.project.name}-${lock.data.project.version}.tar.gz"
  '';
in
assert lock.problems == [ ];
assert lib.assertMsg (
  lock.data.toolVersions == {
    sdk = sdkVersion;
    chicken = nativeChicken.version;
    gcc = gcc.version;
  }
) "CHICKEN SDK changed; update the lock";
{
  packages = {
    default = project;
    inherit project environment;
  };
  tests = project;
  inherit release;
  fetches = lock.entries;
}
