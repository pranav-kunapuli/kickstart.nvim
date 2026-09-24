--- The JSON file both nvim and the agent read and write.
---
--- Concurrency is handled by ownership, not locking: the human owns `body`,
--- `tag`, `line_*` and `snippet`; the agent owns `status` and `replies` and may
--- append comments with author "claude". Every write re-reads from disk first,
--- so the two sides cannot clobber each other's fields.
local util = require("review.util")
local config = require("review.config")

local Store = {}
Store.__index = Store

local function slug(branch)
  return (branch:gsub("[/\\:%s]", "__"))
end

function Store.new(repo_root, branch, base)
  local self = setmetatable({}, Store)
  self.repo_root = repo_root
  self.branch = branch
  self.base = base
  self.dir = vim.fs.joinpath(repo_root, config.opts.dir)
  self.path = vim.fs.joinpath(self.dir, slug(branch) .. ".json")
  self.writing = false
  self.data = self:read() or {
    version = 1,
    repo_root = repo_root,
    branch = branch,
    base = base,
    comments = {},
  }
  return self
end

function Store:read()
  local raw = util.read(self.path)
  if not raw or raw == "" then return nil end
  local ok, d = pcall(vim.json.decode, raw)
  if not ok or type(d) ~= "table" then
    util.notify("store is not valid JSON: " .. self.path, vim.log.levels.ERROR)
    return nil
  end
  d.comments = d.comments or {}
  return d
end

function Store:reload()
  local fresh = self:read()
  if fresh then self.data = fresh end
  return self.data
end

function Store:comments()
  return self.data.comments or {}
end

function Store:get(id)
  for _, c in ipairs(self:comments()) do
    if c.id == id then return c end
  end
end

function Store:exists()
  return vim.uv.fs_stat(self.path) ~= nil
end

--- Apply `fn` to a freshly-read copy, then persist.
function Store:mutate(fn)
  self:reload()
  self.data.version = 1
  self.data.repo_root = self.repo_root
  self.data.branch = self.branch
  self.data.base = self.base
  fn(self.data)
  self.writing = true
  util.write_atomic(self.path, util.encode_pretty(self.data))
  -- Suppress the fs_event our own write is about to produce.
  vim.defer_fn(function() self.writing = false end, 200)
end

function Store:add(c)
  c.id = c.id or util.id()
  c.created_at = c.created_at or util.now()
  c.author = c.author or "human"
  c.status = c.status or "open"
  c.replies = c.replies or {}
  self:mutate(function(d) table.insert(d.comments, c) end)
  return c
end

function Store:update(id, fn)
  self:mutate(function(d)
    for _, c in ipairs(d.comments) do
      if c.id == id then fn(c) end
    end
  end)
end

function Store:delete(id)
  self:mutate(function(d)
    for i = #d.comments, 1, -1 do
      if d.comments[i].id == id then table.remove(d.comments, i) end
    end
  end)
end

function Store:counts()
  local open, resolved, orphaned = 0, 0, 0
  for _, c in ipairs(self:comments()) do
    if c.status == "resolved" then resolved = resolved + 1
    elseif c.status == "orphaned" then orphaned = orphaned + 1
    else open = open + 1 end
  end
  return open, resolved, orphaned
end

--- Watch the containing directory, not the file: an atomic rename replaces the
--- inode and would silently kill a file-level watch.
function Store:watch(cb)
  vim.fn.mkdir(self.dir, "p")
  local handle = vim.uv.new_fs_event()
  if not handle then return end
  local want = vim.fs.basename(self.path)
  handle:start(self.dir, {}, vim.schedule_wrap(function(err, filename)
    if err then return end
    if filename and filename ~= want then return end
    if self.writing then return end
    cb()
  end))
  self.handle = handle
end

function Store:stop()
  if self.handle then
    pcall(function() self.handle:stop() end)
    self.handle = nil
  end
end

return Store
