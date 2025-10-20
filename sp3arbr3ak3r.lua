--[[
Guide (minimal)
ESP [Ctrl+E] — player outlines + nametags. Nearest = pink. Names scale by distance.
Br3ak3r [Ctrl+Enter + Ctrl+LMB] — hide a single part; Ctrl+Z undo (max 20 recent). Hover preview while Ctrl held.
AutoClick [Ctrl+K] — click only when cursor hits a non-local player.
Sky Mode [Ctrl+L] — toggle bright daytime sky (client-only).
Waypoints [Ctrl+MMB] — add/remove at cursor. Hebrew NATO names + unique colors. Persist after shutdown.
Killswitch [Ctrl+6] — full cleanup (UI, outlines, indicators, sky, connections). Waypoints persist.
]]

-- Sp3arBr3ak3r-1.12bLite [OPTIMIZED]

-- ============================================================
-- PERFORMANCE OPTIMIZATIONS:
-- • Local caching of frequently-used globals (math, table, etc.)
-- • RaycastParams reuse instead of recreation
-- • Reduced function calls in hot paths
-- • Optimized table operations
-- • Cached property lookups
-- • Reduced closure overhead
-- ============================================================

-- Local cache of frequently used globals for performance
local abs, floor, max, min, clamp = math.abs, math.floor, math.max, math.min, math.clamp
local deg, atan2 = math.deg, math.atan2
local insert, remove, clear = table.insert, table.remove, table.clear
local huge = math.huge

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local hasVIM, VirtualInputManager = pcall(function() return game:GetService("VirtualInputManager") end)

-- Config / Defaults
local ESP_ENABLED = true
local CLICKBREAK_ENABLED = true      -- shown as "Br3ak3r" in UI
local AUTOCLICK_ENABLED = false
local SKY_MODE_ENABLED = false
local PREDICTION_VECTORS_ENABLED = true
local TARGETING_ASSIST_ENABLED = false
local PROXIMITY_ALERTS_ENABLED = true
local PREDICTION_ZONES_ENABLED = true

local AUTOCLICK_CPS = 25
local AUTOCLICK_INTERVAL = 1 / AUTOCLICK_CPS
local RAYCAST_MAX_DISTANCE = 3000
local UNDO_LIMIT = 25

-- Visuals (cached Color3 constants)
local PINK  = Color3.fromRGB(255,105,180)
local RED   = Color3.fromRGB(255,0,0)
local GREEN = Color3.fromRGB(0,200,0)
local WHITE = Color3.fromRGB(255,255,255)
local GRAY  = Color3.fromRGB(200,200,200)
local CYAN  = Color3.fromRGB(0,255,255)
local YELLOW = Color3.fromRGB(255,255,0)
local ORANGE = Color3.fromRGB(255,165,0)

-- Distance-based color gradient (for nametags)
local CLOSEST_COLOR = Color3.fromRGB(255, 20, 20)  -- Bright red for closest player
local GRADIENT_MIN_DIST = 30   -- Distance where gradient starts (close = warmer)
local GRADIENT_MAX_DIST = 250  -- Distance where gradient ends (far = cooler)

-- Additional UI colors (cached)
local BG_DARK = Color3.fromRGB(15,15,15)
local BG_INDICATOR = Color3.fromRGB(20,20,20)
local TEXT_LIGHT = Color3.fromRGB(210,210,210)
local TEXT_LIGHTER = Color3.fromRGB(220,220,220)
local TEXT_GRAY = Color3.fromRGB(200,200,200)
local DOT_RED = Color3.fromRGB(200,0,0)
local DOT_GREEN = Color3.fromRGB(0,200,0)
local SEPARATOR_GRAY = Color3.fromRGB(60,60,60)

-- Name tag and indicator sizing
local NAME_BASE_W, NAME_BASE_H = 120, 28
local NAME_MIN_SCALE, NAME_MAX_SCALE = 0.45, 2.6
local NAME_DIST_REF = 120
local EDGE_MARGIN = 24
local INDICATOR_SIZE = Vector2.new(110, 22)
local INDICATOR_SIZE_HALF = Vector2.new(55, 11)  -- Cached half for positioning

-- Waypoint Hebrew NATO names and colors
local HEBREW_NATO = {
	"אלפא","בראבו","צ'רלי","דלתא","אקו","פוקסטרוט","גולף","הוטל","אינדיה","ז'ולייט",
	"קילו","לימה","מייק","נובמבר","אוסקר","פאפא","קוויבק","רומיאו","סיירה","טנגו",
	"יוניפורם","ויקטור","וויסקי","אקס-ריי","יאנקי","זולו"
}
local NATO_COLORS = {
	Color3.fromRGB(255,99,132), Color3.fromRGB(54,162,235), Color3.fromRGB(255,206,86),
	Color3.fromRGB(75,192,192), Color3.fromRGB(153,102,255), Color3.fromRGB(255,159,64),
	Color3.fromRGB(233,30,99),  Color3.fromRGB(0,188,212),  Color3.fromRGB(205,220,57),
	Color3.fromRGB(124,179,66), Color3.fromRGB(255,87,34),  Color3.fromRGB(63,81,181),
	Color3.fromRGB(0,150,136),  Color3.fromRGB(244,67,54),  Color3.fromRGB(121,85,72),
	Color3.fromRGB(158,158,158),Color3.fromRGB(3,169,244),  Color3.fromRGB(139,195,74),
	Color3.fromRGB(156,39,176), Color3.fromRGB(255,193,7),  Color3.fromRGB(96,125,139),
	Color3.fromRGB(0,230,118),  Color3.fromRGB(186,104,200),Color3.fromRGB(255,112,67),
	Color3.fromRGB(33,150,243), Color3.fromRGB(255,235,59)
}

-- State
local localPlayer = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local created, binds = {}, {}
local perPlayer = {}   -- [Player] = {bill, text, hum, outline, indicator, cache}
local brokenSet = {}   -- [BasePart] = true
local brokenIgnoreCache, scratchIgnore = {}, {}
local brokenCacheDirty = true
local undoStack = {}   -- LIFO of {part, cc, ltm, t}
local nearestPlayerRef = nil
local screenGui
local dead = false

-- Waypoints UI/State
local guideFrame, wpScroll, wpList
local wpRowMap = {}       -- [Part] = TextLabel
local wpIndicatorMap = {} -- [Part] = Frame
local wpNameIndex = 0
local indicatorFolder

-- Toggle UI setters
local setDotESP, setDotCB, setDotAC, setDotSKY, setDotPV, setDotTA, setDotPA, setDotPZ

-- Hover highlight (Br3ak3r)
local hoverHL

-- Sky backup/injected
local skyBackupFolder, skyInjected, atmosInjected

-- Reusable RaycastParams (performance optimization)
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.IgnoreWater = true

