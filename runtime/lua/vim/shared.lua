-- Functions shared by Nvim and its test-suite.
--
-- The singular purpose of this module is to share code with the Nvim
-- test-suite. If, in the future, Nvim itself is used to run the test-suite
-- instead of "vanilla Lua", these functions could move to src/nvim/lua/vim.lua

local vim = {}

--- Returns a deep copy of the given object. Non-table objects are copied as
--- in a typical Lua assignment, whereas table objects are copied recursively.
---
--@param orig Table to copy
--@returns New table of copied keys and (nested) values.
function vim.deepcopy(orig) end  -- luacheck: no unused
vim.deepcopy = (function()
  local function _id(v)
    return v
  end

  local deepcopy_funcs = {
    table = function(orig)
      local copy = {}
      for k, v in pairs(orig) do
        copy[vim.deepcopy(k)] = vim.deepcopy(v)
      end
      return copy
    end,
    number = _id,
    string = _id,
    ['nil'] = _id,
    boolean = _id,
  }

  return function(orig)
    return deepcopy_funcs[type(orig)](orig)
  end
end)()

--- Splits a string at each instance of a separator.
---
--@see |vim.split()|
--@see https://www.lua.org/pil/20.2.html
--@see http://lua-users.org/wiki/StringLibraryTutorial
---
--@param s String to split
--@param sep Separator string or pattern
--@param plain If `true` use `sep` literally (passed to String.find)
--@returns Iterator over the split components
function vim.gsplit(s, sep, plain)
  assert(type(s) == "string", string.format("Expected string, got %s", type(s)))
  assert(type(sep) == "string", string.format("Expected string, got %s", type(sep)))
  assert(type(plain) == "boolean" or type(plain) == "nil", string.format("Expected boolean or nil, got %s", type(plain)))

  local start = 1
  local done = false

  local function _pass(i, j, ...)
    if i then
      assert(j+1 > start, "Infinite loop detected")
      local seg = s:sub(start, i - 1)
      start = j + 1
      return seg, ...
    else
      done = true
      return s:sub(start)
    end
  end

  return function()
    if done then
      return
    end
    if sep == '' then
      if start == #s then
        done = true
      end
      return _pass(start+1, start)
    end
    return _pass(s:find(sep, start, plain))
  end
end

--- Splits a string at each instance of a separator.
---
--- Examples:
--- <pre>
---  split(":aa::b:", ":")     --> {'','aa','','bb',''}
---  split("axaby", "ab?")     --> {'','x','y'}
---  split(x*yz*o, "*", true)  --> {'x','yz','o'}
--- </pre>
--
--@see |vim.gsplit()|
---
--@param s String to split
--@param sep Separator string or pattern
--@param plain If `true` use `sep` literally (passed to String.find)
--@returns List-like table of the split components.
function vim.split(s,sep,plain)
  local t={} for c in vim.gsplit(s, sep, plain) do table.insert(t,c) end
  return t
end

--- Checks if a list-like (vector) table contains `value`.
---
--@param t Table to check
--@param value Value to compare
--@returns true if `t` contains `value`
function vim.tbl_contains(t, value)
  assert(type(t) == 'table', string.format("Expected table, got %s", type(t)))

  for _,v in ipairs(t) do
    if v == value then
      return true
    end
  end
  return false
end

--- Merges two or more map-like tables.
---
--@see |extend()|
---
--@param behavior Decides what to do if a key is found in more than one map:
---      - "error": raise an error
---      - "keep":  use value from the leftmost map
---      - "force": use value from the rightmost map
--@param ... Two or more map-like tables.
function vim.tbl_extend(behavior, ...)
  if (behavior ~= 'error' and behavior ~= 'keep' and behavior ~= 'force') then
    error('invalid "behavior": '..tostring(behavior))
  end
  local ret = {}
  for i = 1, select('#', ...) do
    local tbl = select(i, ...)
    if tbl then
      for k, v in pairs(tbl) do
        if behavior ~= 'force' and ret[k] ~= nil then
          if behavior == 'error' then
            error('key found in more than one map: '..k)
          end  -- Else behavior is "keep".
        else
          ret[k] = v
        end
      end
    end
  end
  return ret
end

