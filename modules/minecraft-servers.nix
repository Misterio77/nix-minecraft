{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.minecraft-servers;

  mkOpt = type: default:
    mkOption { inherit type default; };

  mkOpt' = type: default: description:
    mkOption { inherit type default description; };

  mkBoolOpt = default: mkOption {
    inherit default;
    type = types.bool;
    example = true;
  };

  mkBoolOpt' = default: description: mkOption {
    inherit default description;
    type = types.bool;
    example = true;
  };

  normalizeFiles = files: mapAttrs configToPath (filterAttrs (_: nonEmptyValue) files);
  nonEmptyValue = x: nonEmpty x && (x ? value -> nonEmpty x.value);
  nonEmpty = x: x != { } && x != [ ];

  configToPath = name: config:
    if isStringLike config # Includes paths and packages
    then config
    else (getFormat name config).generate name config.value;
  getFormat = name: config:
    if config ? format && config.format != null
    then config.format
    else inferFormat name;
  inferFormat = name:
    let
      error = throw "nix-minecraft: Could not infer format from file '${name}'. Specify one using 'format'.";
      extension = builtins.match "[^.]*\\.(.+)" name;
    in
    if extension != null && extension != [ ]
    then formatExtensions.${head extension} or error
    else error;

  formatExtensions = with pkgs.formats; {
    "yml" = yaml { };
    "yaml" = yaml { };
    "json" = json { };
    "props" = keyValue { };
    "properties" = keyValue { };
    "toml" = toml { };
    "ini" = ini { };
  };

  configType = types.submodule {
    options = {
      format = mkOption {
        type = with types; nullOr attrs;
        default = null;
        description = ''
          The format to use when converting "value" into a file. If set to
          null (the default), we'll try to infer it from the file name.
        '';
        example = literalExpression "pkgs.formats.yaml { }";
      };
      value = mkOption {
        type = with types; either (attrsOf anything) (listOf anything);
        description = ''
          A value that can be converted into the specified format.
        '';
      };
    };
  };

  mkEnableOpt = description: mkBoolOpt' false description;
