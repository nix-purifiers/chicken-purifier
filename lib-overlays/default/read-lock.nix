{ lib }:
{
  src,
  lockFile ? src + "/chicken-purifier.lock.json",
}:
let
  raw = if builtins.pathExists lockFile then builtins.fromJSON (builtins.readFile lockFile) else { };
  data = if builtins.isAttrs raw then raw else { };
  entries = data.entries or [ ];
  nodes = data.nodes or [ ];
  inputs = data.inputs or { };
  safe =
    s: builtins.isString s && s != "." && s != ".." && builtins.match "[A-Za-z0-9_.+-]+" s != null;
  relative =
    s:
    builtins.isString s
    && s != ""
    && !(lib.hasPrefix "/" s)
    && !(builtins.elem ".." (lib.splitString "/" s));
  eggFiles = builtins.filter (n: lib.hasSuffix ".egg" n) (builtins.attrNames (builtins.readDir src));
  valid =
    (data.version or null) == 1
    && (data.purifier or null) == "chicken"
    && builtins.isList (data.extraInputs or null)
    && builtins.all relative data.extraInputs
    && builtins.isAttrs inputs
    && builtins.length eggFiles == 1
    &&
      builtins.attrNames inputs
      == builtins.sort builtins.lessThan (lib.unique (eggFiles ++ data.extraInputs))
    && builtins.all (
      name:
      relative name
      && builtins.isAttrs inputs.${name}
      && builtins.isString (inputs.${name}.content or null)
      && builtins.pathExists (src + "/${name}")
      && (builtins.readDir (dirOf (src + "/${name}"))).${baseNameOf name} == "regular"
      && builtins.hashFile "sha256" (src + "/${name}") == (inputs.${name}.sha256 or null)
      && builtins.hashString "sha256" inputs.${name}.content == inputs.${name}.sha256
    ) (builtins.attrNames inputs)
    && builtins.isAttrs (data.project or null)
    && safe (data.project.name or null)
    && safe (data.project.version or null)
    && eggFiles == [ (data.project.name + ".egg") ]
    && builtins.isList nodes
    && builtins.isList entries
    && builtins.all (
      e:
      builtins.isAttrs e
      && relative (e.path or null)
      && builtins.isString (e.hash or null)
      && builtins.match "sha256-[A-Za-z0-9+/]{43}=" e.hash != null
      && builtins.isString (e.url or null)
      && lib.hasPrefix "https://code.call-cc.org/cgi-bin/henrietta.cgi?" e.url
      && (e.mirrors or null) == [ ]
      && !(e ? git)
    ) entries
    && builtins.all (
      n:
      builtins.isAttrs n
      && safe (n.name or null)
      && safe (n.version or null)
      && (n.path or null) == "eggs/${n.name}.henrietta"
      && builtins.any (
        e:
        e.path == n.path
        && lib.hasInfix "name=${n.name}&" e.url
        && lib.hasSuffix "&version=${n.version}" e.url
      ) entries
    ) nodes
    && builtins.length entries == builtins.length nodes
    && builtins.length (lib.unique (map (n: n.name) nodes)) == builtins.length nodes
    && builtins.length (lib.unique (map (e: e.path) entries)) == builtins.length entries
    && builtins.isList (data.order or null)
    &&
      builtins.sort builtins.lessThan data.order
      == builtins.sort builtins.lessThan (map (n: n.name) nodes)
    && builtins.isAttrs (data.toolVersions or null)
    && builtins.all (key: builtins.isString (data.toolVersions.${key} or null)) [
      "sdk"
      "chicken"
      "gcc"
    ];
in
{
  purifier = "chicken";
  inherit data entries;
  problems = lib.optional (
    !valid
  ) "CHICKEN lock is missing, stale, or unsupported; run chicken-purifier lock --update";
  outputs = {
    packages = [
      "default"
      "environment"
      "project"
    ];
    tests = [ "default" ];
    release = [ "default" ];
  };
}
