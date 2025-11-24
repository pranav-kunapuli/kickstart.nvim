return {
  {
    'kdheepak/lazygit.nvim',
    cmd = {
      'LazyGit',
      'LazyGitConfig',
      'LazyGitCurrentFile',
      'LazyGitFilter',
      'LazyGitFilterCurrentFile',
    },
    -- Optional for floating window border decoration
    dependencies = {
      'nvim-lua/plenary.nvim',
    },
    keys = {
      {
        '<leader>gg',
        '<cmd>LazyGit<cr>',
        desc = 'LazyGit',
      },
      {
        '<leader>gf',
        '<cmd>LazyGitCurrentFile<cr>',
        desc = 'LazyGit Current File',
      },
    },
  },
}
