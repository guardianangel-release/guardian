local ffi = require "ffi"
local exploits = require "gamesense/extended_exploits" 

-- ============================================================================
-- GLOBAL STATE PARAMETERS & UTILITIES
-- ============================================================================
local velocity_history = {}
local last_config_check = 0 
local config_cache = nil 

local function contains(tbl, val)
    if not tbl then return false end 
    for i=1, #tbl do
        if tbl[i] == val then return true end 
    end
    return false 
end

local function safe_get_prop(ent, prop, index)
    if not entity then return nil end 
    local success, value = pcall(entity.get_prop, ent, prop, index) 
    return success and value or nil 
end

-- ============================================================================
-- UI INTERFACE ARCHITECTURE
-- ============================================================================
local ui_elements = {
    enable = ui.new_checkbox("RAGE", "Aimbot", "Enhanced Prediction Control"), 
    mode = ui.new_combobox("RAGE", "Aimbot", "Interpolation Mode", {"Minimum", "Medium", "High", "Adaptive", "Dynamic", "Aggressive"}), 
    indicator = ui.new_checkbox("RAGE", "Aimbot", "Show Indicator"), 
    adaptive_options = ui.new_multiselect("RAGE", "Aimbot", "Adaptive Options", { 
        "Auto Speed Adjust", "Ping Compensation", "Smart Interp", "Movement Predict", "Crouch Predict", "Advanced Calculation" 
    }),
    min_speed = ui.new_slider("RAGE", "Aimbot", "Min Speed Threshold", 0, 250, 100, true, "u"), 
    max_ping = ui.new_slider("RAGE", "Aimbot", "Max Ping Compensation", 0, 200, 80, true, "ms"), 
    crouch_predict = ui.new_slider("RAGE", "Aimbot", "Crouch Prediction", 0, 100, 50, true, "%"), 
    indicator_style = ui.new_combobox("RAGE", "Aimbot", "Indicator Style", {"Simple", "Detailed", "Minimal"}), 
    prediction_strength = ui.new_slider("RAGE", "Aimbot", "Prediction Strength", 0, 100, 50, true, "%"), 
    reaction_time = ui.new_slider("RAGE", "Aimbot", "Reaction Time", 0, 100, 20, true, "ms"), 
    prefire = ui.new_checkbox("RAGE", "Aimbot", "Auto Prefire"), 
    aggressive_options = ui.new_multiselect("RAGE", "Aimbot", "Aggressive Options", { "Quick Shot", "Early Prediction", "Fast Recovery" }), 
    anti_defensive = ui.new_checkbox("RAGE", "Aimbot", "Anti Defensive"), 
    anti_defensive_options = ui.new_multiselect("RAGE", "Aimbot", "Anti Defensive Options", { 
        "Instant Double Tap", "Aggressive Prediction", "Early Shot", "Break LC", "Force Backtrack", "Smart Prediction" 
    }),
    unsafe_charge = ui.new_checkbox("RAGE", "Aimbot", "Allow Unsafe Charge"), 
    defensive_strength = ui.new_slider("RAGE", "Aimbot", "Defensive Strength", 1, 100, 50, true, "%"), 
    defensive_indicator = ui.new_checkbox("RAGE", "Aimbot", "Show Defensive Indicator"), 
    configs = ui.new_combobox("RAGE", "Aimbot", "Weapon Configs", { "Default", "AWP", "Scout", "AK47/M4", "Deagle/R8", "Pistols", "Auto", "SMG" }), 
    lc_break_mode = ui.new_combobox("RAGE", "Aimbot", "Break LC Mode", { "Defensive Only", "Always Aggressive", "Smart Aggressive", "Movement Based" }), 
    auto_load = ui.new_checkbox("RAGE", "Aimbot", "Auto-Load Weapon Configs") 
}

