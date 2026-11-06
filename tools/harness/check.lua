package.path = "./?.lua;./tools/?.lua;" .. package.path

local json = require("dkjson")
local replay = require("tools.harness.replay")

local file = assert(io.open(arg[1], "rb"))
local recording = json.decode(file:read("*a"))
file:close()
local report = replay.check(recording)
local luajit = rawget(_G, "jit")
local engine = luajit and luajit.version or _VERSION
for _, err in ipairs(report.errors) do
  print("❌ " .. err)
end
print(
  string.format(
    "🧮 %s: %d checksums, %d snapshots, %d inputs, %d ticks, %d errors",
    engine,
    report.checksums,
    report.snapshots,
    report.inputs,
    report.final_tick,
    #report.errors
  )
)
os.exit(#report.errors == 0 and #recording.checksums == report.checksums and 0 or 1)
