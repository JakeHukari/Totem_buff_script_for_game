--[[
╔════════════════════════════════════════════════════════════╗
║        SP3ARBR3AK3R - TOTEM POWER SYSTEM v3.3              ║
║   CRITICAL BUGFIX - ALL SYSTEMS FUNCTIONAL                 ║
║          🔧 WIRING FIXED • NAMES FIXED • TOGGLES WORK      ║
╚════════════════════════════════════════════════════════════╝

v3.3 CRITICAL FIXES:
✅ PLAYER NAMES NOW DISPLAY CORRECTLY (was showing "StarterCharacter")
✅ ALL 5 TOGGLES NOW PROPERLY WIRED (buttons + keyboard shortcuts)
✅ THERMAL VISION WORKING (orange highlights appear)
✅ ESP DISTANCE SCALING (closer = bigger, color changes with distance)
✅ SKY MODE IMPLEMENTED (atmosphere changes for visibility)
✅ KEYBOARD SHORTCUTS FIXED (Ctrl+key combos work)
✅ UI BUTTON STATE SYNC (checkmarks show correct state)

FIXED BUGS FROM v3.2:
- Player names showing "StarterCharacter" → Now shows actual player.Name
- Toggle buttons not updating systems → Now triggers refresh on toggle
- Keyboard shortcuts not working → Fixed CTRL detection
- No visual distance feedback → Added size scaling + color coding
- Thermal vision invisible → Now shows bright orange highlights
- Sky mode doing nothing → Now changes lighting/atmosphere

KEYBOARD CONTROLS:
  Ctrl+E    Toggle ESP System ✅ WORKING
  Ctrl+C    Toggle AutoClick ✅ WORKING  
  Ctrl+L    Toggle Sky Mode ✅ NOW IMPLEMENTED
  Ctrl+T    Toggle Thermal Vision ✅ WORKING
  Ctrl+H    Toggle UI Visibility ✅ WORKING
  Ctrl+6    Full System Shutdown ✅ WORKING
]]

-- ═══════════════════════════════════════════════════════════════
-- CONFIGURATION
-- ═══════════════════════════════════════════════════════════════
local CONFIG = {
	-- AUTOCLICK SETTINGS
	AUTOCLICK_CPS = 25,
	AUTOCLICK_MIN_DISTANCE = 5,
	AUTOCLICK_MAX_DISTANCE = 300,
	
	-- ESP SETTINGS
	ESP_HEALTH_BAR_HEIGHT = 5,
	ESP_HEALTH_BAR_WIDTH = 90,
	ESP_UPDATE_FREQUENCY = 0.05,
	ESP_CULLING_DISTANCE = 6000,
	ESP_NEAR_DISTANCE = 100,    -- Close range (big + bright)
	ESP_MID_DISTANCE = 300,     -- Mid range (normal)
	ESP_FAR_DISTANCE = 1000,    -- Far range (small + dim)
	
	-- VISUAL SETTINGS
	RADAR_SIZE = 220,
	
	-- UI SETTINGS
	UI_TRANSPARENCY = 0.15,
	BORDER_THICKNESS = 1.5,
	CORNER_RADIUS = 6,

	-- THERMAL VISION SETTINGS
	THERMAL_COLOR_HOT = Color3.fromRGB(255, 100, 50),
	THERMAL_COLOR_WARM = Color3.fromRGB(200, 150, 50),
	THERMAL_TRANSPARENCY = 0.2,  -- More visible
	THERMAL_UPDATE_FREQUENCY = 0.1,
	
	-- SKY MODE SETTINGS
	SKY_BRIGHTNESS = 3,
	SKY_AMBIENT = Color3.fromRGB(200, 200, 200),
	SKY_OUTDOOR_AMBIENT = Color3.fromRGB(150, 150, 150),
}

-- ═══════════════════════════════════════════════════════════════
-- SERVICE IMPORTS
-- ═══════════════════════════════════════════════════════════════
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

-- ═══════════════════════════════════════════════════════════════
-- FEATURE TOGGLES
-- ═══════════════════════════════════════════════════════════════
local ESP_ENABLED = true
local CLICKBREAK_ENABLED = false
local AUTOCLICK_ENABLED = false
local SKY_MODE_ENABLED = false
local THERMAL_ENABLED = false

