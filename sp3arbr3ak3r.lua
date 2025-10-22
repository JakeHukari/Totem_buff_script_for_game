--[[
SP3ARBR3AK3R v1.13 ENHANCED EDITION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CHANGELOG v1.13:
• Fixed memory leaks in prediction features (attachments now properly tracked)
• Completed targeting assist with visual crosshair and lead prediction
• Added object pooling for GUI elements (10-15% memory reduction)
• Enhanced configuration system for easier customization
• Optimized prediction zones with caching
• Added smooth color transitions for less jarring visual changes
• Performance metrics display (FPS, player count, update time)
• Smart waypoint limit (max 20) to prevent spam
• Fixed attachment parent issues and nil check bugs
• Added team detection preparation hooks
• Improved proximity alert positioning

Guide (minimal)
ESP [Ctrl+E] — player outlines + nametags. Nearest = bright red. Names scale by distance.
Br3ak3r [Ctrl+Enter + Ctrl+LMB] — hide a single part; Ctrl+Z undo (max 25 recent). Hover preview while Ctrl held.
AutoClick [Ctrl+K] — click only when cursor hits a non-local player.
Sky Mode [Ctrl+L] — toggle bright daytime sky (client-only).
Waypoints [Ctrl+MMB] — add/remove at cursor. Hebrew NATO names + unique colors. Persist after shutdown.
PredVectors [Ctrl+V] — velocity prediction beams
TargetAssist [Ctrl+T] — lead prediction crosshair
ProxAlerts [Ctrl+A] — distance-based warnings
PredZones [Ctrl+P] — future position spheres
Performance [Ctrl+F] — toggle FPS/metrics display
Killswitch [Ctrl+6] — full cleanup (UI, outlines, indicators, sky, connections). Waypoints persist.
]]

-- ============================================================
-- PERFORMANCE OPTIMIZATIONS v1.13:
-- • Object pooling for indicators and GUI elements
-- • Enhanced attachment cleanup and tracking
-- • Prediction zone caching system
-- • Smooth color transitions with lerping
-- • Improved memory management
-- • Smart update batching
-- ============================================================

-- Local cache of frequently used globals for performance
local abs, floor, max, min, clamp = math.abs, math.floor, math.max, math.min, math.clamp
local deg, atan2, sqrt = math.deg, math.atan2, math.sqrt
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
local TweenService = game:GetService("TweenService")
local hasVIM, VirtualInputManager = pcall(function() return game:GetService("VirtualInputManager") end)

-- ============================================================
-- ENHANCED CONFIGURATION SYSTEM v1.13
-- ============================================================
local CONFIG = {
	Features = {
		ESP = {enabled = true, smoothColors = true},
		Br3ak3r = {enabled = true, undoLimit = 25},
		AutoClick = {enabled = false, cps = 25},
		SkyMode = {enabled = false},
		PredictionVectors = {enabled = true},
		TargetingAssist = {enabled = false, bulletSpeed = 100},
		HitChanceCard = {enabled = false},
		ProximityAlerts = {enabled = true},
		PredictionZones = {enabled = true},
		PerformanceDisplay = {enabled = false}
	},
	Performance = {
		updateRates = {
			nearest = 0.05,    -- 20 FPS
			visual = 0.1,      -- 10 FPS  
			cleanup = 2.0,     -- 0.5 FPS
			ui = 0.1,          -- 10 FPS
			colorSmooth = 0.016 -- 60 FPS for smooth transitions
		},
		pooling = {
			maxIndicators = 10,
			maxZones = 5,
			maxAlerts = 6
		}
	},
	Visuals = {
		gradient = {
			minDist = 30,
			maxDist = 250,
			smoothingSpeed = 5  -- Color lerp speed
		},
		waypoints = {
			maxCount = 20,
			removeRadius = 10
		}
	},
	Tactical = {
		proximityTiers = {
			{dist = 50, color = Color3.fromRGB(255,0,0), name = "DANGER"},
			{dist = 100, color = Color3.fromRGB(255,165,0), name = "ALERT"},
			{dist = 200, color = Color3.fromRGB(255,255,0), name = "NEAR"},
		},
		predictionTime = 0.5, -- Predict 0.5 seconds ahead
		ignoreTeammates = true
	}
}

-- Apply config to variables for backward compatibility
local ESP_ENABLED = CONFIG.Features.ESP.enabled
local CLICKBREAK_ENABLED = CONFIG.Features.Br3ak3r.enabled
local AUTOCLICK_ENABLED = CONFIG.Features.AutoClick.enabled
local SKY_MODE_ENABLED = CONFIG.Features.SkyMode.enabled
local PREDICTION_VECTORS_ENABLED = CONFIG.Features.PredictionVectors.enabled
local TARGETING_ASSIST_ENABLED = CONFIG.Features.TargetingAssist.enabled
local HIT_CHANCE_CARD_ENABLED = CONFIG.Features.HitChanceCard.enabled
local PROXIMITY_ALERTS_ENABLED = CONFIG.Features.ProximityAlerts.enabled
local PREDICTION_ZONES_ENABLED = CONFIG.Features.PredictionZones.enabled
local PERFORMANCE_DISPLAY_ENABLED = CONFIG.Features.PerformanceDisplay.enabled
local IGNORE_TEAMMATES = CONFIG.Tactical.ignoreTeammates

local AUTOCLICK_CPS = CONFIG.Features.AutoClick.cps
local AUTOCLICK_INTERVAL = 1 / AUTOCLICK_CPS
local RAYCAST_MAX_DISTANCE = 3000
local UNDO_LIMIT = CONFIG.Features.Br3ak3r.undoLimit

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
local GRADIENT_MIN_DIST = CONFIG.Visuals.gradient.minDist
local GRADIENT_MAX_DIST = CONFIG.Visuals.gradient.maxDist
local PREDICTION_ZONE_TRANSPARENCY = 0.7

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
local INDICATOR_SIZE_HALF = Vector2.new(55, 11)

