local M = {}

--- Field order for the on-disk JSON. Anything unlisted sorts alphabetically
--- after these, so hand-edits by the agent survive a round-trip.
local KEY_ORDER = {
  version = 1, repo_root = 2, branch = 3, base = 4, comments = 5, sessions = 5,
  id = 1, file = 2, old_file = 2.5, side = 3, rev = 4, line_start = 5, line_end = 6,
  tag = 7, author = 8, status = 9, body = 10, snippet = 11, replies = 12,
  created_at = 13, at = 14,
}

local function key_rank(k)
  return KEY_ORDER[k] or 99
end

function M.encode_pretty(v, indent)
  indent = indent or ""
  local pad = indent .. "  "
  local t = type(v)
  if v == nil or v == vim.NIL then return "null" end
  if t == "boolean" or t == "number" then return tostring(v) end
  if t == "string" then return vim.json.encode(v) end
  if t ~= "table" then return "null" end

  if vim.islist(v) then
    if #v == 0 then return "[]" end
    local parts = {}
    for _, item in ipairs(v) do
      parts[#parts + 1] = "\n" .. pad .. M.encode_pretty(item, pad)
    end
    return "[" .. table.concat(parts, ",") .. "\n" .. indent .. "]"
  end

  local keys = vim.tbl_keys(v)
  if #keys == 0 then return "{}" end
  table.sort(keys, function(a, b)
    local ra, rb = key_rank(a), key_rank(b)
    if ra ~= rb then return ra < rb end
    return tostring(a) < tostring(b)
  end)
  local parts = {}
  for _, k in ipairs(keys) do
    parts[#parts + 1] = "\n" .. pad .. vim.json.encode(tostring(k)) .. ": " .. M.encode_pretty(v[k], pad)
  end
  return "{" .. table.concat(parts, ",") .. "\n" .. indent .. "}"
end

function M.read(path)
  local fd = vim.uv.fs_open(path, "r", 420)
  if not fd then return nil end
  local stat = vim.uv.fs_fstat(fd)
  local data = stat and vim.uv.fs_read(fd, stat.size, 0) or nil
  vim.uv.fs_close(fd)
  return data
end

--- Write via temp file + rename so a concurrent reader never sees a partial file.
function M.write_atomic(path, content)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local tmp = ("%s.%d.tmp"):format(path, vim.uv.os_getpid())
  local fd = vim.uv.fs_open(tmp, "w", 420)
  if not fd then return false end
  vim.uv.fs_write(fd, content)
  vim.uv.fs_close(fd)
  return vim.uv.fs_rename(tmp, path) and true or false
end

function M.git(root, args)
  local cmd = { "git", "-C", root }
  vim.list_extend(cmd, args)
  local ok, res = pcall(function()
    return vim.system(cmd, { text = true }):wait()
  end)
  if not ok or res.code ~= 0 then return nil end
  return (res.stdout or ""):gsub("%s+$", "")
end

function M.now()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local counter = 0
function M.id()
  counter = counter + 1
  return ("h%x%x%x"):format(os.time() % 0xffffff, vim.uv.os_getpid() % 0xfff, counter)
end

function M.notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "review" })
end

return M
