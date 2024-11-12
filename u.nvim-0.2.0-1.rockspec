package = "u.nvim"
version = "0.2.0-1"
source = {
   url = "git+https://github.com/jrop/u.nvim"
}
description = {
   summary = "nvim – a powerful Lua library designed to enhance your text manipulation experience in NeoVim, focusing primarily on a context-aware \"Range\" utility.",
   detailed = "Welcome to u.nvim – a powerful Lua library designed to enhance your text manipulation experience in NeoVim, focusing primarily on a context-aware \"Range\" utility. This utility allows you to work efficiently with text selections based on various conditions, in a variety of contexts, making coding and editing more intuitive and productive.",
   homepage = "https://github.com/jrop/u.nvim",
   license = "MIT"
}
build = {
   type = "builtin",
   modules = {
      ["u.buffer"] = "lua/u/buffer.lua",
      ["u.codewriter"] = "lua/u/codewriter.lua",
      ["u.opkeymap"] = "lua/u/opkeymap.lua",
      ["u.pos"] = "lua/u/pos.lua",
      ["u.range"] = "lua/u/range.lua",
      ["u.repeat"] = "lua/u/repeat.lua",
      ["u.state"] = "lua/u/state.lua",
      ["u.utils"] = "lua/u/utils.lua"
   }
}
