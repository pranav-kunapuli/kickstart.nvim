-- Keep plugin/review.lua from auto-running: specs load what they need
-- explicitly, and the integration spec calls setup() itself.
vim.g.loaded_review = true

local lazy = vim.fn.expand("~/.local/share/nvim/lazy")
for _, p in ipairs({ "plenary.nvim", "diffview.nvim", "snacks.nvim" }) do
  vim.opt.runtimepath:append(lazy .. "/" .. p)
end
vim.opt.runtimepath:prepend(vim.fn.expand("~/.config/nvim"))

-- plenary spawns spec runners with --noplugin, so nothing in plugin/ is
-- sourced there. Pull in the two we actually need by hand.
vim.cmd("runtime! plugin/plenary.vim")
vim.cmd("runtime! plugin/diffview.lua")

vim.opt.swapfile = false
vim.o.autoread = true
