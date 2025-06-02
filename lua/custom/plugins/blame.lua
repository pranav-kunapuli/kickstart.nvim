return {
  {
    'FabijanZulj/blame.nvim',
    lazy = false,
    config = function()
      require('blame').setup {}
    end,
    keys = {
      {
        '<leader>b',
        ':BlameToggle<CR>',
        desc = '[B]lame',
      },
    },
  },
}