-- Cached format strings for performance
local FORMAT_NAME_DIST_HP = "%s  •  %dm  •  %dhp"
local FORMAT_NAME_DIST = "%s · %dm"
local FORMAT_NAME_DIST_TOOL_HP = "%s [%s]  •  %dm  •  %dhp"
local FORMAT_NAME_DIST_TOOL = "%s [%s] · %dm"

-- Custom clamp for Lua 5.1 compatibility (if needed)
local function customClamp(v, lo, hi)
	if v < lo then return lo
	elseif v > hi then return hi
	else return v end
end

-- Color gradient function for distance-based nametag colors
-- Creates a smooth heat-map style gradient from blue (far) to red (close)
local function getDistanceColor(distance)
	-- Clamp distance to gradient range
	local t = customClamp((distance - GRADIENT_MIN_DIST) / (GRADIENT_MAX_DIST - GRADIENT_MIN_DIST), 0, 1)

	-- Heat map gradient with multiple color stops:
	-- Far = Dark blue -> Cyan -> Green -> Yellow -> Orange -> Red = Close
	if t > 0.83 then  -- Very far: dark blue to blue
		local localT = (t - 0.83) / 0.17
		return Color3.new(
			0.0 + localT * 0.1,
			0.2 + localT * 0.3,
			0.6 + localT * 0.3
		)
	elseif t > 0.66 then  -- Far: blue to cyan
		local localT = (t - 0.66) / 0.17
		return Color3.new(
			0.1 + localT * 0.0,
			0.5 + localT * 0.3,
			0.9 + localT * (-0.3)
		)
	elseif t > 0.5 then  -- Mid-far: cyan to green
		local localT = (t - 0.5) / 0.16
		return Color3.new(
			0.1 + localT * 0.1,
			0.8 + localT * 0.0,
			0.6 + localT * (-0.3)
		)
	elseif t > 0.33 then  -- Mid: green to yellow
		local localT = (t - 0.33) / 0.17
		return Color3.new(
			0.2 + localT * 0.6,
			0.8 + localT * 0.2,
			0.3 + localT * (-0.3)
		)
	elseif t > 0.16 then  -- Mid-close: yellow to orange
		local localT = (t - 0.16) / 0.17
		return Color3.new(
			0.8 + localT * 0.2,
			1.0 + localT * (-0.35),
			0.0 + localT * 0.0
		)
	else  -- Close: orange to red-orange
		local localT = t / 0.16
		return Color3.new(
			1.0,
			0.65 + localT * (-0.45),
			0.0
		)
	end
end

-- Helpers
local function track(i) created[#created+1] = i; return i end
local function bind(c) binds[#binds+1] = c; return c end
local function disconnectAll()
	for i = 1, #binds do
		pcall(function() binds[i]:Disconnect() end)
	end
	clear(binds)
end
local function destroyAll()
	for i = 1, #created do
		pcall(function() created[i]:Destroy() end)
	end
	clear(created)
end
local function safeDestroy(x) if x then pcall(function() x:Destroy() end) end end

local function extendArray(target, source)
	local offset = #target
	local sourceLen = #source
	for i = 1, sourceLen do
		target[offset + i] = source[i]
	end
end

local function makeIntervalRunner(interval)
	local acc = 0
	return function(dt)
		acc = acc + dt
		if acc >= interval then
			acc = acc - interval
			return true
		end
		return false
	end
end

local function rebuildBrokenIgnore()
	if not next(brokenSet) then
		clear(brokenIgnoreCache)
		brokenCacheDirty = false
		return
	end
	clear(brokenIgnoreCache)
	local cacheIndex = 1
	for part,_ in pairs(brokenSet) do
		if part and part:IsDescendantOf(Workspace) then
			brokenIgnoreCache[cacheIndex] = part
			cacheIndex = cacheIndex + 1
		end
	end
	brokenCacheDirty = false
end

-- GUI root
do
	screenGui = track(Instance.new("ScreenGui"))
	screenGui.Name = "G"..HttpService:GenerateGUID(false):gsub("-","")
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 999999
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = (localPlayer:FindFirstChildOfClass("PlayerGui") or localPlayer:WaitForChild("PlayerGui"))

	indicatorFolder = track(Instance.new("Folder"))
	indicatorFolder.Name = "SB3_Indicators"
	indicatorFolder.Parent = screenGui
end

-- Guide UI
local function mkToggleRow(label, keybind)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1,0,0,16)
	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.Size = UDim2.fromOffset(10,10)
	dot.Position = UDim2.new(0,0,0.5,-5)
	dot.BackgroundColor3 = DOT_RED
	dot.BorderSizePixel = 0
	dot.Parent = row
	local dc = Instance.new("UICorner"); dc.CornerRadius = UDim.new(1,0); dc.Parent = dot
	local txt = Instance.new("TextLabel")
	txt.BackgroundTransparency = 1
	txt.Position = UDim2.new(0,16,0,-2)
	txt.Size = UDim2.new(1,-16,1,0)
	txt.TextXAlignment = Enum.TextXAlignment.Left
	txt.TextYAlignment = Enum.TextYAlignment.Top
	txt.Font = Enum.Font.Gotham
	txt.TextSize = 12
	txt.TextColor3 = TEXT_LIGHT
	txt.Text = label.."  ["..keybind.."]"
	txt.Parent = row
	return row, function(active) dot.BackgroundColor3 = active and DOT_GREEN or DOT_RED end
end

local function ensureGuide()
	if guideFrame and guideFrame.Parent then return end
	guideFrame = track(Instance.new("Frame"))
	guideFrame.Name = "SB3_Guide"
	guideFrame.AnchorPoint = Vector2.new(0,0.5)
	guideFrame.Position = UDim2.fromScale(0.015, 0.5)
	guideFrame.Size = UDim2.fromOffset(290, 270)
	guideFrame.BackgroundColor3 = BG_DARK
	guideFrame.BackgroundTransparency = 0.25
	guideFrame.BorderSizePixel = 0
	guideFrame.ZIndex = 1000
	guideFrame.Parent = screenGui

	do
		local pad = Instance.new("UIPadding"); pad.PaddingTop=UDim.new(0,8); pad.PaddingBottom=UDim.new(0,8); pad.PaddingLeft=UDim.new(0,10); pad.PaddingRight=UDim.new(0,10); pad.Parent=guideFrame
		local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,10); corner.Parent = guideFrame

		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Size = UDim2.fromOffset(0,18)
		title.Text = "Sp3arBr3ak3r 1.12bLITE [OPT]"
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextYAlignment = Enum.TextYAlignment.Top
		title.Font = Enum.Font.GothamBold
		title.TextSize = 14
		title.TextColor3 = TEXT_LIGHTER
		title.ZIndex = 1001
		title.Parent = guideFrame

		local togglesSection = track(Instance.new("Frame"))
		togglesSection.BackgroundTransparency = 1
		togglesSection.Position = UDim2.new(0,0,0,22)
		togglesSection.Size = UDim2.new(1,0,0,160)
		togglesSection.Parent = guideFrame

		local list = track(Instance.new("UIListLayout")); list.FillDirection=Enum.FillDirection.Vertical; list.SortOrder=Enum.SortOrder.LayoutOrder; list.Padding=UDim.new(0,2); list.Parent=togglesSection

		local r1, s1 = mkToggleRow("ESP","Ctrl+E"); r1.Parent = togglesSection; setDotESP = s1
		local r2, s2 = mkToggleRow("Br3ak3r","Ctrl+Enter"); r2.Parent = togglesSection; setDotCB = s2
		local r3, s3 = mkToggleRow("AutoClick","Ctrl+K"); r3.Parent = togglesSection; setDotAC = s3
		local r4, s4 = mkToggleRow("Sky Mode","Ctrl+L"); r4.Parent = togglesSection; setDotSKY = s4
		local r5, s5 = mkToggleRow("PredVectors","Ctrl+V"); r5.Parent = togglesSection; setDotPV = s5
		local r6, s6 = mkToggleRow("TargetAssist","Ctrl+T"); r6.Parent = togglesSection; setDotTA = s6
		local r7, s7 = mkToggleRow("ProxAlerts","Ctrl+A"); r7.Parent = togglesSection; setDotPA = s7
		local r8, s8 = mkToggleRow("PredZones","Ctrl+P"); r8.Parent = togglesSection; setDotPZ = s8

		local sep = track(Instance.new("Frame")); sep.Size=UDim2.new(1,0,0,1); sep.Position=UDim2.new(0,0,0,22+160+6); sep.BackgroundColor3=SEPARATOR_GRAY; sep.BorderSizePixel=0; sep.Parent=guideFrame

		local listTitle = Instance.new("TextLabel")
		listTitle.BackgroundTransparency = 1
		listTitle.Position = UDim2.new(0,0,0,22+160+10)
		listTitle.Size = UDim2.new(1,0,0,16)
		listTitle.Text = "Waypoints:"
		listTitle.TextColor3 = TEXT_GRAY
		listTitle.TextXAlignment = Enum.TextXAlignment.Left
		listTitle.Font = Enum.Font.GothamSemibold
		listTitle.TextSize = 12
		listTitle.ZIndex = 1001
		listTitle.Parent = guideFrame

		wpScroll = track(Instance.new("ScrollingFrame"))
		wpScroll.Name = "WPScroll"
		wpScroll.BackgroundTransparency = 1
		wpScroll.BorderSizePixel = 0
		wpScroll.Position = UDim2.new(0,0,0,22+160+28)
		wpScroll.Size = UDim2.new(1,0,1,-(22+160+36))
		wpScroll.ScrollBarThickness = 4
		wpScroll.CanvasSize = UDim2.new(0,0,0,0)
		wpScroll.ZIndex = 1001
		wpScroll.Parent = guideFrame

		wpList = track(Instance.new("UIListLayout")); wpList.FillDirection=Enum.FillDirection.Vertical; wpList.SortOrder=Enum.SortOrder.LayoutOrder; wpList.Padding=UDim.new(0,2); wpList.Parent=wpScroll
	end
