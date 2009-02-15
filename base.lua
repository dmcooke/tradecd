DMC_base = LibStub:NewLibrary("DMC-Base-1.0", 1)
if not DMC_base then return end

local is_wow = (module == nil)

local colours
if is_wow then
  -- 0 <= r,g,b <= 255
  local function rgb(r,g,b)
    return string.format("|cff%02x%02x%02x", r, g, b)
  end
  colours = {
    stop =    "|r",
    white =   rgb(255, 255, 255),
    black =   rgb(  0,   0,   0),
    red =     rgb(255,   0,   0),
    green =   rgb(  0, 255,   0),
    blue =    rgb(  0,   0, 255),
    cyan =    rgb(  0, 255, 255),
    magenta = rgb(255,   0, 255),
    yellow =  rgb(255, 255,   0),
    orange =  rgb(255, 165,   0),
    brown =   rgb(165,  42,  42),
  }
else
  -- 0 <= r,g,b <= 5
  local function rgb(r, g, b)
    -- 88 or 256-colour xterm
    return string.format('\27[38;5;%dm', 16+r*36+g*6+b)
  end
  colours = {
    stop = "\27[m",
    white = "\27[37m",
    black = "\27[30m",
    red = "\27[31m",
    green = "\27[32m",
    blue = "\27[34m",
    cyan = "\27[36m",
    yellow = "\27[33m",
    magenta = "\27[35m",
    orange = rgb(5, 3, 0),
    brown = rgb(3, 1, 1),
  }
end

local function colourise(s)
  local cs, _ = string.gsub(s, "{(%w+)}", colours)
  return cs
end
DMC_base.colourise = colourise
local c = colours
setmetatable(c,
             {__call = function(t, s)
                         local cs = t[s]
                         if not cs then
                           cs = colourise(s)
                           t[s] = cs
                         end
                         return cs
                       end})
DMC_base.c = c

--
-- Operations on or with tables
--

-- If tbl[key] exists, return it, else set it to default() and return that.
local function table_get(tbl, key, default)
  local value = tbl[key]
  if value == nil then
    value = default()
    tbl[key] = value
  end
  return value
end
DMC_base.table_get = table_get

-- Return a copy of the table tbl. (Doesn't copy the metatable)
local function copy_table(tbl)
  local c = {}
  for k, v in pairs(tbl) do
    c[k] = v
  end
  return c
end
DMC_base.copy_table = copy_table

local function size(tbl)
  local n = 0
  for _ in pairs(tbl) do
    n = n + 1
  end
  return n
end
DMC_base.size = size

-- Makes a lazy copy of the table tbl. When a key is accessed that doesn't
-- exist in the copy yet, the value from the original table is used.
-- (Changes a (key, value) to the original table before the key is used in
-- the copy will be reflected in the copy.)
local function lazy_table_copy(tbl)
  -- Note that __index is only called if the key doesn't exist in the
  -- table already
  local function getter(t, k)
    local v = tbl[k]
    t[k] = v
    return v
  end
  return setmetatable({}, {__index = getter})
end
DMC_base.lazy_table_copy = lazy_table_copy

-- Return a sorted copy of the table
local function sorted(tbl, cmp)
  local t = copy_table(tbl)
  table.sort(t, cmp)
  return t
end
DMC_base.sorted = sorted

-- Return an iterator over the keys in the table tbl.
local function keys(tbl)
  local function iterator(state)
    local it = next(state.list, state.content)
    state.content = it
    return it
  end
  return iterator, {list=tbl}
end
DMC_base.keys = keys

-- Return an iterator over the values in the table tbl.
-- Useful when used as
--   for x in values{"a", "b", "c"} do ... end
-- (although unlike ivalues below, the order in this case is not guaranteed
--  to be the same)
local function values(tbl)
  local function iterator(state)
    local it
    state.content, it = next(state.list, state.content)
    return it
  end
  return iterator, {list=tbl}
end
DMC_base.values = values

-- Return an iterator over the values of the array tbl.
-- Useful when used as
--   for x in ivalues{"a", "b", "c"} do .. end
local function ivalues(tbl)
  local i = 1
  local function iterator()
    local r = x[i]; i = i+1; return r
  end
  return iterator
end
DMC_base.ivalues = ivalues

-- Return a sorted array of the keys of t
local function sorted_keys(t, cmp)
  local keys = {}
  for k, v in pairs(t) do
    table.insert(keys, k)
  end
  table.sort(keys, cmp)
  return keys
end
DMC_base.sorted_keys = sorted_keys

--
-- "Checked" tables
--
-- Raises an error on indexing if the index (key) doesn't exist in the table

local checked_table_mt = {
  __is_checked_table = true,
  __index = function(t, key)
              error(string.format("Attempt to access non-existing key %q",
                                  tostring(key)), 2)
            end
}
-- Converts the table t to a checked table. (Modifies t)
local function ctable(t)
  return setmetatable(t, checked_table_mt)
end
DMC_base.ctable = ctable
ctable(DMC_base)

local function isctable(t)
  local mt = getmetatable(t)
  return (mt and mt.__is_checked_table)
end

local function new_ctable() return ctable{} end
DMC_base.new_ctable = new_ctable

-- Convert t and its subtables to checked tables.
local function deep_convert_to_ctable(t)
  if not isctable(t) then
    ctable(t)
    for k, v in pairs(t) do
      if type(v) == "table" then
        deep_convert_to_ctable(v)
      end
    end
  end
end
DMC_base.deep_convert_to_ctable = deep_convert_to_ctable

-- Like table_get, but for checked tables.
local function ctable_get(d, key, default)
  local value = rawget(d, key)
  if value == nil then
    value = default()
    d[key] = value
  end
  return value  
end
DMC_base.ctable_get = ctable_get

-- Returns a lazy copy of the table tbl, like lazy_table_copy, but
-- non-existing keys raise an error instead.
-- Useful for catching bad global accesses, as in
--   local _G = getfenv()
--   setfenv(1, lazy_ctable_copy(_G))
local function lazy_ctable_copy(tbl)
  local function getter(t, k)
    local v = tbl[k]
    if v == nil then
      error(string.format("Attempt to access non-existing key %q",
                          tostring(key)), 2)
    end
    t[k] = v
    return v
  end
  return setmetatable({}, {__is_checked_table=true, __index = getter})
end
DMC_base.lazy_ctable_copy = lazy_ctable_copy


local function global_protection(level)
  level = level or 1
  local _G = getfenv(level)
  setfenv(level, lazy_ctable_copy(_G))
  return _G
end
DMC_base.global_protection = global_protection


local function wrap_index(self, key)
  local upref = rawget(self, '_upref')
  local v = upref[key]
  if type(v) == "function" then
    return function(...)
             return v(upref, ...)
           end
  else
    return v
  end
end
local wrap_mt = {__index = wrap_index, __mode = "v"}

local function wrap(obj)
  local w = {_upref = obj}
  return setmetatable(w, wrap_mt)
end
DMC_base.wrap = wrap