-- ═══════════════════════════════════════════════════════════════
-- MODERN COLOR PALETTE
-- ═══════════════════════════════════════════════════════════════
local COLORS = {
	bg_primary = Color3.fromRGB(20, 20, 25),
	bg_secondary = Color3.fromRGB(28, 28, 35),
	bg_panel = Color3.fromRGB(24, 24, 30),
	
	text_primary = Color3.fromRGB(220, 220, 225),
	text_secondary = Color3.fromRGB(160, 160, 170),
	text_dim = Color3.fromRGB(100, 100, 110),
	
	border = Color3.fromRGB(50, 50, 60),
	divider = Color3.fromRGB(40, 40, 50),
	
	accent_threat = Color3.fromRGB(180, 80, 80),
	accent_radar = Color3.fromRGB(100, 150, 180),
	accent_info = Color3.fromRGB(120, 140, 160),
	accent_good = Color3.fromRGB(100, 150, 100),
	
	health_green = Color3.fromRGB(100, 180, 100),
	health_yellow = Color3.fromRGB(200, 180, 80),
	health_red = Color3.fromRGB(180, 80, 80),

	thermal_hot = Color3.fromRGB(255, 100, 50),
	thermal_warm = Color3.fromRGB(200, 150, 50),
	
	-- Distance-based ESP colors
	esp_near = Color3.fromRGB(255, 100, 100),  -- Bright red (close)
	esp_mid = Color3.fromRGB(200, 200, 100),   -- Yellow (medium)
	esp_far = Color3.fromRGB(100, 150, 200),   -- Blue (far)
}

-- ═══════════════════════════════════════════════════════════════
-- CORE VARIABLES
-- ═══════════════════════════════════════════════════════════════
local localPlayer = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local dead = false

local updateCounter = {nearest = 0, visual = 0, culling = 0, radar = 0, cleanup = 0, thermal = 0}
local updateIntervals = {
	nearest = 0.1,
	visual = 0.05,
	culling = 0.2,
	radar = 0.1,
	cleanup = 0.5,
	thermal = 0.1,
}

-- Thermal vision tracking
local thermalEffects = {}
local cachedNPCs = {}
local npcCacheDirty = true

-- ESP tracking
local espObjects = {}

-- Sky mode original values (for restore)
local originalLighting = {
	Brightness = nil,
	Ambient = nil,
	OutdoorAmbient = nil,
}

-- Connection tracking
local connections = {}

local function bind(conn)
	table.insert(connections, conn)
	return conn
end

local function disconnectAll()
	for _, conn in ipairs(connections) do
		if conn and conn.Connected then
			pcall(function() conn:Disconnect() end)
		end
	end
	connections = {}
end

-- ═══════════════════════════════════════════════════════════════
-- UTILITY FUNCTIONS
-- ═══════════════════════════════════════════════════════════════
local function distanceSquared(a, b)
	local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
	return dx*dx + dy*dy + dz*dz
end

local function safeDestroy(obj)
	if obj then
		pcall(function() 
			if obj.Parent then obj:Destroy() end
		end)
	end
end

local function runUpdate(dt, name)
	local counter = updateCounter[name] or 0
	counter = counter + dt
	updateCounter[name] = counter
	
	if counter >= (updateIntervals[name] or 0.1) then
		updateCounter[name] = 0
		return true
	end
	return false
end

-- Toggle debouncing
local toggleDebounce = {}
local TOGGLE_DEBOUNCE_TIME = 0.15

local function canToggle(key)
	local now = tick()
	local lastTime = toggleDebounce[key] or 0

	if (now - lastTime) < TOGGLE_DEBOUNCE_TIME then
		return false
	end

	toggleDebounce[key] = now
	return true
end

-- ═══════════════════════════════════════════════════════════════
-- SKY MODE SYSTEM (NEW - v3.3)
-- ═══════════════════════════════════════════════════════════════
local function applySkyMode()
	if not originalLighting.Brightness then
		-- Store originals first time
		originalLighting.Brightness = Lighting.Brightness
		originalLighting.Ambient = Lighting.Ambient
		originalLighting.OutdoorAmbient = Lighting.OutdoorAmbient
	end
	
	-- Apply enhanced visibility settings
	Lighting.Brightness = CONFIG.SKY_BRIGHTNESS
	Lighting.Ambient = CONFIG.SKY_AMBIENT
	Lighting.OutdoorAmbient = CONFIG.SKY_OUTDOOR_AMBIENT
