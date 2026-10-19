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

local whk = WallHackKiller
local old_stop = whk._runtime_cleanup
local skip = whk.skip

if old_stop then
	pcall(old_stop, "reload")
end

whk.skip = skip

local clock = CurTime
local ok = IsValid
local vec = Vector
local cvar = CreateConVar
local err_stack = ErrorNoHaltWithStack
local server_log = ServerLog
local sys_clock = SysTime
local engine_tick = engine and engine.TickInterval and engine.TickInterval or function()
	return 0.015
end

local con_add = concommand.Add
local ents_class = ents.FindByClass
local ents_name = ents.FindByName
local ents_all = ents.GetAll
local hook_add = hook.Add
local hook_table = hook.GetTable
local hook_drop = hook.Remove
local hook_run = hook.Run
local players_all = player.GetAll
local timer_make = timer.Create
local timer_drop = timer.Remove
local timer_later = timer.Simple
local crc = util.CRC
local surface_name = util.GetSurfacePropName
local trace_hull = util.TraceHull
local trace_line = util.TraceLine

local ipairs = ipairs
local func = isfunction
local num = isnumber
local str = isstring
local tab = istable
local math_abs = math.abs
local math_ceil = math.ceil
local math_clamp = math.Clamp
local math_cos = math.cos
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local math_rad = math.rad
local math_sqrt = math.sqrt
local pairs = pairs
local pcall = pcall
local string_find = string.find
local string_format = string.format
local string_gmatch = string.gmatch
local string_lower = string.lower
local string_sub = string.sub
local table_remove = table.remove
local table_sort = table.sort
local tostring = tostring

local prefix = "WHK.core."
local mask_visual = MASK_VISIBLE_AND_NPCS or MASK_VISIBLE or MASK_SOLID
local mask_audio = MASK_VISIBLE_AND_NPCS or MASK_VISIBLE or MASK_SOLID
local obs_none = OBS_MODE_NONE or 0
local cvar_flags = FCVAR_ARCHIVE or 0
local zero_vec = vec(0, 0, 0)

local run = {
	managed_set = {},
	managed_list = {},
	viewer_states = setmetatable({}, { __mode = "k" }),
	detection = setmetatable({}, { __mode = "k" }),
	occluder_rules = {},
	occluder_order = {},
	sound_classifiers = {},
	sound_classifier_order = {},
	trace_context = nil,
	trace_skip = nil,
	trace_viewer_count = 0,
	trace_viewer_limit = 0,
	trace_global_count = 0,
	trace_global_limit = 0,
	viewer_cursor = 1,
	next_step = 0,
	next_watchdog = 0,
	last_error = 0,
	log_buffer = {},
	rule_sequence = 0,
	sound_sequence = 0,
	last_profile = nil,
	last_debug = nil,
	last_action = nil,
	last_enabled = nil
}

whk.hcls = whk.hcls or {
	companion_doll = true
}
whk.hnms = whk.hnms or {}
whk.hset = whk.hset or setmetatable({}, { __mode = "k" })
whk.harr = whk.harr or {}
whk.trk = whk.trk or setmetatable({}, { __mode = "k" })
whk.nohide = whk.nohide or setmetatable({}, { __mode = "k" })

-- spare gamemode hooks
whk._gm_wrapped = whk._gm_wrapped or {}
whk.patch = whk.patch or {}
whk.profile_name = whk.profile_name or "normal"

local cvar_profile = cvar("whk_profile", "normal", cvar_flags, "WHK profile")
local cvar_enabled = cvar("whk_enabled", "1", cvar_flags, "WHK on/off")
local cvar_debug = cvar("whk_debug", "0", cvar_flags, "WHK debug log")
local cvar_ac_action = cvar("whk_anticheat_action", "hook", cvar_flags, "WHK anticheat action")

local default_config = {
	base = {
		enabled = true,
		debug = false,
		manage_players = true,
		manage_npcs = true,
		manage_nextbots = true,
		manage_entities = true,
		use_pvs = true,
		ignore_player_occluders = true,
		ignore_npc_occluders = false,
		hide_occupied_vehicle = true,
		radius = 9000,
		fov = 145,
		candidate_fov_bonus = 18,
		tick_interval = 0.03,
		viewer_window = 0.12,
		viewers_per_step_min = 1,
		viewers_per_step_max = 14,
		candidate_refresh = 0.45,
		candidate_limit = 650,
		update_limit_per_viewer = 96,
		trace_budget_global = 2400,
		trace_budget_per_viewer = 110,
		state_reuse_interval = 0.10,
		state_reuse_eye_delta = 12,
		state_reuse_target_delta = 10,
		state_reuse_fwd_dot = 0.995,

		-- spawn lock hides fresh clients while the first trace batch warms up
		join_lock = 0.35,
		respawn_lock = 0.10,
		visible_hold_time = 0.18,
		visible_max_age = 0.35,
		trace_start_offset = 6,
		trace_continue_epsilon = 4,
		trace_hull = vec(1, 1, 1),
		trace_pass_limit = 6,
		ignored_pass_limit = 4,
		soft_hit_limit = 5,
		visible_min_clear_samples = 2,
		visible_min_clear_fraction = 0.08,
		sample_close_distance = 900,
		sample_near_distance = 2200,
		max_group_entities = 64,
		mask_visual = mask_visual,
		mask_audio = mask_audio,
		always_visible_classes = {
			worldspawn = true,
			gmod_gamerules = true,
			player_manager = true,
			soundent = true,
			ai_network = true,
			ai_hint = true,
			env_sun = true,
			env_fog_controller = true,
			env_tonemap_controller = true,
			point_worldtext = true,
			point_servercommand = true,
			env_beam = true,
			env_laser = true,
			beam = true,
			info_particle_system = true
		},
		critical_visible_classes = {
			combine_mine = true,
			npc_tripmine = true,
			npc_satchel = true,
			ttt_c4 = true,
			ttt_tripmine = true
		},
		never_manage_classes = {
			gmod_hands = true,
			viewmodel = true
		},
		never_manage_class_prefixes = {
			ai_ = true,
			ambient_ = true,
			env_ = true,
			func_ = true,
			gmod_ = true,
			info_ = true,
			logic_ = true,
			path_ = true,
			point_ = true,
			trigger_ = true
		}
	},
	visual = {
		prediction = false,
		prediction_times = {
			0.06,
			0.12,
			0.18
		},
		prediction_min_viewer_speed = 120,
		prediction_min_target_speed = 80,
		hide_on_soft = true,
		soft_hide_delay = 0.18
	},
	occluders = {
		alpha_ignore = 28,
		alpha_soft = 160,
		ignored_small_volume = 14000,
		ignored_small_max = 24,
		soft_thickness = 10
	},
	audio = {
		enabled = true,
		cache_ttl = 0.18,
		quantize = 16,
		max_distance = 9000,
		reference_level = 70,
		reference_distance = 1250,
		level_exponent = 21,
		trace_pass_limit = 5,
		ignored_pass_limit = 4,
		mask = mask_audio,
		categories = {
			default = {
				enabled = true,
				hard = "mute",
				soft = "attenuate",
				soft_volume_scale = 0.72,
				soft_level_scale = 0.86,
				hard_volume_scale = 0.45,
				hard_level_scale = 0.70,
				max_distance_scale = 1.0
			},
			footsteps = {
				hard = "mute",
				soft = "attenuate",
				soft_volume_scale = 0.40,
				soft_level_scale = 0.55,
				hard_volume_scale = 0.15,
				hard_level_scale = 0.30,
				max_distance_scale = 0.55
			},
			weapon_fire = {
				hard = "attenuate",
				soft = "allow",
				soft_volume_scale = 0.92,
				soft_level_scale = 0.96,
				hard_volume_scale = 0.62,
				hard_level_scale = 0.78,
				max_distance_scale = 1.0
			},
			reload = {
				hard = "mute",
				soft = "attenuate",
				soft_volume_scale = 0.48,
				soft_level_scale = 0.64,
				hard_volume_scale = 0.22,
				hard_level_scale = 0.36,
				max_distance_scale = 0.65
			},
			body = {
				hard = "mute",
				soft = "attenuate",
				soft_volume_scale = 0.42,
				soft_level_scale = 0.58,
				hard_volume_scale = 0.18,
				hard_level_scale = 0.32,
				max_distance_scale = 0.60
			},
			pain = {
				hard = "attenuate",
				soft = "attenuate",
				soft_volume_scale = 0.68,
				soft_level_scale = 0.80,
				hard_volume_scale = 0.50,
				hard_level_scale = 0.70,
				max_distance_scale = 0.95
			},
			death = {
				hard = "attenuate",
				soft = "allow",
				soft_volume_scale = 0.88,
				soft_level_scale = 0.92,
				hard_volume_scale = 0.64,
				hard_level_scale = 0.80,
				max_distance_scale = 1.0
			},
			npc_voice = {
				hard = "attenuate",
				soft = "allow",
				soft_volume_scale = 0.82,
				soft_level_scale = 0.90,
				hard_volume_scale = 0.55,
				hard_level_scale = 0.74,
				max_distance_scale = 1.0
			},
			player_voice = {
				hard = "mute",
				soft = "attenuate",
				soft_volume_scale = 0.62,
				soft_level_scale = 0.78,
				hard_volume_scale = 0.28,
				hard_level_scale = 0.42,
				max_distance_scale = 0.85
			},
			ambience = {
				hard = "attenuate",
				soft = "allow",
				soft_volume_scale = 0.86,
				soft_level_scale = 0.92,
				hard_volume_scale = 0.60,
				hard_level_scale = 0.78,
				max_distance_scale = 1.0
			}
		}
	},
	voice = {
		enabled = true,
		radius = 2500,
		use3d = false,
		hard = "mute",
		soft = "allow",
		cache_ttl = 0.15
	},
	anticheat = {
		enabled = true,
		action = "hook",
		cooldown = 8.0,
		decay_per_second = 10,
		global_threshold = 40,
		max_range = 4200,
		aim_fov = 2.2,
		track_fov = 3.4,
		aim_window = 0.24,
		track_window = 0.90,
		damage_hidden_hits = 2,
		scan_limit = 22,
		hard_hidden_only = true,
		audio_blind_window = 0.90,
		reason_scores = {
			aim_hidden = 8,
			damage_hidden = 18,
			repeated_tracking_hidden = 10,
			suspicious_audio_tracking = 12
		},
		reason_thresholds = {
			aim_hidden = 24,
			damage_hidden = 24,
			repeated_tracking_hidden = 28,
			suspicious_audio_tracking = 20
		},
		reason_cooldowns = {
			aim_hidden = 1.0,
			damage_hidden = 2.5,
			repeated_tracking_hidden = 2.0,
			suspicious_audio_tracking = 2.0
		}
	},
	bypass = {
		staff_usergroups = {},
		staff_channels = "",
		admin_noclip = false,
		spectators = false
	}
}

