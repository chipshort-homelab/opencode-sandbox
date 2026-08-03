{ pkgs ? import <nixpkgs> { } }:

pkgs.callPackage
  ({ lib, stdenv, bubblewrap, bash }:

    let
      bwrapPath = "${bubblewrap}/bin/bwrap";
      bashPath = "${bash}/bin/bash";
    in
    stdenv.mkDerivation {
      pname = "nixos-sandbox";
      version = "0.1.0";

      src = lib.cleanSource ./.;

      buildPhase = ''
        runHook preBuild
        substituteAll ${./sandbox.sh} sandbox.sh
        chmod +x sandbox.sh
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        install -Dm755 sandbox.sh "$out/bin/sandbox"
        runHook postInstall
      '';

      inherit bwrapPath bashPath;

      meta = with lib; {
        description = "Run a command in a bubblewrap sandbox on NixOS";
        longDescription = ''
          sandbox wraps a command in a bubblewrap sandbox. The whole system is
          mounted read-only, including $HOME and $XDG_RUNTIME_DIR. Only the
          working directory (and dirs given with -w/--write) are writable,
          plus the nix daemon socket, the user's per-user nix store dirs and
          the nix cache/state dirs (~/.cache/nix, ~/.local/state/nix), so nix
          tooling works for any command.
        '';
        homepage = "https://github.com/NixOS/bubblewrap";
        license = licenses.mit;
        platforms = platforms.linux;
      };
    })
  { }
