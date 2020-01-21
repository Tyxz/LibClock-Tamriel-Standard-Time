-------------------
-- Utility
-------------------

--- Makes a table read-only
--- Source: http://andrejs-cainikovs.blogspot.com/2009/05/lua-constants.html
--- @param table
--- @return constant table
local function Protect(tbl)
	return setmetatable({}, {
		__index = tbl,
		__newindex = function(t, key, value)
			error("attempting to change constant " ..
				tostring(key) .. " to " .. tostring(value), 2)
		end
	})
end

local function IsNotNilOrEmpty(obj) 
    return obj ~= nil and string.match(tostring(obj), "^%s*$") == nil
end

local function IsString(str) 
    return type(str) == "string"
end

local function IsTimestamp(timestamp)
    timestamp = math.floor(tonumber(timestamp))
    return string.match(tostring(timestamp), "^%d%d%d%d%d%d%d%d%d%d$") ~= nil
end

-------------------
-- Constants
-------------------
local TST = {
	updateDelay = 200,
	moonUpdateDelay = 36000000,
}

local ID, MAJOR, MINOR = "LibClockTST", "LibClockTST-1.0", 0
local eventHandle = table.concat({MAJOR, MINOR}, "r")

local em = EVENT_MANAGER

local const = {
	time = {
		lengthOfDay = 20955, -- length of one day in s (default 5.75h right now)
		lengthOfNight = 7200, -- length of only the night in s (2h)
		lengthOfHour = 873.125,
		startTime = 1398033648.5, -- exact unix time at ingame noon as unix timestamp 1398044126 minus offset from midnight 10477.5 (lengthOfDay/2) in s
	},
	date = {
		startTime = 1394617983.724, -- Eso Release  04.04.2014  UNIX: 1396569600 minus calculated offset to midnight 2801.2760416667 minus offset of days to 1.1.582, 1948815 ((31 + 28 + 31 + 3) * const.time.lengthOfDay)
		startWeekDay = 2, -- Start day was Friday (5) but start time of calculation is 93 days before. Therefore, the weekday is (4 - 93)%7
		startYear = 582, -- offset in years, because the game starts in 2E 582
		startEra = 2,
		monthLength = {
			[1] = 31,
			[2] = 28,
			[3] = 31,
			[4] = 30,
			[5] = 31,
			[6] = 30,
			[7] = 31,
			[8] = 31,
			[9] = 30,
			[10] = 31,
			[11] = 30,
			[12] = 31,
		}, -- length of months
		yearLength = 365,
	},
	moon = {
		--Unix time of the start of the full moon phase in s - old 1425169441 and 1407553200
		--New time is for new moon
		startTime = 1436153095, -- 1435838770 from https://esoclock.uesp.net/ + half phase = 1436153095 - phaseOffsetToEnd * phaseLengthInSeconds = 1436112233
		phaseLength = 30, -- ingame days
		phaseLengthInSeconds = 628650, -- in s, phaseLength * dayLength
		singlePhaseLength = 3.75, -- in ingame days
		singlePhaseLengthInSeconds = 78581.25, -- in s, singlePhaseLength * dayLength
		phasesPercentage = { -- https://esoclock.uesp.net/
			[1] = {
				name = "new",
				endPercentage = 0.06,
			},
			[2] = {
				name = "waxingCrescent",
				endPercentage = 0.185,
			},
			[3] = {
				name = "firstQuarter",
				endPercentage = 0.31,
			},
			[4] = {
				name = "waxingGibbonus",
				endPercentage = 0.435,
			},
			[5] = {
				name = "full",
				endPercentage = 0.56,
			},
			[6] = {
				name = "waningGibbonus",
				endPercentage = 0.685,
			},
			[7] = {
				name = "thirdQuarter",
				endPercentage = 0.81,
			},
			[8] = {
				name = "waningCrescent",
				endPercentage = 0.935,
			},
		},
		phasesPercentageOffsetToEnd = 0.065,
		phasesPercentageBetweenPhases = 0.125,
	},
}