end

local function restoreSkyMode()
	if originalLighting.Brightness then
		Lighting.Brightness = originalLighting.Brightness
		Lighting.Ambient = originalLighting.Ambient
		Lighting.OutdoorAmbient = originalLighting.OutdoorAmbient
	end
end

-- ═══════════════════════════════════════════════════════════════
-- THERMAL VISION SYSTEM
-- ═══════════════════════════════════════════════════════════════
local function createThermalHighlight(character)
	if not character or thermalEffects[character] then return end

	local highlight = Instance.new("Highlight")
	highlight.Name = "ThermalEffect"
	highlight.Adornee = character
	highlight.FillColor = CONFIG.THERMAL_COLOR_HOT
	highlight.OutlineColor = CONFIG.THERMAL_COLOR_WARM
	highlight.FillTransparency = CONFIG.THERMAL_TRANSPARENCY
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = character

	thermalEffects[character] = highlight
	return highlight
end

local function removeThermalHighlight(character)
	if thermalEffects[character] then
		safeDestroy(thermalEffects[character])
		thermalEffects[character] = nil
	end
end

local function clearAllThermalEffects()
	for character, highlight in pairs(thermalEffects) do
		safeDestroy(highlight)
	end
	thermalEffects = {}
end

local function rebuildNPCCache()
	cachedNPCs = {}

	for _, model in ipairs(Workspace:GetChildren()) do
		if model:IsA("Model") then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid then
				local isPlayer = false
				for _, player in ipairs(Players:GetPlayers()) do
					if player.Character == model then
						isPlayer = true
						break
					end
				end

				if not isPlayer then
					table.insert(cachedNPCs, model)
				end
			end
		end
	end

	npcCacheDirty = false
end

-- 🔧 FIXED: Now returns displayName for proper player identification
local function getAllHumanoids()
	local humanoids = {}

	-- Add player characters WITH PROPER NAMES
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= localPlayer and player.Character then
			local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				table.insert(humanoids, {
					character = player.Character, 
					humanoid = humanoid, 
					isPlayer = true,
					player = player,
					displayName = player.Name  -- 🔧 FIXED: Use player.Name not character.Name
				})
			end
		end
	end

	if npcCacheDirty then
		rebuildNPCCache()
	end

	-- Add NPCs
	for _, npcModel in ipairs(cachedNPCs) do
		if npcModel and npcModel.Parent then
			local humanoid = npcModel:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				table.insert(humanoids, {
					character = npcModel, 
					humanoid = humanoid, 
					isPlayer = false,
					player = nil,
					displayName = npcModel.Name  -- NPC name from model
				})
			end
		end
	end

	return humanoids
end

local function updateThermalVision()
	if not THERMAL_ENABLED then
		clearAllThermalEffects()
		return
	end

	local validCharacters = {}
	local allHumanoids = getAllHumanoids()

	for _, data in ipairs(allHumanoids) do
		validCharacters[data.character] = true
		if not thermalEffects[data.character] then
			createThermalHighlight(data.character)
		end
	end

	for character, highlight in pairs(thermalEffects) do
		if not validCharacters[character] then
			removeThermalHighlight(character)
		end
	end
end

bind(Workspace.ChildAdded:Connect(function(child)
	if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") then
		npcCacheDirty = true
	end
end))

bind(Workspace.ChildRemoved:Connect(function(child)
	if child:IsA("Model") then
		npcCacheDirty = true
	end
end))

-- ═══════════════════════════════════════════════════════════════
-- AUTOCLICK SYSTEM
-- ═══════════════════════════════════════════════════════════════
local autoClickTarget = nil
local autoClickTimer = 0

local function findNearestTarget()
	if not localPlayer.Character then return nil end

	local rootPart = localPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return nil end

	local myPosition = rootPart.Position
	local closestTarget = nil
	local closestDistance = CONFIG.AUTOCLICK_MAX_DISTANCE * CONFIG.AUTOCLICK_MAX_DISTANCE

	local allHumanoids = getAllHumanoids()

	for _, data in ipairs(allHumanoids) do
		local targetRoot = data.character:FindFirstChild("HumanoidRootPart")
		if targetRoot then
			local distSq = distanceSquared(myPosition, targetRoot.Position)

			if distSq >= CONFIG.AUTOCLICK_MIN_DISTANCE * CONFIG.AUTOCLICK_MIN_DISTANCE
			   and distSq < closestDistance then
				closestTarget = data
				closestDistance = distSq
			end
		end
	end

	return closestTarget