-- ============================================================================
-- WEAPON CONFIG PROFILE SYSTEM
-- ============================================================================
local configs = {
    ["Default"] = { mode = "Dynamic", prediction = 75, adaptive = {"Auto Speed Adjust", "Ping Compensation", "Movement Predict"}, min_speed = 90, crouch = 65, anti_defensive = true, defensive_strength = 65, defensive_options = {"Smart Prediction", "Aggressive Prediction"} }, 
    ["AWP"] = { mode = "Aggressive", prediction = 85, reaction = 8, prefire = true, aggressive = {"Quick Shot", "Early Prediction"}, crouch = 80, anti_defensive = true, defensive_strength = 80, defensive_options = {"Smart Prediction", "Early Shot"} }, 
    ["Scout"] = { mode = "Aggressive", prediction = 80, reaction = 12, prefire = true, aggressive = {"Quick Shot", "Early Prediction"}, crouch = 75, anti_defensive = true, defensive_strength = 75, defensive_options = {"Smart Prediction", "Early Shot"} }, 
    ["AK47/M4"] = { mode = "Dynamic", prediction = 70, adaptive = {"Auto Speed Adjust", "Ping Compensation", "Smart Interp", "Movement Predict"}, min_speed = 85, max_ping = 100, crouch = 65, anti_defensive = true, defensive_strength = 60, defensive_options = {"Smart Prediction", "Aggressive Prediction"} }, 
    ["Deagle/R8"] = { mode = "Dynamic", prediction = 75, reaction = 10, aggressive = {"Quick Shot"}, crouch = 70, anti_defensive = true, defensive_strength = 70, defensive_options = {"Smart Prediction"} }, 
    ["Pistols"] = { mode = "Dynamic", prediction = 65, adaptive = {"Auto Speed Adjust", "Movement Predict"}, min_speed = 90, crouch = 60, anti_defensive = true, defensive_strength = 55, defensive_options = {"Smart Prediction"} }, 
    ["Auto"] = { mode = "Adaptive", prediction = 75, adaptive = {"Auto Speed Adjust", "Ping Compensation", "Movement Predict"}, min_speed = 100, crouch = 70, anti_defensive = true, defensive_strength = 75, defensive_options = {"Smart Prediction", "Aggressive Prediction"} }, 
    ["SMG"] = { mode = "Dynamic", prediction = 65, adaptive = {"Auto Speed Adjust", "Movement Predict"}, min_speed = 110, crouch = 60, anti_defensive = true, defensive_strength = 50, defensive_options = {"Smart Prediction"} } 
}

local function load_config_values(cfg)
    if not cfg then return end 
    ui.set(ui_elements.mode, cfg.mode) 
    ui.set(ui_elements.prediction_strength, cfg.prediction) 
    ui.set(ui_elements.crouch_predict, cfg.crouch) 
    if cfg.reaction then ui.set(ui_elements.reaction_time, cfg.reaction) end 
    if cfg.prefire ~= nil then ui.set(ui_elements.prefire, cfg.prefire) end 
    if cfg.aggressive then ui.set(ui_elements.aggressive_options, cfg.aggressive) end 
    if cfg.adaptive then ui.set(ui_elements.adaptive_options, cfg.adaptive) end 
    if cfg.min_speed then ui.set(ui_elements.min_speed, cfg.min_speed) end 
    if cfg.max_ping then ui.set(ui_elements.max_ping, cfg.max_ping) end 
    if cfg.anti_defensive ~= nil then ui.set(ui_elements.anti_defensive, cfg.anti_defensive) end 
    if cfg.defensive_strength then ui.set(ui_elements.defensive_strength, cfg.defensive_strength) end 
    if cfg.defensive_options then ui.set(ui_elements.anti_defensive_options, cfg.defensive_options) end 
end

