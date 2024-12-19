# found in:
# - https://github.com/Szymzal/dotfiles
# based on:
# - https://github.com/Faeranne/nix-minecraft/blob/f4e4514f1d65b6a19704eab85070741e40c1d272/pkgs/forge-servers/derivation.nix
# - https://github.com/Infinidoge/nix-minecraft/blob/ab4790259bf8ed20f4417de5a0e5ee592094c7c3/pkgs/build-support/mkTextileLoader.nix
#
# Locks (lock_game.json, lock_launcher.json, lock_libraries.json)
# are copied from https://github.com/Faeranne/nix-minecraft/tree/f4e4514f1d65b6a19704eab85070741e40c1d272/pkgs/forge-servers
#
# Locks are modified to have only one version of Forge (1.20.1-47.3.1)
# I didn't want to deal with many versions of Forge
{ lib
, stdenvNoCC
, fetchurl
, gameVersion
, loaderVersion
, jre_headless
, jq
}:
let
  minecraftInfo = (lib.importJSON ./lock_game.json).${gameVersion};

  forge-installer = "forge-${gameVersion}-${loaderVersion}-installer";

  mappingsInfo = minecraftInfo.mappings;
  mappings = fetchurl {
    name = "minecraft-mappings";
    version = "${gameVersion}";
    inherit (mappingsInfo) sha1 url;
  };

  vanillaInfo = minecraftInfo.server;
  vanilla = fetchurl {
    name = "vanilla-server";
    version = "${gameVersion}";
    inherit (vanillaInfo) sha1 url;
  };

  loader = (lib.importJSON ./lock_launcher.json).${gameVersion}.${loaderVersion};
  libraries = minecraftInfo.libraries;
  libraries_lock = lib.importJSON ./lock_libraries.json;
  fetchedLibraries = lib.forEach libraries (l:
    let
      library = libraries_lock.${l};
    in
    fetchurl {
      inherit (library) url sha1;
    }
  );
in
stdenvNoCC.mkDerivation {
  pname = "forge-loader";
  version = "${gameVersion}-${loaderVersion}";

  libraries = fetchedLibraries;

  src = fetchurl {
    name = forge-installer;
    inherit (loader) url;
    hash = loader.md5;
  };

  preferLocalBuild = true;

  installPhase = if (loader.type == "installer") then (
  let
    libraries_path = lib.concatStringsSep " " (lib.forEach libraries (l: libraries_lock.${l}.path));
  in
  ''
    LIB_PATHS=(${libraries_path})

    mkdir $out

    for i in $libraries; do
      NIX_LIB=$(basename $i)
      NIX_LIB_NAME="''${NIX_LIB:33}"

      for l in ''${!LIB_PATHS[@]}; do
        LIB="''${LIB_PATHS[$l]}"
        LIB_NAME=$(basename $LIB)

        if [[ $LIB_NAME == $NIX_LIB_NAME ]]; then
          mkdir -p "$out/libraries/$(dirname $LIB)"
          ln -s $i $out/libraries/$LIB

          echo Linking library: $LIB_NAME

          break
        fi
      done
    done

    MOJMAP_DIR_NAME=$(basename $out/libraries/de/oceanlabs/mcp/mcp_config/${gameVersion}-*)
    echo $MOJMAP_DIR_NAME
    MOJMAP_DIR=$out/libraries/net/minecraft/server/$MOJMAP_DIR_NAME
    mkdir -p "$MOJMAP_DIR"

    ln -s ${mappings} $MOJMAP_DIR/server-$MOJMAP_DIR_NAME-mappings.txt

    MINECRAFT_LIB=$out/libraries/net/minecraft/server/${gameVersion}
    mkdir -p "$MINECRAFT_LIB"

    ln -s ${vanilla} $MINECRAFT_LIB/server-${gameVersion}.jar

    cp $src $out/forge-installer.jar

    echo Patching forge installer...
    pushd $out

    ${jre_headless}/bin/jar xf $out/forge-installer.jar install_profile.json

    mv $out/install_profile.json $out/install_profile_original.json

    ${lib.getExe jq} 'del(.processors[] | select(.args[1]=="DOWNLOAD_MOJMAPS"))' $out/install_profile_original.json > $out/install_profile.json
    mkdir -p $out/META-INF
    touch $out/META-INF/FORGE.RSA

    ${jre_headless}/bin/jar uf $out/forge-installer.jar install_profile.json META-INF/FORGE.RSA

    popd

    rm $out/install_profile.json
    rm $out/install_profile_original.json
    rm -rf $out/META-INF

    echo Running installer...
    ${jre_headless}/bin/java -jar $out/forge-installer.jar --offline --installServer $out

    echo Cleaning up...

    rm $out/run.bat
    rm $out/run.sh
    rm $out/user_jvm_args.txt
    rm $out/forge-installer.jar

    substituteInPlace $out/libraries/net/minecraftforge/forge/1.20.1-47.3.1/unix_args.txt \
      --replace libraries $out/libraries
  '') else throw "Cannot work with other types of packaging than installer!";

  dontUnpack = true;

  meta = with lib; {
    description = "Minecraft Server";
    homepage = "https://minecraft.net";
    license = licenses.unfreeRedistributable;
    platforms = platforms.unix;
    maintainers = with maintainers; [ infinidoge ];
    mainProgram = "minecraft-server";
  };
}