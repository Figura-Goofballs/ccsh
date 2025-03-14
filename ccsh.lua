local make_package = require("mkRequire")

local shell = {}

local function mkEnv()
   local env = setmetatable({}, {__index = _G})

   env.shell = shell

   env.require, env.package = make_package(env, shell.dir())

   return env
end

local function split(str, on)
    on = on or " "
    local result = {}
    local delimiter = on:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    for match in (str .. on):gmatch("(.-)" .. delimiter) do
        result[#result+1] = match
    end
    return result
end

term.setCursorBlink(true)

local emptyFunc = function() end

---@type thread?
local running
local vars = vars or {
   PATH = "/bin:/rom/programs:/rom/programs/fun" ..
         (multishell and ":/rom/programs/advanced" or "") ..
         (turtle and ":/rom/programs/turtle" or "") ..
         (commands and ":/rom/programs/command" or "") ..
         (http and ":/rom/programs/http" or "") ..
         (pocket and ":/rom/programs/pocket" or "") ..
         (rednet and ":/rom/programs/rednet" or ""),
   SHELL = "ccsh",
   TERM = term.isColor() and "ADVANCED" or "NORMAL",
   PS1 = "$ "
}

local dir = "/"
function shell.dir()
   return dir
end
function shell.path()
   return vars.PATH
end

local importantKeys = {
   shift = {
      [340] = true,
      [344] = true
   },
   control = {
      [341] = true,
      [345] = true
   },
   caps = {
      [280] = true
   },
   enter = {
      [257] = true
   },
   backspace = {
      [259] = true, -- backspace
      [261] = true -- delete
   }
}

local internalCommands = {
   echo = function(...)
      print(table.concat({...}, " "))
   end,
   exit = function() end -- Placeholder
}


term.write(vars.PS1)

local shift, caps, control, escaped
local args = {[0] = ""}
local cols = {[0] = #vars.PS1}

local function locateCommand(cmd, env)
   if internalCommands[cmd] then
      return internalCommands[cmd]
   end

   for _, v in pairs(split(vars.PATH, ":")) do
      local check = fs.combine(v, cmd)
      if v:match("^.") == "/" then
         check = "/" .. check
      end

      if fs.exists(check) and cmd ~= "" then
         local file = fs.open(check, "r")

         if not file then return "" end

         return load(file.readAll(), check, nil, env)
      elseif fs.exists(check .. ".lua") and cmd ~= "" then
         local file = fs.open(check .. ".lua", "r")

         if not file then return "" end

         return load(file.readAll(), check .. ".lua", nil, env)
      elseif fs.exists("/" .. fs.combine(shell.dir(), cmd)) and name ~= "" then
         local file = fs.open(fs.combine(shell.dir(), cmd), "r")

         if not file then return "" end

         return load(file.readAll(), v, nil, env)
      end
   end

   return "Command not found."
end

local commandError
local function runCommand()
   local arg = {}

   for k, v in pairs(args) do
      arg[k] = v:gsub("\x00", "")
   end

   local env = mkEnv()
   env.arg = arg
   env.vars = vars

   local func = locateCommand(arg[0], env)
   local err = type(func) == "string" and func

   if not err then
      local success, error = pcall(func, table.unpack(arg))

      if not success then
         vars["?"] = 1
         local color = term.getTextColor()
         term.setTextColor(colors.red)
         print(error)
         term.setTextColor(color)
         args = {[0] = ""}
      end

      if internalCommands[arg[0]] then
         running = coroutine.create(internalCommands[arg[0]])

         coroutine.resume(running, table.unpack(arg))

         args = {[0] = ""}
         return
      elseif fs.exists(check) and arg[0] ~= "" then
         local file = fs.open(check, "r")

         local env = mkEnv()
         env.arg = arg
         env.vars = vars

         running = coroutine.create(load(file.readAll(), v, nil, env))

         coroutine.resume(running, table.unpack(arg))

         args = {[0] = ""}
         return
      elseif arg[0] ~= "" and fs.exists("/" .. fs.combine(shell.dir(), arg[0])) then
         local file = fs.open(fs.combine(shell.dir(), arg[0]), "r")

         local env = mkEnv()
         env.arg = arg
         env.vars = vars

         running = coroutine.create(load(file.readAll(), v, nil, env))

         coroutine.resume(running, table.unpack(arg))

         args = {[0] = ""}
         return
      end
   end

   if args[0] ~= "" then
      vars["?"] = 127
   else
      vars["?"] = 1
      local color = term.getTextColor()
      term.setTextColor(colors.red)
      print(err)
      term.setTextColor(color)
      args = {[0] = ""}
   end

   args = {[0] = ""}
   cols = {[0] = #vars.PS1}

   local env = mkEnv()
   env.arg = arg
   env.vars = vars

   term.write(vars.PS1)
   cols = {[0] = #vars.PS1}
end

local function backspace()
   local x, y = term.getCursorPos()
   x = x - 1

   if x == 0 then
      y = y - 1

      if y == 0 then
         y = 1
         x = 1
      else
         cols[#cols] = nil
         x = cols[#cols]

         if cols[0] < #vars.PS1 then
            cols[0] = #vars.PS1
         end

         term.setCursorPos(x, y)
         return
      end
   end

   term.setCursorPos(x, y)
   term.write(" ")
   term.setCursorPos(x, y)

   if args[#args] == "" then
      args[#args] = nil

      if not args[0] then
         term.write(" ")
         args[0] = ""
      end
   else
      args[#args] = args[#args]:gsub(".$", "")

      if args[#args]:match("\x00$") then
         escaped = true
      end
   end

   escaped = false
end

while true do
   local eventData = {os.pullEventRaw()}
   local event = eventData[1]
   table.remove(eventData, 1)

   if running and coroutine.status(running) == "running" and event ~= "terminate" then
      goto continue
   elseif running and coroutine.status(running) == "dead" then
      term.write(vars.PS1)
      cols = {[0] = #vars.PS1}
      running = nil
   end

   if event == "terminate" and running then
      running = nil
      print()
      cols = {[0] = #vars.PS1}
      term.write(vars.PS1)
      vars["?"] = 130
   elseif event == "terminate" then
      vars["?"] = 137
   elseif event == "key" then
      if importantKeys.shift[eventData[1]] then
         shift = true
      elseif importantKeys.caps[eventData[1]] then
         caps = not caps
      elseif importantKeys.control[eventData[1]] then
         control = true
      elseif importantKeys.enter[eventData[1]] then
         print()
         cols[#cols + 1] = 0

         if not escaped then
            if args[0]:gsub("\x00", "") == "exit" then
               return tonumber(arg[1] or "") or 0
            end

            runCommand()
         end
      elseif importantKeys.backspace[eventData[1]] then
         backspace()
      end
   elseif event == "key_up" then
      if importantKeys.shift[eventData[1]] then
         shift = false
      elseif importantKeys.control[eventData[1]] then
         control = false
      end
   elseif event == "char" then
      local char = eventData[1]
      local unescape = true

      if char == "\\" and not escaped then
         escaped = true
         cols[#cols] = cols[#cols] + #char

         args[#args] = args[#args] .. "\x00"

         goto write
      elseif char == " " and not escaped then
         args[#args + 1] = ""
         cols[#cols] = cols[#cols] + #char

         goto write
      end

      escaped = false
      args[#args] = args[#args] .. char

      ::write::

      local width = term.getSize()
      local x = term.getCursorPos()

      if x == width then
         print()
         cols[#cols + 1] = 0
      end

      term.write(char)
      cols[#cols] = cols[#cols] + #char
   else
      -- print(event, table.unpack(eventData))
   end

   ::continue::
end