local function apply_weapon_config()
    if not ui.get(ui_elements.auto_load) then return end 
    local local_player = entity.get_local_player() 
    if not local_player then return end 
    local weapon = entity.get_player_weapon(local_player) 
    if not weapon then return end 
    local weapon_id = safe_get_prop(weapon, "m_iItemDefinitionIndex") 
    if not weapon_id then return end 
    
    local current_time = globals.realtime() 
    if config_cache and (current_time - last_config_check) < 0.5 then return end 
    last_config_check = current_time 
    
    local current_config = "Default" 
    if weapon_id == 40 then current_config = "Scout" 
    elseif weapon_id == 9 then current_config = "AWP" 
    elseif weapon_id == 11 or weapon_id == 38 then current_config = "Auto"
    elseif weapon_id == 1 or weapon_id == 64 then current_config = "Deagle/R8" 
    elseif weapon_id == 7 or weapon_id == 16 or weapon_id == 60 then current_config = "AK47/M4" 
    elseif contains({2, 3, 4, 30, 32, 36, 61, 63}, weapon_id) then current_config = "Pistols" 
    elseif contains({17, 19, 23, 24, 26, 33, 34}, weapon_id) then current_config = "SMG" end 
    
    if config_cache ~= current_config then
        config_cache = current_config 
        load_config_values(configs[current_config]) 
    end
end

ui_elements.load_config = ui.new_button("RAGE", "Aimbot", "Load Config", function() 
    local selected = ui.get(ui_elements.configs) 
    load_config_values(configs[selected]) 
end)

-- ============================================================================
-- HIGH FIDELITY TELEMETRY ENGINES
-- ============================================================================

local prediction_records = {}

local function clamp_number(v, mn, mx)
    if v == nil then return mn end
    if v < mn then return mn end
    if v > mx then return mx end
    return v
end

local function calculate_choke_amount(target)
    if not target then return 0 end

    local sim_time = safe_get_prop(target, "m_flSimulationTime")
    local old_sim = safe_get_prop(target, "m_flOldSimulationTime")
    if not sim_time or not old_sim then return 0 end

    local delta = sim_time - old_sim
    local tickinterval = globals.tickinterval()
    if not tickinterval or tickinterval <= 0 then return 0 end

    return math.max(0, math.min(math.floor(delta / tickinterval) - 1, 15))
end

local function get_target_record(target)
    local x, y, z = entity.get_prop(target, "m_vecOrigin")
    local vx, vy, vz = entity.get_prop(target, "m_vecVelocity")
    local sim = entity.get_prop(target, "m_flSimulationTime")

    if not x or not vx or not sim then
        return nil
    end

    local old = prediction_records[target]

    -- Only update when enemy simulation time actually changes.
    if old and old.sim == sim then
        return old, old
    end

    local new = {
        x = x, y = y, z = z or 0,
        vx = vx, vy = vy, vz = vz or 0,
        sim = sim,
        tick = globals.tickcount()
    }

    prediction_records[target] = new
    return new, old
end

local function get_prediction_time(target, speed, is_crouching)
    local mode = ui.get(ui_elements.mode)
    local strength = (ui.get(ui_elements.prediction_strength) or 50) / 100
    local max_ping = (ui.get(ui_elements.max_ping) or 80) / 1000
    local reaction = (ui.get(ui_elements.reaction_time) or 20) / 1000
    local tickinterval = globals.tickinterval()

    if not tickinterval or tickinterval <= 0 then
        tickinterval = 1 / 64
    end

    local options = ui.get(ui_elements.adaptive_options) or {}
    local choke = calculate_choke_amount(target)
    local ping_time = math.min(client.latency() or 0, max_ping)

    local base = tickinterval * math.max(choke, 1)

    if contains(options, "Ping Compensation") then
        base = base + ping_time * 0.35
    end

    if contains(options, "Movement Predict") then
        base = base + math.min((speed or 0) / 1000, 0.08)
    end

    if mode == "Minimum" then
        base = base * 0.45
    elseif mode == "Medium" then
        base = base * 0.75
    elseif mode == "High" then
        base = base * 1.0
    elseif mode == "Adaptive" then
        base = base * 1.15
    elseif mode == "Dynamic" then
        base = base * 1.25
    elseif mode == "Aggressive" then
        base = base * 1.35 + reaction
    end

    if is_crouching then
        local crouch_scale = (ui.get(ui_elements.crouch_predict) or 50) / 100
        base = base * (0.65 + crouch_scale * 0.35)
    end

    return clamp_number(base * strength, tickinterval, 0.25)
end

