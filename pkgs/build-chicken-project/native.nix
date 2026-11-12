{
  chicken,
  python3,
  curl,
}:
chicken.overrideAttrs (old: {
  pname = "chicken-purifier-sdk";
  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ python3 ];
  postPatch =
    (old.postPatch or "")
    + "\n"
    + ''
      cp ${../../chicken_purifier/transport.scm} purifier-transport.scm
      substituteInPlace purifier-transport.scm --replace-fail '@curl@' '${curl}'
      python ${../../chicken_purifier/patch-sdk.py}
      ${chicken}/bin/chicken chicken-install.scm -output-file chicken-install.c -optimize-level 2 -include-path .
    '';
  postInstall =
    (old.postInstall or "")
    + "\n"
    + ''
      mkdir -p "$out/share/chicken-purifier"
      cp egg-download.scm purifier-unpack.scm "$out/share/chicken-purifier/"
      substituteInPlace "$out/share/chicken-purifier/purifier-unpack.scm" \
        --replace-fail '@download@' "$out/share/chicken-purifier/egg-download.scm"
    '';
})
