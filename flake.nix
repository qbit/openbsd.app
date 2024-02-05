{
  description = "openbsd.app: a tool to search OpenBSD packages";

  inputs.nixpkgs.url = "github:nixos/nixpkgs";

  outputs = { self, nixpkgs }:
    let
      supportedSystems =
        [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; });
    in {
      packages = forAllSystems (system:
        let pkgs = nixpkgsFor.${system};
        in {
          thing = pkgs.stdenv.mkDerivation {
            pname = "openbsd.app";
            version = "v0.0.1";
            src = ./.;
            nativeBuildInputs = with pkgs.perlPackages; [
              perl
              Mojolicious
              MojoSQLite
              pkgs.outils
              HTMLEscape
            ];
            buildInputs = with pkgs; [ perl ];

            installPhase = ''
              mkdir -p $out/bin
              install -t openbsd.app.pl $out/bin
            '';
          };
        });

      defaultPackage = forAllSystems (system: self.packages.${system}.thing);
      devShells = forAllSystems (system:
        let pkgs = nixpkgsFor.${system};
        in {
          default = pkgs.mkShell {
            shellHook = ''
              PS1='\u@\h:\@; '
              nix run github:qbit/xin#flake-warn
              echo "Perl `${pkgs.perl}/bin/perl --version`"
            '';
            buildInputs = with pkgs.perlPackages; [ PerlTidy pkgs.sqlite ];
            nativeBuildInputs = with pkgs.perlPackages; [
              perl
              Mojolicious
              MojoSQLite
              pkgs.outils
              HTMLEscape
            ] ++ [ pkgs.rlwrap ];
          };
        });
    };
}