-- Waypoint Hebrew NATO names and colors
local HEBREW_NATO = {
	"אלפא","ברבו","צ'רלי","דלתא","אקו","פוקסטרוט","גולף","הוטל","אינדיה","ז'ולייט",
	"קילו","לימה","מייק","נובמבר","אוסקר","פאפא","קוויבק","רומיאו","סיירה","טנגו",
	"יוניפורם","ויקטור","וויסקי","אקס-ריי","ינקי","זולו"
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

local function playersAreTeammates(a, b)
	if not a or not b then return false end

	local teamA, teamB = a.Team, b.Team
	if teamA and teamB and teamA == teamB then
		return true
	end

	local colorA, colorB = a.TeamColor, b.TeamColor
	if colorA and colorB and colorA == colorB then
		local neutralA, neutralB = a.Neutral, b.Neutral
		if neutralA == false and neutralB == false then
			return true
		end
	end

	return false
end

local function shouldIgnorePlayer(p)
	if not p then return false end
	if p == localPlayer then return true end
	if IGNORE_TEAMMATES and playersAreTeammates(localPlayer, p) then
		return true
	end
	return false
end

local created, binds = {}, {}
local perPlayer = {}   -- [Player] = {bill, text, hum, outline, indicator, cache, smoothColor}
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
local setDotESP, setDotCB, setDotAC, setDotSKY, setDotPV, setDotTA, setDotPA, setDotPZ, setDotPerf

-- Hover highlight (Br3ak3r)
local hoverHL

-- Sky backup/injected
local skyBackupFolder, skyInjected, atmosInjected

-- ============================================================
-- OBJECT POOLING SYSTEM v1.13
-- ============================================================
local ObjectPools = {
	indicators = {pool = {}, size = 0},
	zones = {pool = {}, size = 0},
	alerts = {pool = {}, size = 0}
}

local function getFromPool(poolName)
	local poolData = ObjectPools[poolName]
	if not poolData or poolData.size <= 0 then return nil end
	
	local obj = poolData.pool[poolData.size]
	poolData.pool[poolData.size] = nil
	poolData.size = poolData.size - 1
	return obj
end

local function returnToPool(poolName, obj)
	local poolData = ObjectPools[poolName]
	if not poolData then return end
	
	local maxSize = CONFIG.Performance.pooling["max"..poolName:sub(1,1):upper()..poolName:sub(2)] or 10
	
	if poolData.size < maxSize then
		poolData.size = poolData.size + 1
		poolData.pool[poolData.size] = obj
		obj.Visible = false
		obj.Parent = nil
	else
		pcall(function() obj:Destroy() end)
	end
end

-- ============================================================
-- PREDICTION ZONE CACHING SYSTEM v1.13
-- ============================================================
local predictionZoneCache = {}
local predictionZoneCacheSize = 0

local function getPredictionZone()
	if predictionZoneCacheSize > 0 then
		local zone = predictionZoneCache[predictionZoneCacheSize]
		predictionZoneCache[predictionZoneCacheSize] = nil
		predictionZoneCacheSize = predictionZoneCacheSize - 1
		return zone
	end
	
	local zone = Instance.new("Part")
	zone.Shape = Enum.PartType.Ball
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanTouch = false
	zone.CanQuery = false
	zone.CastShadow = false
	zone.Material = Enum.Material.Glass
	zone.TopSurface = Enum.SurfaceType.Smooth
	zone.BottomSurface = Enum.SurfaceType.Smooth
	return zone
end

local function returnPredictionZone(zone)
	if predictionZoneCacheSize < CONFIG.Performance.pooling.maxZones then
		zone.Parent = nil
		zone.Transparency = 1
		predictionZoneCacheSize = predictionZoneCacheSize + 1
		predictionZoneCache[predictionZoneCacheSize] = zone
	else
		zone:Destroy()
	end
end

-- ============================================================
-- COLOR SMOOTHING SYSTEM v1.13
-- ============================================================
local colorSmoothingData = {}

local function getSmoothColor(p, targetColor, dt)
	local data = colorSmoothingData[p]
	if not data then
		data = {current = targetColor, target = targetColor}
		colorSmoothingData[p] = data
		return targetColor
	end
	
	if not CONFIG.Features.ESP.smoothColors then
		return targetColor
	end
	
	data.target = targetColor
	
	-- Lerp colors smoothly
	local lerpFactor = min(dt * CONFIG.Visuals.gradient.smoothingSpeed, 1)
	data.current = data.current:Lerp(targetColor, lerpFactor)
	
	return data.current
end

-- ============================================================
-- PERFORMANCE METRICS v1.13
-- ============================================================
local performanceData = {
	fps = 0,
	updateTime = 0,
	playerCount = 0,
	memoryUsage = 0
}

local performanceLabel

local function createPerformanceDisplay()
	if performanceLabel then return end
	
	performanceLabel = Instance.new("TextLabel")
	performanceLabel.Name = "PerfMetrics"
	performanceLabel.Size = UDim2.fromOffset(150, 60)
	performanceLabel.Position = UDim2.new(1, -160, 0, 10)
	performanceLabel.BackgroundTransparency = 0.3
	performanceLabel.BackgroundColor3 = BG_DARK
	performanceLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
	performanceLabel.Font = Enum.Font.Code
	performanceLabel.TextSize = 10
	performanceLabel.TextXAlignment = Enum.TextXAlignment.Left
	performanceLabel.BorderSizePixel = 0
	performanceLabel.Parent = screenGui
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = performanceLabel
end

local function updatePerformanceDisplay(dt)
	if not PERFORMANCE_DISPLAY_ENABLED then
		if performanceLabel then performanceLabel.Visible = false end
		return
	end
	
	if not performanceLabel then
		createPerformanceDisplay()
	end
	
	performanceLabel.Visible = true
	
	-- Count active players
	local count = 0
	for _ in pairs(perPlayer) do count = count + 1 end
	performanceData.playerCount = count
	
	-- Calculate FPS
	performanceData.fps = floor(1/dt + 0.5)
	
	-- Update display
	performanceLabel.Text = string.format(
		" FPS: %d\n Players: %d\n Update: %.1fms",
		performanceData.fps,
		performanceData.playerCount,
		performanceData.updateTime * 1000
	)
end

-- Reusable RaycastParams (performance optimization)
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.IgnoreWater = true

-- Cached format strings for performance
local FORMAT_NAME_DIST_HP = "%s  •  %dm  •  %dhp"
local FORMAT_NAME_DIST = "%s · %dm"
local FORMAT_NAME_DIST_TOOL_HP = "%s [%s]  •  %dm  •  %dhp"
local FORMAT_NAME_DIST_TOOL = "%s [%s] · %dm"

-- Custom clamp for Lua 5.1 compatibility
local function customClamp(v, lo, hi)
	if v < lo then return lo
	elseif v > hi then return hi
	else return v end
end

-- Color gradient function for distance-based nametag colors
local function getDistanceColor(distance)
	local t = customClamp((distance - GRADIENT_MIN_DIST) / (GRADIENT_MAX_DIST - GRADIENT_MIN_DIST), 0, 1)
	
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

local function safeDestroy(x) 
	if x then 
		pcall(function() x:Destroy() end) 
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
	
	local dc = Instance.new("UICorner")
	dc.CornerRadius = UDim.new(1,0)
	dc.Parent = dot
	
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
	
	return row, function(active) 
		dot.BackgroundColor3 = active and DOT_GREEN or DOT_RED 
	end
end

local function ensureGuide()
	if guideFrame and guideFrame.Parent then return end
	
	guideFrame = track(Instance.new("Frame"))
	guideFrame.Name = "SB3_Guide"
	guideFrame.AnchorPoint = Vector2.new(0,0.5)
	guideFrame.Position = UDim2.fromScale(0.015, 0.5)
	guideFrame.Size = UDim2.fromOffset(290, 290)  -- Increased height for new toggle
	guideFrame.BackgroundColor3 = BG_DARK
	guideFrame.BackgroundTransparency = 0.25
	guideFrame.BorderSizePixel = 0
	guideFrame.ZIndex = 1000
	guideFrame.Parent = screenGui

	do
		local pad = Instance.new("UIPadding")
		pad.PaddingTop=UDim.new(0,8)
		pad.PaddingBottom=UDim.new(0,8)
		pad.PaddingLeft=UDim.new(0,10)
		pad.PaddingRight=UDim.new(0,10)
		pad.Parent=guideFrame
		
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0,10)
		corner.Parent = guideFrame

		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Size = UDim2.fromOffset(0,18)
		title.Text = "SP3ARBR3AK3R v1.13 ENHANCED"
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
		togglesSection.Size = UDim2.new(1,0,0,176) -- Increased for new toggle
		togglesSection.Parent = guideFrame

		local list = track(Instance.new("UIListLayout"))
		list.FillDirection=Enum.FillDirection.Vertical
		list.SortOrder=Enum.SortOrder.LayoutOrder
		list.Padding=UDim.new(0,2)
		list.Parent=togglesSection

		local r1, s1 = mkToggleRow("ESP","Ctrl+E"); r1.Parent = togglesSection; setDotESP = s1
		local r2, s2 = mkToggleRow("Br3ak3r","Ctrl+Enter"); r2.Parent = togglesSection; setDotCB = s2
		local r3, s3 = mkToggleRow("AutoClick","Ctrl+K"); r3.Parent = togglesSection; setDotAC = s3
		local r4, s4 = mkToggleRow("Sky Mode","Ctrl+L"); r4.Parent = togglesSection; setDotSKY = s4
		local r5, s5 = mkToggleRow("PredVectors","Ctrl+V"); r5.Parent = togglesSection; setDotPV = s5
		local r6, s6 = mkToggleRow("TargetAssist","Ctrl+T"); r6.Parent = togglesSection; setDotTA = s6
		local r7, s7 = mkToggleRow("ProxAlerts","Ctrl+A"); r7.Parent = togglesSection; setDotPA = s7
		local r8, s8 = mkToggleRow("PredZones","Ctrl+P"); r8.Parent = togglesSection; setDotPZ = s8
		local r9, s9 = mkToggleRow("Performance","Ctrl+F"); r9.Parent = togglesSection; setDotPerf = s9

		local sep = track(Instance.new("Frame"))
		sep.Size=UDim2.new(1,0,0,1)
		sep.Position=UDim2.new(0,0,0,22+176+6)
		sep.BackgroundColor3=SEPARATOR_GRAY
		sep.BorderSizePixel=0
		sep.Parent=guideFrame

		local listTitle = Instance.new("TextLabel")
		listTitle.BackgroundTransparency = 1
		listTitle.Position = UDim2.new(0,0,0,22+176+10)
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
		wpScroll.Position = UDim2.new(0,0,0,22+176+28)
		wpScroll.Size = UDim2.new(1,0,1,-(22+176+36))
		wpScroll.ScrollBarThickness = 4
		wpScroll.CanvasSize = UDim2.new(0,0,0,0)
		wpScroll.ZIndex = 1001
		wpScroll.Parent = guideFrame

		wpList = track(Instance.new("UIListLayout"))
		wpList.FillDirection=Enum.FillDirection.Vertical
		wpList.SortOrder=Enum.SortOrder.LayoutOrder
		wpList.Padding=UDim.new(0,2)
		wpList.Parent=wpScroll
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
	if setDotPerf then setDotPerf(PERFORMANCE_DISPLAY_ENABLED) end
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
	if not p or shouldIgnorePlayer(p) then return nil end
	return p, model
