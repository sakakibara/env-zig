# Changelog

All notable changes to this project are documented here. Format based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-07-13

### Added

- `Env`: the process environment as a union of the real one or a supplied map,
  so a program takes its environment as an argument and a test hands it one.
  Windows resolves `std.process.Environ.Block` to a `GlobalBlock` -- the
  environment lives in the PEB, which moves when edited, so no pointer to a
  synthetic one can exist -- and a test there is otherwise left mutating the
  environment of the process running it.
- `dirs`: `home`, `username`, `hostname`, and the XDG base directories, each
  derived from an `Env`. XDG is honoured on every platform; absent it, POSIX
  nests under `~/.config` and `~/.local` and Windows under `%LOCALAPPDATA%`.
  `hostname` reads `COMPUTERNAME` on Windows, where `std.posix.gethostname`
  does not exist. `expandTilde`/`contractTilde` for `~`.
- `path`: `joinRel`, `joinSegments`, `toRel`, `relUnder`, keeping a
  `/`-delimited relative path (as config and repositories write it) apart from
  a native filesystem path, which `std.fs.path.join` does not distinguish.

[Unreleased]: https://github.com/sakakibara/env-zig/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/sakakibara/env-zig/releases/tag/v0.1.0