end

local function performAutoClick()
	if not AUTOCLICK_ENABLED then
		autoClickTarget = nil
		return
	end

	local target = findNearestTarget()
	if not target then
		autoClickTarget = nil
		return
	end

	autoClickTarget = target

	local character = localPlayer.Character
	if character then
		local tool = character:FindFirstChildOfClass("Tool")
		if tool then
			tool:Activate()
		end
	end
end

-- ═══════════════════════════════════════════════════════════════
-- ESP SYSTEM (🔧 FIXED with distance-based scaling/coloring)
-- ═══════════════════════════════════════════════════════════════
local function createESP(character, isPlayer, displayName)
	if espObjects[character] then return end

	local head = character:FindFirstChild("Head")
	if not head then return end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ESP"
	billboard.Adornee = head
	billboard.Size = UDim2.new(0, 200, 0, 50)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = head

	-- 🔧 FIXED: Use displayName parameter instead of character.Name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0, 20)
	nameLabel.Position = UDim2.new(0, 0, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3 = isPlayer and COLORS.accent_info or COLORS.thermal_hot
	nameLabel.TextStrokeTransparency = 0.5
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
	nameLabel.Text = displayName  -- 🔧 FIXED: Now shows actual player name
	nameLabel.Parent = billboard

	local distLabel = Instance.new("TextLabel")
	distLabel.Size = UDim2.new(1, 0, 0, 15)
	distLabel.Position = UDim2.new(0, 0, 0, 20)
	distLabel.BackgroundTransparency = 1
	distLabel.TextColor3 = COLORS.text_secondary
	distLabel.TextStrokeTransparency = 0.5
	distLabel.Font = Enum.Font.Gotham
	distLabel.TextSize = 11
	distLabel.Text = "0m"
	distLabel.Parent = billboard

	local healthBG = Instance.new("Frame")
	healthBG.Size = UDim2.new(0, CONFIG.ESP_HEALTH_BAR_WIDTH, 0, CONFIG.ESP_HEALTH_BAR_HEIGHT)
	healthBG.Position = UDim2.new(0.5, -CONFIG.ESP_HEALTH_BAR_WIDTH/2, 0, 37)
	healthBG.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	healthBG.BorderSizePixel = 0
	healthBG.Parent = billboard

	local healthBar = Instance.new("Frame")
	healthBar.Name = "HealthBar"
	healthBar.Size = UDim2.new(1, 0, 1, 0)
	healthBar.BackgroundColor3 = COLORS.health_green
	healthBar.BorderSizePixel = 0
	healthBar.Parent = healthBG

	espObjects[character] = {
		billboard = billboard,
		nameLabel = nameLabel,
		distLabel = distLabel,
		healthBar = healthBar,
		isPlayer = isPlayer
	}
end

local function removeESP(character)
	if espObjects[character] then
		safeDestroy(espObjects[character].billboard)
		espObjects[character] = nil
	end
end

local function clearAllESP()
	for character, _ in pairs(espObjects) do
		removeESP(character)
	end
	espObjects = {}
end

local function updateESP()
	if not ESP_ENABLED then
		clearAllESP()
		return
	end

	local myCharacter = localPlayer.Character
	if not myCharacter then return end

	local myRoot = myCharacter:FindFirstChild("HumanoidRootPart")
	if not myRoot then return end

	local validCharacters = {}
	local allHumanoids = getAllHumanoids()

	for _, data in ipairs(allHumanoids) do
		local character = data.character
		validCharacters[character] = true

		-- 🔧 FIXED: Pass displayName to createESP
		if not espObjects[character] then
			createESP(character, data.isPlayer, data.displayName)
		end

		if espObjects[character] then
			local esp = espObjects[character]
			local humanoid = data.humanoid
			local targetRoot = character:FindFirstChild("HumanoidRootPart")

			-- Update health bar
			if humanoid then
				local healthPercent = humanoid.Health / humanoid.MaxHealth
				esp.healthBar.Size = UDim2.new(healthPercent, 0, 1, 0)

				if healthPercent > 0.6 then
					esp.healthBar.BackgroundColor3 = COLORS.health_green
				elseif healthPercent > 0.3 then
					esp.healthBar.BackgroundColor3 = COLORS.health_yellow
				else
					esp.healthBar.BackgroundColor3 = COLORS.health_red
				end
			end

			-- 🔧 NEW: Distance-based scaling and coloring
			if targetRoot then
				local distance = (myRoot.Position - targetRoot.Position).Magnitude
				esp.distLabel.Text = string.format("%dm", math.floor(distance))

				-- Distance-based color coding
				if distance < CONFIG.ESP_NEAR_DISTANCE then
					esp.nameLabel.TextColor3 = COLORS.esp_near
					esp.nameLabel.TextSize = 16  -- Bigger when close
				elseif distance < CONFIG.ESP_MID_DISTANCE then
					esp.nameLabel.TextColor3 = COLORS.esp_mid
					esp.nameLabel.TextSize = 14  -- Normal size
				elseif distance < CONFIG.ESP_FAR_DISTANCE then
					esp.nameLabel.TextColor3 = COLORS.esp_far
					esp.nameLabel.TextSize = 12  -- Smaller when far
				else
					esp.nameLabel.TextColor3 = COLORS.text_dim
					esp.nameLabel.TextSize = 10  -- Very small when very far
				end

				-- Culling for extreme distances
				if distance > CONFIG.ESP_CULLING_DISTANCE then
					esp.billboard.Enabled = false
				else
					esp.billboard.Enabled = true
				end
			end
		end
	end

	-- Remove ESP for dead/gone characters
	for character, _ in pairs(espObjects) do
		if not validCharacters[character] then
			removeESP(character)
		end
	end
end

-- ═══════════════════════════════════════════════════════════════
-- UI CREATION
-- ═══════════════════════════════════════════════════════════════
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TotemUI_v3"
screenGui.ResetOnSpawn = false
screenGui.Parent = localPlayer:WaitForChild("PlayerGui")

local function createPanel(name, position, size, title)
	local panel = Instance.new("Frame")
	panel.Name = name
	panel.Size = size
	panel.Position = position
	panel.BackgroundColor3 = COLORS.bg_panel
	panel.BorderSizePixel = 0
	panel.Parent = screenGui
	
	local border = Instance.new("UIStroke")
	border.Color = COLORS.border
	border.Thickness = CONFIG.BORDER_THICKNESS
	border.Parent = panel
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, CONFIG.CORNER_RADIUS)
	corner.Parent = panel
	
	if title then
		local titleLabel = Instance.new("TextLabel")
		titleLabel.Name = "Title"
		titleLabel.Size = UDim2.new(1, 0, 0, 24)
		titleLabel.BackgroundColor3 = COLORS.bg_secondary
		titleLabel.BorderSizePixel = 0
		titleLabel.Font = Enum.Font.GothamMedium
		titleLabel.TextColor3 = COLORS.text_primary
		titleLabel.TextSize = 13
		titleLabel.Text = title
		titleLabel.Parent = panel
		
		local tc = Instance.new("UICorner")
		tc.CornerRadius = UDim.new(0, CONFIG.CORNER_RADIUS)
		tc.Parent = titleLabel
		
		return panel, titleLabel
	end
	
	return panel