in
{
  options.services.minecraft-servers = {
    enable = mkEnableOpt ''
      If enabled, the servers in <option>services.minecraft-servers.servers</option>
      will be created and started as applicable.
      The data for the servers will be loaded from and
      saved to <option>services.minecraft-servers.dataDir</option>
    '';

    eula = mkEnableOpt ''
      Whether you agree to
      <link xlink:href="https://account.mojang.com/documents/minecraft_eula">
      Mojang's EULA</link>. This option must be set to
      <literal>true</literal> to run Minecraft server.
    '';

    openFirewall = mkEnableOpt ''
      Whether to open ports in the firewall for each server.
      Sets the default for <option>services.minecraft-servers.servers.<name>.openFirewall</option>.
    '';

    dataDir = mkOpt' types.path "/srv/minecraft" ''
      Directory to store the Minecraft servers.
      Each server will be under a subdirectory named after
      the server name in this directory, such as <literal>/srv/minecraft/servername</literal>.
    '';

    user = mkOption {
      type = types.str;
      default = "minecraft";
      description = ''
        Name of the user to create and run servers under.
        It is recommended to leave this as the default, as it is
        the same user as <option>services.minecraft-server</option>.
      '';
      internal = true;
      visible = false;
    };

    group = mkOption {
      type = types.str;
      default = "minecraft";
      description = ''
        Name of the group to create and run servers under.
        In order to modify the server files your user must be a part of this
        group.
        It is recommended to leave this as the default, as it is
        the same group as <option>services.minecraft-server</option>.
      '';
    };

    environmentFile = mkOpt' (types.nullOr types.path) null ''
      File consisting of lines in the form varname=value to define environment
      variables for the minecraft servers.

      Secrets (database passwords, secret keys, etc.) can be provided to server
      files without adding them to the Nix store by defining them in the
      environment file and referring to them in option
      <option>services.minecraft-servers.servers.<name>.files</option> with the
      syntax @varname@.
    '';

    servers = mkOption {
      default = { };
      description = ''
        Servers to create and manage using this module.
        Each server can be stopped with <literal>systemctl stop minecraft-server-servername</literal>.
        ::: {.warning}
        If the server is not stopped using `systemctl`, the service will automatically restart the server.
        See <option>services.minecraft-servers.servers.<name>.restart</option>.
        :::
      '';
      type = types.attrsOf (types.submodule {
        options = {
          enable = mkEnableOpt ''
            Whether to enable this server.
            If set to <literal>false</literal>, does NOT delete any data in the data directory,
            just does not generate the service file.
          '';

          autoStart = mkBoolOpt' true ''
            Whether to start this server on boot.
            If set to <literal>false</literal>, can still be started with
            <literal>systemctl start minecraft-server-servername</literal>.
            Requires the server to be enabled.
          '';

          openFirewall = mkOption {
            type = types.bool;
            default = cfg.openFirewall;
            defaultText = "The value of <literal>services.minecraft-servers.openFirewall</literal>";
            description = ''
              Whether to open ports in the firewall for this server.
            '';
          };

          restart = mkOpt' types.str "always" ''
            Value of systemd's <literal>Restart=</literal> service configuration option.
            As a consequence of the <literal>"always"</literal> option, stopping the server
            in-game with the <literal>stop</literal> command will cause the server to automatically restart.
          '';

          enableReload = mkOpt' types.bool false ''
            Reload server when configuration changes (instead of restart).

            This action re-links/copies the declared symlinks/files. You can
            include additional actions (even in-game commands) by setting
            <option>services.minecraft-servers.<name>.extraReload</option>.
          '';

          extraReload = mkOpt' types.lines "" ''
            Extra commands to run when reloading the service. Only has an
            effect if
            <option>services.minecraft-servers.<name>.enableReload</option> is
            true.

            This script has access to $SOCKET variable, that points to the
            relevant stdin socket.
          '';

          extraPreStart = mkOpt' types.lines "" ''
            Extra commands to run before starting the service.
          '';

          extraPostStart = mkOpt' types.lines "" ''
            Extra commands to run after starting the service.

            This script has access to $SOCKET variable, that points to the
            relevant stdin socket.
          '';

          extraPreStop = mkOpt' types.lines "" ''
            Extra commands to run before stopping the service.

            This script has access to $SOCKET variable, that points to the
            relevant stdin socket.
          '';

          extraPostStop = mkOpt' types.lines "" ''
            Extra commands to run after stopping the service.
          '';

          stopCommand = mkOpt' (types.nullOr types.str) "stop" ''
            Console command to run when cleanly stopping the server (ExecStop).
            Defaults to <literal>stop</literal>, which works for most servers.
            For proxies (bungeecord, velocity), you should set
            <literal>end</literal>.

            If set to <literal>null</literal>, the server will be stopped by
            systemd without a explicit ExecStop.
          '';

          whitelist = mkOption {
            type =
              let
                minecraftUUID = types.strMatching
                  "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" // {
                  description = "Minecraft UUID";
                };
              in
              types.attrsOf minecraftUUID;
            default = { };
            description = ''
              Whitelisted players, only has an effect when
              enabled via <option>services.minecraft-servers.<name>.serverProperties</option>
              by setting <literal>white-list</literal> to <literal>true</literal.
            '';
            example = literalExpression ''
              {
                username1 = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx";
                username2 = "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy";
              }
            '';
          };

          serverProperties = mkOption {
            type = with types; attrsOf (oneOf [ bool int str ]);
            default = { };
            example = literalExpression ''
              {
                server-port = 43000;
                difficulty = 3;
                gamemode = 1;
                max-players = 5;
                motd = "NixOS Minecraft server!";
                white-list = true;
                enable-rcon = true;
                "rcon.password" = "hunter2";
              }
            '';
            description = ''
              Minecraft server properties for the server.properties file of this server. See
              <link xlink:href="https://minecraft.gamepedia.com/Server.properties#Java_Edition_3"/>
              for documentation on these values.
            '';
          };

          package = mkOption {
            description = "The Minecraft server package to use.";
            type = types.package;
            default = pkgs.minecraft-server;
            defaultText = literalExpression "pkgs.minecraft-server";
            example = "pkgs.minecraftServers.vanilla-1_18_2";
          };

          jvmOpts = mkOpt' (types.separatedString " ") "-Xmx2G -Xms1G" "JVM options for this server.";

          symlinks = with types; mkOpt' (attrsOf (either path configType)) { } ''
            Things to symlink into this server's data directory, in the form of
            a nix package/derivation. Can be used to declaratively manage
            arbitrary files in the server's data directory.
          '';
          files = with types; mkOpt' (attrsOf (either path configType)) { } ''
            Things to copy into this server's data directory. Similar to
            symlinks, but these are actual files. Useful for configuration
            files that don't behave well when read-only.
          '';
        };
      });
    };
  };

  config = mkIf cfg.enable
    (
      let
        servers = filterAttrs (_: cfg: cfg.enable) cfg.servers;
      in
      {
        users = {
          users.minecraft = {
            description = "Minecraft server service user";
            home = cfg.dataDir;
            createHome = true;
            homeMode = "770";
            isSystemUser = true;
            group = "minecraft";
          };
          groups.minecraft = { };
        };

        assertions = [
          {
            assertion = cfg.eula;
            message = "You must agree to Mojangs EULA to run minecraft-servers."
              + " Read https://account.mojang.com/documents/minecraft_eula and"
              + " set `services.minecraft-servers.eula` to `true` if you agree.";
          }
          {
            assertion = !config.services.minecraft-server.enable && cfg.dataDir != config.services.minecraft-server.dataDir;
            message = "`services.minecraft-servers.dataDir` and `services.minecraft-server.dataDir` conflict."
              + " Set one to use a different data directory.";
          }
          {
            assertion =
              let
                serverPorts = mapAttrsToList
                  (name: conf: conf.serverProperties.server-port or 25565)
                  (filterAttrs (_: cfg: cfg.openFirewall) servers);

                counts = map (port: count (x: x == port) serverPorts) (unique serverPorts);
              in
              lib.all (x: x == 1) counts;
            message = "Multiple servers are set to use the same port. Change one to use a different port.";
          }
        ];

        networking.firewall =
          let
            toOpen = filterAttrs (_: cfg: cfg.openFirewall) servers;
            # Minecraft and RCON
            getTCPPorts = n: c:
              [ c.serverProperties.server-port or 25565 ] ++
              (optional (c.serverProperties.enable-rcon or false) (c.serverProperties."rcon.port" or 25575));
            # Query
            getUDPPorts = n: c:
              optional (c.serverProperties.enable-query or false) (c.serverProperties."query.port" or 25565);
          in
          {
            allowedUDPPorts = flatten (mapAttrsToList getUDPPorts toOpen);
            allowedTCPPorts = flatten (mapAttrsToList getTCPPorts toOpen);
          };

        systemd.tmpfiles.rules = mapAttrsToList
          (name: _:
            "d '${cfg.dataDir}/${name}' 0770 ${cfg.user} - - -"
          )
          servers;

        systemd.sockets = mapAttrs'
          (name: conf: {
            name = "minecraft-server-${name}";
            value = {
              bindsTo = [ "minecraft-server-${name}.service" ];
              socketConfig = {
                ListenFIFO = "/run/minecraft-server/${name}.stdin";
                SocketMode = "0660";
                SocketUser = "minecraft";
                SocketGroup = "minecraft";
                RemoveOnStop = true;
                FlushPending = true;
              };
            };
          }) servers;

        systemd.services = mapAttrs'
          (name: conf:
            let
              symlinks = normalizeFiles ({
                "eula.txt".value = { eula = true; };
                "eula.txt".format = pkgs.formats.keyValue { };
              } // conf.symlinks);
              files = normalizeFiles ({
                "whitelist.json".value = mapAttrsToList (n: v: { name = n; uuid = v; }) conf.whitelist;
                "server.properties".value = conf.serverProperties;
              } // conf.files);

              socketPath = config.systemd.sockets."minecraft-server-${name}".socketConfig.ListenFIFO;

              # Added to relevant scripts, defines $SOCKET to help run in-game commands
              # This may be expanded in the future to add more variables or shell functions
              prelude = ''
                SOCKET=${socketPath}
              '';

              stopScript = pkgs.writeShellScript "minecraft-server-stop" ''
                ${prelude}
                # There's no ExecStopPre, and stopPre conflicts with serviceConfig.ExecStop
                # So put extraPreStop here instead.
                ${conf.extraPreStop}
                ${optionalString (conf.stopCommand != null) "echo ${escapeShellArg conf.stopCommand} > $SOCKET"}

                # Wait for the PID of the minecraft server to disappear before
                # returning, so systemd doesn't attempt to SIGKILL it.
                tries=3
                while kill -0 "$1" 2> /dev/null; do
                  if [[ $tries -gt 0 ]]; then
                    sleep 1s
                  else
                    echo >&2 "Timed out waiting for server to stop."
                    exit 1
                  fi
                  ((tries--))
                done
              '';

              rmSymlinks = pkgs.writeShellScript "minecraft-server-${name}-rm-symlinks"
                (concatStringsSep "\n"
                  (mapAttrsToList (n: v: "unlink \"${n}\"") symlinks)
                );
              rmFiles = pkgs.writeShellScript "minecraft-server-${name}-rm-files"
                (concatStringsSep "\n"
                  (mapAttrsToList (n: v: "rm -f \"${n}\"") files)
                );

              mkSymlinks = pkgs.writeShellScript "minecraft-server-${name}-symlinks"
                (concatStringsSep "\n"
                  (mapAttrsToList
                    (n: v: ''
                      if [[ -L "${n}" ]]; then
                        unlink "${n}"
                      elif [[ -e "${n}" ]]; then
                        echo "${n} already exists, moving"
                        mv "${n}" "${n}.bak"
                      fi
                      mkdir -p "$(dirname "${n}")"
                      ln -sf "${v}" "${n}"
                    '')
                    symlinks));

              mkFiles = pkgs.writeShellScript "minecraft-server-${name}-files"
                (concatStringsSep "\n"
                  (mapAttrsToList
                    (n: v: ''
                      if [[ -L "${n}" ]]; then
                        unlink "${n}"
                      elif ${pkgs.diffutils}/bin/cmp -s "${n}" "${v}"; then
                        rm "${n}"
                      elif [[ -e "${n}" ]]; then
                        echo "${n} already exists, moving"
                        mv "${n}" "${n}.bak"
                      fi
                      mkdir -p $(dirname "${n}")
                      ${pkgs.gawk}/bin/awk '{
                        for(varname in ENVIRON)
                          gsub("@"varname"@", ENVIRON[varname])
                        print
                      }' "${v}" > "${n}"
                    '')
                    files));
            in
            {
              name = "minecraft-server-${name}";
              value = {
                description = "Minecraft Server ${name}";
                wantedBy = mkIf conf.autoStart [ "multi-user.target" ];
                requires = [ "minecraft-server-${name}.socket" ];
                after = [ "network.target" "minecraft-server-${name}.socket" ];

                enable = conf.enable;

                restartIfChanged = !conf.enableReload;
                reloadIfChanged = conf.enableReload;

                reload = ''
                  ${prelude}
                  ${rmSymlinks}
                  ${rmFiles}
                  ${mkSymlinks}
                  ${mkFiles}
                  ${conf.extraReload}
                '';

                preStart = ''
                  ${prelude}
                  ${mkSymlinks}
                  ${mkFiles}
                  ${conf.extraPreStart}
                '';

                postStart = ''
                  ${prelude}
                  ${conf.extraPostStart}
                '';

                postStop = ''
                  ${prelude}
                  ${rmSymlinks}
                  ${rmFiles}
                  ${conf.extraPostStop}
                '';

                serviceConfig = {
                  ExecStart = "${getExe conf.package} ${conf.jvmOpts}";
                  ExecStop = "${stopScript} $MAINPID";
                  Restart = conf.restart;
                  WorkingDirectory = "${cfg.dataDir}/${name}";
                  User = "minecraft";
                  EnvironmentFile = mkIf (cfg.environmentFile != null)
                    (toString cfg.environmentFile);
                  Type = "simple";

                  StandardInput = "socket";
                  StandardOutput = "journal";
                  StandardError = "journal";

                  # Hardening
                  CapabilityBoundingSet = [ "" ];
                  DeviceAllow = [ "" ];
                  LockPersonality = true;
                  PrivateDevices = true;
                  PrivateTmp = true;
                  PrivateUsers = true;
                  ProtectClock = true;
                  ProtectControlGroups = true;
                  ProtectHome = true;
                  ProtectHostname = true;
                  ProtectKernelLogs = true;
                  ProtectKernelModules = true;
                  ProtectKernelTunables = true;
                  ProtectProc = "invisible";
                  RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
                  RestrictNamespaces = true;
                  RestrictRealtime = true;
                  RestrictSUIDSGID = true;
                  SystemCallArchitectures = "native";
                  UMask = "0007";
                };
              };
            })
          servers;
      }
    );
}
