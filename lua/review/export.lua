local M = {}

local function loc(c)
  local range = c.line_start == c.line_end and tostring(c.line_start)
    or ("%d-%d"):format(c.line_start or 0, c.line_end or 0)
  if c.side == "old" then
    return ("old L%s @ %s"):format(range, c.rev or "base")
  end
  return "L" .. range
end

--- Markdown for the clipboard: the comments inline so you can eyeball what
--- you're sending, plus a pointer to the file the agent writes back to.
function M.format(store)
  local by_file, order = {}, {}
  for _, c in ipairs(store:comments()) do
    if c.status ~= "resolved" then
      local f = c.file or "?"
      if not by_file[f] then
        by_file[f] = {}
        order[#order + 1] = f
      end
      table.insert(by_file[f], c)
    end
  end
  table.sort(order)

  if #order == 0 then return nil end

  local rel = vim.fs.joinpath(require("review.config").opts.dir, vim.fs.basename(store.path))
  local out = {
    ("Address the open review comments in `%s`."):format(rel),
    "",
    "For each one you handle: set `status` to `resolved` and append a reply saying what you did.",
    "Do not edit the `body`, `tag`, `line_start`, `line_end`, or `snippet` of a comment authored by `human`.",
    "If you disagree or need a decision, reply and leave it open, or add your own comment with `author` set to `claude`.",
    "",
  }

  for _, f in ipairs(order) do
    out[#out + 1] = "## " .. f
    for _, c in ipairs(by_file[f]) do
      local first = true
      for _, line in ipairs(vim.split(c.body or "", "\n", { plain = true })) do
        if first then
          out[#out + 1] = ("- %s [%s] (`%s`) %s"):format(loc(c), c.tag or "q", c.id, line)
          first = false
        else
          out[#out + 1] = "  " .. line
        end
      end
      for _, r in ipairs(c.replies or {}) do
        out[#out + 1] = ("  - %s: %s"):format(r.author or "?", (r.body or ""):gsub("\n", " "))
      end
    end
    out[#out + 1] = ""
  end

  return table.concat(out, "\n")
end

function M.to_clipboard(store)
  local text = M.format(store)
  if not text then
    require("review.util").notify("no open comments to export")
    return nil
  end
  vim.fn.setreg("+", text)
  vim.fn.setreg('"', text)
  return text
end

return M
