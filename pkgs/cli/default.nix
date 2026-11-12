{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  nix,
  gh,
  toolchain,
  nativeChicken,
  gcc,
  cacert,
  sdkVersion,
  nixpkgsSrc,
  purifierSrc,
}:
stdenvNoCC.mkDerivation {
  pname = "chicken-purifier";
  version = "0.1.0";
  src = ../..;
  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;
  installPhase = ''
    mkdir -p "$out/bin" "$out/lib/chicken-purifier"
    cp -r chicken_purifier pkgs lib-overlays "$out/lib/chicken-purifier/"
    install -m755 bin/chicken-purifier "$out/bin/chicken-purifier"
    substituteInPlace "$out/lib/chicken-purifier/pkgs/build-chicken-project/realize.nix" \
      --replace-fail '@nixpkgs@' '${nixpkgsSrc}' \
      --replace-fail '@purifier@' '${purifierSrc}'
    wrapProgram "$out/bin/chicken-purifier" \
      --prefix PATH : ${
        lib.makeBinPath [
          python3
          nix
          gh
          toolchain
        ]
      } \
      --set-default SSL_CERT_FILE ${cacert}/etc/ssl/certs/ca-bundle.crt \
      --set CHICKEN_PURIFIER_DEFAULTS ${nativeChicken}/share/chicken/setup.defaults \
      --set CHICKEN_PURIFIER_CORE_REPOSITORY ${nativeChicken}/lib/chicken/11 \
      --set CHICKEN_PURIFIER_NATIVE_CSI ${nativeChicken}/bin/csi \
      --set CHICKEN_PURIFIER_NATIVE_CSC ${nativeChicken}/bin/csc \
      --set CHICKEN_PURIFIER_NATIVE_CHICKEN_INSTALL ${nativeChicken}/bin/chicken-install \
      --set CHICKEN_PURIFIER_NATIVE_CHICKEN_UNINSTALL ${nativeChicken}/bin/chicken-uninstall \
      --set CHICKEN_PURIFIER_NATIVE_CHICKEN_STATUS ${nativeChicken}/bin/chicken-status \
      --set CHICKEN_PURIFIER_SDK_VERSION ${sdkVersion} \
      --set CHICKEN_PURIFIER_CHICKEN_VERSION ${nativeChicken.version} \
      --set CHICKEN_PURIFIER_GCC_VERSION ${gcc.version} \
      --set CHICKEN_PURIFIER_SDK "$out" \
      --set CHICKEN_PURIFIER_TOOLCHAIN ${toolchain}
    for tool in csi csc chicken-install chicken-uninstall chicken-status; do
      makeWrapper "$out/bin/chicken-purifier" "$out/bin/$tool" --add-flags "--native --tool=$tool --"
    done
    for program in ${toolchain}/bin/*; do
      name=$(basename "$program")
      if [ ! -e "$out/bin/$name" ]; then ln -s "$program" "$out/bin/$name"; fi
    done
  '';
  meta = {
    description = "Native CHICKEN workflow with locked Nix-resolved dependencies";
    homepage = "https://nix-purifiers.github.io/";
    license = lib.licenses.mit;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "chicken-purifier";
  };
}
