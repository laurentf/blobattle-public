std = "lua51"
max_line_length = 100
codes = true
color = false

include_files = { "**/*.lua", "**/*.script", "**/*.gui_script" }

exclude_files = {
  "docs/**",
  "spec/support/fixtures/**",
  "client/shared/**",
  "client/build/**",
  "client/.internal/**",
  "out/**",
  "tmp/**",
}

files["spec"] = { std = "+busted", read_globals = { "jit" } }

local defold = {
  "buffer",
  "camera",
  "collectionproxy",
  "factory",
  "go",
  "graphics",
  "gui",
  "hash",
  "html5",
  "json",
  "msg",
  "render",
  "resource",
  "socket",
  "sys",
  "timer",
  "vmath",
  "websocket",
  "window",
}

files["client"] = { read_globals = defold }
files["client/**/*.script"] = {
  read_globals = defold,
  globals = { "init", "final", "update", "on_message", "on_input" },
}
files["client/**/*.gui_script"] = {
  read_globals = defold,
  globals = { "init", "final", "update", "on_message", "on_input" },
}
