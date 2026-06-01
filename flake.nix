{
  description = "Standalone build of the flac tools (FLAC lossless audio codec)";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # flac installs two CLIs — `flac` (encode/decode) and `metaflac` (metadata
  # editor); ./multicall.nix post-links them into one `flac` dispatcher binary
  # with `metaflac` as an argv[0]-dispatch UNPIN_META alias. Windows goes through
  # mingw — flac is portable CMake C with a single small dependency (libogg), so
  # it cross-compiles cleanly (like brotli/libwebp); the runtime is folded static
  # in the multicall link so the .exe carries no companion DLLs.
  #
  # The canonical binary is named `flac` (= the package name = the flagship
  # tool); the unpins CI portability/smoke checks resolve result/bin/<name>, so
  # the dispatcher carries the package name and metaflac is its alias. Both
  # upstream man pages (flac.1, metaflac.1) ship, matching nixpkgs' flac man
  # output, so no winManRoot curation is needed.
  outputs = { self, unpins-lib }:
    let
      ulib = unpins-lib.lib;
    in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "flac";
      smoke = [ "--version" ];
      smokePattern = "flac 1\\.5";
      build = pkgs:
        import ./multicall.nix { lib = pkgs.lib // ulib; }
          { inherit pkgs; flac = pkgs.pkgsStatic.flac; };
      windowsBuild = pkgs:
        import ./multicall.nix { lib = pkgs.lib // ulib; }
          { inherit pkgs; flac = (ulib.mingwStaticCross pkgs).flac; };
    };
}
