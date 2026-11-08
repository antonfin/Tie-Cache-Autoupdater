# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`Tie::Cache::Autoupdater` — a CPAN distribution of a single Perl module implementing a tied hash
whose values are produced by user-supplied callbacks and cached for a per-key timeout. Intended for
long-lived processes (FastCGI) that need to re-read slowly changing data on a fixed interval.

## Layout quirk: the module lives at the repo root

The source file is `Autoupdater.pm` at the top level, not `lib/Tie/Cache/Autoupdater.pm`. ExtUtils::
MakeMaker derives the install path from `NAME` in `Makefile.PL` and copies it to
`blib/lib/Tie/Cache/Autoupdater.pm` during `make`. Consequences:

- Tests `use_ok('Tie::Cache::Autoupdater')` and each one starts with `use lib 'blib/lib'`, so **the
  suite only runs after a build has populated `blib/`** — `prove -I.` will not find the module.
- If you add files, update `MANIFEST` by hand; `perl Makefile.PL` checks the kit against it.
- Bump `$VERSION` in `Autoupdater.pm` (read by `VERSION_FROM`), the `=head1 VERSION` POD line, and
  add a `Changes` entry together — all three are kept in sync by hand. The distribution abstract
  comes from the POD `=head1 NAME` line via `ABSTRACT_FROM`, so keep that line in
  `Name - description` form.

## Build and test

```sh
perl Makefile.PL
make                 # copies Autoupdater.pm -> blib/lib/Tie/Cache/Autoupdater.pm
make test            # runs t/*.t
make install
```

Single test file:

```sh
make && prove -Iblib/lib t/10_errors.t      # or: perl -Iblib/lib t/10_errors.t
```

The suite takes ~30s because the timeout tests use real `sleep`.

### macOS system perl cannot build

On this machine `/usr/bin/perl` (5.34) has no `CORE/` headers — the SDK only ships them for 5.18,
5.28 and 5.30 — so `make` dies with `No rule to make target .../CORE/config.h`, and no XS module
(including `Devel::Cover`) can be installed against it. For a pure-Perl dist, staging the module by
hand is equivalent to what `make` does:

```sh
mkdir -p blib/lib/Tie/Cache && cp Autoupdater.pm blib/lib/Tie/Cache/
prove -Iblib/lib t/
```

### Coverage and multi-version checks (Docker)

Both need a working toolchain, so run them in a container. Docker Desktop's credential helper hangs
here; point `DOCKER_CONFIG` at a directory holding `{}` as `config.json` to bypass it.

```sh
docker build -t perl-cover:5.40 -  <<'EOF'
FROM perl:5.40
RUN cpanm --notest Devel::Cover && rm -rf /root/.cpanm
EOF

docker run --rm -v "$PWD":/src:ro -w /work perl-cover:5.40 bash -c \
  'cp -r /src/. /work/ && perl Makefile.PL >/dev/null && make >/dev/null && cover -test'
```

The module is at **100% statement, branch, condition and subroutine coverage** — keep it there when
changing code. `cover -test -report text` lists what is uncovered.

To check a perl version, swap the image (verified on 5.26, 5.32, 5.36, 5.38, 5.40, 5.42; older tags
and anything below 5.26 are not available as arm64 images, add `--platform linux/amd64`):

```sh
docker run --rm -v "$PWD":/src:ro -w /work perl:5.42 bash -c \
  'cp -r /src/. /work/ && perl Makefile.PL >/dev/null && make >/dev/null && make test'
```

## Architecture

`$self` is the tied hash and doubles as the per-key config/state store: each key maps to
`{ timeout, source, last, result, clone }`. There is no separate data structure — writing to the
tied hash registers a cache entry rather than storing a value.

- `STORE` and `TIEHASH` share the same entry-construction logic (duplicated in both); `$cache{k} = {...}`
  and `tie %cache, ..., k => {...}` are interchangeable. A store always resets `last`/`result`,
  so re-registering a key invalidates it.
- `_fetch` is the single read path: if `last + timeout < time()`, it calls `source` under `eval`
  (on error it `warn`s and returns `undef` without updating `last`, so the next read retries),
  normalizes the return (empty list → `undef`, one value → scalar, list → arrayref), and stamps `last`.
- `clone` is applied on the way *out*: `dclone` from `Storable` is returned only when the cached
  result is a reference. Without `clone`, callers receive the cached reference itself and mutating it
  corrupts the cache — `t/07_storable.t` and `t/08_storable.t` assert both halves of this contract.
- `Time::HiRes` is optional, imported in `BEGIN` to override `time`. When present, fractional
  timeouts work; otherwise timeouts are whole seconds. Anything touching timing must keep working
  under both — `t/06_time_hires.t` covers the first case and `t/13_no_time_hires.t` the second, by
  installing an `@INC` hook that makes `require Time::HiRes` fail.
- `FETCH` returns `undef` for unregistered keys silently (the warning was removed in 0.20 — see
  `Changes`); don't reintroduce it.
- A false `timeout` (`0`, `undef`, missing) becomes the default of 1 second — `|| 1`, not `// 1`,
  so there is no way to ask for "never cache".

### Two non-obvious invariants

- `sub DESTROY { return 1 }` — the explicit return value is not used by anything. A body of `{ }` or
  `{ return }` compiles to nothing `Devel::Cover` can instrument, so the subroutine is reported as
  uncovered even though Perl does call it. Don't "simplify" it back.
- `FIRSTKEY`/`NEXTKEY` returned cached *values* instead of key names until 0.22, which broke
  `keys`/`each` and made iterating an empty cache autovivify an entry under the empty-string key.
  They now return key names; `each` gets the value through `FETCH`, so iteration can trigger
  refreshes.
