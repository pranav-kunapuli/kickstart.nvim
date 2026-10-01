local config = require("review.config")

local M = {}

local util = require("review.util")

--- Rows a rounded border adds around a float.
local BORDER = 2

--- Row of a buffer line inside its window, 0-indexed; nil when off screen.
local function win_row(win, lnum)
  local pos = vim.fn.screenpos(win, lnum, 1)
  if pos.row == 0 then return nil end
  return pos.row - vim.fn.win_screenpos(win)[1]
end

--- Float pinned to the commented lines, inside their pane, and following the
--- text if the pane scrolls. It opens below the range when there is room, above
--- it when there is room there instead, and otherwise scrolls the range toward
--- the top of the pane to make room below.
local function anchored(anchor, height)
  local win = anchor.win
  local outer = height + BORDER
  local win_height = vim.api.nvim_win_get_height(win)
  local text_offset = vim.fn.getwininfo(win)[1].textoff
  local base = {
    relative = "win",
    win = win,
    width = vim.api.nvim_win_get_width(win) - text_offset - BORDER,
    height = height,
    col = 0,
  }

  local function below()
    local row = win_row(win, anchor.line_end)
    if row and win_height - row - 1 >= outer then
      return vim.tbl_extend("force", base, { bufpos = { anchor.line_end - 1, 0 }, row = 1 })
    end
  end
  local function above()
    local row = win_row(win, anchor.line_start)
    if row and row >= outer then
      return vim.tbl_extend("force", base, { bufpos = { anchor.line_start - 1, 0 }, row = 0, anchor = "SW" })
    end
  end

  local placed = below() or above()
  if placed then return placed end

  vim.api.nvim_win_call(win, function()
    local cursor = vim.api.nvim_win_get_cursor(win)
    local span = anchor.line_end - anchor.line_start + 1
    local context = math.min(2, math.max(0, win_height - outer - span))
    vim.api.nvim_win_set_cursor(win, { anchor.line_start, 0 })
    vim.fn.winrestview({ topline = math.max(1, anchor.line_start - context) })
    vim.api.nvim_win_set_cursor(win, cursor)
  end)
  -- A range taller than the pane leaves room for gets its tail covered.
  return below() or vim.tbl_extend("force", base, { row = win_height - outer, col = text_offset })
end

--- Window geometry. `anchor` is the commented range, `{ win, line_start,
--- line_end }`; without a live pane to anchor to, the window is centered.
local function placement(anchor, height)
  if anchor and vim.api.nvim_win_is_valid(anchor.win) then
    return anchored(anchor, height)
  end
  return { height = height }
end

local function float(opts, anchor)
  local height = opts.height or 12
  opts.height = nil
  return Snacks.win(vim.tbl_deep_extend("force", {
    position = "float",
    border = "rounded",
    title_pos = "center",
    backdrop = false,
    enter = true,
    width = 0.55,
    wo = { wrap = true, linebreak = true, number = false, relativenumber = false, signcolumn = "no" },
  }, placement(anchor, height), opts))
end

--- Hide the draft so the code behind it is readable, and map the same key in
--- the diff buffer to bring it back.
local function peek(win, anchor)
  local key = config.opts.peek_key
  local src = anchor and anchor.win
  if not (src and vim.api.nvim_win_is_valid(src)) then
    src = vim.fn.win_getid(vim.fn.winnr("#"))
  end
  vim.cmd.stopinsert()
  win:hide()
  if not vim.api.nvim_win_is_valid(src) then return end
  vim.api.nvim_set_current_win(src)
  local buf = vim.api.nvim_win_get_buf(src)
  vim.keymap.set("n", key, function()
    pcall(vim.keymap.del, "n", key, { buffer = buf })
    if not win:buf_valid() then return end
    win:show()
    win:focus()
    vim.cmd.startinsert({ bang = true })
  end, { buffer = buf, desc = "review: back to draft" })
  util.notify(("draft hidden · %s to return"):format(key))
end

local function scratch_bo(bo)
  return vim.tbl_extend("force", { buftype = "nofile", bufhidden = "wipe" }, bo or {})
end

--- Compose a comment. `<Tab>` cycles the tag in the title so the whole flow is
--- one window and never leaves the keyboard.
function M.compose(opts, on_submit, anchor)
  local tags = config.tags
  local idx = 1
  for i, t in ipairs(tags) do
    if t == opts.tag then idx = i end
  end

  local function title()
    return (" %s · [%s]  <Tab> tag  <C-s> save  %s peek  q cancel ")
      :format(opts.where or "comment", tags[idx], config.opts.peek_key)
  end

  local win
  win = float({
    title = title(),
    height = 10,
    ft = "markdown",
    -- hide rather than wipe, so peeking keeps the draft
    bo = scratch_bo({ bufhidden = "hide" }),
    wo = { cursorline = true },
    text = opts.text or { "" },
    keys = {
      q = { "q", function(self) self:close() end, mode = "n" },
      tag = {
        "<Tab>",
        function(self)
          idx = idx % #tags + 1
          self:set_title(title())
        end,
        mode = { "n", "i" },
      },
      peek = { config.opts.peek_key, function(self) peek(self, anchor) end, mode = { "n", "i" } },
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
  }, anchor)
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
function M.thread(c, actions, anchor)
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
    ft = "markdown",
    bo = scratch_bo({ modifiable = false }),
    text = thread_lines(c),
    keys = keys,
  }, anchor)
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
