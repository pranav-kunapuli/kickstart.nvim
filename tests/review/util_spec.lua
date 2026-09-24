local util = require("review.util")

describe("util.encode_pretty", function()
  local function roundtrip(v)
    return vim.json.decode(util.encode_pretty(v))
  end

  it("round-trips a full comment record", function()
    local rec = {
      version = 1,
      branch = "award-recs",
      comments = { {
        id = "h1", file = "app/a.py", side = "new", line_start = 4, line_end = 6,
        tag = "fix", author = "human", status = "open",
        body = "line one\nline two",
        snippet = "    for x in y:\n        z()",
        replies = { { author = "claude", body = 'said "done"', at = "2026-08-26T00:00:00Z" } },
      } },
    }
    assert.are.same(rec, roundtrip(rec))
  end)

  it("escapes quotes, newlines, tabs and backslashes in a body", function()
    local rec = { body = 'a "quote"\nand \\a backslash\tand a tab' }
    assert.are.same(rec, roundtrip(rec))
  end)

  it("preserves unicode", function()
    local rec = { body = "→ ✓ ⚠ é 日本語" }
    assert.are.same(rec, roundtrip(rec))
  end)

  it("emits an empty list as [] so the agent can append to it", function()
    assert.equals("[]", util.encode_pretty({}))
    assert.is_true(util.encode_pretty({ replies = {} }):find("%[%]") ~= nil)
  end)

  it("puts schema fields in a stable, readable order", function()
    local out = util.encode_pretty({ status = "open", id = "h1", body = "b", file = "f", tag = "fix" })
    local order = {}
    for key in out:gmatch('"([%w_]+)":') do order[#order + 1] = key end
    assert.are.same({ "id", "file", "tag", "status", "body" }, order)
  end)

  it("is stable across re-encodes so the file does not churn in git", function()
    local rec = { comments = { { id = "b", body = "x" }, { id = "a", body = "y" } } }
    local once = util.encode_pretty(rec)
    assert.equals(once, util.encode_pretty(vim.json.decode(once)))
  end)

  it("indents nested structures", function()
    local out = util.encode_pretty({ comments = { { id = "h1", replies = { { author = "claude" } } } } })
    assert.is_true(out:find('\n      "id"') ~= nil, "expected nested indent, got:\n" .. out)
  end)
end)

describe("util.write_atomic", function()
  it("writes through a temp file and leaves no debris", function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local path = dir .. "/x.json"
    assert.is_true(util.write_atomic(path, '{"a":1}'))
    assert.equals('{"a":1}', util.read(path))
    assert.are.same({}, vim.fn.glob(dir .. "/*.tmp", false, true))
  end)

  it("overwrites an existing file in place", function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local path = dir .. "/x.json"
    util.write_atomic(path, "one")
    util.write_atomic(path, "two")
    assert.equals("two", util.read(path))
  end)

  it("creates missing parent directories", function()
    local path = vim.fn.tempname() .. "/nested/deep/x.json"
    assert.is_true(util.write_atomic(path, "hi"))
    assert.equals("hi", util.read(path))
  end)
end)

describe("util.read", function()
  it("returns nil for a missing file rather than throwing", function()
    assert.is_nil(util.read(vim.fn.tempname() .. "/nope.json"))
  end)
end)

describe("util.id", function()
  it("does not collide within a session", function()
    local seen = {}
    for _ = 1, 500 do
      local id = util.id()
      assert.is_nil(seen[id], "duplicate id: " .. id)
      seen[id] = true
    end
  end)
end)