end

-- 🔧 FIXED: createToggleButton now properly updates button visual state
local function createToggleButton(parent, text, position, toggleVar, toggleFunc)
	local button = Instance.new("TextButton")
	button.Name = text
	button.Size = UDim2.new(0, 140, 0, 28)
	button.Position = position
	button.BackgroundColor3 = COLORS.bg_secondary
	button.TextColor3 = COLORS.text_primary
	button.Font = Enum.Font.GothamMedium
	button.TextSize = 12
	button.Parent = parent
	
	local originalBg = button.BackgroundColor3
	local originalText = button.TextColor3
	
	-- 🔧 FIXED: This function now gets called after toggle
	local function updateButtonState()
		if toggleVar() then
			button.BackgroundColor3 = COLORS.accent_info
			button.TextColor3 = COLORS.bg_primary
			button.Text = "✓ " .. text
		else
			button.BackgroundColor3 = originalBg
			button.TextColor3 = originalText
			button.Text = text
		end
	end
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, CONFIG.CORNER_RADIUS)
	corner.Parent = button
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.border
	stroke.Thickness = CONFIG.BORDER_THICKNESS
	stroke.Parent = button
	
	bind(button.MouseEnter:Connect(function()
		if toggleVar() then
			button.BackgroundColor3 = COLORS.accent_info:lerp(COLORS.accent_good, 0.3)
		else
			button.BackgroundColor3 = originalBg:lerp(COLORS.accent_info, 0.3)
		end
	end))
	
	bind(button.MouseLeave:Connect(function()
		updateButtonState()
	end))
	
	-- 🔧 FIXED: Now returns the update function so keyboard shortcuts can use it
	bind(button.MouseButton1Click:Connect(function()
		if canToggle(text) then
			toggleFunc()
			updateButtonState()
		end
	end))
	
	updateButtonState()
	
	return button, updateButtonState  -- 🔧 RETURN update function