--- Creates a copy of a list-like table such that any nested tables are
--- "unrolled" and appended to the result.
---
--@param t List-like table
--@returns Flattened copy of the given list-like table.
function vim.tbl_flatten(t)
  -- From https://github.com/premake/premake-core/blob/master/src/base/table.lua
  local result = {}
  local function _tbl_flatten(_t)
    local n = #_t
    for i = 1, n do
      local v = _t[i]
      if type(v) == "table" then
        _tbl_flatten(v)
      elseif v then
        table.insert(result, v)
      end
    end
  end
  _tbl_flatten(t)
  return result
end

--- Trim whitespace (Lua pattern "%s") from both sides of a string.
---
--@see https://www.lua.org/pil/20.2.html
--@param s String to trim
--@returns String with whitespace removed from its beginning and end
function vim.trim(s)
  assert(type(s) == 'string', string.format("Expected string, got %s", type(s)))
  return s:match('^%s*(.*%S)') or ''
end

--- Escapes magic chars in a Lua pattern string.
---
--@see https://github.com/rxi/lume
--@param s  String to escape
--@returns  %-escaped pattern string
function vim.pesc(s)
  assert(type(s) == 'string', string.format("Expected string, got %s", type(s)))
  return s:gsub('[%(%)%.%%%+%-%*%?%[%]%^%$]', '%%%1')
end

--- Validates a parameter specification (types and values).
---
--- Examples:
--- <pre>
---  function user.new(name, age, hobbies)
---    vim.validate{
---      name={name, 'string'},
---      age={age, 'number'},
---      hobbies={hobbies, 'table'},
---    }
---    ...
---  end
--
---  vim.validate{ arg1={{'foo'}, 'table'}, arg2={'foo', 'string'}}
---     => NOP (success)
---  vim.validate{arg1={1, 'table'}}
---     => error("arg1: expected table, got number")
---  vim.validate{arg1={{'foo'}, 'table'}, arg2={1, 'string'}}
---     => error("arg2: expected string, got number")
---  vim.validate{arg1={3, function(a) return (a % 2) == 0 end, 'even number'}}
---     => error("arg1: expected even number, got 3")
--- </pre>
---
--@param opt Map of parameter names to validations. Each key is a parameter
---          name; each value is a tuple in one of these forms:
---          1. {arg_value, type_name, optional}
---             - arg_value: argument value
---             - type_name: string type name, one of: ("table", "t", "string",
---               "s", "number", "n", "boolean", "b", "function", "f", "nil",
---               "thread", "userdata")
---             - optional: (optional) boolean, if true, `nil` is valid
---          2. {arg_value, fn, msg}
---             - arg_value: argument value
---             - fn: any function accepting one argument, returns true if and
---               only if the argument is valid
---             - msg: (optional) error string if validation fails
function vim.validate(opt) end  -- luacheck: no unused
vim.validate = (function()
  local type_names = {
    t='table', s='string', n='number', b='boolean', f='function', c='callable',
    ['table']='table', ['string']='string', ['number']='number',
    ['boolean']='boolean', ['function']='function', ['callable']='callable',
    ['nil']='nil', ['thread']='thread', ['userdata']='userdata',
  }
  local function type_name(t)
    local tname = type_names[t]
    if tname == nil then
      error(string.format('invalid type name: %s', tostring(t)))
    end
    return tname
  end
  local function is_type(val, t)
    return t == 'callable' and vim.is_callable(val) or type(val) == t
  end

  return function(opt)
    assert(type(opt) == 'table', string.format('opt: expected table, got %s', type(opt)))
    for param_name, spec in pairs(opt) do
      assert(type(spec) == 'table', string.format('%s: expected table, got %s', param_name, type(spec)))

      local val = spec[1]   -- Argument value.
      local t = spec[2]     -- Type name, or callable.
      local optional = (true == spec[3])

      if not vim.is_callable(t) then  -- Check type name.
        if not (optional or type(val) == 'nil') and not is_type(val, type_name(t)) then
          error(string.format("%s: expected %s, got %s", param_name, type_name(t), type(val)))
        end
      elseif not t(val) then  -- Check user-provided validation function.
        error(string.format("%s: expected %s, got %s", param_name, spec[3], val))
      end
    end
    return true
  end
end)()

--- Return whether an object can call be used as a function.
---
--@param f Any type of variable
--@return Boolean
function vim.is_callable(f)
  if type(f) == 'function' then return true end
  local m = getmetatable(f)
  if m == nil then return false end
  return type(m.__call) == 'function'
end

return vim
