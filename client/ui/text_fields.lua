local M = {}

local SETUP = [[
(function () {
  if (window.blobattleFields) return 'ready';
  var canvas = document.querySelector('canvas');
  var fields = {};
  var changes = [];
  function element(id) {
    var e = fields[id];
    if (e) return e;
    e = document.createElement('input');
    e.id = 'blobattle-field-' + id;
    e.type = 'text';
    e.autocomplete = 'off';
    e.spellcheck = false;
    e.style.position = 'fixed';
    e.style.zIndex = 10;
    e.style.border = '0';
    e.style.outline = 'none';
    e.style.background = 'transparent';
    e.style.textAlign = 'center';
    e.style.padding = '0';
    e.style.margin = '0';
    e.style.fontFamily = "'Fredoka One', ui-rounded, 'Arial Rounded MT Bold', sans-serif";
    e.style.fontWeight = 'bold';
    e.addEventListener('keydown', function (k) { if (k.key === 'Enter') e.blur(); });
    e.addEventListener('change', function () { changes.push(id + '\t' + e.value); });
    document.body.appendChild(e);
    fields[id] = e;
    return e;
  }
  window.blobattleFields = {
    place: function (id, x, y, w, h, value, max, colour) {
      var e = element(id);
      var r = canvas.getBoundingClientRect();
      var sx = r.width / canvas.width, sy = r.height / canvas.height;
      e.style.left = (r.left + (x - w / 2) * sx) + 'px';
      e.style.top = (r.top + (canvas.height - y - h / 2) * sy) + 'px';
      e.style.width = (w * sx) + 'px';
      e.style.height = (h * sy) + 'px';
      e.style.fontSize = Math.round(h * sy * 0.42) + 'px';
      e.style.color = colour;
      e.maxLength = max;
      if (document.activeElement !== e) e.value = value;
      e.style.display = 'block';
    },
    poll: function () { return changes.length ? changes.shift() : ''; },
    blur: function () {
      var active = document.activeElement;
      for (var id in fields) { if (fields[id] === active) active.blur(); }
    },
    hide: function () {
      for (var id in fields) { fields[id].blur(); fields[id].style.display = 'none'; }
    },
  };
  return 'ready';
})()
]]

local function css_colour(rgb)
  return string.format(
    "rgb(%d,%d,%d)",
    math.floor(rgb[1] * 255),
    math.floor(rgb[2] * 255),
    math.floor(rgb[3] * 255)
  )
end

function M.available()
  return html5 ~= nil
end

function M.setup()
  if html5 then
    html5.run(SETUP)
  end
end

function M.place(id, node, fields)
  if not html5 then
    return
  end
  local p = gui.get_screen_position(node)
  local size = gui.get_size(node)
  local scale = gui.get_scale(node)
  local ratio = fields.scale
  html5.run(
    string.format(
      "window.blobattleFields.place(%s,%f,%f,%f,%f,%s,%d,%s)",
      json.encode(id),
      p.x,
      p.y,
      size.x * scale.x * ratio,
      size.y * scale.y * ratio,
      json.encode(fields.value or ""),
      fields.max,
      json.encode(css_colour(fields.colour))
    )
  )
end

function M.poll()
  if not html5 then
    return nil
  end
  local change = html5.run("window.blobattleFields ? window.blobattleFields.poll() : ''")
  if change == nil or change == "" then
    return nil
  end
  local id, value = change:match("^([^\t]+)\t(.*)$")
  return id, value
end

function M.blur()
  if html5 then
    html5.run("window.blobattleFields && window.blobattleFields.blur()")
  end
end

function M.hide()
  if html5 then
    html5.run("window.blobattleFields && window.blobattleFields.hide()")
  end
end

return M
