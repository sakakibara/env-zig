# env-zig

The process environment, and the identity and directories derived from it.

A program takes its environment as an argument instead of reaching for the
process's own, so the same code runs against an environment a test made up --
on every platform, including the one where the standard library cannot
represent a synthetic environment at all.

```zig
const env = @import("env");

const e = env.Env.current();

const home = try env.dirs.home(arena, e);
const cfg = try env.dirs.configHome(arena, e); // $XDG_CONFIG_HOME, %LOCALAPPDATA%, or ~/.config
const mine = try env.dirs.appDir(arena, cfg, "myapp");
```

And in a test, the same code against an environment you control:

```zig
var map = std.process.Environ.Map.init(a);
try map.put("XDG_CONFIG_HOME", "/custom/config");

const e: env.Env = .{ .map = &map };
try testing.expectEqualStrings("/custom/config", try env.dirs.configHome(a, e));
```

## Why not `std.process.Environ`

On Windows its `Block` is a `GlobalBlock`: the environment lives in the PEB,
which moves whenever it is edited, so no stable pointer to a synthetic one can
exist. Nothing can hand it an environment the process does not already have.
A test that needs a program to see a different `HOME` is then left mutating the
environment of the process running it -- global state, shared across tests, and
restored by hand.

`Env` is a union of the real process environment or a supplied map, so the
injected case works the same everywhere.

## What it covers

| | |
| --- | --- |
| `Env` | `current()`, `getAlloc`, `get` (an empty value reads as unset), `createMap` for a child process |
| `dirs` | `home`, `username`, `hostname`, `configHome`, `dataHome`, `stateHome`, `cacheHome`, `appDir`, `expandTilde`, `contractTilde` |
| | `configHomeFor` and friends resolve against a named OS rather than the host's, so a test can pin every platform's answer from whichever one it runs on. `baseDirIn` takes a home already in hand, for a program that keeps its own answer for "no home in the environment". |
| `path` | `joinRel`, `joinSegments`, `toRel`, `relUnder` |

The XDG base directories are honoured on every platform, because a user who
sets `XDG_CONFIG_HOME` means it. Absent them, POSIX nests under `~/.config` and
`~/.local`, and Windows nests under `%LOCALAPPDATA%`.

`hostname` reads `COMPUTERNAME` on Windows, where `std.posix.gethostname` does
not exist -- `HOST_NAME_MAX` is not even a number there.

## Paths that travel

A relative path written in config, a data file, or a repository is
`/`-delimited on every platform: `.config/git/config` names the same file
whoever wrote it. A filesystem path uses the platform's separator. The two are
not interchangeable, and `std.fs.path.join` does not distinguish them:

- splice a `/`-delimited tail onto a native base and the separators come out
  mixed (`C:\Users\me\.config/git/config`);
- build the relative path with `join` and Windows writes `src\.zshrc`, which
  matches no `src/` prefix and equals nothing another machine wrote.

`path.joinRel` splits the relative path and lets each segment nest with the
platform's own separator; `path.relUnder` goes back the other way.

## Install

```sh
zig fetch --save https://github.com/sakakibara/env-zig/archive/refs/tags/v0.1.0.tar.gz
```

```zig
const env_dep = b.dependency("env", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("env", env_dep.module("env"));
```

Requires Zig 0.16.0.

## Reference

Generated API docs: **https://sakakibara.github.io/env-zig/**, or `zig build docs`
and open `zig-out/docs/index.html`.