end

local function updateToggleDots()
	if setDotESP then setDotESP(ESP_ENABLED) end
	if setDotCB then setDotCB(CLICKBREAK_ENABLED) end
	if setDotAC then setDotAC(AUTOCLICK_ENABLED) end
	if setDotSKY then setDotSKY(SKY_MODE_ENABLED) end
	if setDotPV then setDotPV(PREDICTION_VECTORS_ENABLED) end
	if setDotTA then setDotTA(TARGETING_ASSIST_ENABLED) end
	if setDotPA then setDotPA(PROXIMITY_ALERTS_ENABLED) end
	if setDotPZ then setDotPZ(PREDICTION_ZONES_ENABLED) end
end

-- Rays
local function screenToRay(x,y)
	camera = Workspace.CurrentCamera
	if not camera then return end
	local inset = GuiService:GetGuiInset()
	local vx,vy = x - inset.X, y - inset.Y
	return camera:ScreenPointToRay(vx,vy,0)
end

local function getMouseRay()
	local loc = UserInputService:GetMouseLocation()
	local ray = screenToRay(loc.X, loc.Y)
	if not ray then return end
	return ray.Origin, ray.Direction*RAYCAST_MAX_DISTANCE, loc.X, loc.Y
end

-- Optimized worldRaycast with reusable RaycastParams
local function worldRaycast(origin, direction, ignoreLocalChar, extraIgnore)
	if brokenCacheDirty then
		rebuildBrokenIgnore()
	end

	local ignore = scratchIgnore
	clear(ignore)

	local ignoreCount = 0

	-- Add broken parts to ignore list
	local brokenCacheLen = #brokenIgnoreCache
	if brokenCacheLen > 0 then
		for i = 1, brokenCacheLen do
			ignoreCount = ignoreCount + 1
			ignore[ignoreCount] = brokenIgnoreCache[i]
		end
	end

	-- Add local character to ignore list if needed
	if ignoreLocalChar then
		local ch = localPlayer.Character
		if ch then
			ignoreCount = ignoreCount + 1
			ignore[ignoreCount] = ch
		end
	end

	-- Add extra ignore list if provided
	if extraIgnore then
		local extraLen = #extraIgnore
		for i = 1, extraLen do
			ignoreCount = ignoreCount + 1
			ignore[ignoreCount] = extraIgnore[i]
		end
	end

	raycastParams.FilterDescendantsInstances = ignore
	return Workspace:Raycast(origin, direction, raycastParams)
end

local function hitIsPlayer(hitInst)
	if not hitInst or not hitInst:IsA("BasePart") then return nil end
	local model = hitInst:FindFirstAncestorOfClass("Model")
	if not model then return nil end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then return nil end
	local p = Players:GetPlayerFromCharacter(model)
	if not p or p == localPlayer then return nil end
	return p, model
end

-- Indicators helpers
local function ensureIndicator(parent, key)
	local frame = parent:FindFirstChild(key)
	if frame then return frame end
	frame = Instance.new("Frame")
	frame.Name = key
	frame.Size = UDim2.fromOffset(INDICATOR_SIZE.X, INDICATOR_SIZE.Y)
	frame.BackgroundTransparency = 0.2
	frame.BackgroundColor3 = BG_INDICATOR
	frame.BorderSizePixel = 0
	frame.ZIndex = 1200
	frame.Parent = indicatorFolder
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,6); corner.Parent = frame

	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"; arrow.BackgroundTransparency = 1
	arrow.Size = UDim2.fromOffset(18,18); arrow.Position = UDim2.fromOffset(2,2)
	arrow.Font = Enum.Font.GothamBlack; arrow.Text = "▲"; arrow.TextSize = 16
	arrow.TextColor3 = WHITE; arrow.ZIndex = 1201; arrow.Parent = frame

	local lbl = Instance.new("TextLabel")
	lbl.Name = "Lbl"; lbl.BackgroundTransparency = 1
	lbl.Position = UDim2.fromOffset(22,0); lbl.Size = UDim2.new(1,-24,1,0)
	lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.TextYAlignment = Enum.TextYAlignment.Center
	lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 12; lbl.TextColor3 = WHITE
	lbl.Text = ""; lbl.ZIndex = 1201; lbl.Parent = frame

	return frame
