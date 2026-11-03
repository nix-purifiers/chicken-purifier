{ nixpkgsSrc }:
builtins.hashString "sha256" (
  builtins.toJSON {
    nixpkgs = toString nixpkgsSrc;
    transport = builtins.hashFile "sha256" ../chicken_purifier/transport.scm;
    patch = builtins.hashFile "sha256" ../chicken_purifier/patch-sdk.py;
    native = builtins.hashFile "sha256" ./native.nix;
  }
)
