# AGENTS.md

## Project

Single-file Neovim Lua micro-library (`lua/u.lua`) for range-based text operations, positions, operator-pending mappings, and text objects. Not a plugin — meant to be vendored by other plugins.

## Commands

All tasks use `mise`:

- `mise run fmt` — format (stylua)
- `mise run fmt:check` — check formatting
- `mise run lint` — type-check with `emmylua_check` (ignores `.prefix/`); warnings are errors
- `mise run test` — run busted against Neovim 0.12.1 (includes `test:prepare`)
- `mise run test:all` — test against 0.11.5, 0.12.1, and nightly
- `mise run test:coverage` — test with luacov (only covers `lua/u$`)
- `mise run ci` — `fmt:check` → `lint` → `test:all`

Run a single spec file: `busted spec/u_spec.lua` (after `mise run test:prepare`).

## Architecture

- **`lua/u.lua`** — the entire library: `Pos`, `Range`, `opkeymap`, `define_txtobj`, `ucmd`, `repeat_`
- **`spec/u_spec.lua`** — all tests in one file
- **`library/`** — type stubs for busted/luv (stylua-ignored, used by emmylua)
- **`.prefix/`** — neovim version installs managed by `nvimv` (git-ignored, emmylua-ignored)
- **`examples/`** — usage examples (surround, splitjoin, text-objects, matcher)

## Conventions

- **1-based indexing** everywhere (v2+). `Pos.from00()` / `Range.from00()` convert from 0-based Neovim API values.
- **Lint is a contract**: `mise run lint` fails on any warning. Do not add `@diagnostic` disables to `lua/` or `examples/`; fix the type or narrow the value instead.
- **`Range.stop` is nil only for an empty range.** Methods that require a stop narrow once with `assert(self.stop, EMPTY_RANGE)` after their empty check; methods where a nil stop is legal use `self.stop or self.start`.
- Stylua: LuaJIT syntax, single quotes, no call parens, 2-space indent, sort requires, 100 col width
- Tests run inside Neovim via busted's `lua = "nvim -u NONE -i NONE -l"` (set in `.busted`)
- `test:prepare` installs busted rocks via `luarocks test --prepare` and manages nightly Neovim via `nvimv`
