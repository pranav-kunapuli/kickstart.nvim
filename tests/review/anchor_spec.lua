local anchor = require("review.anchor")

--- Build a comment the way the store holds one.
local function c(line_start, snippet)
  return { id = "x", line_start = line_start, line_end = line_start, snippet = snippet }
end

local function lines(s)
  return vim.split(s, "\n", { plain = true })
end

local BODY = lines([[
def total(awards):
    total = 0
    for award in awards:
        s = fetch(award.id)
        total += s.amount
    return total]])

describe("anchor.relocate", function()
  it("keeps a comment whose code has not moved", function()
    local s, e, how = anchor.relocate(BODY, c(3, "    for award in awards:"))
    assert.equals(3, s)
    assert.equals(3, e)
    assert.equals("same", how)
  end)

  it("follows code that moved down", function()
    local shifted = vim.list_extend({ "# a", "# b", "# c" }, vim.deepcopy(BODY))
    local s, e, how = anchor.relocate(shifted, c(3, "    for award in awards:"))
    assert.equals(6, s)
    assert.equals(6, e)
    assert.equals("moved", how)
  end)

  it("follows code that moved up", function()
    local shifted = vim.list_slice(vim.deepcopy(BODY), 2, #BODY)
    local s, _, how = anchor.relocate(shifted, c(3, "    for award in awards:"))
    assert.equals(2, s)
    assert.equals("moved", how)
  end)

  it("keeps a multi-line range together", function()
    local shifted = vim.list_extend({ "# a", "# b" }, vim.deepcopy(BODY))
    local cm = { id = "x", line_start = 3, line_end = 5, snippet = table.concat({
      "    for award in awards:",
      "        s = fetch(award.id)",
      "        total += s.amount",
    }, "\n") }
    local s, e, how = anchor.relocate(shifted, cm)
    assert.equals(5, s)
    assert.equals(7, e)
    assert.equals("moved", how)
  end)

  it("orphans when the code is gone", function()
    local gone = lines("def total(awards):\n    return 0")
    local s, _, how = anchor.relocate(gone, c(3, "    for award in awards:"))
    assert.is_nil(s)
    assert.is_nil(how)
  end)

  it("falls back to the opening line when the body was rewritten", function()
    local rewritten = lines([[
def total(awards):
    total = 0
    for award in awards:
        s = fetch_batched(award.id)
        total += s.gross_amount
    return total]])
    local cm = { id = "x", line_start = 3, line_end = 5, snippet = table.concat({
      "    for award in awards:",
      "        s = fetch(award.id)",
      "        total += s.amount",
    }, "\n") }
    local s, e, how = anchor.relocate(rewritten, cm)
    assert.equals(3, s)
    assert.equals(5, e)
    assert.equals("fuzzy", how)
  end)

  it("prefers the nearer of two identical snippets", function()
    local dup = lines([[
    target()
# 2
# 3
# 4
# 5
    target()]])
    -- from line 4, line 6 is nearer than line 1
    local s = anchor.relocate(dup, c(4, "    target()"))
    assert.equals(6, s)
  end)

  it("clamps a fuzzy end to the end of the file", function()
    local short = lines("    for award in awards:")
    local cm = { id = "x", line_start = 1, line_end = 3,
      snippet = "    for award in awards:\n        a\n        b" }
    local s, e, how = anchor.relocate(short, cm)
    assert.equals(1, s)
    assert.equals(1, e)
    assert.equals("fuzzy", how)
  end)

  it("anchors a comment on a blank line instead of orphaning it", function()
    -- A blank line captures an empty snippet. Orphaning on sight would make
    -- every comment on a blank line die at the first refresh.
    local body = lines("a\n\nb")
    local s, _, how = anchor.relocate(body, c(2, ""))
    assert.is_not_nil(s)
    assert.equals(2, s)
    assert.equals("same", how)
  end)

  it("does not rebind on a lone punctuation line", function()
    -- Loose matching on "}" or ")" would silently point a comment at unrelated
    -- code, which is exactly what the orphan bucket exists to prevent.
    local body = lines("fn a() {\n  x\n}\n\nfn b() {\n  y\n}")
    local cm = { id = "x", line_start = 3, line_end = 3, snippet = "}\n  gone\n  gone2" }
    local s, _, how = anchor.relocate(body, cm)
    assert.is_nil(s, "expected orphan, got " .. tostring(how) .. " at " .. tostring(s))
  end)

  it("gives up beyond the search radius", function()
    local config = require("review.config")
    local old = config.opts.search_radius
    config.opts.search_radius = 2
    local far = vim.list_extend({ "1", "2", "3", "4", "5", "6" }, { "    needle" })
    local s = anchor.relocate(far, c(1, "    needle"))
    config.opts.search_radius = old
    assert.is_nil(s)
  end)
end)
