---- GunHandler module inside ServerStorage ----
--[[
This is a server authorative gun module which is part of a bigger framework
It uses LuaU typing for simplified debugging and readability
Part creation is handled on the server for demonstration
Downloadable place: https://www.roblox.com/games/109944344893111/Gun-System-Testing
]]

type GunConfig = {
	MAG_SIZE: number,
	FIRE_RATE: number, -- fire rate = shots per second, 1 / fire rate = interval between shots
	DAMAGE: number,
	RANGE: number,
	SPREAD: number,
	RELOAD_TIME: number,
	MAX_HEAT: number,
	COOLING_RATE: number,
	AUTOMATIC: boolean,
	DAMAGE_MULTIPLIERS: {[string]: number}?
}

export type GunInstance = { -- store function signatures and class attributes for easier debugging
	Fire: (self: GunInstance, Origin: Vector3, Direction: Vector3, ExcludeInstances: {Instance}?) -> (),
	Reload: (self: GunInstance) -> (),
	_canFire: (self: GunInstance) -> (),
	_createBeam: (self: GunInstance, cFrame: CFrame, Size: Vector3) -> (),
	_getSpreadAngle: (self: GunInstance) -> CFrame,
	_getDamageMutliplier: (self: GunInstance) -> (),
	_getDamage: (self: GunInstance) -> (),

	Ammo: number,
	MagSize: number,
	Damage: number,
	Config: GunConfig,
	Reloading: boolean,
	ReloadTime: number,
	Heat: number,
	CanFire: boolean,
	Safety: boolean,
	Cooling: boolean,
	LastFire: number
}

local DEFAULT_GUN_CONFIG: GunConfig = {
	MAG_SIZE = 300,
	FIRE_RATE = 8,
	DAMAGE = 10,
	RANGE = 200,
	SPREAD = 5,
	RELOAD_TIME = 1.2,
	MAX_HEAT = 10,
	COOLING_RATE = 1,
	AUTOMATIC = true,
}

local TARGET_CLASSES = {
	["Limb"] = {
		["Left arm"] = true, -- for r6
		["Right arm"] = true,
		["Left leg"] = true,
		["Right leg"] = true,

		["LeftUpperArm"] = true, -- for r15
		["LeftLowerArm"] = true,
		["RightUpperArm"] = true,
		["RightLowerArm"] = true,
		["LeftUpperLeg"] = true,
		["LeftLowerLeg"] = true,
		["RightUpperLeg"] = true,
		["RightLowerLeg"] = true
	},
	
	["Arm"] = {
		["Left arm"] = true,
		["Right arm"] = true,
		
		["LeftUpperArm"] = true,
		["LeftLowerArm"] = true,
		["RightUpperArm"] = true,
		["RightLowerArm"] = true
	},
	
	["Leg"] = {
		["Left leg"] = true,
		["Right leg"] = true,
		
		["LeftUpperLeg"] = true,
		["LeftLowerLeg"] = true,
		["RightUpperLeg"] = true,
		["RightLowerLeg"] = true
	},
	
	["Torso"] = {
		["Torso"] = true,
		["UpperTorso"] = true,
		["LowerTorso"] = true
	}
}

local GunHandler = {}
GunHandler.__index = GunHandler

function GunHandler.new(Config) : GunInstance
	local self = setmetatable({}, GunHandler)

	Config = setmetatable(Config, {__index = DEFAULT_GUN_CONFIG}) -- use defaults if any keys are missing from the config table
	Config.DAMAGE_MULTIPLIERS = Config.DAMAGE_MULTIPLIERS or {} -- create a new table seperately so that the same one is not referenced each time

	self.Config = Config -- store config in attributes for readability and easier reusability
	self.MagSize = Config.MAG_SIZE
	self.Damage = Config.DAMAGE
	self.Ammo = Config.MAG_SIZE
	self.Heat = 0
	self.Reloading = false
	self.ReloadTime = Config.RELOAD_TIME
	self.CanFire = true
	self.Safety = false
	self.Cooling = false
	self.LastFire = 0

	task.spawn(function()
		while task.wait(1 / Config.COOLING_RATE) do
			self.Heat = math.max(self.Heat - 1, 0)
		end
	end)

	return self :: GunInstance -- cast self to GunInstance
end

