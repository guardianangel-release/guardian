local ffi = require "ffi"
local base64 = require "gamesense/base64"
local json = require "json"
local vector = require "vector"
local c_entity = require "gamesense/entity"

-- ===========================
-- FFI DEFINITIONS
-- ===========================
ffi.cdef[[
    typedef struct {
        float x;
        float y;
        float z;
    } vec3_t;

    typedef struct {
        float   m_anim_time;
        float   m_fade_out_time;
        int     m_flags;
        int     m_activity;
        int     m_priority;
        int     m_order;
        int     m_sequence;
        float   m_prev_cycle;
        float   m_weight;
        float   m_weight_delta_rate;
        float   m_playback_rate;
        float   m_cycle;
        void*   m_owner;
        int     m_bits;
    } C_AnimationLayer;

    typedef struct {
        char        pad0[0x60];
        void*       pEntity;
        void*       pActiveWeapon;
        void*       pLastActiveWeapon;
        float       flLastUpdateTime;
        int         iLastUpdateFrame;
        float       flLastUpdateIncrement;
        float       flEyeYaw;
        float       flEyePitch;
        float       flGoalFeetYaw;
        float       flLastFeetYaw;
        float       flMoveYaw;
        float       flLastMoveYaw;
        float       flLeanAmount;
        char        pad1[0x4];
        float       flFeetCycle;
        float       flMoveWeight;
        float       flMoveWeightSmoothed;
        float       flDuckAmount;
        float       flHitGroundCycle;
        float       flRecrouchWeight;
        vec3_t      vecOrigin;
        vec3_t      vecLastOrigin;
        vec3_t      vecVelocity;
        vec3_t      vecVelocityNormalized;
        vec3_t      vecVelocityNormalizedNonZero;
        float       flVelocityLenght2D;
        float       flJumpFallVelocity;
        float       flSpeedNormalized;
        float       flRunningSpeed;
        float       flDuckingSpeed;
        float       flDurationMoving;
        float       flDurationStill;
        bool        bOnGround;
        bool        bHitGroundAnimation;
        char        pad2[0x2];
        float       flNextLowerBodyYawUpdateTime;
        float       flDurationInAir;
        float       flLeftGroundHeight;
        float       flHitGroundWeight;
        float       flWalkToRunTransition;
        char        pad3[0x4];
        float       flAffectedFraction;
        char        pad4[0x208];
        char        pad_extra[0x4];
        float       flMinBodyYaw;
        float       flMaxBodyYaw;
        float       flMinPitch;
        float       flMaxPitch;
        int         iAnimsetVersion;
    } CCSGOPlayerAnimationState_t;

    typedef void*(__thiscall* get_client_entity_t)(void*, int);
]]

-- ===========================
-- UTILITY FUNCTIONS
-- ===========================
local clipboard_util = (function()
    local M = {}
    local native_GetClipboardTextCount = vtable_bind("vgui2.dll", "VGUI_System010", 7, "int(__thiscall*)(void*)")
    local native_SetClipboardText = vtable_bind("vgui2.dll", "VGUI_System010", 9, "void(__thiscall*)(void*, const char*, int)")
    local native_GetClipboardText = vtable_bind("vgui2.dll", "VGUI_System010", 11, "int(__thiscall*)(void*, int, const char*, int)")
    
    function M.set(text)
        text = tostring(text)
        native_SetClipboardText(text, string.len(text))
    end
    
    function M.get()
        local len = native_GetClipboardTextCount()
        if len > 0 then
            local char_arr = ffi.new("char[?]", len)
            native_GetClipboardText(0, char_arr, len)
            return ffi.string(char_arr, len-1)
        end
    end
    
    return M
end)()

local function contains(tbl, val)
    if not tbl or type(tbl) ~= "table" then return false end
    for i=1, #tbl do
        if tbl[i] == val then return true end
    end
    return false
end

local function safe_get_multiselect(element)
    local result = ui.get(element)
    if type(result) ~= "table" then
        return {}
    end
    return result
end

local function clamp(val, min, max)
    if val < min then return min end
    if val > max then return max end
    return val
end

local function normalize_angle(angle)
    while angle > 180 do angle = angle - 360 end
    while angle < -180 do angle = angle + 360 end
    return angle
end

local function angle_diff(a, b)
    local diff = normalize_angle(a - b)
    return diff
end

-- Circular buffer for efficient history tracking
local function create_circular_buffer(size)
    return {
        data = {},
        index = 1,
        size = size,
        max_index = 0,
        
        push = function(self, value)
            self.data[self.index] = value
            self.index = (self.index % self.size) + 1
            self.max_index = math.min(self.max_index + 1, self.size)
        end,
        
        get = function(self, offset)
            if offset >= self.max_index then return nil end
            local idx = ((self.index - 1 - offset + self.size) % self.size) + 1
            return self.data[idx]
        end,
        
        get_all = function(self)
            local result = {}
            for i = 0, self.max_index - 1 do
                table.insert(result, self:get(i))
            end
            return result
        end,
        
        clear = function(self)
            self.data = {}
            self.index = 1
            self.max_index = 0
        end
    }
end

-- ===========================
-- ENTITY PROPERTY CACHING
-- ===========================
local entity_cache = {}
local entity_cache_time = {}
local ENTITY_CACHE_TICKS = 1

local function get_cached_prop(ent, prop, default)
    local key = ent .. "_" .. prop
    local tick = globals.tickcount()
    
    if entity_cache[key] and (tick - (entity_cache_time[key] or 0)) < ENTITY_CACHE_TICKS then
        return entity_cache[key]
    end
    
    local value = entity.get_prop(ent, prop)
    if value == nil then value = default end
    
    entity_cache[key] = value
    entity_cache_time[key] = tick
    return value
end

-- ===========================
-- UTILITIES MODULE
-- ===========================
local utils = {
    safe_get_multiselect = function(element)
        local result = ui.get(element)
        return type(result) == "table" and result or {}
    end,
    
    safe_get_prop = function(ent, prop, default)
        local value = entity.get_prop(ent, prop)
        return value ~= nil and value or default
    end,
    
    safe_call = function(func, ...)
        local success, result = pcall(func, ...)
        if not success then
            if ui.get(ui_elements.console_log) then
                client.log("Error in safe_call: " .. tostring(result))
            end
            return nil
        end
        return result
    end
}

-- === Choke helper (no m_flOldSimulationTime needed) ===
local prev_simtime = {}

local function get_choke_from_simtime(player)
    local sim = entity.get_prop(player, "m_flSimulationTime")
    if not sim then return 0 end

    local last = prev_simtime[player]
    prev_simtime[player] = sim

    if not last then return 0 end
    local dt = sim - last
    if dt <= 0 then return 0 end

    local choke = math.floor(dt / globals.tickinterval())
    if choke < 0 then choke = 0 end
    return choke
end

client.set_event_callback("round_start", function()
    prev_simtime = {}
end)


local function get_player_speed_cached(player)
    local tick = globals.tickcount()
    
    -- invalidate cache on fakelag
    local choke = get_choke_from_simtime(player)
    if choke > 5 then
        speed_cache[player] = nil  -- Force recalculation
    end

    
    if speed_cache[player] and (tick - (speed_cache_time[player] or 0)) < CACHE_DURATION then
        return speed_cache[player]
    end
    
    local vx, vy = get_cached_prop(player, "m_vecVelocity", 0)
    local speed = (vx and vy) and math.sqrt(vx*vx + vy*vy) or 0
    
    speed_cache[player] = speed
    speed_cache_time[player] = tick
    return speed
end



-- ===========================
-- ADVANCED MATH FUNCTIONS
-- ===========================
local function calculate_angle_stats(angles)
    if #angles == 0 then return 0, 0 end
    
    local sum = 0
    for i = 1, #angles do
        sum = sum + angles[i]
    end
    local mean = sum / #angles
    
    local variance_sum = 0
    for i = 1, #angles do
        variance_sum = variance_sum + (angles[i] - mean) ^ 2
    end
    local variance = variance_sum / #angles
    local std_dev = math.sqrt(variance)
    
    return mean, std_dev
end

local function calculate_variance(angles, mean)
    if #angles == 0 then return 0 end
    
    local variance_sum = 0
    for i = 1, #angles do
        variance_sum = variance_sum + (angles[i] - mean) ^ 2
    end
    return variance_sum / #angles
end

local function detect_oscillation(angles, cycle_length)
    if #angles < cycle_length * 2 then return false end
    if cycle_length > 16 then return false end
    
    local patterns = {}
    for i = 1, #angles - cycle_length + 1 do
        local pattern = {}
        for j = 0, cycle_length - 1 do
            table.insert(pattern, angles[i + j])
        end
        table.insert(patterns, pattern)
    end
    
    -- Check for repeating patterns
    for i = 1, #patterns - 1 do
        local match = true
        for j = 1, cycle_length do
            if math.abs(patterns[i][j] - patterns[i + 1][j]) > 5 then
                match = false
                break
            end
        end
        if match then return true end
    end
    
    return false
end

local function detect_consistent_side(angles, min_ticks)
    if #angles < min_ticks then return 0 end
    
    local positive_count = 0
    local negative_count = 0
    
    for i = 1, min_ticks do
        if angles[i] > 0 then
            positive_count = positive_count + 1
        elseif angles[i] < 0 then
            negative_count = negative_count + 1
        end
    end
    
    if positive_count >= min_ticks * 0.8 then
        return 1
    elseif negative_count >= min_ticks * 0.8 then
        return -1
    end
    
    return 0
end

-- ===========================
-- ENHANCED WEAPON TYPE DETECTION FOR HVH
-- ===========================
local function get_weapon_type(weapon_ent)
    if not weapon_ent then return "unknown" end
    
    local weapon_id = entity.get_prop(weapon_ent, "m_iItemDefinitionIndex")
    if not weapon_id then return "unknown" end
    
    -- HVH Primary Weapons
    if weapon_id == 9 then return "awp" end                    -- AWP
    if weapon_id == 40 then return "scout" end                 -- Scout/SSG
    if weapon_id == 11 or weapon_id == 38 then return "auto" end -- Auto Snipers (G3SG1/SCAR-20)
    
    -- HVH Pistols
    if weapon_id == 1 then return "deagle" end                 -- Deagle
    if weapon_id == 64 then return "revolver" end              -- R8 Revolver
    if weapon_id == 2 or weapon_id == 3 or weapon_id == 4 or weapon_id == 30 or 
       weapon_id == 32 or weapon_id == 36 or weapon_id == 61 or weapon_id == 63 then
        return "pistol"                                        -- All other pistols
    end
    
    -- Rifles (less common in HVH but still used)
    if weapon_id == 7 or weapon_id == 8 or weapon_id == 10 or weapon_id == 13 or 
       weapon_id == 16 or weapon_id == 39 or weapon_id == 60 then
        return "rifle"
    end
    
    -- SMGs (rare in HVH but possible)
    if weapon_id == 17 or weapon_id == 19 or weapon_id == 24 or weapon_id == 26 or 
       weapon_id == 33 or weapon_id == 34 then
        return "smg"
    end
    
    return "unknown"
end

-- ===========================
-- GAME STATE DETECTION
-- ===========================
local function count_teammates(player)
    local teammates = entity.get_players(false)
    return teammates and #teammates or 0
end

local function count_enemies(player)
    local enemies = entity.get_players(true)
    return enemies and #enemies or 0
end

-- Robust site resolver using PlayerResource bombsite centers
local function get_nearest_site(x, y, z)
    local pr = entity.get_player_resource()
    if not pr then return nil end

    local ax, ay, az = entity.get_prop(pr, "m_bombsiteCenterA")
    local bx, by, bz = entity.get_prop(pr, "m_bombsiteCenterB")
    if not ax or not bx then return nil end

    local dA = (x-ax)^2 + (y-ay)^2 + (z-az)^2
    local dB = (x-bx)^2 + (y-by)^2 + (z-bz)^2
    return (dA < dB) and "A" or "B"
end


local function get_bomb_site(player)
    -- Prefer planted bomb position; fallback to local player position
    local x, y, z
    local bomb = entity.get_all("CPlantedC4")[1]
    if bomb then
        x, y, z = entity.get_prop(bomb, "m_vecOrigin")
    else
        local lp = entity.get_local_player()
        if lp then
            x, y, z = entity.get_prop(lp, "m_vecOrigin")
        end
    end

    if not x or not y or not z then
        return "unknown"
    end

    return get_nearest_site(x, y, z) or "unknown"
end


-- ===========================
-- ENTITY HELPERS
-- ===========================
local entity_list = ffi.cast("void***", client.create_interface("client.dll", "VClientEntityList003"))
local get_client_entity = ffi.cast("get_client_entity_t", entity_list[0][3])

local function get_entity_address(index)
    return get_client_entity(entity_list, index)
end

local function get_anim_state(entity_ptr)
    if not entity_ptr then return nil end
    return ffi.cast("CCSGOPlayerAnimationState_t**", ffi.cast("uintptr_t", entity_ptr) + 0x9960)[0]
end

local function get_anim_layers(entity_ptr)
    if not entity_ptr then return nil end
    return ffi.cast("C_AnimationLayer**", ffi.cast("uintptr_t", entity_ptr) + 0x2990)[0]
end

-- ===========================
-- UI ELEMENTS
-- ===========================
local ui_elements = {
    enable = ui.new_checkbox("RAGE", "Other", "Guardian Resolver"),
    mode = ui.new_combobox("RAGE", "Other", "Resolver Mode", {"Automatic", "Bruteforce", "Adaptive", "Smart", "Override", "AI"}),
    indicator = ui.new_checkbox("RAGE", "Other", "Show Resolver Info"),
    
    -- Advanced Detection
    detection = ui.new_multiselect("RAGE", "Other", "Detection Methods", {
        "Animation Analysis",
        "Movement Tracking",
        "LBY Analysis",
        "Velocity Prediction",
        "Pose Parameters",
        "Layer Weight",
        "Micro Movement",
        "Standing Detection",
        "Pattern Recognition",
        "Desync Break Detection"
    }),
    
    -- Defensive AA
    defensive = ui.new_checkbox("RAGE", "Other", "Defensive Resolver"),
    defensive_options = ui.new_multiselect("RAGE", "Other", "Defensive Options", {
        "Simulation Check",
        "Lag Compensation",
        "Velocity Exploit",
        "Teleport Detection",
        "Smart Backtrack",
        "Prediction Fix",
        "Layer Correlation"
    }),
    
    -- Bruteforce
    brute_mode = ui.new_combobox("RAGE", "Other", "Brute Mode", {"Sequential", "Random", "Smart", "Adaptive", "Intelligent"}),
    brute_phases = ui.new_slider("RAGE", "Other", "Brute Phases", 2, 7, 5, true),
    brute_reset = ui.new_slider("RAGE", "Other", "Reset After", 1, 5, 3, true),
    
    -- Advanced
    advanced = ui.new_multiselect("RAGE", "Other", "Advanced Features", {
        "Anti-Freestand",
        "Body Aim Fix",
        "Low Delta Detect",
        "Jitter Detection",
        "Micro Movement",
        "Standing Resolver",
        "Smart Prediction",
        "Animation Fix",
        "Pattern Analysis",
        "Context Awareness",
        "Peek Prediction",
        "Adaptive Learning",
        "Weapon Awareness"
    }),
    
    -- Override
    override_left = ui.new_hotkey("RAGE", "Other", "Force Left"),
    override_right = ui.new_hotkey("RAGE", "Other", "Force Right"),
    override_center = ui.new_hotkey("RAGE", "Other", "Force Center"),
    
    -- Settings
    desync_strength = ui.new_slider("RAGE", "Other", "Desync Strength", 1, 100, 60, true, "%"),
    confidence = ui.new_slider("RAGE", "Other", "Confidence Threshold", 50, 100, 75, true, "%"),
    reaction_time = ui.new_slider("RAGE", "Other", "Reaction Time", 0, 100, 20, true, "ms"),
    
    -- AI Settings
    ai_aggression = ui.new_slider("RAGE", "Other", "AI Aggression", 0, 100, 50, true, "%"),
    ai_learning = ui.new_slider("RAGE", "Other", "AI Learning Rate", 0, 100, 75, true, "%"),
    
    -- Visual
    indicator_style = ui.new_combobox("RAGE", "Other", "Indicator Style", {"Simple", "Detailed", "Minimal", "Debug", "Analytics", "Weapon Info"}),
    watermark = ui.new_checkbox("RAGE", "Other", "Watermark"),
    debug = ui.new_checkbox("RAGE", "Other", "Debug Mode"),
    console_log = ui.new_checkbox("RAGE", "Other", "Console Logging"),
    
    -- Defensive Peek System
    defensive_peek_separator = ui.new_label("RAGE", "Other", "────────── Defensive Peek ──────────"),
    defensive_peek_fix = ui.new_checkbox("RAGE", "Other", "Force defensive on peek"),
    peek_prediction_time = ui.new_slider("RAGE", "Other", "Peek prediction", 50, 500, 250, true, "ms", 1, {[50] = "Fast", [250] = "Balanced", [500] = "Safe"}),
    peek_min_damage = ui.new_slider("RAGE", "Other", "Minimum peek damage", 10, 100, 25, true, "hp", 1, {[10] = "Aggressive", [25] = "Balanced", [50] = "Safe", [100] = "Lethal Only"}),
    peek_auto_enable = ui.new_multiselect("RAGE", "Other", "Auto-enable for weapons", {
        "Enemy has AWP",
        "Enemy has Scout",
        "You have AWP/Scout",
        "Low health (<50HP)"
    }),
    
    -- Config
    config_separator = ui.new_label("RAGE", "Other", "───────── Configuration ─────────"),
    config_preset = ui.new_combobox("RAGE", "Other", "Config Preset", {
        "Custom",
        "Default",
        "Aggressive",
        "Defensive"
    }),
    config_description = ui.new_label("RAGE", "Other", "Select a preset to see description"),
    config_load = ui.new_button("RAGE", "Other", "Load Preset", function() end),
    config_separator2 = ui.new_label("RAGE", "Other", "─────────────────────────────"),
    config_export = ui.new_button("RAGE", "Other", "Export Config", function() end),
    config_import = ui.new_button("RAGE", "Other", "Import Config", function() end),

    resolver_flags_separator = ui.new_label("RAGE", "Other", "────────── Resolver Additions ──────────"),
    resolver_flags = ui.new_checkbox("RAGE", "Other", "Show resolver indicators")
}

local ui_defensive_delay = {
    enable = ui.new_checkbox("RAGE", "Other", "Delay head til safe (defensive) EXPERIMENTAL")
}

-- ===========================
-- DEFENSIVE PEEK PREDICTION
-- ===========================
local last_peek_check = 0
local last_peek_result = false
local PEEK_CHECK_INTERVAL = 4  -- Check every 2 ticks for performance

local function vec3(_x, _y, _z)
    return { x = _x or 0, y = _y or 0, z = _z or 0 }
end

local function should_force_defensive_peek()
    if not ui.get(ui_elements.defensive_peek_fix) then 
        return false 
    end
    
    -- Cache result for performance
    if globals.tickcount() - last_peek_check < PEEK_CHECK_INTERVAL then
        return last_peek_result
    end
    
    local local_player = entity.get_local_player()
    if not local_player or not entity.is_alive(local_player) then 
        last_peek_result = false
        last_peek_check = globals.tickcount()
        return false 
    end
    
    -- Check auto-enable conditions
    local auto_enable = safe_get_multiselect(ui_elements.peek_auto_enable)
    local should_auto_enable = false
    
    if contains(auto_enable, "Low health (<50HP)") then
        local health = entity.get_prop(local_player, "m_iHealth") or 100
        if health < 50 then
            should_auto_enable = true
        end
    end
    
    if contains(auto_enable, "You have AWP/Scout") then
        local weapon = entity.get_player_weapon(local_player)
        local weapon_type = get_weapon_type(weapon)
        if weapon_type == "awp" or weapon_type == "scout" then
            should_auto_enable = true
        end
    end
    
    -- Check if any enemy has dangerous weapon
    if contains(auto_enable, "Enemy has AWP") or contains(auto_enable, "Enemy has Scout") then
        local enemies = entity.get_players(true)
        if enemies then
            for i = 1, #enemies do
                local enemy = enemies[i]
                if entity.is_alive(enemy) then
                    local enemy_weapon = entity.get_player_weapon(enemy)
                    local enemy_weapon_type = get_weapon_type(enemy_weapon)
                    
                    if contains(auto_enable, "Enemy has AWP") and enemy_weapon_type == "awp" then
                        should_auto_enable = true
                        break
                    end
                    if contains(auto_enable, "Enemy has Scout") and enemy_weapon_type == "scout" then
                        should_auto_enable = true
                        break
                    end
                end
            end
        end
    end
    
    -- If auto-enable conditions not met, don't force defensive
    if #auto_enable > 0 and not should_auto_enable then
        last_peek_result = false
        last_peek_check = globals.tickcount()
        return false
    end
    
    -- Now check if we're actually peeking
    local enemies = entity.get_players(true)
    if not enemies or #enemies == 0 then 
        last_peek_result = false
        last_peek_check = globals.tickcount()
        return false 
    end

    local eye_position = vec3(client.eye_position())
    if not eye_position.x then 
        last_peek_result = false
        last_peek_check = globals.tickcount()
        return false 
    end
    
    local vx_local, vy_local, vz_local = entity.get_prop(local_player, "m_vecVelocity")
    if not vx_local or not vy_local or not vz_local then
        last_peek_result = false
        last_peek_check = globals.tickcount()
        return false
    end
    local velocity_local = vec3(vx_local, vy_local, vz_local)
    
    -- Convert ms to ticks
    local prediction_ms = ui.get(ui_elements.peek_prediction_time)
    local prediction_ticks = math.floor(prediction_ms / (globals.tickinterval() * 1000))
    local tickinterval = globals.tickinterval()
    
    local predicted_eye = vec3(
        eye_position.x + velocity_local.x * tickinterval * prediction_ticks,
        eye_position.y + velocity_local.y * tickinterval * prediction_ticks,
        eye_position.z + velocity_local.z * tickinterval * prediction_ticks
    )

    local min_damage = ui.get(ui_elements.peek_min_damage)

    for i = 1, #enemies do
        local player = enemies[i]
        if not entity.is_alive(player) then goto continue end

        local vx_enemy, vy_enemy, vz_enemy = entity.get_prop(player, "m_vecVelocity")
        if not vx_enemy or not vy_enemy or not vz_enemy then
            goto continue
        end
        local velocity = vec3(vx_enemy, vy_enemy, vz_enemy)
        
        local head_x, head_y, head_z = entity.hitbox_position(player, 0)
        
        if not head_x then goto continue end
        
        local head_origin = vec3(head_x, head_y, head_z)
        
        local predicted_head = vec3(
            head_origin.x + velocity.x * tickinterval * prediction_ticks,
            head_origin.y + velocity.y * tickinterval * prediction_ticks,
            head_origin.z + velocity.z * tickinterval * prediction_ticks
        )

        -- fixed: capture BOTH return values from trace_line
        local frac, ent = client.trace_line(local_player,
            predicted_eye.x, predicted_eye.y, predicted_eye.z,
            predicted_head.x, predicted_head.y, predicted_head.z)

        -- visible if the ray isn’t fully blocked AND it hits the target player
        if frac < 1.0 and ent == player then
            local _, damage = client.trace_bullet(local_player,
                predicted_eye.x, predicted_eye.y, predicted_eye.z,
                predicted_head.x, predicted_head.y, predicted_head.z)

            if damage and damage >= min_damage then
                last_peek_result = true
                last_peek_check = globals.tickcount()
                return true
            end
        end


        ::continue::
    end

    last_peek_result = false
    last_peek_check = globals.tickcount()
    return false
end

-- ===========================
-- RESOLVER DATA
-- ===========================
local resolver_data = {}
local lag_records = {}
local defensive_records = {}

speed_cache = {}
speed_cache_time = {}
damage_cache = {}
damage_cache_time = {}
CACHE_DURATION = 2
DEFENSIVE_CACHE_DURATION = 4
AA_CHECK_CACHE_DURATION = 32
local eye_angle_data = {}

defensive_check_cache = {}
defensive_check_time = {}

local resolver_cache = {}
local RESOLVER_CACHE_TICKS = 0

local function get_cached_or_resolve(player, resolve_func)
    local tick = globals.tickcount()
    
    if not resolver_cache[player] then
        resolver_cache[player] = {}
    end
    
    local cache = resolver_cache[player]
    
    if cache.result and cache.tick and (tick - cache.tick) < RESOLVER_CACHE_TICKS then
        return cache.result
    end
    
    local result = resolve_func()
    cache.result = result
    cache.tick = tick
    
    return result
end

local function init_player_data(player)
    -- Return existing data immediately (avoids re-checking entire table)
    if resolver_data[player] then
        return resolver_data[player]
    end
    
        -- Only initialize if doesn't exist
        resolver_data[player] = {
            -- Hit/Miss tracking
            misses = 0,
            hits = 0,
            shots = 0,
            hit_rate = 0,
            
            -- Bruteforce
            brute_phase = 1,
            brute_locked = false,
            brute_working = false,
            
            -- Detection
            last_update = globals.tickcount(),
            last_resolve = 0,
            desync_side = 0,
            predicted_side = 0,
            
            -- Animation
            last_lby = 0,
            lby_delta = 0,
            last_simtime = 0,
            last_velocity = {x = 0, y = 0, z = 0},
            
            -- Standing
            standing_ticks = 0,
            moving_ticks = 0,
            
            -- Confidence
            confidence = 0,
            reliability = 0,
            
            -- Defensive
            is_defensive = false,
            defensive_ticks = 0,
            defensive_active = false,
            
            -- Resolved
            resolved_angle = 0,
            body_yaw = 0,
            
            -- Animation tracking
            last_layers = {},
            last_anim_state = nil,
            
            -- Movement tracking
            last_position = nil,
            movement_delta = 0,
            
            -- Layer analysis
            layer_data = {
                move_weight = 0,
                move_cycle = 0,
                stand_cycle = 0
            },
            
            -- NEW: Advanced Features
            recent_angles = {},
            patterns = {
                oscillation = false,
                consistent_side = 0,
                mean_angle = 0,
                variability = 0
            },
            
            method_weights = {
                lby_delta = 0.25,
                movement = 0.20,
                animation = 0.15,
                velocity = 0.15,
                historical = 0.15,
                pattern = 0.10
            },
            
            last_successful_method = "",
            last_failed_method = "",
            
            recent_positions = {},
            predicted_position = nil,
            movement_acceleration = 0,
            
            fake_desync_detected = false,
            true_lby = 0,
            last_lby_update = 0,
            
            brute_patterns = {
                sequential = {phases = {}, success_rate = 0},
                random = {phases = {}, success_rate = 0},
                smart = {phases = {}, success_rate = 0},
                adaptive = {phases = {}, success_rate = 0}
            },
            
            layer_correlations = {},
            suspicious_animation = false,
            
            resolver_context = "balanced",
            likely_peek_type = "unknown",
            peek_aggression = 0.5,
            expected_desync = "unknown",
            
            analytics = {
                method_success = {},
                angle_success = {},
                timing_success = {},
                total_resolves = 0,
                successful_resolves = 0,
                overall_success_rate = 0
            },
            
            learning_phase = "initial",
            brute_aggression = 0.5,
            player_profile = {
                playstyle = "unknown",
                desync_habits = {},
                movement_patterns = {}
            },
            
            -- NEW: Weapon Awareness
            weapon_threat = 50,
            current_weapon = "unknown",
            weapon_priority = {
                ["awp"] = 90,
                ["scout"] = 85,
                ["auto"] = 80,
                ["deagle"] = 75,
                ["revolver"] = 70,
                ["rifle"] = 65,
                ["pistol"] = 60,
                ["smg"] = 50,
                ["unknown"] = 50
            },

            -- Reliable angles for peek detection
            reliable_angles = {
                left_angles = {},
                right_angles = {},
                last_reliable_angle = 0,
                last_reliable_tick = 0,
                confidence_threshold = 70
            },
            
            -- Peek state tracking
            peek_state = {
                last_speed = 0,
                last_direction = 0,
                acceleration = 0,
                direction_changes = 0,
                peek_type = "none",
                peek_confidence = 0
            },

            body_aimable = false,
            body_aim_priority = false,
            health_threshold = 100,
            last_damage_dealt = 0,
            lethal_shot_available = false,
            lethal_mindmg_override = nil,
            lethal_mindmg_required = nil,
            estimated_body_damage = 0,
            last_shot_time = 0,
            shot_accuracy = 100,
            last_known_health = nil,

            -- NEW: Shot timing analysis
            shot_snapshot_angle = 0,
            shot_snapshot_time = 0,
            last_weapon_shot_time = 0,

            -- NEW: Choke analysis
            choke_history = create_circular_buffer(10),
            choke_stability = 1.0,

            -- NEW: Pose tracking
            pose_history = create_circular_buffer(5),
            jitter_detected = false,
            jitter_side_preference = 0,

            -- NEW: Layer 6 micro-analysis
            layer6_weight_history = {},

            -- NEW: LBY prediction
            last_lby_update_time = 0,
            lby_update_imminent = false,

            -- NEW: Brute phase success tracking
            brute_phase_success = {
                [1] = {hits = 0, time = 0, misses = 0},
                [2] = {hits = 0, time = 0, misses = 0},
                [3] = {hits = 0, time = 0, misses = 0},
                [4] = {hits = 0, time = 0, misses = 0},
                [5] = {hits = 0, time = 0, misses = 0}
            },

            -- NEW: Hitgroup learning
            hitgroup_angles = {},
            preferred_head_angle = 0,

            -- NEW: Velocity analysis
            velocity_history = create_circular_buffer(8),
            predicted_flip_angle = 0,
            flip_predicted = false,
            flip_predict_time = 0,

            last_resolved_side = 0,

            -- NEW: Enhanced Defensive Detection Fields
            last_eye_angles = nil,
            defensive_flick_detected = false,
            last_good_angle = 0,
            defensive_suspicious = false,
            defensive_suspicion_score = 0,
            local_ping = 50,
            effective_ping = 50,

            air_state = nil,
            crouch_state = nil,
            sim_history = {},
            pitch_history = {},
            pitch_exploit_detected = false,
        }

    return resolver_data[player]
