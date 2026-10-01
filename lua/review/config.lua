local M = {}

M.tags = { "fix", "suggestion", "nit", "q", "discussion", "love" }

M.tag_hl = {
  fix = "ReviewTagFix",
  suggestion = "ReviewTagSuggestion",
  nit = "ReviewTagNit",
  q = "ReviewTagQ",
  discussion = "ReviewTagDiscussion",
  love = "ReviewTagLove",
}

M.opts = {
  dir = ".review",
  sign = "▌",
  sign_resolved = "▏",
  sign_orphan = "▓",
  search_radius = 400,
  loose_min_chars = 4,
  virt_text = true,
  --- Hides the comment window to look at the code behind it; press again
  --- from the diff to bring the draft back.
  peek_key = "<C-p>",
}

function M.setup_hl()
  local function set(name, def)
    vim.api.nvim_set_hl(0, name, vim.tbl_extend("keep", def, { default = true }))
  end
  set("ReviewTagFix", { link = "DiagnosticError" })
  set("ReviewTagSuggestion", { link = "DiagnosticWarn" })
  set("ReviewTagNit", { link = "DiagnosticHint" })
  set("ReviewTagQ", { link = "DiagnosticInfo" })
  set("ReviewTagDiscussion", { link = "DiagnosticInfo" })
  set("ReviewTagLove", { link = "DiagnosticOk" })
  set("ReviewResolved", { link = "Comment" })
  set("ReviewOrphan", { link = "DiagnosticWarn" })
end

return M
