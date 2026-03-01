# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

obsidian.nvim is a community-maintained Neovim plugin (Lua) for working with Obsidian vaults. It provides completion, navigation, templates, daily notes, and an embedded LSP — all without leaving Neovim. Requires Neovim 0.10.0+.

## Development Commands

```bash
make chores          # Run all checks (style, lint, types, test) — PRs must pass this
make style           # Check formatting with StyLua
make lint            # Lint with selene + typos
make types           # Type check with lua-language-server
make test            # Run tests with mini.test (auto-downloads deps)
make user-docs       # Generate vimdoc from README.md (CI does this automatically)
make api-docs        # Generate API docs from source (CI does this automatically)
```

The test command runs: `nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()"`

Tests use [mini.test](https://github.com/echasnovski/mini.nvim/blob/main/readmes/mini-test.md) with child Neovim processes for isolation. Test files are in `tests/` and use helpers from `tests/helpers.lua` (e.g., `h.child_vault()` for setting up isolated vault environments).

## Architecture

### Global State

The plugin uses a global `Obsidian` table (not module-level state) created during `obsidian.setup()`. This holds the current workspace, config options, picker instance, and all workspaces. The `obsidian.Client` class exists for backward compatibility and wraps the global state — it is deprecated and will be removed in 4.0.0.

### Entry Point and Command System

`plugin/obsidian.lua` registers a single `:Obsidian` user command. Subcommands are dispatched through `lua/obsidian/commands/init.lua`:

- `commands.register(name, config)` registers a command with a `CommandConfig` (func, nargs, range, note_action, complete)
- If no `func` is provided, the module `obsidian.commands.<name>` is auto-loaded
- Commands are context-filtered: visual mode availability, whether cursor is in a note, and whether features (templates, daily_notes) are enabled

Individual command implementations live in `lua/obsidian/commands/<name>.lua`.

### Key Modules

| Module | Purpose |
|--------|---------|
| `lua/obsidian/init.lua` | Plugin setup, module re-exports, global state creation |
| `lua/obsidian/workspace.lua` | Workspace detection (via `.obsidian/` folder) and per-workspace config overrides |
| `lua/obsidian/note.lua` | Note representation — metadata, frontmatter, aliases, tags, creation |
| `lua/obsidian/config/` | Config normalization (`init.lua`) and defaults (`default.lua`) |
| `lua/obsidian/picker/` | Abstraction over picker backends: telescope, fzf-lua, mini.pick, snacks, default |
| `lua/obsidian/completion/` | Completion sources (refs, tags) with adapters for nvim-cmp and blink.cmp |
| `lua/obsidian/search/` | Search patterns and ripgrep command building |
| `lua/obsidian/lsp/` | Built-in LSP client for rename, references, hover |
| `lua/obsidian/templates.lua` | `{{variable}}` substitution in templates |
| `lua/obsidian/daily/` | Daily note path generation and management |
| `lua/obsidian/frontmatter/` | YAML frontmatter parsing and generation |
| `lua/obsidian/api.lua` | Public API functions |

### Conventions

- Type annotations use LuaLS `---@class`, `---@field`, `---@param`, `---@return` throughout — contributions should include them
- Picker backends implement a common interface defined in `lua/obsidian/picker/init.lua`
- Documentation changes go in `README.md` only (vimdoc in `doc/` is auto-generated)
- CHANGELOG.md entries go under the "Unreleased" section using Keep a Changelog format