end

local function placeIndicator(frame, color, nameText, screenPos, angleRad)
	if not frame then return end
	local arrow = frame:FindFirstChild("Arrow")
	if arrow then
		arrow.TextColor3 = color
		arrow.Rotation = deg(angleRad) - 90
	end
	local lbl = frame:FindFirstChild("Lbl")
	if lbl then
		lbl.Text = nameText
		lbl.TextColor3 = color
	end
	frame.Position = UDim2.fromOffset(screenPos.X - INDICATOR_SIZE_HALF.X, screenPos.Y - INDICATOR_SIZE_HALF.Y)
	frame.Visible = true
end

local function hideIndicator(frame) if frame then frame.Visible = false end end

-- Optimized projectToEdge with cached calculations
local function projectToEdge(worldPos)
	if not camera then return nil end
	local v, onScreen = camera:WorldToViewportPoint(worldPos)
	local viewport = camera.ViewportSize
	local centerX, centerY = viewport.X * 0.5, viewport.Y * 0.5
	local pt = Vector2.new(v.X, v.Y)
	local dirX, dirY = v.X - centerX, v.Y - centerY

	if v.Z < 0 then
		dirX, dirY = -dirX, -dirY
	end

	local dirMag = (dirX * dirX + dirY * dirY) ^ 0.5
	if dirMag < 1e-3 then
		dirX, dirY = 0, -1
		dirMag = 1
	end

	local halfX = centerX - EDGE_MARGIN
	local halfY = centerY - EDGE_MARGIN
	local sx = abs(dirX) / halfX
	local sy = abs(dirY) / halfY
	local t = max(sx, sy, 1e-6)

	local edgeX = customClamp(centerX + dirX / t, EDGE_MARGIN, viewport.X - EDGE_MARGIN)
	local edgeY = customClamp(centerY + dirY / t, EDGE_MARGIN, viewport.Y - EDGE_MARGIN)
	local edge = Vector2.new(edgeX, edgeY)

	local angle = atan2(dirY, dirX)
	return onScreen and v.Z > 0, Vector2.new(v.X, v.Y), edge, angle
end

-- Br3ak3r
local function markBroken(part)
	if not part or not part:IsA("BasePart") then return end
	brokenSet[part] = true
	brokenCacheDirty = true
	insert(undoStack, {part=part, cc=part.CanCollide, ltm=part.LocalTransparencyModifier, t=part.Transparency})
	if #undoStack > UNDO_LIMIT then remove(undoStack, 1) end
	part.CanCollide = false; part.LocalTransparencyModifier = 1; part.Transparency = 1
end

local function unbreakLast()
	local e = remove(undoStack)
	if not e or not e.part or not e.part:IsDescendantOf(game) then
		if e and e.part then
			brokenSet[e.part] = nil
			brokenCacheDirty = true
		end
		return
	end
	brokenSet[e.part] = nil
	brokenCacheDirty = true
	e.part.CanCollide = e.cc; e.part.LocalTransparencyModifier = e.ltm; e.part.Transparency = e.t
end

local sweepAccum = 0
local function sweepUndo(dt)
	sweepAccum = sweepAccum + dt
	if sweepAccum < 2 then return end
	sweepAccum = 0
	local i = 1
	while i <= #undoStack do
		local e = undoStack[i]
		if not e.part or not e.part:IsDescendantOf(game) then
			if e and e.part then
				brokenSet[e.part] = nil
				brokenCacheDirty = true
			end
			remove(undoStack, i)
		else
			i = i + 1
		end
	end
end

local function pruneBrokenSet()
	local removed = false
	for part,_ in pairs(brokenSet) do
		if not part or not part:IsDescendantOf(Workspace) then
			brokenSet[part] = nil
			removed = true
		end
	end
	if removed then
		brokenCacheDirty = true
	end
end

local runNearestUpdate = makeIntervalRunner(0.05)
local runVisualUpdate = makeIntervalRunner(0.1)
local runCleanupSweep = makeIntervalRunner(2)

-- ESP
local function destroyPerPlayer(p)
	local pp = perPlayer[p]; if not pp then return end
	if pp.bill then safeDestroy(pp.bill) end
	if pp.outline then safeDestroy(pp.outline) end
	if pp.indicator then
		hideIndicator(pp.indicator)
		safeDestroy(pp.indicator)
	end
	if pp.predictionVector then safeDestroy(pp.predictionVector) end
	if pp.proximityAlert then safeDestroy(pp.proximityAlert) end
	if pp.predictionZone then safeDestroy(pp.predictionZone) end
	perPlayer[p] = nil
end

local function setESPVisible(p, visible)
	local pp = perPlayer[p]; if not pp then return end
	if pp.bill then pp.bill.Enabled = visible end
	if pp.outline then pp.outline.Enabled = visible end
end

local function createOutlineForCharacter(character, enabled)
	local h = Instance.new("Highlight"); h.Name="SB3_PinkOutline"; h.Adornee=character
	h.FillTransparency=1; h.OutlineTransparency=0; h.OutlineColor=PINK
	h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop; h.Enabled=enabled; h.Parent=character
	return h
end

local function getEquippedTool(character)
	local tool = character:FindFirstChildOfClass("Tool")
	if tool then return tool.Name end
	return nil
end

local function billboardFor(p, character)
	local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	local hum = character:FindFirstChildOfClass("Humanoid"); if not head or not hum then return end
	local bill = Instance.new("BillboardGui"); bill.Name="B"..HttpService:GenerateGUID(false):gsub("-","")
	bill.AlwaysOnTop=true; bill.MaxDistance=1e9; bill.Adornee=head; bill.Size=UDim2.fromOffset(NAME_BASE_W, NAME_BASE_H)
	bill.StudsOffset=Vector3.new(0,2,0); bill.Enabled=ESP_ENABLED; bill.Parent=head; track(bill)
	local t = Instance.new("TextLabel"); t.Name="T"; t.BackgroundTransparency=1; t.Size=UDim2.fromScale(1,1)
	t.Font=Enum.Font.GothamBold; t.TextScaled=false; t.TextSize=14; t.TextColor3=RED; t.TextStrokeTransparency=0; t.TextStrokeColor3=WHITE; t.Text=""; t.Parent=bill
	local entry = perPlayer[p] or {}
	entry.bill = bill
	entry.text = t
	entry.hum = hum
	entry.tool = getEquippedTool(character)
	entry.cache = entry.cache or {}
	perPlayer[p] = entry
