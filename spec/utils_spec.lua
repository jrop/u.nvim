local utils = require 'u.utils'

--- @param s string
local function split(s) return vim.split(s, '') end

--- @param original string
--- @param changes LevenshteinChange[]
local function morph(original, changes)
  local t = split(original)
  for _, change in ipairs(changes) do
    if change.kind == 'add' then
      table.insert(t, change.index, change.item)
    elseif change.kind == 'delete' then
      table.remove(t, change.index)
    elseif change.kind == 'change' then
      t[change.index] = change.to
    end
  end
  return vim.iter(t):join ''
end

describe('utils', function()
  it('levenshtein', function()
    local original = 'abc'
    local result = 'absece'
    local changes = utils.levenshtein(split(original), split(result))
    assert.are.same(changes, {
      {
        item = 'e',
        kind = 'add',
        index = 4,
      },
      {
        item = 'e',
        kind = 'add',
        index = 3,
      },
      {
        item = 's',
        kind = 'add',
        index = 3,
      },
    })
    assert.are.same(morph(original, changes), result)

    original = 'jonathan'
    result = 'ajoanthan'
    changes = utils.levenshtein(split(original), split(result))
    assert.are.same(changes, {
      {
        from = 'a',
        index = 4,
        kind = 'change',
        to = 'n',
      },
      {
        from = 'n',
        index = 3,
        kind = 'change',
        to = 'a',
      },
      {
        index = 1,
        item = 'a',
        kind = 'add',
      },
    })
    assert.are.same(morph(original, changes), result)
  end)
end)
