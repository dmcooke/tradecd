local DMC_debug = LibStub:NewLibrary("DMC-Debug-1.0", 1)
if not DMC_debug then return end
local base = LibStub:GetLibrary("DMC-Base-1.0")
local copy_table = base.copy_table
local c = base.c

base.ctable(DMC_debug)

local Buffer = {}
function Buffer.new()
  local o = copy_table(Buffer)
  o.b = {""}
  return o
end
function Buffer:add_string(s)
  local b = self.b
  table.insert(b, s)
  for i = #b-1, 1, -1 do
    if string.len(b[i]) > string.len(b[i+1]) then
      break
    end
    b[i] = b[i] .. table.remove(b)
  end
end
function Buffer:tostring()
  self.b = {table.concat(self.b)}
  return self.b[1]
end


local Repr = {types = {}}
function Repr.new()
  local o = copy_table(Repr)
  o.types = copy_table(Repr.types or {})
  return o
end
Repr.types['nil'] = function (_) return 'nil' end
function Repr.types.boolean(b)
  if b then return "true" else return "false" end
end
function Repr.types.number(n)
  return string.format("%.17g", n)
end
function Repr.types.string(s)
  return string.format("%q", s)
end
function Repr:tostring(...)
  local o = select(1, ...)
  return tostring(o)
end
function Repr:has_repr(...)
  local o = select(1, ...)
  local t = type(o)
  local c = self.types[t]
  if c == nil then
    local mt = getmetatable(o)
    if type(mt) == "table" and mt.__repr then
      return true, mt.__repr
    else
      return false, nil
    end
  else
    return true, c
  end
end
function Repr:repr(...)
  local o = select(1, ...)
  local has_r, r = self:has_repr(...)
  if has_r then
    return r(o)
  else
    return self:tostring(o)
  end
end


local CRepr = Repr:new()
CRepr.types['nil'] = function (_) return c"{blue}nil{stop}" end
function CRepr.types.boolean(b)
  if b then return c"{yellow}true{stop}" else return c"{yellow}false{stop}" end
end
function CRepr.types.number(n)
  return string.format(c"{magenta}%.17g{stop}", n)
end
function CRepr.types.string(s)
  return string.format(c"{cyan}%q{stop}", s)
end
CRepr.types['function'] = function(f)
                            return c"{brown}<"..tostring(f)..c">{stop}"
                          end
function CRepr.types.userdata(u)
  return c"{red}" .. tostring(u) .. c"{stop}"
end
function CRepr.types.thread(t)
  return c"{red}" .. tostring(t) .. c"{stop}"
end


local function has_repr(...) return Repr:has_repr(...) end
local function repr(...) return Repr:repr(...) end
DMC_debug.repr = repr



local no_identity = {number=true, boolean=true, string=true, ['nil']=true}

local symbol_mt = {
  __repr = function(sym)
             return sym.tag
           end
}
local function is_symbol(o)
  return getmetatable(o) == symbol_mt
end

local function flatten(x)
  local gensym_max = 0
  local function gensym(x)
    gensym_max = gensym_max + 1
    local tag = type(x) .. tostring(gensym_max)
    local sym = {tag=tag, type=type(x), g=gensym_max,
                 references = 1}
    setmetatable(sym, symbol_mt)
    return sym
  end
  local originals = {}   -- original object -> symbol
  local tables = {}
  local function ser(x)
    if no_identity[type(x)] then
      return x
    elseif originals[x] then
      local sym = originals[x]
      sym.references = sym.references + 1
      return sym
    end
    local sym = gensym(x)
    originals[x] = sym
    if type(x) ~= "table" then
      return sym
    else
      local parallel = {}
      for k, v in pairs(x) do
        local ok = ser(k)
        local ov = ser(v)
        parallel[ok] = ov
      end
      tables[sym] = parallel
      return sym
    end
  end
  local toplevel = ser(x)
  return toplevel, tables
end

local formatter = {}
function formatter.new()
  local o = copy_table(formatter)
  o.b = Buffer.new()
  o.add_newline = false
  o.indent_level = 0
  return o
end
function formatter:_do_newline()
  if self.add_newline then
    self.b:add_string( "\n" .. string.rep(" ", 2*self.indent_level))
    self.add_newline = false
  end
end
function formatter:add(s)
  self:_do_newline()
  self.b:add_string(s)
  return self
end
function formatter:newline(s)
  self.add_newline = true
  return self
end
function formatter:indent()
  self.indent_level = self.indent_level + 1
  return self
end
function formatter:dedent()
  self.indent_level = math.max(0, self.indent_level-1)
  return self
end
function formatter:tostring()
  return self.b:tostring()
end


_G.table_formatter = {}
function table_formatter.new(acc)
  local o = copy_table(table_formatter)
  o.acc = acc
  o.repr = Repr
  return o
end
function table_formatter:open()
  self.acc:add("{"):indent()
end
function table_formatter:close()
  self.acc:dedent():add("}")
