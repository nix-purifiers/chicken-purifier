{
  lib,
  runCommand,
  fetchgit,
  python3,
  writeText,
  purifier,
  toolchain,
  nativeChicken,
  gcc,
  sdkVersion,
}:
{
  lock,
  fetchers ? { },
  nativeBuildInputs ? [ ],
}:
let
  checked = purifier.checkLock lock;
  sources = purifier.tree (
    {
      name = "locked-chicken-egg-payloads";
      entries = checked.entries;
      inherit
        runCommand
        fetchgit
        python3
        writeText
        ;
    }
    // fetchers
  );
  manifest = writeText "chicken-capture.json" (builtins.toJSON checked.data);
  nodeFor = name: lib.findFirst (n: n.name == name) (throw "Missing egg") checked.data.nodes;
  identities = writeText "chicken-identities.scm" (
    "("
    + lib.concatMapStringsSep " " (
      n: "(${builtins.toJSON n.name} ${builtins.toJSON n.version})"
    ) checked.data.nodes
    + ")"
  );
in
assert checked.problems == [ ];
assert lib.assertMsg (
  checked.data.toolVersions == {
    sdk = sdkVersion;
    chicken = nativeChicken.version;
    gcc = gcc.version;
  }
) "CHICKEN SDK changed; update the lock";
runCommand "purified-chicken-environment"
  {
    nativeBuildInputs = [
      toolchain
      python3
    ]
    ++ nativeBuildInputs;
  }
  ''
    export PATH=${toolchain}/bin:$PATH HOME="$TMPDIR/home"
    export CHICKEN_INSTALL_REPOSITORY="$out/lib/chicken/11" CHICKEN_INSTALL_PREFIX="$out"
    export CHICKEN_REPOSITORY_PATH="$out/lib/chicken/11:${nativeChicken}/lib/chicken/11"
    export CHICKEN_EGG_CACHE="$TMPDIR/eggs" CHICKEN_PURIFIER_FROZEN=1
    mkdir -p "$HOME" "$CHICKEN_INSTALL_REPOSITORY" "$CHICKEN_EGG_CACHE" sources
    sed '/^(server /d' ${nativeChicken}/share/chicken/setup.defaults > defaults
    python3 ${../chicken_purifier/stage.py} ${manifest} ${sources} "$PWD/sources" ${nativeChicken}
    ${lib.optionalString (checked.data.order != [ ]) ''
      chicken-install -defaults "$PWD/defaults" -location "$PWD/sources" ${
        lib.escapeShellArgs (
          map (
            name:
            let
              n = nodeFor name;
            in
            "${n.name}:${n.version}"
          ) checked.data.order
        )
      }
    ''}
    csi -s ${../chicken_purifier/check-installed.scm} "$out/lib/chicken/11" ${identities}
    cp ${manifest} "$out/capture.json"
    ln -s ${sources} "$out/sources"
  ''