local function calculate_true_kinematics(target, time_to_predict)
    local cur, old = get_target_record(target)
    if not cur then return nil end

    local ax, ay, az = 0, 0, 0

    if old and old.sim and cur.sim and cur.sim > old.sim then
        local dt = cur.sim - old.sim

        if dt > 0 and dt < 1.0 then
            ax = (cur.vx - old.vx) / dt
            ay = (cur.vy - old.vy) / dt
            az = (cur.vz - old.vz) / dt

            -- Prevent crazy acceleration spikes from bad records.
            ax = clamp_number(ax, -3500, 3500)
            ay = clamp_number(ay, -3500, 3500)
            az = clamp_number(az, -3500, 3500)
        end
    end

    local t = clamp_number(time_to_predict, globals.tickinterval() or (1 / 64), 0.25)
    local t2 = t * t

    return {
        x = cur.x + cur.vx * t + 0.5 * ax * t2,
        y = cur.y + cur.vy * t + 0.5 * ay * t2,
        z = cur.z + cur.vz * t + 0.5 * az * t2
    }
end

-- ============================================================================
-- EXPLOIT-AWARE PACKET INTERACTION SUBROUTINES
-- ============================================================================
local function handle_anti_defensive(cmd)
    if not ui.get(ui_elements.anti_defensive) then 
        exploits:should_force_defensive(false) 
        return 
    end
    
    local local_player = entity.get_local_player() 
    if not local_player or not entity.is_alive(local_player) then 
        exploits:should_force_defensive(false) 
        return 
    end
    
    local target = client.current_threat() 
    if not target or not exploits:is_active() or exploits:in_defensive() or exploits:in_recharge() then 
        return 
    end
    
    local options = ui.get(ui_elements.anti_defensive_options) 
    local sim_time = safe_get_prop(target, "m_flSimulationTime") 
    local old_sim = safe_get_prop(target, "m_flOldSimulationTime") 
    if not sim_time or not old_sim then 
        exploits:should_force_defensive(false) 
        return 
    end
    
    local vx, vy = safe_get_prop(target, "m_vecVelocity[0]") or 0, safe_get_prop(target, "m_vecVelocity[1]") or 0 
    local speed = math.sqrt(vx * vx + vy * vy) 
    local delta = sim_time - old_sim 
    local should_force = false
    
    -- Target is actively manipulating Tickbase / Breaking Lagcomp
    if delta > 0.2 or speed < 1.01 then 
        if contains(options, "Instant Double Tap") and exploits:is_doubletap() then 
            should_force = true
            cmd.quick_stop = true 
        end
        
        if contains(options, "Early Shot") then 
            should_force = true
            cmd.quick_stop = true 
        end
        
        if contains(options, "Break LC") then 
            local mode = ui.get(ui_elements.lc_break_mode) 
            if mode == "Defensive Only" then 
                local choke = calculate_choke_amount(target) 
                if choke >= 12 or delta > (0.22 + (client.latency() * 0.5)) then 
                    should_force = true
                end
            elseif mode == "Always Aggressive" then 
                should_force = true
            elseif mode == "Movement Based" then 
                local lvx, lvy = safe_get_prop(local_player, "m_vecVelocity[0]") or 0, safe_get_prop(local_player, "m_vecVelocity[1]") or 0 
                if math.sqrt(lvx*lvx + lvy*lvy) > 5 then should_force = true end 
            end
        end

        if contains(options, "Force Backtrack") then 
            should_force = true
        end

        if contains(options, "Smart Prediction") then 
            if speed < 1.01 then should_force = true end 
        end
    end
    
    exploits:should_force_defensive(should_force) 
end