TST.CONSTANTS = Protect(const)

LibClockTST = TST

-------------------
-- Calculation
-------------------

local lastCalculatedHour
local needToUpdateDate = true
local time
local date
local moon

--- Get the lore time
-- If a parameter is given, the lore date of the UNIX timestamp will be returned,
-- otherwise it will be the current time.
-- @param timestamp [optional]
-- @return date object {era, year, month, day, weekDay}
local function CalculateTST(timestamp)
	local timeSinceStart = timestamp - const.time.startTime
	local secondsSinceMidnight = timeSinceStart % const.time.lengthOfDay
	local tst = 24 * secondsSinceMidnight / const.time.lengthOfDay

	local h = math.floor(tst)
	tst = (tst - h) * 60
	local m = math.floor(tst)
	tst = (tst - m) * 60
	local s = math.floor(tst)

	if h == 0 and h ~= lastCalculatedHour then
		needToUpdateDate = true
	end

	lastCalculatedHour = h

	return { hour = h, minute = m, second = s }
end

--- Get the lore date
-- If a parameter is given, the lore date of the UNIX timestamp will be returned,
-- otherwise it will be calculated from the current time.
-- @param timestamp [optional]
-- @return date object {era, year, month, day, weekDay}
local function CalculateTSTDate(timestamp)
	local timeSinceStart = timestamp - const.date.startTime
	local daysPast = math.floor(timeSinceStart / const.time.lengthOfDay)
	local w = (daysPast + const.date.startWeekDay) % 7 + 1

	local y = math.floor(daysPast / const.date.yearLength)
	daysPast = daysPast - y * const.date.yearLength
	y = y + const.date.startYear
	local m = 1
	while daysPast >= const.date.monthLength[m] do
		daysPast = daysPast - const.date.monthLength[m]
		m = m + 1
	end
	local d = daysPast + 1

	needToUpdateDate = false

	return {era = const.date.startEra, year = y, month = m, day = d, weekDay = w }
end

--- Get the name of the current moon phase
-- @param phasePercentage percentage already pased in the current phase
-- @return string of current moon phase
local function GetCurrentPhaseName(phasePercentage)
	for _, phase in ipairs(const.moon.phasesPercentage) do
		if phasePercentage < phase.endPercentage then return phase.name end
	end
end

--- Calculate the seconds until the moon is full again
-- returns 0 if the moon is already full
-- @param phasePercentage percentage already pased in the current phase
-- @return number of seconds until the moon is full again
local function GetSecondsUntilFullMoon(phasePercentage)
	local secondsOffset = -phasePercentage * const.moon.phaseLengthInSeconds
	if phasePercentage > const.moon.phasesPercentage[5].endPercentage then
		secondsOffset = secondsOffset + const.moon.phaseLengthInSeconds
	end
	local secondsUntilFull = const.moon.phasesPercentage[4].endPercentage * const.moon.phaseLengthInSeconds + secondsOffset
	return secondsUntilFull
end

