{
  description = "Kanata keyboard remapping utility";

  inputs.flake-utils.url  = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        manifest = (pkgs.lib.importTOML ./Cargo.toml).package;
      in
      {
        packages.default = pkgs.rustPlatform.buildRustPackage {
          pname = manifest.name;
          version = manifest.version;
          src = pkgs.lib.cleanSource ./.;
          cargoLock.lockFile = ./Cargo.lock;
          buildFeatures = [ "cmd" ];
        };
        apps.default = flake-utils.lib.mkApp {
          drv = self.packages.${system}.default;
        };
      }
    ) // {
      overlays.default = final: prev: { kanata = self.packages.${prev.system}.default; };
      homeManagerModules.default = {pkgs, config, lib, ...}: let inherit (lib) types; in {
        options.services.kanata = {
          enable = lib.mkEnableOption "Enable kanata service";
          extraPackages = lib.mkOption {
            type = with types; listOf (oneOf [ package str ]);
            description = "Extra packages to include in the systemd service path";
            default = [];
          };
          configPath = lib.mkOption {
            type = types.path;
            description = "Path to the config file";
          };
        };

        config = lib.mkIf config.services.kanata.enable {
          systemd.user.services.kanata = {
            Unit.Description = "kanata keyboard config";
            Install.WantedBy = [ "graphical-session.target" ];
            Service = {
              Environment= [
                "PATH=${pkgs.lib.makeBinPath config.services.kanata.extraPackages}"
                "DISPLAY=:0"
              ];
              Restart="always";
              RestartSec=3;
              ExecStart=
                let binpath = "${self.packages.${pkgs.system}.default}/bin/kanata";
                    kanata-cfg = pkgs.stdenv.mkDerivation {
                      name = "kanata-config";
                      src = config.services.kanata.configPath;
                      dontUnpack = true;
                      dontPatch = true;
                      dontConfigure = true;
                      dontBuild = true;
                      buildInputs = [ self.packages.${pkgs.system}.default ];
                      checkPhase = ''
                        kanata --check --cfg $src
                      '';
                      doCheck = true;

                      installPhase = ''
                        cp $src $out
                      '';
                    };
                in "${binpath} --cfg ${kanata-cfg} --nodelay";
              Nice=-20;
            };
          };
        };
      };
    };
}