-- ============================================================================
-- CORE PREDICTION ENGINE HOOK
-- ============================================================================
local function enhanced_prediction(cmd)
    if not ui.get(ui_elements.enable) then return nil end 

    local selected_mode = ui.get(ui_elements.mode) 
    local target = client.current_threat() 
    if not target or not entity.is_alive(target) then return nil end 

    local vx = safe_get_prop(target, "m_vecVelocity[0]") or 0
    local vy = safe_get_prop(target, "m_vecVelocity[1]") or 0
    local speed = math.sqrt(vx * vx + vy * vy)

    local flags = safe_get_prop(target, "m_fFlags") or 0
    local duck_amount = safe_get_prop(target, "m_flDuckAmount") or 0

    local is_on_ground = bit.band(flags, 1) == 1
    local is_crouching = duck_amount > 0.65

    local ping = client.latency() * 1000

    local time_pred = get_prediction_time(target, speed, is_crouching)
    local predicted_pos = calculate_true_kinematics(target, time_pred)

    local prediction_data = {
        mode = selected_mode,
        target_speed = speed,
        ping = ping,
        is_crouching = is_crouching,
        is_on_ground = is_on_ground,
        interp = 1 / (cvar.sv_maxcmdrate:get_int() or 64),
        time_pred = time_pred,
        predicted_pos = predicted_pos
    }
    
    if selected_mode == "Aggressive" and cmd then 
        local aggressive_options = ui.get(ui_elements.aggressive_options) 
        if contains(aggressive_options, "Early Prediction") then 
            local time_pred = ui.get(ui_elements.reaction_time) / 1000 
            prediction_data.predicted_pos = calculate_true_kinematics(target, time_pred)
        end
    end
    
    return prediction_data 
end

-- ============================================================================
-- CANVAS GRAPHICS RENDERING SYSTEM
-- ============================================================================
local function draw_indicator(prediction_data)
    if not ui.get(ui_elements.indicator) or not prediction_data then return end 
    local screen_width, screen_height = client.screen_size() 
    local x, y = screen_width / 2, screen_height - 100 
    local style = ui.get(ui_elements.indicator_style) 
    
    local r, g, b = 255, 255, 255 
    if prediction_data.mode == "Adaptive" then r, g, b = 0, 255, 0 
    elseif prediction_data.mode == "Dynamic" then r, g, b = 0, 191, 255 
    elseif prediction_data.mode == "Aggressive" then r, g, b = 255, 0, 0 end 
    
    if style == "Detailed" then 
        renderer.text(x, y - 30, r, g, b, 255, "c", 0, "Enhanced Prediction") 
        renderer.text(x, y - 15, r, g, b, 255, "c", 0, string.format("Mode: %s", prediction_data.mode)) 
        renderer.text(x, y, r, g, b, 255, "c", 0, string.format("Sim Interval: %.6f", prediction_data.interp)) 
        renderer.text(x, y + 15, r, g, b, 255, "c", 0, string.format("Speed: %.1f | Ping: %dms", prediction_data.target_speed, prediction_data.ping)) 
        if prediction_data.is_crouching then renderer.text(x, y + 30, 255, 165, 0, 255, "c", 0, "DUCK") end 
    elseif style == "Simple" then 
        local status = prediction_data.is_crouching and " [DUCK]" or "" 
        renderer.text(x, y, r, g, b, 255, "c", 0, string.format("PRED: %s%s", prediction_data.mode, status)) 
    else
        renderer.text(x, y, r, g, b, 255, "c", 0, string.format("PRED: %s", prediction_data.mode)) 
    end
end

local function draw_defensive_indicator()
    if not ui.get(ui_elements.defensive_indicator) then return end 
    local screen_width, screen_height = client.screen_size() 
    local y_offset = 80 
    
    if exploits:is_active() then 
        local status_text, r, g, b = "", 255, 255, 255 
        if exploits:in_defensive() then status_text, r, g, b = "DEFENSIVE ACTIVE", 0, 255, 0 
        elseif exploits:in_recharge() then status_text, r, g, b = "RECHARGING", 255, 165, 0 
        elseif exploits:is_doubletap() then status_text, r, g, b = "DT READY", 0, 255, 255 
        elseif exploits:is_hideshots() then status_text, r, g, b = "HIDESHOTS READY", 0, 255, 255 end 
        
        if status_text ~= "" then
            renderer.text(screen_width / 2, screen_height - y_offset, r, g, b, 255, "c", 0, status_text) 
            y_offset = y_offset + 15 
        end
    end
end

