# Changelog

## [Unreleased]

### Fixed

- `metaflac --version` printed nothing on Windows and still exited 0. metaflac
  switches standard output to UTF-16 whenever it converts tags to UTF-8, which
  is the default, and the version line was the one line it printed without
  going through the UTF-8 writer — so it was dropped. Every other output was
  unaffected, and `--no-utf8-convert --version` always worked. Checked on
  Windows 10: it now prints `metaflac 1.5.0`.

