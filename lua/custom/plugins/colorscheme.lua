-- Colorscheme. Light/dark is driven by the `theme` command (~/.local/bin/theme),
-- which keeps Ghostty, herdr, hunk and Neovim in step. See ~/.config/terminal-theme/mode.
local state_file = vim.fn.expand '~/.config/terminal-theme/mode'

--- Read the mode written by the `theme` command: 'dark', 'light' or 'auto'.
local function theme_mode()
  local f = io.open(state_file, 'r')
  if not f then
    return 'auto'
  end
  local mode = f:read 'l'
  f:close()
  mode = (mode or ''):gsub('%s', '')
  if mode == 'dark' or mode == 'light' or mode == 'auto' then
    return mode
  end
  return 'auto'
end

--- The background this session should be using right now.
local function desired_background()
  local mode = theme_mode()
  if mode == 'auto' then
    -- Ghostty owns light/dark in auto mode; Neovim already detects the terminal
    -- background over OSC 11, so whatever it worked out is authoritative.
    return vim.o.background
  end
  return mode
end

return {
  {
    'rebelot/kanagawa.nvim',
    priority = 1000, -- Make sure to load this before all the other start plugins.
    config = function()
      require('kanagawa').setup {
        theme = 'wave', -- Load "wave" theme when 'background' option is not set
        background = { -- map the value of 'background' option to a theme
          dark = 'wave',
          light = 'lotus',
        },
      }

      -- Re-apply the colorscheme for the current mode. kanagawa picks wave or
      -- lotus off vim.o.background at load time, so set background first.
      local function sync()
        local bg = desired_background()
        if vim.o.background ~= bg then
          vim.o.background = bg
        end
        vim.cmd.colorscheme 'kanagawa'
      end

      sync()

      -- Pick up a `theme` run without restarting: focusing this window resyncs.
      vim.api.nvim_create_autocmd('FocusGained', {
        desc = 'Resync colorscheme with the `theme` command',
        callback = sync,
      })

      vim.api.nvim_create_user_command('ThemeSync', sync, {
        desc = 'Resync the colorscheme with the `theme` command',
      })
    end,
  },
}
