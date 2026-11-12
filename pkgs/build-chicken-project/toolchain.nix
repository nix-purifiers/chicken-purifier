{
  symlinkJoin,
  nativeChicken,
  gcc,
  gnumake,
  git,
  curl,
  cacert,
  gnutar,
  gzip,
  unzip,
  coreutils,
  findutils,
}:
symlinkJoin {
  name = "chicken-purifier-toolchain";
  paths = [
    nativeChicken
    gcc
    gnumake
    git
    curl
    cacert
    gnutar
    gzip
    unzip
    coreutils
    findutils
  ];
}