end
function table_formatter:sep()
  self.acc:add(",")
end
function table_formatter:sep_nl()
  self:sep(); self.acc:newline()
end
function table_formatter:open_key()
  self.acc:add("[")
end
function table_formatter:close_key()
  self.acc:add("] = ")
end

function table_formatter:add_empty_table()
  self:open()
  self:close()
end
function table_formatter:add_array(x, repr)
  self:open()
  for i, v in ipairs(x) do
    repr(v)
    if i ~= #x then self:sep() end
  end
  self:close()
end
function table_formatter:add_hash(x, repr)
  self:open()
  for k, v in pairs(x) do
    self:open_key()
    repr(k)
    self:close_key()
    repr(v)
    self:sep_nl()
  end
  self:close()
end

function table_formatter:add_table(x, repr)
  local n = size(x)
  if n == 0 then
    self:add_empty_table()
  elseif n == #x then
    self:add_array(x, repr)
  else
    self:add_hash(x, repr)
  end
  return self
end


_G.table_cformatter = table_formatter.new()
_G.table_cformatter.repr = CRepr
function table_cformatter:open()
  self.acc:add(c"{green}{{stop}"):indent()
end
function table_cformatter:close()
  self.acc:dedent():add(c"{green}}{stop}")
end
function table_cformatter:sep()
  self.acc:add(c"{green},{stop}")
end
function table_cformatter:open_key()
  self.acc:add(c"{green}[{stop}")
end
function table_cformatter:close_key()
  self.acc:add(c"{green}] = {stop}")
end


local function xserialize(x, name, table_formatter)
  name = name or "__unnamed__"
  local toplevel, tables = flatten(x)
  local acc = formatter.new()
  local tacc = table_formatter.new(acc)
  function repr_no_cycles(x)
    if tables[x] and x.references == 1 then
      tacc:add_table(tables[x], repr_no_cycles)
    else
      acc:add(tacc.repr:repr(x))
    end
    return acc
  end
  local function add_toplevel(name, x)
    acc:add(name .. " = ")
    repr_no_cycles(x):add(";"):newline()
  end
  for k, v in pairs(tables) do
    if k.references > 1 then
      acc:add(k.tag .. " = ")
      tacc:add_table(v, repr_no_cycles)
      acc:add(";"):newline()
    end
  end
  add_toplevel(name, toplevel)
  return acc:tostring()
end


local function serialize(...)
  local t, name, maxdepth
  t = select(1, ...)
  name = select(2, ...) or "__unnamed__"
  maxdepth = select(3, ...) or math.huge
  local cart = {}
  local autoref = {} -- for self references

  local function acc(cart, ...)
    for v in base.values{...} do
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
    
    if type(value) ~= "table" or has_repr(value) then
      acc(cart, " = ", repr(value), ";\n")
    else
      if saved[value] then
        acc(cart, " = {}; -- ", saved[value], " (self reference)\n")
        acc(autoref, name, " = ", saved[value], ";\n")
      else
        saved[value] = name
        if isemptytable(value) then
          acc(cart, " = {")
        else
          acc(cart, " = {\n")
          for k, v in pairs(value) do
            k = repr(k)
            local fname = string.format("%s[%s]", name, k)
            field = string.format("[%s]", k)
            -- three spaces between levels
            addtocart(v, fname, indent .. "   ", saved, field, depth+1)
          end
        end
        local mt = getmetatable(value)
        if mt then
          local fname = string.format("%s<metatable>", name)
          addtocart(mt, fname, indent .. "   ", saved, "<metatable>", depth+1)
        end
        acc(cart, indent, "};\n")
      end
    end
  end

  if type(t) ~= "table" then
    return name .. " = " .. repr(t)
  end
  addtocart(t, name, "", {}, name, 0)
  return table.concat(cart, "") .. table.concat(autoref, "")
end


local function create_debug(name)
  local prefix = string.format(c"{orange}%s {magenta}DEBUG {green}",
                               name or "<>")
  local function debug_(...)
    local t = {}
    for i = 1, select("#", ...) do
      t[i] = tostring(select(i, ...))
    end
    local m = table.concat(t, "")
    print(prefix .. m .. c.stop)
  end
  local function dump_(...)
    local nargs = select("#", ...)
    local name, v, maxdepth
    maxdepth = 5
    -- possible arguments:
    -- (varname, obj, maxdepth)
    -- (varname, obj)
    -- (obj)
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
    elseif nargs > 3 then
      error("dump called with too many arguments")
    else
      error("dump called with no arguments")
    end
    name = c.green .. tostring(name) .. c.stop
    msg = prefix .. tostring(msg) .. c.stop
    local s = serialize(v, name, maxdepth)
    for i, line in ipairs({strsplit("\n", s)}) do
      if i == 1 then line = prefix .. line end
      print(line)
    end
  end
  return debug_, dump_
end
DMC_debug.create_debug = create_debug
local debug, dump = create_debug("DMC_debug")
DMC_debug.debug = debug
DMC_debug.dump = dump