function GunHandler:_canFire(): boolean
	if not self.CanFire then return false, "Firing has been disabled" end
	if self.Heat > self.Config.MAX_HEAT or self.Cooling then return false, "Gun is too hot" end
	if self.Safety then return false, "Safety is enabled" end
	if self.Ammo < 1 then return false, "Gun has no ammo left" end
	if os.clock() - self.LastFire < (1 / self.Config.FIRE_RATE) then return false, "Gun is firing too frequently" end
	if self.Reloading then return false, "Gun is currently reloading" end

	return true
end

function GunHandler:_getDamageMutliplier(target: Part)
	local DamageMutlipliers = self.Config.DAMAGE_MULTIPLIERS
	
	local multiplier
	
	for class, names in pairs(TARGET_CLASSES) do
		if names[target.Name] then
			multiplier = DamageMutlipliers[class]
			if multiplier then
				return multiplier
			end
		end
	end
	
	multiplier = DamageMutlipliers[target.Name]
	if multiplier then
		return multiplier
	end
end

function GunHandler:_getDamage(target: Part)
	return self.Damage * (self:_getDamageMutliplier(target) or 1) -- get damage multiplier based on the target, if there is none then the damage will stay the same
end

function GunHandler:_createBeam(cFrame: CFrame, Size: Vector3) : ()
	local beam = Instance.new("Part", workspace)
	beam.Anchored = true
	beam.CanCollide = false
	beam.CFrame = cFrame
	beam.Size = Size
	beam.BrickColor = BrickColor.new("New Yeller")
	beam.Material = Enum.Material.Neon

	game:GetService("Debris"):AddItem(beam, .1)
end

function GunHandler:_getSpreadAngle(): CFrame
	local Spread = self.Config.SPREAD

	local AngleX = math.rad(math.random() * (Spread * 2) - Spread) -- generate 2 random angles and convert to radians
	local AngleY = math.rad(math.random() * (Spread * 2) - Spread)

	return CFrame.Angles(AngleX, AngleY, 0) -- return an angles cframe to use as a multiplier
end

function GunHandler:_addHeat() : ()
	self.Heat += 1
	
	if self.Heat > self.Config.MAX_HEAT and not self.Cooling then
		self.Cooling = true
		print("Waiting for gun to cool down..")
		task.spawn(function()
			while self.Heat > self.Config.MAX_HEAT do
				task.wait(4)
			end
			self.Cooling = false
		end)
	end
end

function GunHandler:Fire(Origin: Vector3, Direction: Vector3, ExcludeInstances: {Instance}?) : ()
	local canFire, info = self:_canFire()
	if not canFire then
		warn(info)
		return
	end
	
	self.CanFire = false -- flag to make sure other bullets cant fire until the current function has ended

	ExcludeInstances = ExcludeInstances or {}
	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = ExcludeInstances
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local directionUnit = (Direction - Origin).Unit
	local actualDirection = directionUnit * self.Config.RANGE -- calculate direction with the gun range

	local RaycastResult = workspace:Raycast(Origin, actualDirection, raycastParams) -- only fire if the direction is within the gun range

	if not RaycastResult then self.CanFire = true return end

	local BeamLength = RaycastResult.Distance

	if BeamLength then
		self.LastFire = os.clock() -- use os.clock() instead of tick() for more precision
		self.Ammo -= 1 -- decrement ammo if shot was successful
		self:_addHeat()

		local SpreadAngle = self:_getSpreadAngle()
		local cFrame = CFrame.new(Origin, Direction) * SpreadAngle * CFrame.new(0, 0, -BeamLength / 2)

		self:_createBeam(cFrame, Vector3.new(.1, .1, BeamLength))

		local Target = RaycastResult.Instance
		if Target then
			local Humanoid: Humanoid = Target.Parent:FindFirstChild("Humanoid")

			if Humanoid and Humanoid.Health > 0 then
				local Damage = self:_getDamage(Target)
				Humanoid:TakeDamage(Damage)
			end
		end
	end

	self.CanFire = true
end

function GunHandler:Reload() : ()
	if self.Reloading then return end
	if self.Ammo >= self.MagSize then return end

	self.Reloading = true
	task.wait(self.ReloadTime)
	self.Ammo = self.MagSize
	self.Reloading = false
end

return GunHandler
