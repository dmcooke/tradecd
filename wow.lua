foreach = table.foreach
foreachi = table.foreachi
getn = table.getn
sort = table.sort
tinsert = table.insert
tremove = table.remove

function table.wipe(t)
  for _, k in ipairs(t) do
    t[k] = nil
  end
end
wipe = table.wipe

strbyte = string.byte
strchar = string.char
strfind = string.find
strlen = string.len
strlower = string.lower
strmatch = string.match
strrep = string.rep
strsub = string.sub
strupper = string.upper

local function escape_delims(chars)
  return '[' .. string.gsub(chars, '%', '%%') .. ']'
end

function strtrim(str, chars)
  chars = chars or " \t\r\n"
  local cclass = escape_delims(chars)
  return string.gsub(str, "(^"..cclass.."+)|("..cclass.."+$)", "")
end

function strsplit(delims, s)
  local t = {}
  local len = string.len(s)
  local pat = escape_delims(delims)
  local prev, i = 0, 0
  while true do
    i = string.find(s, pat, prev+1)
    if i == nil then
      tinsert(t, string.sub(s, prev+1, -1))
      break
    end
    tinsert(t, string.sub(s, prev+1, i-1))
    prev = i
  end
  return unpack(t)
end

function strjoin(delim, ...)
  return table.concat({...}, delim)
end
