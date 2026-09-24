local config = require("review.config")
local dv = require("review.dv")
local registry = require("review.registry")
local session = require("review.session")
local util = require("review.util")

local M = {}

local function visual_range()
  local a = vim.fn.getpos("v")[2]
  local b = vim.fn.getpos(".")[2]
  if a > b then a, b = b, a end
  return { a, b }
end

local function map(bufnr, mode, lhs, rhs, desc)
  vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = "review: " .. desc, silent = true })
end

--- Keymaps are buffer-local to diff buffers: review is a mode you are in, and
--- this keeps ]r and <leader>r out of the way everywhere else.
local function attach_keys(bufnr)
  if vim.b[bufnr].review_keys then return end
  vim.b[bufnr].review_keys = true

  map(bufnr, "n", "]r", function() session.jump(1, false) end, "next comment")
  map(bufnr, "n", "[r", function() session.jump(-1, false) end, "prev comment")
  map(bufnr, "n", "]R", function() session.jump(1, true) end, "next unresolved")
  map(bufnr, "n", "[R", function() session.jump(-1, true) end, "prev unresolved")

  map(bufnr, "n", "<leader>rc", function() session.add(nil) end, "comment")
  map(bufnr, "x", "<leader>rc", function()
    local range = visual_range()
    vim.cmd("normal! \27")
    session.add(range)
  end, "comment on selection")

  map(bufnr, "n", "<leader>rs", session.show, "show thread")
  map(bufnr, "n", "<leader>rr", session.toggle_resolved, "toggle resolved")
  map(bufnr, "n", "<leader>ra", session.reply, "reply")
  map(bufnr, "n", "<leader>rd", session.delete, "delete comment")
  map(bufnr, "n", "<leader>rl", session.list, "list threads")
  map(bufnr, "n", "<leader>ry", session.export, "export to clipboard")
  map(bufnr, "n", "<leader>rR", function()
    local s = session.get()
    if s then
      vim.cmd("silent! checktime")
      session.refresh(s)
      util.notify("refreshed")
    end
  end, "refresh")
  map(bufnr, "n", "<leader>rv", function()
    config.opts.virt_text = not config.opts.virt_text
    local s = session.get()
    if s then session.repaint(s) end
  end, "toggle inline labels")

  local ok, wk = pcall(require, "which-key")
  if ok then
    wk.add({ { "<leader>r", group = "[R]eview / [R]ename", buffer = bufnr } })
  end
end

local function command(name, fn, opts)
  vim.api.nvim_create_user_command(name, fn, opts or {})
end

function M.setup()
  config.setup_hl()

  local group = vim.api.nvim_create_augroup("Review", { clear = true })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "DiffviewViewOpened",
    callback = function()
      vim.schedule(function()
        local s = session.attach()
        if s then session.publish(s) end
      end)
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "DiffviewDiffBufWinEnter", "DiffviewViewEnter" },
    callback = function(ev)
      -- Diffview fires this with the diff buffer current, but only inside a
      -- win_call; by the scheduled tick focus is back on the file panel.
      local fired = ev.buf
      vim.schedule(function()
        local s = session.attach()
        if not s then return end
        local bufs = { fired }
        local v = dv.view()
        local layout = v and v.cur_entry and v.cur_entry.layout
        for _, side in ipairs({ "a", "b" }) do
          local f = layout and layout[side] and layout[side].file
          if f and f.bufnr then bufs[#bufs + 1] = f.bufnr end
        end
        for _, bufnr in ipairs(bufs) do
          if vim.api.nvim_buf_is_valid(bufnr) and dv.locate(bufnr) then
            attach_keys(bufnr)
            session.paint_buf(s, bufnr)
            session.check_live(s)
          end
        end
      end)
    end,
  })

  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = config.setup_hl })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function() session.detach_all() end,
  })

  command("Review", function()
    local s = session.attach()
    if not s then
      util.notify("open a diffview tab first (:DiffviewOpen <base>)", vim.log.levels.WARN)
      return
    end
    session.refresh(s)
    local open, resolved, orphaned = s.store:counts()
    util.notify(("%s @ %s\n%d open · %d resolved · %d orphaned\n%s")
      :format(s.branch, s.base or "?", open, resolved, orphaned, s.store.path))
  end)

  command("ReviewComment", function(a)
    if a.range == 2 then
      session.add({ a.line1, a.line2 })
    else
      session.add(nil)
    end
  end, { range = true })

  command("ReviewShow", session.show)
  command("ReviewResolve", session.toggle_resolved)
  command("ReviewReply", session.reply)
  command("ReviewDelete", session.delete)
  command("ReviewList", session.list)
  command("ReviewExport", session.export)

  command("ReviewRefresh", function()
    local s = session.get()
    if not s then return end
    vim.cmd("silent! checktime")
    local moved, orphaned = session.refresh(s)
    util.notify(("refreshed · %d re-anchored, %d orphaned"):format(moved, orphaned))
  end)

  command("ReviewDetach", function()
    local s = session.get()
    if s then
      session.detach(s.root)
      util.notify("detached")
    end
  end)

  command("ReviewSessions", function()
    local d = registry.read()
    if #d.sessions == 0 then
      util.notify("no live review sessions")
      return
    end
    local lines = {}
    for _, s in ipairs(d.sessions) do
      lines[#lines + 1] = ("%s  [%s]  %d open, %d resolved\n  %s")
        :format(s.repo_root, s.branch, s.open or 0, s.resolved or 0, s.store)
    end
    util.notify(table.concat(lines, "\n"))
  end)

  command("ReviewClear", function()
    local s = session.get()
    if not s then return end
    vim.ui.select({ "no", "yes" }, { prompt = "delete " .. s.store.path .. "?" }, function(choice)
      if choice ~= "yes" then return end
      vim.uv.fs_unlink(s.store.path)
      s.store.data.comments = {}
      s.snapshot = {}
      session.repaint(s)
      session.publish(s)
      util.notify("cleared")
    end)
  end)
end

return M
