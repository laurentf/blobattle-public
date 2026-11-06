local M = {}

M.BASE = 3
M.TIP = 4.2
M.Z = 4
M.RATE = 30
M.LIFE = 0.35
M.SPREAD = 1.8
M.RISE = 2.4
M.SIZE = 0.5

function M.new(random)
  return { list = {}, spare = {}, due = 0, random = random or math.random }
end

function M.step(f, dt)
  local list, spare, kept = f.list, f.spare, 0
  for i = 1, #list do
    local spark = list[i]
    spark.age = spark.age + dt
    if spark.age < spark.life then
      kept = kept + 1
      list[kept] = spark
    else
      spare[#spare + 1] = spark
    end
  end
  for i = #list, kept + 1, -1 do
    list[i] = nil
  end
  f.due = f.due + dt * M.RATE
  while f.due >= 1 do
    f.due = f.due - 1
    local spark = table.remove(spare) or {}
    spark.age = 0
    spark.life = M.LIFE * (0.6 + 0.4 * f.random())
    spark.dx = 2 * f.random() - 1
    spark.colour = spark.colour or (f.random() < 0.5 and 1 or 2)
    list[#list + 1] = spark
  end
end

function M.shape(spark, out)
  out = out or {}
  local k = spark.age / spark.life
  out.x = spark.dx * M.SPREAD * k
  out.y = M.RISE * k * (1.4 - k)
  out.size = M.SIZE * (1 - k)
  return out
end

return M
