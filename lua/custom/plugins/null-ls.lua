return {
  {
    'nvimtools/none-ls.nvim',
    ft = { 'python' },
    opts = function()
      return require 'custom.config.null-ls-config'
    end,
  },
}
