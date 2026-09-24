--- Re-find a comment's code after the agent has rewritten the file on disk.
--- Extmarks only survive edits made inside nvim, so the snippet is the anchor
--- of record across reloads.
local config = require("review.config")

local M = {}

function M.capture(bufnr, line_start, line_end)
  local lines = vim.api.nvim_buf_get_lines(bufnr, line_start - 1, line_end, false)
  return table.concat(lines, "\n")
end

local function exact_at(lines, at, snippet)
  if at < 1 or at + #snippet - 1 > #lines then return false end
  for i, sl in ipairs(snippet) do
    if lines[at + i - 1] ~= sl then return false end
  end
  return true
end

local function all_blank(snippet)
  for _, l in ipairs(snippet) do
    if vim.trim(l) ~= "" then return false end
  end
  return true
end

--- A first line is only worth loose-matching if it identifies a place. Lone
--- punctuation like `}` or `});` occurs everywhere, and rebinding to one would
--- silently point the comment at unrelated code.
local function distinctive(line)
  local t = vim.trim(line)
  return #t >= config.opts.loose_min_chars and t:find("%w") ~= nil
end

local function loose_at(lines, at, snippet)
  local l = lines[at]
  if not l then return false end
  return distinctive(snippet[1]) and vim.trim(l) == vim.trim(snippet[1])
end

--- @return integer|nil new_start, integer|nil new_end, string|nil how
--- how is "same" | "moved" | "fuzzy"; nil means the code is gone (orphan).
function M.relocate(lines, c)
  if c.snippet == nil then return nil end
  local snippet = vim.split(c.snippet, "\n", { plain = true })
  local n = #snippet
  if n == 0 then return nil end
  local start = c.line_start or 1

  if exact_at(lines, start, snippet) then
    return start, start + n - 1, "same"
  end

  -- A comment on blank lines has no content to search for. Keeping it where it
  -- sits would be a guess, so it orphans rather than pretending.
  if all_blank(snippet) then return nil end

  local radius = config.opts.search_radius
  for d = 1, radius do
    for _, at in ipairs({ start - d, start + d }) do
      if exact_at(lines, at, snippet) then return at, at + n - 1, "moved" end
    end
  end

  -- The agent may have rewritten the body but kept the opening line.
  for d = 0, radius do
    for _, at in ipairs({ start - d, start + d }) do
      if at >= 1 and at <= #lines and loose_at(lines, at, snippet) then
        return at, math.min(at + n - 1, #lines), "fuzzy"
      end
    end
  end

  return nil
end

return M