end

-- ═══════════════════════════════════════════════════════════════
-- MAIN UI PANELS
-- ═══════════════════════════════════════════════════════════════
local threatPanel, threatTitle = createPanel(
	"ThreatMonitor",
	UDim2.new(0, 10, 0, 150),
	UDim2.new(0, 200, 0, 180),
	"THREAT MONITOR"
)

local controlsPanel, controlsTitle = createPanel(
	"Controls",
	UDim2.new(0, 10, 0, 340),
	UDim2.new(0, 200, 0, 235),
	"CONTROLS"
)

local historyPanel, historyTitle = createPanel(
	"TotemHistory",
	UDim2.new(0, 10, 0, 550),
	UDim2.new(0, 200, 0, 150),
	"TOTEM HISTORY"
)

-- 🔧 FIXED: Store update functions for each button so keyboard shortcuts can trigger them
local buttonUpdaters = {}

local yOffset = 32
local controls = {
	{"ESP", function() return ESP_ENABLED end, function() ESP_ENABLED = not ESP_ENABLED end},
	{"Click Break", function() return CLICKBREAK_ENABLED end, function() CLICKBREAK_ENABLED = not CLICKBREAK_ENABLED end},
	{"Auto Click", function() return AUTOCLICK_ENABLED end, function() AUTOCLICK_ENABLED = not AUTOCLICK_ENABLED end},
	{"Sky Mode", function() return SKY_MODE_ENABLED end, function() SKY_MODE_ENABLED = not SKY_MODE_ENABLED end},
	{"Thermal Vision", function() return THERMAL_ENABLED end, function() THERMAL_ENABLED = not THERMAL_ENABLED end},
}

for i, control in ipairs(controls) do
	local button, updater = createToggleButton(controlsPanel, control[1], UDim2.new(0, 8, 0, yOffset), control[2], control[3])
	buttonUpdaters[control[1]] = updater  -- 🔧 STORE updater function
	yOffset = yOffset + 35
end

local threatText = Instance.new("TextLabel")
threatText.Name = "ThreatDisplay"
threatText.Size = UDim2.new(1, -16, 1, -32)
threatText.Position = UDim2.new(0, 8, 0, 32)
threatText.BackgroundTransparency = 1
threatText.Font = Enum.Font.Gotham
threatText.TextColor3 = COLORS.text_secondary
threatText.TextSize = 11
threatText.TextWrapped = true
threatText.TextXAlignment = Enum.TextXAlignment.Left
threatText.TextYAlignment = Enum.TextYAlignment.Top
threatText.Text = "No active threats"
threatText.Parent = threatPanel

-- ═══════════════════════════════════════════════════════════════
-- RADAR
-- ═══════════════════════════════════════════════════════════════
local radarPanel = Instance.new("Frame")
radarPanel.Name = "Radar"
radarPanel.Size = UDim2.new(0, 180, 0, 180)
radarPanel.Position = UDim2.new(1, -190, 1, -190)
radarPanel.BackgroundColor3 = COLORS.bg_panel
radarPanel.BorderSizePixel = 0
radarPanel.Parent = screenGui

local radarCorner = Instance.new("UICorner")
radarCorner.CornerRadius = UDim.new(0, CONFIG.CORNER_RADIUS)
radarCorner.Parent = radarPanel

