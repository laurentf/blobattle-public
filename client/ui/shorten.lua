local M = {}

function M.fit(fields)
  local text, max, width, mark = fields.text, fields.max, fields.width, fields.mark
  if width(text) <= max then
    return text
  end
  for keep = #text - 1, 1, -1 do
    local head = text:sub(1, keep):gsub(" +$", "")
    local cut = head .. mark
    if width(cut) <= max or keep == 1 then
      return cut
    end
  end
  return text:sub(1, 1) .. mark
end

return M
