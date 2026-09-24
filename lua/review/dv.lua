--- Resolve a diffview buffer to {path, side, rev}. Diffview only hands you a
--- real file buffer for the working-tree side; every git-blob side is a
--- diffview:// URI. Rather than parse those, ask diffview directly.
local M = {}

local function lib()
  local ok, l = pcall(require, "diffview.lib")
  return ok and l or nil
end

function M.view()
  local l = lib()
  if not l then return nil end
  local ok, v = pcall(l.get_current_view)
  return ok and v or nil
end

function M.in_diffview()
  return M.view() ~= nil
end

function M.repo_root()
  local v = M.view()
  if v and v.adapter and v.adapter.ctx then return v.adapter.ctx.toplevel end
  return nil
end

--- @return table|nil { path, side, rev, frozen }
function M.locate(bufnr)
  local v = M.view()
  if not v or not v.cur_entry then return nil end
  local entry = v.cur_entry
  local layout = entry.layout
  if not layout then return nil end

  local a = layout.a and layout.a.file
  local b = layout.b and layout.b.file
  local side, file
  if b and b.bufnr == bufnr then
    side, file = "new", b
  elseif a and a.bufnr == bufnr then
    side, file = "old", a
  else
    return nil
  end

  local rev, frozen = nil, true
  if file.rev then
    if tostring(file.rev) == "LOCAL" then
      frozen = false
    else
      local ok, abbrev = pcall(function() return file.rev:abbrev(11) end)
      rev = ok and abbrev or tostring(file.rev)
    end
  end

  -- A rename shows the old name on the old side. `path` stays the entry's
  -- name so both sides group together; `old_path` is where the code lived.
  local old_path
  if side == "old" and entry.oldpath and entry.oldpath ~= entry.path then
    old_path = entry.oldpath
  end

  return {
    path = entry.path,
    old_path = old_path,
    side = side,
    rev = rev,
    frozen = frozen,
  }
end

--- True when the new side is a live working-tree file. If it isn't (a
--- `base...HEAD` range), nothing can re-anchor and nothing reloads.
function M.is_live()
  local v = M.view()
  if not v or not v.cur_entry or not v.cur_entry.layout then return false end
  local b = v.cur_entry.layout.b and v.cur_entry.layout.b.file
  return b ~= nil and b.rev ~= nil and tostring(b.rev) == "LOCAL"
end

return M