--- Calculate the lore moon
-- @param timestamp UNIX to be calculated from
-- @return moon object { percentageOfPhaseDone, currentPhaseName, isWaxing,
--      percentageOfCurrentPhaseDone, secondsUntilNextPhase, daysUntilNextPhase,
--      secondsUntilFullMoon, daysUntilFullMoon, percentageOfFullMoon }
local function CalculateMoon(timestamp)
	local timeSinceStart = timestamp - const.moon.startTime
	local secondsSinceNewMoon = timeSinceStart % const.moon.phaseLengthInSeconds
	local phasePercentage = secondsSinceNewMoon / const.moon.phaseLengthInSeconds
	local isWaxing = phasePercentage <= const.moon.phasesPercentage[4].endPercentage
	local currentPhaseName = GetCurrentPhaseName(phasePercentage)
	local percentageOfNextPhase = phasePercentage % const.moon.phasesPercentageBetweenPhases
	local secondsUntilNextPhase = percentageOfNextPhase * const.moon.singlePhaseLengthInSeconds
	local daysUntilNextPhase = percentageOfNextPhase * const.moon.singlePhaseLength
	local secondsUntilFullMoon = GetSecondsUntilFullMoon(phasePercentage)
	local daysUntilFullMoon = secondsUntilFullMoon / const.time.lengthOfDay
    local percentageOfFullMoon
    if phasePercentage > 0.5 then  
        percentageOfFullMoon = 1 - (phasePercentage - 0.5) * 2
    else
        percentageOfFullMoon = phasePercentage * 2
    end

	return {
		percentageOfPhaseDone = phasePercentage,
		currentPhaseName = currentPhaseName,
		isWaxing = isWaxing,
		percentageOfCurrentPhaseDone = percentageOfNextPhase,
		secondsUntilNextPhase = secondsUntilNextPhase,
		daysUntilNextPhase = daysUntilNextPhase,
		secondsUntilFullMoon = secondsUntilFullMoon,
		daysUntilFullMoon = daysUntilFullMoon,
        percentageOfFullMoon = percentageOfFullMoon
	}
end

--- Update the time with the current timestamp and store it in the time variable
-- If neccessary, update the date and store in also
local function Update()
	local systemTime = GetTimeStamp()
	time = CalculateTST(systemTime)
	needToUpdateDate = true -- TODO: Remove
	if needToUpdateDate then
		date = CalculateTSTDate(systemTime)
	end
end

--- Update the moon with the current timestamp and store it in the moon variable
local function MoonUpdate()
	local systemTime = GetTimeStamp()
	moon = CalculateMoon(systemTime)
end

-------------------
-- Commands
-------------------

--- Event to update the time and date and its listeners
local function PrintHelp()
	d("Welcome to the |cFFD700LibClock|r - TST by |c5175ea@Tyx|r [EU] help menu\n"
		.. "To show the current time, write:\n"
		.. "\t\\tst time\n"
		.. "To show a specific time at a given UNIX timestamp in seconds, write:\n"
		.. "\t\\tst time [timestamp]\n"
		.. "To show the current date, write:\n"
		.. "\t\\tst date\n"
		.. "To show a specific date at a given UNIX timestamp in seconds, write:\n"
		.. "\t\\tst date [timestamp]\n"
		.. "To show the current moon phase, write:\n"
		.. "\t\\tst moon\n"
		.. "To show a specific moon phase at a given UNIX timestamp in seconds, write:\n"
		.. "\t\\tst moon [timestamp]\n")
end

--- Handel a given command
-- If time is given, the time table will be printed.
-- If date is given, the date table will be printed.
-- If moon is given, the moon table will be printed.
-- If the second argument is a timestamp, it will be the basis for the calculations.
-- @param options table of arguments
local function CommandHandler(options)
	if #options == 0 or options[1] == "help" or #options > 2 then
		PrintHelp()
	else
		local timestamp
		local tNeedToUpdateDate = needToUpdateDate
		if #options == 2 then
			if not string.match(options[2], "^%d%d%d%d%d%d%d%d%d%d$") then
				d("Please give only a 10 digit long timestamp as your seconds argument!")
				return
			else
				timestamp = tonumber(options[2])
			end
		end
		if options[1] == "time" then
			d(CalculateTST(timestamp))
		elseif options[1] == "date" then
			d(CalculateTSTDate(timestamp))
		elseif options[1] == "moon" then
			d(CalculateMoon(timestamp))
		else
			PrintHelp()
		end
		needToUpdateDate = tNeedToUpdateDate
	end
end

--- Register the slash command 'tst'
local function RegisterCommands()
	SLASH_COMMANDS["/tst"] = function (extra)
		local options = {}
		local searchResult = { string.match(extra,"^(%S*)%s*(.-)$") }
		for i,v in pairs(searchResult) do
			if (v ~= nil and v ~= "") then
				options[i] = string.lower(v)
			end
		end
		CommandHandler(options)
	end
