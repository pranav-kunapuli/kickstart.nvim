local null_ls = require 'null-ls'

return {
  sources = {
    null_ls.builtins.diagnostics.mypy.with {
      -- Use poetry run to ensure mypy runs in the correct virtualenv context
      command = 'poetry',
      args = { 'run', 'mypy' },
      cwd = function(params)
        return require('null-ls.utils').root_pattern 'pyproject.toml'(params.bufname)
      end,
    },
  },
}
