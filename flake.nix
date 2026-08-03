{
  description = "bubblewrap-based sandbox for NixOS";

  inputs.nixpkgs.url = "nixpkgs";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system} = {
        default = pkgs.callPackage ./default.nix { };
        opencode = import ./opencode.nix { inherit pkgs; };
      };

      nixosModules.default = { config, lib, pkgs, ... }:
        let
          cfg = config.programs.opencode-sandbox;
        in
        {
          options.programs.opencode-sandbox = {
            enable = lib.mkEnableOption "the bubblewrap-sandboxed opencode";
            opencode = lib.mkOption {
              type = lib.types.package;
              default = pkgs.opencode;
              description = "The opencode package to run inside the sandbox.";
            };
          };

          config = lib.mkIf cfg.enable {
            environment.systemPackages = [
              (import ./opencode.nix { inherit pkgs; opencode = cfg.opencode; })
            ];
          };
        };
    };
}
