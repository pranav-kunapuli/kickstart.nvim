return {
  {
    -- You can easily change to a different colorscheme.
    -- Change the name of the colorscheme plugin below, and then
    -- change the command in the config to whatever the name of that colorscheme is.
    --
    -- If you want to see what colorschemes are already installed, you can use `:Telescope colorscheme`.
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

      -- Load the colorscheme here.
      vim.cmd.colorscheme 'kanagawa-wave'
    end,
  },
  -- {
  --   'f-person/auto-dark-mode.nvim',
  --   opts = {
  --     -- your configuration comes here
  --     -- or leave it empty to use the default settings
  --     -- refer to the configuration section below
  --   },
  -- },
}
