local config = require("review.config")

local M = {}

local function float(opts)
  return Snacks.win(vim.tbl_deep_extend("force", {
    position = "float",
    border = "rounded",
    title_pos = "center",
    backdrop = false,
    enter = true,
    width = 0.55,
    height = 12,
    wo = { wrap = true, linebreak = true, number = false, relativenumber = false, signcolumn = "no" },
  }, opts))
end

--- Snacks' `ft` starts treesitter unconditionally, bypassing the markdown
--- disable in init.lua, and the pinned nvim-treesitter master's markdown
--- injection directives throw on nvim 0.12. Regex syntax sidesteps both.
local function markdown_bo(bo)
  return vim.tbl_extend("force", { buftype = "nofile", bufhidden = "wipe", syntax = "markdown" }, bo or {})
end

--- Compose a comment. `<Tab>` cycles the tag in the title so the whole flow is
--- one window and never leaves the keyboard.
function M.compose(opts, on_submit)
  local tags = config.tags
  local idx = 1
  for i, t in ipairs(tags) do
    if t == opts.tag then idx = i end
  end

  local function title()
    return (" %s · [%s]  <Tab> tag  <C-s> save  q cancel "):format(opts.where or "comment", tags[idx])
  end

  local win
  win = float({
    title = title(),
    bo = markdown_bo(),
    wo = { cursorline = true },
    text = opts.text or { "" },
    keys = {
      q = { "q", function(self) self:close() end, mode = "n" },
      tag = {
        "<Tab>",
        function(self)
          idx = idx % #tags + 1
          local cfg = vim.api.nvim_win_get_config(self.win)
          cfg.title = title()
          pcall(vim.api.nvim_win_set_config, self.win, cfg)
        end,
        mode = { "n", "i" },
      },
      submit = {
        "<C-s>",
        function(self)
          local body = vim.trim(table.concat(vim.api.nvim_buf_get_lines(self.buf, 0, -1, false), "\n"))
          local tag = tags[idx]
          vim.cmd.stopinsert()
          self:close()
          if body ~= "" then on_submit(body, tag) end
        end,
        mode = { "n", "i" },
      },
    },
  })
  vim.schedule(function() vim.cmd.startinsert() end)
  return win
end

local function thread_lines(c)
  local out = {}
  local head = ("%s[%s] %s:%s"):format(
    c.author == "claude" and "claude " or "",
    c.tag or "q",
    c.file or "?",
    c.line_start == c.line_end and tostring(c.line_start) or (c.line_start .. "-" .. c.line_end)
  )
  if c.side == "old" then head = head .. "  (old side @ " .. (c.rev or "base") .. ")" end
  if c.status == "resolved" then head = head .. "  ✓ resolved" end
  if c.status == "orphaned" then head = head .. "  ⚠ orphaned" end
  out[#out + 1] = "# " .. head
  out[#out + 1] = ""
  for _, l in ipairs(vim.split(c.body or "", "\n", { plain = true })) do
    out[#out + 1] = l
  end
  for _, r in ipairs(c.replies or {}) do
    out[#out + 1] = ""
    out[#out + 1] = ("**%s:**"):format(r.author or "?")
    for _, l in ipairs(vim.split(r.body or "", "\n", { plain = true })) do
      out[#out + 1] = "> " .. l
    end
  end
  return out
end

--- Read-only thread view. Actions are a table of single-key handlers.
function M.thread(c, actions)
  local win
  local keys = {
    q = { "q", function(self) self:close() end, mode = "n" },
    esc = { "<Esc>", function(self) self:close() end, mode = "n" },
  }
  for key, spec in pairs(actions or {}) do
    keys[spec.name] = {
      key,
      function(self)
        self:close()
        spec.fn()
      end,
      mode = "n",
    }
  end
  local hints = {}
  for key, spec in pairs(actions or {}) do
    hints[#hints + 1] = key .. " " .. spec.name
  end
  table.sort(hints)
  win = float({
    title = " thread ",
    footer = " " .. table.concat(hints, "  ") .. "  q close ",
    footer_pos = "center",
    height = math.min(20, #thread_lines(c) + 2),
    bo = markdown_bo({ modifiable = false }),
    text = thread_lines(c),
    keys = keys,
  })
  return win
end

--- Thread list. Uses Snacks.picker when available, quickfix otherwise.
function M.list(comments, on_pick)
  if #comments == 0 then
    require("review.util").notify("no comments in this review")
    return
  end

  local items = {}
  for _, c in ipairs(comments) do
    local mark = c.status == "resolved" and "✓" or (c.status == "orphaned" and "⚠" or "○")
    items[#items + 1] = {
      text = ("%s %s %s:%d%s %s"):format(mark, c.tag or "q", c.file or "?", c.line_start or 0,
        c.side == "old" and " (old)" or "", c.body or ""),
      comment = c,
      preview = { text = table.concat(thread_lines(c), "\n"), ft = "markdown" },
    }
  end

  local ok = pcall(function()
    Snacks.picker.pick({
      source = "review",
      title = "review threads",
      items = items,
      preview = "preview",
      format = function(item)
        local c = item.comment
        local mark = c.status == "resolved" and "✓" or (c.status == "orphaned" and "⚠" or "○")
        local hl = config.tag_hl[c.tag] or "ReviewTagQ"
        return {
          { mark .. " ", c.status == "resolved" and "ReviewResolved" or hl },
          { ("%-10s"):format(c.tag or "q"), hl },
          { ("%s:%d "):format(c.file or "?", c.line_start or 0), "SnacksPickerFile" },
          c.side == "old" and { "old ", "DiagnosticWarn" } or { "" },
          { vim.split(c.body or "", "\n")[1] or "", "SnacksPickerComment" },
        }
      end,
      confirm = function(picker, item)
        picker:close()
        if item and item.comment then on_pick(item.comment) end
      end,
    })
  end)

  if not ok then
    local qf = {}
    for _, item in ipairs(items) do
      local c = item.comment
      qf[#qf + 1] = {
        filename = vim.fs.joinpath(c.repo_root or vim.uv.cwd(), c.file or ""),
        lnum = c.line_start or 1,
        text = item.text,
      }
    end
    vim.fn.setqflist({}, " ", { title = "review threads", items = qf })
    vim.cmd.copen()
  end
end

return M
