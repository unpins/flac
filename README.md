# flac

The [flac](https://xiph.org/flac/) command-line programs — the reference
encoder/decoder and metadata editor for the FLAC lossless audio codec. A single
self-contained binary, built natively for Linux, macOS, and Windows.

[![CI](https://github.com/unpins/flac/actions/workflows/flac.yml/badge.svg)](https://github.com/unpins/flac/actions)
![Linux](https://img.shields.io/badge/Linux-✓-success?logo=linux&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-✓-success?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-✓-success?logo=windows&logoColor=white)

Part of the [unpins](https://unpins.org) catalog; install it with [`unpin`](https://github.com/unpins/unpin): `unpin install flac`.

## Usage

Run the `flac` program with [unpin](https://github.com/unpins/unpin):

```bash
unpin flac song.wav             # encode WAV -> song.flac
unpin flac -d song.flac         # decode -> song.wav
unpin flac -c - < in.wav > out.flac   # or straight through a pipe
```

To install it onto your PATH:

```bash
unpin install flac
```

`unpin install flac` also creates the `metaflac` command, which views and edits FLAC metadata, tags and pictures.

## Man pages

Both man pages are embedded — read them with `unpin man flac` and `unpin man flac metaflac`.

## Build locally

```bash
nix build github:unpins/flac
./result/bin/flac --version
```

Or run directly:

```bash
nix run github:unpins/flac -- --version
```

The first invocation will offer to add the [unpins.cachix.org](https://unpins.cachix.org) substituter so most pulls come pre-built.

## Manual download

The [Releases](https://github.com/unpins/flac/releases) page has standalone binaries for manual download.

## Build notes

- Both tools live in one binary and share the code they have in common —
  libFLAC, libogg and the internal helpers are in there once, not twice, which
  is why the pair costs little more than `flac` alone.
- **Windows:** a single `.exe`, no companion DLLs. Encoding and decoding
  through a pipe is byte-for-byte the same as on Linux and macOS.
