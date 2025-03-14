local function preload(package)
   return function(name)
      if package.preload[name] then
         return package.preload[name]
      else
         return nil, "no field package.preload['" .. name .. "']"
      end
   end
end

local function fromFile(package, env)
   return function(name)
      local path, err = package.searchpath(name, package.path)

      if not path then
         error(err)
      end

      local file = assert(loadfile(path, nil, env))

      return file, path
   end
end


local function mkSearchPath(dir)
   return function(name, path)
      local fileName = name:gsub("%.", "/")
      local err = ""

      for pattern in path:gmatch("[^;]+") do
         local trueFileName = pattern:gsub("%?", fileName)
         if not trueFileName:match("^/") then
            trueFileName = "/" .. fs.combine(dir, trueFileName)
         end

         if fs.exists(trueFileName) and not fs.isDir(trueFileName) then
            return trueFileName
         else
            err = err .. "File " .. trueFileName:gsub("^/", ""):gsub("/", ".") .. " does not exist."
         end
      end

      error(err)
   end
end

local function mkRequire(package)
   local sentinel = {}

   local function loadWithLoader(loader, name)
      if loader[1] then
         package.loaded[name] = sentinel
         local result = loader[1](name, table.unpack(loader, 2, loader.n))

         if result == nil then
            result = true
         end

         package.loaded[name] = result
         return result
      else
         return nil, loader[2]
      end
   end

   return function(name)
      if package.loaded[name] == sentinel then
         error("Infinite loop or previous error loading module " .. name .. ".")
      end

      if package.loaded[name] then
         return package.loaded[name]
      end

      local err = ""
      for _, searcher in ipairs(package.loaders) do
         local loader = table.pack(searcher(name))

         local result, error = loadWithLoader(loader, name)

         if not result then
            err = err .. "\n"
         else
            return result
         end
      end

      error(err)
   end
end

local function mkPackage(env, dir)
   local package = {}
   package.loaded = {
      _G = _G,
      package = package
   }

   local registry = debug.getregistry()
   if registry and type(registry._LOADED) == "table" then
      for k, v in pairs(registry._LOADED) do
         if type(k) == "string" then
            package.loaded[k] = v
         end
      end
   end

   package.path = "?;?.lua;?/init.lua" ..
      ";/rom/modules/main/?;/rom/modules/main/?.lua;/rom/modules/main/?/init.lua" ..
      (turtle and ";/rom/modules/turtle/?;/rom/modules/turtle/?.lua;/rom/modules/turtle/?/init.lua" or "") ..
      (commands and ";/rom/modules/command/?;/rom/modules/command/?.lua;/rom/modules/command/?/init.lua" or "")

   package.config = "/\n;\n?\n!\n-"

   package.preload = {}
   package.loaders = { preload(package), fromFile(package, env) }
   package.searchpath = mkSearchPath(dir)

   return package
end

return function(env, dir)
   local package = mkPackage(env, dir)

   return mkRequire(package), package
end

