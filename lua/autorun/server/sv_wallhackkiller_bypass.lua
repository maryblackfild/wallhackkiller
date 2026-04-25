--[[

          _______  _        _                       _______  _______  _              _       _________ _        _        _______  _______ 
|\     /|(  ___  )( \      ( \            |\     /|(  ___  )(  ____ \| \    /\      | \    /\\__   __/( \      ( \      (  ____ \(  ____ )
| )   ( || (   ) || (      | (            | )   ( || (   ) || (    \/|  \  / /      |  \  / /   ) (   | (      | (      | (    \/| (    )|
| | _ | || (___) || |      | |            | (___) || (___) || |      |  (_/ /       |  (_/ /    | |   | |      | |      | (__    | (____)|
| |( )| ||  ___  || |      | |            |  ___  ||  ___  || |      |   _ (        |   _ (     | |   | |      | |      |  __)   |     __)
| || || || (   ) || |      | |            | (   ) || (   ) || |      |  ( \ \       |  ( \ \    | |   | |      | |      | (      | (\ (   
| () () || )   ( || (____/\| (____/\      | )   ( || )   ( || (____/\|  /  \ \      |  /  \ \___) (___| (____/\| (____/\| (____/\| ) \ \__
(_______)|/     \|(_______/(_______/      |/     \||/     \|(_______/|_/    \/      |_/    \/\_______/(_______/(_______/(_______/|/   \__/
        
                   _                       
                  | |                      
  _ __  _   ___  _| |_ ___  __ _ _ __ ___  
 | '_ \| | | \ \/ / __/ _ \/ _` | '_ ` _ \ 
 | | | | |_| |>  <| ||  __/ (_| | | | | | |
 |_| |_|\__, /_/\_\\__\___|\__,_|_| |_| |_|
         __/ |                             
        |___/                              


By MaryBlackfild and kristov6

Hi!

This is an experimental version of WallHackKiller, and we assume no responsibility for its use during this testing phase.
However, we welcome any feedback or reports of bugs and errors, and we can help you configure it for your server.
Follow us on Telegram and Discord to get guaranteed support.

Join to our Telegram for support: t.me/nyxteam_gmod
Join to our Discord for support: discord.gg/rUEEz4mfXw

--]]

WallHackKiller = WallHackKiller or {}

local WHK = WallHackKiller
local oldSkip = WHK.skip

if oldSkip and oldSkip.stop then
	pcall(oldSkip.stop, "reload")
end

local DEFAULT_CHANNELS = {
	transmit = true,
	audio = true,
	voice = true,
	anticheat = true
}

local HOOK_PREFIX = "WHK.skipRules."
local OBS_NONE = OBS_MODE_NONE or 0

-- old hook ids can survive lua_openscript reloads
hook.Remove("PlayerDisconnected", "WHK.pass.left")
hook.Remove("EntityRemoved", "WHK.pass.gone")

local Skip = {
	rulesById = {},
	ruleOrder = {},

	-- weak keys keep reconnect spam out of these caches
	playerState = setmetatable({}, { __mode = "k" }),
	entityState = setmetatable({}, { __mode = "k" })
}

WHK.skip = Skip

local function asLookup(value)
	local lookup = {}

	if value == nil then
		return lookup
	end

	if isstring(value) or isnumber(value) then
		lookup[value] = true
		return lookup
	end

	if not istable(value) then
		return lookup
	end

	for key, item in pairs(value) do
		if isnumber(key) then
			lookup[item] = true
		elseif item then
			lookup[key] = true
		end
	end

	return lookup
end

local function channelLookup(value)
	if value == nil or value == true or value == "all" then
		return asLookup(DEFAULT_CHANNELS)
	end

	local channels = {}

	if isstring(value) then
		for part in string.gmatch(string.lower(value), "[^,%s]+") do
			channels[part] = true
		end
	elseif istable(value) then
		for key, enabled in pairs(value) do
			local name = isnumber(key) and enabled or key

			if enabled ~= false and isstring(name) and name ~= "" then
				channels[string.lower(name)] = true
			end
		end
	end

	if channels.all or next(channels) == nil then
		return asLookup(DEFAULT_CHANNELS)
	end

	return channels
end

local function normalizeRuleSide(raw)
	raw = raw or {}

	return {
		players = asLookup(raw.players),
		entities = asLookup(raw.entities),
		usergroups = asLookup(raw.usergroups or raw.ranks),
		teams = asLookup(raw.teams),
		classes = asLookup(raw.classes),
		names = asLookup(raw.names),
		states = asLookup(raw.states),
		flags = asLookup(raw.flags),
		systems = asLookup(raw.systems or raw.marks),
		predicate = isfunction(raw.predicate) and raw.predicate or nil
	}
end

local function sortRules()
	table.sort(Skip.ruleOrder, function(a, b)
		if a.priority == b.priority then
			return a.id < b.id
		end

		return a.priority > b.priority
	end)
end

local function getPlayerState(ply)
	local state = Skip.playerState[ply]

	if state then
		return state
	end

	state = {
		flags = {},
		flagExpires = {},

		systems = {},
		systemExpires = {},

		channelBypass = {},
		channelExpires = {}
	}

	Skip.playerState[ply] = state
	return state
end

local function getEntityState(ent)
	local state = Skip.entityState[ent]

	if state then
		return state
	end

	state = {
		flags = {},
		flagExpires = {},

		systems = {},
		systemExpires = {}
	}

	Skip.entityState[ent] = state
	return state
end

local function clearExpired(values, expires, now)
	if not values or not expires then
		return
	end

	for key, expireAt in pairs(expires) do
		if expireAt > 0 and expireAt <= now then
			expires[key] = nil
			values[key] = nil
		end
	end
end

local function entityMatchesBuiltinState(ent, stateName)
	if not IsValid(ent) then
		return false
	end

	if stateName == "admin" then
		return ent.IsPlayer and ent:IsPlayer() and ent:IsAdmin()
	end

	if stateName == "superadmin" then
		return ent.IsPlayer and ent:IsPlayer() and ent:IsSuperAdmin()
	end

	if stateName == "noclip" then
		return ent.IsPlayer and ent:IsPlayer() and ent:GetMoveType() == MOVETYPE_NOCLIP
	end

	if stateName == "spectate" or stateName == "observer" then
		return ent.IsPlayer and ent:IsPlayer() and ent:GetObserverMode() ~= OBS_NONE
	end

	if stateName == "alive" then
		return ent.IsPlayer and ent:IsPlayer() and ent:Alive()
	end

	if stateName == "dead" then
		return ent.IsPlayer and ent:IsPlayer() and not ent:Alive()
	end

	if stateName == "vehicle" then
		return ent.IsVehicle and ent:IsVehicle()
	end

	if stateName == "player" then
		return ent.IsPlayer and ent:IsPlayer()
	end

	if stateName == "npc" then
		return ent.IsNPC and ent:IsNPC()
	end

	return false
end

local function hasFlag(state, flag, now)
	if not state then
		return false
	end

	clearExpired(state.flags, state.flagExpires, now)
	return state.flags[flag] == true
end

local function hasSystemMark(state, mark, now)
	if not state then
		return false
	end

	clearExpired(state.systems, state.systemExpires, now)
	return state.systems[mark] == true
end

local function contextHasSystem(context, mark, side)
	if not context then
		return false
	end

	if side == "viewer" then
		if context.system == mark then
			return true
		end

		return istable(context.systems) and context.systems[mark] == true
	end

	if context.target_system == mark then
		return true
	end

	return istable(context.target_systems) and context.target_systems[mark] == true
end

local function getUsergroup(ent)
	if not (IsValid(ent) and ent.IsPlayer and ent:IsPlayer()) then
		return nil
	end

	local group = ent.GetUserGroup and ent:GetUserGroup() or nil

	if not isstring(group) or group == "" then
		return nil
	end

	return string.lower(group)
end

local function sideMatches(sideRule, ent, state, context, now, sideName)
	if sideRule == nil then
		return true
	end

	if next(sideRule.players) then
		if not (IsValid(ent) and ent.IsPlayer and ent:IsPlayer()) then
			return false
		end

		if sideRule.players[ent] ~= true then
			return false
		end
	end

	if next(sideRule.entities) and sideRule.entities[ent] ~= true then
		return false
	end

	if next(sideRule.usergroups) then
		local group = getUsergroup(ent)

		if group == nil or sideRule.usergroups[group] ~= true then
			return false
		end
	end

	if next(sideRule.teams) then
		if not (IsValid(ent) and ent.Team) then
			return false
		end

		if sideRule.teams[ent:Team()] ~= true then
			return false
		end
	end

	if next(sideRule.classes) then
		local class = IsValid(ent) and ent.GetClass and ent:GetClass() or nil

		if not isstring(class) then
			return false
		end

		if sideRule.classes[string.lower(class)] ~= true then
			return false
		end
	end

	if next(sideRule.names) then
		local name = IsValid(ent) and ent.GetName and ent:GetName() or nil

		if not isstring(name) then
			return false
		end

		if sideRule.names[string.lower(name)] ~= true then
			return false
		end
	end

	if next(sideRule.flags) then
		for flag in pairs(sideRule.flags) do
			if not hasFlag(state, flag, now) then
				return false
			end
		end
	end

	if next(sideRule.systems) then
		for mark in pairs(sideRule.systems) do
			local fromState = hasSystemMark(state, mark, now)
			local fromContext = contextHasSystem(context, mark, sideName)

			if not fromState and not fromContext then
				return false
			end
		end
	end

	if next(sideRule.states) then
		for stateName in pairs(sideRule.states) do
			if not entityMatchesBuiltinState(ent, stateName) and not hasFlag(state, stateName, now) then
				return false
			end
		end
	end

	if sideRule.predicate then
		local ok, result = pcall(sideRule.predicate, ent, context)

		if not ok or not result then
			return false
		end
	end

	return true
end

local function ruleUsesChannel(rule, channel)
	if not isstring(channel) or channel == "" then
		return false
	end

	return rule.channels[channel] == true
end

local function getManualBypass(ply, channel, now)
	local state = getPlayerState(ply)

	clearExpired(state.channelBypass, state.channelExpires, now)

	if state.channelBypass.all then
		return true, state.channelBypass.all
	end

	if state.channelBypass[channel] then
		return true, state.channelBypass[channel]
	end

	return false, nil
end

local function ruleAllows(rule, viewer, target, channel, context, now)
	if rule.enabled == false then
		return false
	end

	if not ruleUsesChannel(rule, channel) then
		return false
	end

	local viewerState = getPlayerState(viewer)
	local targetState = IsValid(target) and getEntityState(target) or nil

	if not sideMatches(rule.viewer, viewer, viewerState, context, now, "viewer") then
		return false
	end

	if IsValid(target) and not sideMatches(rule.target, target, targetState, context, now, "target") then
		return false
	end

	return true
end

function Skip.stamp(id, definition)
	if not isstring(id) or id == "" then
		return false
	end

	definition = definition or {}

	local rule = {
		id = id,
		enabled = definition.enabled ~= false,
		priority = tonumber(definition.priority) or 0,
		channels = channelLookup(definition.taplist or definition.channels),
		viewer = normalizeRuleSide(definition.viewer),
		target = normalizeRuleSide(definition.target),
		reason = definition.reason or id
	}

	Skip.rulesById[id] = rule

	local replaced = false

	for i = 1, #Skip.ruleOrder do
		if Skip.ruleOrder[i].id == id then
			Skip.ruleOrder[i] = rule
			replaced = true
			break
		end
	end

	if not replaced then
		Skip.ruleOrder[#Skip.ruleOrder + 1] = rule
	end

	sortRules()
	return true
end

function Skip.rip(id)
	if not isstring(id) or id == "" then
		return false
	end

	Skip.rulesById[id] = nil

	for i = #Skip.ruleOrder, 1, -1 do
		if Skip.ruleOrder[i].id == id then
			table.remove(Skip.ruleOrder, i)
		end
	end

	return true
end

function Skip.peek(id)
	return Skip.rulesById[id]
end

function Skip.burn(prefix)
	if prefix == nil then
		Skip.rulesById = {}
		Skip.ruleOrder = {}
		return
	end

	if not isstring(prefix) or prefix == "" then
		return
	end

	for id in pairs(Skip.rulesById) do
		if string.sub(id, 1, #prefix) == prefix then
			Skip.rip(id)
		end
	end
end

function Skip.pin_ply(ply, flag, enabled, duration)
	if not (IsValid(ply) and isstring(flag) and flag ~= "") then
		return false
	end

	local state = getPlayerState(ply)
	flag = string.lower(flag)

	if enabled then
		state.flags[flag] = true
		state.flagExpires[flag] = isnumber(duration) and duration > 0 and (CurTime() + duration) or 0
	else
		state.flags[flag] = nil
		state.flagExpires[flag] = nil
	end

	return true
end

function Skip.stamp_ply(ply, mark, enabled, duration)
	if not (IsValid(ply) and isstring(mark) and mark ~= "") then
		return false
	end

	local state = getPlayerState(ply)
	mark = string.lower(mark)

	if enabled then
		state.systems[mark] = true
		state.systemExpires[mark] = isnumber(duration) and duration > 0 and (CurTime() + duration) or 0
	else
		state.systems[mark] = nil
		state.systemExpires[mark] = nil
	end

	return true
end

function Skip.hold_ply(ply, enabled, rawChannels, duration, reason)
	if not IsValid(ply) then
		return false
	end

	local state = getPlayerState(ply)
	local channels = channelLookup(rawChannels)

	for channel in pairs(channels) do
		if enabled then
			state.channelBypass[channel] = reason or "manual_bypass"
			state.channelExpires[channel] = isnumber(duration) and duration > 0 and (CurTime() + duration) or 0
		else
			state.channelBypass[channel] = nil
			state.channelExpires[channel] = nil
		end
	end

	return true
end

function Skip.pin_ent(ent, flag, enabled, duration)
	if not (IsValid(ent) and isstring(flag) and flag ~= "") then
		return false
	end

	local state = getEntityState(ent)
	flag = string.lower(flag)

	if enabled then
		state.flags[flag] = true
		state.flagExpires[flag] = isnumber(duration) and duration > 0 and (CurTime() + duration) or 0
	else
		state.flags[flag] = nil
		state.flagExpires[flag] = nil
	end

	return true
end

function Skip.stamp_ent(ent, mark, enabled, duration)
	if not (IsValid(ent) and isstring(mark) and mark ~= "") then
		return false
	end

	local state = getEntityState(ent)
	mark = string.lower(mark)

	if enabled then
		state.systems[mark] = true
		state.systemExpires[mark] = isnumber(duration) and duration > 0 and (CurTime() + duration) or 0
	else
		state.systems[mark] = nil
		state.systemExpires[mark] = nil
	end

	return true
end

function Skip.rankline(id, groups, definition)
	definition = definition or {}
	definition.viewer = definition.viewer or {}
	definition.viewer.usergroups = groups

	return Skip.stamp(id, definition)
end

function Skip.teamline(id, teams, definition)
	definition = definition or {}
	definition.viewer = definition.viewer or {}
	definition.viewer.teams = teams

	return Skip.stamp(id, definition)
end

function Skip.plyline(id, players, definition)
	definition = definition or {}
	definition.viewer = definition.viewer or {}
	definition.viewer.players = players

	return Skip.stamp(id, definition)
end

function Skip.markline(id, systems, definition)
	definition = definition or {}
	definition.viewer = definition.viewer or {}
	definition.viewer.systems = systems

	return Skip.stamp(id, definition)
end

function Skip.ask_bouncer(viewer, target, channel, context)
	if not IsValid(viewer) then
		return false
	end

	channel = isstring(channel) and string.lower(channel) or "transmit"
	context = context or {}

	local now = CurTime()

	local bypassed, bypassReason = getManualBypass(viewer, channel, now)
	if bypassed then
		return true, bypassReason or "manual_bypass", "manual_bypass"
	end

	for i = 1, #Skip.ruleOrder do
		local rule = Skip.ruleOrder[i]

		if ruleAllows(rule, viewer, target, channel, context, now) then
			return true, rule.reason, rule.id
		end
	end

	-- local addons get one last say before core hides the entity
	local allow, reason = hook.Run("WHK.skip", viewer, target, channel, context)

	if allow then
		return true, reason or "hook", "hook"
	end

	return false
end

function Skip.boot(config)
	config = config or {}

	Skip.rip("__default_staff_groups")
	Skip.rip("__default_admin_noclip")
	Skip.rip("__default_spectators")

	if config.staff_usergroups and next(asLookup(config.staff_usergroups)) ~= nil then
		Skip.stamp("__default_staff_groups", {
			priority = 900,
			channels = config.staff_channels or "all",
			reason = "default_staff_group",
			viewer = {
				usergroups = config.staff_usergroups
			}
		})
	end

	if config.admin_noclip ~= false then
		Skip.stamp("__default_admin_noclip", {
			priority = 850,
			channels = "all",
			reason = "default_admin_noclip",
			viewer = {
				predicate = function(ply)
					return IsValid(ply)
						and ply:IsPlayer()
						and ply:IsAdmin()
						and ply:GetMoveType() == MOVETYPE_NOCLIP
				end
			}
		})
	end

	if config.spectators ~= false then
		Skip.stamp("__default_spectators", {
			priority = 800,
			channels = "all",
			reason = "default_observer",
			viewer = {
				states = {
					spectate = true
				}
			}
		})
	end
end

local function forgetPlayer(ply)
	Skip.playerState[ply] = nil
	Skip.entityState[ply] = nil
end

local function forgetEntity(ent)
	Skip.entityState[ent] = nil
end

hook.Add("PlayerDisconnected", HOOK_PREFIX .. "player_left", forgetPlayer)
hook.Add("EntityRemoved", HOOK_PREFIX .. "entity_removed", forgetEntity)

function Skip.stop()
	hook.Remove("PlayerDisconnected", HOOK_PREFIX .. "player_left")
	hook.Remove("EntityRemoved", HOOK_PREFIX .. "entity_removed")

	hook.Remove("PlayerDisconnected", "WHK.pass.left")
	hook.Remove("EntityRemoved", "WHK.pass.gone")

	Skip.rulesById = {}
	Skip.ruleOrder = {}

	Skip.playerState = setmetatable({}, { __mode = "k" })
	Skip.entityState = setmetatable({}, { __mode = "k" })
end
