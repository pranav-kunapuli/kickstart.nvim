local config = require("review.config")

local M = {}

M.ns = vim.api.nvim_create_namespace("review")
--- bufnr -> comment id -> extmark id. Extmarks track edits made inside nvim,
--- which the stored line numbers cannot.
M.marks = {}

local function decorate(c)
  if c.status == "resolved" then
    return config.opts.sign_resolved, "ReviewResolved"
  elseif c.status == "orphaned" then
    return config.opts.sign_orphan, "ReviewOrphan"
  end
  return config.opts.sign, config.tag_hl[c.tag] or "ReviewTagQ"
end

local function label(c)
  local parts = {}
  if c.author == "claude" then parts[#parts + 1] = "claude" end
  parts[#parts + 1] = "[" .. (c.tag or "q") .. "]"
  local n = #(c.replies or {})
  if n > 0 then parts[#parts + 1] = "·" .. n end
  if c.status == "resolved" then parts[#parts + 1] = "✓" end
  if c.status == "orphaned" then parts[#parts + 1] = "⚠ orphaned" end
  return "  " .. table.concat(parts, " ")
end

function M.paint(bufnr, comments)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)
  M.marks[bufnr] = {}
  local total = vim.api.nvim_buf_line_count(bufnr)
  for _, c in ipairs(comments) do
    local s = math.max(1, math.min(c.line_start or 1, total))
    local e = math.max(s, math.min(c.line_end or s, total))
    local sign, hl = decorate(c)
    local opts = {
      end_row = e - 1,
      sign_text = sign,
      sign_hl_group = hl,
      hl_mode = "combine",
      priority = 200,
    }
    if config.opts.virt_text then
      opts.virt_text = { { label(c), hl } }
      opts.virt_text_pos = "eol"
    end
    local ok, id = pcall(vim.api.nvim_buf_set_extmark, bufnr, M.ns, s - 1, 0, opts)
    if ok then M.marks[bufnr][c.id] = id end
  end
end

function M.clear(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)
  end
  M.marks[bufnr] = nil
end

--- Live position of a comment, preferring the extmark over the stored line.
function M.pos(bufnr, id)
  local ids = M.marks[bufnr]
  if not ids or not ids[id] then return nil end
  local ok, m = pcall(vim.api.nvim_buf_get_extmark_by_id, bufnr, M.ns, ids[id], { details = true })
  if not ok or not m or not m[1] then return nil end
  local start = m[1] + 1
  local finish = (m[3] and m[3].end_row and m[3].end_row + 1) or start
  return start, math.max(start, finish)
end

--- Pull extmark drift back into the store's line numbers before persisting.
function M.sync(bufnr, comments)
  local moved = false
  for _, c in ipairs(comments) do
    local s, e = M.pos(bufnr, c.id)
    if s and (c.line_start ~= s or c.line_end ~= e) then
      c.line_start, c.line_end = s, e
      moved = true
    end
  end
  return moved
end

return M