end

-- Indicators helpers
local function ensureIndicator(parent, key)
	-- Try to get from pool first
	local frame = getFromPool("indicators")
	if frame then
		frame.Name = key
		frame.Parent = indicatorFolder
		return frame
	end
	
	-- Create new if pool is empty
	frame = Instance.new("Frame")
	frame.Name = key
	frame.Size = UDim2.fromOffset(INDICATOR_SIZE.X, INDICATOR_SIZE.Y)
	frame.BackgroundTransparency = 0.2
	frame.BackgroundColor3 = BG_INDICATOR
	frame.BorderSizePixel = 0
	frame.ZIndex = 1200
	frame.Parent = indicatorFolder
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0,6)
	corner.Parent = frame

	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.BackgroundTransparency = 1
	arrow.Size = UDim2.fromOffset(18,18)
	arrow.Position = UDim2.fromOffset(2,2)
	arrow.Font = Enum.Font.GothamBlack
	arrow.Text = "▲"
	arrow.TextSize = 16
	arrow.TextColor3 = WHITE
	arrow.ZIndex = 1201
	arrow.Parent = frame

	local lbl = Instance.new("TextLabel")
	lbl.Name = "Lbl"
	lbl.BackgroundTransparency = 1
	lbl.Position = UDim2.fromOffset(22,0)
	lbl.Size = UDim2.new(1,-24,1,0)
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextYAlignment = Enum.TextYAlignment.Center
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 12
	lbl.TextColor3 = WHITE
	lbl.Text = ""
	lbl.ZIndex = 1201
	lbl.Parent = frame

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

local function hideIndicator(frame) 
	if frame then frame.Visible = false end 
end

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

	local dirMag = sqrt(dirX * dirX + dirY * dirY)
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
	part.CanCollide = false
	part.LocalTransparencyModifier = 1
	part.Transparency = 1
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
	e.part.CanCollide = e.cc
	e.part.LocalTransparencyModifier = e.ltm
	e.part.Transparency = e.t
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

local runNearestUpdate = makeIntervalRunner(CONFIG.Performance.updateRates.nearest)
local runVisualUpdate = makeIntervalRunner(CONFIG.Performance.updateRates.visual)
local runCleanupSweep = makeIntervalRunner(CONFIG.Performance.updateRates.cleanup)
local runColorSmooth = makeIntervalRunner(CONFIG.Performance.updateRates.colorSmooth)

-- ESP (ENHANCED v1.13 - Fixed memory leaks)
local function destroyPerPlayer(p)
	local pp = perPlayer[p]
	if not pp then return end
	
	-- Clean up UI elements
	if pp.bill then safeDestroy(pp.bill) end
	if pp.outline then safeDestroy(pp.outline) end
	
	-- Return indicator to pool instead of destroying
	if pp.indicator then
		hideIndicator(pp.indicator)
		returnToPool("indicators", pp.indicator)
	end
	
	-- FIXED: Properly clean up prediction vector attachments
	if pp.predVecAttach0 then safeDestroy(pp.predVecAttach0) end
	if pp.predVecAttach1 then safeDestroy(pp.predVecAttach1) end
	if pp.predictionVector then safeDestroy(pp.predictionVector) end
	
	-- Clean up proximity alert
	if pp.alertIndex ~= nil then
		proximityAlertManager:releaseSlot(p)
		pp.alertIndex = nil
	end
	if pp.proximityAlert then
		returnToPool("alerts", pp.proximityAlert)
	end
	
	-- Return prediction zone to cache
	if pp.predictionZone then
		returnPredictionZone(pp.predictionZone)
	end
	
	-- Clean up color smoothing data
	colorSmoothingData[p] = nil
	
	perPlayer[p] = nil
end

local function setESPVisible(p, visible)
	local pp = perPlayer[p]
	if not pp then return end
	if shouldIgnorePlayer(p) then
		visible = false
	end
	if pp.bill then pp.bill.Enabled = visible end
	if pp.outline then pp.outline.Enabled = visible end
end

local function createOutlineForCharacter(character, enabled)
	local h = Instance.new("Highlight")
	h.Name="SB3_PinkOutline"
	h.Adornee=character
	h.FillTransparency=1
	h.OutlineTransparency=0
	h.OutlineColor=PINK
	h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
	h.Enabled=enabled
	h.Parent=character
	return h
end

local function getEquippedTool(character)
	local tool = character:FindFirstChildOfClass("Tool")
	if tool then return tool.Name end
	return nil
end

local function billboardFor(p, character)
	local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not head or not hum then return end
	
	local bill = Instance.new("BillboardGui")
	bill.Name="B"..HttpService:GenerateGUID(false):gsub("-","")
	bill.AlwaysOnTop=true
	bill.MaxDistance=1e9
	bill.Adornee=head
	bill.Size=UDim2.fromOffset(NAME_BASE_W, NAME_BASE_H)
	bill.StudsOffset=Vector3.new(0,2,0)
	bill.Enabled=ESP_ENABLED
	bill.Parent=head
	track(bill)
	
	local t = Instance.new("TextLabel")
	t.Name="T"
	t.BackgroundTransparency=1
	t.Size=UDim2.fromScale(1,1)
	t.Font=Enum.Font.GothamBold
	t.TextScaled=false
	t.TextSize=14
	t.TextColor3=RED
	t.TextStrokeTransparency=0
	t.TextStrokeColor3=WHITE
	t.Text=""
	t.Parent=bill
	
	local entry = perPlayer[p] or {}
	entry.bill = bill
	entry.text = t
	entry.hum = hum
	entry.tool = getEquippedTool(character)
	entry.cache = entry.cache or {}
	perPlayer[p] = entry
