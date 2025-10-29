---- GunHandler module inside ServerStorage ----
--[[
This is a server authorative gun module which is part of a bigger framework
It uses LuaU typing for simplified debugging and readability
Part creation is handled on the server for demonstration
Downloadable place: https://www.roblox.com/games/109944344893111/Gun-System-Testing
]]

local RunService = game:GetService("RunService")

type GunConfig = {
	MAG_SIZE: number,
	FIRE_RATE: number, -- fire rate = shots per second
	DAMAGE: number, -- the base damage of the gun
	RANGE: number, -- the maximum distance of the raycast
	SPREAD: number, -- the maximum angle of the bullet spread
	RELOAD_TIME: number, -- time taken for gun to reload
	MAX_HEAT: number, -- the maximum heat the gun can reach before not being able to fire
	COOLING_RATE: number, -- the temperature of the gun lost per second
	AUTOMATIC: boolean, -- a flag used on the client side to determine if the firing is manual or automatic
	DAMAGE_MULTIPLIERS: {[string]: number}? -- damage mutlipliers is optional, the default is handled inside the new method so that the same table is not referenced
}

export type GunInstance = { -- store function signatures and class attributes for easier debugging
	Fire: (self: GunInstance, Origin: Vector3, Direction: Vector3, ExcludeInstances: {Instance}?) -> (),
	Reload: (self: GunInstance) -> (),
	_canFire: (self: GunInstance) -> (),
	_createBeam: (self: GunInstance, cFrame: CFrame, Size: Vector3) -> (),
	_getSpreadAngle: (self: GunInstance) -> CFrame,
	_getDamageMultiplier: (self: GunInstance) -> (),
	_getDamage: (self: GunInstance) -> (),
	delete: (self: GunInstance) -> (),

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

local DEFAULT_GUN_CONFIG: GunConfig = { -- store defaults in a table to use if any keys are missing from the provided configuration table
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

local TARGET_CLASSES = { -- a table to classify each instance for convenience and compatibility with both avatar types
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

local GunInstances: {GunInstance} = {}

local GunHandler = {}
GunHandler.__index = GunHandler

local RNG = Random.new() -- define a new instance of random to use for generating a random spread, used over math.random for more flexibility and no interfering with other scripts

local function GenerateRandomAngle(AngleRange: number) -- generate a random angle within the specified range and return it in radians
	return math.rad(RNG:NextNumber() * (AngleRange * 2) - AngleRange)
end

function GunHandler.new(Config) : GunInstance -- function to create a new gun instance and initialise all the attributes
	local self = setmetatable({}, GunHandler)

	Config = setmetatable(Config, {__index = DEFAULT_GUN_CONFIG}) -- use defaults if any keys are missing from the config table
	Config.DAMAGE_MULTIPLIERS = Config.DAMAGE_MULTIPLIERS or {} -- create a new table seperately so that the same one is not referenced each time

	self.Config = Config -- store frequently used values to reduce memory access time
	self.MagSize = Config.MAG_SIZE -- the maximum ammo capacity for the gun
	self.Damage = Config.DAMAGE -- the base damage dealt by the gun
	self.Ammo = Config.MAG_SIZE -- current ammo in the gun, defaults to the maximum capacity
	self.Heat = 0 -- the current heat of the gun, determines whether the gun is too hot to fire
	self.Reloading = false -- flag to keep track of whether the gun is currently realoading
	self.ReloadTime = Config.RELOAD_TIME -- the time it takes to reload the gun
	self.CanFire = true -- a flag used to manually disable firing, can be used during cutscenes or during the firing function to ensure it waits until the function has ended
	self.Safety = false -- a flag to check if the gun safety is enabled
	self.Cooling = false -- a flag to check if the gun is currently cooling
	self.LastFire = 0 -- a float used to store the last time the gun was fired to check if the gun can fire based on the fire rate

	table.insert(GunInstances, self) -- store the new gun object insde gun instances to apply the gun cooling loop

	return self :: GunInstance -- cast self to GunInstance to apply all the type annotations
end

function GunHandler:_canFire(): (boolean, string) -- function which checks multiple conditions to see if the gun can fire
	if not self.CanFire then return false, "Firing has been disabled" end -- returns a boolean and a string tuple for debugging
	if self.Heat > self.Config.MAX_HEAT or self.Cooling then return false, "Gun is too hot" end
	if self.Safety then return false, "Safety is enabled" end
	if self.Ammo < 1 then return false, "Gun has no ammo left" end
	if os.clock() - self.LastFire < (1 / self.Config.FIRE_RATE) then return false, "Gun is firing too frequently" end -- server side checks to ensure that the gun is firing at the correct rate
	if self.Reloading then return false, "Gun is currently reloading" end

	return true, "" -- if all conditions are passed, return true with an empty message to avoid any errors
end

function GunHandler:_getDamageMultiplier(target: Part) -- function to get the damage multiplier based on the target, used by the _getDamage function
	local DamageMultipliers = self.Config.DAMAGE_MULTIPLIERS

	local multiplier -- initialise the multiplier to use as a temporary variable and return it if it contains a valid value

	for class, names in pairs(TARGET_CLASSES) do
		if names[target.Name] then -- check if the target name is part of the current class
			multiplier = DamageMultipliers[class] -- attempt to set the multiplier
			if multiplier then
				return multiplier -- if the multiplier exists, return it
			end
		end
	end

	multiplier = DamageMultipliers[target.Name] -- check if the target name is specified directly in the damage multipliers
	if multiplier then
		return multiplier
	end

	return 1 -- return 1 if no multiplier was found
end

function GunHandler:_getDamage(target: Part)
	return self.Damage * self:_getDamageMultiplier(target) -- calculate the damage with the damage multiplier applied
end

function GunHandler:_createBeam(cFrame: CFrame, Size: Vector3) : () -- create the visual beam
	local beam = Instance.new("Part", workspace) -- create a new part inside the workspace
	beam.Anchored = true
	beam.CanCollide = false
	beam.CFrame = cFrame
	beam.Size = Size
	beam.Color = Color3.fromRGB(255, 255, 0)
	beam.Material = Enum.Material.Neon

	game:GetService("Debris"):AddItem(beam, .1) -- delete the beam after 0.1 seconds
end

function GunHandler:_getSpreadAngle(): CFrame -- generate a random spread angle
	local Spread = self.Config.SPREAD

	local AngleX = GenerateRandomAngle(Spread) -- generate 2 random angles within -Spread and +Spread in radians
	local AngleY = GenerateRandomAngle(Spread)

	return CFrame.Angles(AngleX, AngleY, 0) -- return an angles cframe to use as a multiplier
end

function GunHandler:_addHeat() : () -- function to add heat to the gun and prevent firing when the heat goes above its maximum	
	self.Heat += 1

	if self.Heat > self.Config.MAX_HEAT and not self.Cooling then
		self.Cooling = true
		print("Waiting for gun to cool down..") -- print a message for debugging
		task.spawn(function()
			while self.Heat > self.Config.MAX_HEAT do
				task.wait(4) -- wait 4 seconds every iteration and continue the loop if the heat is still above max heat
			end
			self.Cooling = false -- allow gun firing again after cooled down
		end)
	end
end

function GunHandler:Fire(Origin: Vector3, Direction: Vector3, ExcludeInstances: {Instance}?) : ()
	local canFire, info = self:_canFire() -- unpack the returned values from the _canFire function
	if not canFire then
		warn(info) -- warn the debugging message if canFire is false
		return
	end

	self.CanFire = false -- flag to make sure other bullets cant fire until the current function has ended

	ExcludeInstances = ExcludeInstances or {} -- create a new table if ExcludeInstances is missing
	local raycastParams = RaycastParams.new() -- create a raycast params object to specify the instances which should be excluded from the raycast
	raycastParams.FilterDescendantsInstances = ExcludeInstances
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local directionUnit = (Direction - Origin).Unit -- convert the direction to a unit vector so that the raycast direction always has the same magnitude when mutliplied by the gun range
	local actualDirection = directionUnit * self.Config.RANGE -- calculate direction with the gun range

	local RaycastResult = workspace:Raycast(Origin, actualDirection, raycastParams) -- only fire if the direction is within the gun range

	if not RaycastResult then self.CanFire = true return end -- if the raycast fails, end the function

	local BeamLength = RaycastResult.Distance -- use the distance of the raycast as the beam size on the Z axis

	if BeamLength then
		self.LastFire = os.clock() -- use os.clock() instead of tick() for more precision
		self.Ammo -= 1 -- decrement ammo if shot was successful
		self:_addHeat() -- add heat if shot was successful

		local SpreadAngle = self:_getSpreadAngle()
		local cFrame = CFrame.new(Origin, Direction) * SpreadAngle * CFrame.new(0, 0, -BeamLength / 2) -- calculate the beam cframe by making it point in the direction of the shot and offsetting the angle by the random spread angle and multiply by half of the beam length so that it touches the hit part

		self:_createBeam(cFrame, Vector3.new(.1, .1, BeamLength)) -- create a beam with the cframe and size

		local Target = RaycastResult.Instance
		if Target then -- check if the raycast hit a part
			local Humanoid: Humanoid = Target.Parent:FindFirstChild("Humanoid")

			if Humanoid and Humanoid.Health > 0 then -- check if the parent of the part has a humanoid and is alive
				local Damage = self:_getDamage(Target) -- calculate the damage with the damage multiplier applied
				Humanoid:TakeDamage(Damage) -- apply damage to the humanoid
			end
		end
	end

	self.CanFire = true -- enable canfire at the end of the function
end

function GunHandler:Reload() : ()
	if self.Reloading then return end -- if gun is already realoding then end the function
	if self.Ammo >= self.MagSize then return end -- if ammo is full then end the function

	self.Reloading = true -- enable realoding so that the gun cant reload again while the function is running
	task.wait(self.ReloadTime)
	self.Ammo = self.MagSize
	self.Reloading = false
end

function GunHandler:delete() -- a function to remove the gun instance from the instances table so that the heat loop will no longer affect it
	local i = table.find(GunInstances, self) -- get the index of the gun instance inside the instances table
	if i then -- check if the index exists
		table.remove(GunInstances, i)
	end
end

RunService.Heartbeat:Connect(function(dt)
	for _, Gun: GunInstance in GunInstances do -- loop through every gun instance and add heat based on the delta time
		Gun.Heat = math.max(Gun.Heat - Gun.Config.COOLING_RATE * dt, 0) -- subtract cooling rate multiplied by the delta time which is the amount it should have cooled in that time and make sure it stays above 0
	end
end)

return GunHandler
