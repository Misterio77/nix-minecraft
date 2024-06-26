{ lib }:
lib.makeExtensible (self:
with lib;
with builtins;
rec {
  latestVersion = versions:
    last
      (sort versionOlder
        (filter
          (v: isList (match "([[:digit:]]+\.[[:digit:]]+(\.[[:digit:]]+)?)" v))
          (attrNames versions)));

  escapeVersion = builtins.replaceStrings [ "." " " ] [ "_" "_" ];

  removeVanilla = n: escapeVersion (lib.removePrefix "vanilla-" n);

  # Stolen from digga: https://github.com/divnix/digga/blob/587013b2500031b71959496764b6fdd1b2096f9a/src/importers.nix#L61-L114
  rakeLeaves =
    dirPath:
    let
      seive = file: type:
        # Only rake `.nix` files or directories
        (type == "regular" && lib.hasSuffix ".nix" file) || (type == "directory")
      ;

      collect = file: type: {
        name = lib.removeSuffix ".nix" file;
        value =
          let
            path = dirPath + "/${file}";
          in
          if (type == "regular")
            || (type == "directory" && builtins.pathExists (path + "/default.nix"))
          then path
          # recurse on directories that don't contain a `default.nix`
          else rakeLeaves path;
      };

      files = lib.filterAttrs seive (builtins.readDir dirPath);
    in
    lib.filterAttrs (n: v: v != { }) (lib.mapAttrs' collect files);

  # Get a given path's (usually a modpack) files at a specific subdirectory
  # (e.g. "config"), and return them in the format expected by the
  # files/symlinks module options.
  collectFilesAt = let
    mapListToAttrs = fn: fv: list:
      lib.listToAttrs (map (x: lib.nameValuePair (fn x) (fv x)) list);
  in path: prefix:
    mapListToAttrs
    (x: builtins.unsafeDiscardStringContext (lib.removePrefix "${path}/" x))
    (lib.id) (lib.filesystem.listFilesRecursive "${path}/${prefix}");
})