end

local function rebuildForCharacter(p, character)
	destroyPerPlayer(p); if not character then return end
	billboardFor(p, character)
	local data = perPlayer[p]
	if not data then return end
	data.cache = data.cache or {}
	clear(data.cache)
	data.outline = createOutlineForCharacter(character, ESP_ENABLED)
	data.indicator = ensureIndicator(indicatorFolder, "PI_"..p.UserId)
	data.character = character
	data.root = character:FindFirstChild("HumanoidRootPart")
	data.hum = character:FindFirstChildOfClass("Humanoid")
end

local function updateNearestPlayer()
	local myChar = localPlayer.Character
	local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
	if not myRoot then
		nearestPlayerRef = nil
		return
	end
	local myRootPos = myRoot.Position
	local best, bestDist = nil, nil
	for p,data in pairs(perPlayer) do
		local character = p.Character or data.character
		local root = data.root
		if character then
			if not root or root.Parent ~= character then
				root = character:FindFirstChild("HumanoidRootPart")
				data.root = root
			end
		end
		if root and root:IsDescendantOf(Workspace) then
			local d = (root.Position - myRootPos).Magnitude
			if not bestDist or d < bestDist then
				best, bestDist = p, d
			end
		end
	end
	nearestPlayerRef = best
end

-- Prediction Vector (velocity visualization)
local function ensurePredictionVector(p, root)
	local pp = perPlayer[p]
	if not pp then return end
	if not pp.predictionVector then
		local beam = Instance.new("Beam")
		beam.Name = "PredVector_" .. p.UserId
		beam.Transparency = NumberSequence.new(0.3)
		beam.Width0 = 0.2
		beam.Width1 = 0.2
		beam.Parent = Workspace
		pp.predictionVector = beam
		pp.predVecAttach0 = Instance.new("Attachment")
		pp.predVecAttach0.Parent = root
		pp.predVecAttach1 = Instance.new("Attachment")
		pp.predVecAttach1.Parent = Workspace
		beam.Attachment0 = pp.predVecAttach0
		beam.Attachment1 = pp.predVecAttach1
	end
	return pp.predictionVector
end

local function updatePredictionVector(p, data)
	if not PREDICTION_VECTORS_ENABLED or not data.root then
		if data.predictionVector then data.predictionVector.Enabled = false end
		return
	end
	local beam = ensurePredictionVector(p, data.root)
	if not beam then return end

	local vel = data.root.AssemblyLinearVelocity
	local speed = vel.Magnitude

	if speed > 0.5 then
		-- Scale the vector based on speed (normalized to 50 studs max)
		local vizLength = min(speed / 20, 50)
		local vizDir = vel.Unit

		if data.predVecAttach1 then
			data.predVecAttach1.Position = vizDir * vizLength
		end

		-- Color based on speed
		local speedRatio = min(speed / 100, 1)
		local beamColor = Color3.new(
			1,
			max(0, 1 - speedRatio * 2),
			max(0, 1 - speedRatio)
		)
		beam.Color = ColorSequence.new(beamColor)
		beam.Enabled = true
	else
		beam.Enabled = false
	end
end

-- Proximity Alerts (visual warnings at distance tiers)
local PROXIMITY_TIERS = {
	{dist=50, color=RED, name="DANGER"},
	{dist=100, color=ORANGE, name="ALERT"},
	{dist=200, color=YELLOW, name="NEAR"},
}

local function updateProximityAlert(p, data)
	if not PROXIMITY_ALERTS_ENABLED then
		if data.proximityAlert then data.proximityAlert.Visible = false end
		return
	end

	local myChar = localPlayer.Character
	local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
	if not myRoot or not data.root then
		if data.proximityAlert then data.proximityAlert.Visible = false end
		return
	end

	local dist = (myRoot.Position - data.root.Position).Magnitude
	local alertColor = nil
	local alertText = nil

	for _, tier in ipairs(PROXIMITY_TIERS) do
		if dist <= tier.dist then
			alertColor = tier.color
			alertText = tier.name
			break
		end
	end

	if not alertColor then
		if data.proximityAlert then data.proximityAlert.Visible = false end
		return
	end

	if not data.proximityAlert then
		local alert = Instance.new("TextLabel")
		alert.Name = "ProxAlert_" .. p.UserId
		alert.BackgroundTransparency = 0.2
		alert.BackgroundColor3 = alertColor
		alert.BorderSizePixel = 0
		alert.Size = UDim2.fromOffset(80, 20)
		alert.Position = UDim2.fromOffset(10, 10 + (p.UserId % 3) * 25)
		alert.Font = Enum.Font.GothamBold
		alert.TextSize = 12
		alert.TextColor3 = WHITE
		alert.ZIndex = 500
		alert.Parent = screenGui
		data.proximityAlert = alert
		track(alert)
	end

	if data.proximityAlert then
		data.proximityAlert.Text = alertText
		data.proximityAlert.BackgroundColor3 = alertColor
		data.proximityAlert.Visible = true
	end
end

-- Prediction Zones (circles showing likely player position in future)
local function updatePredictionZone(p, data)
	if not PREDICTION_ZONES_ENABLED or not data.root then
		if data.predictionZone then data.predictionZone.Enabled = false end
		return
	end

	local vel = data.root.AssemblyLinearVelocity
	local speed = vel.Magnitude

	if speed < 0.5 then
		if data.predictionZone then data.predictionZone.Enabled = false end
		return
	end

	if not data.predictionZone then
		local zone = Instance.new("Part")
		zone.Name = "PredZone_" .. p.UserId
		zone.Shape = Enum.PartType.Ball
		zone.CanCollide = false
		zone.CFrame = data.root.CFrame
		zone.TopSurface = Enum.SurfaceType.Smooth
		zone.BottomSurface = Enum.SurfaceType.Smooth
		zone.Material = Enum.Material.Glass
		zone.Transparency = 0.7
		zone.Color = CYAN
		zone.Parent = Workspace
		data.predictionZone = zone
	end

	if data.predictionZone then
		-- Predict position 0.5 seconds ahead
		local predictedPos = data.root.Position + (vel * 0.5)
		data.predictionZone.Position = predictedPos
		data.predictionZone.Size = Vector3.new(5, 5, 5)  -- 5 stud radius for prediction uncertainty
		data.predictionZone.Enabled = true
	end
end

