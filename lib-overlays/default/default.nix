final: prev: {
  chicken-purifier = {
    readLock = import ./read-lock.nix { lib = final; };
  };
}