end

-------------------
-- Initialize
-------------------

local dateListener = {}
local moonListener = {}
local timeListener = {}
local listener = {}

--- Event to update the time and date and its listeners
local function OnUpdate()
	Update()
	assert(time, "Time object is empty")
	assert(date, "Date object is empty")

	for _, f in pairs(listener) do
		f(time, date)
	end

	for _, f in pairs(timeListener) do
		f(time)
	end

    for _, f in pairs(dateListener) do
        f(date)
    end
end

--- Event to update the moon and its listeners
local function OnMoonUpdate()
	MoonUpdate()
	assert(moon, "Moon object is empty")
	for _, f in pairs(moonListener) do
		f(moon)
	end
end

--- Event to be called on Load
local function OnLoad(_, addonName)
	if addonName ~= ID then return end
	-- wait for the first loaded event
	em:UnregisterForEvent(eventHandle, EVENT_ADD_ON_LOADED)
	RegisterCommands()
end
em:RegisterForEvent(eventHandle, EVENT_ADD_ON_LOADED, OnLoad)


-------------------
-- Public
-------------------

function TST:New(updateDelay, moonUpdateDelay)
    updateDelay = tonumber(updateDelay)
    moonUpdateDelay = tonumber(moonUpdateDelay)
	self.updateDelay = updateDelay or self.updateDelay
	self.moonUpdateDelay = moonUpdateDelay or self.moonUpdateDelay
	return self
end

--- Get the lore time
-- If a parameter is given, the lore date of the UNIX timestamp will be returned,
-- otherwise it will be the current time.
-- @param timestamp [optional]
-- @return date object {era, year, month, day, weekDay}
function TST:GetTime(timestamp)
	if timestamp then
        assert(IsTimestamp(timestamp), "Please provide nil or a valid timestamp as an argument")
        timestamp = tonumber(timestamp)
		local tNeedToUpdateDate = needToUpdateDate
		local t = CalculateTST(timestamp)
		needToUpdateDate = tNeedToUpdateDate
		return t
	else
		Update()
		return time
	end
end

--- Get the lore date
-- If a parameter is given, the lore date of the UNIX timestamp will be returned,
-- otherwise it will be calculated from the current time.
-- @param timestamp [optional]
-- @return date object {era, year, month, day, weekDay}
function TST:GetDate(timestamp)
	if timestamp then
        assert(IsTimestamp(timestamp), "Please provide nil or a valid timestamp as an argument")
        timestamp = tonumber(timestamp)
		local tNeedToUpdateDate = needToUpdateDate
		local d = CalculateTSTDate(timestamp)
		needToUpdateDate = tNeedToUpdateDate
		return d
	else
		Update()
		return date
	end
end

--- Get the lore moon
-- If a parameter is given, the lore moon of the UNIX timestamp will be returned,
-- otherwise it will be calculated from the current time.
-- @param timestamp [optional]
-- @return moon object { phasePercentage, currentPhaseName, isWaxing,
--      percentageOfNextPhase, secondsUntilNextPhase, daysUntilNextPhase,
--      secondsUntilFullMoon, daysUntilFullMoon }
function TST:GetMoon(timestamp)
	if timestamp then
        assert(IsTimestamp(timestamp), "Please provide nil or a valid timestamp as an argument")
        timestamp = tonumber(timestamp)
		return CalculateMoon(timestamp)
	else
		MoonUpdate()
		return moon
	end
end

--- Register an addon to subscribe to date and time updates.
-- @param addonId Id of the addon to be registered
-- @param func function with two parameters for time and date to be called
function TST:Register(addonId, func)
	assert(IsNotNilOrEmpty(addonId), "Please provide an ID for the addon. Store it to cancel the subscription later.")
	assert(func, "Please provide a function: func(time, date) to be called every second for a time update.")
	assert(not listener[addonId], addonId .. " already subscribes.")
	listener[addonId] = func
	em:RegisterForUpdate(eventHandle, self.updateDelay, OnUpdate)