-- Optimized updateSinglePlayerVisual with reduced redundant checks
local function updateSinglePlayerVisual(p, data)
	local cache = data.cache
	if not cache then
		cache = {}
		data.cache = cache
	end
	local character = p.Character or data.character
	data.character = character
	local root = data.root
	if character then
		if not root or root.Parent ~= character then
			root = character:FindFirstChild("HumanoidRootPart")
			data.root = root
		end
	else
		root = nil
	end
	if not character or not root then
		if data.bill and cache.billEnabled then
			data.bill.Enabled = false
			cache.billEnabled = false
		end
		if cache.indicatorVisible then
			hideIndicator(data.indicator)
			cache.indicatorVisible = false
		end
		return
	end
	local hum = data.hum
	if not hum or hum.Parent ~= character then
		hum = character:FindFirstChildOfClass("Humanoid")
		data.hum = hum
	end
	local onScreen, _, edge, angle = projectToEdge(root.Position)
	if onScreen == nil then return end

	local cameraCFrame = camera.CFrame
	local dist = (cameraCFrame.Position - root.Position).Magnitude
	local distRounded = floor(dist + 0.5)
	local scale = customClamp(NAME_DIST_REF / max(dist, 1), NAME_MIN_SCALE, NAME_MAX_SCALE)
	local hp = hum and floor((hum.Health or 0) + 0.5) or 0
	local name = p.DisplayName or p.Name
	local isNearest = (p == nearestPlayerRef)

	-- Distance-based color: closest is bright red, others use heat-map gradient
	local textColor
	if isNearest then
		textColor = CLOSEST_COLOR  -- Bright red for closest player
	else
		textColor = getDistanceColor(dist)  -- Gradient based on distance
	end

	local textZ = isNearest and 10 or 1

	if data.bill then
		-- Only update scale if it changed significantly
		if abs((cache.billScale or 0) - scale) > 0.01 then
			data.bill.Size = UDim2.fromOffset(NAME_BASE_W * scale, NAME_BASE_H * scale)
			cache.billScale = scale
		end
		local shouldEnable = ESP_ENABLED and onScreen
		if cache.billEnabled ~= shouldEnable then
			data.bill.Enabled = shouldEnable
			cache.billEnabled = shouldEnable
		end
		if data.text then
			-- Update equipped tool detection
			local currentTool = getEquippedTool(character)
			if cache.billTool ~= currentTool then
				data.tool = currentTool
				cache.billTool = currentTool
			end

			-- Only update text if data changed
			if cache.billDist ~= distRounded or cache.billHP ~= hp or cache.billName ~= name or cache.billTool ~= data.tool then
				local toolDisplay = data.tool or "UNARMED"
				local textValue = string.format(FORMAT_NAME_DIST_TOOL_HP, name, toolDisplay, distRounded, hp)
				data.text.Text = textValue
				cache.billDist = distRounded
				cache.billHP = hp
				cache.billName = name
				cache.billTool = data.tool
				cache.billText = textValue
			end
			if cache.billColor ~= textColor then
				data.text.TextColor3 = textColor
				cache.billColor = textColor
			end
			if cache.billZ ~= textZ then
				data.text.ZIndex = textZ
				cache.billZ = textZ
			end
		end
	end

	if data.outline then
		data.outline.Enabled = ESP_ENABLED
	end

	if not (onScreen and ESP_ENABLED) then
		local indicator = data.indicator
		if indicator then
			local indicatorColor = textColor
			local labelText = cache.indicatorText
			if cache.indicatorDist ~= distRounded or cache.indicatorName ~= name then
				labelText = string.format(FORMAT_NAME_DIST, name, distRounded)
				cache.indicatorDist = distRounded
				cache.indicatorName = name
				cache.indicatorText = labelText
			end
			cache.indicatorColor = indicatorColor
			placeIndicator(indicator, indicatorColor, labelText, edge, angle)
			cache.indicatorVisible = true
		end
	else
		if cache.indicatorVisible then
			hideIndicator(data.indicator)
			cache.indicatorVisible = false
		end
	end
end

local function updatePlayerVisuals()
	camera = Workspace.CurrentCamera or camera
	if not camera then return end
	for p,data in pairs(perPlayer) do
		updateSinglePlayerVisual(p, data)
		updatePredictionVector(p, data)
		updateProximityAlert(p, data)
		updatePredictionZone(p, data)
	end
end

local function createForPlayer(p)
	local function onSpawn(character) task.wait(0.1); rebuildForCharacter(p, character) end
	bind(p.CharacterAdded:Connect(onSpawn)); if p.Character then onSpawn(p.Character) end
end

for _,p in ipairs(Players:GetPlayers()) do if p ~= localPlayer then createForPlayer(p) end end
bind(Players.PlayerAdded:Connect(function(p) if p ~= localPlayer then createForPlayer(p) end end))
bind(Players.PlayerRemoving:Connect(function(p) destroyPerPlayer(p) end))