local profile_patches = {
	off = {
		base = {
			enabled = false
		},
		audio = {
			enabled = false
		},
		voice = {
			enabled = false
		},
		anticheat = {
			enabled = false
		}
	},
	normal = {},
	aggressive = {
		visual = {
			hide_on_soft = true,
			soft_hide_delay = 0.25
		},
		audio = {
			categories = {
				weapon_fire = {
					soft = "attenuate"
				},
				npc_voice = {
					soft = "attenuate"
				}
			}
		},
		voice = {
			soft = "mute"
		},
		anticheat = {
			global_threshold = 34
		}
	},
	paranoid = {
		base = {
			visible_hold_time = 0.10,
			trace_pass_limit = 4,
			soft_hit_limit = 2
		},
		visual = {
			prediction = false,
			hide_on_soft = true,
			soft_hide_delay = 0.05
		},
		audio = {
			categories = {
				default = {
					soft = "mute"
				},
				weapon_fire = {
					soft = "attenuate"
				},
				death = {
					soft = "attenuate"
				},
				npc_voice = {
					soft = "attenuate"
				},
				ambience = {
					soft = "attenuate"
				}
			}
		},
		voice = {
			soft = "mute"
		},
		anticheat = {
			global_threshold = 28
		}
	}
}

whk.defaults = default_config
whk.profiles = profile_patches

local function copy(value)
	if not tab(value) then
		return value
	end

	local out = {}

	for key, item in pairs(value) do
		out[key] = copy(item)
	end

	return out
end

local function merge(target, patch)
	if not tab(target) or not tab(patch) then
		return target
	end

	for key, value in pairs(patch) do
		if tab(value) and tab(target[key]) then
			merge(target[key], value)
		else
			target[key] = copy(value)
		end
	end

	return target
end

local function setof(input)
	local out = {}

	if input == nil then
		return out
	end

	if str(input) or num(input) then
		out[input] = true
		return out
	end

	if not tab(input) then
		return out
	end

	for key, value in pairs(input) do
		if num(key) then
			out[value] = true
		elseif value then
			out[key] = true
		end
	end

	return out
end

local function lower(value)
	if not str(value) or value == "" then
		return ""
	end

	return string_lower(value)
end