end

--- Cancel a subscription for the date and time updates.
-- Will also stop background calculations if no addon is subscribing anymore.
-- @param addonId Id of the addon previous registered
function TST:CancelSubscription(addonId)
	assert(IsNotNilOrEmpty(addonId), "Please provide an ID to cancel the subscription.")
	assert(listener[addonId], "Subscription could not be found.")
	listener[addonId] = nil
	if #listener == 0 then
		em:UnregisterForUpdate(eventHandle)
	end
end

--- Register an addon to subscribe to time updates.
-- @param addonId Id of the addon to be registered
-- @param func function with a parameter for time to be called
-- @see TST:Register
function TST:RegisterForTime(addonId, func)
	assert(IsNotNilOrEmpty(addonId), "Please provide an ID for the addon. Store it to cancel the subscription later.")
	assert(func, "Please provide a function: func(time) to be called every second for a time update.")
	assert(not timeListener[addonId], addonId .. " already subscribes.")
	timeListener[addonId] = func
	em:RegisterForUpdate(eventHandle, self.updateDelay, OnUpdate)
end

--- Cancel a subscription for the time updates.
-- @param addonId Id of the addon previous registered
-- @see TST:CancelSubscription
function TST:CancelSubscriptionForTime(addonId)
	assert(IsNotNilOrEmpty(addonId), "Please provide an ID to cancel the subscription.")
	assert(timeListener[addonId], "Subscription could not be found.")
	timeListener[addonId] = nil
	if #timeListener == 0 then
		em:UnregisterForUpdate(eventHandle.."-Time")
	end
end

--- Register an addon to subscribe to date updates.
-- @param addonId Id of the addon to be registered
-- @param func function with a parameter for date to be called
-- @see TST:Register
function TST:RegisterForDate(addonId, func)
	assert(IsNotNilOrEmpty(addonId), "Please provide an ID for the addon. Store it to cancel the subscription later.")
	assert(func, "Please provide a function: func(date) to be called every second for a time update.")
	assert(not dateListener[addonId], addonId .. " already subscribes.")
	dateListener[addonId] = func
	em:RegisterForUpdate(eventHandle, self.updateDelay, OnUpdate)
end

--- Cancel a subscription for the date updates.
-- @param addonId Id of the addon previous registered
-- @see TST:CancelSubscription
function TST:CancelSubscriptionForDate(addonId)
	assert(IsNotNilOrEmpty(addonId), "Please provide an ID to cancel the subscription.")
	assert(dateListener[addonId], "Subscription could not be found.")
	dateListener[addonId] = nil
	if #dateListener == 0 then
		em:UnregisterForUpdate(eventHandle.."-Date")
	end
end

--- Register an addon to subscribe to moon updates.
-- @param addonId Id of the addon to be registered
-- @param func function with a parameter for moon to be called
-- @see TST:Register
function TST:RegisterForMoon(addonId, func)
	assert(IsNotNilOrEmpty(addonId), "Please provide an ID for the addon. Store it to cancel the subscription later.")
	assert(func, "Please provide a function: func(moon) to be called every second for a time update.")
	assert(not moonListener[addonId], addonId .. " already subscribes.")
	moonListener[addonId] = func
	em:RegisterForUpdate(eventHandle.."-Moon", self.moonUpdateDelay, OnMoonUpdate) -- once per hour should be enough

	-- Update once
	MoonUpdate()
	func(moon)
end

--- Cancel a subscription for the moon updates.
-- @param addonId Id of the addon previous registered
-- @see TST:CancelSubscription
function TST:CancelSubscriptionForMoon(addonId)
	assert(IsNotNilOrEmpty(addonId), "Please provide an ID to cancel the subscription.")
	assert(moonListener[addonId], "Subscription could not be found.")
	moonListener[addonId] = nil
	if #moonListener == 0  then
		em:UnregisterForUpdate(eventHandle.."-Moon")
	end
end
