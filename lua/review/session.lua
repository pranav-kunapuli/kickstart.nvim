local Store = require("review.store")
local anchor = require("review.anchor")
local config = require("review.config")
local dv = require("review.dv")
local export = require("review.export")
local registry = require("review.registry")
local render = require("review.render")
local ui = require("review.ui")
local util = require("review.util")

local M = {}

--- repo_root -> session. One session per worktree; several can be live at once.
M.sessions = {}
M.current = nil

--- Keep the store out of git without touching the team's shared .gitignore.
--- Uses the COMMON git dir so it covers every linked worktree at once.
local function ensure_excluded(root)
  local gitdir = util.git(root, { "rev-parse", "--git-common-dir" })
  if not gitdir then return end
  if not gitdir:match("^/") then gitdir = vim.fs.joinpath(root, gitdir) end
  local path = vim.fs.joinpath(gitdir, "info", "exclude")
  local content = util.read(path) or ""
  if content:find(vim.pesc(config.opts.dir) .. "/") then return end
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f = io.open(path, "a")
  if not f then return end
  if content ~= "" and not content:match("\n$") then f:write("\n") end
  f:write(config.opts.dir .. "/\n")
  f:close()
end

local function snapshot(store)
  local snap = {}
  for _, c in ipairs(store:comments()) do
    snap[c.id] = { status = c.status, replies = #(c.replies or {}), author = c.author }
  end
  return snap
end

local function describe_change(before, after)
  local resolved, new_replies, new_comments = 0, 0, 0
  for id, a in pairs(after) do
    local b = before[id]
    if not b then
      if a.author == "claude" then new_comments = new_comments + 1 end
    else
      if b.status ~= "resolved" and a.status == "resolved" then resolved = resolved + 1 end
      if a.replies > b.replies then new_replies = new_replies + a.replies - b.replies end
    end
  end
  return resolved, new_replies, new_comments
end

---------------------------------------------------------------------------
-- lifecycle
---------------------------------------------------------------------------

function M.attach()
  local root = dv.repo_root()
  if not root then return nil end
  if M.sessions[root] then
    M.current = M.sessions[root]
    return M.current
  end

  local branch = util.git(root, { "rev-parse", "--abbrev-ref", "HEAD" }) or "detached"
  local base
  local view = dv.view()
  if view then
    local ok, left = pcall(function() return tostring(view.left) end)
    if ok then base = left end
  end

  local s = {
    root = root,
    branch = branch,
    base = base,
    store = Store.new(root, branch, base),
    bufs = {},
    live = nil, -- unknown until a diff buffer is laid out
  }
  s.snapshot = snapshot(s.store)

  ensure_excluded(root)
  s.store:watch(function() M.on_store_changed(s) end)

  M.sessions[root] = s
  M.current = s

  if s.store:exists() then
    M.refresh(s)
    local open, resolved = s.store:counts()
    util.notify(("%s · %d open, %d resolved"):format(branch, open, resolved))
  end

  return s
end

--- Liveness is only knowable once diffview has laid a file out, which happens
--- after DiffviewViewOpened. Called from the buffer-enter path instead.
function M.check_live(s)
  if s.live ~= nil then return s.live end
  local v = dv.view()
  if not v or not v.cur_entry then return nil end
  s.live = dv.is_live()
  if not s.live and not s.warned_frozen then
    s.warned_frozen = true
    util.notify(
      "frozen review: both sides are git blobs, so re-anchoring and reload are off.\n"
        .. "Use :DiffviewOpen <base> for a live review.",
      vim.log.levels.WARN
    )
  end
  M.publish(s)
  return s.live
end

function M.detach(root)
  local s = M.sessions[root]
  if not s then return end
  s.store:stop()
  for bufnr in pairs(s.bufs) do
    render.clear(bufnr)
  end
  registry.remove(root)
  M.sessions[root] = nil
  if M.current == s then M.current = nil end
end

function M.detach_all()
  for _, root in ipairs(vim.tbl_keys(M.sessions)) do
    M.detach(root)
  end
end

--- The session for the buffer under the cursor, if any.
function M.get()
  local root = dv.repo_root()
  if root and M.sessions[root] then
    M.current = M.sessions[root]
    return M.sessions[root]
  end
  return M.current
end

function M.publish(s)
  local open, resolved, orphaned = s.store:counts()
  registry.publish({
    repo_root = s.root,
    branch = s.branch,
    base = s.base,
    store = s.store.path,
    live = s.live == true,
    open = open,
    resolved = resolved,
    orphaned = orphaned,
  })
end

---------------------------------------------------------------------------
-- painting and anchoring
---------------------------------------------------------------------------

local function for_buf(s, bufnr)
  local loc = dv.locate(bufnr)
  if not loc then return nil, nil end
  local out = {}
  for _, c in ipairs(s.store:comments()) do
    -- A frozen buffer is one commit's copy of the file; comments made against
    -- another range's commit must not paint here.
    if c.file == loc.path and (c.side or "new") == loc.side
      and (not loc.frozen or c.rev == loc.rev) then
      out[#out + 1] = c
    end
  end
  return out, loc
end

function M.paint_buf(s, bufnr)
  local comments, loc = for_buf(s, bufnr)
  if not comments then return end
  s.bufs[bufnr] = loc
  render.paint(bufnr, comments)
end

function M.repaint(s)
  for bufnr in pairs(s.bufs) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      M.paint_buf(s, bufnr)
    else
      s.bufs[bufnr] = nil
    end
  end
end

--- Re-find every live comment's code after an external rewrite.
--- @return integer moved, integer orphaned
function M.reanchor(s)
  local moved, orphaned = 0, 0
  local updates = {}

  for bufnr, loc in pairs(s.bufs) do
    if vim.api.nvim_buf_is_valid(bufnr) and loc.side == "new" and not loc.frozen then
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      for _, c in ipairs(s.store:comments()) do
        if c.file == loc.path and (c.side or "new") == "new" then
          local ns, ne, how = anchor.relocate(lines, c)
          if not ns then
            if c.status ~= "orphaned" and c.status ~= "resolved" then
              updates[c.id] = { status = "orphaned" }
              orphaned = orphaned + 1
            end
          else
            local changed = (ns ~= c.line_start or ne ~= c.line_end)
            local unorphan = c.status == "orphaned"
            if changed or unorphan then
              updates[c.id] = {
                line_start = ns,
                line_end = ne,
                status = unorphan and "open" or nil,
              }
              if how ~= "same" then moved = moved + 1 end
            end
          end
        end
      end
    end
  end

  if next(updates) then
    s.store:mutate(function(d)
      for _, c in ipairs(d.comments) do
        local u = updates[c.id]
        if u then
          for k, v in pairs(u) do c[k] = v end
        end
      end
    end)
  end

  return moved, orphaned
end

function M.refresh(s)
  s.store:reload()
  M.repaint(s)
  local moved, orphaned = M.reanchor(s)
  if moved > 0 or orphaned > 0 then M.repaint(s) end
  M.publish(s)
  return moved, orphaned
end

--- The agent wrote the store. Pull in its file edits too, then re-anchor.
function M.on_store_changed(s)
  local before = s.snapshot
  s.store:reload()
  s.snapshot = snapshot(s.store)
  local resolved, replies, new_comments = describe_change(before, s.snapshot)

  vim.cmd("silent! checktime")
  if dv.in_diffview() then pcall(vim.cmd, "DiffviewRefresh") end

  vim.defer_fn(function()
    local moved, orphaned = M.refresh(s)
    local parts = {}
    if resolved > 0 then parts[#parts + 1] = ("✓ %d resolved"):format(resolved) end
    if replies > 0 then parts[#parts + 1] = ("%d new %s"):format(replies, replies == 1 and "reply" or "replies") end
    if new_comments > 0 then parts[#parts + 1] = ("○ %d new from claude"):format(new_comments) end
    if moved > 0 then parts[#parts + 1] = ("%d re-anchored"):format(moved) end
    if orphaned > 0 then parts[#parts + 1] = ("⚠ %d orphaned"):format(orphaned) end
    if #parts > 0 then util.notify(table.concat(parts, ", ")) end
  end, 120)
end

---------------------------------------------------------------------------
-- comment operations
---------------------------------------------------------------------------

local function sync_lines(s)
  for bufnr in pairs(s.bufs) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      local comments = for_buf(s, bufnr)
      if comments and render.sync(bufnr, comments) then
        local by_id = {}
        for _, c in ipairs(comments) do by_id[c.id] = c end
        s.store:mutate(function(d)
          for _, c in ipairs(d.comments) do
            local live = by_id[c.id]
            if live then
              c.line_start, c.line_end = live.line_start, live.line_end
            end
          end
        end)
      end
    end
  end
end

function M.add(range)
  local s = M.attach()
  if not s then
    util.notify("not in a diffview tab", vim.log.levels.WARN)
    return
  end
  local bufnr = vim.api.nvim_get_current_buf()
  local loc = dv.locate(bufnr)
  if not loc then
    util.notify("cursor is not in a diff buffer", vim.log.levels.WARN)
    return
  end

  local line_start, line_end
  if range then
    line_start, line_end = range[1], range[2]
  else
    line_start = vim.api.nvim_win_get_cursor(0)[1]
    line_end = line_start
  end

  local where = ("%s:%s%s"):format(
    loc.path,
    line_start == line_end and tostring(line_start) or (line_start .. "-" .. line_end),
    loc.side == "old" and " (old)" or ""
  )

  ui.compose({ where = where, tag = config.tags[1] }, function(body, tag)
    s.store:add({
      file = loc.path,
      old_file = loc.old_path,
      side = loc.side,
      rev = loc.rev,
      line_start = line_start,
      line_end = line_end,
      snippet = anchor.capture(bufnr, line_start, line_end),
      tag = tag,
      body = body,
      author = "human",
      status = "open",
    })
    s.snapshot = snapshot(s.store)
    M.paint_buf(s, bufnr)
    M.publish(s)
  end)
end

function M.at_cursor(s)
  local bufnr = vim.api.nvim_get_current_buf()
  local comments = for_buf(s, bufnr)
  if not comments then return nil end
  local line = vim.api.nvim_win_get_cursor(0)[1]
  for _, c in ipairs(comments) do
    local ls, le = render.pos(bufnr, c.id)
    ls, le = ls or c.line_start, le or c.line_end
    if line >= (ls or 0) and line <= (le or 0) then return c end
  end
  return nil
end

function M.toggle_resolved()
  local s = M.get()
  if not s then return end
  local c = M.at_cursor(s)
  if not c then
    util.notify("no comment under the cursor")
    return
  end
  local nextstatus = c.status == "resolved" and "open" or "resolved"
  s.store:update(c.id, function(x) x.status = nextstatus end)
  s.snapshot = snapshot(s.store)
  M.repaint(s)
  M.publish(s)
  util.notify(nextstatus == "resolved" and "resolved" or "reopened")
end

function M.reply()
  local s = M.get()
  if not s then return end
  local c = M.at_cursor(s)
  if not c then
    util.notify("no comment under the cursor")
    return
  end
  ui.compose({ where = "reply to [" .. (c.tag or "q") .. "]", tag = c.tag }, function(body)
    s.store:update(c.id, function(x)
      x.replies = x.replies or {}
      table.insert(x.replies, { author = "human", body = body, at = util.now() })
    end)
    s.snapshot = snapshot(s.store)
    M.repaint(s)
  end)
end

function M.delete()
  local s = M.get()
  if not s then return end
  local c = M.at_cursor(s)
  if not c then
    util.notify("no comment under the cursor")
    return
  end
  s.store:delete(c.id)
  s.snapshot = snapshot(s.store)
  M.repaint(s)
  M.publish(s)
  util.notify("deleted")
end

function M.show()
  local s = M.get()
  if not s then return end
  local c = M.at_cursor(s)
  if not c then
    util.notify("no comment under the cursor")
    return
  end
  ui.thread(c, {
    r = { name = "resolve", fn = M.toggle_resolved },
    a = { name = "reply", fn = M.reply },
    d = { name = "delete", fn = M.delete },
  })
end

function M.list()
  local s = M.get()
  if not s then return end
  s.store:reload()
  local comments = vim.deepcopy(s.store:comments())
  for _, c in ipairs(comments) do c.repo_root = s.root end
  ui.list(comments, function(c)
    M.goto_comment(s, c)
  end)
end

function M.goto_comment(s, c)
  for bufnr, loc in pairs(s.bufs) do
    if loc.path == c.file and loc.side == (c.side or "new") and vim.api.nvim_buf_is_valid(bufnr)
      and (not loc.frozen or loc.rev == c.rev) then
      local win = vim.fn.bufwinid(bufnr)
      if win ~= -1 then
        vim.api.nvim_set_current_win(win)
        pcall(vim.api.nvim_win_set_cursor, win, { c.line_start or 1, 0 })
        vim.cmd("normal! zz")
        return
      end
    end
  end
  util.notify(("%s is not open in this tab — select it in the file panel"):format(c.file))
end

---------------------------------------------------------------------------
-- navigation
---------------------------------------------------------------------------

function M.jump(dir, unresolved_only)
  local s = M.get()
  if not s then return end
  local bufnr = vim.api.nvim_get_current_buf()
  local comments = for_buf(s, bufnr)
  if not comments or #comments == 0 then
    util.notify("no comments in this file")
    return
  end

  local lines = {}
  for _, c in ipairs(comments) do
    if not unresolved_only or c.status ~= "resolved" then
      local ls = render.pos(bufnr, c.id) or c.line_start
      if ls then lines[#lines + 1] = ls end
    end
  end
  if #lines == 0 then
    util.notify(unresolved_only and "no unresolved comments in this file" or "no comments in this file")
    return
  end
  table.sort(lines)

  local cur = vim.api.nvim_win_get_cursor(0)[1]
  local target
  if dir > 0 then
    for _, l in ipairs(lines) do
      if l > cur then target = l break end
    end
    target = target or lines[1]
  else
    for i = #lines, 1, -1 do
      if lines[i] < cur then target = lines[i] break end
    end
    target = target or lines[#lines]
  end
  vim.api.nvim_win_set_cursor(0, { target, 0 })
  vim.cmd("normal! zz")
end

---------------------------------------------------------------------------
-- export
---------------------------------------------------------------------------

function M.export()
  local s = M.get()
  if not s then
    util.notify("no active review", vim.log.levels.WARN)
    return
  end
  sync_lines(s)
  s.store:reload()
  local text = export.to_clipboard(s.store)
  if text then
    local open = select(1, s.store:counts())
    util.notify(("copied %d open %s to +"):format(open, open == 1 and "comment" or "comments"))
  end
end

return M
