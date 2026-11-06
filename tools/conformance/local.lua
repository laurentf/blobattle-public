package.path = "./?.lua;./tools/?.lua;./spec/?.lua;" .. package.path

local runner = require("conformance.runner")

local vector = require("vectors." .. arg[1])
local sums, names
if arg[2] == "expected" then
  sums = assert(vector.expected, vector.name .. " has no recorded sums")
  names = assert(vector.names, vector.name .. " has no recorded names")
else
  sums, names = runner.run(vector), runner.names(vector)
end
for _, sum in ipairs(sums) do
  print(sum.tick .. " " .. sum.a .. " " .. sum.b)
end
for _, line in ipairs(runner.name_lines(names)) do
  print(line)
end
