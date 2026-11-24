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
  stdenv,
  binutils,
}:
{
  src,
  lockFile ? src + "/chicken-purifier.lock.json",
  fetchers ? { },
  nativeBuildInputs ? [ ],
  doCheck ? true,
  embeddedLibraries ? { },
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
  relative =
    s:
    builtins.isString s
    && s != ""
    && !(lib.hasPrefix "/" s)
    && !(builtins.elem ".." (lib.splitString "/" s));
  symbol = s: builtins.isString s && builtins.match "[A-Za-z_][A-Za-z0-9_]*" s != null;
  validLibrary =
    name: spec:
    symbol name
    && builtins.isAttrs spec
    &&
      builtins.attrNames spec == [
        "exports"
        "header"
        "hostSources"
        "initializeSymbol"
        "source"
      ]
    && relative spec.source
    && relative spec.header
    && builtins.isList spec.hostSources
    && spec.hostSources != [ ]
    && builtins.all relative spec.hostSources
    && symbol spec.initializeSymbol
    && builtins.isList spec.exports
    && spec.exports != [ ]
    && builtins.all symbol spec.exports
    &&
      builtins.length (lib.unique (spec.exports ++ [ spec.initializeSymbol ]))
      == builtins.length spec.exports + 1;
  selected = embeddedLibraries != { };
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
  builtProject =
    runCommand "purified-chicken-project"
      {
        nativeBuildInputs = [
          toolchain
          makeWrapper
          python3
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
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (name: spec: ''
              mkdir -p "$out/lib" "$out/include/${name}" "$out/embedding/${name}"
            install -m644 ${lib.escapeShellArg spec.header} "$out/include/${name}/"
            python3 ${./check-embedded-inputs.py} ${source} "$PWD" \
              ${lib.escapeShellArg spec.header} "$out/include/${name}" \
              ${lib.escapeShellArgs ([ spec.source ] ++ spec.hostSources)}
              csc -embedded -shared -k -v ${lib.escapeShellArgs ([ spec.source ] ++ spec.hostSources)} \
                -o "$out/lib/lib${name}.so" > "$out/embedding/${name}/compiler.log" 2>&1
              python3 ${./verify-embedded.py} "$out/lib/lib${name}.so" \
                ${nativeChicken}/lib/libchicken.so ${binutils}/bin/nm \
                ${lib.escapeShellArgs ([ spec.initializeSymbol ] ++ spec.exports)}
          '') embeddedLibraries
        )}
        for tool in csi csc; do
          if [ ! -e "$out/bin/$tool" ]; then
            makeWrapper ${nativeChicken}/bin/$tool "$out/bin/$tool" \
              --set CHICKEN_REPOSITORY_PATH "$CHICKEN_REPOSITORY_PATH"
          fi
        done
      '';
  projections = lib.optionalAttrs selected (
    purifier.nativeProjections {
      producer = builtProject;
      libraries = lib.mapAttrs (name: _: "lib/lib${name}.so") embeddedLibraries;
      includeDirectories = lib.mapAttrsToList (name: _: "include/${name}") embeddedLibraries;
      targetMetadata = lib.mapAttrs (name: spec: {
        abi = "c";
        inherit (spec) exports initializeSymbol;
        repository = "${builtProject}/lib/chicken/11:${environment}/lib/chicken/11:${nativeChicken}/lib/chicken/11";
        runtime = {
          kind = "chicken";
          lifecycle = "same-thread-process-lifetime";
          path = toString nativeChicken;
          version = nativeChicken.version;
        };
      }) embeddedLibraries;
      system = stdenv.hostPlatform.system;
      inherit runCommand python3;
    }
  );
  project = builtProject // {
    inherit projections;
  };
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
assert lib.assertMsg
  (builtins.all (name: validLibrary name embeddedLibraries.${name}) (
    builtins.attrNames embeddedLibraries
  ))
  "embeddedLibraries requires explicit native Scheme/host/header paths, unique C exports and initialization symbol";
assert lib.assertMsg (
  !selected || stdenv.hostPlatform.isLinux
) "embeddedLibraries currently supports native Linux only";
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
  inherit release projections;
  fetches = lock.entries;
}