-- Waypoints
local function getWpContainer() return Workspace:FindFirstChild("SP_WP_CONTAINER") end
local function nextWpNameAndColor() wpNameIndex=(wpNameIndex % #HEBREW_NATO)+1; return HEBREW_NATO[wpNameIndex], NATO_COLORS[wpNameIndex] end

local function setWaypointAppearance(part, name, color)
	part.Name="SP_WP_"..name; part:SetAttribute("SB3_Name", name); part:SetAttribute("SB3_Color", color)
	local bb=part:FindFirstChild("BB") or Instance.new("BillboardGui"); bb.Name="BB"; bb.AlwaysOnTop=true; bb.Size=UDim2.fromOffset(100,26); bb.StudsOffset=Vector3.new(0,1.5,0); bb.Parent=part
	local t=bb:FindFirstChild("T") or Instance.new("TextLabel"); t.Name="T"; t.BackgroundTransparency=1; t.Size=UDim2.fromScale(1,1); t.Font=Enum.Font.GothamBold; t.TextScaled=true; t.Text=name; t.TextColor3=color; t.TextStrokeTransparency=0.2; t.TextStrokeColor3=WHITE; t.Parent=bb
end

local function refreshWaypointGuide()
	local container=getWpContainer(); local parts={}
	if container then
		for _,ch in ipairs(container:GetChildren()) do
			if ch:IsA("Part") then insert(parts,ch) end
		end
	end
	local myPos; local ch=localPlayer.Character; local root=ch and ch:FindFirstChild("HumanoidRootPart"); if root then myPos=root.Position end
	local sorted={}
	for _,p in ipairs(parts) do
		local d=myPos and (p.Position-myPos).Magnitude or huge
		insert(sorted,{part=p,dist=d})
	end
	table.sort(sorted,function(a,b) return a.dist<b.dist end)
	for part,row in pairs(wpRowMap) do
		if not part.Parent or not part:IsDescendantOf(container or Workspace) then
			if row and row.Parent then row:Destroy() end
			wpRowMap[part]=nil
		end
	end
	local canvas=0
	for idx,entry in ipairs(sorted) do
		local part=entry.part; local dist=entry.dist
		local row=wpRowMap[part]; local name=part:GetAttribute("SB3_Name") or "??"; local color=part:GetAttribute("SB3_Color") or GRAY
		if not row then
			row=Instance.new("TextLabel")
			row.BackgroundTransparency=1
			row.Size=UDim2.new(1,0,0,16)
			row.TextXAlignment=Enum.TextXAlignment.Left
			row.Font=Enum.Font.Gotham
			row.TextSize=12
			row.TextColor3=color
			row.ZIndex=1002
			row.Parent=wpScroll
			wpRowMap[part]=row
			track(row)
		end
		row.LayoutOrder=idx
		row.Text=string.format(FORMAT_NAME_DIST, name, floor(dist+0.5))
		row.TextColor3=color
		canvas=canvas+18
	end
	wpScroll.CanvasSize=UDim2.new(0,0,0,canvas)
end

local function ensureWpIndicator(part)
	local key="WI_"..part:GetDebugId(); local frame=wpIndicatorMap[part]
	if frame and frame.Parent then return frame end
	frame=ensureIndicator(indicatorFolder, key); wpIndicatorMap[part]=frame; return frame
end

local function updateWaypointIndicators()
	local container=getWpContainer()
	for part,frame in pairs(wpIndicatorMap) do
		if not part.Parent or not part:IsDescendantOf(container or Workspace) then
			hideIndicator(frame)
			wpIndicatorMap[part]=nil
		end
	end
	if not container then return end
	local cameraCFrame = camera.CFrame
	for _,part in ipairs(container:GetChildren()) do
		if part:IsA("Part") then
			local name=part:GetAttribute("SB3_Name") or "WP"; local color=part:GetAttribute("SB3_Color") or GRAY
			local onscreen, v2, edge, angle = projectToEdge(part.Position)
			local bb=part:FindFirstChild("BB")
			if onscreen then
				if bb then bb.Enabled=true end
				local f=wpIndicatorMap[part]
				if f then hideIndicator(f) end
			else
				if bb then bb.Enabled=false end
				local f=ensureWpIndicator(part)
				local dist=(cameraCFrame.Position - part.Position).Magnitude
				placeIndicator(f, color, string.format(FORMAT_NAME_DIST, name, floor(dist+0.5)), edge, angle)
			end
		end
	end
end

-- Targeting Assist (lead prediction + mouse smoothing)
local function getTargetLeadPosition(targetRoot, bulletSpeed)
	if not targetRoot then return nil end
	-- Predict where target will be when bullet arrives
	-- Simple: vel * (distance / bulletSpeed)
	local vel = targetRoot.AssemblyLinearVelocity
	local myPos = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not myPos then return nil end
	local dist = (targetRoot.Position - myPos.Position).Magnitude
	if bulletSpeed <= 0 then bulletSpeed = 100 end
	local travelTime = dist / bulletSpeed
	return targetRoot.Position + (vel * travelTime)
end

local targetingAssistData = {
	targetPlayer = nil,
	targetPos = nil,
	screenPos = nil,
	lastMouseX = 0,
	lastMouseY = 0
}

local function updateTargetingAssist()
	if not TARGETING_ASSIST_ENABLED then
		return
	end

	-- Find nearest player
	if nearestPlayerRef and nearestPlayerRef.Character then
		local targetRoot = nearestPlayerRef.Character:FindFirstChild("HumanoidRootPart")
		if targetRoot then
			-- Calculate lead position (assuming ~100 stud/s bullet speed)
			local leadPos = getTargetLeadPosition(targetRoot, 100)
			if leadPos then
				targetingAssistData.targetPlayer = nearestPlayerRef
				targetingAssistData.targetPos = leadPos

				-- Project to screen
				local v, onScreen = camera:WorldToViewportPoint(leadPos)
				if onScreen then
					targetingAssistData.screenPos = Vector2.new(v.X, v.Y)
				end
			end
		end
	else
		targetingAssistData.targetPlayer = nil
		targetingAssistData.targetPos = nil
		targetingAssistData.screenPos = nil
	end
end

local function drawTargetingCrosshair()
	if not TARGETING_ASSIST_ENABLED or not targetingAssistData.screenPos then return end

	-- This would draw a crosshair at the target position
	-- For now, we just calculate it; actual rendering would need a canvas or GUI
	local targetScreen = targetingAssistData.screenPos
	return targetScreen
end

-- Sky Mode
local function enableSkyMode()
	if not skyBackupFolder then
		skyBackupFolder=Instance.new("Folder")
		skyBackupFolder.Name="SB3_SkyBackup"
		skyBackupFolder.Parent=Lighting
		for _,o in ipairs(Lighting:GetChildren()) do
			if o:IsA("Sky") then o.Parent=skyBackupFolder end
		end
	end
	if not skyInjected then
		skyInjected=Instance.new("Sky")
		skyInjected.Name="SB3_Sky"
		skyInjected.CelestialBodiesShown=true
		skyInjected.Parent=Lighting
	end
	if not atmosInjected then
		atmosInjected=Instance.new("Atmosphere")
		atmosInjected.Name="SB3_Atmosphere"
		atmosInjected.Color=Color3.fromRGB(200,220,255)
		atmosInjected.Decay=Color3.fromRGB(255,255,255)
		atmosInjected.Density=0.15
		atmosInjected.Offset=0.25
		atmosInjected.Glare=0
		atmosInjected.Haze=0.25
		atmosInjected.Parent=Lighting
	end
end

local function disableSkyMode()
	if skyBackupFolder then
		for _,o in ipairs(skyBackupFolder:GetChildren()) do o.Parent=Lighting end
		safeDestroy(skyBackupFolder)
		skyBackupFolder=nil
	end
	safeDestroy(skyInjected); skyInjected=nil
	safeDestroy(atmosInjected); atmosInjected=nil
end

-- Hover highlight for Br3ak3r
hoverHL = track(Instance.new("Highlight"))
hoverHL.Name = "SB3_Hover"; hoverHL.FillColor=PINK; hoverHL.OutlineColor=WHITE; hoverHL.FillTransparency=0.6; hoverHL.OutlineTransparency=0.2
hoverHL.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop; hoverHL.Enabled=false; hoverHL.Parent=Workspace

-- Input
local CTRL_HELD = false
bind(UserInputService.InputBegan:Connect(function(input,gp)
	if gp or dead then return end
	if input.KeyCode == Enum.KeyCode.LeftControl then CTRL_HELD = true end

	-- Br3ak3r action
	if CTRL_HELD and input.UserInputType == Enum.UserInputType.MouseButton1 and CLICKBREAK_ENABLED then
		local o,d = getMouseRay(); if o and d then local hit=worldRaycast(o,d,true); if hit and hit.Instance and hit.Instance:IsA("BasePart") then markBroken(hit.Instance) end end
	end

	-- Waypoints add/remove
	if CTRL_HELD and input.UserInputType == Enum.UserInputType.MouseButton3 then
		local o,d = getMouseRay(); if o and d then local r=worldRaycast(o,d,true); if r and r.Position then
			local pos=r.Position; local existing=Workspace:FindFirstChild("SP_WP_CONTAINER")
			if existing then for _,p in ipairs(existing:GetChildren()) do if p:IsA("Part") and (p.Position - pos).Magnitude < 10 then p:Destroy(); return end end end
			local container=existing or Instance.new("Folder"); container.Name="SP_WP_CONTAINER"; container.Parent=Workspace
			local part=Instance.new("Part"); part.Anchored=true; part.CanCollide=false; part.Transparency=1; part.Size=Vector3.new(1,1,1); part.Position=pos+Vector3.new(0,2,0)
			local name,color=nextWpNameAndColor(); setWaypointAppearance(part, name, color); part.Parent=container
		end end
	end
end))
bind(UserInputService.InputEnded:Connect(function(input,gp) if input.KeyCode == Enum.KeyCode.LeftControl then CTRL_HELD = false end end))

-- Toggle keys (with Ctrl)
bind(UserInputService.InputBegan:Connect(function(input,gp)
	if gp or not CTRL_HELD or dead then return end
	if input.KeyCode == Enum.KeyCode.Return then CLICKBREAK_ENABLED = not CLICKBREAK_ENABLED
	elseif input.KeyCode == Enum.KeyCode.K then AUTOCLICK_ENABLED = not AUTOCLICK_ENABLED
	elseif input.KeyCode == Enum.KeyCode.L then SKY_MODE_ENABLED = not SKY_MODE_ENABLED; if SKY_MODE_ENABLED then enableSkyMode() else disableSkyMode() end
	elseif input.KeyCode == Enum.KeyCode.E then ESP_ENABLED = not ESP_ENABLED; for p,_ in pairs(perPlayer) do setESPVisible(p, ESP_ENABLED) end
	elseif input.KeyCode == Enum.KeyCode.V then PREDICTION_VECTORS_ENABLED = not PREDICTION_VECTORS_ENABLED
	elseif input.KeyCode == Enum.KeyCode.T then TARGETING_ASSIST_ENABLED = not TARGETING_ASSIST_ENABLED
	elseif input.KeyCode == Enum.KeyCode.A then PROXIMITY_ALERTS_ENABLED = not PROXIMITY_ALERTS_ENABLED
	elseif input.KeyCode == Enum.KeyCode.P then PREDICTION_ZONES_ENABLED = not PREDICTION_ZONES_ENABLED
	elseif input.KeyCode == Enum.KeyCode.Z then unbreakLast()
	elseif input.KeyCode == Enum.KeyCode.Six then
		dead = true
		AUTOCLICK_ENABLED=false; ESP_ENABLED=false; SKY_MODE_ENABLED=false; CLICKBREAK_ENABLED=false
		disableSkyMode()
		disconnectAll()
		for p,_ in pairs(perPlayer) do destroyPerPlayer(p) end
		perPlayer = {}
		clear(brokenSet)
		clear(undoStack)
		clear(brokenIgnoreCache)
		clear(scratchIgnore)
		brokenCacheDirty = true
		hoverHL.Enabled=false; safeDestroy(hoverHL)
		if guideFrame then safeDestroy(guideFrame) end
		for _,f in pairs(wpIndicatorMap) do safeDestroy(f) end
		wpIndicatorMap={}
		for i=#indicatorFolder:GetChildren(),1,-1 do safeDestroy(indicatorFolder:GetChildren()[i]) end
		safeDestroy(indicatorFolder)
		destroyAll()
		-- restore mouse behavior if we changed it
		pcall(function() UserInputService.MouseBehavior = Enum.MouseBehavior.Default end)
	end
end))

-- AutoClick & UI refresh
local lastClick, uiAccum = AUTOCLICK_INTERVAL,0
local autoClickTargetPlayer, autoClickTargetPart = nil, nil

local function sendAutoClick(mouseX, mouseY)
	VirtualInputManager:SendMouseButtonEvent(mouseX, mouseY, 0, true, game, 0)
	VirtualInputManager:SendMouseButtonEvent(mouseX, mouseY, 0, false, game, 0)
end

bind(RunService.Heartbeat:Connect(function(dt)
	if dead then return end
	ensureGuide()
	updateToggleDots()

	-- Hover preview for Br3ak3r
	if CTRL_HELD and CLICKBREAK_ENABLED then
		local o,d = getMouseRay(); if o and d then local r=worldRaycast(o,d,true); local part=r and r.Instance
			if part and part:IsA("BasePart") and not brokenSet[part] then hoverHL.Adornee=part; hoverHL.Enabled=true else hoverHL.Enabled=false end
		else hoverHL.Enabled=false end
	else hoverHL.Enabled=false end

	-- Nearest and visuals
	if runNearestUpdate(dt) then
		updateNearestPlayer()
		updateTargetingAssist()
	end
	if runVisualUpdate(dt) then
		updatePlayerVisuals()
	end

	-- Throttled UI work
	uiAccum = uiAccum + dt
	if uiAccum >= 0.1 then uiAccum = 0; refreshWaypointGuide(); updateWaypointIndicators() end

	if runCleanupSweep(dt) then
		pruneBrokenSet()
	end

	-- Br3ak3r sweeper
	sweepUndo(dt)

	-- AutoClick: immediate start + steady CPS while over a valid player
	if AUTOCLICK_ENABLED and hasVIM then
		local origin, direction, mouseX, mouseY = getMouseRay()
		if origin and direction then
			local result = worldRaycast(origin, direction, true)
			local inst = result and result.Instance
			local player = inst and hitIsPlayer(inst)
			if player then
				local targetChanged = player ~= autoClickTargetPlayer or inst ~= autoClickTargetPart
				autoClickTargetPlayer, autoClickTargetPart = player, inst
				if targetChanged then
					lastClick = AUTOCLICK_INTERVAL + dt
				else
					lastClick = lastClick + dt
				end
				while lastClick >= AUTOCLICK_INTERVAL do
					lastClick = lastClick - AUTOCLICK_INTERVAL
					sendAutoClick(mouseX, mouseY)
				end
			else
				autoClickTargetPlayer, autoClickTargetPart = nil, nil
				lastClick = AUTOCLICK_INTERVAL
			end
		else
			autoClickTargetPlayer, autoClickTargetPart = nil, nil
			lastClick = AUTOCLICK_INTERVAL
		end
	else
		autoClickTargetPlayer, autoClickTargetPart = nil, nil
		lastClick = AUTOCLICK_INTERVAL
	end
end))

-- Initial ESP visibility state
for p,_ in pairs(perPlayer) do setESPVisible(p, ESP_ENABLED) end

-- Character respawn handling for local player
bind(localPlayer.CharacterAdded:Connect(function()
	if dead then return end
	if indicatorFolder and indicatorFolder.Parent ~= screenGui then indicatorFolder.Parent = screenGui end
	if SKY_MODE_ENABLED then task.defer(enableSkyMode) end
end))
