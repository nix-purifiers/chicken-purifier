{
  pkgs,
  build,
  src ? ../examples/minimal,
  expected ? 42,
}:
let
  project = build {
    inherit src;
    embeddedLibraries.example = {
      source = "embedded.scm";
      hostSources = [ "host.c" ];
      header = "embedded.h";
      initializeSymbol = "purifier_initialize";
      exports = [ "purifier_answer" ];
    };
  };
  python = pkgs.python3.withPackages (p: [ p.cffi ]);
in
pkgs.runCommand "chicken-native-embedded-consumers"
  {
    nativeBuildInputs = [
      python
      pkgs.stdenv.cc
      pkgs.jdk21
    ];
  }
  ''
    python ${./embedded-consumer.py} ${project.projections.native}/catalog.json ${toString expected}
    python ${./embedded-controls.py} ${project.packages.project} \
      ${../pkgs/build-chicken-project/verify-embedded.py} \
      ${../pkgs/build-chicken-project/check-embedded-inputs.py} \
      ${pkgs.chicken-purifier.nativeChicken}/lib/libchicken.so ${pkgs.binutils}/bin/nm
    export CHICKEN_REPOSITORY_PATH=$(python -c 'import json; print(json.load(open("${project.projections.native}/catalog.json"))["targets"]["example"]["repository"])')
    cc ${./embedded-consumer.c} -DEXPECTED=${toString expected} -I${project.packages.project}/include/example \
      -L${project.packages.project}/lib -Wl,-rpath,${project.packages.project}/lib -lexample -o consume
    ./consume
    cp ${./EmbeddedConsumer.java} EmbeddedConsumer.java
    javac --enable-preview --release 21 EmbeddedConsumer.java
    java --enable-preview --enable-native-access=ALL-UNNAMED EmbeddedConsumer ${project.packages.project}/lib/libexample.so ${toString expected}
    mkdir "$out"
    cp ${project.packages.project}/lib/libexample.json "$out/"
  ''
