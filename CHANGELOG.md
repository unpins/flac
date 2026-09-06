# Changelog

## [Unreleased]

### Fixed

- `metaflac --version` printed nothing on Windows and still exited 0. metaflac
  switches standard output to UTF-16 whenever it converts tags to UTF-8, which
  is the default, and the version line was the one line it printed without
  going through the UTF-8 writer — so it was dropped. Every other output was
  unaffected, and `--no-utf8-convert --version` always worked. Checked on
  Windows 10: it now prints `metaflac 1.5.0`.

- On Windows, selecting metaflac with `--unpin-program=metaflac` failed with
  `unrecognized option` whenever the binary was invoked under a name shorter
  than `metaflac` — typing `flac --unpin-program=metaflac` with the program on
  PATH was enough. The selector was consumed but stayed in the command line
  metaflac rebuilt its arguments from. Fixed in the shared build library and
  picked up here by the version bump.