-- ============================================================================
-- INTERFACE ENGINE CALL LOOPS
-- ============================================================================
client.set_event_callback("setup_command", function(cmd)
    -- Fixed syntax error: Converted inline expression to a proper statement block
    if ui.get(ui_elements.unsafe_charge) then
        exploits:allow_unsafe_charge(true)
    else
        exploits:allow_unsafe_charge(false)
    end
    
    handle_anti_defensive(cmd) --
    
    local prediction_data = enhanced_prediction(cmd) 
    if prediction_data then
        client.fire_event("prediction_update", prediction_data) 
    end
end)

client.set_event_callback("paint", function()
    if not ui.get(ui_elements.enable) then return end 
    local prediction_data = enhanced_prediction() 
    if prediction_data then
        draw_indicator(prediction_data) 
        draw_defensive_indicator() 
    end
end)

client.set_event_callback("weapon_fire", apply_weapon_config) 
client.set_event_callback("item_equip", apply_weapon_config) 

-- ============================================================================
-- WINDOW HOOK ENVIRONMENT VISIBILITY
-- ============================================================================
local function handle_menu_visibility()
    local enabled = ui.get(ui_elements.enable) 
    local mode = ui.get(ui_elements.mode) 
    local lc_mode = ui.get(ui_elements.lc_break_mode) -- Added to prevent runtime nil checks
    
    ui.set_visible(ui_elements.mode, enabled) 
    ui.set_visible(ui_elements.indicator, enabled) 
    ui.set_visible(ui_elements.adaptive_options, enabled and (mode == "Adaptive" or mode == "Dynamic")) 
    ui.set_visible(ui_elements.min_speed, enabled and (mode == "Adaptive" or mode == "Dynamic")) 
    ui.set_visible(ui_elements.max_ping, enabled and (mode == "Adaptive" or mode == "Dynamic")) 
    ui.set_visible(ui_elements.crouch_predict, enabled) 
    ui.set_visible(ui_elements.prediction_strength, enabled) 
    ui.set_visible(ui_elements.indicator_style, enabled and ui.get(ui_elements.indicator)) 
    ui.set_visible(ui_elements.reaction_time, enabled and mode == "Aggressive") 
    ui.set_visible(ui_elements.prefire, enabled and mode == "Aggressive") 
    ui.set_visible(ui_elements.aggressive_options, enabled and mode == "Aggressive") 
    ui.set_visible(ui_elements.configs, enabled) 
    ui.set_visible(ui_elements.load_config, enabled) 
    ui.set_visible(ui_elements.auto_load, enabled) 
    ui.set_visible(ui_elements.anti_defensive, enabled) 
    ui.set_visible(ui_elements.anti_defensive_options, enabled and ui.get(ui_elements.anti_defensive)) 
    ui.set_visible(ui_elements.unsafe_charge, enabled and ui.get(ui_elements.anti_defensive)) 
    ui.set_visible(ui_elements.defensive_strength, enabled and ui.get(ui_elements.anti_defensive)) 
    ui.set_visible(ui_elements.defensive_indicator, enabled and ui.get(ui_elements.anti_defensive)) 
    ui.set_visible(ui_elements.lc_break_mode, enabled and ui.get(ui_elements.anti_defensive) and contains(ui.get(ui_elements.anti_defensive_options), "Break LC")) 
end

ui.set_callback(ui_elements.enable, handle_menu_visibility) 
ui.set_callback(ui_elements.mode, handle_menu_visibility) 
ui.set_callback(ui_elements.indicator, handle_menu_visibility) 
ui.set_callback(ui_elements.anti_defensive, handle_menu_visibility) 
ui.set_callback(ui_elements.anti_defensive_options, handle_menu_visibility) 
ui.set_callback(ui_elements.unsafe_charge, handle_menu_visibility) 
ui.set_callback(ui_elements.lc_break_mode, handle_menu_visibility) 
handle_menu_visibility()

return {
    stop = function()
        ui.set(ui_elements.enable, false)
        exploits:should_force_defensive(false)
        exploits:allow_unsafe_charge(false)

        velocity_history = {}
        prediction_records = {}
        config_cache = nil

        for _, ref in pairs(ui_elements) do
            pcall(ui.set_visible, ref, false)
        end
    end
}
