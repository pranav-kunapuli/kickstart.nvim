return {
  {
    'nvim-neo-tree/neo-tree.nvim',
    cmd = 'Neotree',
    branch = 'v3.x',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-tree/nvim-web-devicons', -- not strictly required, but recommended
      'MunifTanjim/nui.nvim',
      -- {"3rd/image.nvim", opts = {}}, -- Optional image support in preview window: See `# Preview Mode` for more information
    },
    keys = {
      {
        '<leader>e',
        function()
          require('neo-tree.command').execute { toggle = true, dir = vim.uv.cwd() }
        end,
        desc = '[E]xplorer NeoTree (Root Dir)',
      },
    },
    opts = {
      window = {
        mappings = {
          ['e'] = function()
            vim.api.nvim_exec('Neotree focus filesystem left', true)
          end,
          ['b'] = function()
            vim.api.nvim_exec('Neotree focus buffers left', true)
          end,
          ['g'] = function()
            vim.api.nvim_exec('Neotree focus git_status left', true)
          end,
        },
      },
    },
  },
}
