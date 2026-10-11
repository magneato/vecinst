-- test/harness.lua - drive VecNIST in MAME's vectrex driver: scripted buttons, joystick and light pen, snapshots,
-- memory pokes and reads, and a batch mode that feeds the cartridge grids or strokes and reads back its answers.
-- Configured through environment variables (frames are emulated 50 Hz frames):
--   SHOTS="300 400"                snapshot at these frames
--   BTN="200-260:1,300-305:3"      hold joystick 1 button n (1-4) for a frame range
--   STICK="200-260:255:128"        hold the analog stick at x:y (0..255, 128 = centre) for a frame range
--   LPEN="200-300:x0:y0:x1:y1"     light pen pressed, moving linearly from (x0,y0) to (x1,y1) over the range, in
--                                  Vectrex screen units (signed; the pen locks on to its patch, so start it there)
--   LPENCONF=1                     light pen port setting (0 off, 1 / 2 / 3)
--   BATCH=/path/in.txt             lines "G <48 hex digits>" (a grid) or "P <npts> <hex y,x pairs>" (strokes):
--                                  each is poked in, test_cmd set, and the answer printed as "ANS <result> <out hex>"
--   BATCH_FROM=150                 frame of the first batch item
--   PEEK="300:C888:2,400:C884:1"   print "PEEK frame addr bytes" at those frames
--   EXITAT=500                     quit at this frame
local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]
local ports = manager.machine.ioport.ports
local function fld(port, name) return ports[port].fields[name] end

-- addresses (ram.i)
local A = { npts = 0xC884, result = 0xC88A, test_cmd = 0xC88B, grid = 0xC8B6, out = 0xC98E, pts = 0xC9AC, mode = 0xC886 }

