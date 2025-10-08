# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Neovim configuration based on kickstart.nvim with custom plugins and personal customizations. The configuration uses lazy.nvim as the plugin manager and is structured as a modular setup with custom plugins in `lua/custom/plugins/`.

## Architecture

### Entry Point
- `init.lua`: Main configuration file containing core settings, keymaps, autocommands, and base plugin setup
  - Leader key: `<space>`
  - Enables relative line numbers and Nerd Font support
  - Custom keymaps: `;` and `:` are swapped, `j`/`k` move by display lines

### Plugin Structure
- **Base plugins** (in `init.lua`): vim-sleuth, gitsigns, which-key, telescope, LSP (lspconfig, mason), conform (formatting), nvim-cmp (completion), todo-comments, treesitter
- **Custom plugins** (in `lua/custom/plugins/*.lua`): Each file returns a plugin spec for lazy.nvim
  - Custom plugins include: abolish, avante, blame, claude-code, colorscheme, grug-far, mini, neo-tree, snacks, supermaven, trouble

### LSP Configuration
- Language servers configured: `lua_ls`, `ruff`, `basedpyright`, `mypy`, `cucumber_language_server`
- `.feature` files are set to use cucumber filetype
- Formatters: `stylua` (Lua), `ruff_fix`/`ruff_format`/`ruff_organize_imports` (Python), `prettierd`/`prettier` (JavaScript)
- Format on save is enabled (with LSP fallback, except for C/C++)

### Key Bindings
- `<leader>e`: Toggle neo-tree file explorer
- `<leader>f`: Format buffer
- Telescope bindings under `<leader>s` prefix (search files, grep, diagnostics, etc.)
- LSP bindings: `gd` (goto definition), `gr` (references), `<leader>ca` (code action), `<leader>rn` (rename)

## Development Commands

### Plugin Management
```bash
# Launch Neovim and manage plugins
nvim
:Lazy          # Open lazy.nvim plugin manager
:Lazy update   # Update all plugins
:Lazy sync     # Sync plugins (install missing, update existing, remove unused)
```

### LSP and Tools
```bash
:Mason         # Open Mason for managing LSP servers, formatters, linters
:LspInfo       # Show LSP client information for current buffer
:ConformInfo   # Show conform formatting information
```

### Health Checks
```bash
:checkhealth   # Run all health checks
```

### Testing Configuration
```bash
# Start Neovim from command line
nvim

# Test keybindings
# - Press <space> to see which-key menu
# - Use :Telescope keymaps to search all keymaps
```

## Important Notes

- Avante plugin is configured to use Claude (model: `claude-3-5-sonnet-20241022`) with agentic mode
- Telescope is configured to search hidden files but respects `.gitignore`
- The configuration extends kickstart.nvim, so refer to comments in `init.lua` for detailed explanations of each section
- Custom plugins are auto-imported via `{ import = 'custom.plugins' }` in the lazy.nvim setup