end

            local function init_lag_record(player)
                if not lag_records[player] then
                    lag_records[player] = {}
                end
                
                table.insert(lag_records[player], 1, {
                    time = globals.curtime(),
                    tickcount = globals.tickcount(),
                    origin = {entity.get_prop(player, "m_vecOrigin")},
                    velocity = {get_cached_prop(player, "m_vecVelocity", 0)},
                    simtime = entity.get_prop(player, "m_flSimulationTime"),
                    lby = entity.get_prop(player, "m_flLowerBodyYawTarget"),
                    layers = nil,
                    anim_state = nil
                })
                
                -- Keep only last 16 records
                while #lag_records[player] > 16 do
                    table.remove(lag_records[player])
                end
            end

-- ===========================
-- WEAPON DAMAGE CALCULATION
-- ===========================
local function get_weapon_damage(weapon_type, has_armor)
    local damage_table = {
        ["awp"] = {body = 115, armored_body = 85},
        ["scout"] = {body = 85, armored_body = 65},
        ["deagle"] = {body = 53, armored_body = 43},
        ["revolver"] = {body = 51, armored_body = 41},
        ["auto"] = {body = 80, armored_body = 65},
        ["rifle"] = {body = 35, armored_body = 27},
        ["pistol"] = {body = 25, armored_body = 20},
        ["smg"] = {body = 30, armored_body = 23}
    }
    
    local dmg = damage_table[weapon_type] or {body = 25, armored_body = 20}
    return has_armor and dmg.armored_body or dmg.body
end

-- ===========================
-- ACCURATE DAMAGE CALCULATION (ADD THIS - NEW)
-- ===========================
local baim_hitboxes = {3, 4, 5, 6}  -- Body hitboxes

local function extrapolate_position(xpos, ypos, zpos, ticks, player, data)
    if not data then data = init_player_data(player) end
    
    local x, y, z = get_cached_prop(player, "m_vecVelocity", 0)
    if not x or not y or not z then return xpos, ypos, zpos end
    
    -- Calculate acceleration if we have history
    local ax, ay, az = 0, 0, 0
    if data.velocity_history then
        local history = data.velocity_history:get_all()
        if history and #history >= 2 then
            local current_vel = history[1]
            local prev_vel = history[2]
            
            if current_vel and prev_vel then
                local dt = globals.tickinterval()
                ax = (current_vel.x - prev_vel.x) / dt
                ay = (current_vel.y - prev_vel.y) / dt
                az = (current_vel.z - prev_vel.z) / dt
            end
        end
    end
    
    -- Use kinematic equation: s = ut + 0.5at²
    local t = ticks * globals.tickinterval()
    
    xpos = xpos + (x * t) + (0.5 * ax * t * t)
    ypos = ypos + (y * t) + (0.5 * ay * t * t)
    zpos = zpos + (z * t) + (0.5 * az * t * t)
    
    return xpos, ypos, zpos
end

