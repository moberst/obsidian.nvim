# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Answering user questions

If the user asks about functionality in this plugin, you MUST ground your answers in the code of the repository.  For instance, if the user asks "How do I insert a link to a file?" you must find the relevant command in the documentation or in the codebase before answering.

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

## Local Customizations

This fork adds several features on top of upstream `obsidian-nvim/obsidian.nvim`. Local commits live on `main` rebased on top of `upstream/main`.

### Custom Commands

| Command | Module | Description |
|---------|--------|-------------|
| `:Obsidian rename_tag [OLD] [NEW]` | `commands/rename_tag.lua` | Rename a tag across the entire vault (inline `#tags` and frontmatter). Handles nested tags and skips code blocks. Prompts for confirmation before applying. |
| `:Obsidian insert_link_by_tag <TAG> [LABEL] [OFFSET]` | `commands/insert_link_by_tag.lua` | Insert a link to a single note matching a tag. Notes are sorted by mtime (newest first); `OFFSET` selects which one (0-indexed). Designed for keymap-driven workflows. |
| `:Obsidian insert_all_links_by_tag <TAG>` | `commands/insert_all_links_by_tag.lua` | Insert a markdown bullet list of links to **all** notes matching a tag at the cursor position, sorted by most recently modified. |

All three commands also have Lua API wrappers in `lua/obsidian/actions.lua`.

### Note Cache (`lua/obsidian/cache.lua`)

An in-memory cache for parsed notes and their code blocks, keyed by file path. Entries are invalidated when the file's mtime changes. Key API:
- `get(path_str, opts)` — lazy-load and cache a note
- `invalidate(path_str)` / `clear()` — manual invalidation
- `populate_async(dir, opts)` — eagerly scan a directory to warm the cache on startup

The cache is populated automatically during plugin setup.

### Tag Picker Enhancements (`lua/obsidian/picker/init.lua`)

Extra mappings added to the tag picker:
- `insert_link` — insert a wiki-link to the selected note (bound to `<C-]>` by default)
- `rename_tag` — trigger `:Obsidian rename_tag` on the selected tag

### Other Local Fixes

- Absolute paths are handled correctly for templates, daily notes, and notes subdirs
- Tag picker results are sorted by filename instead of raw ripgrep order

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
| `lua/obsidian/cache.lua` | In-memory note cache (local addition) — speeds up repeated tag searches |
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