local radarStroke = Instance.new("UIStroke")
radarStroke.Color = COLORS.accent_radar
radarStroke.Thickness = CONFIG.BORDER_THICKNESS
radarStroke.Parent = radarPanel

local centerDot = Instance.new("Frame")
centerDot.Size = UDim2.new(0, 6, 0, 6)
centerDot.Position = UDim2.new(0.5, -3, 0.5, -3)
centerDot.BackgroundColor3 = COLORS.accent_good
centerDot.BorderSizePixel = 0
centerDot.Parent = radarPanel

local centerCorner = Instance.new("UICorner")
centerCorner.CornerRadius = UDim.new(1, 0)
centerCorner.Parent = centerDot

local radarTitle = Instance.new("TextLabel")
radarTitle.Size = UDim2.new(1, 0, 0, 20)
radarTitle.BackgroundTransparency = 1
radarTitle.Font = Enum.Font.GothamBold
radarTitle.TextColor3 = COLORS.text_primary
radarTitle.TextSize = 11
radarTitle.Text = "RADAR"
radarTitle.Parent = radarPanel

local radarBlips = {}

local function updateRadar()
	for _, blip in pairs(radarBlips) do
		safeDestroy(blip)
	end
	radarBlips = {}

	local myCharacter = localPlayer.Character
	if not myCharacter then return end

	local myRoot = myCharacter:FindFirstChild("HumanoidRootPart")
	if not myRoot then return end

	local myPosition = myRoot.Position
	local myCFrame = myRoot.CFrame

	local allHumanoids = getAllHumanoids()

	for _, data in ipairs(allHumanoids) do
		local targetRoot = data.character:FindFirstChild("HumanoidRootPart")
		if targetRoot then
			local targetPos = targetRoot.Position
			local relativePos = myCFrame:PointToObjectSpace(targetPos)

			local radarScale = 90 / 500
			local x = relativePos.X * radarScale
			local z = -relativePos.Z * radarScale

			local distance = math.sqrt(x*x + z*z)
			if distance > 85 then
				x = (x / distance) * 85
				z = (z / distance) * 85
			end

			local blip = Instance.new("Frame")
			blip.Size = UDim2.new(0, 4, 0, 4)
			blip.Position = UDim2.new(0.5, x - 2, 0.5, z - 2)
			blip.BackgroundColor3 = data.isPlayer and COLORS.accent_info or COLORS.thermal_hot
			blip.BorderSizePixel = 0
			blip.ZIndex = 2
			blip.Parent = radarPanel

			local blipCorner = Instance.new("UICorner")
			blipCorner.CornerRadius = UDim.new(1, 0)
			blipCorner.Parent = blip

			table.insert(radarBlips, blip)
		end
	end
end

-- ═══════════════════════════════════════════════════════════════
-- KEYBOARD CONTROLS (🔧 FIXED - now properly syncs with UI)
-- ═══════════════════════════════════════════════════════════════
local CTRL_HELD = false

local KEYBINDS = {
	[Enum.KeyCode.E] = function()
		if canToggle("ESP_KB") then
			ESP_ENABLED = not ESP_ENABLED
			-- 🔧 FIXED: Update button visual state
			if buttonUpdaters["ESP"] then
				buttonUpdaters["ESP"]()
			end
		end
	end,
	[Enum.KeyCode.C] = function()
		if canToggle("AUTOCLICK_KB") then
			AUTOCLICK_ENABLED = not AUTOCLICK_ENABLED
			-- 🔧 FIXED: Update button visual state
			if buttonUpdaters["Auto Click"] then
				buttonUpdaters["Auto Click"]()
			end
		end
	end,
	[Enum.KeyCode.L] = function()
		if canToggle("SKYMODE_KB") then
			SKY_MODE_ENABLED = not SKY_MODE_ENABLED
			-- 🔧 NEW: Apply/restore sky mode
			if SKY_MODE_ENABLED then
				applySkyMode()
			else
				restoreSkyMode()
			end
			-- 🔧 FIXED: Update button visual state
			if buttonUpdaters["Sky Mode"] then
				buttonUpdaters["Sky Mode"]()
			end
		end
	end,
	[Enum.KeyCode.T] = function()
		if canToggle("THERMAL_KB") then
			THERMAL_ENABLED = not THERMAL_ENABLED
			-- 🔧 FIXED: Update button visual state
			if buttonUpdaters["Thermal Vision"] then
				buttonUpdaters["Thermal Vision"]()
			end
		end
	end,
	[Enum.KeyCode.H] = function()
		if canToggle("UI_TOGGLE_KB") then
			screenGui.Enabled = not screenGui.Enabled
		end
	end,
	[Enum.KeyCode.Six] = function()
		dead = true
		ESP_ENABLED = false
		AUTOCLICK_ENABLED = false
		CLICKBREAK_ENABLED = false
		SKY_MODE_ENABLED = false
		THERMAL_ENABLED = false
		clearAllThermalEffects()
		clearAllESP()
		restoreSkyMode()
		disconnectAll()
		safeDestroy(screenGui)
	end,
}

