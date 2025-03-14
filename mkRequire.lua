local function mkRequire()
end

return function()
   local package = {
   }

   return mkRequire(), package
end

