return {
  {
    'nvim-treesitter/nvim-treesitter',
    opts = function(_, opts)
      -- Configure embedded_template parser for EJS files
      local parser_config = require('nvim-treesitter.parsers').get_parser_configs()
      parser_config.embedded_template = {
        install_info = {
          url = 'https://github.com/tree-sitter/tree-sitter-embedded-template',
          files = { 'src/parser.c' },
          requires_generate_from_grammar = true,
        },
        filetype = 'embedded_template',
        used_by = { 'ejs' },
      }

      -- Set up filetype detection for .ejs files
      vim.api.nvim_create_autocmd({ 'BufRead', 'BufNewFile' }, {
        pattern = '*.ejs',
        callback = function()
          vim.bo.filetype = 'embedded_template'
        end,
      })
    end,
  },
}