local function ranges(spec, pat)
  local r = {}
  for a in string.gmatch(spec or "", "[^,]+") do
    local t = {}
    for v in string.gmatch(a, "[^:%-]+") do t[#t + 1] = tonumber(v) end
    r[#r + 1] = t
  end
  return r
end
local btn = ranges(os.getenv("BTN"))
local stick = ranges(os.getenv("STICK"))
local lpen = {}
for a, b, x0, y0, x1, y1 in string.gmatch(os.getenv("LPEN") or "", "(%d+)%-(%d+):(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+)") do
  lpen[#lpen + 1] = {tonumber(a), tonumber(b), tonumber(x0), tonumber(y0), tonumber(x1), tonumber(y1)}
end
local shots = {}
for f in string.gmatch(os.getenv("SHOTS") or "", "%d+") do shots[tonumber(f)] = true end
local exitat = tonumber(os.getenv("EXITAT") or "0")
local batch = {}
if os.getenv("BATCH") then for l in io.lines(os.getenv("BATCH")) do batch[#batch + 1] = l end end
local batch_from = tonumber(os.getenv("BATCH_FROM") or "150")
local bi, waiting = 1, false
local lpconf = tonumber(os.getenv("LPENCONF") or "-1")
LPX = tonumber(os.getenv("LPEN_SX") or "1.10")      -- screen units per pen step, x and y (measured)
LPY = tonumber(os.getenv("LPEN_SY") or "1.44")
local peeks = {}
for f, a, n in string.gmatch(os.getenv("PEEK") or "", "(%d+):(%x+):(%d+)") do
  peeks[#peeks + 1] = {tonumber(f), tonumber(a, 16), tonumber(n)}
end

local function hexbytes(s) local t = {} for h in string.gmatch(s, "%x%x") do t[#t + 1] = tonumber(h, 16) end return t end

local frame = 0
_G.h = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  if lpconf >= 0 then fld(":LPENCONF", "Lightpen"):set_value(lpconf) end
  for b = 1, 4 do
    local down = 0
    for _, r in ipairs(btn) do if frame >= r[1] and frame <= r[2] and r[3] == b then down = 1 end end
    fld(":BUTTONS", "P1 Button " .. b):set_value(down)
  end
  local sx, sy = 128, 128
  for _, r in ipairs(stick) do if frame >= r[1] and frame <= r[2] then sx, sy = r[3], r[4] end end
  fld(":CONTR1X", "AD Stick X"):set_value(sx)
  fld(":CONTR1Y", "AD Stick Y"):set_value(sy)
  local pen = 0
  for _, r in ipairs(lpen) do
    if frame >= r[1] and frame <= r[2] then
      local t = (frame - r[1]) / math.max(1, r[2] - r[1])
      -- the path is in Vectrex screen units; MAME's pen ports are crossed (the screen is rotated) and scaled:
      -- measured, screen x = (LPENY - 128) x 1.10 and screen y = (LPENX - 128) x 1.44
      local x = r[3] + (r[5] - r[3]) * t
      local y = r[4] + (r[6] - r[4]) * t
      if os.getenv("LPENRAW") then          -- raw port values: x -> LPENY, y -> LPENX
        fld(":LPENY", "Lightgun X"):set_value(math.floor(x)); fld(":LPENX", "Lightgun Y"):set_value(math.floor(y))
      else
        fld(":LPENY", "Lightgun X"):set_value(math.max(0, math.min(255, math.floor(128 + x / LPX + 0.5))))
        fld(":LPENX", "Lightgun Y"):set_value(math.max(0, math.min(255, math.floor(128 + y / LPY + 0.5))))
      end
      pen = 1
    end
  end
  fld(":LPENCONF", "P1 Button 5"):set_value(pen)
  if os.getenv("LPENDBG") and frame % 20 == 0 then
    print(string.format("LPENDBG frame=%d LPENX=%d LPENY=%d CONF=%d", frame, ports[":LPENX"]:read(), ports[":LPENY"]:read(), ports[":LPENCONF"]:read()))
  end
  -- batch: one item per few frames; the cartridge clears test_cmd when it has answered
  if #batch > 0 and frame >= batch_from then
    if waiting then
      if mem:read_u8(A.test_cmd) == 0 then
        local o = ""
        for i = 0, 29 do o = o .. string.format("%02X", mem:read_u8(A.out + i)) end
        print(string.format("ANS %d %s", mem:read_u8(A.result), o))
        if os.getenv("BATCH_GRID") then
          local g = ""
          for i = 0, 23 do g = g .. string.format("%02X", mem:read_u8(A.grid + i)) end
          print("GRID " .. g)
        end
        waiting, bi = false, bi + 1
      end
    elseif bi <= #batch then
      local l = batch[bi]
      local kind, rest = l:match("^(%a) (.*)$")
      if kind == "G" then
        local b = hexbytes(rest)
        for i = 1, 24 do mem:write_u8(A.grid + i - 1, b[i]) end
        mem:write_u8(A.test_cmd, 1)
      else
        local n, hx = rest:match("^(%d+) (%x*)$")
        local b = hexbytes(hx)
        for i = 1, #b do mem:write_u8(A.pts + i - 1, b[i]) end
        mem:write_u8(A.npts, tonumber(n))
        mem:write_u8(A.test_cmd, 2)
      end
      waiting = true
    elseif bi == #batch + 1 then
      print("BATCH done")
      bi = bi + 1
      if exitat == 0 then manager.machine:exit() end
    end
  end
  for _, p in ipairs(peeks) do
    if p[1] == frame then
      local t = ""
      for i = 0, p[3] - 1 do t = t .. string.format("%02X", mem:read_u8(p[2] + i)) end
      print(string.format("PEEK %d %04X %s", frame, p[2], t))
    end
  end
  if shots[frame] then
    print(string.format("SHOT frame=%d npts=%d result=%d mode=%d", frame, mem:read_u8(A.npts), mem:read_u8(A.result), mem:read_u8(A.mode)))
    manager.machine.video:snapshot()
  end
  if exitat > 0 and frame >= exitat then manager.machine:exit() end
end)
