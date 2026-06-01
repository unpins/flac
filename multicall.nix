# flac ships two command-line tools — `flac` (the encoder/decoder) and
# `metaflac` (the metadata editor). To honour the unpins one-pkg-one-bin rule we
# post-link them into a single multicall binary at $out/bin/flac (a busybox-style
# dispatcher named after the package, as the unpins CI resolves
# result/bin/<package-name>); `lib.withAliases` then embeds `metaflac` as an
# UNPIN_META alias so unpin's installer recreates the argv[0] shim.
#
# Why a post-link route (no source patch): the two tools are separate CMake
# executables, but each is built from its OWN object set (src/flac/* and
# src/metaflac/*) and they share the heavy static archives — libFLAC plus the
# internal getopt / replaygain_synthesis / utf8 helper libs and external libogg.
# So we reuse the proven ld-free rename recipe (cf. libwebp): per tool, build ONE
# redef map (main → <tool>_main, every other strong defined global foo →
# <tool>__foo) from the tool's raw objects and objcopy it onto each object in
# place — objcopy rewrites the definition AND every relocation, so the
# multi-object tools stay internally consistent and their two `main`s (plus any
# same-named helper, e.g. both tools carry a `utils.c`) no longer collide. The
# renamed raw objects, not an `ld -r` partial, go into the final link: ld64's
# `-r` would demote a `main` that owns function-local statics from global (T) to
# local (t), emptying the map and leaving <tool>_main undefined on darwin. The
# shared archives are linked ONCE at the end, so the binary carries one copy of
# libFLAC, not two.
#
# The archive + -l link list is read straight out of each tool's CMake link.txt
# at build time, so the exact store paths and codec libs the build actually
# configured are reused verbatim on every platform (musl ELF / Mach-O / mingw) —
# no hard-coded dependency set to drift. Unlike libwebp, flac's targets live in
# subdirs (src/flac, src/metaflac), so each link.txt's relative archive paths are
# resolved against that target's link dir before use.
#
# Shared by the native `build` (pkgsStatic) and the `windowsBuild`
# (mingwStaticCross) paths; isDarwin/isWindows come from the INPUT derivation's
# stdenv (under windowsBuild `pkgs` is the x86_64-linux root — the cross lives
# inside mingwStaticCross — so `pkgs.stdenv` would wrongly say "not Windows").
{ lib }:
{ pkgs, flac }:
let
  isDarwin = flac.stdenv.hostPlatform.isDarwin or false;
  isWindows = flac.stdenv.hostPlatform.isWindows or false;

  multicall = flac.overrideAttrs (old: {
    pname = "flac-multi";
    outputs = [ "out" ];

    # Build the static archives (and the two CLIs) rather than the shared libs;
    # appended last so it wins over the expr's BUILD_SHARED_LIBS toggle. (FLAC's
    # CMake already adds -DFLAC__NO_DLL to the static tool builds, so the mingw
    # objects' refs to libFLAC are plain `.refptr` stubs that resolve straight
    # from libFLAC.a — no dllimport guard to add here.)
    cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DBUILD_SHARED_LIBS:BOOL=FALSE" ];

    # flac's test suite downloads/encodes large fixtures; we re-link the tools
    # ourselves and smoke-test the result, so skip it.
    doCheck = false;
    doInstallCheck = false;

    postBuild = (old.postBuild or "") + ''
      set -e
      mkdir -p mc

      # Tool → (link dir, CMake object dir). flac's executable target is named
      # `flacapp` (RUNTIME_OUTPUT_NAME flac); metaflac's target matches its name.
      declare -A TLD TOD
      TLD[flac]="src/flac";          TOD[flac]="src/flac/CMakeFiles/flacapp.dir"
      TLD[metaflac]="src/metaflac";  TOD[metaflac]="src/metaflac/CMakeFiles/metaflac.dir"
      TOOLS="flac metaflac"

      # CMake names objects <src>.c.o on ELF/Mach-O but <src>.c.obj on MinGW
      # (where the .rc resource also yields version.rc.obj). Detect the extension
      # from flac's main object, then take every object in each tool's dir — they
      # are all unique to that tool. Search recursively: on Windows the
      # tools pull in ../share/win_utf8_io/win_utf8_io.c, which CMake compiles to
      # a nested CMakeFiles/<t>.dir/__/share/win_utf8_io/win_utf8_io.c.obj.
      oext=o
      [ -f "''${TOD[flac]}/main.c.obj" ] && oext=obj
      declare -A TOBJ
      for t in $TOOLS; do TOBJ[$t]=$(find "''${TOD[$t]}" -name "*.$oext" | sort); done

      # Harvest the library link list from each tool's CMake link.txt. We take
      # only the archive / -l tokens (objects are gathered above). Relative *.a
      # paths are resolved against the tool's link dir; absolute *.a and -l* pass
      # through. The per-tool `objects.a` bundle and `*.dll.a` import libs are
      # skipped. Dedup, first-seen order (dependency-correct).
      LIBS=""
      addlib() { case " $LIBS " in *" $1 "*) ;; *) LIBS="$LIBS $1" ;; esac; }
      classify() {
        local base="$1" tok="$2"
        tok="''${tok%\"}"; tok="''${tok#\"}"
        case "$tok" in
          *objects.a | *.dll.a) ;;
          -l*)   addlib "$tok" ;;
          /*.a)  addlib "$tok" ;;
          *.a)   addlib "$(realpath -m "$base/$tok")" ;;
        esac
      }
      # MinGW CMake moves the library list into an `@…linkLibs.rsp` response
      # file referenced *relative to the tool's link dir* — resolve the @path
      # against TLD[$t] (not the build root) or the rsp is silently skipped and
      # every archive in it (libFLAC, libogg, …) goes missing from the link.
      for t in $TOOLS; do
        lt="''${TOD[$t]}/link.txt"
        for tok in $(tr ' ' '\n' < "$lt"); do
          case "$tok" in
            @*) rf="''${TLD[$t]}/''${tok#@}"
                [ -f "$rf" ] && for rt in $(tr ' ' '\n' < "$rf"); do classify "''${TLD[$t]}" "$rt"; done ;;
            *)  classify "''${TLD[$t]}" "$tok" ;;
          esac
        done
      done

      # Mach-O leads C symbols with '_'; detect once from flac's main object.
      if $NM --defined-only ''${TOBJ[flac]} 2>/dev/null | awk '$3=="_main"{f=1} END{exit !f}'; then
        up=_
      else
        up=""
      fi

      # Per tool: one redef map (main → <t>_main, other strong defined globals
      # foo → <t>__foo; skip weak/COMDAT W/V and names containing '.'), applied
      # to each raw object so refs follow the rename and the two tools never
      # collide.
      MCOBJS=""
      for t in $TOOLS; do
        $NM --defined-only ''${TOBJ[$t]} 2>/dev/null \
          | awk -v t="$t" -v up="$up" '
              $2 ~ /^[A-TX-Z]$/ && $2 != "W" && $2 != "V" {
                sym = $3; core = sym
                if (up != "" && index(core, up) == 1) core = substr(core, 2)
                if (index(core, ".") != 0) next
                if (core !~ /^[A-Za-z_][A-Za-z0-9_]*$/) next
                if (core == "main") print sym " " up t "_main"
                else                print sym " " up t "__" core
              }' | sort -u > "mc/$t.redef"
        for o in ''${TOBJ[$t]}; do
          d="mc/$t.$(basename "$o")"
          cp "$o" "$d"
          [ -s "mc/$t.redef" ] && $OBJCOPY --redefine-syms="mc/$t.redef" "$d"
          MCOBJS="$MCOBJS $d"
        done
      done

      # Dispatcher (shared canonical generator — see nix-lib
      # lib.multicallDispatcherC). Applet list from multicall/apps.list ($TOOLS);
      # a bare/unknown invocation runs flac (defaultApplet) so the `flac
      # --version` smoke reaches flac_main and a renamed copy still dispatches.
      mkdir -p multicall
      printf '%s\n' $TOOLS > multicall/apps.list
${lib.multicallDispatcherC { name = "flac"; defaultApplet = "flac"; }}
      $CC -O2 -c -o multicall/dispatcher.o multicall/dispatcher.c

      # Final link: shared archives, once. On GNU-ld targets wrap them in a group
      # to absorb back-references; ld64 (darwin) rejects --start-group but
      # re-scans archives on its own, so list them plain there.
      if ${if isDarwin then "true" else "false"}; then
        GO=""; GC=""
      else
        GO="-Wl,--start-group"; GC="-Wl,--end-group"
      fi
      # mingw: this manual link bypasses the `-static` the normal
      # mingwStaticCross build applies. flac 1.5.0's multithreaded encoder pulls
      # the gcc `mcf` thread model, which would import libmcfgthread-2.dll next to
      # the .exe; link the runtime fully static so every -l resolves to its .a and
      # only real Windows system DLLs remain.
      MCF=""
      ${lib.optionalString isWindows ''MCF="-static"''}
      $CC -O2 \
        $MCOBJS multicall/dispatcher.o \
        $GO $LIBS $GC -lm $MCF \
        -o mc/flac
      [ -f mc/flac ] || mv mc/flac.exe mc/flac
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/bin" "$out/share/man/man1"
      # Canonical binary is named after the package (flac) — a busybox-style
      # dispatcher; metaflac is a symlink that lib.withAliases turns into an
      # argv[0] alias.
      install -m755 mc/flac "$out/bin/flac"
      ln -s flac "$out/bin/metaflac"

      # Man pages ship prebuilt in the tarball (man/<tool>.1); ship both so the
      # set matches nixpkgs' flac man output (no winManRoot needed).
      mandir=""
      for d in ../man man "$src/man"; do [ -f "$d/flac.1" ] && mandir="$d" && break; done
      if [ -n "$mandir" ]; then
        for m in flac metaflac; do
          [ -f "$mandir/$m.1" ] && cp "$mandir/$m.1" "$out/share/man/man1/$m.1"
        done
      fi
      runHook postInstall
    '';
  });

  aliased = lib.withAliases pkgs
    {
      primary = "flac";
      aliasesFromSymlinksIn = "bin";
    }
    multicall;
in
if isWindows
then aliased.overrideAttrs (o: {
  postFixup = (o.postFixup or "") + ''
    [ -f "$out/bin/flac" ] && mv "$out/bin/flac" "$out/bin/flac.exe"
  '';
})
else aliased
