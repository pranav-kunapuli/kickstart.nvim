--- Global index of every live review session, so an agent running in ANY
--- worktree can resolve which store belongs to its cwd.
local util = require("review.util")

local M = {}

M.path = vim.fs.joinpath(vim.fn.stdpath("state"), "nvim-review", "sessions.json")

local function alive(pid)
  if not pid then return false end
  local ok, res = pcall(vim.uv.kill, pid, 0)
  return ok and res == 0
end

function M.read()
  local raw = util.read(M.path)
  if not raw or raw == "" then return { sessions = {} } end
  local ok, d = pcall(vim.json.decode, raw)
  if not ok or type(d) ~= "table" then return { sessions = {} } end
  d.sessions = d.sessions or {}
  return d
end

--- Drop our own entry and any entry whose nvim has exited.
local function without(sessions, repo_root)
  local out = {}
  for _, s in ipairs(sessions) do
    if s.repo_root ~= repo_root and alive(s.pid) then out[#out + 1] = s end
  end
  return out
end

function M.publish(entry)
  local sessions = without(M.read().sessions, entry.repo_root)
  entry.pid = vim.uv.os_getpid()
  entry.servername = vim.v.servername
  entry.updated_at = util.now()
  sessions[#sessions + 1] = entry
  util.write_atomic(M.path, util.encode_pretty({ sessions = sessions }))
end

function M.remove(repo_root)
  util.write_atomic(M.path, util.encode_pretty({ sessions = without(M.read().sessions, repo_root) }))
end

return M