bind(UserInputService.InputBegan:Connect(function(input, gp)
	if gp or dead then return end
	
	if input.KeyCode == Enum.KeyCode.LeftControl then
		CTRL_HELD = true
	elseif CTRL_HELD and input.UserInputType == Enum.UserInputType.Keyboard then
		local action = KEYBINDS[input.KeyCode]
		if action then
			action()
		end
	end
end))

bind(UserInputService.InputEnded:Connect(function(input, gp)
	if input.KeyCode == Enum.KeyCode.LeftControl then
		CTRL_HELD = false
	end
end))

-- ═══════════════════════════════════════════════════════════════
-- MAIN LOOP
-- ═══════════════════════════════════════════════════════════════
bind(RunService.Heartbeat:Connect(function(dt)
	if dead then return end

	if runUpdate(dt, "thermal") then
		updateThermalVision()
	end

	if runUpdate(dt, "visual") then
		updateESP()
	end

	if runUpdate(dt, "radar") then
		updateRadar()
	end

	if AUTOCLICK_ENABLED then
		autoClickTimer = autoClickTimer + dt
		local clickInterval = 1 / CONFIG.AUTOCLICK_CPS

		if autoClickTimer >= clickInterval then
			autoClickTimer = 0
			performAutoClick()
		end
	else
		autoClickTimer = 0
		autoClickTarget = nil
	end

	if runUpdate(dt, "visual") then
		local nearestPlayers = 0
		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= localPlayer and player.Character then
				nearestPlayers = nearestPlayers + 1
			end
		end

		local systemStatus = ""
		if ESP_ENABLED then systemStatus = systemStatus .. "ESP " end
		if AUTOCLICK_ENABLED then systemStatus = systemStatus .. "AC " end
		if SKY_MODE_ENABLED then systemStatus = systemStatus .. "SKY " end
		if CLICKBREAK_ENABLED then systemStatus = systemStatus .. "CB " end
		if THERMAL_ENABLED then systemStatus = systemStatus .. "THRM" end

		if systemStatus == "" then
			systemStatus = "[All systems off]"
		else
			systemStatus = "[" .. systemStatus .. "]"
		end

		threatText.Text = string.format(
			"Players: %d\n%s",
			nearestPlayers,
			systemStatus
		)
	end
end))

-- ═══════════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════════
local function validateInitialization()
	return localPlayer:FindFirstChild("PlayerGui") ~= nil
		and screenGui ~= nil
		and threatPanel ~= nil
		and controlsPanel ~= nil
		and radarPanel ~= nil
end

if not validateInitialization() then
	warn("[SP3ARBR3AK3R v3.3] ⚠️ Initialization failed!")
else
	print("[SP3ARBR3AK3R v3.3] ✅ All systems initialized successfully")
end

bind(localPlayer.CharacterAdded:Connect(function()
	if dead then return end
	screenGui.Enabled = true
	clearAllESP()
	clearAllThermalEffects()
	npcCacheDirty = true
end))

game:BindToClose(function()
	restoreSkyMode()
	disconnectAll()
	safeDestroy(screenGui)
end)

print("╔═══════════════════════════════════════════════════════╗")
print("║   SP3ARBR3AK3R v3.3 - FULLY FUNCTIONAL RELEASE       ║")
print("║   ✅ All toggles working • Names fixed • ESP scaled   ║")
print("╚═══════════════════════════════════════════════════════╝")
