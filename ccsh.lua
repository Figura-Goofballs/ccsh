local function split(str, on)
    on = on or " "
    local result = {}
    local delimiter = on:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    for match in (str .. on):gmatch("(.-)" .. delimiter) do
        result[#result+1] = match
    end
    return result
end

---@type thread?
local running
local vars = vars or {
   PATH = "/bin:" .. shell.path(),
   SHELL = "ccsh",
   TERM = term.isColor() and "ADVANCED" or "NORMAL",
   PS1 = "$ "
}

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
   echo = function(arg)
      print(table.concat(arg, " "))
   end,
   exit = function() end -- Placeholder
}

term.write(vars.PS1)

local shift, caps, control, escaped
local args = {[0] = ""}
local cols = {[0] = 2}
while true do
   local eventData = {os.pullEventRaw()}
   local event = eventData[1]
   table.remove(eventData, 1)

   if running and coroutine.status(running) == "running" and event ~= "terminate" then
      goto continue
   elseif running and coroutine.status(running) == "dead" then
      _, vars["?"] = coroutine.resume(running)

      term.write(vars.PS1)
      cols = {[0] = 2}
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
            for _, v in pairs(split(vars.PATH, ":")) do
               local check = fs.combine(v, args[0])
               if v:match("^.") == "/" then
                  check = "/" .. check
               end

               if internalCommands[args[0]] then
                  if args[0] == "exit" then
                     return tonumber(args[1] or "") or 0
                  end

                  running = coroutine.create(internalCommands[args[0]])

                  coroutine.resume(running, args)

                  args = {[0] = ""}
                  goto continue
               elseif fs.exists(check) and args[0] ~= "" then
                  local file = fs.open(check, "r")

                  local env = _G
                  env.args = args

                  running = coroutine.create(load(file.readAll(), v, "t", env))

                  coroutine.resume(running)

                  args = {[0] = ""}
                  goto continue
               elseif fs.exists("/" .. fs.combine(shell.dir(), args[0])) and args[0] ~= "" then
                  local file = fs.open(fs.combine(shell.dir(), args[0]), "r")

                  local env = _G
                  env.args = args

                  running = coroutine.create(load(file.readAll(), v, "t", env))

                  coroutine.resume(running)

                  args = {[0] = ""}
                  goto continue
               end
            end

            if args[0] ~= "" then
               vars["?"] = 127
               local color = term.getTextColor()
               term.setTextColor(colors.red)
               print("Command " .. args[0] .. " not found.")
               term.setTextColor(color)
               args = {[0] = ""}
            end
            term.write(vars.PS1)
            cols = {[0] = 2}
         end
      elseif importantKeys.backspace[eventData[1]] then
         local x, y = term.getCursorPos()
         x = x - 1

         if x == 0 then
            y = y - 1

            if y == 0 then
               y = 1
               x = 1
            else
               x = cols[#cols - 1]
               cols[#cols] = nil

               if cols[0] < 2 then
                  cols[0] = 2
               end
            end
         end

         term.setCursorPos(x, y)
         term.write(" ")
         term.setCursorPos(x, y)

         if not escaped then
            if args[#args] == "" then
               args[#args] = nil

               if not args[0] then
                  term.write(" ")
                  args[0] = ""
               end
            else
               args[#args] = args[#args]:gsub(".$", "")
            end
         else
            escaped = false
         end
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

      if char == "\\" and not escaped and not strictquote then
         escaped = true
         unescape = false
         cols[#cols] = cols[#cols] + #char

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

