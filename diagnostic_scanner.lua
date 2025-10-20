--[[
SB3 DIAGNOSTIC SCANNER
Run this script in your game to map out available properties and services.
The output will help identify what we can exploit for real tactical advantages.

HOW TO USE:
1. Copy this entire script
2. Paste and run it in your game's console or executor
3. Wait 10-15 seconds for it to scan
4. Copy ALL the output from the console
5. Share it so we can analyze what's available

The script scans for:
- Player character structure
- Tool/weapon properties
- Velocity and physics data
- Camera access
- Team information
- Health/damage systems
- Replication properties
- Input systems
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer
local output = {}

local function log(category, message)
	local entry = string.format("[%s] %s", category, message)
	table.insert(output, entry)
	print(entry)
end

local function separator(title)
	local line = string.rep("=", 60)
	table.insert(output, line)
	table.insert(output, title)
	table.insert(output, line)
	print(line)
	print(title)
	print(line)
end

-- Scan character structure
local function scanCharacter()
	separator("CHARACTER STRUCTURE SCAN")

	local char = localPlayer.Character
	if not char then
		log("CHARACTER", "No character found (waiting for spawn)")
		return
	end

	log("CHARACTER", "Character Name: " .. char.Name)

	-- Basic parts
	local parts = {"Head", "Torso", "HumanoidRootPart", "UpperTorso", "LowerTorso"}
	for _, partName in ipairs(parts) do
		local part = char:FindFirstChild(partName)
		log("CHARACTER", partName .. ": " .. (part and "EXISTS" or "NOT FOUND"))
	end

	-- Humanoid
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		log("HUMANOID", "Health: " .. hum.Health .. " / " .. hum.MaxHealth)
		log("HUMANOID", "WalkSpeed: " .. hum.WalkSpeed)
		log("HUMANOID", "JumpPower: " .. (hum.JumpPower or hum.JumpHeight or "N/A"))
		log("HUMANOID", "DisplayName: " .. (hum.DisplayName or "N/A"))

		-- Check for velocity-related properties
		local root = char:FindFirstChild("HumanoidRootPart")
		if root then
			log("PHYSICS", "AssemblyLinearVelocity: " .. tostring(root.AssemblyLinearVelocity))
			log("PHYSICS", "AssemblyAngularVelocity: " .. tostring(root.AssemblyAngularVelocity))
			log("PHYSICS", "CFrame: " .. tostring(root.CFrame.Position))
		end
	else
		log("HUMANOID", "NOT FOUND")
	end

	-- List all children
	log("CHARACTER", "All children (" .. #char:GetChildren() .. " total):")
	for _, child in ipairs(char:GetChildren()) do
		log("CHARACTER", "  - " .. child.Name .. " (" .. child.ClassName .. ")")
	end
end

-- Scan tools and weapons
local function scanTools()
	separator("TOOLS & WEAPONS SCAN")

	local char = localPlayer.Character
	if not char then return end

	-- Check for equipped tools
	local tool = char:FindFirstChildOfClass("Tool")
	if tool then
		log("TOOL", "Equipped: " .. tool.Name)
		log("TOOL", "ClassName: " .. tool.ClassName)

		-- Common weapon properties
		local props = {"Damage", "FireRate", "Ammo", "MaxAmmo", "ReloadTime", "Range", "Spread", "Velocity", "BulletSpeed"}
		for _, prop in ipairs(props) do
			local val = tool:GetAttribute(prop)
			if val ~= nil then
				log("TOOL_ATTR", prop .. ": " .. tostring(val))
			end
		end

		-- Check for Handle
		local handle = tool:FindFirstChild("Handle")
		if handle then
			log("TOOL", "Has Handle: YES")
		end

		-- List all children
		log("TOOL", "Children:")
		for _, child in ipairs(tool:GetChildren()) do
			log("TOOL", "  - " .. child.Name .. " (" .. child.ClassName .. ")")
			if child:IsA("Script") or child:IsA("LocalScript") then
				log("TOOL_SCRIPT", "    Script found: " .. child.Name)
			end
		end

		-- Check for RemoteEvents (weapon firing)
		for _, obj in ipairs(tool:GetDescendants()) do
			if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
				log("TOOL_REMOTE", "  Found: " .. obj.Name .. " (" .. obj.ClassName .. ")")
			end
		end
	else
		log("TOOL", "No tool equipped")
	end

	-- Check backpack
	local backpack = localPlayer:FindFirstChild("Backpack")
	if backpack then
		log("BACKPACK", "Tools in backpack: " .. #backpack:GetChildren())
		for _, item in ipairs(backpack:GetChildren()) do
			if item:IsA("Tool") then
				log("BACKPACK", "  - " .. item.Name)
			end
		end
	end
end

-- Scan other players
local function scanOtherPlayers()
	separator("OTHER PLAYERS SCAN")

	local otherPlayers = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= localPlayer then
			table.insert(otherPlayers, player)
		end
	end

	log("PLAYERS", "Other players online: " .. #otherPlayers)

	if #otherPlayers > 0 then
		local targetPlayer = otherPlayers[1]
		log("PLAYERS", "Scanning first player: " .. targetPlayer.Name)

		-- Team info
		if targetPlayer.Team then
			log("PLAYERS", "  Team: " .. targetPlayer.Team.Name)
			log("PLAYERS", "  TeamColor: " .. tostring(targetPlayer.TeamColor))
		else
			log("PLAYERS", "  Team: NONE")
		end

		-- Character scan
		local char = targetPlayer.Character
		if char then
			log("PLAYERS", "  Character exists: YES")

			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then
				log("PLAYERS", "  Health: " .. hum.Health .. " / " .. hum.MaxHealth)
				log("PLAYERS", "  Can read health: YES ✓")
			end

			local root = char:FindFirstChild("HumanoidRootPart")
			if root then
				-- Try to access velocity
				local success, velocity = pcall(function()
					return root.AssemblyLinearVelocity
				end)
				if success then
					log("PLAYERS", "  Can read velocity: YES ✓")
					log("PLAYERS", "  Current velocity: " .. tostring(velocity))
				else
					log("PLAYERS", "  Can read velocity: NO ✗")
				end
			end

			-- Check for tool
			local tool = char:FindFirstChildOfClass("Tool")
			if tool then
				log("PLAYERS", "  Equipped tool: " .. tool.Name)
				log("PLAYERS", "  Can see equipped tool: YES ✓")
			else
				log("PLAYERS", "  Equipped tool: NONE")
			end
		else
			log("PLAYERS", "  Character exists: NO")
		end
	end
end

-- Scan camera capabilities
local function scanCamera()
	separator("CAMERA CAPABILITIES SCAN")

	local camera = Workspace.CurrentCamera
	if camera then
		log("CAMERA", "CFrame: " .. tostring(camera.CFrame))
		log("CAMERA", "Focus: " .. tostring(camera.Focus))
		log("CAMERA", "FieldOfView: " .. camera.FieldOfView)
		log("CAMERA", "ViewportSize: " .. tostring(camera.ViewportSize))

		-- Check what we can access
		local props = {"CameraType", "CameraSubject", "HeadLocked", "HeadScale"}
		for _, prop in ipairs(props) do
			local success, val = pcall(function() return camera[prop] end)
			if success then
				log("CAMERA", prop .. ": " .. tostring(val))
			end
		end
	else
		log("CAMERA", "Camera not found")
	end
end

-- Scan workspace for projectiles/bullets
local function scanProjectiles()
	separator("PROJECTILE SYSTEM SCAN")

	-- Look for common projectile folders
	local folders = {"Projectiles", "Bullets", "Shots", "Effects"}
	for _, folderName in ipairs(folders) do
		local folder = Workspace:FindFirstChild(folderName)
		if folder then
			log("PROJECTILES", "Found folder: " .. folderName)
			log("PROJECTILES", "  Children: " .. #folder:GetChildren())
		end
	end

	-- Look for bullet trails or effects
	for _, obj in ipairs(Workspace:GetDescendants()) do
		if obj.Name:lower():match("bullet") or obj.Name:lower():match("projectile") then
			log("PROJECTILES", "Found: " .. obj.Name .. " (" .. obj.ClassName .. ")")
			if obj:IsA("BasePart") then
				local success, velocity = pcall(function() return obj.AssemblyLinearVelocity end)
				if success and velocity.Magnitude > 0 then
					log("PROJECTILES", "  Velocity: " .. tostring(velocity))
					log("PROJECTILES", "  Speed: " .. velocity.Magnitude)
				end
			end
			break -- Just show first example
		end
	end
end

-- Scan input capabilities
local function scanInput()
	separator("INPUT CAPABILITIES SCAN")

	log("INPUT", "MouseEnabled: " .. tostring(UserInputService.MouseEnabled))
	log("INPUT", "KeyboardEnabled: " .. tostring(UserInputService.KeyboardEnabled))
	log("INPUT", "TouchEnabled: " .. tostring(UserInputService.TouchEnabled))
	log("INPUT", "GamepadEnabled: " .. tostring(UserInputService.GamepadEnabled))

	-- Check for VirtualInputManager
	local success, VIM = pcall(function() return game:GetService("VirtualInputManager") end)
	log("INPUT", "VirtualInputManager available: " .. (success and "YES ✓" or "NO ✗"))
end

-- Scan for game-specific systems
local function scanGameSystems()
	separator("GAME-SPECIFIC SYSTEMS SCAN")

	-- Check ReplicatedStorage for game systems
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	log("GAME", "ReplicatedStorage children: " .. #ReplicatedStorage:GetChildren())

	local interesting = {}
	for _, obj in ipairs(ReplicatedStorage:GetChildren()) do
		if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") or obj:IsA("Folder") then
			table.insert(interesting, obj)
		end
	end

	log("GAME", "Interesting objects in ReplicatedStorage:")
	for i, obj in ipairs(interesting) do
		if i <= 10 then -- Limit to first 10
			log("GAME", "  - " .. obj.Name .. " (" .. obj.ClassName .. ")")
		end
	end

	-- Check for game passes or game logic
	local folders = {"Weapons", "Tools", "Skills", "Abilities", "Powers", "GameLogic"}
	for _, name in ipairs(folders) do
		local folder = ReplicatedStorage:FindFirstChild(name)
		if folder then
			log("GAME", "Found system: " .. name)
		end
	end
end

-- Velocity tracking test
local function testVelocityTracking()
	separator("VELOCITY TRACKING TEST")

	log("VELOCITY", "Testing velocity tracking over 2 seconds...")

	local samples = {}
	local startTime = tick()
	local connection

	connection = RunService.Heartbeat:Connect(function()
		if tick() - startTime > 2 then
			connection:Disconnect()

			-- Analyze samples
			if #samples > 0 then
				local avgVel = Vector3.new(0, 0, 0)
				for _, vel in ipairs(samples) do
					avgVel = avgVel + vel
				end
				avgVel = avgVel / #samples

				log("VELOCITY", "Samples collected: " .. #samples)
				log("VELOCITY", "Average velocity: " .. tostring(avgVel))
				log("VELOCITY", "Average speed: " .. avgVel.Magnitude)
				log("VELOCITY", "Velocity tracking: WORKING ✓")
			else
				log("VELOCITY", "No samples collected: FAILED ✗")
			end

			-- Final summary
			separator("DIAGNOSTIC SCAN COMPLETE")
			log("SUMMARY", "Total log entries: " .. #output)
			log("SUMMARY", "Copy all output above and share for analysis")
			log("SUMMARY", "We'll use this to identify real tactical advantages!")

			return
		end

		local char = localPlayer.Character
		if char then
			local root = char:FindFirstChild("HumanoidRootPart")
			if root then
				local success, vel = pcall(function()
					return root.AssemblyLinearVelocity
				end)
				if success and vel then
					table.insert(samples, vel)
				end
			end
		end
	end)
end

-- Main execution
separator("SB3 DIAGNOSTIC SCANNER - STARTING")
log("INFO", "This will take about 10-15 seconds...")
log("INFO", "Move around and switch weapons during the scan if possible")

task.wait(1)
scanCharacter()
task.wait(0.5)
scanCamera()
task.wait(0.5)
scanInput()
task.wait(0.5)
scanTools()
task.wait(0.5)
scanOtherPlayers()
task.wait(0.5)
scanProjectiles()
task.wait(0.5)
scanGameSystems()
task.wait(0.5)
testVelocityTracking()