-- ===========================
-- ADAPTIVE EXTRAPOLATION
-- ===========================
local function get_adaptive_extrapolation_ticks(player, data)
    local ping = entity.get_prop(player, "m_iPing")
    if not ping then
        return 4  -- Return base ticks if we can't get ping
    end
    
    local choke = get_choke_from_simtime(player)
    local local_ping = get_local_ping()
    
    -- Base extrapolation
    local base_ticks = 4
    
    -- Adjust for ping (higher ping = more extrapolation needed)
    local ping_ticks = math.floor((ping + local_ping) / 30)
    
    -- Adjust for choke (high choke = they're updating less frequently)
    local choke_ticks = math.min(choke / 2, 4)
    
    -- Total ticks, clamped to reasonable range
    local total_ticks = base_ticks + ping_ticks + choke_ticks
    return math.min(total_ticks, 12)  -- Cap at 12 ticks (backtrack limit)
end

-- ✅ IMPROVED: More aggressive damage calculation
local function calculate_body_damage(ent, localplayer)
    -- Add caching
    local tick = globals.tickcount()
    if damage_cache[ent] and (tick - (damage_cache_time[ent] or 0)) < CACHE_DURATION then
        return damage_cache[ent]
    end
    
    local final_damage = 0

    local eyepos_x, eyepos_y, eyepos_z = client.eye_position()
    if not eyepos_x then 
        damage_cache[ent] = 0
        damage_cache_time[ent] = tick
        return 0 
    end
    
    local fs_stored_eyepos_x, fs_stored_eyepos_y, fs_stored_eyepos_z

    -- better calculation
    local data = init_player_data(ent)
    local extrap_ticks = get_adaptive_extrapolation_ticks(ent, data)
    eyepos_x, eyepos_y, eyepos_z = extrapolate_position(eyepos_x, eyepos_y, eyepos_z, extrap_ticks, localplayer, data)

    if not eyepos_x or not eyepos_y or not eyepos_z then
        damage_cache[ent] = 0
        damage_cache_time[ent] = tick
        return 0
    end

    fs_stored_eyepos_x, fs_stored_eyepos_y, fs_stored_eyepos_z = eyepos_x, eyepos_y, eyepos_z
    
    -- ✅ IMPROVED: Check all body hitboxes and use HIGHEST damage
    for k, v in pairs(baim_hitboxes) do
        local hx, hy, hz = entity.hitbox_position(ent, v)
        if hx then
            local ___, dmg = client.trace_bullet(localplayer, fs_stored_eyepos_x, fs_stored_eyepos_y, fs_stored_eyepos_z, hx, hy, hz, true)
            
            if dmg and dmg > final_damage then
                final_damage = dmg
            end
        end
    end
    
    -- ✅ NEW: If body damage seems low, also check stomach (hitbox 2)
    if final_damage < 50 then
        local hx, hy, hz = entity.hitbox_position(ent, 2)  -- Stomach
        if hx then
            local ___, dmg = client.trace_bullet(localplayer, fs_stored_eyepos_x, fs_stored_eyepos_y, fs_stored_eyepos_z, hx, hy, hz, true)
            if dmg and dmg > final_damage then
                final_damage = dmg
            end
        end
    end
    
    -- Cache result
    damage_cache[ent] = final_damage
    damage_cache_time[ent] = tick
    
    return final_damage
end

-- ===========================
-- UNIFIED SMART BODY AIM SYSTEM
-- ===========================
local ui_smart_baim = {
    enable = ui.new_checkbox("RAGE", "Other", "Smart body aim"),
    separator1 = ui.new_label("RAGE", "Other", "────────── General Settings ──────────"),
    mode = ui.new_combobox("RAGE", "Other", "Playstyle", {"Default", "Aggressive", "Defensive"}),
    
    separator2 = ui.new_label("RAGE", "Other", "────────── Lethal Shots ──────────"),
    lethal_enable = ui.new_checkbox("RAGE", "Other", "Force body on lethal shots"),
    lethal_threshold = ui.new_slider("RAGE", "Other", "Lethal HP threshold", 1, 100, 80, true, "hp"),
    accuracy_threshold = ui.new_slider("RAGE", "Other", "Min shot accuracy", 0, 100, 75, true, "%"),
    lethal_mode = ui.new_combobox("RAGE", "Other", "Lethal behavior", {
        "Force body (strict)",
        "Prefer body (flexible)", 
        "Smart (adjust by accuracy)"
    }),
    -- override dmg on lethal thing
    lethal_override_mindmg = ui.new_checkbox("RAGE", "Other", "Override min damage on lethal (SCOUT ONLY)"),
    
    separator3 = ui.new_label("RAGE", "Other", "────────── ESP Indicators ──────────"),
    show_lethal_flag = ui.new_checkbox("RAGE", "Other", "Show lethal ESP flag"),
    lethal_flag_style = ui.new_combobox("RAGE", "Other", "Flag style", {"Simple", "Detailed"}),
    lethal_flag_color = ui.new_color_picker("RAGE", "Other", "Lethal flag color", 255, 0, 0, 255) 
}

-- per wep min dmg
local ref_mindmg = ui.reference("RAGE", "Aimbot", "Minimum damage")
local ref_mindmg_override_enable = ui.reference("RAGE", "Aimbot", "Minimum damage override")

local last_target = nil
local last_mindmg_value = nil
local original_mindmg_per_weapon = {}  -- stores per wep

-- Function to get current weapon ID
local function get_local_weapon_id()
    local me = entity.get_local_player()
    if not me or not entity.is_alive(me) then return nil end
    
    local weapon = entity.get_player_weapon(me)
    if not weapon then return nil end
    
    return entity.get_prop(weapon, "m_iItemDefinitionIndex")
end

-- Function to save current min damage for active weapon
local function save_current_mindmg()
    local weapon_id = get_local_weapon_id()
    if not weapon_id or not ref_mindmg then return end
    
    -- Only save if we haven't overridden it
    if last_mindmg_value == nil then
        original_mindmg_per_weapon[weapon_id] = ui.get(ref_mindmg)
    end
end

-- Function to restore min damage for active weapon
local function restore_mindmg()
    local weapon_id = get_local_weapon_id()
    if not weapon_id or not ref_mindmg then return end
    
    local saved_value = original_mindmg_per_weapon[weapon_id]
    if saved_value then
        ui.set(ref_mindmg, saved_value)
    end
end

-- Save initial values for all weapons on round start
client.set_event_callback("round_prestart", function()
    save_current_mindmg()
end)

-- Also save when switching weapons
local last_weapon_id = nil

-- ===========================
-- SPREAD/ACCURACY CALCULATION
-- ===========================
local function calculate_shot_accuracy(player)
    local local_player = entity.get_local_player()
    if not local_player then return 100 end
    
    local weapon = entity.get_player_weapon(local_player)
    if not weapon then return 100 end
    
    local inaccuracy = entity.get_prop(weapon, "m_fAccuracyPenalty") or 0
    
    -- Calculate confidence percentage (lower inaccuracy = higher confidence)
    local accuracy = math.max(0, 100 - (inaccuracy * 200))
    
    return accuracy
end

-- ===========================
-- WEAPON AWARENESS SYSTEM (UPDATED)
-- ===========================
local function update_weapon_priority(player, data)
    local weapon_type = get_weapon_type(entity.get_player_weapon(player))
    
    -- Adjust resolver aggression based on weapon threat
    local weapon_priority = {
        ["awp"] = 90,
        ["scout"] = 85,
        ["auto"] = 80,
        ["deagle"] = 75,
        ["revolver"] = 70,
        ["rifle"] = 65,
        ["pistol"] = 60,
        ["smg"] = 50,
        ["unknown"] = 50
    }
    
    data.weapon_threat = weapon_priority[weapon_type] or 50
    data.current_weapon = weapon_type
    
    -- Body aim viability is handled by apply_smart_hitbox_override()
end

-- ===========================
-- SHOT TIMING SAFETY
-- ===========================
local function should_delay_shot(player, data)
    -- Check if we're shooting too fast without good accuracy
    if data.last_shot_time and (globals.curtime() - data.last_shot_time) < 0.2 then
        local accuracy = calculate_shot_accuracy(player)
        if accuracy < ui.get(ui_smart_baim.accuracy_threshold) then
            return true -- Should delay shot
        end
    end
    return false
end

-- ===========================
-- CONTEXT-AWARE RESOLVING
-- ===========================
local function get_resolver_context(player)
    if not player or not entity.is_alive(player) then
        return "balanced"
    end
    
    local game_rules = entity.get_game_rules()
    local round_start_time = 0
    local bomb_planted = false
    
    if game_rules then
        round_start_time = entity.get_prop(game_rules, "m_fRoundStartTime") or 0
        bomb_planted = entity.get_prop(game_rules, "m_bBombPlanted") or false
    end
    
    local context = {
        round_time = globals.curtime() - round_start_time,
        bomb_planted = bomb_planted,
        bomb_site = get_bomb_site(player),
        teammates_alive = count_teammates(player),
        enemies_alive = count_enemies(player),
        player_health = get_cached_prop(player, "m_iHealth", 100)
    }
    
    -- Adjust resolver aggression based on context
    if context.bomb_planted and context.player_health < 50 then
        return "aggressive"  -- Player likely to peek
    elseif context.teammates_alive > context.enemies_alive then
        return "defensive"   -- Player likely to hold angle
    else
        return "balanced"
    end
end

-- ===========================
-- ENHANCED PEEK PREDICTION FOR HVH WEAPONS
-- ===========================
local function predict_peek_behavior(player, data)
    if not player or not entity.is_alive(player) then
        data.likely_peek_type = "unknown"
        data.peek_aggression = 0.5
        data.expected_desync = "unknown"
        data.resolver_context = "balanced"
        return
    end
    local context = get_resolver_context(player)
    local weapon = entity.get_player_weapon(player)
    local weapon_type = get_weapon_type(weapon)
    
    -- Default values
    data.likely_peek_type = "unknown"
    data.peek_aggression = 0.5
    data.expected_desync = "unknown"
    
    -- HVH Weapon-Specific Peek Prediction
    if weapon_type == "awp" then
        -- AWP users: Shoulder peeks, bait shots, minimal exposure
        data.likely_peek_type = "shoulder"
        data.peek_aggression = 0.3
        data.expected_desync = "maximum"
        
    elseif weapon_type == "scout" then
        -- Scout users: More aggressive than AWP, faster peeks, jiggle peeking
        data.likely_peek_type = "jiggle"
        data.peek_aggression = 0.6
        data.expected_desync = "dynamic"  -- Scout users change desync often
        
    elseif weapon_type == "auto" then
        -- Auto sniper users: Hold angles, prefire common spots, less movement
        data.likely_peek_type = "hold"
        data.peek_aggression = 0.4
        data.expected_desync = "minimum"  -- Often minimal desync when holding
        
    elseif weapon_type == "deagle" then
        -- Deagle users: Jiggle peeks, crouch peeks, headshot angles
        data.likely_peek_type = "crouch"
        data.peek_aggression = 0.7
        data.expected_desync = "medium"   -- Balanced desync for deagle
        
    elseif weapon_type == "revolver" then
        -- Revolver users: Similar to deagle but more deliberate
        data.likely_peek_type = "delayed"
        data.peek_aggression = 0.5
        data.expected_desync = "medium"
        
    elseif weapon_type == "pistol" then
        -- Pistol users: Run-and-gun, wide peeks, aggressive pushes
        data.likely_peek_type = "wide"
        data.peek_aggression = 0.8
        data.expected_desync = "minimum"  -- Often minimal when running
        
    elseif weapon_type == "rifle" then
        -- Rifle users: Wide peeks, spray transfers, medium aggression
        data.likely_peek_type = "wide"
        data.peek_aggression = 0.7
        data.expected_desync = "medium"
        
    else
        -- Unknown/fallback
        data.likely_peek_type = "unknown"
        data.peek_aggression = 0.5
        data.expected_desync = "unknown"
    end
    
    -- Context adjustments for HVH
    local health = get_cached_prop(player, "m_iHealth", 100)
    if health < 50 then
        -- Low health players peek more cautiously
        data.peek_aggression = data.peek_aggression * 0.7
        if data.likely_peek_type == "wide" then
            data.likely_peek_type = "shoulder"
        end
    end
    
    -- Round time adjustments (late round vs early round)
    local round_time = globals.curtime() - (entity.get_prop(entity.get_game_rules(), "m_fRoundStartTime") or 0)
    if round_time > 30 then
        -- Late round: more cautious peeks
        data.peek_aggression = data.peek_aggression * 0.8
    end
    
    data.resolver_context = context
end

-- ===========================
-- WEAPON-AWARE RESOLUTION
-- ===========================
local function weapon_aware_resolution(player, data, base_angle)
    local weapon_type = get_weapon_type(entity.get_player_weapon(player))
    local resolved_angle = base_angle
    
    -- Weapon-specific adjustments
    if weapon_type == "scout" then
        -- Scout users: more dynamic, adapt faster
        if data.patterns.oscillation then
            resolved_angle = resolved_angle * 1.2  -- More aggressive against jitter
        end
        
    elseif weapon_type == "auto" then
        -- Auto users: more predictive, less reactive
        resolved_angle = resolved_angle * 0.9  -- More conservative
        
    elseif weapon_type == "deagle" then
        -- Deagle users: account for crouch peeks
        if data.likely_peek_type == "crouch" then
            resolved_angle = resolved_angle * 1.1  -- Slightly more aggressive
        end
        
    elseif weapon_type == "pistol" then
        -- Pistol users: faster reaction
        resolved_angle = resolved_angle * 1.15  -- More aggressive for run-and-gun
    end
    
    return resolved_angle
end

-- ===========================
-- ADVANCED PATTERN RECOGNITION
-- ===========================
local function analyze_desync_patterns(player, data)
    local patterns = {}
    local recent_angles = data.recent_angles or {}
    
    -- Store recent resolved angles
    table.insert(recent_angles, 1, data.resolved_angle)
    if #recent_angles > 32 then table.remove(recent_angles) end
    data.recent_angles = recent_angles
    
    if #recent_angles >= 8 then
        -- Calculate statistical patterns
        local mean, std_dev = calculate_angle_stats(recent_angles)
        local variance = calculate_variance(recent_angles, mean)
        
        -- Detect oscillation patterns (common in jitter AA)
        local oscillation_detected = detect_oscillation(recent_angles, 3) -- 3-cycle detection
        local consistent_side = detect_consistent_side(recent_angles, 8) -- 8-tick consistency
        
        data.patterns = {
            oscillation = oscillation_detected,
            consistent_side = consistent_side,
            mean_angle = mean,
            variability = std_dev
        }
        
        return true
    end
    
    return false
end

-- ===========================
-- ADAPTIVE CONFIDENCE SYSTEM
-- ===========================
local function adaptive_confidence_system(player, data)
    local weights = data.method_weights
    
    -- Adjust weights based on hit success
    if data.hit_rate > 0.7 then
        -- Boost what's working
        for method, _ in pairs(weights) do
            if data.last_successful_method == method then
                weights[method] = weights[method] * 1.3
            end
        end
    elseif data.hit_rate < 0.3 then
        -- Reduce what's failing
        for method, _ in pairs(weights) do
            if data.last_failed_method == method then
                weights[method] = weights[method] * 0.7
            end
        end
    end
    
    -- Normalize weights
    local total = 0
    for _, w in pairs(weights) do total = total + w end
    for method, w in pairs(weights) do
        weights[method] = w / total
    end
    
    data.method_weights = weights
    return weights
end

-- ===========================
-- PREDICTIVE MOVEMENT ANALYSIS
-- ===========================
local function predict_movement_trajectory(player, data)
    local positions = data.recent_positions or {}
    local x, y, z = entity.get_prop(player, "m_vecOrigin")
    
    if not x or not y then return end
    
    -- Store position history
    table.insert(positions, 1, {x = x, y = y, z = z, time = globals.curtime()})
    if #positions > 16 then table.remove(positions) end
    data.recent_positions = positions
    
    if #positions >= 3 then
        -- Calculate acceleration and predict next position
        local vel1 = {
            x = positions[1].x - positions[2].x,
            y = positions[1].y - positions[2].y,
            z = positions[1].z - positions[2].z
        }
        
        local vel2 = {
            x = positions[2].x - positions[3].x,
            y = positions[2].y - positions[3].y,
            z = positions[2].z - positions[3].z
        }
        
        local acceleration = {
            x = vel1.x - vel2.x,
            y = vel1.y - vel2.y,
            z = vel1.z - vel2.z
        }
        
        -- Predict next position using basic physics
        local predicted_pos = {
            x = positions[1].x + vel1.x + acceleration.x * 0.5,
            y = positions[1].y + vel1.y + acceleration.y * 0.5,
            z = positions[1].z + vel1.z + acceleration.z * 0.5
        }
        
        data.predicted_position = predicted_pos
        data.movement_acceleration = math.sqrt(acceleration.x^2 + acceleration.y^2 + acceleration.z^2)
    end
end

-- ===========================
-- DESYNC BREAK DETECTION
-- ===========================
local function detect_desync_break(player, data)
    local current_lby = entity.get_prop(player, "m_flLowerBodyYawTarget") or 0
    local lby_delta = math.abs(angle_diff(current_lby, data.last_lby))
    
    -- Detect fake flickers (too fast to be real)
    if lby_delta > 60 and data.last_lby_update and 
       (globals.curtime() - data.last_lby_update) < 0.2 then
        data.fake_desync_detected = true
        data.true_lby = data.last_lby  -- Store the real LBY
        return true
    end
    
    data.last_lby_update = globals.curtime()
    return false
end

-- ===========================
-- PING-AWARE HELPER FUNCTIONS
-- ===========================

-- Get local player's ping (use client.latency(); returns seconds)
local function get_local_ping()
    local lat = client.latency()
    if not lat or lat <= 0 then return 50 end
    local ms = math.floor(lat * 1000 + 0.5)  -- convert to ms
    return math.min(ms, 300)
end


-- Get enemy player's ping from PlayerResource
local function get_player_ping(player)
    if not player then return 50 end
    local pr = entity.get_player_resource()
    if not pr then return 50 end

    local ping = entity.get_prop(pr, "m_iPing", player)  -- indexed by player
    if not ping or ping < 0 then return 50 end
    return math.min(ping, 300)
end


-- Calculate ping-adjusted thresholds
local function get_ping_thresholds(enemy_ping, local_ping)

    -- Validate inputs
    enemy_ping = enemy_ping or 50
    local_ping = local_ping or 50

    local effective_ping = math.max(enemy_ping, local_ping)
    
    local thresholds = {
        teleport_dist = 64,
        velocity_max = 320,
        simtime_gap = 14,
        suspicion_base = 60,
        ping_category = "low",
        enemy_ping = enemy_ping,
        local_ping = local_ping,
        effective_ping = effective_ping
    }
    
    if effective_ping < 50 then
        thresholds.ping_category = "low"
        thresholds.teleport_dist = 64
        thresholds.velocity_max = 320
        thresholds.suspicion_base = 60
        
    elseif effective_ping < 100 then
        thresholds.ping_category = "medium"
        thresholds.teleport_dist = 90
        thresholds.velocity_max = 350
        thresholds.suspicion_base = 65
        
    elseif effective_ping < 150 then
        thresholds.ping_category = "high"
        thresholds.teleport_dist = 120
        thresholds.velocity_max = 380
        thresholds.suspicion_base = 70
        
    else
        thresholds.ping_category = "very_high"
        thresholds.teleport_dist = 150
        thresholds.velocity_max = 420
        thresholds.suspicion_base = 80
    end
    
    return thresholds
end

-- ===========================
-- UNIFIED DEFENSIVE DETECTION SYSTEM
-- ===========================

-- Validate defensive detection to reduce false positives
local function is_valid_defensive_detection(player, data, detection)
    if not detection or not detection.detected then
        return false
    end
    
    -- Require minimum confidence
    if detection.confidence < 85 then
        return false
    end
    
    -- Don't detect defensive within 0.25s of taking damage
    if data.last_damage_time and (globals.curtime() - data.last_damage_time) < 0.25 then
        return false
    end
    
    -- Don't detect defensive if we just shot at them (might be hit reaction)
    if data.last_shot_time and (globals.curtime() - data.last_shot_time) < 0.2 then
        return false
    end
    
    -- Require multiple ticks of suspicious behavior for lower confidence
    if detection.confidence < 92 then
        if not data.defensive_suspicion_ticks then
            data.defensive_suspicion_ticks = 0
        end
        data.defensive_suspicion_ticks = data.defensive_suspicion_ticks + 1
        
        -- Need 2+ suspicious ticks for medium confidence
        if data.defensive_suspicion_ticks < 2 then
            return false
        end
    else
        -- High confidence = reset counter
        data.defensive_suspicion_ticks = 0
    end
    
    return true
end

-- Detection result structure
local function create_detection_result(detected, confidence, method, ticks, angle)
    return {
        detected = detected,
        confidence = confidence,
        method = method,
        ticks = ticks or 0,
        angle = angle
    }
end

-- Unified Neverlose/Metaset detection (merges both)
local function detect_exploit_doubletap(player, data)
    local sim_time = entity.get_prop(player, "m_flSimulationTime")
    local old_sim_time = entity.get_prop(player, "m_flOldSimulationTime")
    
    if not sim_time or not old_sim_time then 
        return create_detection_result(false, 0, "none", 0)
    end
    
    -- Store simulation history
    if not data.sim_history then data.sim_history = {} end
    
    table.insert(data.sim_history, 1, {
        sim_time = sim_time,
        old_sim_time = old_sim_time,
        tick = globals.tickcount()
    })
    if #data.sim_history > 10 then table.remove(data.sim_history) end
    
    local sim_diff = math.floor((sim_time - old_sim_time) / globals.tickinterval())
    
    -- PRIORITY 1: Negative simtime (instant confirmation)
    if sim_diff < 0 then
        return create_detection_result(true, 100, "negative_simtime", 
            math.min(math.abs(sim_diff), 14), data.last_good_angle or 0)
    end
    
    -- PRIORITY 2: Instant large gap (14+ choke in one tick)
    if sim_diff >= 14 then
        return create_detection_result(true, 98, "instant_lc", 14, data.last_good_angle or 0)
    end
    
    -- PRIORITY 3: Doubletap spike pattern (NEW - catches more cases)
    if #data.sim_history >= 4 then
        local current = sim_diff
        local prev1 = math.floor((data.sim_history[2].sim_time - data.sim_history[2].old_sim_time) / globals.tickinterval())
        local prev2 = math.floor((data.sim_history[3].sim_time - data.sim_history[3].old_sim_time) / globals.tickinterval())
        local prev3 = math.floor((data.sim_history[4].sim_time - data.sim_history[4].old_sim_time) / globals.tickinterval())
        
        -- Pattern: Low choke (1-3) -> Sudden spike (12+)
        local avg_prev = (prev1 + prev2 + prev3) / 3
        if avg_prev <= 3 and current >= 12 then
            return create_detection_result(true, 96, "doubletap_spike", 8, data.last_good_angle or 0)
        end
        
        -- Pattern: Oscillating choke (fake lag break)
        if prev1 >= 12 and current <= 2 and prev2 <= 2 then
            return create_detection_result(true, 93, "fakelag_break", 6, data.last_good_angle or 0)
        end
    end
    
    -- PRIORITY 4: Teleport detection (already exists but keep it)
    if data.last_position then
        local x, y, z = entity.get_prop(player, "m_vecOrigin")
        if x and y and z then
            local dx = x - data.last_position.x
            local dy = y - data.last_position.y
            local dist = math.sqrt(dx*dx + dy*dy)
            
            local vx, vy = get_cached_prop(player, "m_vecVelocity", 0)
            local speed = vx and vy and math.sqrt(vx*vx + vy*vy) or 0
            
            local expected_dist = speed * globals.tickinterval() * (sim_diff + 1)
            
            -- Tighter threshold for teleport
            if dist > expected_dist * 1.8 and dist > 50 then
                return create_detection_result(true, 91, "teleport", 6, data.last_good_angle or 0)
            end
        end
    end
    
    return create_detection_result(false, 0, "none", 0)
end

-- ===========================
-- ENHANCED DETECTION FUNCTIONS
-- ===========================

-- Eye angle flick detection with priority scoring
local function detect_eye_angle_flick(player, data)
    local pitch = entity.get_prop(player, "m_angEyeAngles[0]")
    local yaw = entity.get_prop(player, "m_angEyeAngles[1]")
    
    if not pitch or not yaw then 
        return create_detection_result(false, 0, "none", 0)
    end
    
    -- Nil safety check
    if not eye_angle_data[player] or not eye_angle_data[player].history then
        eye_angle_data[player] = {
            history = {},
            last_update = globals.tickcount()
        }
        return create_detection_result(false, 0, "none", 0)
    end
    
    -- Initialize tracking
    if not eye_angle_data[player] then
        eye_angle_data[player] = {
            history = {},
            last_update = globals.tickcount()
        }
    end
    
    local eye_data = eye_angle_data[player]
    
    -- Store history using circular buffer (more efficient)
    if not eye_data.buffer then
        eye_data.buffer = create_circular_buffer(5)
    end
    
    eye_data.buffer:push({
        pitch = pitch,
        yaw = yaw,
        tick = globals.tickcount()
    })
    
    eye_data.history = eye_data.buffer:get_all()  -- For compatibility
    
    if #eye_data.history < 2 then 
        return create_detection_result(false, 0, "none", 0)
    end
    
    local current = eye_data.history[1]
    local previous = eye_data.history[2]
    
    if not current.pitch or not current.yaw or not previous.pitch or not previous.yaw then
        return create_detection_result(false, 0, "none", 0)
    end

    local pitch_delta = math.abs(current.pitch - previous.pitch)
    local yaw_delta = math.abs(normalize_angle(current.yaw - previous.yaw))
    
    local ping = get_player_ping(player)
    local pitch_threshold = ping < 100 and 50 or 65
    local yaw_threshold = ping < 100 and 120 or 140
    
    -- Priority 1: Instant yaw flick (35°+)
    if yaw_delta > 33 then
        data.flick_direction = normalize_angle(current.yaw - previous.yaw) > 0 and 1 or -1
        return create_detection_result(true, 100, "yaw_flick", 6, previous.yaw)
    end
    
    -- Priority 2: Zero pitch mode
    if math.abs(current.pitch) < 5 and math.abs(previous.pitch) > 45 then
        return create_detection_result(true, 98, "zero_pitch", 5, previous.yaw)
    end
    
    -- Priority 3: Custom pitch
    if pitch_delta > pitch_threshold then
        return create_detection_result(true, 95, "custom_pitch", 5, previous.yaw)
    end
    
    -- Priority 4: Switch pitch (requires 4 samples)
    if #eye_data.history >= 4 then
        local pitch1 = eye_data.history[1].pitch
        local pitch2 = eye_data.history[2].pitch
        local pitch3 = eye_data.history[3].pitch
        local pitch4 = eye_data.history[4].pitch
        
        local diff1 = math.abs(pitch1 - pitch2)
        local diff2 = math.abs(pitch3 - pitch4)
        local diff3 = math.abs(pitch1 - pitch3)
        
        if diff1 > 40 and diff2 > 40 and diff3 < 10 then
            return create_detection_result(true, 93, "switch_pitch", 6, previous.yaw)
        end
    end
    
    -- Priority 5: Multi-tick pattern
    if #eye_data.history >= 4 then
        local total_yaw_change = 0
        for i = 1, 3 do
            total_yaw_change = total_yaw_change + 
                math.abs(normalize_angle(eye_data.history[i].yaw - eye_data.history[i+1].yaw))
        end
        
        if total_yaw_change > 180 then
            return create_detection_result(true, 88, "oscillation", 4, previous.yaw)
        end
    end
    
    return create_detection_result(false, 0, "none", 0)
end

-- Spin detection (optimized with scoring)
local function detect_defensive_spin(player, data)
    if not eye_angle_data[player] then 
        return create_detection_result(false, 0, "none", 0)
    end
    if not eye_angle_data[player].history then 
        return create_detection_result(false, 0, "none", 0)
    end
    if #eye_angle_data[player].history < 4 then 
        return create_detection_result(false, 0, "none", 0)
    end
    
    local history = eye_angle_data[player].history
    
    -- Check continuous rotation
    local rotations = {}
    for i = 1, 3 do
        local delta = normalize_angle(history[i].yaw - history[i+1].yaw)
        table.insert(rotations, delta)
    end
    
    local all_positive = true
    local all_negative = true
    local total_rotation = 0
    
    for _, rot in ipairs(rotations) do
        total_rotation = total_rotation + math.abs(rot)
        if rot < 0 then all_positive = false end
        if rot > 0 then all_negative = false end
    end
    
    -- Fast spin
    if (all_positive or all_negative) and total_rotation > 45 then
        data.spin_direction = all_positive and 1 or -1
        return create_detection_result(true, 89, "spin", 5, data.last_good_angle or 0)
    end
    
    -- Slow spin detection
    if (all_positive or all_negative) and total_rotation > 25 then
        if not data.spin_sequence then data.spin_sequence = 0 end
        data.spin_sequence = data.spin_sequence + 1
        
        if data.spin_sequence >= 3 then
            return create_detection_result(true, 85, "slow_spin", 4, data.last_good_angle or 0)
        end
    else
        data.spin_sequence = 0
    end
    
    return create_detection_result(false, 0, "none", 0)
end

-- ===========================
-- NEVERLOSE PITCH EXPLOIT DETECTION
-- ===========================

-- Pitch exploit detection
local function detect_pitch_exploit(player, data)
    local pitch = entity.get_prop(player, "m_angEyeAngles[0]")
    local yaw = entity.get_prop(player, "m_angEyeAngles[1]")
    
    if not pitch or not yaw then 
        return create_detection_result(false, 0, "none", 0)
    end
    
    if not data.pitch_history then data.pitch_history = {} end
    
    table.insert(data.pitch_history, 1, {
        pitch = pitch,
        yaw = yaw,
        tick = globals.tickcount()
    })
    if #data.pitch_history > 10 then table.remove(data.pitch_history) end
    
    if #data.pitch_history < 3 then 
        return create_detection_result(false, 0, "none", 0)
    end
    
    local current = data.pitch_history[1]
    local prev = data.pitch_history[2]
    local older = data.pitch_history[3]
    
    -- NEW: Detect fake-up pitch (89 degrees)
    if math.abs(pitch - 89) < 2 then
        return create_detection_result(true, 97, "fake_up", 5, data.last_good_angle or 0)
    end
    
    -- NEW: Detect fake-down pitch (-89 degrees)
    if math.abs(pitch + 89) < 2 then
        return create_detection_result(true, 97, "fake_down", 5, data.last_good_angle or 0)
    end
    
    -- Rapid pitch oscillation (existing but improved threshold)
    local pitch_changes = 0
    local total_pitch_delta = 0
    
    for i = 1, math.min(3, #data.pitch_history - 1) do
        local delta = math.abs(data.pitch_history[i].pitch - data.pitch_history[i+1].pitch)
        total_pitch_delta = total_pitch_delta + delta
        if delta > 40 then
            pitch_changes = pitch_changes + 1
        end
    end
    
    -- Lower threshold for better detection
    if pitch_changes >= 2 and total_pitch_delta > 100 then
        return create_detection_result(true, 94, "pitch_oscillation", 6, data.last_good_angle or 0)
    end
    
    -- NEW: Zero pitch during shot
    if math.abs(pitch) < 3 then
        local weapon = entity.get_player_weapon(player)
        if weapon then
            local last_shot = entity.get_prop(weapon, "m_fLastShotTime")
            if last_shot and (globals.curtime() - last_shot) < 0.15 then
                return create_detection_result(true, 96, "zero_pitch_shot", 5, data.last_good_angle or 0)
            end
        end
    end
    
    -- Extreme pitch during engagement
    if math.abs(pitch) > 85 then
        local weapon = entity.get_player_weapon(player)
        if weapon then
            local last_shot = entity.get_prop(weapon, "m_fLastShotTime")
            if last_shot and (globals.curtime() - last_shot) < 0.2 then
                return create_detection_result(true, 91, "extreme_pitch", 4, data.last_good_angle or 0)
            end
        end
    end
    
    -- NEW: Switch pitch detection (up/down/up pattern)
    if #data.pitch_history >= 4 then
        local p1, p2, p3, p4 = 
            data.pitch_history[1].pitch,
            data.pitch_history[2].pitch,
            data.pitch_history[3].pitch,
            data.pitch_history[4].pitch
        
        -- Check for alternating pattern
        local diff1 = p1 - p2
        local diff2 = p2 - p3
        local diff3 = p3 - p4
        
        if (diff1 > 45 and diff2 < -45) or (diff1 < -45 and diff2 > 45) then
            return create_detection_result(true, 92, "switch_pitch", 5, data.last_good_angle or 0)
        end
    end
    
    return create_detection_result(false, 0, "none", 0)
end

-- Choke detection (ping-aware with scoring)
local function detect_defensive_choke(player, data)
    local sim_time = entity.get_prop(player, "m_flSimulationTime")
    local old_sim_time = entity.get_prop(player, "m_flOldSimulationTime")
    
    if not sim_time or not old_sim_time then 
        return create_detection_result(false, 0, "none", 0)
    end
    
    local choke = math.floor((sim_time - old_sim_time) / globals.tickinterval())
    local ping = get_player_ping(player)
    
    -- Store choke history
    if not data.choke_pattern_history then
        data.choke_pattern_history = {}
    end
    
    table.insert(data.choke_pattern_history, 1, choke)
    if #data.choke_pattern_history > 16 then
        table.remove(data.choke_pattern_history)
    end
    
    local instant_threshold = ping < 100 and 15 or 18
    local spike_threshold = ping < 100 and 12 or 15
    
    -- Instant defensive
    if choke >= instant_threshold then
        return create_detection_result(true, 92, "choke_instant", 6, data.last_good_angle or 0)
    end
    
    -- Choke spike
    if #data.choke_pattern_history >= 4 then
        local recent_avg = (data.choke_pattern_history[2] + data.choke_pattern_history[3] + data.choke_pattern_history[4]) / 3
        
        if recent_avg < 3 and choke > spike_threshold then
            return create_detection_result(true, 87, "choke_spike", 5, data.last_good_angle or 0)
        end
        
        -- Jitter pattern
        local variance = 0
        for i = 1, 4 do
            variance = variance + math.abs(data.choke_pattern_history[i] - recent_avg)
        end
        variance = variance / 4
        
        if variance > 6 and choke > 10 then
            data.choke_jitter_detected = true
            return create_detection_result(true, 83, "choke_jitter", 4, data.last_good_angle or 0)
        end
    end
    
    return create_detection_result(false, 0, "none", 0)
end

local function predict_body_yaw_update(player, data)
    local body_yaw = entity.get_prop(player, "m_flPoseParameter", 11)
    if not body_yaw then return false, nil end
    
    body_yaw = body_yaw * 120 - 60
    
    if not data.body_yaw_history then
        data.body_yaw_history = {}
    end
    
    table.insert(data.body_yaw_history, 1, {
        value = body_yaw,
        time = globals.curtime(),
        tick = globals.tickcount()
    })
    if #data.body_yaw_history > 10 then
        table.remove(data.body_yaw_history)
    end
    
    if #data.body_yaw_history < 3 then return false, nil end
    
    local current = data.body_yaw_history[1]
    local prev = data.body_yaw_history[2]
    local older = data.body_yaw_history[3]
    
    -- Detect body yaw flip pattern
    local delta1 = current.value - prev.value
    local delta2 = prev.value - older.value
    
    -- Opposite direction deltas = flip pattern
    if (delta1 > 30 and delta2 < -30) or (delta1 < -30 and delta2 > 30) then
        -- Predict next flip
        local predicted_angle = current.value > 0 and -58 or 58
        local base_confidence = 20
        local adjusted_conf = base_confidence * (data.velocity_reliability or 0.5)
        data.confidence = math.min(100, data.confidence + adjusted_conf)
        return true, predicted_angle
    end
    
    -- Consistent movement in one direction
    if math.abs(delta1) > 20 and math.abs(delta2) > 20 then
        if (delta1 > 0 and delta2 > 0) or (delta1 < 0 and delta2 < 0) then
            -- Moving consistently, predict continuation
            local predicted_angle = delta1 > 0 and 58 or -58
            local base_confidence = 15
            local adjusted_conf = base_confidence * (data.velocity_reliability or 0.5)
            data.confidence = math.min(100, data.confidence + adjusted_conf)
            return true, predicted_angle
        end
    end
    
    return false, nil
end

-- ===========================
-- VELOCITY CONFIDENCE TRACKING
-- ===========================
local function update_velocity_confidence(player, data, hit_success)
    if not data.velocity_confidence then
        data.velocity_confidence = 0.5  -- Start at 50%
    end
    
    local vx, vy = get_cached_prop(player, "m_vecVelocity", 0)
    local speed = (vx and vy) and math.sqrt(vx*vx + vy*vy) or 0
    
    -- Only update confidence if velocity-based resolution was used
    if data.last_resolve_method == "velocity" then
        if hit_success then
            -- Boost confidence
            data.velocity_confidence = math.min(1.0, data.velocity_confidence + 0.1)
        else
            -- Reduce confidence
            data.velocity_confidence = math.max(0.1, data.velocity_confidence - 0.15)
        end
    end
    
    -- Store for use in resolve_by_velocity_advanced
    data.velocity_reliability = data.velocity_confidence
    
    return data.velocity_confidence
end

-- ===========================
-- STRAFE CONTINUATION PREDICTION
-- ===========================
local function predict_strafe_continuation(player, data)
    if not data.velocity_history then return nil end
    
    local history = data.velocity_history:get_all()
    if not history or #history < 3 then return nil end
    
    local vel1 = history[1]
    local vel2 = history[2]
    local vel3 = history[3]
    
    if not vel1 or not vel2 or not vel3 then return nil end
    
    -- Calculate strafe angle change
    local angle1 = math.deg(math.atan2(vel1.y, vel1.x))
    local angle2 = math.deg(math.atan2(vel2.y, vel2.x))
    local angle3 = math.deg(math.atan2(vel3.y, vel3.x))
    
    local delta1 = normalize_angle(angle1 - angle2)
    local delta2 = normalize_angle(angle2 - angle3)
    
    -- If strafe direction is consistent, predict continuation
    if math.abs(delta1 - delta2) < 15 then
        -- Predict next strafe direction
        local predicted_delta = (delta1 + delta2) / 2
        
        -- Determine desync side based on strafe curve
        if predicted_delta > 5 then
            return -1  -- Strafing left = desync right
        elseif predicted_delta < -5 then
            return 1   -- Strafing right = desync left
        end
    end
    
    return nil
end

-- ===========================
-- VELOCITY STABILITY ANALYSIS
-- ===========================
local function is_velocity_stable(player, data)
    if not data.velocity_history then return false end
    
    local history = data.velocity_history:get_all()
    if not history or #history < 4 then return false end
    
    local speeds = {}
    for i = 1, 4 do
        local vel = history[i]
        if vel then
            speeds[i] = math.sqrt(vel.x^2 + vel.y^2)
        else
            return false
        end
    end
    
    local avg = (speeds[1] + speeds[2] + speeds[3] + speeds[4]) / 4
    local variance = 0
    for i = 1, 4 do
        variance = variance + (speeds[i] - avg)^2
    end
    variance = variance / 4
    
    -- Low variance = stable velocity
    return variance < 100
end

local function resolve_by_velocity_advanced(player, data)
    local vx, vy, vz = get_cached_prop(player, "m_vecVelocity", 0)
    if not vx or not vy then return false, nil end
    
    local speed = math.sqrt(vx*vx + vy*vy)

    local velocity_stable = is_velocity_stable(player, data)
    if not velocity_stable and speed > 100 then
        -- Unstable velocity = lower confidence in velocity-based resolution
        data.confidence = math.max(40, data.confidence - 10)
    end
    
    -- Initialize velocity tracking
    if not data.velocity_pattern then
        data.velocity_pattern = {}
    end
    
    table.insert(data.velocity_pattern, 1, {
        x = vx,
        y = vy,
        z = vz,
        speed = speed,
        time = globals.curtime(),
        tick = globals.tickcount()
    })
    if #data.velocity_pattern > 8 then
        table.remove(data.velocity_pattern)
    end
    
    if speed < 5 then return false, nil end
    
    local entity_ptr = get_entity_address(player)
    if not entity_ptr then return false, nil end
    
    local anim_state = get_anim_state(entity_ptr)
    if not anim_state then return false, nil end
    
    local move_yaw = anim_state.flMoveYaw
    local feet_yaw = anim_state.flGoalFeetYaw
    
    -- Calculate velocity angle
    local vel_angle = math.deg(math.atan2(vy, vx))
    local angle_diff_to_feet = normalize_angle(vel_angle - feet_yaw)
    
    -- Detect velocity change patterns
    local vel_stable = true
    local vel_variance = 0
    
    if #data.velocity_pattern >= 3 then
        local avg_speed = 0
        for i = 1, 3 do
            avg_speed = avg_speed + data.velocity_pattern[i].speed
        end
        avg_speed = avg_speed / 3
        
        for i = 1, 3 do
            vel_variance = vel_variance + math.abs(data.velocity_pattern[i].speed - avg_speed)
        end
        vel_variance = vel_variance / 3
        
        if vel_variance > 50 then
            vel_stable = false
        end
    end
    
    -- Detect strafe type
    local strafe_type = "none"
    local is_strafing = math.abs(angle_diff_to_feet) > 45 and math.abs(angle_diff_to_feet) < 135
    
    if is_strafing then
        if speed > 220 then
            strafe_type = "fast_strafe"  -- Fast strafing (hard to hit)
        elseif speed > 150 then
            strafe_type = "normal_strafe"
        else
            strafe_type = "slow_strafe"
        end
    end
    
    -- STRATEGY 1: Fast strafing (most predictable)
    if strafe_type == "fast_strafe" then
        -- Fast strafe = max desync opposite to strafe direction
        local side = angle_diff_to_feet > 0 and -1 or 1
        
        -- Check if they're air-strafing (even more predictable)
        local flags = entity.get_prop(player, "m_fFlags")
        local is_airborne = flags and bit.band(flags, 1) == 0
        
        if is_airborne then
            local base_confidence = 30
            local adjusted_conf = base_confidence * (data.velocity_reliability or 0.5)
            data.confidence = math.min(100, data.confidence + adjusted_conf)
            return true, side * 60  -- Max desync in air
        else
            local base_confidence = 25
            local adjusted_conf = base_confidence * (data.velocity_reliability or 0.5)
            data.confidence = math.min(100, data.confidence + adjusted_conf)
            return true, side * 58
        end
    end
    
    -- STRATEGY 2: Normal strafing
    if strafe_type == "normal_strafe" then
        local side = angle_diff_to_feet > 0 and -1 or 1
        local base_confidence = 20
        local adjusted_conf = base_confidence * (data.velocity_reliability or 0.5)
        data.confidence = math.min(100, data.confidence + adjusted_conf)
        return true, side * 55
    end
    
    -- STRATEGY 3: Slow strafe (crouch strafing)
    if strafe_type == "slow_strafe" then
        local side = angle_diff_to_feet > 0 and -1 or 1
        
        -- Check if crouching
        local flags = entity.get_prop(player, "m_fFlags")
        local is_ducking = flags and bit.band(flags, 2) ~= 0
        
        if is_ducking then
            -- Crouch strafing = reduced desync
            local base_confidence = 22
            local adjusted_conf = base_confidence * (data.velocity_reliability or 0.5)
            data.confidence = math.min(100, data.confidence + adjusted_conf)
            return true, side * 45
        else
            local base_confidence = 18
            local adjusted_conf = base_confidence * (data.velocity_reliability or 0.5)
            data.confidence = math.min(100, data.confidence + adjusted_conf)
            return true, side * 50
        end
    end
    
    -- STRATEGY 4: Running forward/backward
    if move_yaw > 175 or move_yaw < -175 then
        -- Running backwards = likely faking
        local body_yaw = entity.get_prop(player, "m_flPoseParameter", 11)
        if body_yaw then
            body_yaw = body_yaw * 120 - 60
            
            -- Uses reliable angles if available
            if data.reliable_angles then
                if body_yaw > 0 and #data.reliable_angles.left_angles > 0 then
                    local sum = 0
                    for i = 1, math.min(3, #data.reliable_angles.left_angles) do
                        sum = sum + data.reliable_angles.left_angles[i]
                    end
                    local avg = sum / math.min(3, #data.reliable_angles.left_angles)
                    local base_confidence = 20
                    local adjusted_conf = base_confidence * (data.velocity_reliability or 0.5)
                    data.confidence = math.min(100, data.confidence + adjusted_conf)
                    return true, avg
                elseif body_yaw < 0 and #data.reliable_angles.right_angles > 0 then
                    local sum = 0
                    for i = 1, math.min(3, #data.reliable_angles.right_angles) do
                        sum = sum + data.reliable_angles.right_angles[i]
                    end
                    local avg = sum / math.min(3, #data.reliable_angles.right_angles)
                    local base_confidence = 20
                    local adjusted_conf = base_confidence * (data.velocity_reliability or 0.5)
                    data.confidence = math.min(100, data.confidence + adjusted_conf)
                    return true, avg
                end
            end
            
            -- Fallback
            local base_confidence = 15
            local adjusted_conf = base_confidence * (data.velocity_reliability or 0.5)
            data.confidence = math.min(100, data.confidence + adjusted_conf)
            return true, (body_yaw > 0 and -55 or 55)
        end
        
    elseif math.abs(move_yaw) < 15 then
        -- Running forward with velocity jitter = AA indicator
        if not vel_stable and vel_variance > 50 then
            local body_yaw = entity.get_prop(player, "m_flPoseParameter", 11)
            if body_yaw then
                body_yaw = body_yaw * 120 - 60
                local base_confidence = 16
                local adjusted_conf = base_confidence * (data.velocity_reliability or 0.5)
                data.confidence = math.min(100, data.confidence + adjusted_conf)
                return true, (body_yaw > 0 and -58 or 58)
            end
        end
    end
    
    -- STRATEGY 5: Velocity acceleration analysis (NEW)
    if #data.velocity_pattern >= 4 then
        local recent_accel = data.velocity_pattern[1].speed - data.velocity_pattern[2].speed
        local prev_accel = data.velocity_pattern[2].speed - data.velocity_pattern[3].speed
        
        -- Detect sudden direction change (180° flip)
        local recent_dir = math.deg(math.atan2(data.velocity_pattern[1].y, data.velocity_pattern[1].x))
        local prev_dir = math.deg(math.atan2(data.velocity_pattern[2].y, data.velocity_pattern[2].x))
        local dir_change = math.abs(normalize_angle(recent_dir - prev_dir))
        
        if dir_change > 150 and speed > 100 then
            -- Just reversed direction = likely using opposite desync now
            if data.last_resolved_side then
                local new_side = -data.last_resolved_side
                data.last_resolved_side = new_side
                local base_confidence = 18
                local adjusted_conf = base_confidence * (data.velocity_reliability or 0.5)
                data.confidence = math.min(100, data.confidence + adjusted_conf)
                return true, new_side * 58
            end
        end
    end

    -- STRATEGY 6: Strafe continuation prediction
    local strafe_prediction = predict_strafe_continuation(player, data)
    if strafe_prediction then
        data.confidence = math.min(100, data.confidence + 20)
        data.last_resolved_side = strafe_prediction
        return true, strafe_prediction * 58
    end
    
    return false, nil
end

local function resolve_standing_improved(player, data, lby)
    if data.standing_ticks < 16 then return false, nil end
    
    -- ✅ FIXED: Only skip fakeduck (duck_amount > 0.9), not normal crouch
    local flags = entity.get_prop(player, "m_fFlags")
    if flags and bit.band(flags, 2) ~= 0 then
        local duck_amount = entity.get_prop(player, "m_flDuckAmount")
        if duck_amount and duck_amount > 0.9 then
            -- Only skip on FULL duck (fakeduck)
            return false, nil
        end
    end
    
    local vx, vy = get_cached_prop(player, "m_vecVelocity", 0)
    local speed = (vx and vy) and math.sqrt(vx*vx + vy*vy) or 0
    
    -- Micro-movement nullification
    if speed > 0.1 and speed < 1.5 then
        speed = 0
        data.standing_ticks = data.standing_ticks + 1
    end
    
    if speed > 1.5 then
        data.standing_ticks = 0
        return false, nil
    end
    
    -- Initialize standing LBY history
    if not data.standing_lby_history then
        data.standing_lby_history = {}
    end
    
    table.insert(data.standing_lby_history, 1, {
        lby = lby,
        tick = globals.tickcount(),
        time = globals.curtime()
    })
    if #data.standing_lby_history > 8 then
        table.remove(data.standing_lby_history)
    end
    
    -- Get body yaw (actual desync indicator)
    local body_yaw = entity.get_prop(player, "m_flPoseParameter", 11)
    if body_yaw then
        body_yaw = body_yaw * 120 - 60
    end
    
    -- ✅ FIX 1: Detect LBY update happening RIGHT NOW
    if #data.standing_lby_history >= 2 then
        local current_lby = data.standing_lby_history[1].lby
        local prev_lby = data.standing_lby_history[2].lby
        local lby_change = math.abs(angle_diff(current_lby, prev_lby))
        
        -- LBY just updated
        if lby_change > 25 then
            -- ✅ CRITICAL FIX: Body yaw shows TRUE side during LBY update
            local side = 0
            if body_yaw and math.abs(body_yaw) > 10 then
                -- ✅ CORRECT: Resolve OPPOSITE of body yaw
                side = body_yaw > 0 and -1 or 1
            else
                -- Fallback to LBY
                side = current_lby > 0 and -1 or 1
            end
            
            data.confidence = 98
            data.last_lby_update_time = globals.curtime()
            data.lby_update_tick = globals.tickcount()
            data.lby_just_updated = true
            
            -- Store angle for next few ticks
            data.standing_locked_angle = side * 60
            data.standing_lock_until = globals.tickcount() + 8  -- ✅ Extended to 8 ticks
            
            return true, side * 60
        end
    end
    
    -- ✅ FIX 2: Use locked angle for 8 ticks after LBY update
    if data.standing_locked_angle and data.standing_lock_until then
        if globals.tickcount() <= data.standing_lock_until then
            data.confidence = 96
            return true, data.standing_locked_angle
        else
            -- Lock expired
            data.standing_locked_angle = nil
            data.standing_lock_until = nil
        end
    end
    
    -- ✅ FIX 3: PREDICT LBY update (0.9-1.2s window)
    local time_standing = data.standing_ticks * globals.tickinterval()
    local time_since_last_update = globals.curtime() - (data.last_lby_update_time or 0)
    
    -- LBY updates every ~1.1 seconds when standing
    local lby_cycle_time = 1.1
    local time_in_cycle = time_since_last_update % lby_cycle_time
    
    -- PREDICT: LBY will update in next 0.3 seconds
    if time_in_cycle >= 0.8 and time_in_cycle <= 1.1 then
        local side = 0
        if body_yaw and math.abs(body_yaw) > 10 then
            -- ✅ CORRECT: Opposite of body yaw
            side = body_yaw > 0 and -1 or 1
        else
            side = lby > 0 and -1 or 1
        end
        
        data.confidence = 92
        data.lby_update_predicted = true
        return true, side * 58
    end
    
    -- ✅ CORRECTED LOGIC FOR STANDING
    -- Early standing (16-30 ticks)
    if data.standing_ticks >= 16 and data.standing_ticks < 30 then
        local side = 0
        
        if body_yaw and math.abs(body_yaw) > 10 then
            -- ✅ CORRECT: Opposite of body yaw
            side = body_yaw > 0 and -1 or 1
            data.confidence = 78
            return true, side * 55
        else
            side = lby > 0 and -1 or 1
            data.confidence = 70
            return true, side * 52
        end
    end
    
    -- Medium standing (30-50 ticks)
    if data.standing_ticks >= 30 and data.standing_ticks < 50 then
        local side = 0
        
        if body_yaw and math.abs(body_yaw) > 10 then
            side = body_yaw > 0 and -1 or 1
            data.confidence = 88
            return true, side * 58
        else
            side = lby > 0 and -1 or 1
            data.confidence = 82
            return true, side * 55
        end
    end
    
    -- Long standing (50+ ticks)
    if data.standing_ticks >= 50 then
        local side = 0
        
        if body_yaw and math.abs(body_yaw) > 10 then
            side = body_yaw > 0 and -1 or 1
            data.confidence = 96
            return true, side * 60
        else
            side = lby > 0 and -1 or 1
            data.confidence = 90
            return true, side * 58
        end
    end
    
    return false, nil
end

local function analyze_lean_layer(player, data)
    local entity_ptr = get_entity_address(player)
    if not entity_ptr then return false, nil end
    
    local layers = get_anim_layers(entity_ptr)
    if not layers then return false, nil end
    
    local lean_layer = layers[12]
    local move_layer = layers[6]
    
    if not data.lean_history then
        data.lean_history = {}
    end
    
    table.insert(data.lean_history, 1, {
        weight = lean_layer.m_weight,
        cycle = lean_layer.m_cycle,
        move_weight = move_layer.m_weight,
        tick = globals.tickcount()
    })
    if #data.lean_history > 6 then
        table.remove(data.lean_history)
    end
    
    if #data.lean_history < 3 then return false, nil end
    
    local current = data.lean_history[1]
    local prev = data.lean_history[2]
    
    -- Detect lean direction from weight
    local lean_delta = current.weight - prev.weight
    
    -- Lean weight correlates with desync side
    if math.abs(lean_delta) > 0.15 then
        local side = lean_delta > 0 and 1 or -1
        data.confidence = math.min(100, data.confidence + 18)
        return true, side * 58
    end
    
    -- Check for lean-move correlation break (fake animation)
    local weight_ratio = current.weight / (current.move_weight + 0.001)
    local prev_ratio = prev.weight / (prev.move_weight + 0.001)
    
    if math.abs(weight_ratio - prev_ratio) > 3.0 then
        -- Abnormal ratio change = possible defensive
        data.suspicious_animation = true
        data.is_defensive = true
        data.defensive_ticks = 3
        return false, nil
    end
    
    return false, nil
end

local function smooth_resolved_angle(player, data, raw_angle)

    if not raw_angle or raw_angle == 0 then
        return raw_angle
    end

    if not data.angle_smooth_history then
        data.angle_smooth_history = {}
    end
    
    table.insert(data.angle_smooth_history, 1, raw_angle)
    if #data.angle_smooth_history > 2 then
        table.remove(data.angle_smooth_history)
    end
    
    -- Only smooth if we have consistent data
    if #data.angle_smooth_history >= 2 then 
        local sum = 0
        local consistent = true
        
        for i = 1, #data.angle_smooth_history do
            sum = sum + data.angle_smooth_history[i]
            
            if i > 1 then
                local diff = math.abs(data.angle_smooth_history[i] - data.angle_smooth_history[i-1])
                if diff > 30 then  -- Was 40, made more lenient
                    consistent = false
                end
            end
        end
        
        if consistent then
            local smoothed = sum / #data.angle_smooth_history
            data.confidence = math.min(100, data.confidence + 10)
            return smoothed
        end
    end
    
    return raw_angle
end

local function detect_animation_break_enhanced(player, data)
    local entity_ptr = get_entity_address(player)
    if not entity_ptr then return false end
    
    local layers = get_anim_layers(entity_ptr)
    if not layers then return false end
    
    -- Key layers to monitor
    local move_layer = layers[6]   -- Movement
    local lean_layer = layers[12]  -- Lean/balance
    local adjust_layer = layers[3] -- Body adjust
    
    -- Store layer history
    if not data.layer_history then
        data.layer_history = {}
    end
    
    table.insert(data.layer_history, 1, {
        move_weight = move_layer.m_weight,
        move_cycle = move_layer.m_cycle,
        lean_weight = lean_layer.m_weight,
        adjust_cycle = adjust_layer.m_cycle,
        tick = globals.tickcount()
    })
    if #data.layer_history > 8 then
        table.remove(data.layer_history)
    end
    
    if #data.layer_history < 2 then return false end
    
    local current = data.layer_history[1]
    local previous = data.layer_history[2]
    
    -- Detect impossible weight changes
    local weight_delta = math.abs(current.move_weight - previous.move_weight)
    local cycle_delta = math.abs(current.move_cycle - previous.move_cycle)
    
    -- Impossible animation progression
    if weight_delta > 0.5 and cycle_delta < 0.01 then
        data.suspicious_animation = true
        data.is_defensive = true
        data.defensive_ticks = 5
        return true
    end
    
    -- Cycle reversal (defensive exploit)
    if current.move_cycle < previous.move_cycle - 0.5 then
        data.is_defensive = true
        data.defensive_ticks = 4
        return true
    end
    
    -- Layer desync (move vs lean mismatch)
    local ratio_discrepancy = math.abs(
        (current.move_weight / (current.move_cycle + 0.001)) - 
        (current.lean_weight / (current.adjust_cycle + 0.001))
    )
    
    if ratio_discrepancy > 8.0 then
        data.suspicious_animation = true
        data.is_defensive = true
        data.defensive_ticks = 3
        return true
    end
    
    return false
end

local function detect_defensive_comprehensive(player, data)
    local tick = globals.tickcount()
    
    -- ✅ IMPROVED: Check cooldown FIRST
    if data.defensive_cooldown and tick < data.defensive_cooldown then
        defensive_check_cache[player] = false
        defensive_check_time[player] = tick
        return false
    end
    
    -- Rate limiting cache check
    if defensive_check_cache[player] and 
       (tick - (defensive_check_time[player] or 0)) < DEFENSIVE_CACHE_DURATION then
        return defensive_check_cache[player]
    end
    
    -- Get ping thresholds for adaptive detection
    local enemy_ping = get_player_ping(player)
    local local_ping = get_local_ping()
    local thresholds = get_ping_thresholds(enemy_ping, local_ping)
    
    -- Run all detections and collect results (optimized)
    local detections = {
        detect_eye_angle_flick(player, data),
        detect_exploit_doubletap(player, data),
        detect_defensive_spin(player, data),
        detect_pitch_exploit(player, data),
        detect_defensive_choke(player, data)
    }
    
    -- Multi-detection confirmation (reduce false positives)
    local detection_count = 0
    local total_confidence = 0
    
    for _, detection in ipairs(detections) do
        if detection.detected then
            detection_count = detection_count + 1
            total_confidence = total_confidence + detection.confidence
        end
    end
    
    -- Require at least 1 high-confidence detection OR 2+ medium detections
    local requires_confirmation = enemy_ping > 100  -- High ping = more lenient
    
    if detection_count == 0 then
        defensive_check_cache[player] = false
        defensive_check_time[player] = tick
        return false
    end
    
    local best_detection = nil
    local best_confidence = 0
    
    for _, detection in ipairs(detections) do
        if detection.detected and detection.confidence > best_confidence then
            best_detection = detection
            best_confidence = detection.confidence
        end
    end
    
    -- Confidence threshold based on ping
    local confidence_threshold = thresholds.suspicion_base + 25
    
    -- Strong single detection OR multiple weaker detections
    local confirmed = false
    if best_confidence >= confidence_threshold then
        confirmed = true
    elseif detection_count >= 2 and (total_confidence / detection_count) >= (confidence_threshold * 0.7) then
        confirmed = true
    end
    
    -- Anti-false-positive check
    -- Don't mark defensive if target just got hit (hit reactions can look like defensive)
    if data.last_shot_time and (globals.curtime() - data.last_shot_time) < 0.15 then
        -- Just shot at them, might be hit reaction not defensive
        if best_confidence < 95 then  -- Only override if not super confident
            defensive_check_cache[player] = false
            defensive_check_time[player] = tick
            return false
        end
    end
    
    -- NEW: Also check if they recently took damage from anyone
    if data.last_damage_time and (globals.curtime() - data.last_damage_time) < 0.25 then
        if best_confidence < 95 then
            defensive_check_cache[player] = false
            defensive_check_time[player] = tick
            return false
        end
    end
    
    -- ✅ NEW: Don't spam defensive detection (cooldown between detections)
    if data.last_defensive_detect and (tick - data.last_defensive_detect) < 8 then
        -- Too soon after last defensive detection (0.12s cooldown)
        defensive_check_cache[player] = false
        defensive_check_time[player] = tick
        return false
    end
    
    -- Apply best detection

    -- Apply best detection
    if confirmed and best_detection then
        data.is_defensive = true
        data.defensive_ticks = best_detection.ticks
        data.defensive_method = best_detection.method
        data.defensive_suspicion_score = best_confidence
        data.defensive_type = best_detection.method  -- ✅ Store type for resolve_defensive
        
        if best_detection.angle and best_detection.angle ~= 0 then
            data.last_good_angle = best_detection.angle
        end
        
        -- Set cooldown to prevent re-detection
        data.defensive_cooldown = tick + 32  -- 32 tick cooldown
        
        data.last_defensive_detect = tick
        defensive_check_cache[player] = true
        defensive_check_time[player] = tick
        return true
    end
    
    defensive_check_cache[player] = false
    defensive_check_time[player] = tick
    return false
end

-- ===========================
-- AIRBORNE RESOLUTION SYSTEM
-- ===========================
local function detect_airborne_state(player, data)
    local flags = entity.get_prop(player, "m_fFlags")
    if not flags then return false end
    
    local is_airborne = bit.band(flags, 1) == 0  -- FL_ONGROUND = 1
    
    -- Initialize air state tracking
    if not data.air_state then
        data.air_state = {
            is_airborne = false,
            air_ticks = 0,
            last_ground_angle = 0,
            takeoff_velocity = {x = 0, y = 0, z = 0},
            apex_reached = false,
            landing_predicted = false
        }
    end
    
    local vx, vy, vz = get_cached_prop(player, "m_vecVelocity", 0)
    if not vx or not vy or not vz then return false end
    
    -- Track air state changes
    if is_airborne and not data.air_state.is_airborne then
        -- Just took off
        data.air_state.takeoff_velocity = {x = vx, y = vy, z = vz}
        data.air_state.last_ground_angle = data.resolved_angle or 0
        data.air_state.air_ticks = 0
        data.air_state.apex_reached = false
    end
    
    data.air_state.is_airborne = is_airborne
    
    if is_airborne then
        data.air_state.air_ticks = data.air_state.air_ticks + 1
        
        -- Detect apex (when vz changes from positive to negative)
        if not data.air_state.apex_reached and vz < 0 and data.air_state.air_ticks > 3 then
            data.air_state.apex_reached = true
        end
    else
        -- Just landed
        data.air_state.air_ticks = 0
        data.air_state.apex_reached = false
    end
    
    return is_airborne
end

local function resolve_airborne(player, data)
    if not data.air_state or not data.air_state.is_airborne then
        return false, nil
    end
    
    local air_ticks = data.air_state.air_ticks
    local vx, vy, vz = get_cached_prop(player, "m_vecVelocity", 0)
    if not vx or not vy or not vz then return false, nil end
    
    local speed_2d = math.sqrt(vx*vx + vy*vy)
    local vel_angle = math.deg(math.atan2(vy, vx))
    local yaw = entity.get_prop(player, "m_angEyeAngles[1]")
    local body_yaw = entity.get_prop(player, "m_flPoseParameter", 11)
    if body_yaw then body_yaw = body_yaw * 120 - 60 end
    
    if not yaw then return false, nil end
    
    local resolved_angle = 0
    
    -- Calculate strafe direction
    local strafe_delta = normalize_angle(vel_angle - yaw)
    
    -- CRITICAL: Airborne players have limited desync control
    -- Early air (0-5 ticks) - use takeoff angle
    if air_ticks <= 3 then
        resolved_angle = data.air_state.last_ground_angle
        data.confidence = 85
        return true, resolved_angle
        
    -- Mid air (4-10 ticks) - active strafing phase
    elseif air_ticks <= 10 then
        -- Check for perfect air strafe
        if math.abs(strafe_delta) > 60 and math.abs(strafe_delta) < 120 then
            -- Perfect air strafe = very predictable
            local side = strafe_delta > 0 and -1 or 1
            data.confidence = 95
            return true, side * 60
            
        elseif speed_2d > 250 then
            -- Fast air movement = check velocity history for consistency
            if data.velocity_history then
                local history = data.velocity_history:get_all()
                if history and #history >= 3 then
                    local vel_consistency = true
                    for i = 1, 3 do
                        local vel = history[i]
                        if vel then
                            local vel_dir = math.deg(math.atan2(vel.y, vel.x))
                            if math.abs(normalize_angle(vel_dir - vel_angle)) > 30 then
                                vel_consistency = false
                                break
                            end
                        end
                    end
                    
                    if vel_consistency then
                        -- Consistent air strafe direction
                        local side = strafe_delta > 0 and -1 or 1
                        data.confidence = 88
                        return true, side * 58
                    end
                end
            end
        end
        
        -- Fallback for mid-air
        if body_yaw and math.abs(body_yaw) > 20 then
            resolved_angle = body_yaw > 0 and 55 or -55
            data.confidence = 80
            return true, resolved_angle
        end
        
    -- Late air / landing (11+ ticks) - players often reset
    else
        if vz < -300 then  -- Fast falling
            resolved_angle = 0  -- Center on landing
            data.confidence = 70
            return true, resolved_angle
        elseif body_yaw and math.abs(body_yaw) > 20 then
            resolved_angle = body_yaw > 0 and -50 or 50
            data.confidence = 75
            return true, resolved_angle
        end
    end
    
    return false, nil
end

-- ===========================
-- CROUCH DETECTION & RESOLUTION
-- ===========================
local function detect_crouch_state(player, data)
    local flags = entity.get_prop(player, "m_fFlags")
    if not flags then return false end
    
    local is_ducking = bit.band(flags, 2) ~= 0  -- FL_DUCKING = 2
    local duck_amount = entity.get_prop(player, "m_flDuckAmount")
    
    if not data.crouch_state then
        data.crouch_state = {
            is_crouching = false,
            crouch_ticks = 0,
            duck_amount = 0,
            last_duck_amount = 0,
            crouch_type = "none"  -- "full", "partial", "fakeduck"
        }
    end
    
    -- Detect crouch type
    if is_ducking or (duck_amount and duck_amount > 0.1) then
        data.crouch_state.crouch_ticks = data.crouch_state.crouch_ticks + 1
        
        if duck_amount then
            data.crouch_state.last_duck_amount = data.crouch_state.duck_amount
            data.crouch_state.duck_amount = duck_amount
            
            -- Full crouch
            if duck_amount > 0.9 then
                data.crouch_state.crouch_type = "full"
                
            -- Fakeduck detection (rapid duck changes)
            elseif math.abs(duck_amount - data.crouch_state.last_duck_amount) > 0.5 then
                data.crouch_state.crouch_type = "fakeduck"
                
            -- Partial crouch
            else
                data.crouch_state.crouch_type = "partial"
            end
        end
        
        data.crouch_state.is_crouching = true
    else
        data.crouch_state.crouch_ticks = 0
        data.crouch_state.is_crouching = false
        data.crouch_state.crouch_type = "none"
    end
    
    return data.crouch_state.is_crouching
end

local function resolve_crouching(player, data)
    if not data.crouch_state or not data.crouch_state.is_crouching then
        return false, nil
    end
    
    local crouch_type = data.crouch_state.crouch_type
    local body_yaw = entity.get_prop(player, "m_flPoseParameter", 11)
    if not body_yaw then return false, nil end
    body_yaw = body_yaw * 120 - 60
    
    local resolved_angle = 0
    
    -- Fakeduck = extremely predictable
    if crouch_type == "fakeduck" then
        resolved_angle = 0
        data.confidence = 95
        data.is_defensive = true
        data.defensive_ticks = 3
        
    -- Full crouch = reduced desync
    elseif crouch_type == "full" then
        -- ✅ CORRECT: Opposite of body yaw
        resolved_angle = body_yaw > 0 and -45 or 45
        data.confidence = 85
        
    -- Partial crouch (crouch peeking)
    elseif crouch_type == "partial" then
        -- ✅ CORRECT: Opposite of body yaw
        resolved_angle = body_yaw > 0 and -58 or 58
        data.confidence = 80
    end
    
    return true, resolved_angle
end

local function resolve_defensive(player, data)
    if not data.is_defensive or data.defensive_ticks <= 0 then
        return nil -- Use normal resolver
    end
   
    local resolved_angle = 0
   
    -- ============================================
    -- HANDLE DIFFERENT DEFENSIVE TYPES
    -- ============================================
   
    -- Type 1: YAW-BASED DEFENSIVES (flick, spin)
    if data.defensive_type == "yaw_flick" or
       data.defensive_type == "spin" or
       data.defensive_type == "slow_spin" or
       data.defensive_type == "oscillation" then
       
        -- Use last known good angle
        if data.last_good_angle and data.last_good_angle ~= 0 then
            resolved_angle = data.last_good_angle
           
            -- Apply flick compensation
            if data.flick_direction then
                resolved_angle = resolved_angle + (data.flick_direction * -60)
            end
           
            -- For spin, predict next rotation
            if data.defensive_type == "spin" or data.defensive_type == "slow_spin" then
                if data.spin_direction then
                    -- Counter-rotate
                    resolved_angle = resolved_angle - (data.spin_direction * 45)
                end
            end
           
            data.confidence = 90
            return normalize_angle(resolved_angle)
        end
    end
   
    -- Type 2: PITCH-BASED DEFENSIVES (zero, custom, switch)
    if data.defensive_type == "zero_pitch" or
       data.defensive_type == "custom_pitch" or
       data.defensive_type == "switch_pitch" then
       
        -- For pitch defensives, use last known good angle
        if data.last_good_angle and data.last_good_angle ~= 0 then
            resolved_angle = data.last_good_angle
            data.confidence = 85
            return normalize_angle(resolved_angle)
        end
       
        -- Fallback: Use LBY
        if data.last_lby then
            local side = data.last_lby > 0 and -1 or 1
            data.confidence = 75
            return side * 58
        end
    end
   
    -- Type 3: METASET-SPECIFIC (negative simtime, teleport)
    if data.defensive_type == "metaset_primary" or
       data.defensive_type == "metaset_teleport" then
       
        -- Use last known good angle (most reliable)
        if data.last_good_angle and data.last_good_angle ~= 0 then
            resolved_angle = data.last_good_angle
            data.confidence = 95
            return normalize_angle(resolved_angle)
        end
    end
   
    -- ============================================
    -- IMPROVED FALLBACK LOGIC (Priority System)
    -- ============================================
    
    -- Priority 1: Last good angle with freshness check
    if data.last_good_angle and data.last_good_angle ~= 0 then
        local ticks_old = globals.tickcount() - (data.last_good_angle_tick or 0)
        if ticks_old < 16 then  -- Only use if less than 16 ticks old (0.25s)
            data.confidence = 85
            return normalize_angle(data.last_good_angle)
        end
    end
    
    -- Priority 2: Shot snapshot (if recent)
    if data.shot_snapshot_angle and data.shot_snapshot_time then
        local time_diff = globals.curtime() - data.shot_snapshot_time
        if time_diff < 0.4 then  -- Valid for 0.4 seconds
            data.confidence = 80
            return normalize_angle(data.shot_snapshot_angle)
        end
    end
    
    -- Priority 3: LBY opposite (defensive usually flips)
    if data.last_lby then
        local side = data.last_lby > 0 and -1 or 1
        data.confidence = 70
        return side * 58
    end
    
    -- Priority 4: Current LBY
    local lby = entity.get_prop(player, "m_flLowerBodyYawTarget")
    if lby then
        local side = lby > 0 and -1 or 1
        data.confidence = 60
        return side * 55
    end
    
    -- Priority 5: Any stored resolved angle
    if data.resolved_angle and data.resolved_angle ~= 0 then
        data.confidence = 55
        return normalize_angle(data.resolved_angle)
    end
    
    -- Last resort: center
    data.confidence = 50
    return 0
end

-- ===========================
-- INTELLIGENT BRUTEFORCE
-- ===========================
local function intelligent_bruteforce(player, data)
    -- Analyze which bruteforce mode works best against this player
    local best_mode = "sequential"
    local best_success = 0
    
    for mode, pattern in pairs(data.brute_patterns) do
        if pattern.success_rate > best_success then
            best_success = pattern.success_rate
            best_mode = mode
        end
    end
    
    -- Adaptive phase count based on player behavior
    local base_phases = ui.get(ui_elements.brute_phases)
    local adaptive_phases = base_phases
    
    if data.hit_rate < 0.2 then
        adaptive_phases = math.min(7, base_phases + 2)  -- More aggressive
    elseif data.hit_rate > 0.6 then
        adaptive_phases = math.max(2, base_phases - 1)  -- More precise
    end
    
    return best_mode, adaptive_phases
end

-- ===========================
-- LAYER CORRELATION ANALYSIS
-- ===========================
local function analyze_layer_correlations(player, data)
    local entity_ptr = get_entity_address(player)
    if not entity_ptr then return {} end
    
    local layers = get_anim_layers(entity_ptr)
    if not layers then return {} end
    
    local correlations = {}
    
    -- Analyze relationship between different animation layers
    for i = 0, 12 do  -- Check all relevant layers
        local layer = layers[i]
        if layer then
            local weight_cycle_ratio = layer.m_weight / (layer.m_cycle + 0.001)
            local playback_velocity = layer.m_playback_rate * 1000
            
            correlations[i] = {
                weight_cycle_ratio = weight_cycle_ratio,
                playback_velocity = playback_velocity,
                activity = layer.m_activity
            }
        end
    end
    
    -- Detect abnormal layer relationships (indicative of fake animations)
    local move_layer = correlations[6]
    local lean_layer = correlations[12]
    
    if move_layer and lean_layer then
        local ratio_discrepancy = math.abs(
            move_layer.weight_cycle_ratio - lean_layer.weight_cycle_ratio
        )
        
        if ratio_discrepancy > 5.0 then  -- Threshold for fake animation detection
            data.suspicious_animation = true
        end
    end
    
    data.layer_correlations = correlations
    return correlations
end

-- ===========================
-- PERFORMANCE ANALYTICS
-- ===========================
local function update_resolver_analytics(player, data, hit_success, method_used)

    if not data.analytics then
        data.analytics = {
            method_success = {},
            angle_success = {},
            timing_success = {},
            total_resolves = 0,
            successful_resolves = 0,
            overall_success_rate = 0
        }
    end
    
    data.analytics.total_resolves = data.analytics.total_resolves + 1
    
    if hit_success then
        data.analytics.successful_resolves = data.analytics.successful_resolves + 1
        
        -- Track which methods are working
        data.analytics.method_success[method_used] = 
            (data.analytics.method_success[method_used] or 0) + 1
        data.last_successful_method = method_used
    else
        data.last_failed_method = method_used
    end
    
    -- Calculate real-time success rates
    data.analytics.overall_success_rate = 
        data.analytics.successful_resolves / math.max(1, data.analytics.total_resolves)
end

-- ===========================
-- ADAPTIVE LEARNING SYSTEM
-- ===========================
local function adaptive_learning(player, data)
    -- Only learn from substantial sample size
    if data.analytics.total_resolves < 5 then return end  -- Lowered from 10 to 5
    
    local success_rate = data.analytics.overall_success_rate
    
    -- ✅ NEW: More aggressive adaptation
    if success_rate < 0.3 then
        -- Very poor performance - MAJOR changes
        data.learning_phase = "experimental"
        data.brute_aggression = math.min(1.0, data.brute_aggression + 0.2)  -- Bigger jump
        
        -- Reset method weights to default (current strategy not working)
        data.method_weights = {
            lby_delta = 0.25,
            movement = 0.20,
            animation = 0.15,
            velocity = 0.15,
            historical = 0.15,
            pattern = 0.10
        }
        
    elseif success_rate < 0.5 then
        -- Poor performance - try different approach
        data.learning_phase = "experimental"
        data.brute_aggression = math.min(1.0, data.brute_aggression + 0.15)
        
    elseif success_rate > 0.75 then
        -- Excellent performance - refine current approach
        data.learning_phase = "refinement"
        data.brute_aggression = math.max(0.3, data.brute_aggression - 0.08)
        
        -- ✅ NEW: Boost weights of successful methods
        if data.last_successful_method and data.method_weights[data.last_successful_method] then
            data.method_weights[data.last_successful_method] = 
                math.min(0.4, data.method_weights[data.last_successful_method] * 1.2)
            
            -- Normalize weights
            local total = 0
            for _, w in pairs(data.method_weights) do total = total + w end
            for method, w in pairs(data.method_weights) do
                data.method_weights[method] = w / total
            end
        end
        
    else
        -- Moderate performance - continue current strategy
        data.learning_phase = "stable"
    end
    
    -- Estimate player playstyle based on multiple factors
    local movement_variability = data.patterns.variability or 0
    local avg_speed = 0
    local speed_samples = 0
    
    if data.velocity_pattern and #data.velocity_pattern > 0 then
        for i = 1, math.min(5, #data.velocity_pattern) do
            avg_speed = avg_speed + data.velocity_pattern[i].speed
            speed_samples = speed_samples + 1
        end
        avg_speed = avg_speed / speed_samples
    end
    
    -- Classify playstyle
    if movement_variability > 30 and avg_speed > 180 then
        data.player_profile.playstyle = "aggressive"
    elseif movement_variability < 10 and avg_speed < 80 then
        data.player_profile.playstyle = "passive"
    else
        data.player_profile.playstyle = "balanced"
    end
    
    -- Track desync habits
    if data.patterns.oscillation then
        data.player_profile.desync_habits.jitter = true
    end
    if data.patterns.consistent_side ~= 0 then
        data.player_profile.desync_habits.consistent_side = data.patterns.consistent_side
    end
    
    -- Adjust resolver aggression based on playstyle
    if data.player_profile.playstyle == "aggressive" then
        -- Aggressive players = predict more, brute less
        data.method_weights.velocity = math.min(0.3, data.method_weights.velocity * 1.2)
        data.method_weights.pattern = math.min(0.2, data.method_weights.pattern * 1.3)
        
    elseif data.player_profile.playstyle == "passive" then
        -- Passive players = use LBY more
        data.method_weights.lby_delta = math.min(0.35, data.method_weights.lby_delta * 1.2)
        data.method_weights.historical = math.min(0.2, data.method_weights.historical * 1.1)
    end
    
    -- Normalize weights again
    local total = 0
    for _, w in pairs(data.method_weights) do total = total + w end
    for method, w in pairs(data.method_weights) do
        data.method_weights[method] = w / total
    end
end

-- ===========================
-- LEGIT PLAYER DETECTION (IMPROVED v4 - OPTIMIZED)
-- ===========================
local function is_using_antiaim(player)
    if not player or not entity.is_alive(player) then return false end
    
    local data = init_player_data(player)
    
    -- Once detected as AA user, stay as AA user
    if data.aa_detected then
        return true
    end
    
    -- Cache both positive AND negative results
    if data.aa_check_result ~= nil then
        if globals.tickcount() - (data.aa_check_time or 0) < AA_CHECK_CACHE_DURATION then
            return data.aa_check_result
        end
    end
    
    data.aa_check_time = globals.tickcount()
    
    -- Simple detection
    local eye_yaw = entity.get_prop(player, "m_angEyeAngles[1]")
    local body_yaw = entity.get_prop(player, "m_flLowerBodyYawTarget")
    
    if eye_yaw and body_yaw then
        local delta = math.abs(angle_diff(eye_yaw, body_yaw))
        
        if delta > 20 then
            data.aa_detected = true
            data.aa_check_result = true
            return true
        end
    end
    
    -- Cache negative result too
    data.aa_check_result = false
    return true
end

-- ===========================
-- DEFENSIVE SHOT DELAY
-- ===========================
local function apply_defensive_shot_delay(player, data)
    if not ui.get(ui_defensive_delay.enable) then
        -- Clear overrides
        data.block_shots = false
        return false
    end
    
    local should_delay = false
    
    -- Check if defensive is active
    if data.is_defensive and data.defensive_ticks > 0 then
        should_delay = true
    end
    
    -- Check if waiting for defensive to clear
    if data.defensive_wait_until and globals.tickcount() < data.defensive_wait_until then
        should_delay = true
    end
    
    if should_delay then
        -- ✅ NEW: Also force safepoint to make resolver more confident
        plist.set(player, "Override safe point", "On")
        
        -- Mark for shot blocking
        data.block_shots = true
        
        return true
    else
        -- Clear shot block
        data.block_shots = false
        plist.set(player, "Override safe point", "-")
        
        return false
    end
end

-- ===========================
-- SMART BODY AIM PRESETS (MOVE THIS UP)
-- ===========================
local smart_baim_presets = {
    ["Default"] = {
        speed_threshold = 280,
        confidence_threshold = 40,
        miss_mode = "Prefer after 1 miss",
        reset_on_hit = true,
        description = "Default preset by Tama"
    },
    ["Aggressive"] = {
        speed_threshold = 240,
        confidence_threshold = 50,
        miss_mode = "Force after 1 miss",
        reset_on_hit = true,
        description = "Best for Scout/Deagle rushes - body aims faster"
    },
    ["Defensive"] = {
        speed_threshold = 320,
        confidence_threshold = 30,
        miss_mode = "Prefer after 2 miss",
        description = "Best for AWP/Auto holding - prioritizes resolver"
    }
}


-- smart baim preset stuff
local function apply_smart_baim_preset()
    local mode = ui.get(ui_smart_baim.mode)
    local preset = smart_baim_presets[mode]
    
    if preset then
        return preset
    end
    return smart_baim_presets["Default"]
end

local function apply_smart_hitbox_override(player, data)
    if not ui.get(ui_smart_baim.enable) then
        plist.set(player, "Override prefer body aim", "-")
        plist.set(player, "Override safe point", "-")
        data.baim_reason = nil
        data.lethal_mindmg_required = nil
        return
    end
    
    local speed = get_player_speed_cached(player)
    local local_player = entity.get_local_player()
    if not local_player then return end
    
    -- check if local player has Scout
    local my_weapon = entity.get_player_weapon(local_player)
    local my_weapon_type = get_weapon_type(my_weapon)
    
    -- only apply lethal logic if using Scout or AWP
    if my_weapon_type ~= "scout" then
        -- Not using Scout/AWP - use normal body aim logic
        plist.set(player, "Override prefer body aim", "-")
        plist.set(player, "Override safe point", "-")
        data.baim_reason = "HEAD"
        data.lethal_mindmg_required = nil
        return
    end

    if not ui.get(ui_smart_baim.lethal_override_mindmg) then
        data.lethal_mindmg_required = nil
    end
    
    local enemy_health = get_cached_prop(player, "m_iHealth", 100)
    local lethal_threshold = ui.get(ui_smart_baim.lethal_threshold)
    
    -- Rest of the function stays the same...
    local is_lethal = enemy_health <= lethal_threshold
    
    if ui.get(ui_elements.debug) then
        local player_name = entity.get_player_name(player)
        client.log(string.format("[Lethal Check] %s: HP=%d, Threshold=%d, Lethal=%s, MyWeapon=%s",
            player_name, enemy_health, lethal_threshold, tostring(is_lethal), my_weapon_type))
    end
    
    data.body_aimable = is_lethal
    data.lethal_shot_available = is_lethal
    
    -- If not lethal, don't force body aim
    if not is_lethal then
        plist.set(player, "Override prefer body aim", "-")
        plist.set(player, "Override safe point", "-")
        data.baim_reason = "HEAD"
        data.lethal_mindmg_required = nil
        return
    end
    
    -- Enemy is lethal - apply body aim logic
    local lethal_mode = ui.get(ui_smart_baim.lethal_mode)
    local should_baim = false
    local force_safe = false
    local reason = nil
    
    local accuracy = calculate_shot_accuracy(player)
    local accuracy_threshold = ui.get(ui_smart_baim.accuracy_threshold)
    
    if lethal_mode == "Force body (strict)" then
        should_baim = true
        reason = "LETHAL_STRICT"
        
    elseif lethal_mode == "Prefer body (flexible)" then
        if data.confidence >= 90 and speed < 5 and accuracy >= accuracy_threshold then
            should_baim = false
            reason = "LETHAL_HEAD_OVERRIDE"
        else
            should_baim = true
            reason = "LETHAL_PREFER"
        end
        
    elseif lethal_mode == "Smart (adjust by accuracy)" then
        if accuracy < accuracy_threshold then
            should_baim = true
            reason = "LETHAL_SMART_LOW_ACC"
        else
            if data.confidence < 75 then
                should_baim = true
                reason = "LETHAL_SMART_LOW_CONF"
            else
                should_baim = false
                reason = "LETHAL_SMART_HIGH_ACC"
            end
        end
    end
    
    -- Enable safepoint if 2+ misses OR low accuracy
    if data.misses >= 2 or (accuracy < 70 and is_lethal) then
        force_safe = true
        reason = (reason or "LETHAL") .. "_SAFEPOINT"
    end
    
    -- Apply body aim preference
    if should_baim then
        plist.set(player, "Override prefer body aim", "Force")
    else
        plist.set(player, "Override prefer body aim", "-")
    end
    
    -- Apply safepoint
    if force_safe then
        plist.set(player, "Override safe point", "On")
    else
        plist.set(player, "Override safe point", "-")
    end

    if is_lethal and should_baim then
        local has_armor = entity.get_prop(player, "m_ArmorValue") > 0
        local buffer = has_armor and 5 or 0
        
        local kill_damage = math.min(enemy_health + buffer, 100)
        data.lethal_mindmg_required = kill_damage
        
        -- debug for lethal
        --if ui.get(ui_elements.debug) then
            --client.log(string.format("[Lethal] %dHP (armor=%s) → min dmg %d", 
                --enemy_health, tostring(has_armor), kill_damage))
        --end
    else
        data.lethal_mindmg_required = nil
    end
    data.baim_reason = reason
end

-- ===========================
-- AI RESOLVER MODE
-- ===========================
local function ai_resolve(player, data)
    -- Use all advanced systems together
    local confidence = 0
    local resolved_angle = 0
    
    -- Run all analysis systems
    analyze_desync_patterns(player, data)
    adaptive_confidence_system(player, data)
    predict_movement_trajectory(player, data)
    detect_desync_break(player, data)
    analyze_layer_correlations(player, data)
    predict_peek_behavior(player, data)
    update_weapon_priority(player, data)
    
    -- Get weighted confidence from all systems
    local weights = data.method_weights
    
    -- LBY Analysis
    local lby = entity.get_prop(player, "m_flLowerBodyYawTarget") or 0
    local lby_delta = angle_diff(lby, data.last_lby)
    
    if math.abs(lby_delta) > 35 then
        if lby_delta > 0 then
            resolved_angle = resolved_angle + (-60 * weights.lby_delta)
        else
            resolved_angle = resolved_angle + (60 * weights.lby_delta)
        end
        confidence = confidence + 25 * weights.lby_delta
    end
    
    -- Movement Analysis
    local speed = get_player_speed_cached(player)
    
    if speed > 5 then
        local entity_ptr = get_entity_address(player)
        if entity_ptr then
            local anim_state = get_anim_state(entity_ptr)
            if anim_state then
                local move_yaw = anim_state.flMoveYaw
                if move_yaw >= -180 and move_yaw < 0 then
                    resolved_angle = resolved_angle + (-40 * weights.movement)
                elseif move_yaw > 0 and move_yaw <= 180 then
                    resolved_angle = resolved_angle + (40 * weights.movement)
                end
                confidence = confidence + 20 * weights.movement
            end
        end
    end
    
    -- Pattern Analysis
    if data.patterns.consistent_side ~= 0 then
        resolved_angle = resolved_angle + (data.patterns.consistent_side * 50 * weights.pattern)
        confidence = confidence + 15 * weights.pattern
    end
    
    -- Weapon-aware resolution
    if contains(utils.safe_get_multiselect(ui_elements.advanced), "Weapon Awareness") then
        resolved_angle = weapon_aware_resolution(player, data, resolved_angle)
    end
    
    -- Context Awareness
    if data.resolver_context == "aggressive" then
        resolved_angle = resolved_angle * 1.2  -- More aggressive resolution
    elseif data.resolver_context == "defensive" then
        resolved_angle = resolved_angle * 0.8  -- More conservative
    end
    
    -- Apply AI learning aggression
    local ai_aggression = ui.get(ui_elements.ai_aggression) / 100
    resolved_angle = resolved_angle * (0.5 + ai_aggression)
    
    -- Clamp final angle
    resolved_angle = clamp(resolved_angle, -60, 60)
    confidence = clamp(confidence, 0, 100)
    
    data.confidence = confidence
    data.resolved_angle = resolved_angle
    
    return resolved_angle
end

-- ===========================
-- ANIMATION ANALYSIS
-- ===========================
local function analyze_animation_layers(player, data)
    local entity_ptr = get_entity_address(player)
    if not entity_ptr then return false end
    
    local layers = get_anim_layers(entity_ptr)
    if not layers then return false end
    
    -- Movement layer (6)
    local move_layer = layers[6]
    data.layer_data.move_weight = move_layer.m_weight
    data.layer_data.move_cycle = move_layer.m_cycle
    data.layer_data.move_playback = move_layer.m_playback_rate
    
    -- Standing layer (3)
    local stand_layer = layers[3]
    data.layer_data.stand_cycle = stand_layer.m_cycle
    data.layer_data.stand_weight = stand_layer.m_weight
    
    return true
end

local function detect_side_switch(player, data, old_record, older_record)
    if not old_record or not older_record then return false end
    
    local entity_ptr = get_entity_address(player)
    if not entity_ptr then return false end
    
    local layers = get_anim_layers(entity_ptr)
    if not layers then return false end
    
    local move_layer = layers[6]
    local weight = move_layer.m_weight
    local old_weight = old_record.layers and old_record.layers[6].m_weight or 0
    
    local playback = move_layer.m_playback_rate * 100000
    local old_playback = old_record.layers and old_record.layers[6].m_playback_rate * 100000 or 0
    local older_playback = older_record.layers and older_record.layers[6].m_playback_rate * 100000 or 0
    
    local prev_diff = older_playback - old_playback
    local curr_diff = playback - old_playback
    
    -- more reliable switch detection
    local vx, vy = get_cached_prop(player, "m_vecVelocity", 0)
    local speed = (vx and vy) and math.sqrt(vx*vx + vy*vy) or 0
    
    -- Micro-movement detection (metaset-style)
    if speed >= 1.1 and speed <= 1.4 then
        speed = 1.0
    end
    
    local is_micromoving = (speed < 1) and (data.layer_data.move_weight and data.layer_data.move_weight > 0)
    
    if is_micromoving then
        -- Metaset's micro-movement check
        local playback_check = (playback / speed * 100000) > 5.9
        if playback_check then
            return true
        end
    end
    
    -- Original weight check (improved threshold)
    if weight > 0.01 and math.abs(weight - old_weight) > 0.05 then
        return true
    end
    
    -- Enhanced playback rate check
    if math.abs(prev_diff) < 0.15 and math.abs(curr_diff) > 0.8 then
        return true
    end
    
    -- ✅ NEW: Cycle reversal detection
    local cycle = move_layer.m_cycle
    local old_cycle = old_record.layers and old_record.layers[6].m_cycle or 0
    if cycle < old_cycle - 0.5 then
        return true
    end
    
    return false
end

local function get_move_direction_side(player, data)
    local vx, vy = get_cached_prop(player, "m_vecVelocity", 0)
    if not vx or not vy then return 0 end
    
    local speed = math.sqrt(vx*vx + vy*vy)
    if speed < 1 then return 0 end
    
    local entity_ptr = get_entity_address(player)
    if not entity_ptr then return 0 end
    
    local anim_state = get_anim_state(entity_ptr)
    if not anim_state then return 0 end
    
    local move_yaw = anim_state.flMoveYaw
    
    -- Better side detection logic
    local is_backwards = move_yaw > 175 or move_yaw < -175
    local is_forward = math.abs(move_yaw) < 5
    local is_left = move_yaw >= -180 and move_yaw < -5
    local is_right = move_yaw > 5 and move_yaw <= 180
    
    -- Prioritize clear directions
    if is_right then 
        return -1 
    elseif is_left then 
        return 1 
    elseif is_backwards then 
        -- Moving backwards = likely faking opposite side
        return -1 
    elseif is_forward then
        -- Moving forward = use body yaw
        local body_yaw = entity.get_prop(player, "m_flPoseParameter", 11) * 120 - 60
        return body_yaw > 0 and -1 or 1
    end
    
    return 0
end

-- ===========================
-- DEFENSIVE AA DETECTION (ENHANCED)
-- ===========================
-- Legacy defensive detection (fallback)
local function detect_defensive(player, data)
    -- Just call comprehensive detection
    return detect_defensive_comprehensive(player, data)
end

-- ===========================
-- JIGGLE PEEK & AUTOPEEK DETECTION
-- ===========================
local function detect_peek_state(player, data)
    local vx, vy = get_cached_prop(player, "m_vecVelocity", 0)
    if not vx or not vy then return "unknown", 0 end
    
    local speed = math.sqrt(vx*vx + vy*vy)
    
    local peek = data.peek_state
    
    -- Calculate acceleration
    peek.acceleration = speed - peek.last_speed
    
    -- Calculate movement direction
    local current_direction = math.deg(math.atan2(vy, vx))
    local direction_change = math.abs(normalize_angle(current_direction - peek.last_direction))
    
    -- Track direction changes (jiggling indicator)
    if direction_change > 90 and speed > 50 then
        peek.direction_changes = peek.direction_changes + 1
    else
        peek.direction_changes = math.max(0, peek.direction_changes - 0.1)
    end
    
    -- === DETECTION LOGIC ===
    
    -- 1. JIGGLE PEEK (rapid direction changes + moderate speed)
    if peek.direction_changes > 2 and speed > 100 and speed < 220 then
        peek.peek_type = "jiggle"
        peek.peek_confidence = 90
        
    -- 2. FAST PEEK (high speed + acceleration)
    elseif speed > 220 and peek.acceleration > 50 then
        peek.peek_type = "fast_peek"
        peek.peek_confidence = 85
        
    -- 3. SHOULDER PEEK (slow peek then stop)
    elseif speed > 50 and speed < 150 and peek.acceleration < -30 then
        peek.peek_type = "shoulder"
        peek.peek_confidence = 80
        
    -- 4. WIDE PEEK (constant high speed)
    elseif speed > 200 and math.abs(peek.acceleration) < 20 then
        peek.peek_type = "wide"
        peek.peek_confidence = 75
        
    -- 5. STOP PEEK (was moving, now stopping)
    elseif peek.last_speed > 100 and speed < 30 then
        peek.peek_type = "stop"
        peek.peek_confidence = 85
        
    -- 6. HOLDING (minimal movement)
    elseif speed < 5 then
        peek.peek_type = "holding"
        peek.peek_confidence = 95
        
    else
        peek.peek_type = "moving"
        peek.peek_confidence = 60
    end
    
    -- Update tracking
    peek.last_speed = speed
    peek.last_direction = current_direction
    
    return peek.peek_type, peek.peek_confidence
end

local function resolve_peek_adaptive(player, data, peek_type, peek_confidence)
    local vx, vy = get_cached_prop(player, "m_vecVelocity", 0)
    if not vx or not vy then return false, nil end
    
    local speed = math.sqrt(vx*vx + vy*vy)
    local lby = entity.get_prop(player, "m_flLowerBodyYawTarget") or 0
    local body_yaw = entity.get_prop(player, "m_flPoseParameter", 11)
    if body_yaw then body_yaw = body_yaw * 120 - 60 end
    
    local reliable = data.reliable_angles
    
    -- === CAPTURE RELIABLE ANGLES (when NOT jiggling) ===
    if peek_type ~= "jiggle" and peek_type ~= "fast_peek" and speed > 5 and speed < 200 then
        -- ✅ This is a "stable" moment - capture the angle
        local current_angle = 0
        
        -- Use body yaw if available and reliable
        if body_yaw and math.abs(body_yaw) > 20 then
            current_angle = body_yaw
        -- Fallback to LBY delta
        elseif lby then
            current_angle = lby > 0 and -58 or 58
        end
        
        if current_angle ~= 0 then
            -- Store in appropriate bucket
            if current_angle > 0 then
                table.insert(reliable.right_angles, 1, current_angle)
                if #reliable.right_angles > 10 then
                    table.remove(reliable.right_angles)
                end
            else
                table.insert(reliable.left_angles, 1, current_angle)
                if #reliable.left_angles > 10 then
                    table.remove(reliable.left_angles)
                end
            end
            
            reliable.last_reliable_angle = current_angle
            reliable.last_reliable_tick = globals.tickcount()
        end
    end
    
    -- === NOW HANDLE DIFFERENT PEEK TYPES ===
    
    if peek_type == "jiggle" then
        -- ✅ Calculate average angles from history
        local left_avg = 0
        local right_avg = 0
        
        if #reliable.left_angles > 0 then
            local sum = 0
            for i = 1, #reliable.left_angles do
                sum = sum + reliable.left_angles[i]
            end
            left_avg = sum / #reliable.left_angles
        end
        
        if #reliable.right_angles > 0 then
            local sum = 0
            for i = 1, #reliable.right_angles do
                sum = sum + reliable.right_angles[i]
            end
            right_avg = sum / #reliable.right_angles
        end
        
        -- ✅ Determine which side they're likely using
        local resolved_angle = 0
        local method_confidence = 0
        
        -- Strategy 1: Use recent reliable angle if fresh (< 1 second old)
        local ticks_since_reliable = globals.tickcount() - reliable.last_reliable_tick
        if ticks_since_reliable < 64 and reliable.last_reliable_angle ~= 0 then
            resolved_angle = reliable.last_reliable_angle
            method_confidence = 85
            
        -- Strategy 2: Use statistical average
        elseif #reliable.left_angles > 3 or #reliable.right_angles > 3 then
            -- Use side with more samples (shows preference)
            if #reliable.left_angles > #reliable.right_angles then
                resolved_angle = left_avg
                method_confidence = 75 + (#reliable.left_angles * 2)
            else
                resolved_angle = right_avg
                method_confidence = 75 + (#reliable.right_angles * 2)
            end
            
        -- Strategy 3: Use LBY as last resort (lower confidence)
        else
            resolved_angle = lby > 0 and -58 or 58
            method_confidence = 55
        end
        
        -- ✅ Clamp confidence
        method_confidence = math.min(95, method_confidence)
        data.confidence = method_confidence
        
        return true, resolved_angle
        
    elseif peek_type == "fast_peek" then
        -- ✅ Fast peek: Use velocity-based prediction
        local vel_angle = math.deg(math.atan2(vy, vx))
        local eye_yaw = entity.get_prop(player, "m_angEyeAngles[1]")
        
        if eye_yaw then
            local delta = normalize_angle(vel_angle - eye_yaw)
            
            -- Strafing = desync opposite to strafe direction
            if math.abs(delta) > 45 and math.abs(delta) < 135 then
                -- Use historical angle if available
                if delta > 0 and #reliable.right_angles > 0 then
                    local sum = 0
                    for i = 1, math.min(3, #reliable.right_angles) do
                        sum = sum + reliable.right_angles[i]
                    end
                    local angle = sum / math.min(3, #reliable.right_angles)
                    data.confidence = 82
                    return true, angle
                    
                elseif delta < 0 and #reliable.left_angles > 0 then
                    local sum = 0
                    for i = 1, math.min(3, #reliable.left_angles) do
                        sum = sum + reliable.left_angles[i]
                    end
                    local angle = sum / math.min(3, #reliable.left_angles)
                    data.confidence = 82
                    return true, angle
                end
                
                -- Fallback to simple prediction
                local resolved = delta > 0 and 58 or -58
                data.confidence = 70
                return true, resolved
            end
        end
        
        -- Moving forward/back
        if body_yaw and math.abs(body_yaw) > 20 then
            data.confidence = 68
            return true, body_yaw > 0 and -55 or 55
        end
        
    elseif peek_type == "shoulder" then
        -- ✅ Shoulder peek: Use most recent reliable angle
        if reliable.last_reliable_angle ~= 0 then
            local ticks_old = globals.tickcount() - reliable.last_reliable_tick
            if ticks_old < 32 then
                data.confidence = 88
                return true, reliable.last_reliable_angle
            end
        end
        
        -- Fallback
        if body_yaw and math.abs(body_yaw) > 20 then
            data.confidence = 75
            return true, body_yaw > 0 and -58 or 58
        end
        
    elseif peek_type == "stop" then
        -- ✅ Just stopped: LBY is most reliable
        data.confidence = 92
        return true, lby > 0 and -60 or 60
        
    elseif peek_type == "wide" then
        -- ✅ Wide peek: Reduced desync
        local entity_ptr = get_entity_address(player)
        if entity_ptr then
            local anim_state = get_anim_state(entity_ptr)
            if anim_state then
                local move_yaw = anim_state.flMoveYaw
                
                -- Moving straight = less desync
                if math.abs(move_yaw) < 30 then
                    local angle = body_yaw and (body_yaw > 0 and -40 or 40) or 0
                    data.confidence = 78
                    return true, angle
                end
                
                -- Strafing wide
                local angle = move_yaw > 0 and 50 or -50
                data.confidence = 75
                return true, angle
            end
        end
    end
    
    return false, nil
end

-- ===========================
-- SMART RESOLVER
-- ===========================
local function smart_resolve(player, data)
    local detection = utils.safe_get_multiselect(ui_elements.detection)
    local confidence = 40
    local predicted_side = 0
    local angle_offset = 0
    
    -- Get current state
    local vx, vy = get_cached_prop(player, "m_vecVelocity", 0)
    local speed = (vx and vy) and math.sqrt(vx*vx + vy*vy) or 0
    local lby = entity.get_prop(player, "m_flLowerBodyYawTarget") or 0

    -- PRIORITY 0: Peek state detection
    local peek_type, peek_conf = detect_peek_state(player, data)
    local peek_resolved, peek_angle = resolve_peek_adaptive(player, data, peek_type, peek_conf)
    
    if peek_resolved and peek_angle then
        data.last_peek_type = peek_type
        data.resolved_angle = peek_angle
        return peek_angle
    end

    -- Enhanced movement prediction
    local vx, vy = get_cached_prop(player, "m_vecVelocity", 0)
    if vx and vy then
        local speed = math.sqrt(vx*vx + vy*vy)
        
        -- Fast strafe prediction (most reliable in HVH)
        if speed > 220 then
            local vel_angle = math.deg(math.atan2(vy, vx))
            local eye_yaw = entity.get_prop(player, "m_angEyeAngles[1]")
            
            if eye_yaw then
                local strafe_delta = normalize_angle(vel_angle - eye_yaw)
                
                -- Clear strafe = very predictable desync
                if math.abs(strafe_delta) > 60 and math.abs(strafe_delta) < 120 then
                    local predicted_angle = strafe_delta > 0 and -58 or 58
                    
                    data.confidence = 92
                    data.resolved_angle = predicted_angle
                    return predicted_angle
                end
            end
        end
    end

    -- PRIORITY 1: Comprehensive defensive detection (all methods)
    -- ✅ FIX 4: Require stronger confirmation to avoid false positives
    local defensive_detected = detect_defensive_comprehensive(player, data)
    local defensive_valid = is_valid_defensive_detection(player, data, {
        detected = defensive_detected,
        confidence = data.defensive_suspicion_score or 0
    })
    
    if defensive_detected and defensive_valid and data.defensive_ticks > 2 then
        local defensive_angle = resolve_defensive(player, data)
        if defensive_angle then
            data.resolved_angle = defensive_angle
            return defensive_angle
        end
    end
    
    -- PRIORITY 2: Airborne resolution
    detect_airborne_state(player, data)
    local is_air, air_angle = resolve_airborne(player, data)
    if is_air and air_angle then
        return air_angle
    end
    
    -- PRIORITY 3: Crouch resolution
    detect_crouch_state(player, data)
    local is_crouch, crouch_angle = resolve_crouching(player, data)
    if is_crouch and crouch_angle then
        return crouch_angle
    end
    
    -- Run advanced systems if enabled
    if contains(detection, "Pattern Recognition") then  -- cached var i think
        analyze_desync_patterns(player, data)
    end

    adaptive_confidence_system(player, data)
    predict_movement_trajectory(player, data)
    
    if contains(detection, "Desync Break Detection") then
        detect_desync_break(player, data)
    end
    
    analyze_layer_correlations(player, data)

    -- Use true LBY if fake desync detected
    if data.fake_desync_detected then
        lby = data.true_lby
    end

    if contains(detection, "Peek Prediction") then
        predict_peek_behavior(player, data)
    end

    if contains(detection, "Weapon Awareness") then
        update_weapon_priority(player, data)
    end
    
    -- LBY Analysis
    if contains(utils.safe_get_multiselect(ui_elements.detection), "LBY Analysis") then
        local lby_delta = angle_diff(lby, data.last_lby)
        
        if math.abs(lby_delta) > 35 then
            if lby_delta > 0 then
                predicted_side = -1
                confidence = confidence + 25
            else
                predicted_side = 1
                confidence = confidence + 25
            end
        end
    end
    
    -- Movement Tracking
    if contains(utils.safe_get_multiselect(ui_elements.detection), "Movement Tracking") then
        if speed > 2.0 then 
            local move_side = get_move_direction_side(player, data)
            if move_side ~= 0 then
                predicted_side = move_side
                confidence = confidence + 20
                data.moving_ticks = data.moving_ticks + 1
                data.standing_ticks = 0
            end
        else
            data.standing_ticks = data.standing_ticks + 1
            data.moving_ticks = 0
        end
    end
    
    -- Standing Detection
    if contains(utils.safe_get_multiselect(ui_elements.detection), "Standing Detection") then
        if data.standing_ticks > 32 then
            -- Use LBY more heavily when standing
            if lby > 0 then
                predicted_side = -1
                confidence = confidence + 30
            elseif lby < 0 then
                predicted_side = 1
                confidence = confidence + 30
            end
        end
    end
    
    -- Animation Analysis
    if contains(utils.safe_get_multiselect(ui_elements.detection), "Animation Analysis") then
        if analyze_animation_layers(player, data) then
            confidence = confidence + 15
        end
    end
    
    -- Pattern Recognition
    if contains(utils.safe_get_multiselect(ui_elements.detection), "Pattern Recognition") then
        if data.patterns.consistent_side ~= 0 then
            predicted_side = data.patterns.consistent_side
            confidence = confidence + 20
        end
    end

    -- PRIORITY: Body yaw prediction
    if contains(utils.safe_get_multiselect(ui_elements.detection), "Pose Parameters") then
        local body_predicted, body_angle = predict_body_yaw_update(player, data)
        if body_predicted and body_angle then
            predicted_side = body_angle > 0 and 1 or -1
            confidence = confidence + 20
            angle_offset = body_angle
        end
    end

    -- Enhanced velocity resolution
    if contains(utils.safe_get_multiselect(ui_elements.detection), "Velocity Prediction") then
        local vel_resolved, vel_angle = resolve_by_velocity_advanced(player, data)
        if vel_resolved and vel_angle then
            predicted_side = vel_angle > 0 and 1 or -1
            confidence = confidence + 25
            angle_offset = vel_angle
        end
    end

    -- Improved standing detection
    if contains(utils.safe_get_multiselect(ui_elements.detection), "Standing Detection") then
        local standing_resolved, standing_angle = resolve_standing_improved(player, data, lby)
        if standing_resolved and standing_angle then
            predicted_side = standing_angle > 0 and 1 or -1
            
            -- ✅ CRITICAL: If we have a locked angle from LBY update, use it with maximum priority
            if data.standing_locked_angle and data.standing_lock_until and globals.tickcount() <= data.standing_lock_until then
                confidence = confidence + 50  -- Massive boost for locked angles
                angle_offset = standing_angle
                
                -- Override everything else - this is the most reliable state
                data.confidence = math.min(100, confidence)
                data.resolved_angle = standing_angle
                return standing_angle  -- Return immediately, skip other detection
            else
                confidence = confidence + 35
                angle_offset = standing_angle
            end
        end
    end

    -- Lean layer analysis
    if contains(utils.safe_get_multiselect(ui_elements.detection), "Layer Weight") then
        local lean_resolved, lean_angle = analyze_lean_layer(player, data)
        if lean_resolved and lean_angle then
            predicted_side = lean_angle > 0 and 1 or -1
            confidence = confidence + 18
            angle_offset = lean_angle
        end
    end
    
    -- Micro Movement Detection
    if contains(utils.safe_get_multiselect(ui_elements.detection), "Micro Movement") and speed < 3 and speed > 0.1 then
        local entity_ptr = get_entity_address(player)
        if entity_ptr then
            local layers = get_anim_layers(entity_ptr)
            if layers then
                local move_layer = layers[6]
                local playback = move_layer.m_playback_rate * 100000
                
                if playback > 5.9 then
                    predicted_side = 1
                else
                    predicted_side = -1
                end
                confidence = confidence + 20
            end
        end
    end
    
    -- ✅ IMPROVED: Confidence decay system (exponential)
    if data.last_update then
        local time_since_update = globals.curtime() - data.last_update
        if time_since_update > 0.3 then
            -- Exponential decay based on hit rate
            local decay_rate = 0.15  -- Base 15% per second
            
            -- Adjust decay rate based on performance
            if data.hit_rate > 0.7 then
                decay_rate = 0.08  -- Slower decay if working well
            elseif data.hit_rate < 0.3 then
                decay_rate = 0.25  -- Faster decay if performing poorly
            end
            
            local decay_factor = math.exp(-decay_rate * time_since_update)
            confidence = confidence * decay_factor
        end
    end
    data.last_update = globals.curtime()

    -- Update data
    data.desync_side = predicted_side
    data.confidence = math.min(100, confidence)
    data.last_lby = lby

    -- Boost confidence based on consistency
    if data.recent_angles and #data.recent_angles >= 3 then
        local angles = data.recent_angles
        local consistent = true
        
        -- Check if last 3 resolved angles are similar
        for i = 1, 3 do
            if angles[i] then
                local diff = math.abs(angles[i] - angle_offset)
                if diff > 25 then
                    consistent = false
                    break
                end
            end
        end
        
        if consistent then
            -- Resolving same side consistently = boost confidence
            data.confidence = math.min(100, data.confidence + 15)
        end
    end

    -- Side consistency check
    if not data.last_predicted_side then
        data.last_predicted_side = predicted_side
    else
        -- If side is consistent, boost confidence
        if data.last_predicted_side == predicted_side then
            data.confidence = math.min(100, data.confidence + 5)
        end
        data.last_predicted_side = predicted_side
    end
        
        -- Calculate resolved angle
        local desync_amount = ui.get(ui_elements.desync_strength) * 0.6
        angle_offset = predicted_side * desync_amount

        if math.abs(angle_offset) < 5 then
            -- No strong detection, use LBY fallback
            local lby = entity.get_prop(player, "m_flLowerBodyYawTarget") or 0
            angle_offset = lby > 0 and -58 or 58
            data.confidence = 50  -- Mark as fallback confidence
        end

        if not data.is_defensive and data.confidence > 60 and data.resolved_angle and data.resolved_angle ~= 0 then
            data.last_good_angle = data.resolved_angle
            data.last_good_angle_tick = globals.tickcount()
        end

        if data.last_successful_angle and data.last_successful_time then
            if (globals.curtime() - data.last_successful_time) < 2.0 and confidence < 50 then
                -- Use last angle that worked (within 2 seconds) if current confidence is low
                data.confidence = 65
                angle_offset = data.last_successful_angle
            end
        end
        
        return angle_offset
    end

-- ===========================
-- BRUTEFORCE RESOLVER
-- ===========================
local function bruteforce_resolve(player, data)
    local mode = ui.get(ui_elements.brute_mode)
    local max_phases = ui.get(ui_elements.brute_phases)
    local angle_offset = 0
    
    if data.brute_working and data.brute_locked then
        -- Keep using working angle
        return data.resolved_angle
    end
    
    -- Use intelligent bruteforce if enabled
    if mode == "Intelligent" then
        local best_mode, adaptive_phases = intelligent_bruteforce(player, data)
        mode = best_mode
        max_phases = adaptive_phases
    end
    
    if mode == "Sequential" then
        local angle_per_phase = 120 / max_phases
        angle_offset = -60 + (data.brute_phase - 1) * angle_per_phase
        
    elseif mode == "Random" then
        angle_offset = math.random(-60, 60)
        
    elseif mode == "Smart" then
        -- Use hit rate to determine if current phase is working
        if data.shots > 0 then
            data.hit_rate = data.hits / data.shots
            
            if data.hit_rate > 0.5 then
                -- Current phase working, lock it
                data.brute_working = true
                data.brute_locked = true
            else
                -- Try opposite side
                data.desync_side = -data.desync_side
            end
        end
        
        angle_offset = data.desync_side * 60
        
    elseif mode == "Adaptive" then
        -- Combine smart logic with animation detection
        local lby = entity.get_prop(player, "m_flLowerBodyYawTarget") or 0
        
        if data.shots > 2 and data.hit_rate > 0.6 then
            data.brute_locked = true
        else
            -- Use LBY to guide bruteforce
            if lby > 0 then
                data.desync_side = -1
            elseif lby < 0 then
                data.desync_side = 1
            end
        end
        
        angle_offset = data.desync_side * (40 + data.brute_phase * 5)
    end
    
    data.resolved_angle = angle_offset
    return angle_offset
end

-- ===========================
-- SHOT TIMING ANALYSIS
-- ===========================
local function detect_shot_timing(player, data)
    local weapon = entity.get_player_weapon(player)
    if not weapon then return false, nil end
   
    local last_shot_time = entity.get_prop(weapon, "m_fLastShotTime")
    if not last_shot_time then return false, nil end
   
    local time_since_shot = globals.curtime() - last_shot_time
   
    -- ✅ IMPROVEMENT 3: Lock angle during shot animation (0-0.2s)
    if time_since_shot < 0.2 then
        -- Get CURRENT body yaw (not LBY)
        local body_yaw = entity.get_prop(player, "m_flPoseParameter", 11)
        if body_yaw then
            body_yaw = body_yaw * 120 - 60
           
            -- Store snapshot
            data.shot_snapshot_angle = body_yaw > 0 and 58 or -58
            data.shot_snapshot_time = globals.curtime()
            data.shot_locked = true
            data.confidence = 98  -- Very high confidence
           
            return true, data.shot_snapshot_angle
        end
    else
        data.shot_locked = false
    end
   
    -- Use snapshot for 0.3s after shot
    if data.shot_snapshot_time and (globals.curtime() - data.shot_snapshot_time) < 0.3 then
        data.confidence = 95
        return true, data.shot_snapshot_angle
    end
   
    return false, nil
end
-- ===========================
-- CHOKE STABILITY ANALYSIS
-- ===========================
local function analyze_choke_stability(player, data)
    local choke = get_choke_from_simtime(player)
    if choke == 0 then return 1.0 end
    
    data.choke_history:push(choke)
    if #data.choke_history > 10 then table.remove(data.choke_history) end
    
    -- High consistent choke = more predictable
    if choke >= 12 then
        data.confidence = math.min(100, data.confidence + 15)
        return 0.8
    elseif choke <= 3 then
        data.confidence = math.max(50, data.confidence - 10)
        return 1.2
    end
    
    return 1.0
end

-- ===========================
-- LBY UPDATE PREDICTION
-- ===========================
local function predict_lby_update(player, data)
    -- ✅ FIX: Check if player is dormant/dead first
    if not entity.is_alive(player) or entity.is_dormant(player) then
        return false, nil
    end
    
    local lby = entity.get_prop(player, "m_flLowerBodyYawTarget") or 0
    
    -- ✅ FIX: Properly get velocity (returns 3 values, not cacheable easily)
    local vx, vy, vz = entity.get_prop(player, "m_vecVelocity")
    if not vx or not vy then
        return false, nil
    end
    
    local speed = math.sqrt(vx*vx + vy*vy)
    
    if not data.last_lby then data.last_lby = lby end
    if not data.last_lby_update_time then data.last_lby_update_time = globals.curtime() end
    
    local lby_changed = math.abs(angle_diff(lby, data.last_lby)) > 35
    
    if lby_changed then
        data.last_lby_update_time = globals.curtime()
        data.last_lby = lby
    end
    
    local time_since_update = globals.curtime() - data.last_lby_update_time
    
    -- LBY updates every ~1.1s when standing
    if speed < 5 then
        if time_since_update > 0.9 and time_since_update < 1.3 then
            data.confidence = 95
            data.lby_update_imminent = true
            return true, (lby > 0 and -60 or 60)
        elseif time_since_update > 1.3 then
            data.lby_update_imminent = false
            return true, (lby > 0 and -58 or 58)
        end
    else
        data.lby_update_imminent = false
    end
    
    return false, nil
end

-- ===========================
-- POSE PARAMETER DELTA TRACKING
-- ===========================
local function track_pose_delta_speed(player, data)
    local current_pose = entity.get_prop(player, "m_flPoseParameter", 11) * 120 - 60
    
    data.pose_history:push({
        value = current_pose,
        time = globals.curtime()
    })
    
    local history = data.pose_history:get_all()
    if #history >= 3 then
        local delta1 = math.abs(history[1].value - history[2].value)
        local delta2 = math.abs(history[2].value - history[3].value)
        
        -- Detect jitter AA
        if delta1 > 80 and delta2 > 80 then
            data.jitter_detected = true
            data.jitter_side_preference = history[1].value > 0 and 1 or -1
            return true, (data.jitter_side_preference * 58)
        end
        
        -- Detect slow turn vs desync flip
        local time_diff = history[1].time - history[3].time
        local total_delta = math.abs(history[1].value - history[3].value)
        local turn_speed = total_delta / time_diff
        
        if turn_speed < 60 then
            data.confidence = math.min(100, data.confidence + 10)
        end
    end
    
    return false, nil
end

-- ===========================
-- CONTEXT-AWARE PHASE BIAS
-- ===========================
local function get_contextual_phase_bias(player, data)
    local vx, vy = get_cached_prop(player, "m_vecVelocity", 0)
    local speed = (vx and vy) and math.sqrt(vx*vx + vy*vy) or 0
    
    local bias = {}
    
    -- Standing targets: center phases work better
    if speed < 5 then
        bias[3] = 1.3  -- Center phase
        bias[2] = 1.1
        bias[4] = 1.1
        bias[1] = 0.9
        bias[5] = 0.9
        
    -- Fast moving: extreme phases
    elseif speed > 220 then
        bias[1] = 1.3  -- Left extreme
        bias[5] = 1.3  -- Right extreme
        bias[3] = 0.7  -- Center less likely
        bias[2] = 1.0
        bias[4] = 1.0
        
    -- Medium speed: balanced
    else
        for i = 1, 5 do
            bias[i] = 1.0
        end
    end
    
    return bias
end

-- ===========================
-- BRUTE COUNTER DETECTION
-- ===========================
local function detect_brute_counter(player, data)
    if not data.phase_hit_pattern then
        data.phase_hit_pattern = {}
    end
    
    -- Track last 10 phase results
    table.insert(data.phase_hit_pattern, 1, {
        phase = data.brute_phase,
        hit = data.last_shot_hit,
        time = globals.curtime()
    })
    if #data.phase_hit_pattern > 10 then
        table.remove(data.phase_hit_pattern)
    end
    
    -- Check if enemy is adapting to our pattern
    if #data.phase_hit_pattern >= 6 then
        local sequential_misses = 0
        for i = 1, 6 do
            if not data.phase_hit_pattern[i].hit then
                sequential_misses = sequential_misses + 1
            end
        end
        
        -- If we're missing 5+ times in a row, enemy might be countering
        if sequential_misses >= 5 then
            -- Reset to random phases
            data.brute_counter_detected = true
            data.brute_counter_time = globals.curtime()
            return true
        end
    end
    
    return false
end

-- ===========================
-- ENHANCED BRUTE PHASE INTELLIGENCE
-- ===========================
local function predict_best_brute_phase(player, data)

    if detect_brute_counter(player, data) then
        -- Return random phase if counter detected
        return math.random(1, 5)
    end

    -- Check if we have enough data
    if not data.brute_phase_success then return 1 end
    
    local phase_scores = {}
    local current_time = globals.curtime()
    
    for phase = 1, 5 do
        local phase_data = data.brute_phase_success[phase]
        if not phase_data then
            phase_scores[phase] = 0
            goto continue
        end
        
        local hits = phase_data.hits or 0
        local misses = phase_data.misses or 0
        local last_time = phase_data.time or 0

        -- Add decay factor based on how old the data is
        local age = current_time - last_time
        local freshness = math.exp(-age / 10)  -- 10 second half-life

        -- Weight recent successes more heavily
        local weighted_hits = hits * freshness
        local weighted_total = (hits + misses) * freshness

        if weighted_total == 0 then
            phase_scores[phase] = 0
            goto continue
        end

        -- Success rate with time weighting
        local success_rate = weighted_hits / weighted_total
        
        -- Time decay (exponential - recent hits matter WAY more)
        local age = current_time - last_time
        local recency = math.exp(-age / 5)  -- 5 second half-life
        
        -- ✅ NEW: Pattern matching - if they're using jitter, prefer alternating phases
        local pattern_bonus = 0
        if data.jitter_detected then
            -- Jitter users often alternate sides
            local last_phase = data.last_brute_phase or 1
            if math.abs(phase - last_phase) >= 2 then
                pattern_bonus = 0.2  -- Prefer opposite side
            end
        end
        
        -- ✅ NEW: Velocity-aware scoring
        local velocity_bonus = 0
        local vx, vy = get_cached_prop(player, "m_vecVelocity", 0)
        if vx and vy then
            local speed = math.sqrt(vx*vx + vy*vy)
            
            -- Moving fast = certain phases work better
            if speed > 200 then
                -- Phases 1 and 5 (extremes) work better on moving targets
                if phase == 1 or phase == 5 then
                    velocity_bonus = 0.15
                end
            elseif speed < 5 then
                -- Standing = center phases work better
                if phase == 3 then
                    velocity_bonus = 0.2
                end
            end
        end
        
        -- ✅ NEW: Confidence-based adjustment
        local confidence_weight = 1.0
        if data.confidence < 50 then
            -- Low confidence = weight recent success more heavily
            confidence_weight = 1.3
        end
        
        -- Final score
        local base_score = success_rate * 100
        local weighted_score = base_score * recency * confidence_weight
        local bias = get_contextual_phase_bias(player, data)
        local final_score = weighted_score + (pattern_bonus * 50) + (velocity_bonus * 50)
        final_score = final_score * (bias[phase] or 1.0)  -- Apply contextual bias

        phase_scores[phase] = final_score
        
        ::continue::
    end
    
    -- ✅ NEW: Skip obviously bad phases
    local viable_phases = {}
    for phase = 1, 5 do
        local phase_data = data.brute_phase_success[phase]
        if phase_data then
            local total = (phase_data.hits or 0) + (phase_data.misses or 0)
            if total > 5 then
                local success_rate = (phase_data.hits or 0) / total
                if success_rate < 0.15 then
                    goto continue
                end
            end
        end
        table.insert(viable_phases, phase)
        ::continue::
    end
    
    if #viable_phases == 0 then
        viable_phases = {1, 2, 3, 4, 5}
    end
    
    -- Find best phase (only from viable phases)
    local best_phase = 1
    local best_score = -1
    
    for _, phase in ipairs(viable_phases) do
        if phase_scores[phase] > best_score then
            best_phase = phase
            best_score = phase_scores[phase]
        end
    end
    
    -- ✅ NEW: Don't switch if current phase is still working
    if data.brute_phase and phase_scores[data.brute_phase] then
        local current_score = phase_scores[data.brute_phase]
        
        -- Only switch if new phase is SIGNIFICANTLY better (30% threshold)
        if best_score < current_score * 1.3 then
            return data.brute_phase
        end
    end
    
    data.last_brute_phase = best_phase
    return best_phase
end

-- ===========================
-- IDEAL TICK - ULTRA SIMPLIFIED
-- ===========================
local ui_ideal_tick = {
    enable = ui.new_checkbox("RAGE", "Other", "Ideal tick detection")
}

local function calculate_ideal_tick(player, data)
    if not ui.get(ui_ideal_tick.enable) then return 0 end
    
    local choke = get_choke_from_simtime(player)
    
    -- HVH-optimized automatic settings (no user input)
    local min_choke = 2   -- Min safe choke
    local max_choke = 12  -- Max safe choke (accounts for HVH fakelag)
    local boost = 15      -- Confidence boost on ideal tick
    local penalty = 15    -- Confidence penalty on bad tick
    
    -- Ideal tick = low choke (most accurate data)
    if choke >= min_choke and choke <= max_choke then
        data.confidence = math.min(100, data.confidence + boost)
        data.ideal_tick = true
        return 1  -- Good tick
    elseif choke > max_choke then
        data.confidence = math.max(20, data.confidence - penalty)
        data.ideal_tick = false
        return -1  -- Bad tick (high choke)
    end
    
    data.ideal_tick = false
    return 0  -- Normal
end

-- ===========================
-- ENHANCED LAG COMPENSATION
-- ===========================
local function get_best_backtrack_tick(player, data)
    if not lag_records[player] or #lag_records[player] == 0 then
        return nil
    end
    
    local records = lag_records[player]
    local best_record = nil
    local best_score = -1
    
    -- ✅ Evaluate each lag record
    for i = 1, math.min(#records, 12) do  -- Check last 12 ticks
        local record = records[i]
        if not record then goto continue end
        
        local score = 0
        local age = globals.tickcount() - record.tickcount
        
        -- Factor 1: Recency (newer = better)
        local recency_score = 100 - (age * 8)  -- Decay 8 points per tick
        if recency_score < 0 then goto continue end
        score = score + recency_score
        
        -- Factor 2: Velocity stability
        if record.velocity then
            local vx, vy, vz = record.velocity[1], record.velocity[2], record.velocity[3]
            if vx and vy then
                local speed = math.sqrt(vx*vx + vy*vy)
                
                -- Prefer low-velocity records (easier to hit)
                if speed < 10 then
                    score = score + 40
                elseif speed < 100 then
                    score = score + 20
                else
                    score = score + 5
                end
            end
        end
        
        -- Factor 3: Simulation time validity
        if record.simtime and record.simtime > 0 then
            local simtime_age = globals.curtime() - record.simtime
            
            -- Prefer recent simtimes (< 0.5s old)
            if simtime_age < 0.5 then
                score = score + 30
            elseif simtime_age < 1.0 then
                score = score + 15
            end
        end
        
        -- Factor 4: LBY stability (if available)
        if record.lby and data.last_lby then
            local lby_delta = math.abs(angle_diff(record.lby, data.last_lby))
            
            -- Prefer stable LBY (small change)
            if lby_delta < 10 then
                score = score + 25
            elseif lby_delta < 35 then
                score = score + 10
            end
        end
        
        -- Factor 5: Animation layer stability
        if record.layers then
            -- Check if move layer was stable
            -- (This requires storing layers in lag_records, which you already do)
            score = score + 10
        end
        
        if score > best_score then
            best_score = score
            best_record = record
        end
        
        ::continue::
    end
    
    return best_record
end

-- ===========================
-- BACKTRACK TICK HINTING
-- ===========================
local function hint_best_backtrack_tick(player, data)
    local best_record = get_best_backtrack_tick(player, data)
    
    if not best_record then 
        data.backtrack_ticks = nil
        data.backtrack_score = nil
        return 
    end
    
    local ticks_ago = globals.tickcount() - best_record.tickcount
    
    if ticks_ago < 0 or ticks_ago > 12 then 
        data.backtrack_ticks = nil
        data.backtrack_score = nil
        return 
    end
    
    -- Store metadata for analytics/debugging
    data.backtrack_ticks = ticks_ago
    data.backtrack_score = best_record.score or 0  -- Use stored score
    
    -- HINT to the aimbot by adjusting confidence
    -- Recent + high quality = boost confidence
    if ticks_ago <= 3 and data.backtrack_score > 150 then
        data.confidence = math.min(100, data.confidence + 15)  -- Bigger boost
    elseif ticks_ago <= 5 and data.backtrack_score > 120 then
        data.confidence = math.min(100, data.confidence + 10)
    -- Old or low quality = reduce confidence
    elseif ticks_ago >= 8 or data.backtrack_score < 80 then
        data.confidence = math.max(30, data.confidence - 8)
    end
end

-- ===========================
-- SMART FAKELAG OPTIMIZER
-- ===========================
local ui_fakelag = {
    enable = ui.new_checkbox("RAGE", "Other", "Smart fakelag optimizer")
}

local fakelag_ref = ui.reference("AA", "Fake lag", "Limit")

local function optimize_fakelag()
    if not ui.get(ui_fakelag.enable) then return end
    
    local me = entity.get_local_player()
    if not me or not entity.is_alive(me) then return end
    
    -- Check if fakeduck is active
    local fakeduck_key = ui.reference("RAGE", "Other", "Duck peek assist")
    if ui.get(fakeduck_key) then
        ui.set(fakelag_ref, 15)  -- Max fakelag during fakeduck
        return
    end
    
    local ping = client.latency() * 1000
    local vx, vy = entity.get_prop(me, "m_vecVelocity")
    local speed = vx and vy and math.sqrt(vx*vx + vy*vy) or 0
    
    -- HVH-specific automatic optimization
    
    -- Priority 1: High ping compensation (critical in HVH)
    if ping > 80 then
        local reduction = math.floor((ping - 80) / 10)
        local new_amount = math.max(1, 15 - reduction)
        ui.set(fakelag_ref, new_amount)
        return
    end
    
    -- Priority 2: Peeking with Scout/AWP (unpredictability)
    if speed > 100 then
        ui.set(fakelag_ref, 15)  -- Max fakelag for jiggle peeks
        return
    end
    
    -- Priority 3: Standing with AWP/Auto (quick shot)
    if speed < 5 then
        ui.set(fakelag_ref, 4)  -- Low fakelag for holding angles
        return
    end
    
    -- Default: don't override (let user AA settings handle it)
end

-- ===========================
-- BACKTRACK COMPENSATION
-- ===========================
local function apply_backtrack_compensation(player, data, base_angle)
    if not data.backtrack_ticks or not data.backtrack_score then
        return base_angle
    end
    
    local ticks_ago = data.backtrack_ticks
    local score = data.backtrack_score
    
    -- If backtrack is very old (10-12 ticks), use a more conservative angle
    if ticks_ago >= 10 then
        return base_angle * 0.85  -- Reduce desync prediction
    end
    
    -- If backtrack is perfect (recent + high score), be more aggressive
    if ticks_ago <= 3 and score > 150 then
        return base_angle * 1.1  -- Trust the resolve more
    end
    
    -- If backtrack quality is poor, center slightly
    if score < 80 then
        return base_angle * 0.7  -- Play it safer
    end
    
    return base_angle
end

-- ===========================
-- MAIN RESOLVER
-- ===========================
local function resolve_player(player)
    if not ui.get(ui_elements.enable) then return end
    if not entity.is_alive(player) then
        plist.set(player, "Force body yaw", false)
        plist.set(player, "Force body yaw value", 0)
        plist.set(player, "Correction active", true)
        return
    end
    
    local resolved_angle = 0
    local method_used = "unknown"
    local shot_active, shot_angle = false, nil
    local lby_active, lby_angle = false, nil
    local jitter_active, jitter_angle = false, nil
    local choke_modifier = 1.0
    
    local data = init_player_data(player)
    hint_best_backtrack_tick(player, data)

    local mode = ui.get(ui_elements.mode)
    local smart_baim_enabled = ui.get(ui_smart_baim.enable)

    local current_health = get_cached_prop(player, "m_iHealth", 100)
    if data.last_known_health and current_health > data.last_known_health + 50 then
        data.body_aimable = false
        data.lethal_shot_available = false
        data.estimated_body_damage = 0
    end
    data.last_known_health = current_health

    -- Store lag record
    init_lag_record(player)

    -- Update position tracking
    local x, y, z = entity.get_prop(player, "m_vecOrigin")
    if x and y and z then
        data.last_position = {x = x, y = y, z = z}
    end

    calculate_ideal_tick(player, data)

    -- Skip RESOLVER for legit players (but keep body aim override)
    --if not is_using_antiaim(player) then
      --  plist.set(player, "Force body yaw", false)
        --plist.set(player, "Force body yaw value", 0)
        -- Apply smart baim even for legit players
        --if smart_baim_enabled then
           -- apply_smart_hitbox_override(player, data)
        --end
        --return
    --end
    
    -- Handle override mode
    if mode == "Override" then
        if ui.get(ui_elements.override_left) then
            plist.set(player, "Force body yaw", true)
            plist.set(player, "Force body yaw value", -60)
            return
        elseif ui.get(ui_elements.override_right) then
            plist.set(player, "Force body yaw", true)
            plist.set(player, "Force body yaw value", 60)
            return
        elseif ui.get(ui_elements.override_center) then
            plist.set(player, "Force body yaw", true)
            plist.set(player, "Force body yaw value", 0)
            return
        end
    end
    
    -- Detect defensive AA
    if ui.get(ui_elements.defensive) then
        detect_defensive(player, data)
        
        if data.defensive_ticks > 0 then
            local old_ticks = data.defensive_ticks
            data.defensive_ticks = data.defensive_ticks - 1
            
            -- When defensive expires, set smart wait period
            if old_ticks > 0 and data.defensive_ticks <= 0 then
                data.is_defensive = false
                
                if ui.get(ui_defensive_delay.enable) then
                    local wait_ticks = 6  -- Default
                    
                    if data.defensive_type then
                        -- Pitch exploits = longer wait
                        if data.defensive_type == "fake_up" or 
                           data.defensive_type == "fake_down" or
                           data.defensive_type == "pitch_oscillation" or
                           data.defensive_type == "custom_pitch" or
                           data.defensive_type == "switch_pitch" then
                            wait_ticks = 10
                        
                        -- Teleports/flicks = medium wait
                        elseif data.defensive_type == "teleport" or
                               data.defensive_type == "yaw_flick" or
                               data.defensive_type == "spin" then
                            wait_ticks = 6
                        
                        -- Simtime/choke = short wait
                        elseif data.defensive_type == "negative_simtime" or
                               data.defensive_type == "instant_lc" or
                               data.defensive_type == "choke_instant" then
                            wait_ticks = 4
                        end
                    end
                    
                    -- Confidence adjustment
                    if data.confidence < 60 then
                        wait_ticks = wait_ticks + 3
                    elseif data.confidence > 85 then
                        wait_ticks = math.max(2, wait_ticks - 2)
                    end
                    
                    data.defensive_wait_until = globals.tickcount() + wait_ticks
                    
                    --if ui.get(ui_elements.console_log) then
                        --client.log(string.format("[Defensive] %s: Delaying shots for %d ticks (%s)",
                            --entity.get_player_name(player), 
                            --wait_ticks,
                            --data.defensive_type or "unknown"))
                    --end
                end
            end
        end
    end

    -- PRIORITY 1: Shot timing (highest confidence)
    shot_active, shot_angle = detect_shot_timing(player, data)
    if shot_active and shot_angle then
        resolved_angle = shot_angle
        method_used = "shot_timing"
        goto apply_resolution
    end

    -- PRIORITY 2: LBY update window
    lby_active, lby_angle = predict_lby_update(player, data)
    if lby_active and lby_angle then
        resolved_angle = lby_angle
        method_used = "lby_prediction"
        goto apply_resolution
    end

    -- PRIORITY 3: Jitter detection
    jitter_active, jitter_angle = track_pose_delta_speed(player, data)
    if jitter_active and jitter_angle then
        resolved_angle = jitter_angle
        method_used = "jitter_detect"
        goto apply_resolution
    end

    -- PRIORITY 4: Choke stability modifier
    choke_modifier = analyze_choke_stability(player, data)
    
    -- PRIORITY 5: Original resolver logic
    if mode == "AI" then
        resolved_angle = ai_resolve(player, data)
        method_used = "ai"
    elseif mode == "Smart" or mode == "Automatic" then
        resolved_angle = smart_resolve(player, data)
        method_used = "smart"
    elseif mode == "Bruteforce" then
        local brute_mode = ui.get(ui_elements.brute_mode)
        
        -- ✅ IMPROVEMENT 1: Use enhanced prediction
        if brute_mode == "Intelligent" or brute_mode == "Adaptive" then
            local best_phase = predict_best_brute_phase(player, data)
            data.brute_phase = best_phase
        end
        
        resolved_angle = bruteforce_resolve(player, data)
        method_used = "bruteforce"
    elseif mode == "Adaptive" then
        if data.confidence > ui.get(ui_elements.confidence) then
            resolved_angle = smart_resolve(player, data)
            method_used = "smart"
        else
            local best_phase = time_weighted_brute(player, data)
            if best_phase ~= data.brute_phase then
                data.brute_phase = best_phase
            end
            resolved_angle = bruteforce_resolve(player, data)
            method_used = "bruteforce"
        end
    end
    
    -- Apply choke modifier
    resolved_angle = resolved_angle * choke_modifier
    
    ::apply_resolution::

    -- Apply adaptive learning
    if contains(safe_get_multiselect(ui_elements.advanced), "Adaptive Learning") then
        adaptive_learning(player, data)
    end

    -- Apply weapon awareness
    if contains(utils.safe_get_multiselect(ui_elements.advanced), "Weapon Awareness") then
        update_weapon_priority(player, data)
    end

    -- Applying backtrack testing
    resolved_angle = apply_backtrack_compensation(player, data, resolved_angle)

    -- Apply resolution
    data.resolved_angle = smooth_resolved_angle(player, data, resolved_angle)
    data.last_resolved_side = data.resolved_angle > 0 and 1 or -1

    plist.set(player, "Correction active", false)
    plist.set(player, "Force body yaw", true)
    plist.set(player, "Force body yaw value", data.resolved_angle)

    -- Apply defensive shot delay FIRST (highest priority)
    local shot_delayed = apply_defensive_shot_delay(player, data)

    if not shot_delayed then
        -- Only apply smart baim if shot is NOT delayed
        if smart_baim_enabled then
            apply_smart_hitbox_override(player, data)
        end
    end
    
    -- Update analytics
    update_resolver_analytics(player, data, nil, method_used)
end 

    -- ===========================
    -- EVENT HANDLERS
    -- ===========================
    local function on_aim_miss(e)
        if not ui.get(ui_elements.enable) then return end
    
    local target = e.target
    
    -- ignore death and dormant misses
    if not entity.is_alive(target) then return end
    if entity.get_prop(target, "m_bDormant") then return end
    
    local data = init_player_data(target)

        data.last_shot_time = globals.curtime()
        
        -- Determine if this was a resolver miss or other cause
        local reason = e.reason or "?"
        local is_resolver_miss = false
        
        -- Check if miss was due to resolver (not spread/prediction)
        if reason == "spread" then
            is_resolver_miss = false
        elseif reason == "prediction error" then
            is_resolver_miss = false
        elseif reason == "death" then
            is_resolver_miss = false
        elseif reason == "?" then
            -- Unknown reason - check hit chance to determine
            local hitchance = e.hit_chance or 0
            if hitchance < 75 then
                is_resolver_miss = false  -- Likely spread/prediction
            else
                is_resolver_miss = true   -- High hitchance miss = resolver issue
            end
        else
            is_resolver_miss = true  -- Jitter, resolver, etc.
        end
    
        data.shots = data.shots + 1
        data.misses = data.misses + 1  -- always count misses
        data.last_shot_hit = false

        -- Track miss for brute phases (only resolver misses)
        if is_resolver_miss then
            local current_phase = data.brute_phase
            if data.brute_phase_success[current_phase] then
                data.brute_phase_success[current_phase].misses = 
                    data.brute_phase_success[current_phase].misses + 1
            end
        end
    
        -- Update bruteforce FIRST before logging (ONLY on resolver misses)
        local mode = ui.get(ui_elements.mode)
        local phase_changed = false

        -- ✅ IMPROVEMENT 6: Smart reset on behavior change
        local vx, vy = entity.get_prop(target, "m_vecVelocity")
        local current_speed = vx and vy and math.sqrt(vx*vx + vy*vy) or 0
        
        local behavior_changed = false
        if data.last_miss_speed then
            local speed_diff = math.abs(current_speed - data.last_miss_speed)
            
            -- Major speed change = player changed playstyle, reset brute
            if speed_diff > 150 then
                behavior_changed = true
                data.brute_phase = 1
                data.misses = 0
                data.confidence = 40
                
                if ui.get(ui_elements.console_log) then
                    client.log("↻ Reset: Player changed movement style")
                end
            end
        end
        data.last_miss_speed = current_speed
        
        if is_resolver_miss and (mode == "Bruteforce" or mode == "Adaptive" or mode == "AI") then
            local max_phases = ui.get(ui_elements.brute_phases)
            local reset_threshold = ui.get(ui_elements.brute_reset)
            
            --  Don't change phase on low-confidence misses
            local should_change_phase = true
            
            if data.confidence < 30 then
                -- Very low confidence = don't trust this miss for bruteforce
                should_change_phase = false
                if ui.get(ui_elements.console_log) then
                    client.log("â†' Skipped phase change: confidence too low (<30%)")
                end
            end
            
            if should_change_phase then
                -- Increment phase
                local old_phase = data.brute_phase
                data.brute_phase = data.brute_phase + 1
                phase_changed = true

                if data.brute_phase > max_phases then
                    data.brute_phase = 1
                    data.misses = 0  -- Reset miss counter after full cycle
                end
            end
        
            -- Reset if too many consecutive misses across multiple cycles
            if data.misses >= (max_phases * reset_threshold) then
                data.brute_phase = 1
                data.misses = 0
                data.confidence = 0
                data.brute_locked = false
                data.brute_working = false
                if ui.get(ui_elements.console_log) then
                    client.log("→ Reset: Too many consecutive resolver misses across cycles")
                end
            end
        end
    
        -- Console logging (only if enabled)
        if ui.get(ui_elements.console_log) then
            -- Get target info
            local target_name = entity.get_player_name(target)
        
            -- Build miss log message with reason
            local miss_type = is_resolver_miss and "RESOLVER" or "OTHER"
            local log_msg = string.format("┌─ [Guardian] Miss on %s [%s: %s]", target_name, miss_type, reason)
            client.log(log_msg)
        
            -- Log resolver information
            client.log(string.format("│ Mode: %s | Phase: %d/%d%s", 
                mode, 
                data.brute_phase, 
                ui.get(ui_elements.brute_phases),
                phase_changed and " ✓ CHANGED" or " (unchanged)"
            ))
            client.log(string.format("│ Resolved Angle: %d° | Side: %d", math.floor(data.resolved_angle), data.desync_side))
            client.log(string.format("│ Confidence: %d%% | Hit Rate: %.1f%%", data.confidence, data.hit_rate * 100))
        
            -- Log detection info
            local vx, vy = entity.get_prop(target, "m_vecVelocity")
            local speed = (vx and vy) and math.sqrt(vx*vx + vy*vy) or 0
            local is_standing = speed < 5
            client.log(string.format("│ Speed: %.1f u/s | Standing: %s", speed, is_standing and "Yes" or "No"))
        
            -- Log bruteforce info
            if mode == "Bruteforce" or mode == "Adaptive" or mode == "AI" then
                client.log(string.format("│ Brute: %s | Locked: %s", ui.get(ui_elements.brute_mode), data.brute_locked and "Yes" or "No"))
            end
        
            -- Log defensive status
            if data.is_defensive then
                client.log("│ ⚠️ Defensive AA Detected!")
            end
        
            -- Log reason/action
            local likely_reason = "Unknown"
            if not is_resolver_miss then
                if reason == "spread" then
                    likely_reason = "Weapon spread (not resolver issue)"
                elseif reason == "prediction error" then
                    likely_reason = "Movement prediction failed"
                elseif reason == "death" then
                    likely_reason = "Target died / You died"
                else
                    likely_reason = "Low hitchance/spread (not resolver)"
                end
            else
                -- More detailed resolver miss analysis
                if data.is_defensive then
                    likely_reason = "Defensive AA active"
                elseif speed > 250 then
                    likely_reason = "Extrapolation fal"
                elseif is_standing and data.standing_ticks < 32 then
                    likely_reason = "Early standing detection"
                elseif data.jitter_detected then
                    likely_reason = "Jitter AA (trying to counter)"
                elseif data.fake_desync_detected then
                    likely_reason = "Fake desync detected"
                elseif data.brute_phase == 1 and data.shots < 3 then
                    likely_reason = "Initial bruteforce phase"
                elseif data.confidence < 40 then
                    likely_reason = "Very low confidence (<40%)"
                elseif data.confidence < 60 then
                    likely_reason = "Low confidence (<60%)"
                elseif math.abs(data.resolved_angle) < 10 then
                    likely_reason = "Center angle resolve (might be fakelag)"
                elseif data.brute_locked then
                    likely_reason = "Locked brute phase failed (switching)"
                else
                    likely_reason = "Wrong resolve angle (phase " .. data.brute_phase .. ")"
                end
            end
        
            client.log(string.format("│ Likely Reason: %s", likely_reason))
            
            if is_resolver_miss then
                local next_phase = data.brute_phase + 1
                if next_phase > ui.get(ui_elements.brute_phases) then
                    next_phase = 1
                end
                client.log(string.format("└─ Next: Phase %d (Resolver Misses: %d)", next_phase, data.misses))
            else
                client.log(string.format("└─ Action: Keeping Phase %d (not resolver miss)", data.brute_phase))
            end
        end
    
        -- Flip side ONLY on resolver misses
        if is_resolver_miss then
            data.desync_side = -data.desync_side
        end
    
        -- Update hit rate
        if data.shots > 0 then
            data.hit_rate = data.hits / data.shots
        end

        update_velocity_confidence(target, data, false)
    end

    local function on_aim_hit(e)
        if not ui.get(ui_elements.enable) then return end
        
        local target = e.target
        local data = init_player_data(target)
        
        data.hits = data.hits + 1
        data.shots = data.shots + 1
        data.confidence = math.min(100, data.confidence + 10)
        data.last_shot_hit = true

        update_velocity_confidence(target, data, true)

        data.last_successful_angle = data.resolved_angle
        data.last_successful_time = globals.curtime()

        local preset = apply_smart_baim_preset()
        if preset.reset_on_hit then
            data.misses = 0
        end
        
        -- Update analytics with hit
        update_resolver_analytics(target, data, true, data.last_successful_method or "unknown")
        
        -- Update hit rate
        if data.shots > 0 then
            data.hit_rate = data.hits / data.shots
        end
        
        -- Lock bruteforce if working well
        if data.hit_rate > 0.6 then
            data.brute_working = true
        end

        -- Track hit success for brute phases
        local current_phase = data.brute_phase
        if data.brute_phase_success[current_phase] then
            data.brute_phase_success[current_phase].hits = 
                data.brute_phase_success[current_phase].hits + 1
            data.brute_phase_success[current_phase].time = globals.curtime()
        end
        
        -- Store hitgroup-angle correlation
        local hitgroup_names = {
            [0] = "generic",
            [1] = "head",
            [2] = "chest",
            [3] = "stomach",
            [4] = "left arm",
            [5] = "right arm",
            [6] = "left leg",
            [7] = "right leg"
        }

        local hitgroup_name = hitgroup_names[e.hitgroup] or "unknown"
        if not data.hitgroup_angles[hitgroup_name] then
            data.hitgroup_angles[hitgroup_name] = {}
        end
        table.insert(data.hitgroup_angles[hitgroup_name], data.resolved_angle)
        if #data.hitgroup_angles[hitgroup_name] > 10 then
            table.remove(data.hitgroup_angles[hitgroup_name], 1)
        end
    end

    local function on_player_hurt(e)
        local victim = client.userid_to_entindex(e.userid)
        if not victim then return end
        
        local data = resolver_data[victim]
        if data then
            data.last_damage_time = globals.curtime()
        end
    end

    -- Register the event
    client.set_event_callback("player_hurt", on_player_hurt)

    local function on_round_start()
        -- test lethal
        last_target = nil
        last_mindmg_override = nil
        last_weapon_id = nil

        -- restores wep spec min dmg i tihnk
        restore_mindmg()

        client.delay_call(0.5, function()
            save_current_mindmg()
        end)

        eye_angle_data = {}
        entity_cache = {}
        entity_cache_time = {}
        velocity_cache = {}
        velocity_cache_time = {}

        for player, _ in pairs(resolver_cache) do
            if not entity.is_alive(player) and not entity.is_dormant(player) then
                resolver_cache[player] = nil
                speed_cache[player] = nil
                speed_cache_time[player] = nil
                damage_cache[player] = nil
                damage_cache_time[player] = nil
                defensive_check_cache[player] = nil
                defensive_check_time[player] = nil
            end
        end

    -- Reset all player data
    for player, data in pairs(resolver_data) do
        data.misses = 0
        data.hits = 0
        data.shots = 0
        data.hit_rate = 0
        data.brute_phase = 1
        data.confidence = 0
        data.brute_locked = false
        data.brute_working = false
        data.is_defensive = false
        data.defensive_ticks = 0
        data.standing_ticks = 0
        data.moving_ticks = 0
        data.fake_desync_detected = false
        data.suspicious_animation = false
        data.defensive_wait_until = nil
        
        -- Safely reset analytics
        if data.analytics then
            data.analytics.overall_success_rate = 0
            data.analytics.total_resolves = 0
            data.analytics.successful_resolves = 0
        end
        
        -- NEW: Reset lethal flags
        data.body_aimable = false
        data.lethal_shot_available = false
        data.estimated_body_damage = 0
        data.last_known_health = nil

        data.body_aimable = false
        data.lethal_shot_available = false
        data.estimated_body_damage = 0
        data.baim_reason = nil
        
        -- Clear plist overrides with correct values
        pcall(function()
            plist.set(player, "Override prefer body aim", "-")
            plist.set(player, "Minimum damage override", 0)
            plist.set(player, "Override safe point", "-")
            plist.set(player, "Force body yaw", false)
            plist.set(player, "Force body yaw value", 0)
        end)
    end

    speed_cache = {}
    speed_cache_time = {}
    damage_cache = {}
    damage_cache_time = {}
end

-- ===========================
-- INDICATORS
-- ===========================
local function draw_indicator()
    if not ui.get(ui_elements.indicator) then return end
    if not ui.get(ui_elements.enable) then return end
    
    local screen_width, screen_height = client.screen_size()
    local x = screen_width / 2
    local y = screen_height / 2 + 50
    local style = ui.get(ui_elements.indicator_style)
    
    local target = client.current_threat()
    if not target or not entity.is_alive(target) then
        renderer.text(x, y, 255, 255, 255, 200, "c", 0, "No Target")
        return
    end
    
    local data = init_player_data(target)
    local mode = ui.get(ui_elements.mode)
    local name = entity.get_player_name(target)
    
    -- Color based on confidence
    local r, g, b = 255, 255, 255
    if data.confidence > 75 then
        r, g, b = 0, 255, 0
    elseif data.confidence > 50 then
        r, g, b = 255, 255, 0
    else
        r, g, b = 255, 100, 100
    end
    
    if style == "Weapon Info" then
        renderer.text(x, y, r, g, b, 255, "c", 0, string.format("Guardian - %s", name))
        renderer.text(x, y + 15, r, g, b, 255, "c", 0, string.format("Weapon: %s | Threat: %d", data.current_weapon:upper(), data.weapon_threat))
        renderer.text(x, y + 30, r, g, b, 255, "c", 0, string.format("Mode: %s | Peek: %s", mode, data.likely_peek_type))
        renderer.text(x, y + 45, r, g, b, 255, "c", 0, string.format("Confidence: %d%% | Success: %.1f%%", data.confidence, data.analytics.overall_success_rate * 100))
        renderer.text(x, y + 60, r, g, b, 255, "c", 0, string.format("Resolved: %d° | Context: %s", data.resolved_angle, data.resolver_context))
        
        if data.patterns.oscillation then
            renderer.text(x, y + 75, 255, 100, 255, 255, "c", 0, "OSCILLATION DETECTED")
        end
        if data.fake_desync_detected then
            renderer.text(x, y + 90, 255, 0, 0, 255, "c", 0, "FAKE DESYNC DETECTED")
        end
        if data.is_defensive then
            renderer.text(x, y + 105, 255, 0, 0, 255, "c", 0, "DEFENSIVE AA")
        end
        
    elseif style == "Analytics" then
        renderer.text(x, y, r, g, b, 255, "c", 0, string.format("Guardian - %s", name))
        renderer.text(x, y + 15, r, g, b, 255, "c", 0, string.format("Mode: %s | Phase: %s", mode, data.learning_phase))
        renderer.text(x, y + 30, r, g, b, 255, "c", 0, string.format("Confidence: %d%% | Success: %.1f%%", data.confidence, data.analytics.overall_success_rate * 100))
        renderer.text(x, y + 45, r, g, b, 255, "c", 0, string.format("Resolved: %d° | Context: %s", data.resolved_angle, data.resolver_context))
        renderer.text(x, y + 60, r, g, b, 255, "c", 0, string.format("Playstyle: %s | Peek: %s", data.player_profile.playstyle, data.likely_peek_type))
        
        if data.patterns.oscillation then
            renderer.text(x, y + 75, 255, 100, 255, 255, "c", 0, "OSCILLATION DETECTED")
        end
        if data.fake_desync_detected then
            renderer.text(x, y + 90, 255, 0, 0, 255, "c", 0, "FAKE DESYNC DETECTED")
        end
        if data.is_defensive then
            renderer.text(x, y + 105, 255, 0, 0, 255, "c", 0, "DEFENSIVE AA")
        end
        
    elseif style == "Detailed" then
        renderer.text(x, y, r, g, b, 255, "c", 0, string.format("Mode: %s", mode))
        renderer.text(x, y + 15, r, g, b, 255, "c", 0, string.format("Target: %s", name))
        renderer.text(x, y + 30, r, g, b, 255, "c", 0, string.format("Confidence: %d%%", data.confidence))
        renderer.text(x, y + 45, r, g, b, 255, "c", 0, string.format("Phase: %d/%d", data.brute_phase, ui.get(ui_elements.brute_phases)))
        renderer.text(x, y + 60, r, g, b, 255, "c", 0, string.format("Hit Rate: %.1f%%", data.hit_rate * 100))
        renderer.text(x, y + 75, r, g, b, 255, "c", 0, string.format("Angle: %d°", data.resolved_angle))
        
        if data.is_defensive then
            renderer.text(x, y + 90, 255, 0, 0, 255, "c", 0, "DEFENSIVE")
        end
        
    elseif style == "Simple" then
        renderer.text(x, y, r, g, b, 255, "c", 0, 
            string.format("%s | %s | %d%% | %.0f%%", mode, name, data.confidence, data.hit_rate * 100))
        if data.is_defensive then
            renderer.text(x, y + 15, 255, 0, 0, 255, "c", 0, "DEF")
        end
        
    elseif style == "Minimal" then
        renderer.text(x, y, r, g, b, 255, "c", 0, string.format("%s [%d%%]", mode, data.confidence))
        
    elseif style == "Debug" then
        renderer.text(x, y, r, g, b, 255, "c", 0, string.format("=== Guardian Debug ==="))
        renderer.text(x, y + 15, 255, 255, 255, 255, "c", 0, string.format("Target: %s [%d]", name, target))
        renderer.text(x, y + 30, 255, 255, 255, 255, "c", 0, string.format("Mode: %s | Learning: %s", mode, data.learning_phase))
        renderer.text(x, y + 45, 255, 255, 255, 255, "c", 0, string.format("Side: %d | Angle: %d°", data.desync_side, data.resolved_angle))
        renderer.text(x, y + 60, 255, 255, 255, 255, "c", 0, string.format("Confidence: %d%% | Success: %.1f%%", data.confidence, data.analytics.overall_success_rate * 100))
        renderer.text(x, y + 75, 255, 255, 255, 255, "c", 0, string.format("Phase: %d | Locked: %s", data.brute_phase, data.brute_locked and "YES" or "NO"))
        renderer.text(x, y + 90, 255, 255, 255, 255, "c", 0, string.format("Hits: %d | Misses: %d | Rate: %.1f%%", data.hits, data.misses, data.hit_rate * 100))
        renderer.text(x, y + 105, 255, 255, 255, 255, "c", 0, string.format("Standing: %dt | Moving: %dt", data.standing_ticks, data.moving_ticks))
        renderer.text(x, y + 120, 255, 255, 255, 255, "c", 0, string.format("Context: %s | Peek: %s", data.resolver_context, data.likely_peek_type))
        renderer.text(x, y + 135, 255, 255, 255, 255, "c", 0, string.format("Weapon: %s | Threat: %d", data.current_weapon, data.weapon_threat))
        
        if data.is_defensive then
            renderer.text(x, y + 150, 255, 0, 0, 255, "c", 0, "DEFENSIVE ACTIVE")
        end
        if data.fake_desync_detected then
            renderer.text(x, y + 165, 255, 0, 0, 255, "c", 0, "FAKE DESYNC DETECTED")
        end
    end
    
       -- NEW: Advanced resolver info (only show in Debug style)
    if style == "Debug" then
        local debug_y = y + 180  -- Start after the main debug info
        
        renderer.text(x, debug_y, 200, 150, 255, 255, "", 0, string.format("Shot Timing: %s", 
            data.shot_snapshot_time and (globals.curtime() - data.shot_snapshot_time < 0.3) and "ACTIVE" or "inactive"))
        debug_y = debug_y + 15

        renderer.text(x, debug_y, 200, 150, 255, 255, "", 0, string.format("LBY Update: %s", 
            data.lby_update_imminent and "IMMINENT" or "normal"))
        debug_y = debug_y + 15

        renderer.text(x, debug_y, 200, 150, 255, 255, "", 0, string.format("Jitter: %s | Side: %d", 
            data.jitter_detected and "YES" or "NO", data.jitter_side_preference))
        debug_y = debug_y + 15

        -- Brute phase success rates
        if data.brute_phase_success then
            local phase_str = "Phases: "
            for i = 1, 5 do
                local hits = data.brute_phase_success[i].hits
                local misses = data.brute_phase_success[i].misses
                local total = hits + misses
                local rate = total > 0 and math.floor((hits / total) * 100) or 0
                phase_str = phase_str .. string.format("%d:%d%% ", i, rate)
            end
            renderer.text(x, debug_y, 200, 150, 255, 255, "", 0, phase_str)  -- ✅ Now uses debug_y
        end
    end
end

local function draw_debug_info()
    if not ui.get(ui_elements.debug) then return end
    if not ui.get(ui_elements.enable) then return end

    local target = client.current_threat()
    if not target or not entity.is_alive(target) then return end
    
    local x = 10
    local y = 200
    local line_height = 15
    
    renderer.text(x, y, 150, 200, 255, 255, "", 0, "=== Guardian Enhanced ===")
    y = y + line_height
    
    local target = client.current_threat()
    if target and entity.is_alive(target) then
        local data = init_player_data(target)
        
        renderer.text(x, y, 255, 255, 255, 255, "", 0, string.format("Target: %s [%d]", entity.get_player_name(target), target))
        y = y + line_height
        
        renderer.text(x, y, 255, 255, 255, 255, "", 0, string.format("Desync Side: %d | Predicted: %d", data.desync_side, data.predicted_side))
        y = y + line_height
        
        renderer.text(x, y, 255, 255, 255, 255, "", 0, string.format("Confidence: %d%% | Reliability: %d%%", data.confidence, data.reliability))
        y = y + line_height
        
        renderer.text(x, y, 255, 255, 255, 255, "", 0, string.format("Bruteforce Phase: %d | Working: %s", data.brute_phase, data.brute_working and "YES" or "NO"))
        y = y + line_height
        
        renderer.text(x, y, 255, 255, 255, 255, "", 0, string.format("Resolved Angle: %.1f° | Body Yaw: %.1f°", data.resolved_angle, data.body_yaw))
        y = y + line_height
        
        renderer.text(x, y, 255, 255, 255, 255, "", 0, string.format("Hits: %d | Misses: %d | Shots: %d", data.hits, data.misses, data.shots))
        y = y + line_height
        
        renderer.text(x, y, 255, 255, 255, 255, "", 0, string.format("Hit Rate: %.1f%%", data.hit_rate * 100))
        y = y + line_height
        
        renderer.text(x, y, 255, 255, 255, 255, "", 0, string.format("Defensive: %s | Ticks: %d", data.is_defensive and "YES" or "NO", data.defensive_ticks))
        y = y + line_height
        
        renderer.text(x, y, 255, 255, 255, 255, "", 0, string.format("Standing: %dt | Moving: %dt", data.standing_ticks, data.moving_ticks))
        y = y + line_height
        
        renderer.text(x, y, 255, 255, 255, 255, "", 0, string.format("LBY: %.1f° | Delta: %.1f°", data.last_lby, data.lby_delta))
        y = y + line_height
        
        -- Advanced analytics
        renderer.text(x, y, 150, 200, 255, 255, "", 0, string.format("Learning Phase: %s", data.learning_phase))
        y = y + line_height
        
        renderer.text(x, y, 150, 200, 255, 255, "", 0, string.format("Overall Success: %.1f%%", data.analytics.overall_success_rate * 100))
        y = y + line_height
        
        renderer.text(x, y, 150, 200, 255, 255, "", 0, string.format("Playstyle: %s", data.player_profile.playstyle))
        y = y + line_height
        
        renderer.text(x, y, 150, 200, 255, 255, "", 0, string.format("Context: %s | Peek: %s", data.resolver_context, data.likely_peek_type))
        y = y + line_height
        
        -- Weapon info
        renderer.text(x, y, 200, 150, 255, 255, "", 0, string.format("Weapon: %s | Threat: %d", data.current_weapon, data.weapon_threat))
        y = y + line_height
        
        -- Pattern data
        if data.patterns then
            renderer.text(x, y, 200, 150, 255, 255, "", 0, string.format("Oscillation: %s | Consistent: %d", data.patterns.oscillation and "YES" or "NO", data.patterns.consistent_side))
            y = y + line_height
        end
        
        -- Layer data
        renderer.text(x, y, 150, 200, 255, 255, "", 0, string.format("Layer Weight: %.3f", data.layer_data.move_weight or 0))
        y = y + line_height
        
        renderer.text(x, y, 150, 200, 255, 255, "", 0, string.format("Layer Cycle: %.3f", data.layer_data.move_cycle or 0))
        y = y + line_height
        
        -- Velocity
        local vx, vy = entity.get_prop(target, "m_vecVelocity")
        if vx and vy then
            local speed = math.sqrt(vx*vx + vy*vy)
            renderer.text(x, y, 150, 200, 255, 255, "", 0, string.format("Speed: %.1f u/s", speed))
        end
        y = y + line_height
        
        -- Active detections
        local detections = ui.get(ui_elements.detection)
        local detection_count = (type(detections) == "table") and #detections or 0
        renderer.text(x, y, 150, 200, 255, 255, "", 0, string.format("Active Detections: %d", detection_count))

        -- Enhanced defensive info
        if data.is_defensive then
            renderer.text(x, y, 255, 50, 50, 255, "", 0, string.format("DEFENSIVE ACTIVE: %d ticks", data.defensive_ticks))
            y = y + line_height
            
            if data.defensive_suspicion_score and data.defensive_suspicion_score > 0 then
                renderer.text(x, y, 255, 150, 50, 255, "", 0, string.format("Suspicion Score: %d", data.defensive_suspicion_score))
                y = y + line_height
            end
            
            if data.defensive_flick_detected then
                renderer.text(x, y, 255, 100, 255, 255, "", 0, "Eye Angle Flick Detected")
                y = y + line_height
            end
            
            if data.last_good_angle and data.last_good_angle ~= 0 then
                renderer.text(x, y, 150, 255, 150, 255, "", 0, string.format("Last Good Angle: %.1f°", data.last_good_angle))
                y = y + line_height
            end
            
            if data.effective_ping then
                renderer.text(x, y, 200, 200, 255, 255, "", 0, string.format("Effective Ping: %dms [%s]", data.effective_ping, data.ping_category or "unknown"))
                y = y + line_height
            end
        end
        
    else
        renderer.text(x, y, 255, 100, 100, 255, "", 0, "No valid target")
    end
end

local function draw_watermark()
    if not ui.get(ui_elements.watermark) then return end
    
    local screen_width, screen_height = client.screen_size()
    local watermark_text = "Guardian Enhanced"
    local x = screen_width / 2
    local y = screen_height - 20
    
    local highlight_fraction = (globals.realtime() / 2 % 1.2 * 2) - 1.2
    local output = ""
    
    local r1, g1, b1 = 150, 200, 255
    local r2, g2, b2 = 55, 55, 55
    
    for idx = 1, #watermark_text do
        local character = watermark_text:sub(idx, idx)
        local character_fraction = idx / #watermark_text
        local r_s, g_s, b_s = r1, g1, b1
        
        local highlight_delta = (character_fraction - highlight_fraction)
        if highlight_delta >= 0 and highlight_delta <= 1.4 then
            if highlight_delta > 0.7 then
                highlight_delta = 1.4 - highlight_delta
            end
            local r_fraction = r2 - r_s
            local g_fraction = g2 - g_s
            local b_fraction = b2 - b_s
            r_s = r_s + r_fraction * highlight_delta / 0.8
            g_s = g_s + g_fraction * highlight_delta / 0.8
            b_s = b_s + b_fraction * highlight_delta / 0.8
        end
        
        output = output .. string.format('\a%02x%02x%02x%02x%s', r_s, g_s, b_s, 255, character)
    end
    
    renderer.text(x, y, 255, 255, 255, 255, "c", 0, output)
end

-- ===========================
-- LETHAL ESP FLAG (FIXED)
-- ===========================
local lethal_flag_pulse = 0

local function draw_lethal_flags()
    if not ui.get(ui_smart_baim.show_lethal_flag) then return end
    if not ui.get(ui_elements.enable) then return end
    if not ui.get(ui_smart_baim.enable) then return end
    if not ui.get(ui_smart_baim.lethal_enable) then return end
    
    local enemies = entity.get_players(true)
    if not enemies then return end
    
    local style = ui.get(ui_smart_baim.lethal_flag_style)
    local r, g, b, a = ui.get(ui_smart_baim.lethal_flag_color)
    
    lethal_flag_pulse = (lethal_flag_pulse + 0.05) % (math.pi * 2)
    local pulse = math.abs(math.sin(lethal_flag_pulse))
    local pulse_alpha = math.floor(a * (0.6 + pulse * 0.4))
    
    -- DEBUG: Count how many lethal targets
    local lethal_count = 0
    
    for i = 1, #enemies do
    local player = enemies[i]
    
    if entity.is_alive(player) then
        local data = resolver_data[player]
        
        -- Initialize if needed
        if not data then
            data = init_player_data(player)
        end
        
        -- ✅ Use cached data instead of recalculating every frame
        local is_lethal = data.lethal_shot_available or false
        
        -- Only recalculate if cache is old (older than 5 ticks)
        if not is_lethal or not data.last_lethal_check or 
           (globals.tickcount() - data.last_lethal_check) > 5 then
            
            local health = get_cached_prop(player, "m_iHealth", 100)
            local lethal_threshold = ui.get(ui_smart_baim.lethal_threshold)
            
            if health and health <= lethal_threshold then
                local local_player = entity.get_local_player()
                if local_player then
                    local body_damage = calculate_body_damage(player, local_player)
                    data.estimated_body_damage = body_damage
                    
                    if body_damage >= health then
                        is_lethal = true
                        data.body_aimable = true
                        data.lethal_shot_available = true
                        data.last_lethal_check = globals.tickcount()
                        lethal_count = lethal_count + 1
                    else
                        is_lethal = false
                        data.lethal_shot_available = false
                    end
                end
            else
                is_lethal = false
                data.lethal_shot_available = false
            end
        elseif is_lethal then
            lethal_count = lethal_count + 1
        end
            
            if is_lethal then
                local screen_x, screen_y
                
                -- Try bounding box first
                local bbox_x1, bbox_y1, bbox_x2, bbox_y2 = entity.get_bounding_box(player)
                
                if bbox_x1 then
                    screen_x = (bbox_x1 + bbox_x2) / 2
                    screen_y = bbox_y1 - 15  -- Move up a bit
                else
                    -- Fallback to world position
                    local x, y, z = entity.get_prop(player, "m_vecOrigin")
                    if x and y and z then
                        screen_x, screen_y = renderer.world_to_screen(x, y, z + 75)
                    end
                end
                
                if not screen_x or not screen_y then 
                    goto continue 
                end
                
                local enemy_health = health or 0
                local estimated_dmg = data.estimated_body_damage or 0
                
                -- Draw based on style
                if style == "Simple" then
                    renderer.text(screen_x, screen_y, r, g, b, pulse_alpha, "c", 0, "LETHAL")
                
                elseif style == "Detailed" then
                    renderer.text(screen_x, screen_y, r, g, b, pulse_alpha, "c", 0, 
                        string.format("LETHAL %dHP", enemy_health))
                
                elseif style == "Box highlight" then
                    local text = "⚠ LETHAL ⚠"
                    local text_width, text_height = renderer.measure_text("", text)
                    
                    local box_x = screen_x - text_width / 2 - 4
                    local box_y = screen_y - 10
                    local box_w = text_width + 8
                    local box_h = text_height + 4
                    
                    renderer.rectangle(box_x, box_y, box_w, box_h, 0, 0, 0, 180)
                    renderer.rectangle(box_x - 1, box_y - 1, box_w + 2, 1, r, g, b, pulse_alpha)
                    renderer.rectangle(box_x - 1, box_y + box_h, box_w + 2, 1, r, g, b, pulse_alpha)
                    renderer.rectangle(box_x - 1, box_y, 1, box_h, r, g, b, pulse_alpha)
                    renderer.rectangle(box_x + box_w, box_y, 1, box_h, r, g, b, pulse_alpha)
                    
                    renderer.text(screen_x, box_y + 2, r, g, b, 255, "c", 0, text)
                    
                elseif style == "All" then
                    local text = "⚠ LETHAL ⚠"
                    local text_width, text_height = renderer.measure_text("c", text)
                    
                    local box_x = screen_x - text_width / 2 - 6
                    local box_y = screen_y - 15
                    local box_w = text_width + 12
                    local box_h = text_height + 6
                    
                    renderer.rectangle(box_x, box_y, box_w, box_h, 0, 0, 0, 180 + pulse * 50)
                    renderer.gradient(box_x, box_y, box_w, 2, r, g, b, pulse_alpha, r, g, b, 0, true)
                    renderer.gradient(box_x, box_y + box_h - 2, box_w, 2, r, g, b, 0, r, g, b, pulse_alpha, true)
                    
                    renderer.rectangle(box_x - 1, box_y - 1, box_w + 2, 1, r, g, b, pulse_alpha)
                    renderer.rectangle(box_x - 1, box_y + box_h, box_w + 2, 1, r, g, b, pulse_alpha)
                    renderer.rectangle(box_x - 1, box_y - 1, 1, box_h + 2, r, g, b, pulse_alpha)
                    renderer.rectangle(box_x + box_w, box_y - 1, 1, box_h + 2, r, g, b, pulse_alpha)
                    
                    renderer.text(screen_x, box_y + 3, r, g, b, 255, "c", 0, text)
                    renderer.text(screen_x, screen_y + 15, 255, 255, 255, 200, "c", 0, 
                        string.format("%dHP | %dDMG", enemy_health, estimated_dmg))
                end
            end
        end
        ::continue::
    end
    
    -- DEBUG: Show count
    -- if ui.get(ui_elements.debug) and lethal_count > 0 then
        -- client.log(string.format("Lethal targets visible: %d", lethal_count))
    -- end
end

-- ===========================
-- RESOLVER ESP FLAGS
-- ===========================

-- FLAG 1: RESOLVED ✓ (Green checkmark = Working!)
client.register_esp_flag("Resolved ✓", 0, 255, 0, function(entindex)
    if not ui.get(ui_elements.enable) then return false end
    if not ui.get(ui_elements.resolver_flags) then return false end
    if not entity.is_enemy(entindex) then return false end
    if not entity.is_alive(entindex) then return false end
    
    local data = resolver_data[entindex]
    if not data then return false end
    
    -- Show green checkmark when confident (>65%)
    return data.confidence and data.confidence >= 65
end)

-- FLAG 2: SIDE (L/R = Which side we're shooting)
client.register_esp_flag("", 255, 255, 255, function(entindex)
    if not ui.get(ui_elements.enable) then return false end
    if not ui.get(ui_elements.resolver_flags) then return false end
    if not entity.is_enemy(entindex) then return false end
    if not entity.is_alive(entindex) then return false end
    
    local data = resolver_data[entindex]
    if not data or not data.resolved_angle then return false end
    
    -- Simple L/R indicator
    if data.resolved_angle > 5 then
        return "Right Desync →"  -- Right arrow
    elseif data.resolved_angle < -5 then
        return "Left Desync ←"  -- Left arrow
    end
    
    return false
end)

-- FLAG 3: ⚠ DEF (Red warning = Defensive AA active)
client.register_esp_flag("DEFENSIVE AA ⚠", 255, 50, 50, function(entindex)
    if not ui.get(ui_elements.enable) then return false end
    if not ui.get(ui_elements.resolver_flags) then return false end
    if not entity.is_enemy(entindex) then return false end
    if not entity.is_alive(entindex) then return false end
    
    local data = resolver_data[entindex]
    if not data then return false end
    
    -- Show red warning when defensive AA detected
    return data.is_defensive and data.defensive_ticks > 0
end)

-- FLAG 4 (OPTIONAL): BRUTE PHASE (Only when bruteforcing)
client.register_esp_flag("", 255, 200, 100, function(entindex)
    if not ui.get(ui_elements.enable) then return false end
    if not ui.get(ui_elements.resolver_flags) then return false end
    if not entity.is_enemy(entindex) then return false end
    if not entity.is_alive(entindex) then return false end
    
    local mode = ui.get(ui_elements.mode)
    -- Only show if bruteforcing
    if mode ~= "Bruteforce" and mode ~= "Adaptive" then
        return false
    end
    
    local data = resolver_data[entindex]
    if not data or not data.brute_phase then return false end
    
    -- Show current phase
    return string.format("%d", data.brute_phase)
end)

-- ===========================
-- SETUP COMMAND (DEFENSIVE PEEK + FAKELAG)
-- ===========================
client.set_event_callback("setup_command", function(cmd)
    if not ui.get(ui_elements.enable) then return end
    
    -- Track weapon switches and save min damage
    local current_weapon_id = get_local_weapon_id()
    if current_weapon_id and current_weapon_id ~= last_weapon_id then
        save_current_mindmg()
        last_weapon_id = current_weapon_id
    end
    
    -- Fakelag optimizer
    optimize_fakelag()
    
    -- Defensive peek
    local force_defensive = should_force_defensive_peek()
    if force_defensive then
        cmd.force_defensive = true
    end

    -- ✅ FIXED: Apply smart baim FIRST, then check defensive delay
    local enemies = entity.get_players(true)
    if enemies then
        for i = 1, #enemies do
            local player = enemies[i]
            if entity.is_alive(player) then
                local data = resolver_data[player]
                
                if data then
                    -- ✅ ALWAYS apply smart baim override (even if defensive active)
                    if ui.get(ui_smart_baim.enable) then
                        apply_smart_hitbox_override(player, data)  -- ✅ Fixed: added (player, data)
                    end
                    
                    -- ✅ THEN check if we should block shots due to defensive delay
                    if ui.get(ui_defensive_delay.enable) and data.block_shots then
                        local me = entity.get_local_player()
                        if not me then goto continue end
                        
                        local weapon = entity.get_player_weapon(me)
                        if not weapon then goto continue end
                        
                        local weapon_id = entity.get_prop(weapon, "m_iItemDefinitionIndex")
                        if not weapon_id then goto continue end
                        
                        -- ✅ Check weapon type before blocking
                        local is_gun = (
                            -- Pistols
                            weapon_id == 1 or weapon_id == 2 or weapon_id == 3 or weapon_id == 4 or 
                            weapon_id == 30 or weapon_id == 32 or weapon_id == 36 or weapon_id == 61 or 
                            weapon_id == 63 or weapon_id == 64 or
                            -- Rifles
                            weapon_id == 7 or weapon_id == 8 or weapon_id == 10 or weapon_id == 13 or 
                            weapon_id == 16 or weapon_id == 39 or weapon_id == 60 or
                            -- SMGs
                            weapon_id == 17 or weapon_id == 19 or weapon_id == 24 or weapon_id == 26 or 
                            weapon_id == 33 or weapon_id == 34 or
                            -- Snipers
                            weapon_id == 9 or weapon_id == 11 or weapon_id == 38 or weapon_id == 40 or
                            -- Shotguns
                            weapon_id == 25 or weapon_id == 27 or weapon_id == 29 or weapon_id == 35 or
                            -- Machine guns
                            weapon_id == 14 or weapon_id == 28
                        )
                        
                        -- Block shooting if holding a gun
                        if is_gun then
                            cmd.in_attack = false
                        end
                        -- If holding utility/bomb/knife, DON'T block anything
                    end
                    
                    ::continue::
                end
            end
        end
    end
    
    -- Min damage override for lethal shots
    if ui.get(ui_smart_baim.enable) and 
       ui.get(ui_smart_baim.lethal_enable) and 
       ui.get(ui_smart_baim.lethal_override_mindmg) then
        
        local current_target = client.current_threat()
        
        if current_target and entity.is_alive(current_target) then
            local data = resolver_data[current_target]
            
            if data and data.lethal_mindmg_required then
                local required_dmg = data.lethal_mindmg_required
                
                if current_target ~= last_target or required_dmg ~= last_mindmg_value then
                    if ref_mindmg then
                        save_current_mindmg()
                        
                        ui.set(ref_mindmg, required_dmg)
                        last_mindmg_value = required_dmg
                        last_target = current_target
                    end
                end
            else
                if last_mindmg_value ~= nil then
                    restore_mindmg()
                    last_mindmg_value = nil
                end
            end
        else
            if last_mindmg_value ~= nil then
                restore_mindmg()
                last_mindmg_value = nil
                last_target = nil
            end
        end
    else
        if last_mindmg_value ~= nil then
            restore_mindmg()
            last_mindmg_value = nil
            last_target = nil
        end
    end
end)

-- Reset backtrack on weapon fire to ensure clean shots
client.set_event_callback("weapon_fire", function(event)
    if not ui.get(ui_elements.enable) then return end
    if not ui.get(ui_elements.defensive_peek_fix) then return end
    
    local userid = client.userid_to_entindex(event.userid)
    local local_player = entity.get_local_player()
    
    if userid == local_player then
        -- Reset our own position to ensure clean shot
        local origin_x, origin_y, origin_z = entity.get_prop(local_player, "m_vecOrigin")
        if origin_x then
            entity.set_prop(local_player, "m_vecOrigin", origin_x, origin_y, origin_z)
        end
    end
end)

-- ===========================
-- CONFIG PRESETS (UPDATED)
-- ===========================
local config_presets = {
    ["Default"] = {
    mode = "AI",
    detection = {
        "Animation Analysis",
        "Movement Tracking",
        "LBY Analysis",
        "Velocity Prediction",
        "Pose Parameters",
        "Layer Weight",
        "Micro Movement",
        "Standing Detection",
        "Pattern Recognition",
        "Desync Break Detection"
    },
    defensive = true,
    defensive_options = {
        "Simulation Check",
        "Lag Compensation",
        "Velocity Exploit",
        "Teleport Detection",
        "Smart Backtrack",
        "Prediction Fix",
        "Layer Correlation"
    },
    brute_mode = "Intelligent",
    brute_phases = 5,
    brute_reset = 2,
    advanced = {
        "Anti-Freestand",
        "Body Aim Fix",
        "Low Delta Detect",
        "Jitter Detection",
        "Micro Movement",
        "Standing Resolver",
        "Smart Prediction",
        "Animation Fix",
        "Pattern Analysis",
        "Context Awareness",
        "Peek Prediction",
        "Adaptive Learning",
        "Weapon Awareness"
    },
    desync_strength = 75,
    confidence = 70,
    reaction_time = 5,
    ai_aggression = 80,
    ai_learning = 90,
    indicator = false,  
    indicator_style = "Detailed",
    watermark = true,
    debug = false,
    console_log = false,
    
    -- smart baim settings
    smart_baim_enable = true,
    smart_baim_mode = "Default",
    smart_baim_lethal_enable = true,
    smart_baim_lethal_threshold = 70,
    smart_baim_lethal_mode = "Prefer body (flexible)",
    smart_baim_lethal_override_mindmg = false,
    smart_baim_show_lethal_flag = true,
    smart_baim_lethal_flag_style = "Simple",
    smart_baim_accuracy_threshold = 70,
    
    -- experimental features
    ideal_tick_enable = true,
    fakelag_enable = true,

    -- defensive peek
    defensive_peek_fix = true,
    peek_prediction_time = 50,
    peek_min_damage = 10,
    peek_auto_enable = {
        "Enemy has AWP",
        "Enemy has Scout",
        "You have AWP/Scout",
        "Low health (<50HP)"
    },
    
    resolver_flags = true,
    
    description = "All features enabled - balanced for HvH"
},

    ["Aggressive"] = {
        mode = "AI",
        detection = {
            "Animation Analysis",
            "LBY Analysis",
            "Pattern Recognition",
            "Desync Break Detection",
            "Micro Movement",
        },
        defensive = true,
        defensive_options = {
            "Simulation Check",
            "Velocity Exploit",
            "Teleport Detection",
        },
        brute_mode = "Adaptive",
        brute_phases = 7,
        brute_reset = 1,
        advanced = {
            "Anti-Freestand",
            "Body Aim Fix", 
            "Jitter Detection",
            "Micro Movement",
            "Smart Prediction",
            "Peek Prediction",
            "Adaptive Learning",
            "Weapon Awareness",
        },
        desync_strength = 85,
        confidence = 60,
        reaction_time = 3,
        ai_aggression = 95,
        ai_learning = 85,
        indicator = false,
        indicator_style = "Detailed",
        watermark = false,
        debug = false,
        
        -- smart baim setting
        smart_baim_enable = true,
        smart_baim_mode = "Aggressive",
        smart_baim_lethal_enable = true,
        smart_baim_lethal_threshold = 70,
        smart_baim_lethal_mode = "Force body (strict)",
        smart_baim_lethal_override_mindmg = false,
        smart_baim_show_lethal_flag = true,
        smart_baim_lethal_flag_style = "Detailed",
        smart_baim_accuracy_threshold = 60,
        
        -- experimental
        ideal_tick_enable = true,
        fakelag_enable = true,

        -- defensive peek
        defensive_peek_fix = true,
        peek_prediction_time = 120,  -- Fast peeking
        peek_min_damage = 20,
        peek_auto_enable = {"You have AWP/Scout", "Enemy has AWP"},
        
        description = "Scout users"
    },

    ["Defensive"] = {
        mode = "AI",
        detection = {
            "Animation Analysis",
            "LBY Analysis", 
            "Movement Tracking",
            "Pattern Recognition",
            "Desync Break Detection",
            "Micro Movement",
        },
        defensive = true,
        defensive_options = {
            "Simulation Check",
            "Velocity Exploit", 
            "Teleport Detection",
            "Layer Correlation",
        },
        brute_mode = "Intelligent",
        brute_phases = 6,
        brute_reset = 2,
        advanced = {
            "Anti-Freestand",
            "Body Aim Fix",
            "Jitter Detection", 
            "Smart Prediction",
            "Context Awareness",
            "Peek Prediction",
            "Adaptive Learning",
            "Weapon Awareness",
        },
        desync_strength = 75,
        confidence = 70,
        reaction_time = 5,
        ai_aggression = 80,
        ai_learning = 90,
        indicator = false,
        indicator_style = "Detailed",
        watermark = true,
        debug = false,
        
        -- smart baim setting
        smart_baim_enable = true,
        smart_baim_mode = "Defensive",
        smart_baim_lethal_enable = true,
        smart_baim_lethal_threshold = 85,
        smart_baim_lethal_mode = "Prefer body (flexible)",
        smart_baim_lethal_override_mindmg = false,
        smart_baim_show_lethal_flag = true,
        smart_baim_lethal_flag_style = "Detailed",
        smart_baim_accuracy_threshold = 85,
        
        -- experimental feature
        ideal_tick_enable = true,
        fakelag_enable = true,

        -- defensive peek
        defensive_peek_fix = true,
        peek_prediction_time = 250,  -- Slower when holding angles
        peek_min_damage = 30,
        peek_auto_enable = {"Enemy has AWP", "Enemy has Scout", "Low health (<50HP)"},
        
        description = "Auto users"
    }
}

-- ===========================
-- CONFIG SYSTEM
-- ===========================
local config_system = {}

function config_system.get_current_config()
    return {
        mode = ui.get(ui_elements.mode),
        detection = ui.get(ui_elements.detection),
        defensive = ui.get(ui_elements.defensive),
        defensive_options = ui.get(ui_elements.defensive_options),
        brute_mode = ui.get(ui_elements.brute_mode),
        brute_phases = ui.get(ui_elements.brute_phases),
        brute_reset = ui.get(ui_elements.brute_reset),
        advanced = ui.get(ui_elements.advanced),
        desync_strength = ui.get(ui_elements.desync_strength),
        confidence = ui.get(ui_elements.confidence),
        reaction_time = ui.get(ui_elements.reaction_time),
        ai_aggression = ui.get(ui_elements.ai_aggression),
        ai_learning = ui.get(ui_elements.ai_learning),
        indicator = ui.get(ui_elements.indicator),
        indicator_style = ui.get(ui_elements.indicator_style),
        watermark = ui.get(ui_elements.watermark),
        debug = ui.get(ui_elements.debug),
        smart_baim_enable = ui.get(ui_smart_baim.enable),
        smart_baim_mode = ui.get(ui_smart_baim.mode),
        smart_baim_lethal_enable = ui.get(ui_smart_baim.lethal_enable),
        smart_baim_lethal_threshold = ui.get(ui_smart_baim.lethal_threshold),
        smart_baim_lethal_mode = ui.get(ui_smart_baim.lethal_mode),
        smart_baim_show_lethal_flag = ui.get(ui_smart_baim.show_lethal_flag),
        smart_baim_lethal_flag_style = ui.get(ui_smart_baim.lethal_flag_style),
        ideal_tick_enable = ui.get(ui_ideal_tick.enable),
        fakelag_enable = ui.get(ui_fakelag.enable),
        defensive_peek_fix = ui.get(ui_elements.defensive_peek_fix),
        peek_prediction_time = ui.get(ui_elements.peek_prediction_time),
        peek_min_damage = ui.get(ui_elements.peek_min_damage),
        peek_auto_enable = ui.get(ui_elements.peek_auto_enable),
        resolver_flags = ui.get(ui_elements.resolver_flags)
    }
end

function config_system.apply_config(config)
    ui.set(ui_elements.mode, config.mode)
    ui.set(ui_elements.detection, config.detection)
    ui.set(ui_elements.defensive, config.defensive)
    ui.set(ui_elements.defensive_options, config.defensive_options)
    ui.set(ui_elements.brute_mode, config.brute_mode)
    ui.set(ui_elements.brute_phases, config.brute_phases)
    ui.set(ui_elements.brute_reset, config.brute_reset)
    ui.set(ui_elements.advanced, config.advanced)
    ui.set(ui_elements.desync_strength, config.desync_strength)
    ui.set(ui_elements.confidence, config.confidence)
    ui.set(ui_elements.reaction_time, config.reaction_time)
    
    if config.ai_aggression ~= nil then
        ui.set(ui_elements.ai_aggression, config.ai_aggression)
    end
    if config.ai_learning ~= nil then
        ui.set(ui_elements.ai_learning, config.ai_learning)
    end
    
    if config.indicator ~= nil then
        ui.set(ui_elements.indicator, config.indicator)
    end
    if config.indicator_style ~= nil then
        ui.set(ui_elements.indicator_style, config.indicator_style)
    end
    if config.watermark ~= nil then
        ui.set(ui_elements.watermark, config.watermark)
    end
    if config.debug ~= nil then
        ui.set(ui_elements.debug, config.debug)
    end
    
    -- smart baim setting
    if config.smart_baim_enable ~= nil then
        ui.set(ui_smart_baim.enable, config.smart_baim_enable)
    end
    if config.smart_baim_mode ~= nil then
        ui.set(ui_smart_baim.mode, config.smart_baim_mode)
    end
    if config.smart_baim_lethal_enable ~= nil then
        ui.set(ui_smart_baim.lethal_enable, config.smart_baim_lethal_enable)
    end
    if config.smart_baim_lethal_threshold ~= nil then
        ui.set(ui_smart_baim.lethal_threshold, config.smart_baim_lethal_threshold)
    end
    if config.smart_baim_lethal_mode ~= nil then
        ui.set(ui_smart_baim.lethal_mode, config.smart_baim_lethal_mode)
    end
    if config.smart_baim_lethal_override_mindmg ~= nil then
        ui.set(ui_smart_baim.lethal_override_mindmg, config.smart_baim_lethal_override_mindmg)
    end
    if config.smart_baim_show_lethal_flag ~= nil then
        ui.set(ui_smart_baim.show_lethal_flag, config.smart_baim_show_lethal_flag)
    end
    if config.smart_baim_lethal_flag_style ~= nil then
        ui.set(ui_smart_baim.lethal_flag_style, config.smart_baim_lethal_flag_style)
    end

    if config.smart_baim_accuracy_threshold ~= nil then
        ui.set(ui_smart_baim.accuracy_threshold, config.smart_baim_accuracy_threshold)
    end
    
    -- experimental subject to changes
    if config.ideal_tick_enable ~= nil then
        ui.set(ui_ideal_tick.enable, config.ideal_tick_enable)
    end
    if config.fakelag_enable ~= nil then
        ui.set(ui_fakelag.enable, config.fakelag_enable)
    end

    -- defensive peek
    if config.defensive_peek_fix ~= nil then
        ui.set(ui_elements.defensive_peek_fix, config.defensive_peek_fix)
    end
    if config.peek_prediction_time ~= nil then
        ui.set(ui_elements.peek_prediction_time, config.peek_prediction_time)
    end
    if config.peek_min_damage ~= nil then
        ui.set(ui_elements.peek_min_damage, config.peek_min_damage)
    end
    if config.peek_auto_enable ~= nil then
        ui.set(ui_elements.peek_auto_enable, config.peek_auto_enable)
    end

    if config.resolver_flags ~= nil then
        ui.set(ui_elements.resolver_flags, config.resolver_flags)
    end
end

function config_system.load_preset()
    local selected = ui.get(ui_elements.config_preset)
    
    if selected == "Custom" then
        client.log("Guardian Enhanced: Custom config selected - no preset to load")
        return
    end
    
    local preset = config_presets[selected]
    if preset then
        config_system.apply_config(preset)
        client.log("Guardian Enhanced: Loaded preset '" .. selected .. "'")
        if preset.description then
            client.log("→ " .. preset.description)
        end
        
        -- Set preset selector back to Custom after loading
        client.delay_call(0.1, function()
            ui.set(ui_elements.config_preset, "Custom")
        end)
    else
        client.log("Guardian Enhanced: Preset not found!")
    end
end

function config_system.export_config()
    local config = config_system.get_current_config()
    local json_str = json.stringify(config)
    local encoded = base64.encode(json_str)
    clipboard_util.set(encoded)
    client.log("Guardian Enhanced: Config exported to clipboard!")
end

function config_system.import_config()
    local encoded = clipboard_util.get()
    if not encoded then
        client.log("Guardian Enhanced: Clipboard is empty!")
        return
    end
    
    local success, json_str = pcall(base64.decode, encoded)
    if not success then
        client.log("Guardian Enhanced: Failed to decode config!")
        return
    end
    
    local success2, config = pcall(json.parse, json_str)
    if not success2 then
        client.log("Guardian Enhanced: Failed to parse config!")
        return
    end
    
    config_system.apply_config(config)
    client.log("Guardian Enhanced: Config imported successfully!")
end

-- Button callbacks
ui.set_callback(ui_elements.config_preset, function()
    local selected = ui.get(ui_elements.config_preset)
    if selected == "Custom" then
        ui.set(ui_elements.config_description, "Custom configuration - your current settings")
    else
        local preset = config_presets[selected]
        if preset and preset.description then
            ui.set(ui_elements.config_description, preset.description)
        end
    end
end)

ui.set_callback(ui_elements.config_load, function()
    config_system.load_preset()
end)

ui.set_callback(ui_elements.config_export, function()
    config_system.export_config()
end)

ui.set_callback(ui_elements.config_import, function()
    config_system.import_config()
end)

-- ===========================
-- MENU VISIBILITY
-- ===========================
local function handle_menu_visibility()
    local function safe_set_visible(element, state, name)
        local success, err = pcall(function()
            ui.set_visible(element, state)
        end)
        if not success then
            client.log(string.format("ERROR setting visibility for '%s': %s", name or "unknown", tostring(err)))
            client.log(string.format("  element type: %s, state type: %s, state value: %s", 
                type(element), type(state), tostring(state)))
        end
        return success
    end
    
    local enabled = ui.get(ui_elements.enable)
    local mode = ui.get(ui_elements.mode)
    local defensive = ui.get(ui_elements.defensive)
    local indicator = ui.get(ui_elements.indicator)
    
    -- resolver mode
    safe_set_visible(ui_elements.mode, enabled, "mode")
    safe_set_visible(ui_elements.indicator, enabled, "indicator")
    safe_set_visible(ui_elements.detection, enabled and (mode == "Smart" or mode == "Automatic" or mode == "Adaptive" or mode == "AI"), "detection")
    safe_set_visible(ui_elements.defensive, enabled, "defensive")
    safe_set_visible(ui_elements.defensive_options, enabled and defensive, "defensive_options")
    safe_set_visible(ui_elements.brute_mode, enabled and (mode == "Bruteforce" or mode == "Adaptive" or mode == "AI"), "brute_mode")
    safe_set_visible(ui_elements.brute_phases, enabled and (mode == "Bruteforce" or mode == "Adaptive" or mode == "AI"), "brute_phases")
    safe_set_visible(ui_elements.brute_reset, enabled and (mode == "Bruteforce" or mode == "Adaptive" or mode == "AI"), "brute_reset")
    safe_set_visible(ui_elements.advanced, enabled, "advanced")
    safe_set_visible(ui_elements.override_left, enabled and mode == "Override", "override_left")
    safe_set_visible(ui_elements.override_right, enabled and mode == "Override", "override_right")
    safe_set_visible(ui_elements.override_center, enabled and mode == "Override", "override_center")
    safe_set_visible(ui_elements.desync_strength, enabled, "desync_strength")
    safe_set_visible(ui_elements.confidence, enabled and (mode == "Adaptive" or mode == "AI"), "confidence")
    safe_set_visible(ui_elements.reaction_time, enabled, "reaction_time")
    safe_set_visible(ui_elements.ai_aggression, enabled and mode == "AI", "ai_aggression")
    safe_set_visible(ui_elements.ai_learning, enabled and mode == "AI", "ai_learning")
    safe_set_visible(ui_elements.indicator_style, enabled and indicator, "indicator_style")
    safe_set_visible(ui_elements.watermark, enabled, "watermark")
    safe_set_visible(ui_elements.debug, enabled, "debug")
    safe_set_visible(ui_elements.console_log, enabled, "console_log")

    -- Defensive peek system
    safe_set_visible(ui_elements.defensive_peek_separator, enabled, "defensive_peek_separator")
    safe_set_visible(ui_elements.defensive_peek_fix, enabled, "defensive_peek_fix")
    
    local peek_enabled = enabled and ui.get(ui_elements.defensive_peek_fix)
    safe_set_visible(ui_elements.peek_prediction_time, peek_enabled, "peek_prediction_time")
    safe_set_visible(ui_elements.peek_min_damage, peek_enabled, "peek_min_damage")
    safe_set_visible(ui_elements.peek_auto_enable, peek_enabled, "peek_auto_enable")

    -- Smart body aim visibility
    safe_set_visible(ui_smart_baim.enable, enabled, "smart_baim_enable")
    local smart_baim_enabled = enabled and ui.get(ui_smart_baim.enable)
    -- defensive shot delay
    safe_set_visible(ui_defensive_delay.enable, enabled, "defensive_delay_enable")
    
    safe_set_visible(ui_smart_baim.separator1, smart_baim_enabled, "smart_baim_sep1")
    safe_set_visible(ui_smart_baim.mode, smart_baim_enabled, "smart_baim_mode")
    
    safe_set_visible(ui_smart_baim.separator2, smart_baim_enabled, "smart_baim_sep2")
    safe_set_visible(ui_smart_baim.lethal_enable, smart_baim_enabled, "smart_baim_lethal_enable")
    
    local lethal_enabled = smart_baim_enabled and ui.get(ui_smart_baim.lethal_enable)
    safe_set_visible(ui_smart_baim.lethal_threshold, lethal_enabled, "smart_baim_lethal_threshold")
    safe_set_visible(ui_smart_baim.lethal_mode, lethal_enabled, "smart_baim_lethal_mode")
    safe_set_visible(ui_smart_baim.accuracy_threshold, lethal_enabled, "smart_baim_accuracy_threshold")

    safe_set_visible(ui_smart_baim.lethal_override_mindmg, lethal_enabled, "smart_baim_lethal_override_mindmg")
    
    safe_set_visible(ui_smart_baim.separator3, smart_baim_enabled, "smart_baim_sep3")
    safe_set_visible(ui_smart_baim.show_lethal_flag, smart_baim_enabled, "smart_baim_show_flag")

    -- lethal flag
    local flag_enabled = smart_baim_enabled and ui.get(ui_smart_baim.show_lethal_flag)
    safe_set_visible(ui_smart_baim.lethal_flag_style, flag_enabled, "smart_baim_flag_style")
    safe_set_visible(ui_smart_baim.lethal_flag_color, flag_enabled, "smart_baim_flag_color")
    
    -- SIMPLIFIED: Ideal tick (only checkbox - fully automatic)
    safe_set_visible(ui_ideal_tick.enable, enabled, "ideal_tick_enable")
    
    -- SIMPLIFIED: Fakelag (only checkbox - fully automatic)
    safe_set_visible(ui_fakelag.enable, enabled, "fakelag_enable")

    -- show lethal flag ui
    local flag_active = smart_baim_enabled and ui.get(ui_smart_baim.show_lethal_flag)
    safe_set_visible(ui_smart_baim.lethal_flag_style, flag_active, "smart_baim_flag_style")
    safe_set_visible(ui_smart_baim.lethal_flag_color, flag_active, "smart_baim_flag_color")
    
    -- cfg 
    safe_set_visible(ui_elements.config_separator, enabled, "config_separator")
    safe_set_visible(ui_elements.config_preset, enabled, "config_preset")
    safe_set_visible(ui_elements.config_description, enabled, "config_description")
    safe_set_visible(ui_elements.config_load, enabled, "config_load")
    safe_set_visible(ui_elements.config_separator2, enabled, "config_separator2")
    safe_set_visible(ui_elements.config_export, enabled, "config_export")
    safe_set_visible(ui_elements.config_import, enabled, "config_import")
    
    -- resolver indicator
    safe_set_visible(ui_elements.resolver_flags_separator, enabled, "resolver_flags_sep")
    safe_set_visible(ui_elements.resolver_flags, enabled, "resolver_flags")
end

-- ===========================
-- MAIN LOOP
-- ===========================
client.set_event_callback("paint", function()
    -- early exit
    if not ui.get(ui_elements.enable) then return end

    draw_indicator()
    draw_debug_info()
    draw_watermark()
    draw_lethal_flags()
end)

-- ✅ NEW: Run resolver once per tick instead of 60 times per second
client.set_event_callback("net_update_end", function()
    if not ui.get(ui_elements.enable) then 
        -- Clear all settings when disabled
        local all_players = entity.get_players(true)
        if all_players then
            for i = 1, #all_players do
                plist.set(all_players[i], "Force body yaw", false)
            end
        end
        return 
    end
    for player, data in pairs(resolver_data) do
        if not entity.is_alive(player) or entity.is_dormant(player) then
            if not data.dormant_ticks then
                data.dormant_ticks = 0
            end
            data.dormant_ticks = data.dormant_ticks + 1
            
            if data.dormant_ticks > 32 then
                resolver_data[player] = nil
                lag_records[player] = nil
                defensive_records[player] = nil
                speed_cache[player] = nil
                speed_cache_time[player] = nil
                damage_cache[player] = nil
                damage_cache_time[player] = nil
                eye_angle_data[player] = nil
                resolver_cache[player] = nil
                defensive_check_cache[player] = nil
                defensive_check_time[player] = nil
            end
        else
            if data.dormant_ticks then
                data.dormant_ticks = 0
            end
        end
    end
    
    local enemies = entity.get_players(true)
    if not enemies or #enemies == 0 then return end
    
    for i = 1, #enemies do
        local enemy = enemies[i]
        if not entity.is_alive(enemy) then
            plist.set(enemy, "Force body yaw", false)
            goto continue
        end
        
        plist.set(enemy, "Correction active", true)
        resolve_player(enemy)
        
        ::continue::
    end
end)

-- ===========================
-- EVENT CALLBACKS
-- ===========================
client.set_event_callback("aim_miss", on_aim_miss)
client.set_event_callback("aim_hit", on_aim_hit)
client.set_event_callback("round_start", on_round_start)

client.set_event_callback("player_death", function(e)
    local victim = client.userid_to_entindex(e.userid)
    if victim and resolver_data[victim] then
        -- Clear plist settings for dead player
        pcall(function()
            plist.set(victim, "Force body yaw", false)
            plist.set(victim, "Force body yaw value", 0)
            plist.set(victim, "Correction active", true)  -- Re-enable for respawn
            plist.set(victim, "Override prefer body aim", "-")
            plist.set(victim, "Override safe point", "-")
            plist.set(victim, "Minimum damage override", 0)

        end)
    end
end)

-- Menu callbacks
ui.set_callback(ui_elements.enable, handle_menu_visibility)
ui.set_callback(ui_elements.mode, handle_menu_visibility)
ui.set_callback(ui_elements.indicator, handle_menu_visibility)
ui.set_callback(ui_elements.defensive, handle_menu_visibility)

-- Experimental features - nemu
ui.set_callback(ui_elements.defensive_peek_fix, handle_menu_visibility)
ui.set_callback(ui_defensive_delay.enable, handle_menu_visibility)
ui.set_callback(ui_smart_baim.enable, handle_menu_visibility)
ui.set_callback(ui_smart_baim.lethal_enable, handle_menu_visibility)
ui.set_callback(ui_smart_baim.show_lethal_flag, handle_menu_visibility)
ui.set_callback(ui_ideal_tick.enable, handle_menu_visibility)
ui.set_callback(ui_fakelag.enable, handle_menu_visibility)
ui.set_callback(ui_elements.resolver_flags, handle_menu_visibility)

-- ===========================
-- INITIALIZATION
-- ===========================
handle_menu_visibility()

-- Set initial description
ui.set(ui_elements.config_description, "Custom configuration - your current settings")

client.log("Guardian Enhanced loaded successfully!")
client.log("Version: 1.0.0 | Release")
client.log("Bruteforce Improvements, Extrapolation improvements and few bug fixes")

-- Cleanup when player disconnects
client.set_event_callback("player_disconnect", function(e)
    local player = client.userid_to_entindex(e.userid)
    if not player then return end
    
    -- Clear all data for disconnected player
    resolver_data[player] = nil
    lag_records[player] = nil
    defensive_records[player] = nil
    speed_cache[player] = nil
    speed_cache_time[player] = nil
    damage_cache[player] = nil
    damage_cache_time[player] = nil
    eye_angle_data[player] = nil
    resolver_cache[player] = nil
    defensive_check_cache[player] = nil
    defensive_check_time[player] = nil
    
    -- Clear plist settings
    pcall(function()
        plist.set(player, "Force body yaw", false)
        plist.set(player, "Force body yaw value", 0)
        plist.set(player, "Override prefer body aim", "-")
        plist.set(player, "Override safe point", "-")
    end)
end)

-- Cleanup on unload
client.set_event_callback("shutdown", function()
    
    if last_mindmg_value ~= nil then
        restore_mindmg()
        last_mindmg_value = nil
        last_target = nil
    end
    
    -- Disable all forced body yaw
    local enemies = entity.get_players(true)
    if enemies then
        for i = 1, #enemies do
            pcall(function()
                plist.set(enemies[i], "Force body yaw", false)
                plist.set(enemies[i], "Force body yaw value", 0)
                plist.set(enemies[i], "Override prefer body aim", "-")
                plist.set(enemies[i], "Override safe point", "-")
            end)
        end
    end
    client.log("Guardian Enhanced unloaded")
end)
