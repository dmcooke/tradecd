--
-- Utility functions.
--
local debug, dump

local is_wow = (module == nil)

-- Implementations for running under non-WoW
if not wipe then
  function wipe(t)
    for _, k in ipairs(t) do
      t[k] = nil
    end
  end
end

if not tinsert then
  tinsert = table.insert
end

if not strsplit then
  function strsplit(delims, s)
    local t = {}
    local len = string.len(s)
    local pat = "[" .. delims .. "]"
    local prev, i = 0, 0
    while true do
      i = string.find(s, pat, prev+1)
      if i == nil then break end
      tinsert(t, string.sub(s, prev+1, i-1))
      prev = i
    end
    return unpack(t)
  end
end

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
  }
else
  -- 0 <= r,g,b <= 5
  local function rgb(r, g, b)
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
  }
end

local function colourise(s)
  local cs, _ = string.gsub(s, "{(%w+)}", colours)
  return cs
end
local c = colourise

local function table_get(d, key, default)
  local value = d[key]
  if value == nil then
    value = default()
    d[key] = value
  end
  return value
end

local function sorted_keys(t)
  local keys = {}
  for k, v in pairs(t) do
    table.insert(keys, k)
  end
  table.sort(keys)
  return keys
end

local function copy_table(t)
  local c = {}
  for k, v in pairs(t) do
    c[k] = v
  end
  return c
end


local function values(x)
  assert(type(x) == 'table', 'values() expects a table')
  local function iterator(state)
    local it
    state.content, it = next(state.list, state.content)
    return it
  end
  return iterator, {list=x}
end

local basic_reprs = {}
basic_reprs['nil'] = function (_) return 'nil' end
function basic_reprs.boolean(o)
  if o then return "true" else return "false" end
end
function basic_reprs.string(s)
  return string.format("%q", s)
end

local function repr(o)
  local t = type(o)
  local c = basic_reprs[t]
  if c == nil then
    return tostring(o)
  else
    return c(o)
  end
end


local function serialize(t, name, maxdepth)
  local cart = {}
  local autoref = {} -- for self references

  local function acc(cart, ...)
    for v in values{...} do
      table.insert(cart, v)
    end
  end

  local function isemptytable(t) return next(t) == nil end

  local function addtocart(value, name, indent, saved, field, depth)
    if depth > maxdepth then
      acc(cart, indent, "...")
      return
    end
    
    acc(cart, indent, field)
    
    if type(value) ~= "table" then
      acc(cart, " = ", repr(value), ";\n")
    else
      if saved[value] then
        acc(cart, " = {}; -- ", saved[value], " (self reference)\n")
        acc(autoref, name, " = ", saved[value], ";\n")
      else
        saved[value] = name
        if isemptytable(value) then
          acc(cart, " = {};\n")
        else
          acc(cart, " = {\n")
          for k, v in pairs(value) do
            k = repr(k)
            local fname = string.format("%s[%s]", name, k)
            field = string.format("[%s]", k)
            -- three spaces between levels
            addtocart(v, fname, indent .. "   ", saved, field, depth+1)
          end
          acc(cart, indent, "};\n")
        end
      end
    end
  end

  name = name or "__unnamed__"
  if type(t) ~= "table" then
    return name .. " = " .. repr(t)
  end
  addtocart(t, name, "", {}, name, 0)
  return table.concat(cart, "") .. table.concat(autoref, "")
end

local function sprintf(fmt, ...)
  local t = {...}
  fmt = tostring(fmt)
  if #t ~= 0 then
    return string.format(fmt, ...)
  else
    return fmt
  end
end

local function create_debug(name)
  local prefix = string.format(c"{orange}%s {magenta}DEBUG {green}",
                               name or "<>")
  local c_stop = c"{stop}"
  local function debug_(...)
    local t = {}
    for i = 1, select("#", ...) do
      t[i] = tostring(select(i, ...))
    end
    local m = table.concat(t, "")
    print(prefix .. m .. c_stop)
  end
  local function dump_(...)
    local nargs = select("#", ...)
    local name, v, maxdepth
    maxdepth = 5
    if nargs == 3 then
      name = select(1, ...)
      v = select(2, ...)
      maxdepth = select(3, ...)
    elseif nargs == 2 then
      name = select(1, ...)
      v = select(2, ...)
    elseif nargs == 1 then
      name = "__unnamed__"
      v = select(1, ...)
    elseif #t > 3 then
      error("dump called with too many arguments")
    else
      error("dump called with no arguments")
    end
    name = c"{green}" .. tostring(name) .. c_stop
    msg = prefix .. tostring(msg) .. c_stop
    local s = serialize(v, name, maxdepth)
    for i, line in ipairs({strsplit("\n", s)}) do
      if i == 1 then line = prefix .. line end
      print(line)
    end
  end
  return debug_, dump_
end

debug, dump = create_debug("DMC_simple")

DMC_simple = {
  colourise = colourise,
  table_get = table_get,
  sorted_keys = sorted_keys,
  copy_table = copy_table,
  repr = repr,
  values = values,
  create_debug = create_debug,
  debug = debug,
  dump = dump,
}