local function log_push(message)
	local buffer = run.log_buffer
	buffer[#buffer + 1] = message
	if #buffer > 128 then
		table_remove(buffer, 1)
	end
end

local function log(message)
	local line = string_format("[WHK] %s\n", message)
	log_push(line)
	server_log(line)
end

local function debug_on()
	return whk.config and whk.config.base and whk.config.base.debug == true
end

local function dbg(message)
	if debug_on() then
		log(message)
	end
end

whk.log = log

local function action_name(action)
	action = lower(action)

	if action == "kick" or action == "punish" or action == "log" or action == "hook" then
		return action
	end

	return "hook"
end

local function channels(channels)
	if channels == nil or channels == true or channels == "all" then
		return {
			transmit = true,
			audio = true,
			voice = true,
			anticheat = true
		}
	end

	local out = {}

	if str(channels) then
		for token in string_gmatch(lower(channels), "[^,%s]+") do
			out[token] = true
		end
	elseif tab(channels) then
		for key, value in pairs(channels) do
			local name = num(key) and value or key
			if value ~= false and str(name) then
				out[lower(name)] = true
			end
		end
	end

	if out.all then
		return {
			transmit = true,
			audio = true,
			voice = true,
			anticheat = true
		}
	end

	return out
end

local function exacts(input)
	local out = {}

	if input == nil then
		return out
	end

	if str(input) or num(input) then
		out[lower(input)] = true
		return out
	end

	if not tab(input) then
		return out
	end

	for key, value in pairs(input) do
		if num(key) then
			out[lower(value)] = true
		elseif value then
			out[lower(key)] = true
		end
	end

	return out
end

local function patterns(input)
	local out = {}

	if input == nil then
		return out
	end

	if str(input) then
		out[1] = lower(input)
		return out
	end

	if not tab(input) then
		return out
	end

	for key, value in pairs(input) do
		local pattern = num(key) and value or (value and key or nil)
		if str(pattern) and pattern ~= "" then
			out[#out + 1] = string_lower(pattern)
		end
	end

	return out
end

local function picked(value, exact, patterns)
	local has_exact = next(exact) ~= nil
	local has_pattern = #patterns > 0

	if not has_exact and not has_pattern then
		return true
	end

	value = lower(value)
	if value == "" then
		return false
	end

	if has_exact and exact[value] then
		return true
	end

	if has_pattern then
		for index = 1, #patterns do
			if string_find(value, patterns[index], 1, true) then
				return true
			end
		end
	end

	return false
end

local function has_text(text, patterns)
	text = lower(text)
	if text == "" then
		return false
	end

	for index = 1, #patterns do
		if string_find(text, patterns[index], 1, true) then
			return true
		end
	end

	return false
end

local function cfg()
	return whk.config
end

local function math_state()
	local config = cfg()
	local base = config.base
	local ac = config.anticheat

	run.dot_visual = math_cos(math_rad(base.fov * 0.5))
	run.dot_candidate = math_cos(math_rad((base.fov + base.candidate_fov_bonus) * 0.5))
	run.dot_aim = math_cos(math_rad(ac.aim_fov))
	run.dot_track = math_cos(math_rad(ac.track_fov))
end

local function audio_cfg()
	local config = cfg()
	local categories = config.audio.categories or {}
	local compiled = {}
	local defaults = categories.default or {}

	for name, settings in pairs(categories) do
		if name ~= "compiled" then
			local entry = copy(defaults)
			if settings ~= defaults then
				merge(entry, settings)
			end
			compiled[name] = entry
		end
	end

	if compiled.default == nil then
		compiled.default = copy(defaults)
	end

	config.audio.compiled = compiled
end

local function make_config()
	local profile = lower(cvar_profile and cvar_profile:GetString() or whk.profile_name)
	if profile_patches[profile] == nil then
		profile = "normal"
	end

	whk.profile_name = profile

	local built = copy(default_config)
	merge(built, profile_patches[profile] or {})
	merge(built, whk.patch or {})

	if cvar_enabled and not cvar_enabled:GetBool() then
		built.base.enabled = false
	end

	if cvar_debug and cvar_debug:GetBool() then
		built.base.debug = true
	end

	if cvar_ac_action then
		built.anticheat.action = action_name(cvar_ac_action:GetString())
	end

	whk.config = built
	whk.cfg = built

	math_state()
	audio_cfg()

	if skip and skip.boot then
		skip.boot(built.bypass)
	end
end

local function profile_line()
	return string_format(
		"profile=%s enabled=%s audio=%s voice=%s ac=%s",
		whk.profile_name,
		tostring(cfg().base.enabled),
		tostring(cfg().audio.enabled),
		tostring(cfg().voice.enabled),
		tostring(cfg().anticheat.enabled)
	)
end

function whk.setup(patch)
	if not tab(patch) then
		return false
	end

	whk.patch = whk.patch or {}
	merge(whk.patch, patch)
	make_config()
	if whk.reset then
		whk.reset("config")
	end
	dbg("config updated: " .. profile_line())
	return true
end

function whk.profile(name)
	name = lower(name)
	if profile_patches[name] == nil then
		return false
	end

	whk.profile_name = name
	if cvar_profile and cvar_profile.SetString then
		cvar_profile:SetString(name)
	end

	make_config()
	if whk.reset then
		whk.reset("profile")
	end
	dbg("profile switched: " .. name)
	return true
end

function whk.current()
	return whk.profile_name
end

local function pack_roots()
	local write = 1

	for read = 1, #whk.harr do
		local entity = whk.harr[read]
		if ok(entity) and whk.hset[entity] then
			whk.harr[write] = entity
			write = write + 1
		end
	end

	for index = write, #whk.harr do
		whk.harr[index] = nil
	end
end

local function pinned(entity)
	if not ok(entity) then
		return true
	end

	local class = lower(entity.GetClass and entity:GetClass() or nil)
	if class ~= "" then
		if cfg().base.always_visible_classes[class] or cfg().base.critical_visible_classes[class] then
			return true
		end
	end

	if whk.nohide[entity] or entity.whk_nohide then
		return true
	end

	return false
end

local function driver(vehicle)
	if not (ok(vehicle) and vehicle.IsVehicle and vehicle:IsVehicle()) then
		return nil
	end

	local driver = vehicle.GetDriver and vehicle:GetDriver() or nil
	if ok(driver) then
		return driver
	end

	return nil
end

local function root_of(entity)
	if not ok(entity) then
		return nil
	end

	local now = clock()
	local cached = entity.whk_root
	local expire = entity.whk_root_till or 0
	if ok(cached) and expire > now then
		return cached
	end

	local root = entity

	for _ = 1, 8 do
		local parent = root.GetParent and root:GetParent() or nil
		if not ok(parent) then
			break
		end
		root = parent
	end

	if root.IsVehicle and root:IsVehicle() then
		local driver = driver(root)
		if ok(driver) then
			root = driver
		end
	end

	if root.IsWeapon and root:IsWeapon() then
		local owner = root.GetOwner and root:GetOwner() or nil
		if ok(owner) then
			root = owner
		end
	end

	local owner = root.GetOwner and root:GetOwner() or nil
	if ok(owner) and owner ~= root and (owner:IsPlayer() or owner:IsNPC() or owner:IsNextBot()) then
		root = owner
	end

	entity.whk_root = root
	entity.whk_root_till = now + 0.20

	return root
end

local function same_root(entity, root)
	if not (ok(entity) and ok(root)) then
		return false
	end

	return root_of(entity) == root
end

local push_roots
local free_roots

local function add_root(root)
	if not ok(root) or run.managed_set[root] then
		return
	end

	run.managed_set[root] = true
	run.managed_list[#run.managed_list + 1] = root

	if push_roots then
		push_roots(root, "default_hidden")
	end
end

local function drop_root(root)
	if not run.managed_set[root] then
		return
	end

	run.managed_set[root] = nil

	if free_roots then
		free_roots(root)
	end

	local list = run.managed_list
	for index = #list, 1, -1 do
		if list[index] == root then
			table_remove(list, index)
			break
		end
	end
end

local function bad_prefix(class, prefixes)
	if class == "" or not tab(prefixes) then
		return false
	end

	for prefix, enabled in pairs(prefixes) do
		local value = num(prefix) and enabled or prefix
		local active = num(prefix) and enabled ~= false or enabled
		if active and str(value) and value ~= "" and string_sub(class, 1, #value) == value then
			return true
		end
	end

	return false
end

local function managed_root(root)
	if not ok(root) then
		return false
	end

	if pinned(root) then
		return false
	end

	if root.IsWorld and root:IsWorld() then
		return false
	end

	local class = lower(root.GetClass and root:GetClass() or nil)
	if class ~= "" and cfg().base.never_manage_classes[class] then
		return false
	end

	if bad_prefix(class, cfg().base.never_manage_class_prefixes) then
		return false
	end

	local external = hook_run("WHK.manage", root)
	if external ~= nil then
		return external == true
	end

	if whk.hset[root] or whk.trk[root] or root.whk_managed then
		return true
	end

	if class ~= "" and whk.hcls[lower(class)] then
		return true
	end

	local name = lower(root.GetName and root:GetName() or nil)
	if name ~= "" and whk.hnms[name] then
		return true
	end

	if root:IsPlayer() then
		return cfg().base.manage_players
	end

	if root:IsNPC() then
		return cfg().base.manage_npcs
	end

	if root:IsNextBot() then
		return cfg().base.manage_nextbots
	end

	if cfg().base.manage_entities and class ~= "" then
		return true
	end

	return false
end

local function touch_root(entity)
	local root = root_of(entity)
	if not ok(root) then
		return nil
	end

	if managed_root(root) then
		add_root(root)
	else
		drop_root(root)
	end

	return root
end

local function sync_lists()
	pack_roots()

	for root in pairs(whk.hset) do
		if not ok(root) then
			whk.hset[root] = nil
		else
			touch_root(root)
		end
	end

	for root in pairs(whk.trk) do
		if not ok(root) then
			whk.trk[root] = nil
		else
			touch_root(root)
		end
	end

	for root in pairs(whk.nohide) do
		if not ok(root) then
			whk.nohide[root] = nil
		end
	end
end

function whk.add(entity)
	if not ok(entity) then
		return false
	end

	entity = root_of(entity)
	if not ok(entity) then
		return false
	end

	if whk.hset[entity] then
		return true
	end

	whk.hset[entity] = true
	whk.harr[#whk.harr + 1] = entity
	touch_root(entity)
	whk.refresh()
	return true
end

function whk.drop(entity)
	if not ok(entity) then
		return false
	end

	entity = root_of(entity)
	if not ok(entity) then
		return false
	end

	whk.hset[entity] = nil
	pack_roots()
	touch_root(entity)
	whk.refresh()
	return true
end

function whk.wipe()
	for entity in pairs(whk.hset) do
		whk.hset[entity] = nil
	end

	for index = #whk.harr, 1, -1 do
		whk.harr[index] = nil
	end

	sync_lists()
	whk.refresh()
end

function whk.track(entity, enabled)
	if not ok(entity) then
		return false
	end

	entity = root_of(entity)
	if not ok(entity) then
		return false
	end

	if enabled then
		whk.trk[entity] = true
	else
		whk.trk[entity] = nil
	end

	touch_root(entity)
	whk.refresh()
	return true
end

function whk.keep(entity, enabled)
	if not ok(entity) then
		return false
	end

	entity = root_of(entity)
	if not ok(entity) then
		return false
	end

	if enabled then
		whk.nohide[entity] = true
		entity.whk_nohide = true
	else
		whk.nohide[entity] = nil
		entity.whk_nohide = nil
	end

	touch_root(entity)
	whk.refresh()
	return true
end

function whk.players(enabled)
	whk.setup({
		base = {
			manage_players = enabled == true
		}
	})
	return true
end

function whk.predict(enabled)
	whk.setup({
		visual = {
			prediction = enabled == true
		}
	})
	return true
end

function whk.ac(enabled)
	whk.setup({
		anticheat = {
			enabled = enabled == true
		}
	})
	return true
end

function whk.class(classname)
	classname = lower(classname)
	if classname == "" then
		return false
	end

	whk.hcls[classname] = true
	whk.reset("auto_hide_class")
	return true
end

function whk.unclass(classname)
	classname = lower(classname)
	if classname == "" then
		return false
	end

	whk.hcls[classname] = nil
	whk.reset("auto_hide_class")
	return true
end

function whk.name(name)
	name = lower(name)
	if name == "" then
		return false
	end

	whk.hnms[name] = true
	whk.reset("auto_hide_name")
	return true
end

function whk.unname(name)
	name = lower(name)
	if name == "" then
		return false
	end

	whk.hnms[name] = nil
	whk.reset("auto_hide_name")
	return true
end

local function wall_rule(bucket, definition)
	run.rule_sequence = run.rule_sequence + 1
	definition = definition or {}

	return {
		id = definition.id or (bucket .. "_" .. run.rule_sequence),
		bucket = bucket,
		priority = tonumber(definition.priority) or 0,
		classnames = exacts(definition.classname or definition.classnames or definition.class),
		classname_patterns = patterns(definition.classname_patterns or definition.class_patterns),
		models = exacts(definition.model or definition.models),
		model_patterns = patterns(definition.model_patterns),
		materials = exacts(definition.material or definition.materials),
		material_patterns = patterns(definition.material_patterns),
		surfaceprops = exacts(definition.surfaceprop or definition.surfaceprops),
		surfaceprop_patterns = patterns(definition.surfaceprop_patterns),
		textures = exacts(definition.texture or definition.textures),
		texture_patterns = patterns(definition.texture_patterns),
		names = exacts(definition.name or definition.names),
		name_patterns = patterns(definition.name_patterns),
		predicate = func(definition.predicate) and definition.predicate or nil
	}
end

local function sort_walls()
	table_sort(run.occluder_order, function(left, right)
		if left.priority == right.priority then
			return left.id < right.id
		end

		return left.priority > right.priority
	end)
end

function whk.wall(bucket, definition)
	bucket = lower(bucket)
	if bucket ~= "hard" and bucket ~= "soft" and bucket ~= "ignored" then
		return nil
	end

	local rule = wall_rule(bucket, definition)
	run.occluder_rules[rule.id] = rule
	run.occluder_order[#run.occluder_order + 1] = rule
	sort_walls()
	return rule.id
end

function whk.unwall(id)
	if not str(id) or id == "" then
		return false
	end

	run.occluder_rules[id] = nil

	for index = #run.occluder_order, 1, -1 do
		if run.occluder_order[index].id == id then
			table_remove(run.occluder_order, index)
		end
	end

	return true
end

local function wipe_walls()
	for id in pairs(run.occluder_rules) do
		if string_sub(id, 1, 10) == "__builtin_" then
			whk.unwall(id)
		end
	end
end

local function stock_walls()
	wipe_walls()

	whk.wall("ignored", {
		id = "__builtin_ignored_helpers",
		priority = 500,
		classnames = {
			env_sprite = true,
			env_beam = true,
			beam = true,
			info_particle_system = true,
			point_worldtext = true,
			prop_ragdoll = false
		},
		texture_patterns = {
			"tools/toolsskybox",
			"tools/toolsnodraw",
			"tools/toolsinvisible",
			"tools/toolsclip",
			"tools/toolstrigger"
		}
	})

	whk.wall("soft", {
		id = "__builtin_soft_glass",
		priority = 450,
		classnames = {
			func_breakable_surf = true
		},
		material_patterns = {
			"glass",
			"chain",
			"grate",
			"mesh",
			"screen",
			"fence",
			"rail",
			"bar",
			"ladder",
			"window"
		},
		model_patterns = {
			"glass",
			"window",
			"grate",
			"fence",
			"railing",
			"ladder",
			"bars",
			"chainlink",
			"gate"
		},
		surfaceprop_patterns = {
			"glass",
			"grate",
			"chain",
			"metalgrate"
		},
		texture_patterns = {
			"glass",
			"window",
			"grate",
			"chain",
			"fence",
			"railing",
			"bars",
			"screen",
			"mesh",
			"ladder"
		}
	})

	whk.wall("hard", {
		id = "__builtin_hard_doors",
		priority = 400,
		classname_patterns = {
			"func_door",
			"prop_door",
			"func_brush",
			"func_wall",
			"func_movelinear"
		}
	})
end

local function sound_rule(id, callback, priority)
	return {
		id = id,
		callback = callback,
		priority = tonumber(priority) or 0
	}
end

local function sort_sounds()
	table_sort(run.sound_classifier_order, function(left, right)
		if left.priority == right.priority then
			return left.id < right.id
		end

		return left.priority > right.priority
	end)
end

function whk.sound(id, callback, priority)
	if not (str(id) and id ~= "" and func(callback)) then
		return false
	end

	local entry = sound_rule(id, callback, priority)
	run.sound_classifiers[id] = entry

	local replaced = false
	for index = 1, #run.sound_classifier_order do
		if run.sound_classifier_order[index].id == id then
			run.sound_classifier_order[index] = entry
			replaced = true
			break
		end
	end

	if not replaced then
		run.sound_classifier_order[#run.sound_classifier_order + 1] = entry
	end

	sort_sounds()
	return true
end

function whk.unsound(id)
	if not str(id) or id == "" then
		return false
	end

	run.sound_classifiers[id] = nil

	for index = #run.sound_classifier_order, 1, -1 do
		if run.sound_classifier_order[index].id == id then
			table_remove(run.sound_classifier_order, index)
		end
	end

	return true
end

local function viewer_box(viewer)
	local state = run.viewer_states[viewer]
	if state then
		return state
	end

	state = {
		visible = {},
		occlusion = {},
		visible_until = {},
		soft_since = {},
		last_eval = {},
		transmit_groups = {},
		candidates = {},
		candidate_set = {},
		candidate_cursor = 1,
		next_candidate_refresh = 0,
		join_lock = 0,
		audio_cache = {},
		voice_cache = {}
	}

	run.viewer_states[viewer] = state
	return state
end

local function heat_box(viewer)
	local detection = run.detection[viewer]
	if detection then
		return detection
	end

	detection = {
		total = 0,
		reason_totals = {},
		reason_stamp = {},
		report_cooldown = 0,
		last_decay = clock(),
		tracking = {},
		damage = {},
		audio_blind_until = {}
	}

	run.detection[viewer] = detection
	return detection
end

local function clear_viewer(viewer)
	run.viewer_states[viewer] = nil
	run.detection[viewer] = nil
end

local function owns(viewer, entity)
	if not (ok(viewer) and ok(entity)) then
		return false
	end

	if entity == viewer then
		return true
	end

	if entity.GetOwner and entity:GetOwner() == viewer then
		return true
	end

	if entity.IsWeapon and entity:IsWeapon() and entity.GetOwner and entity:GetOwner() == viewer then
		return true
	end

	if entity.IsVehicle and entity:IsVehicle() and viewer.GetVehicle and viewer:GetVehicle() == entity then
		return true
	end

	local root = root_of(entity)
	if root == viewer then
		return true
	end

	return false
end

local function group_of(root)
	local group = {}
	local seen = {}
	local queue = {
		root
	}
	local read = 1
	local max_ents = cfg().base.max_group_entities

	while queue[read] ~= nil and #group < max_ents do
		local entity = queue[read]
		read = read + 1

		if ok(entity) and not seen[entity] then
			seen[entity] = true
			group[#group + 1] = entity

			local children = entity.GetChildren and entity:GetChildren() or nil
			if children then
				for index = 1, #children do
					local child = children[index]
					if ok(child) and not seen[child] then
						queue[#queue + 1] = child
					end
				end
			end

			if entity:IsPlayer() then
				local vehicle = entity.GetVehicle and entity:GetVehicle() or nil
				if cfg().base.hide_occupied_vehicle and ok(vehicle) and not seen[vehicle] then
					queue[#queue + 1] = vehicle
				end

				local weapons = entity.GetWeapons and entity:GetWeapons() or nil
				if weapons then
					for index = 1, #weapons do
						local weapon = weapons[index]
						if ok(weapon) and not seen[weapon] then
							queue[#queue + 1] = weapon
						end
					end
				end
			elseif entity.IsVehicle and entity:IsVehicle() then
				local driver = driver(entity)
				if ok(driver) and not seen[driver] then
					queue[#queue + 1] = driver
				end
			end

			local owner = entity.GetOwner and entity:GetOwner() or nil
			if ok(owner) and not seen[owner] and (owner:IsPlayer() or owner:IsNPC() or owner:IsNextBot()) then
				queue[#queue + 1] = owner
			end
		end
	end

	return group
end

local function block_group(root, viewer, hidden, state)
	if not (ok(root) and ok(viewer) and state) then
		return
	end

	local group = group_of(root)
	local previous = state.transmit_groups[root] or {}
	local current = {}

	for index = 1, #group do
		local entity = group[index]
		if ok(entity) then
			current[entity] = true
			entity:SetPreventTransmit(viewer, hidden)
		end
	end

	for index = 1, #previous do
		local entity = previous[index]
		if ok(entity) and not current[entity] then
			entity:SetPreventTransmit(viewer, false)
		end
	end

	state.transmit_groups[root] = group
end

local function clear_group(viewer, state, root)
	if not (ok(viewer) and state and root) then
		return
	end

	local previous = state.transmit_groups[root]
	if previous == nil then
		return
	end

	for index = 1, #previous do
		local entity = previous[index]
		if ok(entity) then
			entity:SetPreventTransmit(viewer, false)
		end
	end

	state.transmit_groups[root] = nil
end

free_roots = function(root)
	local viewers = players_all()

	for index = 1, #viewers do
		local viewer = viewers[index]
		local state = run.viewer_states[viewer]
		if ok(viewer) and state then
			clear_group(viewer, state, root)
			state.visible[root] = nil
			state.occlusion[root] = nil
			state.visible_until[root] = nil
			state.soft_since[root] = nil
			state.last_eval[root] = nil
			state.audio_cache[root] = nil
			state.voice_cache[root] = nil
			state.candidate_set[root] = nil
		end
	end
end

local function push_vis(viewer, state, root, visible, occlusion, now)
	local current = state.visible[root]

	state.visible[root] = visible == true
	state.occlusion[root] = occlusion or (visible and "clear" or "hard")

	if visible and occlusion ~= "hold" and occlusion ~= "partial_hold" then
		state.visible_until[root] = now + cfg().base.visible_hold_time
	else
		if not visible then
			state.soft_since[root] = nil
			state.visible_until[root] = nil
		end
	end

	if current ~= state.visible[root] or state.visible[root] == false then
		block_group(root, viewer, not state.visible[root], state)
	end
end

local function gap(viewer, target, channel, context)
	if not (skip and skip.ask_bouncer) then
		return false
	end

	return skip.ask_bouncer(viewer, target, channel, context or {})
end

local function allowed(viewer, entity, root)
	if not (ok(viewer) and ok(entity) and ok(root)) then
		return false
	end

	if pinned(root) or pinned(entity) then
		return true
	end

	if owns(viewer, entity) or owns(viewer, root) then
		return true
	end

	local hole = gap(viewer, root, "transmit", {
		entity = entity
	})

	return hole == true
end

local hard_list = {
	hard = true,
	hard_hidden = true,
	out_of_pvs = true,
	out_of_range = true,
	out_of_fov = true,
	candidate_outside = true,
	default_hidden = true,
	join_lock = true,
	stale_visible = true,
	budget_hidden = true
}

local function hard_mark(reason)
	return hard_list[reason] == true
end

local function push_root(root, viewer, state, reason, now)
	if not (ok(root) and ok(viewer) and viewer:IsPlayer() and state) then
		return
	end

	now = now or clock()

	if root == viewer or allowed(viewer, root, root) then
		if state.visible[root] ~= true then
			push_vis(viewer, state, root, true, "always_visible", now)
		else
			block_group(root, viewer, false, state)
		end
		return
	end

	if state.visible[root] == true then
		block_group(root, viewer, false, state)
		return
	end

	state.visible[root] = false
	state.occlusion[root] = reason or state.occlusion[root] or "default_hidden"
	state.visible_until[root] = nil
	state.soft_since[root] = nil
	block_group(root, viewer, true, state)
end

push_roots = function(root, reason)
	if not (ok(root) and managed_root(root)) then
		return
	end

	local now = clock()
	local viewers = players_all()

	for index = 1, #viewers do
		local viewer = viewers[index]
		if ok(viewer) and viewer:IsPlayer() then
			push_root(root, viewer, viewer_box(viewer), reason or "default_hidden", now)
		end
	end
end

local function guard_viewer(viewer, state, now)
	local stale_after = cfg().base.visible_max_age

	for index = 1, #run.managed_list do
		local root = run.managed_list[index]
		if ok(root) and root ~= viewer then
			if managed_root(root) then
				if allowed(viewer, root, root) then
					if state.visible[root] ~= true then
						push_vis(viewer, state, root, true, "always_visible", now)
					end
				elseif state.visible[root] ~= true then
					push_root(root, viewer, state, state.occlusion[root] or "default_hidden", now)
				elseif num(stale_after) and stale_after >= 0 then
					local last = state.last_eval[root]
					if last == nil or (now - last.time) > stale_after then
						push_vis(viewer, state, root, false, "stale_visible", now)
					end
				end
			else
				drop_root(root)
			end
		end
	end
end

local function aim_dir(viewer)
	local forward = viewer:EyeAngles():Forward()
	if not forward then
		return vec(1, 0, 0)
	end

	return forward
end

local function in_arc(eye, forward, point, limit)
	local delta = point - eye
	local len_sqr = delta:LengthSqr()
	if len_sqr <= 1 then
		return true
	end

	local dot = forward:Dot(delta)
	if dot <= 0 then
		return false
	end

	return dot >= limit * math_sqrt(len_sqr)
end

local function in_pvs(viewer, root)
	if not cfg().base.use_pvs or not (viewer.TestPVS and ok(root)) then
		return true
	end

	return viewer:TestPVS(root)
end

local function point(points, seen, point)
	local key = string_format("%d:%d:%d", math_floor(point.x + 0.5), math_floor(point.y + 0.5), math_floor(point.z + 0.5))
	if seen[key] then
		return
	end

	seen[key] = true
	points[#points + 1] = point
end

local function points(root, eye, mode)
	local cache_key = mode == "audio" and "whk_audio_points" or "whk_visual_points"
	local expire_key = cache_key .. "Expire"
	local close = eye:DistToSqr(root:WorldSpaceCenter()) <= (cfg().base.sample_close_distance * cfg().base.sample_close_distance)
	local near = eye:DistToSqr(root:WorldSpaceCenter()) <= (cfg().base.sample_near_distance * cfg().base.sample_near_distance)
	local cached = root[cache_key]
	if cached and root[expire_key] and root[expire_key] > clock() and cached.close == close and cached.near == near then
		return cached.points
	end

	local mins = root:OBBMins()
	local maxs = root:OBBMaxs()
	local center = vec((mins.x + maxs.x) * 0.5, (mins.y + maxs.y) * 0.5, (mins.z + maxs.z) * 0.5)
	local height = maxs.z - mins.z
	local low = mins.z + height * 0.18
	local knee = mins.z + height * 0.35
	local chest = mins.z + height * 0.62
	local head = mins.z + height * 0.88
	local points = {}
	local seen = {}

	point(points, seen, center)
	point(points, seen, vec(center.x, center.y, head))
	point(points, seen, vec(center.x, center.y, knee))

	if root.EyePos and (root:IsPlayer() or root:IsNPC() or root:IsNextBot()) then
		local good, eye = pcall(root.EyePos, root)
		if good and eye then
			point(points, seen, root:WorldToLocal(eye))
		end
	end

	if mode ~= "audio" and near then
		local z_list = {
			knee,
			chest,
			head
		}

		for index = 1, #z_list do
			local z = z_list[index]
			point(points, seen, vec(maxs.x, center.y, z))
			point(points, seen, vec(mins.x, center.y, z))
			point(points, seen, vec(center.x, maxs.y, z))
			point(points, seen, vec(center.x, mins.y, z))
		end
	end

	if mode ~= "audio" and close then
		local xs = {
			mins.x,
			maxs.x
		}
		local ys = {
			mins.y,
			maxs.y
		}
		local zs = {
			low,
			knee,
			chest,
			head
		}

		for xi = 1, #xs do
			for yi = 1, #ys do
				for zi = 1, #zs do
					point(points, seen, vec(xs[xi], ys[yi], zs[zi]))
				end
			end
		end
	end

	root[cache_key] = {
		close = close,
		near = near,
		points = points
	}
	root[expire_key] = clock() + 1.5

	return points
end

local function trace_pick(entity)
	if not ok(entity) then
		return true
	end

	local context = run.trace_context
	if context == nil then
		return true
	end

	if run.trace_skip and run.trace_skip[entity] then
		return false
	end

	if entity == context.viewer or entity == context.root or entity == context.vehicle or entity == context.weapon then
		return false
	end

	local owner = entity.GetOwner and entity:GetOwner() or nil
	if ok(owner) and (owner == context.viewer or owner == context.root) then
		return false
	end

	if cfg().base.ignore_player_occluders and entity:IsPlayer() then
		return false
	end

	if cfg().base.ignore_npc_occluders and (entity:IsNPC() or entity:IsNextBot()) then
		return false
	end

	return true
end

local trace_line_data = {
	start = zero_vec,
	endpos = zero_vec,
	filter = trace_pick,
	mask = mask_visual
}

local trace_hull_data = {
	start = zero_vec,
	endpos = zero_vec,
	filter = trace_pick,
	mask = mask_visual,
	mins = -vec(1, 1, 1),
	maxs = vec(1, 1, 1)
}

local function trace(start_pos, end_pos, mode, context)
	run.trace_viewer_count = run.trace_viewer_count + 1
	run.trace_global_count = run.trace_global_count + 1

	if run.trace_viewer_count > run.trace_viewer_limit or run.trace_global_count > run.trace_global_limit then
		return nil
	end

	run.trace_context = context

	if mode == "audio" then
		trace_line_data.start = start_pos
		trace_line_data.endpos = end_pos
		trace_line_data.mask = cfg().audio.mask
		return trace_line(trace_line_data)
	end

	trace_hull_data.start = start_pos
	trace_hull_data.endpos = end_pos
	trace_hull_data.mask = cfg().base.mask_visual
	trace_hull_data.mins = -cfg().base.trace_hull
	trace_hull_data.maxs = cfg().base.trace_hull

	local trace = trace_hull(trace_hull_data)
	if trace.StartSolid or trace.AllSolid then
		local direction = end_pos - start_pos
		if direction:LengthSqr() > 1 then
			direction:Normalize()
			trace_line_data.start = start_pos + direction * cfg().base.trace_start_offset
			trace_line_data.endpos = end_pos
			trace_line_data.mask = cfg().base.mask_visual
			trace = trace_line(trace_line_data)
		end
	end

	return trace
end

local function box(entity)
	local mins = entity:OBBMins()
	local maxs = entity:OBBMaxs()
	local x = math_abs(maxs.x - mins.x)
	local y = math_abs(maxs.y - mins.y)
	local z = math_abs(maxs.z - mins.z)
	local min_dim = math_min(x, math_min(y, z))
	local max_dim = math_max(x, math_max(y, z))
	return min_dim, max_dim, x * y * z
end

local function trace_info(trace)
	local entity = trace.Entity
	local surface = ""

	if surface_name and trace.SurfaceProps then
		surface = lower(surface_name(trace.SurfaceProps))
	elseif trace.SurfaceProps ~= nil then
		surface = lower(tostring(trace.SurfaceProps))
	end

	return {
		entity = entity,
		classname = lower(ok(entity) and entity.GetClass and entity:GetClass() or (trace.HitWorld and "worldspawn" or nil)),
		model = lower(ok(entity) and entity.GetModel and entity:GetModel() or nil),
		material = lower(ok(entity) and entity.GetMaterial and entity:GetMaterial() or nil),
		texture = lower(trace.HitTexture),
		surfaceprop = surface,
		name = lower(ok(entity) and entity.GetName and entity:GetName() or nil),
		hit_world = trace.HitWorld == true
	}
end

local function wall_hit(rule, info, trace, root)
	if not picked(info.classname, rule.classnames, rule.classname_patterns) then
		return false
	end

	if not picked(info.model, rule.models, rule.model_patterns) then
		return false
	end

	if not picked(info.material, rule.materials, rule.material_patterns) then
		return false
	end

	if not picked(info.surfaceprop, rule.surfaceprops, rule.surfaceprop_patterns) then
		return false
	end

	if not picked(info.texture, rule.textures, rule.texture_patterns) then
		return false
	end

	if not picked(info.name, rule.names, rule.name_patterns) then
		return false
	end

	if rule.predicate then
		local good, result = pcall(rule.predicate, trace, info, root)
		if not good or not result then
			return false
		end
	end

	return true
end

local function block_kind(trace, root)
	if not trace or not trace.Hit then
		return "clear"
	end

	local info = trace_info(trace)

	for index = 1, #run.occluder_order do
		local rule = run.occluder_order[index]
		if wall_hit(rule, info, trace, root) then
			return rule.bucket
		end
	end

	local entity = info.entity
	if ok(entity) then
		if same_root(entity, root) then
			return "ignored"
		end

		if entity.GetNoDraw and entity:GetNoDraw() then
			return "ignored"
		end

		local color = entity.GetColor and entity:GetColor() or nil
		local alpha = color and color.a or 255
		if alpha <= cfg().occluders.alpha_ignore then
			return "ignored"
		end

		if alpha < cfg().occluders.alpha_soft then
			return "soft"
		end

		local min_dim, max_dim, volume = box(entity)
		if volume <= cfg().occluders.ignored_small_volume and max_dim <= cfg().occluders.ignored_small_max then
			return "ignored"
		end

		if min_dim <= cfg().occluders.soft_thickness then
			return "soft"
		end
	end

	if has_text(info.texture, {
		"nodraw",
		"clip",
		"trigger",
		"skybox"
	}) then
		return "ignored"
	end

	if has_text(info.texture, {
		"glass",
		"grate",
		"chain",
		"fence",
		"rail",
		"bars",
		"screen",
		"mesh",
		"ladder",
		"window"
	}) or has_text(info.material, {
		"glass",
		"grate",
		"chain",
		"fence",
		"rail",
		"screen",
		"mesh",
		"window"
	}) or has_text(info.surfaceprop, {
		"glass",
		"grate",
		"chain",
		"metalgrate"
	}) then
		return "soft"
	end

	return "hard"
end

local function probe(viewer, root, start_pos, end_pos, mode, context)
	local direction = end_pos - start_pos
	local len_sqr = direction:LengthSqr()
	if len_sqr <= 1 then
		return "clear", 0
	end

	direction:Normalize()

	local max_passes = mode == "audio" and cfg().audio.trace_pass_limit or cfg().base.trace_pass_limit
	local max_ignored = mode == "audio" and cfg().audio.ignored_pass_limit or cfg().base.ignored_pass_limit
	local soft_hits = 0
	local ignored_hits = 0
	local current_start = start_pos
	run.trace_skip = {}

	for _ = 1, max_passes do
		local trace = trace(current_start, end_pos, mode, context)
		if trace == nil then
			run.trace_skip = nil
			return "unknown", soft_hits
		end

		if not trace.Hit then
			run.trace_skip = nil
			return soft_hits > 0 and "soft" or "clear", soft_hits
		end

		if ok(trace.Entity) and same_root(trace.Entity, root) then
			run.trace_skip = nil
			return soft_hits > 0 and "soft" or "clear", soft_hits
		end

		local blocker = block_kind(trace, root)
		if blocker == "ignored" then
			ignored_hits = ignored_hits + 1
			if ignored_hits > max_ignored then
				run.trace_skip = nil
				return soft_hits > 0 and "soft" or "clear", soft_hits
			end
		elseif blocker == "soft" then
			soft_hits = soft_hits + 1
			if soft_hits >= cfg().base.soft_hit_limit then
				run.trace_skip = nil
				return "hard", soft_hits
			end
		else
			run.trace_skip = nil
			return "hard", soft_hits
		end

		if ok(trace.Entity) then
			run.trace_skip[trace.Entity] = true
		end

		current_start = trace.HitPos + direction * cfg().base.trace_continue_epsilon
		if current_start:DistToSqr(end_pos) <= 16 then
			run.trace_skip = nil
			return soft_hits > 0 and "soft" or "clear", soft_hits
		end
	end

	run.trace_skip = nil
	return soft_hits > 0 and "soft" or "hard", soft_hits
end

local function guess(viewer, root, context, eye)
	if not cfg().visual.prediction then
		return false
	end

	local viewer_vel = viewer:GetVelocity()
	local target_vel = root:GetVelocity()

	if viewer_vel:LengthSqr() < (cfg().visual.prediction_min_viewer_speed * cfg().visual.prediction_min_viewer_speed)
		and target_vel:LengthSqr() < (cfg().visual.prediction_min_target_speed * cfg().visual.prediction_min_target_speed) then
		return false
	end

	local points = points(root, eye, "visual")

	for index = 1, #cfg().visual.prediction_times do
		local dt = cfg().visual.prediction_times[index]
		local next_eye = eye + viewer_vel * dt

		for pi = 1, #points do
			local next_point = root:LocalToWorld(points[pi]) + target_vel * dt

			if in_arc(next_eye, context.forward, next_point, run.dot_visual) then
				local result = probe(viewer, root, next_eye, next_point, "visual", context)
				if result == "clear" then
					return true
				end
			end
		end
	end

	return false
end

local function see(viewer, state, root, now)
	if not ok(root) or root == viewer then
		return true, "self"
	end

	if pinned(root) then
		return true, "always_visible"
	end

	if gap(viewer, root, "transmit", {}) then
		return true, "bypass"
	end

	local eye = viewer:EyePos()
	local forward = aim_dir(viewer)
	local center = root:WorldSpaceCenter()
	local dist_sqr = eye:DistToSqr(center)
	if dist_sqr > (cfg().base.radius * cfg().base.radius) then
		return false, "out_of_range"
	end

	if not in_arc(eye, forward, center, run.dot_visual) then
		return false, "out_of_fov"
	end

	if not in_pvs(viewer, root) then
		return false, "out_of_pvs"
	end

	local last = state.last_eval[root]
	if last and (now - last.time) <= cfg().base.state_reuse_interval then
		if last.eye:DistToSqr(eye) <= (cfg().base.state_reuse_eye_delta * cfg().base.state_reuse_eye_delta)
			and last.target_pos:DistToSqr(root:GetPos()) <= (cfg().base.state_reuse_target_delta * cfg().base.state_reuse_target_delta)
			and last.forward:Dot(forward) >= cfg().base.state_reuse_fwd_dot then
			return last.visible, last.reason
		end
	end

	local context = {
		viewer = viewer,
		root = root,
		vehicle = viewer:GetVehicle(),
		weapon = viewer:GetActiveWeapon(),
		forward = forward
	}

	local points = points(root, eye, "visual")
	local best = "hard"
	local tested_count = 0
	local clear_count = 0
	local need_clear = math_max(1, cfg().base.visible_min_clear_samples or 1)
	local clear_part = cfg().base.visible_min_clear_fraction or 0
	if clear_part > 0 then
		need_clear = math_max(need_clear, math_ceil(#points * clear_part))
	end

	for index = 1, #points do
		local world_point = root:LocalToWorld(points[index])
		if in_arc(eye, forward, world_point, run.dot_visual) then
			tested_count = tested_count + 1
			local result = probe(viewer, root, eye, world_point, "visual", context)
			if result == "clear" then
				clear_count = clear_count + 1
				if clear_count >= need_clear then
					state.last_eval[root] = {
						time = now,
						eye = eye,
						target_pos = root:GetPos(),
						forward = forward,
						visible = true,
						reason = "clear"
					}
					return true, "clear"
				end
			end

			if result == "soft" then
				best = "soft"
			elseif result == "unknown" and best ~= "soft" then
				best = "unknown"
			end
		end
	end

	if clear_count > 0 then
		best = "partial"
	elseif tested_count == 0 then
		best = "out_of_fov"
	end

	local visible = false
	local reason = best

	if best == "partial" then
		state.soft_since[root] = state.soft_since[root] or now
		local hold = state.visible_until[root] or 0
		if state.visible[root] == true and hold > now then
			visible = true
			reason = "partial_hold"
		end
	elseif best == "soft" then
		state.soft_since[root] = state.soft_since[root] or now
		if not cfg().visual.hide_on_soft or (now - state.soft_since[root]) < cfg().visual.soft_hide_delay then
			visible = true
			reason = "soft"
		end
	else
		state.soft_since[root] = nil
		local hold = state.visible_until[root] or 0
		if hold > now then
			visible = true
			reason = "hold"
		elseif best == "hard" and guess(viewer, root, context, eye) then
			visible = true
			reason = "predicted"
		elseif best == "unknown" then
			visible = false
			reason = "budget_hidden"
		end
	end

	state.last_eval[root] = {
		time = now,
		eye = eye,
		target_pos = root:GetPos(),
		forward = forward,
		visible = visible,
		reason = reason
	}

	return visible, reason
end

local function audio_kind_cfg(category)
	local compiled = cfg().audio.compiled or {}
	return compiled[category] or compiled.default or {}
end

local FOOTSTEP_TOKENS = {
	"footstep",
	"player/footsteps",
	"npc/foot",
	"step_"
}
local RELOAD_TOKENS = {
	"reload",
	"clipin",
	"clipout",
	"magin",
	"magout",
	"bolt",
	"deploy",
	"draw"
}
local BODY_TOKENS = {
	"cloth",
	"gear",
	"equipment",
	"foley",
	"body",
	"suit"
}
local PAIN_TOKENS = {
	"pain",
	"hurt",
	"moan",
	"grunt"
}
local DEATH_TOKENS = {
	"death",
	"die",
	"fatal"
}
local VOICE_TOKENS = {
	"vo/",
	"voice",
	"radio",
	"dialog"
}
local AMBIENCE_TOKENS = {
	"ambient",
	"idle",
	"loop",
	"engine",
	"rotor"
}

local function sound_kind(root, data)
	for index = 1, #run.sound_classifier_order do
		local entry = run.sound_classifier_order[index]
		local good, category = pcall(entry.callback, root, data)
		if good and str(category) and category ~= "" then
			return lower(category)
		end
	end

	local snd = lower(data.SoundName)
	local entity = data.Entity
	local channel = data.Channel or CHAN_AUTO

	if has_text(snd, FOOTSTEP_TOKENS) then
		return "footsteps"
	end

	if has_text(snd, RELOAD_TOKENS) then
		return "reload"
	end

	if has_text(snd, DEATH_TOKENS) then
		return "death"
	end

	if has_text(snd, PAIN_TOKENS) then
		return "pain"
	end

	if has_text(snd, BODY_TOKENS) then
		return "body"
	end

	local weapon_snd = (ok(entity) and entity.IsWeapon and entity:IsWeapon()) or channel == CHAN_WEAPON or string_find(snd, "weapons/", 1, true) ~= nil
	if weapon_snd then
		return "weapon_fire"
	end

	if root:IsNPC() or root:IsNextBot() then
		if has_text(snd, VOICE_TOKENS) then
			return "npc_voice"
		end
	end

	if root:IsPlayer() and (channel == CHAN_VOICE or has_text(snd, VOICE_TOKENS)) then
		return "player_voice"
	end

	if has_text(snd, AMBIENCE_TOKENS) then
		return "ambience"
	end

	return "default"
end

local function sound_range(snd_level)
	local audio = cfg().audio
	if not num(snd_level) then
		snd_level = 75
	end

	if snd_level <= 0 then
		return audio.max_distance
	end

	local distance = audio.reference_distance * (2 ^ ((snd_level - audio.reference_level) / audio.level_exponent))
	return math_clamp(distance, 64, audio.max_distance)
end

local function snap_pos(position)
	local quantum = cfg().audio.quantize
	if not num(quantum) or quantum <= 0 then
		return position, "0"
	end

	local qx = math.floor((position.x / quantum) + 0.5) * quantum
	local qy = math.floor((position.y / quantum) + 0.5) * quantum
	local qz = math.floor((position.z / quantum) + 0.5) * quantum

	return vec(qx, qy, qz), string_format("%d:%d:%d", qx, qy, qz)
end

local function audio_state(listener, root, position, now)
	local state = viewer_box(listener)
	local cache = state.audio_cache[root]
	local snap, key = snap_pos(position)

	if cache and cache.expire > now and cache.key == key then
		return cache.state
	end

	if gap(listener, root, "audio", {}) then
		state.audio_cache[root] = {
			key = key,
			expire = now + cfg().audio.cache_ttl,
			state = "clear"
		}
		return "clear"
	end

	local eye = listener:EyePos()
	if eye:DistToSqr(snap) > (cfg().audio.max_distance * cfg().audio.max_distance) then
		state.audio_cache[root] = {
			key = key,
			expire = now + cfg().audio.cache_ttl,
			state = "hard"
		}
		return "hard"
	end

	local context = {
		viewer = listener,
		root = root,
		vehicle = listener:GetVehicle(),
		weapon = listener:GetActiveWeapon(),
		forward = aim_dir(listener)
	}

	local points = {
		root:WorldSpaceCenter()
	}

	if root.EyePos and (root:IsPlayer() or root:IsNPC() or root:IsNextBot()) then
		local good, eye = pcall(root.EyePos, root)
		if good and eye then
			points[#points + 1] = eye
		end
	end

	local best = "hard"
	for index = 1, #points do
		local result = probe(listener, root, eye, points[index], "audio", context)
		if result == "clear" then
			best = "clear"
			break
		end

		if result == "soft" then
			best = "soft"
		elseif result == "unknown" and best ~= "soft" then
			best = "unknown"
		end
	end

	if best == "unknown" then
		best = "hard"
	end

	state.audio_cache[root] = {
		key = key,
		expire = now + cfg().audio.cache_ttl,
		state = best
	}

	return best
end

local function voice_state(listener, talker, now)
	local state = viewer_box(listener)
	local cache = state.voice_cache[talker]
	if cache and cache.expire > now then
		return cache.state
	end

	local voice_mark = audio_state(listener, talker, talker:WorldSpaceCenter(), now)
	state.voice_cache[talker] = {
		expire = now + cfg().voice.cache_ttl,
		state = voice_mark
	}
	return voice_mark
end

local function cool_heat(viewer, detection, now)
	local dt = now - (detection.last_decay or now)
	detection.last_decay = now
	if dt <= 0 then
		return
	end

	local amount = cfg().anticheat.decay_per_second * dt
	detection.total = math_max(0, (detection.total or 0) - amount)

	for reason, total in pairs(detection.reason_totals) do
		detection.reason_totals[reason] = math_max(0, total - amount)
	end

	for root, blind in pairs(detection.audio_blind_until) do
		if blind <= now or not ok(root) then
			detection.audio_blind_until[root] = nil
		end
	end

	for root, sample in pairs(detection.damage) do
		if not ok(root) or sample.expire_at <= now then
			detection.damage[root] = nil
		end
	end
end

local function punish(viewer, reason, payload)
	log(string_format("detected %s on %s", reason, ok(viewer) and viewer:Nick() or "unknown"))
	hook_run("WHK.hit", viewer, reason, payload)

	local action = action_name(cfg().anticheat.action)
	if action == "punish" then
		local callback = cfg().anticheat.punish_callback
		if func(callback) then
			pcall(callback, viewer, reason, payload)
		end
		hook_run("WHK.punish", viewer, reason, payload, action)
	elseif action == "kick" then
		hook_run("WHK.punish", viewer, reason, payload, action)
		if ok(viewer) and viewer.Kick then
			viewer:Kick("Wallhack detection: " .. reason)
		end
	end
end

function whk.mark(viewer, amount, reason, extra)
	if not (ok(viewer) and viewer:IsPlayer() and cfg().anticheat.enabled) then
		return false
	end

	local detection = heat_box(viewer)
	local now = clock()
	cool_heat(viewer, detection, now)

	if detection.report_cooldown > now then
		return false
	end

	reason = lower(reason)
	if reason == "" then
		reason = "mark"
	end

	local score = num(amount) and amount or (cfg().anticheat.reason_scores[reason] or 1)
	local cooldown = cfg().anticheat.reason_cooldowns[reason] or 0

	if (detection.reason_stamp[reason] or 0) > now then
		return false
	end

	detection.reason_stamp[reason] = now + cooldown
	detection.total = (detection.total or 0) + score
	detection.reason_totals[reason] = (detection.reason_totals[reason] or 0) + score

	local threshold = cfg().anticheat.reason_thresholds[reason] or cfg().anticheat.global_threshold
	if detection.total >= cfg().anticheat.global_threshold or detection.reason_totals[reason] >= threshold then
		detection.report_cooldown = now + cfg().anticheat.cooldown
		local payload = {
			reason = reason,
			score = score,
			total = detection.total,
			reason_total = detection.reason_totals[reason],
			data = extra or {}
		}
		punish(viewer, reason, payload)
		return true
	end

	return false
end

local function ac_step(viewer, state, now)
	if not cfg().anticheat.enabled then
		return
	end

	if gap(viewer, viewer, "anticheat", {}) then
		return
	end

	local detection = heat_box(viewer)
	cool_heat(viewer, detection, now)

	if detection.report_cooldown > now then
		return
	end

	local eye = viewer:EyePos()
	local forward = aim_dir(viewer)
	local max_range_sqr = cfg().anticheat.max_range * cfg().anticheat.max_range
	local inspected = 0

	for index = 1, #state.candidates do
		local root = state.candidates[index]
		if inspected >= cfg().anticheat.scan_limit then
			break
		end

		if ok(root) and root ~= viewer and state.visible[root] == false then
			local occlusion = state.occlusion[root]
			if not cfg().anticheat.hard_hidden_only or hard_mark(occlusion) then
				local target_pos = root:WorldSpaceCenter()
				local dist_sqr = eye:DistToSqr(target_pos)
				if dist_sqr <= max_range_sqr then
					local delta = target_pos - eye
					local len = delta:LengthSqr()
					if len > 1 then
						local dot = forward:Dot(delta) / math_sqrt(len)
						local tracking = detection.tracking[root] or {
							aim = 0,
							track = 0,
							last = now
						}
						local dt = now - (tracking.last or now)
						tracking.last = now

						if dot >= run.dot_aim then
							tracking.aim = tracking.aim + dt
						else
							tracking.aim = math_max(0, tracking.aim - dt * 2)
						end

						if dot >= run.dot_track then
							tracking.track = tracking.track + dt
						else
							tracking.track = math_max(0, tracking.track - dt)
						end

						if tracking.aim >= cfg().anticheat.aim_window then
							tracking.aim = 0
							whk.mark(viewer, nil, "aim_hidden", {
								target = root
							})
						end

						if tracking.track >= cfg().anticheat.track_window then
							tracking.track = 0
							local reason = detection.audio_blind_until[root] and detection.audio_blind_until[root] > now and "suspicious_audio_tracking" or "repeated_tracking_hidden"
							whk.mark(viewer, nil, reason, {
								target = root
							})
						end

						detection.tracking[root] = tracking
						inspected = inspected + 1
					end
				end
			end
		end
	end
end

local function candidates(viewer, state, now)
	state.next_candidate_refresh = now + cfg().base.candidate_refresh

	for root in pairs(state.candidate_set) do
		state.candidate_set[root] = nil
	end

	local eye = viewer:EyePos()
	local forward = aim_dir(viewer)
	local radius_sqr = cfg().base.radius * cfg().base.radius
	local limit = cfg().base.candidate_limit
	local write = 1

	for index = 1, #run.managed_list do
		local root = run.managed_list[index]
		if ok(root) and root ~= viewer then
			if managed_root(root) then
				if gap(viewer, root, "transmit", {}) then
					push_vis(viewer, state, root, true, "bypass", now)
				else
					local center = root:WorldSpaceCenter()
					if eye:DistToSqr(center) <= radius_sqr and in_arc(eye, forward, center, run.dot_candidate) and in_pvs(viewer, root) then
						state.candidates[write] = root
						state.candidate_set[root] = true
						write = write + 1
						if (write - 1) >= limit then
							break
						end
					end
				end
			else
				drop_root(root)
			end
		end
	end

	for index = write, #state.candidates do
		state.candidates[index] = nil
	end

	for root in pairs(state.visible) do
		if not state.candidate_set[root] and ok(root) and root ~= viewer and not gap(viewer, root, "transmit", {}) then
			if state.visible[root] == true then
				push_vis(viewer, state, root, false, "candidate_outside", now)
			elseif state.visible[root] ~= false then
				push_root(root, viewer, state, "candidate_outside", now)
			end
		end
	end

	state.candidate_cursor = 1
end

local function prime(viewer, delay)
	if not (ok(viewer) and viewer:IsPlayer()) then
		return
	end

	if not cfg().base.enabled then
		return
	end

	local state = viewer_box(viewer)
	local now = clock()
	state.join_lock = now + (num(delay) and delay or cfg().base.join_lock)

	for index = 1, #run.managed_list do
		local root = run.managed_list[index]
		if ok(root) and root ~= viewer and not allowed(viewer, root, root) then
			state.visible[root] = false
			state.occlusion[root] = "join_lock"
			block_group(root, viewer, true, state)
		end
	end

	timer_later(0, function()
		if not (ok(viewer) and viewer:IsPlayer()) then
			return
		end

		local state_now = viewer_box(viewer)
		candidates(viewer, state_now, clock())
	end)
end

local function tick_viewer(viewer, state, now, force_all)
	if not (ok(viewer) and viewer:IsPlayer()) then
		return
	end

	if not cfg().base.enabled then
		return
	end

	if state.join_lock > now then
		return
	end

	guard_viewer(viewer, state, now)

	if state.next_candidate_refresh <= now or force_all then
		candidates(viewer, state, now)
	end

	local candidate_count = #state.candidates
	if candidate_count == 0 then
		return
	end

	run.trace_viewer_count = 0
	run.trace_viewer_limit = cfg().base.trace_budget_per_viewer * (force_all and 2 or 1)

	local limit = force_all and candidate_count or cfg().base.update_limit_per_viewer
	local cursor = state.candidate_cursor
	local processed = 0

	while processed < limit and candidate_count > 0 do
		if cursor > candidate_count then
			cursor = 1
		end

		local root = state.candidates[cursor]
		cursor = cursor + 1
		processed = processed + 1

		if ok(root) and root ~= viewer and managed_root(root) then
			local visible, reason = see(viewer, state, root, now)
			push_vis(viewer, state, root, visible, reason, now)
		elseif root then
			state.candidate_set[root] = nil
			state.visible[root] = nil
			state.occlusion[root] = nil
		end

		if run.trace_global_count >= run.trace_global_limit then
			break
		end
	end

	state.candidate_cursor = cursor
	ac_step(viewer, state, now)
end

local function refresh_viewer(viewer)
	if not (ok(viewer) and viewer:IsPlayer()) then
		return
	end

	local state = viewer_box(viewer)
	state.join_lock = 0
	candidates(viewer, state, clock())
	tick_viewer(viewer, state, clock(), true)
end

function whk.refresh(viewer)
	if ok(viewer) then
		refresh_viewer(viewer)
		return true
	end

	local players = players_all()
	for index = 1, #players do
		refresh_viewer(players[index])
	end

	return true
end

function whk.managed(entity)
	entity = root_of(entity)
	return ok(entity) and managed_root(entity) or false
end

function whk.view(viewer, entity)
	if not (ok(viewer) and ok(entity)) then
		return nil
	end

	local state = run.viewer_states[viewer]
	entity = root_of(entity)
	if not (state and ok(entity)) then
		return nil
	end

	return {
		visible = state.visible[entity] == true,
		occlusion = state.occlusion[entity] or "unknown"
	}
end

local function transmit(entity, viewer)
	if not cfg().base.enabled then
		return
	end

	if not (ok(entity) and ok(viewer) and viewer:IsPlayer()) then
		return
	end

	local root = root_of(entity)
	if not ok(root) or root == viewer then
		return
	end

	if allowed(viewer, entity, root) or not managed_root(root) then
		return
	end

	local state = viewer_box(viewer)
	if state.join_lock > clock() then
		return TRANSMIT_NEVER
	end

	if state.visible[root] == true then
		return
	end

	return TRANSMIT_NEVER
end

local redirecting_sound = false

local function sound_hook(data)
	if redirecting_sound or not cfg().base.enabled or not cfg().audio.enabled or not data then -- рекурсия
		return
	end

	local entity = data.Entity
	if not ok(entity) or (entity.IsWorld and entity:IsWorld()) then
		return
	end

	local root = root_of(entity)
	if not ok(root) or not managed_root(root) or pinned(root) then
		return
	end

	local category = sound_kind(root, data)
	local kind_cfg = audio_kind_cfg(category)
	if kind_cfg.enabled == false then
		return
	end

	local snd = data.SoundName
	if not str(snd) or snd == "" then
		return
	end

	local now = clock()
	local position = data.Pos or data.Position or root:WorldSpaceCenter()
	local distance = sound_range(data.SoundLevel or 75)
	local clear_filter = RecipientFilter()
	local soft_filter = RecipientFilter()
	local hard_filter = RecipientFilter()
	local clear_count = 0
	local soft_count = 0
	local hard_count = 0
	local filtered = false
	local players = players_all()

	for index = 1, #players do
		local listener = players[index]
		if ok(listener) and listener:IsPlayer() then
			if listener == root or gap(listener, root, "audio", {
				category = category
			}) then
				clear_filter:AddPlayer(listener)
				clear_count = clear_count + 1
			else
				local state = viewer_box(listener)
				local hear_state = state.join_lock > now and "hard" or audio_state(listener, root, position, now)
				local reach = distance * (kind_cfg.max_distance_scale or 1)
				if listener:EyePos():DistToSqr(position) <= (reach * reach) then
					if hear_state == "clear" or kind_cfg[hear_state] == "allow" then
						clear_filter:AddPlayer(listener)
						clear_count = clear_count + 1
					elseif kind_cfg[hear_state] == "attenuate" then
						if hear_state == "soft" then
							soft_filter:AddPlayer(listener)
							soft_count = soft_count + 1
						else
							hard_filter:AddPlayer(listener)
							hard_count = hard_count + 1
						end
						filtered = true
					else
						filtered = true
						if hear_state == "hard" and cfg().anticheat.enabled then
							local detection = heat_box(listener)
							detection.audio_blind_until[root] = now + cfg().anticheat.audio_blind_window
						end
					end
				end
			end
		end
	end

	if not filtered and hard_count == 0 and soft_count == 0 then
		return
	end

	local ent_index = ok(entity) and entity:EntIndex() or 0
	local channel = data.Channel or CHAN_AUTO
	local volume = data.Volume or 1
	local snd_level = data.SoundLevel or 75
	local flags = data.Flags or 0
	local pitch = data.Pitch or 100
	local dsp = data.DSP or 0

	redirecting_sound = true

	local success, err = pcall(function()
		if clear_count > 0 then
			EmitSound(snd, position, ent_index, channel, volume, snd_level, flags, pitch, dsp, clear_filter) -- 29 april
		end

		if soft_count > 0 then
			EmitSound(
				snd,
				position,
				ent_index,
				channel,
				volume * (kind_cfg.soft_volume_scale or 1),
				math_max(0, math_floor(snd_level * (kind_cfg.soft_level_scale or 1))),
				flags,
				pitch,
				dsp,
				soft_filter
			)
		end

		if hard_count > 0 then
			EmitSound(
				snd,
				position,
				ent_index,
				channel,
				volume * (kind_cfg.hard_volume_scale or 1),
				math_max(0, math_floor(snd_level * (kind_cfg.hard_level_scale or 1))),
				flags,
				pitch,
				dsp,
				hard_filter
			)
		end
	end)

	redirecting_sound = false
	if not success then
		err_stack("wallhackkiller sound: " .. tostring(err) .. "\n")
	end

	return false
end

local function voice_hook(listener, talker)
	if not cfg().base.enabled or not cfg().voice.enabled then
		return
	end

	if not (ok(listener) and ok(talker) and listener:IsPlayer() and talker:IsPlayer()) or listener == talker then
		return
	end

	local root = root_of(talker)
	if not ok(root) or not managed_root(root) or pinned(root) then
		return
	end

	if gap(listener, root, "voice", {}) then
		return true, cfg().voice.use3d
	end

	local now = clock()
	local state = viewer_box(listener)
	local voice_mark = state.join_lock > now and "hard" or voice_state(listener, root, now)

	if listener:EyePos():DistToSqr(root:WorldSpaceCenter()) > (cfg().voice.radius * cfg().voice.radius) then
		return false, false
	end

	if voice_mark == "hard" and cfg().voice.hard == "mute" then
		return false, false
	end

	if voice_mark == "soft" and cfg().voice.soft == "mute" then
		return false, false
	end

	return true, cfg().voice.use3d
end

local function damage_hook(target, dmg)
	if not cfg().base.enabled or not cfg().anticheat.enabled or not ok(target) or not dmg then
		return
	end

	local attacker = dmg.GetAttacker and dmg:GetAttacker() or nil
	if not (ok(attacker) and attacker:IsPlayer()) or attacker == target then
		return
	end

	local root = root_of(target)
	if not ok(root) or root == attacker or not managed_root(root) or pinned(root) then
		return
	end

	if gap(attacker, root, "anticheat", {}) then
		return
	end

	local state = run.viewer_states[attacker]
	if state == nil or state.visible[root] == true then
		return
	end

	local last = state.last_eval[root]
	if last == nil or (clock() - last.time) > 0.60 then
		return
	end

	if cfg().anticheat.hard_hidden_only and not hard_mark(state.occlusion[root]) then
		return
	end

	local detection = heat_box(attacker)
	local now = clock()
	cool_heat(attacker, detection, now)

	local sample = detection.damage[root] or {
		count = 0,
		expire_at = now + 1.0
	}
	sample.count = sample.count + 1
	sample.expire_at = now + 1.0
	detection.damage[root] = sample

	if sample.count >= cfg().anticheat.damage_hidden_hits then
		sample.count = 0
		whk.mark(attacker, nil, "damage_hidden", {
			target = root,
			damage = dmg.GetDamage and dmg:GetDamage() or 0
		})
	end
end

local function wrap_gm(name, replacement)
	local gamemode = GAMEMODE
	if not gamemode then
		return
	end

	local current = gamemode[name]
	local wrapped = whk._gm_wrapped[name]
	if current == replacement and wrapped then
		return
	end

	whk._gm_wrapped[name] = whk._gm_wrapped[name] or {}
	if current ~= replacement then
		whk._gm_wrapped[name].old = current
		gamemode[name] = replacement
	end
end

local function gm_transmit(_, entity, viewer)
	local wrapped = whk._gm_wrapped.EntityShouldTransmit
	local old = wrapped and wrapped.old or nil
	if old and old ~= gm_transmit then
		local good, result = pcall(old, GAMEMODE, entity, viewer)
		if good and result == TRANSMIT_NEVER then
			return result
		end
	end

	return transmit(entity, viewer)
end

local function gm_voice(_, listener, talker)
	local wrapped = whk._gm_wrapped.PlayerCanHearPlayersVoice
	local old = wrapped and wrapped.old or nil
	if old and old ~= gm_voice then
		local good, hear, in3d = pcall(old, GAMEMODE, listener, talker)
		if good and hear == false then
			return hear, in3d
		end
	end

	return voice_hook(listener, talker)
end

local function clear_hooks()
	local hooks = hook_table()
	if not hooks then
		return
	end

	for ev, ev_hooks in pairs(hooks) do
		for hook_id in pairs(ev_hooks) do
			if str(hook_id) and string_find(hook_id, "WallHackKiller", 1, true) then
				hook_drop(ev, hook_id)
			end
		end
	end
end

local function hooks()
	local hook_list = hook_table()
	if not hook_list then
		return
	end

	wrap_gm("EntityShouldTransmit", gm_transmit)
	wrap_gm("PlayerCanHearPlayersVoice", gm_voice)

	hook_add("EntityShouldTransmit", prefix .. "transmit", transmit)
	hook_add("EntityEmitSound", prefix .. "sound", sound_hook)
	hook_add("PlayerCanHearPlayersVoice", prefix .. "voice", voice_hook)
	hook_add("EntityTakeDamage", prefix .. "damage", damage_hook)
	hook_add("Tick", prefix .. "tick", function()
		local good, err = pcall(function()
			local now = clock()
			if now < run.next_step then
				return
			end

			run.next_step = now + math_max(engine_tick(), cfg().base.tick_interval)
			run.trace_global_count = 0
			run.trace_global_limit = cfg().base.trace_budget_global

			local players = players_all()
			local count = #players
			if count == 0 or not cfg().base.enabled then
				return
			end

			local viewer_batch = math_ceil(count * cfg().base.tick_interval / cfg().base.viewer_window)
			viewer_batch = math_clamp(viewer_batch, cfg().base.viewers_per_step_min, cfg().base.viewers_per_step_max)

			local cursor = run.viewer_cursor
			for _ = 1, viewer_batch do
				if count == 0 then
					break
				end

				if cursor > count then
					cursor = 1
				end

				local viewer = players[cursor]
				cursor = cursor + 1

				if ok(viewer) and viewer:IsPlayer() then
					tick_viewer(viewer, viewer_box(viewer), now, false)
				end

				if run.trace_global_count >= run.trace_global_limit then
					break
				end
			end

			run.viewer_cursor = cursor
		end)

		if not good then
			local now = clock()
			if (now - run.last_error) > 1.0 then
				run.last_error = now
				err_stack("WallHackKiller: " .. tostring(err) .. "\n")
			end
		end
	end)
	hook_add("OnEntityCreated", prefix .. "create", function(entity)
		timer_later(0, function()
			if not ok(entity) then
				return
			end

			local root = touch_root(entity)
			if ok(root) and managed_root(root) and push_roots then
				push_roots(root, "entity_created")
			end
		end)
	end)
	hook_add("EntityRemoved", prefix .. "remove", function(entity)
		local root = root_of(entity)
		if ok(root) then
			if root == entity then
				drop_root(root)
			else
				touch_root(root)
			end
		end

		for viewer, state in pairs(run.viewer_states) do
			if state then
				clear_group(viewer, state, entity)
				state.visible[entity] = nil
				state.occlusion[entity] = nil
				state.visible_until[entity] = nil
				state.soft_since[entity] = nil
				state.last_eval[entity] = nil
				state.audio_cache[entity] = nil
				state.voice_cache[entity] = nil
			end
		end
	end)
	hook_add("PlayerInitialSpawn", prefix .. "join", function(viewer)
		prime(viewer, cfg().base.join_lock)
	end)
	hook_add("PlayerAuthed", prefix .. "auth", function(viewer)
		prime(viewer, cfg().base.join_lock)
	end)
	hook_add("PlayerSpawn", prefix .. "spawn", function(viewer)
		prime(viewer, cfg().base.respawn_lock)
		timer_later(cfg().base.respawn_lock, function()
			if ok(viewer) then
				refresh_viewer(viewer)
			end
		end)
	end)
	hook_add("PlayerEnteredVehicle", prefix .. "veh_in", function(viewer)
		refresh_viewer(viewer)
	end)
	hook_add("PlayerLeaveVehicle", prefix .. "veh_out", function(viewer)
		refresh_viewer(viewer)
	end)
	hook_add("PlayerDisconnected", prefix .. "left", function(viewer)
		clear_viewer(viewer)
	end)
	hook_add("PostCleanupMap", prefix .. "map", function()
		timer_later(0, function()
			sync_lists()
			for index = 1, #players_all() do
				local viewer = players_all()[index]
				prime(viewer, cfg().base.join_lock)
			end
		end)
	end)
end

local free_all

local function seed()
	run.managed_set = {}
	run.managed_list = {}

	local entities = ents_all()
	for index = 1, #entities do
		touch_root(entities[index])
	end

	local players = players_all()
	for index = 1, #players do
		touch_root(players[index])
	end

	sync_lists()
end

local function watch()
	local now = clock()
	if now < run.next_watchdog then
		return
	end

	run.next_watchdog = now + 1.25

	local profile = lower(cvar_profile and cvar_profile:GetString() or whk.profile_name)
	local debug_value = cvar_debug and cvar_debug:GetBool() or false
	local action_value = cvar_ac_action and lower(cvar_ac_action:GetString()) or "hook"
	local enabled_value = not cvar_enabled or cvar_enabled:GetBool() -- off whk fix

	if profile ~= run.last_profile or debug_value ~= run.last_debug or action_value ~= run.last_action or enabled_value ~= run.last_enabled then
		make_config()
		run.last_profile = profile
		run.last_debug = debug_value
		run.last_action = action_value
		run.last_enabled = enabled_value
		whk.reset("watch")
		dbg("watch rebuild: " .. profile_line())
	end

	sync_lists()
	hooks()
end

function whk.reset(reason)
	if not cfg().base.enabled then
		if free_all then
			free_all()
		end
		run.viewer_states = setmetatable({}, { __mode = "k" })
		run.detection = setmetatable({}, { __mode = "k" })
		dbg("reinitialized in disabled mode: " .. tostring(reason or "manual"))
		return
	end

	if free_all then
		free_all()
	end

	seed()
	local players = players_all()
	for index = 1, #players do
		local viewer = players[index]
		prime(viewer, cfg().base.join_lock)
		timer_later(cfg().base.join_lock, function()
			if ok(viewer) then
				refresh_viewer(viewer)
			end
		end)
	end
	dbg("reinitialized: " .. tostring(reason or "manual"))
end

con_add("whk_rebuild", function()
	whk.reset("console")
end)

con_add("whk_profile_set", function(_, _, args)
	if args[1] then
		whk.profile(args[1])
	end
end)

free_all = function()
	local viewers = players_all()
	local entities = ents_all()

	for vi = 1, #viewers do
		local viewer = viewers[vi]
		if ok(viewer) then
			for ent_index = 1, #entities do
				local entity = entities[ent_index]
				if ok(entity) then
					entity:SetPreventTransmit(viewer, false)
				end
			end
		end
	end
end

local function stop(reason)
	hook_drop("EntityShouldTransmit", prefix .. "transmit")
	hook_drop("EntityEmitSound", prefix .. "sound")
	hook_drop("PlayerCanHearPlayersVoice", prefix .. "voice")
	hook_drop("EntityTakeDamage", prefix .. "damage")
	hook_drop("Tick", prefix .. "tick")
	hook_drop("OnEntityCreated", prefix .. "create")
	hook_drop("EntityRemoved", prefix .. "remove")
	hook_drop("PlayerInitialSpawn", prefix .. "join")
	hook_drop("PlayerAuthed", prefix .. "auth")
	hook_drop("PlayerSpawn", prefix .. "spawn")
	hook_drop("PlayerEnteredVehicle", prefix .. "veh_in")
	hook_drop("PlayerLeaveVehicle", prefix .. "veh_out")
	hook_drop("PlayerDisconnected", prefix .. "left")
	hook_drop("PostCleanupMap", prefix .. "map")
	timer_drop(prefix .. "watch")

	local gamemode = GAMEMODE
	if gamemode and whk._gm_wrapped then
		local old_transmit = whk._gm_wrapped.EntityShouldTransmit
		if old_transmit and gamemode.EntityShouldTransmit == gm_transmit then
			gamemode.EntityShouldTransmit = old_transmit.old
		end

		local old_voice = whk._gm_wrapped.PlayerCanHearPlayersVoice
		if old_voice and gamemode.PlayerCanHearPlayersVoice == gm_voice then
			gamemode.PlayerCanHearPlayersVoice = old_voice.old
		end
	end

	whk._gm_wrapped = {}

	if reason == "reload" then
		free_all()
	end
end

whk._runtime_cleanup = stop
whk.stop = stop

clear_hooks()
make_config()
run.last_profile = whk.profile_name
run.last_debug = debug_on()
run.last_action = cfg().anticheat.action
run.last_enabled = cfg().base.enabled
stock_walls()
seed()
hooks()

timer_make(prefix .. "watch", 1.25, 0, function()
	local good, err = pcall(watch)
	if not good then
		err_stack("WallHackKiller watch: " .. tostring(err) .. "\n")
	end
end)

timer_later(0, function()
	whk.reset("startup")
end)

dbg("loaded " .. profile_line())
