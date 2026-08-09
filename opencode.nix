{ pkgs ? import <nixpkgs> { }, opencode ? null }:

let
  sandbox = import ./default.nix { inherit pkgs; };
  oc = if opencode == null then pkgs.opencode else opencode;
in
pkgs.callPackage
  ({ lib, stdenv, bash }:

    stdenv.mkDerivation {
      pname = "opencode-sandbox";
      version = oc.version or "";

      src = lib.cleanSource ./.;

      buildPhase = ''
        runHook preBuild
        substituteAll ${./opencode.sh} opencode.sh
        chmod +x opencode.sh
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        install -Dm755 opencode.sh "$out/bin/opencode"
        runHook postInstall
      '';

      sandboxPath = "${sandbox}/bin/sandbox";
      opencodePath = "${oc}/bin/opencode";
      bashPath = "${bash}/bin/bash";

      meta = with lib; {
        description = "opencode running inside the nixos-sandbox";
        longDescription = ''
          Runs the given opencode package inside the bubblewrap sandbox from
          this repository, with network enabled. opencode's XDG config, state
          and data dirs are writable, and the cache dir (~/.cache) is writable
          via the general sandbox; everything else in the home directory stays
          read-only.
        '';
        homepage = "https://github.com/anomalyco/opencode";
        license = oc.meta.license or licenses.mit;
        platforms = platforms.linux;
        mainProgram = "opencode";
      };
    })
  { }