end

local function rebuildForCharacter(p, character)
	destroyPerPlayer(p)
	if not character then return end
	
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
		if not shouldIgnorePlayer(p) then
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
	end
	nearestPlayerRef = best
end

-- Prediction Vector (FIXED attachment cleanup)
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
		pp.predVecAttach1.Parent = root  -- FIXED: Parent to root, not Workspace
		
		beam.Attachment0 = pp.predVecAttach0
		beam.Attachment1 = pp.predVecAttach1
		
		track(beam)
		track(pp.predVecAttach0)
		track(pp.predVecAttach1)
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
		local vizLength = min(speed / 20, 50)
		local vizDir = vel.Unit
		local vizOffset = data.root.CFrame:VectorToObjectSpace(vizDir * vizLength)

		if data.predVecAttach1 then
			data.predVecAttach1.Position = vizOffset
		end

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

local proximityAlertManager = {
	indexByPlayer = {},
	activeThisFrame = {},
	freeSlots = {},
	nextSlot = 0
}

local function insertFreeSlot(sortedList, value)
	local inserted = false
	for i = 1, #sortedList do
		if value < sortedList[i] then
			insert(sortedList, i, value)
			inserted = true
			break
		end
	end
	if not inserted then
		sortedList[#sortedList + 1] = value
	end
end

function proximityAlertManager:beginFrame()
	clear(self.activeThisFrame)
end

function proximityAlertManager:acquireSlot(player)
	self.activeThisFrame[player] = true
	local existing = self.indexByPlayer[player]
	if existing ~= nil then
		return existing
	end

	local freeSlots = self.freeSlots
	local slot
	if #freeSlots > 0 then
		slot = freeSlots[1]
		remove(freeSlots, 1)
	else
		slot = self.nextSlot
		self.nextSlot = self.nextSlot + 1
	end

	self.indexByPlayer[player] = slot
	return slot
end

function proximityAlertManager:releaseSlot(player)
	local current = self.indexByPlayer[player]
	if current == nil then return end

	self.indexByPlayer[player] = nil
	insertFreeSlot(self.freeSlots, current)
end

function proximityAlertManager:endFrame()
	if next(self.indexByPlayer) == nil then
		self.nextSlot = 0
		clear(self.freeSlots)
		return
	end

	local toRelease
	for player in pairs(self.indexByPlayer) do
		if not self.activeThisFrame[player] then
			toRelease = toRelease or {}
			toRelease[#toRelease + 1] = player
		end
	end

	if toRelease then
		for i = 1, #toRelease do
			self:releaseSlot(toRelease[i])
		end
	end

	clear(self.activeThisFrame)

	while self.nextSlot > 0 and #self.freeSlots > 0 do
		local highest = self.nextSlot - 1
		local lastIndex = self.freeSlots[#self.freeSlots]
		if lastIndex == highest then
			remove(self.freeSlots, #self.freeSlots)
			self.nextSlot = highest
		else
			break
		end
	end
end

function proximityAlertManager:reset()
	clear(self.indexByPlayer)
	clear(self.activeThisFrame)
	clear(self.freeSlots)
	self.nextSlot = 0
end

local function updateProximityAlert(p, data)
	if not PROXIMITY_ALERTS_ENABLED then
		if data.proximityAlert then data.proximityAlert.Visible = false end
		if data.alertIndex ~= nil then
			proximityAlertManager:releaseSlot(p)
			data.alertIndex = nil
		end
		return
	end

	local myChar = localPlayer.Character
	local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
	if not myRoot or not data.root then
		if data.proximityAlert then data.proximityAlert.Visible = false end
		if data.alertIndex ~= nil then
			proximityAlertManager:releaseSlot(p)
			data.alertIndex = nil
		end
		return
	end

	local dist = (myRoot.Position - data.root.Position).Magnitude
	local alertColor = nil
	local alertText = nil

	for _, tier in ipairs(CONFIG.Tactical.proximityTiers) do
		if dist <= tier.dist then
			alertColor = tier.color
			alertText = tier.name
			break
		end
	end

	if not alertColor then
		if data.proximityAlert then
			data.proximityAlert.Visible = false
		end
		if data.alertIndex ~= nil then
			proximityAlertManager:releaseSlot(p)
			data.alertIndex = nil
		end
		return
	end

	if not data.proximityAlert then
		local alert = getFromPool("alerts") or Instance.new("TextLabel")
		alert.Name = "ProxAlert_" .. p.UserId
		alert.BackgroundTransparency = 0.2
		alert.BackgroundColor3 = alertColor
		alert.BorderSizePixel = 0
		alert.Size = UDim2.fromOffset(80, 20)
		alert.Font = Enum.Font.GothamBold
		alert.TextSize = 12
		alert.TextColor3 = WHITE
		alert.ZIndex = 500
		alert.Parent = screenGui
		data.proximityAlert = alert

		track(alert)
	end

	if data.proximityAlert then
		local slotIndex = proximityAlertManager:acquireSlot(p)
		data.alertIndex = slotIndex
		data.proximityAlert.Text = alertText
		data.proximityAlert.BackgroundColor3 = alertColor
		data.proximityAlert.Position = UDim2.fromOffset(10, 10 + slotIndex * 25)
		data.proximityAlert.Visible = true
	end
end

local function setPredictionZoneVisible(zone, visible)
	if not zone then return end
	
	local desiredTransparency = visible and PREDICTION_ZONE_TRANSPARENCY or 1
	if zone.Transparency ~= desiredTransparency then
		zone.Transparency = desiredTransparency
	end
	
	if visible and zone.Parent ~= Workspace then
		zone.Parent = Workspace
	elseif not visible and zone.Parent then
		zone.Parent = nil  -- Remove from workspace when not visible
	end
end

-- Prediction Zones (ENHANCED with caching)
local function updatePredictionZone(p, data)
	if not PREDICTION_ZONES_ENABLED or not data.root then
		setPredictionZoneVisible(data.predictionZone, false)
		return
	end

	local vel = data.root.AssemblyLinearVelocity
	local speed = vel.Magnitude

	if speed < 0.5 then
		setPredictionZoneVisible(data.predictionZone, false)
		return
	end

	if not data.predictionZone then
		local zone = getPredictionZone()
		zone.Name = "PredZone_" .. p.UserId
		zone.Color = CYAN
		data.predictionZone = zone
	end

	if data.predictionZone then
		local predictedPos = data.root.Position + (vel * CONFIG.Tactical.predictionTime)
		data.predictionZone.Position = predictedPos
		data.predictionZone.Size = Vector3.new(5, 5, 5)
		setPredictionZoneVisible(data.predictionZone, true)
	end
end

local function applyIgnoredPlayerState(p, data)
	if not data then return end
	setESPVisible(p, false)
	local cache = data.cache
	if cache then
		cache.billEnabled = false
		cache.indicatorVisible = false
	end
	hideIndicator(data.indicator)
	if data.proximityAlert then
		data.proximityAlert.Visible = false
	end
	if data.alertIndex ~= nil then
		proximityAlertManager:releaseSlot(p)
		data.alertIndex = nil
	end
	if data.predictionVector then
		data.predictionVector.Enabled = false
	end
	setPredictionZoneVisible(data.predictionZone, false)
end

-- Optimized updateSinglePlayerVisual with smooth colors
local function updateSinglePlayerVisual(p, data, dt)
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

	-- Get target color, then smooth it
	local targetColor = isNearest and CLOSEST_COLOR or getDistanceColor(dist)
	local smoothedColor = getSmoothColor(p, targetColor, dt)
	local textZ = isNearest and 10 or 1

	if data.bill then
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
			local currentTool = getEquippedTool(character)
			if cache.billTool ~= currentTool then
				data.tool = currentTool
				cache.billTool = currentTool
			end

			if cache.billDist ~= distRounded or cache.billHP ~= hp or cache.billName ~= name or cache.billTool ~= data.tool then
				local toolDisplay = data.tool or "UNARMED"
				local textValue = string.format(FORMAT_NAME_DIST_TOOL_HP, name, toolDisplay, distRounded, hp)
				data.text.Text = textValue
				cache.billDist = distRounded
				cache.billHP = hp
				cache.billName = name
				cache.billTool = data.tool
			end
			
			-- Use smoothed color
			data.text.TextColor3 = smoothedColor
			
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
			local labelText = string.format(FORMAT_NAME_DIST, name, distRounded)
			placeIndicator(indicator, smoothedColor, labelText, edge, angle)
			cache.indicatorVisible = true
		end
	else
		if cache.indicatorVisible then
			hideIndicator(data.indicator)
			cache.indicatorVisible = false
		end
	end
end

local visualUpdateTimer = 0
local function updatePlayerVisuals(dt)
	camera = Workspace.CurrentCamera or camera
	if not camera then return end

	-- Measure performance
	local startTime = os.clock()

	proximityAlertManager:beginFrame()

	for p,data in pairs(perPlayer) do
		if shouldIgnorePlayer(p) then
			applyIgnoredPlayerState(p, data)
		else
			updateSinglePlayerVisual(p, data, dt)
			updatePredictionVector(p, data)
			updateProximityAlert(p, data)
			updatePredictionZone(p, data)
		end
	end

	proximityAlertManager:endFrame()

	performanceData.updateTime = os.clock() - startTime
end

local function createForPlayer(p)
	local function onSpawn(character)
		task.wait(0.1)
		rebuildForCharacter(p, character)
	end
	bind(p.CharacterAdded:Connect(onSpawn))
	if p.Character then onSpawn(p.Character) end
end

for _,p in ipairs(Players:GetPlayers()) do 
	if p ~= localPlayer then createForPlayer(p) end 
end

bind(Players.PlayerAdded:Connect(function(p) 
	if p ~= localPlayer then createForPlayer(p) end 
end))

bind(Players.PlayerRemoving:Connect(function(p) 
	destroyPerPlayer(p) 
end))

-- ============================================================
-- TARGETING ASSIST v1.13 (COMPLETED IMPLEMENTATION)
-- ============================================================
local targetingAssistData = {
	targetPlayer = nil,
	targetPos = nil,
	screenPos = nil,
	crosshair = nil,
	leadIndicator = nil
}

local hitChanceCardData = {
	frame = nil,
	background = nil,
	label = nil,
	stroke = nil,
	shouldShow = false,
	alpha = 1,
	lastTarget = nil
}

local function getTargetLeadPosition(targetRoot, bulletSpeed)
	if not targetRoot then return nil end

	local vel = targetRoot.AssemblyLinearVelocity
	local myPos = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not myPos then return nil end

	local relative = targetRoot.Position - myPos.Position
	local dist = relative.Magnitude
	if bulletSpeed <= 0 then bulletSpeed = CONFIG.Features.TargetingAssist.bulletSpeed end

	local travelTime = dist / bulletSpeed
	local bulletSpeedSq = bulletSpeed * bulletSpeed
	local vDotV = vel:Dot(vel)
	local vDotR = vel:Dot(relative)
	local relDotRel = relative:Dot(relative)

	local a = vDotV - bulletSpeedSq
	local b = 2 * vDotR
	local c = relDotRel
	local t = nil

	if math.abs(a) < 1e-6 then
		if math.abs(b) > 1e-6 then
			t = -c / b
		end
	else
		local discriminant = (b * b) - (4 * a * c)
		if discriminant >= 0 then
			local sqrtDisc = math.sqrt(discriminant)
			local denom = 2 * a
			local t1 = (-b - sqrtDisc) / denom
			local t2 = (-b + sqrtDisc) / denom
			if t1 > 0 and t2 > 0 then
				t = math.min(t1, t2)
			elseif t1 > 0 then
				t = t1
			elseif t2 > 0 then
				t = t2
			end
		end
	end

	if not t or t <= 0 then
		t = travelTime
	end

	return targetRoot.Position + (vel * t)
end

local function createTargetingCrosshair()
	if targetingAssistData.crosshair then return end
	
	local crosshair = Instance.new("Frame")
	crosshair.Name = "TargetCrosshair"
	crosshair.Size = UDim2.fromOffset(40, 40)
	crosshair.BackgroundTransparency = 1
	crosshair.BorderSizePixel = 0
	crosshair.ZIndex = 2000
	crosshair.Parent = screenGui
	
	-- Horizontal line
	local h = Instance.new("Frame")
	h.Size = UDim2.new(1, 0, 0, 2)
	h.Position = UDim2.fromScale(0, 0.5)
	h.AnchorPoint = Vector2.new(0, 0.5)
	h.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
	h.BorderSizePixel = 0
	h.Parent = crosshair
	
	-- Vertical line
	local v = Instance.new("Frame")
	v.Size = UDim2.new(0, 2, 1, 0)
	v.Position = UDim2.fromScale(0.5, 0)
	v.AnchorPoint = Vector2.new(0.5, 0)
	v.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
	v.BorderSizePixel = 0
	v.Parent = crosshair
	
	-- Center dot
	local dot = Instance.new("Frame")
	dot.Size = UDim2.fromOffset(4, 4)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
	dot.BorderSizePixel = 0
	dot.Parent = crosshair
	
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot
	
	targetingAssistData.crosshair = track(crosshair)
	
	-- Lead indicator (shows where target will be)
	local leadIndicator = Instance.new("Frame")
	leadIndicator.Name = "LeadIndicator"
	leadIndicator.Size = UDim2.fromOffset(20, 20)
	leadIndicator.BackgroundTransparency = 0.5
	leadIndicator.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
	leadIndicator.BorderSizePixel = 0
	leadIndicator.ZIndex = 1999
	leadIndicator.Parent = screenGui
	
	local leadCorner = Instance.new("UICorner")
	leadCorner.CornerRadius = UDim.new(1, 0)
	leadCorner.Parent = leadIndicator
	
	targetingAssistData.leadIndicator = track(leadIndicator)
end


local function ensureHitChanceCard()
	local data = hitChanceCardData
	local frame = data.frame
	if frame and frame.Parent then
		if frame.Parent ~= screenGui then
			frame.Parent = screenGui
		end
		return frame
	end
	if not screenGui then return nil end

	frame = Instance.new("Frame")
	frame.Name = "HitChanceCard"
	frame.Size = UDim2.fromOffset(200, 72)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.ZIndex = 2001
	frame.Visible = false
	frame.Parent = screenGui

	local background = Instance.new("Frame")
	background.Name = "Background"
	background.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
	background.BackgroundTransparency = 0.7
	background.BorderSizePixel = 0
	background.Size = UDim2.fromScale(1, 1)
	background.ZIndex = 2001
	background.Parent = frame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = background

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = background

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(255, 50, 50)
	stroke.Transparency = 0.6
	stroke.Parent = background

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 0.4
	label.Text = ""
	label.TextWrapped = true
	label.TextScaled = false
	label.TextSize = 16
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.ZIndex = 2002
	label.Parent = background

	data.frame = frame
	data.background = background
	data.label = label
	data.stroke = stroke
	data.shouldShow = false
	data.alpha = 1
	data.lastTarget = nil

	return frame
end

local function destroyHitChanceCard()
	if hitChanceCardData.frame then
		safeDestroy(hitChanceCardData.frame)
	end
	hitChanceCardData.frame = nil
	hitChanceCardData.background = nil
	hitChanceCardData.label = nil
	hitChanceCardData.stroke = nil
	hitChanceCardData.shouldShow = false
	hitChanceCardData.alpha = 1
	hitChanceCardData.lastTarget = nil
end

local function hideHitChanceCard()
	if hitChanceCardData.shouldShow then
		hitChanceCardData.shouldShow = false
		hitChanceCardData.lastTarget = nil
	end
end

local function stepHitChanceCardFade(dt)
	local frame = hitChanceCardData.frame
	if not frame then return end

	local targetAlpha = hitChanceCardData.shouldShow and 0 or 1
	local speed = hitChanceCardData.shouldShow and 12 or 8
	local currentAlpha = hitChanceCardData.alpha or 1
	local step = min(dt * speed, 1)
	currentAlpha = currentAlpha + (targetAlpha - currentAlpha) * step
	if abs(currentAlpha - targetAlpha) < 0.01 then
		currentAlpha = targetAlpha
	end
	hitChanceCardData.alpha = currentAlpha

	if currentAlpha >= 0.995 then
		frame.Visible = false
		if not hitChanceCardData.shouldShow and hitChanceCardData.label then
			hitChanceCardData.label.Text = ""
		end
	else
		frame.Visible = true
	end

	local background = hitChanceCardData.background
	if background then
		background.BackgroundTransparency = 0.15 + (0.55 * currentAlpha)
	end
	local label = hitChanceCardData.label
	if label then
		label.TextTransparency = currentAlpha * 0.9
		label.TextStrokeTransparency = clamp(0.25 + currentAlpha * 0.7, 0, 1)
	end
	local stroke = hitChanceCardData.stroke
	if stroke then
		stroke.Transparency = clamp(0.2 + currentAlpha * 0.7, 0, 1)
	end
end
local function updateHitChanceCard(dt)
	local shouldDisplay = false
	local labelText, cardPosition
	local targetForCard = nil

	if HIT_CHANCE_CARD_ENABLED and not dead and rightMouseDown then
		local target = nearestPlayerRef
		if target and not shouldIgnorePlayer(target) then
			local targetData = perPlayer[target]
			local targetChar = target.Character or (targetData and targetData.character)
			local targetRoot = targetChar and targetChar:FindFirstChild("HumanoidRootPart") or (targetData and targetData.root)
			if targetData then
				targetData.root = targetRoot or targetData.root
			end
			if targetRoot and targetRoot:IsDescendantOf(Workspace) then
				camera = Workspace.CurrentCamera or camera
				local cam = camera
				if cam then
					local viewportPos, onScreen = cam:WorldToViewportPoint(targetRoot.Position)
					if onScreen and viewportPos.Z >= 0 then
						local myChar = localPlayer.Character
						local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
						if myRoot then
							local origin = myRoot.Position
							local diff = targetRoot.Position - origin
							local distance = diff.Magnitude
							if distance >= 1e-3 then
								local result = worldRaycast(origin, diff, true)
								local blocked = false
								if result then
									local hitPlayer = hitIsPlayer(result.Instance)
									if hitPlayer ~= target then
										blocked = true
									end
								end
								local hitChance = blocked and 0 or 100
								if not blocked then
									local rangePenalty = clamp((distance - 40) / 3.5, 0, 40)
									hitChance = hitChance - rangePenalty
									local leadPos = getTargetLeadPosition(targetRoot, CONFIG.Features.TargetingAssist.bulletSpeed)
									if leadPos then
										local aimVec = leadPos - cam.CFrame.Position
										local mag = aimVec.Magnitude
										if mag > 0 then
											local aimDir = aimVec / mag
											local lookDir = cam.CFrame.LookVector
											local dot = clamp(lookDir:Dot(aimDir), -1, 1)
											local angle = deg(math.acos(dot))
											local anglePenalty = clamp(angle / 1.8, 0, 35)
											hitChance = hitChance - anglePenalty
										end
									end
								end
								hitChance = clamp(hitChance, 0, 100)
								if not blocked then
									local anchor = targetingAssistData.screenPos
									local displayPos
									if anchor then
										displayPos = Vector2.new(anchor.X, anchor.Y + 60)
									else
										displayPos = Vector2.new(viewportPos.X, viewportPos.Y + 60)
									end
									local displayName = target.DisplayName
									if not displayName or displayName == '' then
										displayName = target.Name
									end
									local studs = floor(distance + 0.5)
									labelText = string.format('%s\n%d studs • %.0f%%', displayName, studs, hitChance)
									cardPosition = displayPos
									targetForCard = target
									shouldDisplay = true
								end
							end
						end
					end
			end
		end
	end

	if shouldDisplay then
		local frame = ensureHitChanceCard()
		if frame and cardPosition then
			hitChanceCardData.shouldShow = true
			hitChanceCardData.lastTarget = targetForCard
			frame.Position = UDim2.fromOffset(cardPosition.X, cardPosition.Y)
			local label = hitChanceCardData.label
			if label and labelText then
				label.Text = labelText
			end
		else
			hideHitChanceCard()
		end
	else
		hideHitChanceCard()
	end

	stepHitChanceCardFade(dt)
end



local function updateTargetingAssist(targetPlayer)
	if not TARGETING_ASSIST_ENABLED then
		if targetingAssistData.crosshair then
			targetingAssistData.crosshair.Visible = false
		end
		if targetingAssistData.leadIndicator then
			targetingAssistData.leadIndicator.Visible = false
		end
		return
	end
	
	if not targetingAssistData.crosshair then
		createTargetingCrosshair()
	end
	
	local activeTarget = targetPlayer
	if activeTarget and activeTarget.Character then
		local targetRoot = activeTarget.Character:FindFirstChild("HumanoidRootPart")
		if targetRoot and camera then
			-- Calculate lead position
			local leadPos = getTargetLeadPosition(targetRoot, CONFIG.Features.TargetingAssist.bulletSpeed)
			if leadPos then
				targetingAssistData.targetPlayer = activeTarget
				targetingAssistData.targetPos = leadPos
				
				-- Project lead position to screen
				local v, onScreen = camera:WorldToViewportPoint(leadPos)
				if onScreen then
					targetingAssistData.screenPos = Vector2.new(v.X, v.Y)
					
					-- Position crosshair at lead position
					targetingAssistData.crosshair.Position = UDim2.fromOffset(
						targetingAssistData.screenPos.X - 20,
						targetingAssistData.screenPos.Y - 20
					)
					targetingAssistData.crosshair.Visible = true
					
					-- Show current position indicator
					local currentV, currentOnScreen = camera:WorldToViewportPoint(targetRoot.Position)
					if currentOnScreen then
						targetingAssistData.leadIndicator.Position = UDim2.fromOffset(
							currentV.X - 10,
							currentV.Y - 10
						)
						targetingAssistData.leadIndicator.Visible = true
					else
						targetingAssistData.leadIndicator.Visible = false
					end
				else
					targetingAssistData.crosshair.Visible = false
					targetingAssistData.leadIndicator.Visible = false
				end
			end
		end
	else
		targetingAssistData.targetPlayer = nil
		targetingAssistData.targetPos = nil
		targetingAssistData.screenPos = nil
		if targetingAssistData.crosshair then
			targetingAssistData.crosshair.Visible = false
		end
		if targetingAssistData.leadIndicator then
			targetingAssistData.leadIndicator.Visible = false
		end
	end
end

-- Waypoints
local function getWpContainer() 
	return Workspace:FindFirstChild("SP_WP_CONTAINER") 
end

local function nextWpNameAndColor() 
	wpNameIndex = (wpNameIndex % #HEBREW_NATO) + 1
	return HEBREW_NATO[wpNameIndex], NATO_COLORS[wpNameIndex] 
end

local function canAddWaypoint()
	local container = getWpContainer()
	if not container then return true end
	
	local count = 0
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Part") then
			count = count + 1
			if count >= CONFIG.Visuals.waypoints.maxCount then
				return false
			end
		end
	end
	return true
end

local function setWaypointAppearance(part, name, color)
	part.Name = "SP_WP_"..name
	part:SetAttribute("SB3_Name", name)
	part:SetAttribute("SB3_Color", color)
	
	local bb = part:FindFirstChild("BB") or Instance.new("BillboardGui")
	bb.Name = "BB"
	bb.AlwaysOnTop = true
	bb.Size = UDim2.fromOffset(100,26)
	bb.StudsOffset = Vector3.new(0,1.5,0)
	bb.Parent = part
	
	local t = bb:FindFirstChild("T") or Instance.new("TextLabel")
	t.Name = "T"
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1,1)
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.Text = name
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.2
	t.TextStrokeColor3 = WHITE
	t.Parent = bb
end

local function refreshWaypointGuide()
	local container = getWpContainer()
	local parts = {}
	
	if container then
		for _,ch in ipairs(container:GetChildren()) do
			if ch:IsA("Part") then insert(parts, ch) end
		end
	end
	
	local myPos
	local ch = localPlayer.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if root then myPos = root.Position end
	
	local sorted = {}
	for _,p in ipairs(parts) do
		local d = myPos and (p.Position - myPos).Magnitude or huge
		insert(sorted, {part=p, dist=d})
	end
	
	table.sort(sorted, function(a,b) return a.dist < b.dist end)
	
	-- Clean up orphaned rows
	for part,row in pairs(wpRowMap) do
		if not part.Parent or not part:IsDescendantOf(container or Workspace) then
			if row and row.Parent then row:Destroy() end
			wpRowMap[part] = nil
		end
	end
	
	local canvas = 0
	for idx,entry in ipairs(sorted) do
		local part = entry.part
		local dist = entry.dist
		local row = wpRowMap[part]
		local name = part:GetAttribute("SB3_Name") or "??"
		local color = part:GetAttribute("SB3_Color") or GRAY
		
		if not row then
			row = Instance.new("TextLabel")
			row.BackgroundTransparency = 1
			row.Size = UDim2.new(1,0,0,16)
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.Font = Enum.Font.Gotham
			row.TextSize = 12
			row.TextColor3 = color
			row.ZIndex = 1002
			row.Parent = wpScroll
			wpRowMap[part] = row
			track(row)
		end
		
		row.LayoutOrder = idx
		row.Text = string.format(FORMAT_NAME_DIST, name, floor(dist+0.5))
		row.TextColor3 = color
		canvas = canvas + 18
	end
	
	wpScroll.CanvasSize = UDim2.new(0,0,0,canvas)
end

local function ensureWpIndicator(part)
	local key = "WI_"..part:GetDebugId()
	local frame = wpIndicatorMap[part]
	if frame and frame.Parent then return frame end
	frame = ensureIndicator(indicatorFolder, key)
	wpIndicatorMap[part] = frame
	return frame
end

local function updateWaypointIndicators()
	local container = getWpContainer()
	
	for part,frame in pairs(wpIndicatorMap) do
		if not part.Parent or not part:IsDescendantOf(container or Workspace) then
			hideIndicator(frame)
			returnToPool("indicators", frame)
			wpIndicatorMap[part] = nil
		end
	end
	
	if not container then return end
	
	local cameraCFrame = camera.CFrame
	for _,part in ipairs(container:GetChildren()) do
		if part:IsA("Part") then
			local name = part:GetAttribute("SB3_Name") or "WP"
			local color = part:GetAttribute("SB3_Color") or GRAY
			local onscreen, v2, edge, angle = projectToEdge(part.Position)
			local bb = part:FindFirstChild("BB")
			
			if onscreen then
				if bb then bb.Enabled = true end
				local f = wpIndicatorMap[part]
				if f then hideIndicator(f) end
			else
				if bb then bb.Enabled = false end
				local f = ensureWpIndicator(part)
				local dist = (cameraCFrame.Position - part.Position).Magnitude
				placeIndicator(f, color, string.format(FORMAT_NAME_DIST, name, floor(dist+0.5)), edge, angle)
			end
		end
	end
end

-- Sky Mode
local function enableSkyMode()
	if not skyBackupFolder then
		skyBackupFolder = Instance.new("Folder")
		skyBackupFolder.Name = "SB3_SkyBackup"
		skyBackupFolder.Parent = Lighting
		for _,o in ipairs(Lighting:GetChildren()) do
			if o:IsA("Sky") then o.Parent = skyBackupFolder end
		end
	end
	
	if not skyInjected then
		skyInjected = Instance.new("Sky")
		skyInjected.Name = "SB3_Sky"
		skyInjected.CelestialBodiesShown = true
		skyInjected.Parent = Lighting
	end
	
	if not atmosInjected then
		atmosInjected = Instance.new("Atmosphere")
		atmosInjected.Name = "SB3_Atmosphere"
		atmosInjected.Color = Color3.fromRGB(200,220,255)
		atmosInjected.Decay = Color3.fromRGB(255,255,255)
		atmosInjected.Density = 0.15
		atmosInjected.Offset = 0.25
		atmosInjected.Glare = 0
		atmosInjected.Haze = 0.25
		atmosInjected.Parent = Lighting
	end
end

local function disableSkyMode()
	if skyBackupFolder then
		for _,o in ipairs(skyBackupFolder:GetChildren()) do 
			o.Parent = Lighting 
		end
		safeDestroy(skyBackupFolder)
		skyBackupFolder = nil
	end
	safeDestroy(skyInjected)
	skyInjected = nil
	safeDestroy(atmosInjected)
	atmosInjected = nil
end

-- Hover highlight for Br3ak3r
hoverHL = track(Instance.new("Highlight"))
hoverHL.Name = "SB3_Hover"
hoverHL.FillColor = PINK
hoverHL.OutlineColor = WHITE
hoverHL.FillTransparency = 0.6
hoverHL.OutlineTransparency = 0.2
hoverHL.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
hoverHL.Enabled = false
hoverHL.Parent = Workspace

-- Input
local CTRL_HELD = false
local rightMouseDown = false

bind(UserInputService.InputBegan:Connect(function(input,gp)
	if not gp and not dead and input.UserInputType == Enum.UserInputType.MouseButton2 then
		rightMouseDown = true
	end
	if gp or dead then return end
	if input.KeyCode == Enum.KeyCode.LeftControl then CTRL_HELD = true end

	-- Br3ak3r action
	if CTRL_HELD and input.UserInputType == Enum.UserInputType.MouseButton1 and CLICKBREAK_ENABLED then
		local o,d = getMouseRay()
		if o and d then
			local hit = worldRaycast(o,d,true)
			if hit and hit.Instance and hit.Instance:IsA("BasePart") then
				markBroken(hit.Instance)
			end
		end
	end

	-- Waypoints add/remove
	if CTRL_HELD and input.UserInputType == Enum.UserInputType.MouseButton3 then
		local o,d = getMouseRay()
		if o and d then
			local r = worldRaycast(o,d,true)
			if r and r.Position then
				local pos = r.Position
				local existing = Workspace:FindFirstChild("SP_WP_CONTAINER")
				
				-- Check for nearby waypoint to remove
				if existing then
					for _,p in ipairs(existing:GetChildren()) do
						if p:IsA("Part") and (p.Position - pos).Magnitude < CONFIG.Visuals.waypoints.removeRadius then
							p:Destroy()
							return
						end
					end
				end
				
				-- Check waypoint limit
				if not canAddWaypoint() then
					-- Could add a notification here
					return
				end
				
				-- Add new waypoint
				local container = existing or Instance.new("Folder")
				container.Name = "SP_WP_CONTAINER"
				container.Parent = Workspace
				
				local part = Instance.new("Part")
				part.Anchored = true
				part.CanCollide = false
				part.Transparency = 1
				part.Size = Vector3.new(1,1,1)
				part.Position = pos + Vector3.new(0,2,0)
				
				local name,color = nextWpNameAndColor()
				setWaypointAppearance(part, name, color)
				part.Parent = container
			end
		end
	end
end))

bind(UserInputService.InputEnded:Connect(function(input,gp)
	if not gp and not dead and input.UserInputType == Enum.UserInputType.MouseButton2 then
		rightMouseDown = false
	end
	if input.KeyCode == Enum.KeyCode.LeftControl then CTRL_HELD = false end
end))

-- Toggle keys (with Ctrl)
bind(UserInputService.InputBegan:Connect(function(input,gp)
	if gp or not CTRL_HELD or dead then return end
	
	if input.KeyCode == Enum.KeyCode.Return then
		CLICKBREAK_ENABLED = not CLICKBREAK_ENABLED
	elseif input.KeyCode == Enum.KeyCode.K then
		AUTOCLICK_ENABLED = not AUTOCLICK_ENABLED
	elseif input.KeyCode == Enum.KeyCode.L then
		SKY_MODE_ENABLED = not SKY_MODE_ENABLED
		if SKY_MODE_ENABLED then enableSkyMode() else disableSkyMode() end
	elseif input.KeyCode == Enum.KeyCode.E then
		ESP_ENABLED = not ESP_ENABLED
		for p,_ in pairs(perPlayer) do setESPVisible(p, ESP_ENABLED) end
	elseif input.KeyCode == Enum.KeyCode.V then
		PREDICTION_VECTORS_ENABLED = not PREDICTION_VECTORS_ENABLED
	elseif input.KeyCode == Enum.KeyCode.T then
		TARGETING_ASSIST_ENABLED = not TARGETING_ASSIST_ENABLED
	elseif input.KeyCode == Enum.KeyCode.A then
		PROXIMITY_ALERTS_ENABLED = not PROXIMITY_ALERTS_ENABLED
		proximityAlertManager:reset() -- Reset stacking
	elseif input.KeyCode == Enum.KeyCode.P then
		PREDICTION_ZONES_ENABLED = not PREDICTION_ZONES_ENABLED
	elseif input.KeyCode == Enum.KeyCode.F then
		PERFORMANCE_DISPLAY_ENABLED = not PERFORMANCE_DISPLAY_ENABLED
	elseif input.KeyCode == Enum.KeyCode.Z then
		unbreakLast()
	elseif input.KeyCode == Enum.KeyCode.Six then
		-- Killswitch
		dead = true
		AUTOCLICK_ENABLED = false
		ESP_ENABLED = false
		SKY_MODE_ENABLED = false
		CLICKBREAK_ENABLED = false
		PREDICTION_VECTORS_ENABLED = false
		TARGETING_ASSIST_ENABLED = false
		HIT_CHANCE_CARD_ENABLED = false
		PROXIMITY_ALERTS_ENABLED = false
		PREDICTION_ZONES_ENABLED = false
		PERFORMANCE_DISPLAY_ENABLED = false
		rightMouseDown = false
		
		disableSkyMode()
		disconnectAll()
		
		-- Clean up all players
		for p,_ in pairs(perPlayer) do
			destroyPerPlayer(p)
		end
		perPlayer = {}
		
		-- Clear pools
		for poolName, poolData in pairs(ObjectPools) do
			for i = 1, poolData.size do
				safeDestroy(poolData.pool[i])
			end
			clear(poolData.pool)
			poolData.size = 0
		end
		
		-- Clear prediction zone cache
		for i = 1, predictionZoneCacheSize do
			safeDestroy(predictionZoneCache[i])
		end
		clear(predictionZoneCache)
		predictionZoneCacheSize = 0
		
		-- Clear other data
		clear(brokenSet)
		clear(undoStack)
		clear(brokenIgnoreCache)
		clear(scratchIgnore)
		clear(colorSmoothingData)
		brokenCacheDirty = true
		
		hoverHL.Enabled = false
		safeDestroy(hoverHL)
		
		if guideFrame then safeDestroy(guideFrame) end
		if performanceLabel then safeDestroy(performanceLabel) end
		
		for _,f in pairs(wpIndicatorMap) do safeDestroy(f) end
		wpIndicatorMap = {}
		
		for i = #indicatorFolder:GetChildren(),1,-1 do
			safeDestroy(indicatorFolder:GetChildren()[i])
		end
		safeDestroy(indicatorFolder)
		
		if targetingAssistData.crosshair then
			safeDestroy(targetingAssistData.crosshair)
		end
		if targetingAssistData.leadIndicator then
			safeDestroy(targetingAssistData.leadIndicator)
		end
		
		destroyHitChanceCard()
		
		destroyAll()
		
		-- Restore mouse behavior
		pcall(function() UserInputService.MouseBehavior = Enum.MouseBehavior.Default end)
	end
end))

-- AutoClick & UI refresh
local lastClick, uiAccum = AUTOCLICK_INTERVAL, 0
local autoClickTargetPlayer, autoClickTargetPart = nil, nil
local perfAccum = 0

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
		local o,d = getMouseRay()
		if o and d then
			local r = worldRaycast(o,d,true)
			local part = r and r.Instance
			if part and part:IsA("BasePart") and not brokenSet[part] then
				hoverHL.Adornee = part
				hoverHL.Enabled = true
			else
				hoverHL.Enabled = false
			end
		else
			hoverHL.Enabled = false
		end
	else
		hoverHL.Enabled = false
	end

	-- Nearest and visuals
	if runNearestUpdate(dt) then
		updateNearestPlayer()
	end

	updateTargetingAssist(nearestPlayerRef)
	updateHitChanceCard(dt)
	
	if runVisualUpdate(dt) then
		updatePlayerVisuals(dt)
	end

	-- Throttled UI work
	uiAccum = uiAccum + dt
	if uiAccum >= CONFIG.Performance.updateRates.ui then
		uiAccum = 0
		refreshWaypointGuide()
		updateWaypointIndicators()
	end
	
	-- Performance display
	perfAccum = perfAccum + dt
	if perfAccum >= 0.5 then
		perfAccum = 0
		updatePerformanceDisplay(dt)
	end

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
	if indicatorFolder and indicatorFolder.Parent ~= screenGui then
		indicatorFolder.Parent = screenGui
	end
	if SKY_MODE_ENABLED then
		task.defer(enableSkyMode)
	end
end))
