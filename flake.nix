{
  description = "the flac tools (FLAC lossless audio codec) as a single self-contained binary";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # flac installs two CLIs — `flac` (encode/decode) and `metaflac` (metadata
  # editor); nix-lib folds them into one `flac` dispatcher binary with
  # `metaflac` as an argv[0]-dispatch UNPIN_META alias. Windows goes through
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
      # metaflac puts stdout in _O_U8TEXT whenever it converts tags to UTF-8,
      # which is the default; in that mode the narrow printf writes nothing.
      # Every other line it prints goes through flac_printf (= printf_utf8 on
      # Windows) — show_version() is the one that does not, so on Windows
      # `metaflac --version` printed an empty line and exited 0. Applied on
      # every platform so the source stays the same everywhere; off Windows
      # flac_printf *is* printf, so only the .exe changes behaviour.
      versionFix = drv: drv.overrideAttrs (oa: {
        postPatch = (oa.postPatch or "") + ''
          substituteInPlace src/metaflac/operations.c \
            --replace-fail 'printf("metaflac %s\n", FLAC__VERSION_STRING);' \
                           'flac_printf("metaflac %s\n", FLAC__VERSION_STRING);'
        '';
      });
    in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "flac";
      # the flac/metaflac CLI tools are GPL-2.0-or-later; libFLAC (BSD) is linked
      # in but the shipped programs are GPL.
      license = "GPL-2.0-or-later";
      smoke = [ "--version" ];
      smokePattern = "flac 1\\.5";

      # Every target self-folds flac + metaflac from the captured module.bc.
      engine = "unpin-llvm";
      multicall = {
        windows = true;
        programs = [{ name = "flac"; } { name = "metaflac"; }];
      };
      # flac's suite already runs, and unlike most of the catalog it is a real
      # one: the build is CMake, and test/CMakeLists.txt registers ten ctest
      # entries — the libFLAC and grabbag unit tests plus the test_flac.sh,
      # test_metaflac.sh, test_streams.sh, test_seeking.sh, test_replaygain.sh
      # and test_compression.sh shell suites. doCheck is what leaves
      # BUILD_TESTING on, so turning it off would silently register none of
      # them. Said here so it is this package's decision and not an inherited
      # default that can flip under us; the drvPath is unchanged by saying it.
      build = pkgs:
        let base = versionFix pkgs.pkgsStatic.flac; in
        base.overrideAttrs (_: {
          doCheck = base.stdenv.buildPlatform.canExecute base.stdenv.hostPlatform;
        });
      windowsBuild = pkgs: versionFix (ulib.mingwStaticCross pkgs).flac;
    };
}
