local M = {}

M.is_html5 = html5 ~= nil and sys.get_sys_info().system_name == "HTML5"
M.lines = {}
M.order = {}

local function js_string(s)
	s = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", "")
	return "\"" .. s .. "\""
end
M.js_string = js_string

function M.js(code)
	if M.is_html5 then
		return html5.run(code)
	end
end

function M.install()
	if not M.is_html5 then return end
	M.js([==[(function(){
if (window.spikeUI) return 'x';
var d=document.createElement('div');
d.style.cssText='position:fixed;top:0;left:0;right:0;z-index:10;font:10px/1.2 monospace;color:#fff;background:rgba(0,0,0,.6);padding:4px 6px;pointer-events:none';
var p=document.createElement('pre'); p.id='spikestats'; p.style.cssText='margin:0;white-space:pre-wrap'; d.appendChild(p);
var b=document.createElement('div'); b.style.cssText='pointer-events:auto;margin-top:3px';
[['bench sub','bench:sub'],['bench full','bench:full'],['tap=sub','mode:sub'],['tap=full','mode:full'],['reset','reset'],['2048','size:2048'],['3072','size:3072'],['echo','echo'],['hide','hide']].forEach(function(x){
 var e=document.createElement('button'); e.textContent=x[0]; e.style.cssText='font:11px monospace;margin:1px;padding:5px 6px';
 e.onclick=function(ev){ev.stopPropagation(); if(x[1]==='hide'){var q=document.getElementById('spikestats'); q.style.display=q.style.display==='none'?'':'none'; return;} if(x[1].indexOf('size:')===0){var u=new URL(location.href);u.searchParams.set('size',x[1].slice(5));location.href=u.toString();} else {window.spikeCmd=x[1];}};
 b.appendChild(e);});
d.appendChild(b); document.body.appendChild(d);
window.spikeUI=1; window.spikeCmd=''; window.spikeLog=[];
return 'ok';})()]==])
end

function M.param(name, default)
	if M.is_html5 then
		local v = M.js("new URL(location.href).searchParams.get(" .. js_string(name) .. ")||''")
		if v and v ~= "" then return v end
	end
	return sys.get_config_string("spike." .. name, default)
end

function M.poll_cmd()
	if not M.is_html5 then return nil end
	local c = M.js("(function(){var c=window.spikeCmd||'';window.spikeCmd='';return c;})()")
	if c and c ~= "" then return c end
	return nil
end

function M.set(key, text)
	if not M.lines[key] then
		M.order[#M.order + 1] = key
	end
	M.lines[key] = text
	M.dirty = true
end

function M.flush()
	if not M.dirty then return end
	M.dirty = false
	local out = {}
	for _, k in ipairs(M.order) do
		out[#out + 1] = M.lines[k]
	end
	local text = table.concat(out, "\n")
	if M.is_html5 then
		M.js("document.getElementById('spikestats').textContent=" .. js_string(text))
	end
end

function M.publish(name, jsontext)
	if M.is_html5 then
		M.js("window." .. name .. "=" .. jsontext .. ";0")
	end
	print("SPIKE " .. name .. " " .. jsontext)
end

return M
