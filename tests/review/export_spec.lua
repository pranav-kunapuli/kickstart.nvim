local Store = require("review.store")
local export = require("review.export")

local function store_with(comments)
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  local s = Store.new(root, "award-recs", "main")
  for _, c in ipairs(comments) do s:add(c) end
  return s
end

describe("export.format", function()
  it("returns nil when nothing is open", function()
    local s = store_with({ { file = "a.py", body = "done", status = "resolved" } })
    assert.is_nil(export.format(s))
  end)

  it("returns nil for an empty store", function()
    assert.is_nil(export.format(store_with({})))
  end)

  it("omits resolved comments but keeps orphaned ones", function()
    local s = store_with({
      { file = "a.py", line_start = 1, line_end = 1, tag = "fix", body = "still open" },
      { file = "a.py", line_start = 2, line_end = 2, tag = "nit", body = "already done", status = "resolved" },
      { file = "a.py", line_start = 3, line_end = 3, tag = "fix", body = "lost its anchor", status = "orphaned" },
    })
    local out = export.format(s)
    assert.is_true(out:find("still open", 1, true) ~= nil)
    assert.is_nil(out:find("already done", 1, true))
    assert.is_true(out:find("lost its anchor", 1, true) ~= nil)
  end)

  it("points at the store and states the write-back contract", function()
    local s = store_with({ { file = "a.py", line_start = 1, line_end = 1, tag = "fix", body = "x" } })
    local out = export.format(s)
    assert.is_true(out:find(".review/award-recs.json", 1, true) ~= nil)
    assert.is_true(out:find("resolved", 1, true) ~= nil)
    assert.is_true(out:find("Do not edit", 1, true) ~= nil)
  end)

  it("groups by file in sorted order", function()
    local s = store_with({
      { file = "z.py", line_start = 1, line_end = 1, tag = "fix", body = "zed" },
      { file = "a.py", line_start = 1, line_end = 1, tag = "fix", body = "aye" },
    })
    local out = export.format(s)
    assert.is_true(out:find("## a.py", 1, true) < out:find("## z.py", 1, true))
  end)

  it("renders a single line, a range, and an old-side anchor distinctly", function()
    local s = store_with({
      { file = "a.py", line_start = 4, line_end = 4, tag = "nit", body = "one" },
      { file = "a.py", line_start = 7, line_end = 9, tag = "fix", body = "many" },
      { file = "a.py", line_start = 40, line_end = 40, tag = "q", body = "old",
        side = "old", rev = "abc123def45" },
    })
    local out = export.format(s)
    assert.is_true(out:find("- L4 %[nit%]") ~= nil, out)
    assert.is_true(out:find("- L7%-9 %[fix%]") ~= nil, out)
    assert.is_true(out:find("- old L40 @ abc123def45 %[q%]") ~= nil, out)
  end)

  it("carries the id so the agent can address a specific comment", function()
    local s = store_with({ { file = "a.py", line_start = 1, line_end = 1, tag = "fix", body = "x" } })
    local id = s:comments()[1].id
    assert.is_true(export.format(s):find("`" .. id .. "`", 1, true) ~= nil)
  end)

  it("indents continuation lines of a multi-line body", function()
    local s = store_with({
      { file = "a.py", line_start = 1, line_end = 1, tag = "fix", body = "first line\nsecond line" },
    })
    local out = export.format(s)
    assert.is_true(out:find("\n  second line", 1, true) ~= nil, out)
  end)

  it("shows existing replies so the agent sees the conversation so far", function()
    local s = store_with({
      { file = "a.py", line_start = 1, line_end = 1, tag = "discussion", body = "thoughts?",
        replies = { { author = "claude", body = "I think yes" } } },
    })
    assert.is_true(export.format(s):find("claude: I think yes", 1, true) ~= nil)
  end)
end)
