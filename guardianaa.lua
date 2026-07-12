--- const
local OBEX = obex_fetch and obex_fetch() or {
    discord = "unknown",
    username = "Tama",
    build = "Debug"
}

if not LPH_OBFUSCATED then
    LPH_NO_VIRTUALIZE = function(...) return ... end
end

return LPH_NO_VIRTUALIZE(function ()
    local USERNAME = OBEX.username
    local BUILD = OBEX.build == 'User' and 'beta' or 'stable'
    
    --- declarations
    local merge = table.concat
    local f = string.format
    
    --- modules
    local ffi = require "ffi"
    local vector = require "vector"
    local http = require "gamesense/http"
    local inspect = require 'gamesense/inspect'
    local base64 = require "gamesense/base64"
    local websockets = require 'gamesense/websockets'
    local c_entity = require "gamesense/entity"
    local csgo_weapons = require "gamesense/csgo_weapons"
    
    local clipboard do
        clipboard = { }
    
        local GetClipboardTextCount = vtable_bind('vgui2.dll', 'VGUI_System010', 7, 'int(__thiscall*)(void*)')
        local SetClipboardText = vtable_bind('vgui2.dll', 'VGUI_System010', 9, 'void(__thiscall*)(void*, const char*, int)')
        local GetClipboardText = vtable_bind('vgui2.dll', 'VGUI_System010', 11, 'int(__thiscall*)(void*, int, const char*, int)')
    
        local function set(...)
            local text = tostring(table.concat({ ... }))
    
            SetClipboardText(text, string.len(text))
        end
    
        local function get()
            local len = GetClipboardTextCount()
    
            if len > 0 then
                local char_arr = ffi.typeof('char[?]')(len)
                GetClipboardText(0, char_arr, len)
                local text = ffi.string(char_arr, len - 1)
    
                local text_end do
                    text_end = text:find('_acid')
    
                    if text_end then
                        text = text:sub(1, text_end)
                    end
                end
    
                return text
            end
        end
    
        clipboard.set = set
        clipboard.get = get
    end
    
    local oprint = print
    local function print(...)
        local res = ""
    
        for _, str in ipairs({...}) do
            res = res .. tostring(str) .. "\t"
        end
    
        oprint(res)
    end
    
    local function print_raw(r, g, b, ...)
        client.color_log(r, g, b, 'Guardian\0')
        client.color_log(150, 150, 150, ' · \0')
        client.color_log(255, 255, 255, f(...))
    end
    
    --- defines
    local function contains(list, value)
        for i = 1, #list do
            if list[i] == value then
                return true
            end
        end
    
        return false
    end
    
    --- enumerations
    local e_statement = {
        [0]  = "Main",
        [1]  = "Standing",
        [2]  = "Moving",
        [3]  = "Slow Walk",
        [4]  = "Crouched",
        [5]  = "Move Crouched",
        [6]  = "Air",
        [7]  = "Air Crouched",
        [8]  = "Fake Lag"
    }
    
    local e_hotkey_mode = {
        [0] = "Always on",
        [1] = "On hotkey",
        [2] = "Toggle",
        [3] = "Off hotkey"
    }
    
    local e_hitgroup = {
        [0]  = "generic",
        [1]  = "head",
        [2]  = "chest",
        [3]  = "stomach",
        [4]  = "left arm",
        [5]  = "right arm",
        [6]  = "left leg",
        [7]  = "right leg",
        [8]  = "neck",
        [10] = "gear"
    }
    
    --- regions
    local utils = { }
    local software = { }
    local override = { }
    
    local iengineclient = { }
    local inetchannel = { }
    
    local ceasar = { }
    
    local menu = { }
    local gui = { }
    
    local motion = { }
    local windows = { }
    
    local graphics = { }
    local decorations = { }
    
    local exploit = { }
    local localplayer = { }
    local statement = { }
    
    local antiaim = { }
    local widgets = { }
    local settings = { }
    
    local angles = { }
    local defensive = { }
    local fast_ladder = { }
    local anim_breakers = { }
    
    local disablers = { }
    local avoid_backstab = { }
    local air_exploit = { }
    local safe_head = { }
    local fs_disablers = { }
    local delay_data_all = { }
    
    local yaw_direction = { }
    local manual_direction = { }
    local hitchance = { }
    local log_aimbot_shots = { }
    
    local aa_tweaks = { }
    local eventlogs = { }
    local watermark = { }
    local keybinds = { }
    local indicators = { }
    local arrows = { }
    local velocity_warning = { }
    local con_filter_text = { }
    local ctx_bebra = { }
    local custom_scope = { }
    
    local clientside_nickname = { }
    local trashtalk = { }
    local tab_to_game = { }
    local buy_bot = { }
    local auto_peek = { }
    local hit_marker = { }
    local unmute = { }
    local shared = { }

    --- region utils
    do
        local escape = {
            ["="] = true,
            ["0"] = true,
            ["1"] = true,
            ["2"] = true,
            ["3"] = true,
            ["4"] = true,
            ["5"] = true,
            ["6"] = true,
            ["7"] = true,
            ["8"] = true,
            ["9"] = true
        }

        local colors = {
            ['black'] = { 0, 0, 0, 0 },
            ['nick'] = { 255, 62, 62, 255 },
            ['default'] = { 198, 203, 209, 255 },
            ['highlight'] = { 151, 177, 187, 255 },
            ['miss'] = { 154, 255, 154, 255 },
            ['idle'] = { 137, 137, 137, 255 }
        }

        utils.unmute = vtable_bind('client.dll', 'GameClientExports001', 3, 'void(__thiscall*)(void*, int)')

        function utils.keys(list)
            local keys = { }

            for k, v in pairs(list) do
                keys[v] = k
            end

            return keys
        end

        function utils.collect_keys(tbl, init)
            local keys = init or { }
            for item, value in next, tbl do
                keys[#keys+1] = item
            end

            return keys
        end

        function utils.clamp(x, min, max)
            return math.max(min, math.min(x, max))
        end

        function utils.round(x)
            if x < 0 then
                return math.ceil(x - 0.5)
            end

            return math.floor(x + 0.5)
        end

        function utils.lerp(a, b, t)
            return a + t * (b - a)
        end

        function utils.inverse_lerp(a, b, v)
            return (v - a) / (b - a)
        end

        function utils.to_hex(r, g, b, a)
            return f("%02x%02x%02x%02x", r, g, b, a)
        end

        function utils.format(str, r, g, b, a)
            if type(str) ~= 'string' then
                return str
            end

            str = string.gsub(str, '[\v\r]', {
                ['\v'] = '\a' .. utils.to_hex(r, g, b, a),
                ['\r'] = '\aFFFFFFFF'
            })

            str = string.gsub(str, "\a%[(.-)%]", function (col)
                local r, g, b, a = unpack(colors[col])
                return '\a' .. utils.to_hex(r, g, b, a)
            end)

            return str
        end

        function utils.map(v, in_a, in_b, out_a, out_b, clamped)
            if clamped then
                v = utils.clamp(v, in_a, in_b)
            end

            return utils.lerp(out_a, out_b, utils.inverse_lerp(in_a, in_b, v))
        end

        function utils.normalize(x, min, max)
            local delta = max - min

            while x < min do
                x = x + delta
            end

            while x > max do
                x = x - delta
            end

            return x
        end

        function utils.normalize_yaw(x)
            return utils.normalize(x, -180, 180)
        end

        function utils.breathe(x)
            x = x % 2.0

            if x > 1.0 then
                x = 2.0 - x
            end

            return x
        end

        function utils.color_lerp(r1, g1, b1, a1, r2, g2, b2, a2, t)
            local r = utils.lerp(r1, r2, t)
            local g = utils.lerp(g1, g2, t)
            local b = utils.lerp(b1, b2, t)
            local a = utils.lerp(a1, a2, t)

            return r, g, b, a
        end

        function utils.win11_fix(input)
            local result = ""

            for i = 1, #input do
                local char = input:sub(i, i)
                local byte = string.byte(char)

                if escape[char] or (byte >= 65 and byte <= 122) then
                    result = result .. char
                end
            end

            return result
        end

        function utils.get_eye_position(ent)
            local x1, y1, z1 = entity.get_origin(ent)
            if x1 == nil then return end

            local x2, y2, z2 = entity.get_prop(ent, "m_vecViewOffset")
            if x2 == nil then return end

            return x1 + x2, y1 + y2, z1 + z2
        end
    end

    local memory do
        memory = { }

        function memory.pattern_scan(module, signature, add)
            local buff = ffi.new("char[1024]")

            local c = 0

            for char in string.gmatch(signature, "..%s?") do
                if char == "? " or char == "?? " then
                    buff[c] = 0xcc
                else
                    buff[c] = tonumber("0x" .. char)
                end

                c = c + 1
            end

            local result = ffi.cast("uintptr_t", client.find_signature(module, ffi.string(buff)))

            if add and tonumber(result) ~= 0 then
                result = ffi.cast("uintptr_t", tonumber(result) + add)
            end

            return result
        end

        function memory.rel_jmp(addr, pattern)
            if pattern then
                addr = memory.pattern_scan(addr, pattern)
            end

            addr = ffi.cast("uint8_t*", addr)

            local jmp_addr = ffi.cast("uintptr_t", addr)
            local jmp_disp = ffi.cast("int32_t*", jmp_addr + 0x1)[0]

            return ffi.cast("uintptr_t", jmp_addr + 0x5 + jmp_disp)
        end

        function memory.addr_to_num(in_addr)
            return tonumber(ffi.cast("int", in_addr))
        end

        local jmp_ecx = client.find_signature("engine.dll", "\xFF\xE1")
        local fnGetModuleHandle = ffi.cast("uint32_t(__fastcall*)(unsigned int, unsigned int, const char*)", jmp_ecx)
        local fnGetProcAddress = ffi.cast("uint32_t(__fastcall*)(unsigned int, unsigned int, uint32_t, const char*)", jmp_ecx)

        local pGetProcAddress = ffi.cast("uint32_t**", ffi.cast("uint32_t", client.find_signature("engine.dll", "\xFF\x15\xCC\xCC\xCC\xCC\xA3\xCC\xCC\xCC\xCC\xEB\x05")) + 2)[0][0]
        local pGetModuleHandle = ffi.cast("uint32_t**", ffi.cast("uint32_t", client.find_signature("engine.dll", "\xFF\x15\xCC\xCC\xCC\xCC\x85\xC0\x74\x0B")) + 2)[0][0]

        function memory.get_export(module, func, typedef)
            local ctype = ffi.typeof(typedef)

            local fn = fnGetProcAddress(pGetProcAddress, 0, fnGetModuleHandle(pGetModuleHandle, 0, module), func)

            return function (...)
                return ffi.cast(ctype, jmp_ecx)(fn, 0, ...)
            end
        end
    end

    do
        software.rage = {
            weapon = {
                weapon_type = ui.reference("Rage", "Weapon type", "Weapon type")
            },

            aimbot = {
                enabled = { ui.reference("Rage", "Aimbot", "Enabled") },
                target_selection = ui.reference("Rage", "Aimbot", "Target selection"),
                minimum_damage = ui.reference("Rage", "Aimbot", "Minimum damage"),
                hitchance = ui.reference('Rage', 'Aimbot', 'Minimum hit chance'),
                auto_scope = ui.reference('Rage', 'Aimbot', 'Automatic Scope'),
                minimum_damage_override = { ui.reference("Rage", "Aimbot", "Minimum damage override") },
                prefer_safe_point = ui.reference("Rage", "Aimbot", "Prefer safe point"),
                force_safe_point = ui.reference("Rage", "Aimbot", "Force safe point"),
                force_body_aim = ui.reference("Rage", "Aimbot", "Force body aim"),
                double_tap = { ui.reference("Rage", "Aimbot", "Double tap") }
            },

            other = {
                quick_peek_assist = { ui.reference("Rage", "Other", "Quick peek assist") },
                duck_peek_assist = ui.reference("Rage", "Other", "Duck peek assist")
            }
        }

        software.aa = {
            angles = {
                enabled = ui.reference("AA", "Anti-aimbot angles", "Enabled"),
                pitch = { ui.reference("AA", "Anti-aimbot angles", "Pitch") },
                yaw_base = ui.reference("AA", "Anti-aimbot angles", "Yaw base"),
                yaw = { ui.reference("AA", "Anti-aimbot angles", "Yaw") },
                yaw_jitter = { ui.reference("AA", "Anti-aimbot angles", "Yaw jitter") },
                body_yaw = { ui.reference("AA", "Anti-aimbot angles", "Body yaw") },
                freestanding_body_yaw = ui.reference("AA", "Anti-aimbot angles", "Freestanding body yaw"),
                edge_yaw = ui.reference("AA", "Anti-aimbot angles", "Edge yaw"),
                freestanding = { ui.reference("AA", "Anti-aimbot angles", "Freestanding") },
                roll = ui.reference("AA", "Anti-aimbot angles", "Roll")
            },

            fakelag = {
                enabled = { ui.reference("AA", "Fake lag", "Enabled") },
                amount = ui.reference("AA", "Fake lag", "Amount"),
                variance = ui.reference("AA", "Fake lag", "Variance"),
                limit = ui.reference("AA", "Fake lag", "Limit")
            },

            other = {
                slow_motion = { ui.reference("AA", "Other", "Slow motion") },
                leg_movement = ui.reference("AA", "Other", "Leg movement"),
                on_shot_antiaim = { ui.reference("AA", "Other", "On shot anti-aim") },
                fake_peek = { ui.reference("AA", "Other", "Fake peek") }
            }
        }

        software.visuals = {
            scope_overlay = ui.reference('VISUALS', 'Effects', 'Remove scope overlay')
        }

        software.misc = {
            miscellaneous = {
                clan_tag_spammer = { ui.reference("Misc", "Miscellaneous", "Clan tag spammer") },
                ping_spike = { ui.reference("Misc", "Miscellaneous", "Ping spike") }
            },

            settings = {
                menu_color = ui.reference("Misc", "Settings", "Menu color"),
                output = ui.reference("Misc", "Miscellaneous", "Draw console output"),
                dpi_scale = ui.reference("Misc", "Settings", "DPI scale"),
                sv_maxusrcmdprocessticks = ui.reference("Misc", "Settings", "sv_maxusrcmdprocessticks2")
            }
        }

        function software.is_double_tap()
            return ui.get(software.rage.aimbot.double_tap[1])
                and ui.get(software.rage.aimbot.double_tap[2])
        end

        function software.is_minimum_damage_override()
            return ui.get(software.rage.aimbot.minimum_damage_override[1])
                and ui.get(software.rage.aimbot.minimum_damage_override[2])
        end

        function software.is_force_body_aim()
            return ui.get(software.rage.aimbot.force_body_aim)
        end

        function software.is_force_safe_point()
            return ui.get(software.rage.aimbot.force_safe_point)
        end

        function software.is_quick_peek_assist()
            return ui.get(software.rage.other.quick_peek_assist[1])
                and ui.get(software.rage.other.quick_peek_assist[2])
        end

        function software.is_freestanding()
            return ui.get(software.aa.angles.freestanding[1])
                and ui.get(software.aa.angles.freestanding[2])
        end

        function software.is_duck_peek_assist()
            return ui.get(software.rage.other.duck_peek_assist)
        end

        function software.is_on_shot_antiaim()
            return ui.get(software.aa.other.on_shot_antiaim[1])
                and ui.get(software.aa.other.on_shot_antiaim[2])
        end

        function software.is_slow_motion()
            return ui.get(software.aa.other.slow_motion[1])
                and ui.get(software.aa.other.slow_motion[2])
        end

        function software.is_edge()
            return ui.get(software.aa.angles.edge_yaw)
        end

        function software.get_color()
            return ui.get(software.misc.settings.menu_color)
        end

        function software.get_dpi_scale()
            local value = ui.get(software.misc.settings.dpi_scale)
            local unit = string.match(value, "(%d+)%%")

            return unit * 0.01
        end

        function software.get_minimum_damage()
            if software.is_minimum_damage_override() then
                return ui.get(software.rage.aimbot.minimum_damage_override[3]), true
            end

            return ui.get(software.rage.aimbot.minimum_damage), false
        end
    end

    --- region override
    do
        local data = { }

        local function get_value(ref)
            local value = { ui.get(ref) }
            local typeof = ui.type(ref)

            if typeof == "hotkey" then
                return { e_hotkey_mode[value[2]] }
            end

            return value
        end

        function override.get(ref, ...)
            local value = data[ref]

            if value == nil then
                return
            end

            return unpack(value)
        end

        function override.set(ref, ...)
            if data[ref] == nil then
                data[ref] = get_value(ref)
            end

            ui.set(ref, ...)
        end

        function override.unset(ref)
            if data[ref] == nil then
                return
            end

            ui.set(ref, unpack(data[ref]))
            data[ref] = nil
        end

        function override.clear()
            local refs = {}
            for ref in pairs(data) do
                refs[#refs + 1] = ref
            end

            for i = 1, #refs do
                override.unset(refs[i])
            end
        end
    end

    --- region iengineclient
    do
        local native_GetNetChannelInfo = vtable_bind("engine.dll", "VEngineClient014", 78, "void*(__thiscall*)(void*)")

        function iengineclient.get_net_channel_info()
            return native_GetNetChannelInfo()
        end
    end

    --- region inetchannel
    do
        local native_IsLoopback = vtable_thunk(6, "bool(__thiscall*)(void*)")
        local native_IsTimingOut = vtable_thunk(7, "bool(__thiscall*)(void*)")

        local native_GetLatency = vtable_thunk(9, "float(__thiscall*)(void*, int flow)")
        local native_GetAvgLatency = vtable_thunk(10, "float(__thiscall*)(void*, int flow)")

        local native_GetRemoteFramerate = vtable_thunk(25, "void(__thiscall*)(void*, float *pflFrameTime, float *pflFrameTimeStdDeviation, float *pflFrameStartTimeStdDeviation)")

        local pflFrameTime = ffi.new "float[1]"
        local pflFrameTimeStdDeviation = ffi.new "float[1]"
        local pflFrameStartTimeStdDeviation = ffi.new "float[1]"

        local function get_remote_framerate(inetchannelinfo)
            if inetchannelinfo == nil then
                return 0, 0
            end

            local server_var = 0
            local server_framerate = 0

            native_GetRemoteFramerate(inetchannelinfo, pflFrameTime, pflFrameTimeStdDeviation, pflFrameStartTimeStdDeviation)

            if pflFrameTime[0] > 0 then
                server_framerate = pflFrameTime[0] * 1000
                server_var = pflFrameStartTimeStdDeviation[0] * 1000
            end

            return server_framerate, server_var
        end

        function inetchannel.is_loopback(inetchannelinfo)
            return native_IsLoopback(inetchannelinfo)
        end

        function inetchannel.is_timing_out(inetchannelinfo)
            return native_IsTimingOut(inetchannelinfo)
        end

        function inetchannel.get_latency(inetchannelinfo, flow)
            return native_GetLatency(inetchannelinfo, flow)
        end

        function inetchannel.get_avg_latency(inetchannelinfo, flow)
            return native_GetAvgLatency(inetchannelinfo, flow)
        end

        function inetchannel.get_remote_framerate(inetchannelinfo)
            return get_remote_framerate(inetchannelinfo)
        end
    end

    --- region ceaser
    do
        local function ascii_base(s)
            if string.lower(s) == s then
                return string.byte("a")
            end

            return string.byte("A")
        end

        function ceasar.cipher(s, key)
            local result = string.gsub(s, "%a", function(char)
                local base = ascii_base(s)
                local byte = string.byte(char)

                return string.char(base + (byte - base + key) % 26)
            end)

            return result
        end

        function ceasar.decipher(s, key)
            return ceasar.cipher(s, -key)
        end
    end

    --- region menu
    do
        local items = { }
        local records = { }

        local callbacks = { }

        local function get_value(ref)
            local value = { pcall(ui.get, ref) }
            if not value[1] then return end

            return unpack(value, 2)
        end

        local function get_keys(value)
            if type(value[1]) == "table" then
                return utils.keys(value[1])
            end

            return { }
        end

        local function update_items()
            for i = 1, #callbacks do
                callbacks[i]()
            end

            for i = 1, #items do
                local item = items[i]

                ui.set_visible(item.ref, item.is_visible)
                item.is_visible = false
            end
        end

        local c_item = { } do
            function c_item:new()
                return setmetatable({ }, self)
            end

            function c_item:init()
                local function callback(ref)
                    self:update_value(ref)
                    self:invoke_callback(ref)

                    update_items()
                end

                ui.set_callback(self.ref, callback)
            end

            function c_item:get()
                return unpack(self.value)
            end

            function c_item:set(...)
                local ref = self.ref

                ui.set(ref, ...)
                self:update_value(ref)
            end

            function c_item:have_key(key)
                return self.keys[key] ~= nil
            end

            function c_item:rawget()
                return ui.get(self.ref)
            end

            function c_item:reset()
                pcall(ui.set, self.ref, unpack(self.default))
            end

            function c_item:record(tab, name)
                if records[tab] == nil then
                    records[tab] = { }
                end

                self.is_recorded = true
                records[tab][name] = self

                return self
            end

            function c_item:save()
                if not self.is_recorded then
                    error("unable to save unrecorded item")
                    return
                end

                self.is_saved = true
                return self
            end

            function c_item:display()
                self.is_visible = true
            end

            function c_item:config_ignore()
                self.saveable = false
                return self
            end

            function c_item:set_callback(callback)
                self.callbacks[#self.callbacks + 1] = callback
            end

            function c_item:update_value(ref)
                local value = { get_value(ref) }
                self.keys = get_keys(value)

                self.value = value
            end

            function c_item:invoke_callback(...)
                for i = 1, #self.callbacks do
                    self.callbacks[i](...)
                end
            end

            function c_item:get_ref()
                return self.ref
            end

            c_item.__index = c_item
        end

        function menu.new_item(fn, ...)
            local ref = fn(...)

            local value = { get_value(ref) }
            local typeof = ui.type(ref)

            local item = c_item:new()

            item.ref = ref
            item.name = select(3, ...)

            item.value = value
            item.default = value

            item.keys = get_keys(value)
            item.callbacks = { }

            item.is_saved = false
            item.is_visible = false
            item.is_recorded = false

            item.saveable = true

            if typeof == "button" then
                item.callbacks[#item.callbacks + 1] = select(4, ...)
            end

            item:init()
            items[#items + 1] = item

            return item
        end

        function menu.get_items()
            return items
        end

        function menu.get_records()
            return records
        end

        function menu.set_callback(callback)
            callbacks[#callbacks + 1] = callback
        end

        function menu.update()
            update_items()
        end

        function menu.get_items()
            return items
        end
    end

    local qhouss_config_system do
        qhouss_config_system = { }
    
        local function resolve_item_export(item)
            if not item.saveable then
                return
            end
    
            if ui.type(item.ref) == "label" or ui.type(item.ref) == "hotkey" then
                return
            end
    
            return item.value
        end
    
        local function resolve_item_import(item, data)
            if ui.type(item.ref) == "label" or ui.type(item.ref) == "hotkey" then
                return true
            end
    
            if not item.saveable then
                return true
            end
    
            if data == nil then
                return false
            end
    
            item:set(unpack(data))
    
            return true
        end
    
        function qhouss_config_system.export_to_str()
            local config_result = { }
    
            for _, item in ipairs(menu.get_items()) do
                config_result[item.name] = resolve_item_export(item)
            end
    
            cvar.play:invoke_callback("buttons\\blip1")
    
            return base64.encode(json.stringify(config_result)) .. '_acid'
        end
    
        function qhouss_config_system.import_from_str(str)
            str = str:gsub('_acid', '')
            local status, config = pcall(base64.decode, str)
            if not status then
                print_raw(255, 100, 100, "Failed to decode config")
                return
            end
    
            status, config = pcall(json.parse, config)
            if not status then
                print_raw(255, 100, 100, "Failed to parse config")
                return
            end
    
            for _, item in ipairs(menu.get_items()) do
                local imported = resolve_item_import(item, config[item.name])
    
                if not imported then
                end
            end
    
            cvar.play:invoke_callback("buttons\\blip2")
        end
    end

    --- region gui
    do
        local function set_native_ui(visible)
            local pitch_val = ui.get(software.aa.angles.pitch[1])
            local yaw_val = ui.get(software.aa.angles.yaw[1])
            local yaw_jitter_val = ui.get(software.aa.angles.yaw_jitter[1])
            local body_yaw_val = ui.get(software.aa.angles.body_yaw[1])

            ui.set_visible(software.aa.angles.enabled, visible)
            ui.set_visible(software.aa.angles.pitch[1], visible)
            ui.set_visible(software.aa.angles.yaw_base, visible)
            ui.set_visible(software.aa.angles.yaw[1], visible)
            ui.set_visible(software.aa.angles.body_yaw[1], visible)
            ui.set_visible(software.aa.angles.edge_yaw, visible)
            ui.set_visible(software.aa.angles.freestanding[1], visible)
            ui.set_visible(software.aa.angles.freestanding[2], visible)
            ui.set_visible(software.aa.angles.roll, visible)

            if pitch_val == "Custom" then
                ui.set_visible(software.aa.angles.pitch[2], visible)
            end

            if yaw_val ~= "Off" then
                ui.set_visible(software.aa.angles.yaw[2], visible)
                ui.set_visible(software.aa.angles.yaw_jitter[1], visible)

                if yaw_jitter_val ~= "Off" then
                    ui.set_visible(software.aa.angles.yaw_jitter[2], visible)
                end
            end

            if body_yaw_val ~= "Off" then
                if body_yaw_val ~= "Opposite" then
                    ui.set_visible(software.aa.angles.body_yaw[2], visible)
                end

                ui.set_visible(software.aa.angles.freestanding_body_yaw, visible)
            end
        end

        do
            gui.enabled = menu.new_item(ui.new_checkbox, "AA", "Anti-aimbot angles", string.format('\a%sGuardian', utils.to_hex(182, 182, 101, 255)))
            : record("gui", "enabled")

            gui.enabled:set(true)
        end

        shared.online_label = menu.new_item(ui.new_label, 'AA', 'Anti-aimbot angles', 'Guardian Debug')

        gui.selection = menu.new_item(ui.new_combobox, "AA", "Anti-aimbot angles", merge { "\n", "gui.selection" }, { "Home", "Settings", "Anti-aim" })
        : record("gui", "selection")

        function gui.shutdown()
            set_native_ui(true)
        end

        function gui.frame()
            set_native_ui(not gui.enabled:get())
        end
    end

    --- region motion
    do
        local function linear(t, b, c, d)
            return c * t / d + b
        end

        local function get_deltatime()
            return globals.frametime()
        end

        local function solve(easing_fn, prev, new, clock, duration)
            if clock <= 0 then return new end
            if clock >= duration then return new end

            prev = easing_fn(clock, prev, new - prev, duration)

            if type(prev) == "number" then
                if math.abs(new - prev) < 0.001 then
                    return new
                end

                local remainder = math.fmod(prev, 1.0)

                if remainder < 0.001 then
                    return math.floor(prev)
                end

                if remainder > 0.999 then
                    return math.ceil(prev)
                end
            end

            return prev
        end

        function motion.interp(a, b, t, easing_fn)
            easing_fn = easing_fn or linear

            if type(b) == "boolean" then
                b = b and 1 or 0
            end

            return solve(easing_fn, a, b, get_deltatime(), t)
        end
    end

    --- region windows
    do
        local data = { }
        local queue = { }
    
        local mouse_pos = vector()
        local mouse_pos_prev = vector()
    
        local mouse_down = false
        local mouse_clicked = false
    
        local mouse_down_duration = 0
        local dragging_smth = false
    
        local mouse_delta = vector()
        local mouse_clicked_pos = vector()
    
        local hovered_window
        local foreground_window
    
        local c_window = { } do
            function c_window:new(name)
                local window = { }
    
                window.name = name
    
                window.pos = vector()
                window.size = vector()
    
                window.anchor = vector(0.0, 0.0)
    
                window.updated = false
                window.dragging = false
    
                data[name] = window
                queue[#queue + 1] = window
    
                setmetatable(window, self)
                return window
            end
    
            function c_window:set_pos(pos)
                local screen = vector(client.screen_size())
                local new_pos = pos:clone()
    
                new_pos.x = utils.clamp(new_pos.x, 0, screen.x - self.size.x)
                new_pos.y = utils.clamp(new_pos.y, 0, screen.y - self.size.y)
    
                self.pos = new_pos
            end
    
            function c_window:set_size(size)
                local size_delta = size - self.size
    
                self.size = size
                self:set_pos(self.pos - size_delta * self.anchor)
            end
    
            function c_window:set_anchor(anchor)
                self.anchor = anchor
            end
    
            function c_window:is_hovering()
                return self.hovering
            end
    
            function c_window:is_dragging()
                return self.dragging
            end
    
            function c_window:update()
                self.updated = true
            end
    
            c_window.__index = c_window
        end
    
        local function is_collided(point, a, b)
            return point.x >= a.x and point.y >= a.y
                and point.x <= b.x and point.y <= b.y
        end
    
        local function update_mouse_inputs()
            local cursor = vector(ui.mouse_position())
            local is_down = client.key_state(0x01)
    
            local delta_time = globals.frametime()
    
            mouse_pos = cursor
            mouse_delta = mouse_pos - mouse_pos_prev
    
            mouse_pos_prev = mouse_pos
    
            mouse_down = is_down
            mouse_clicked = is_down and mouse_down_duration < 0
    
            mouse_down_duration = is_down and (mouse_down_duration < 0 and 0 or mouse_down_duration + delta_time) or -1
    
            if mouse_clicked then
                mouse_clicked_pos = mouse_pos
            end
        end
    
        local function appear_all_windows()
            for i = 1, #queue do
                local window = queue[i]
    
                local pos = window.pos
                local size = window.size
    
                local r, g, b, a = 0, 0, 0, 255
    
                renderer.rectangle(pos.x, pos.y, size.x, size.y, r, g, b, a)
            end
        end
    
        local function find_hovered_window()
            local found_window = nil
    
            if ui.is_menu_open() then
                for i = 1, #queue do
                    local window = queue[i]
    
                    local pos = window.pos
                    local size = window.size
    
                    if not window.updated then
                        goto continue
                    end
    
                    if not is_collided(mouse_pos, pos, pos + size) then
                        goto continue
                    end
    
                    found_window = window
                    ::continue::
                end
            end
    
            hovered_window = found_window
        end
    
        local function find_foreground_window()
            if mouse_down then
                if mouse_clicked and hovered_window ~= nil then
                    for i = 1, #queue do
                        local window = queue[i]
    
                        if window == hovered_window then
                            table.remove(queue, i)
                            table.insert(queue, window)
    
                            break
                        end
                    end
    
                    foreground_window = hovered_window
                    return
                end
    
                return
            end
    
            foreground_window = nil
        end
    
        local function update_all_windows()
            for i = 1, #queue do
                local window = queue[i]
    
                window.updated = false
    
                window.hovering = false
                window.dragging = false
            end
        end
    
        local function update_hovered_window()
            if hovered_window == nil then
                return
            end
    
            hovered_window.hovering = true
        end
    
        local function update_foreground_window()
            dragging_smth = false
            if foreground_window == nil then
                return
            end
    
            local new_position = foreground_window.pos + mouse_delta
    
            foreground_window:set_pos(new_position)
            foreground_window.dragging = true
            dragging_smth = true
        end
    
        function windows.new(name, x, y)
            local window = data[name]
                or c_window:new(name)
    
            local screen = vector(client.screen_size())
            window:set_pos(screen * vector(x, y))
    
            return window
        end
    
        function windows.frame()
            -- appear_all_windows()
            update_mouse_inputs()
    
            find_hovered_window()
            find_foreground_window()
    
            update_all_windows()
    
            update_hovered_window()
            update_foreground_window()
        end
    
        client.set_event_callback('setup_command', function (cmd)
            if dragging_smth or hovered_window then
                cmd.in_attack = false
                cmd.in_attack2 = false
            end
        end)
    end

    --- region graphics
    do
        local alpha_unit = 1 / 255

        local function string_alpha_mod(s, alpha)
            local result = s:gsub("\a(%x%x%x%x%x%x)(%x%x)", function(rgb, a)
                return f("\a%s%02x", rgb, tonumber(a, 16) * alpha)
            end)

            return result
        end

        graphics.config_export = menu.new_item(ui.new_button, "AA", "Anti-aimbot angles", "Export Configuration", function ()
            clipboard.set(qhouss_config_system.export_to_str())
        end):config_ignore()

        graphics.config_import = menu.new_item(ui.new_button, "AA", "Anti-aimbot angles", "Import Configuration", function ()
            qhouss_config_system.import_from_str(clipboard.get())
        end):config_ignore()

        graphics.config_default = menu.new_item(ui.new_button, "AA", "Anti-aimbot angles", "Default Configuration", function ()
            qhouss_config_system.import_from_str(
                'eyJCb2R5IHlhd1xuY3VzdG9tX2JvZHlfeWF3X1N0YW5kaW5nIjpbIk9mZiJdLCJVdGlsaXR5IHdlYXBvbiI6W1siS2V2bGFyIiwiSGVsbWV0IiwiRGVmdXNlciIsIlRhc2VyIiwiSEUiLCJNb2xvdG92IiwiU21va2UiXV0sIlxuY3VzdG9tX3lhd18xODBscl9tb2RlX0Zha2UgTGFnIjpbIlNpZGUgYmFzZWQiXSwiXG5KaXR0ZXIgb2Zmc2V0XG5jdXN0b21faml0dGVyX29mZnNldF9BaXIiOlswXSwiLSBPcHRpb25zIjpbWyJBdm9pZCBCYWNrc3RhYiIsIkZhc3QgTGFkZGVyIiwiRWRnZSBZYXcgb24gRkQiXV0sIllhdyBiYXNlXG5jdXN0b21feWF3X2Jhc2VfRmFrZSBMYWciOlsiTG9jYWwgdmlldyJdLCJcblBvc2l0aW9uIjpbNTBdLCItIFN0YXRlXG5kZWZlbnNpdmU6OnN0YXRlIjpbWyJBaXIiLCJTdGFuZGluZyIsIk1vdmluZyIsIlNsb3cgV2FsayIsIkNyb3VjaGVkIiwiT24gUGVlayJdXSwiXG5jdXN0b21feWF3X29mZnNldF9TdGFuZGluZyI6WzBdLCJEZWxheVxuY3VzdG9tX0RlbGF5X0Nyb3VjaGVkIjpbNV0sIlJpZ2h0IG9mZnNldFxuY3VzdG9tX3lhd19yaWdodF9TdGFuZGluZyI6WzBdLCJcbmN1c3RvbV95YXdfMTgwbHJfbW9kZV9NYWluIjpbIlNpZGUgYmFzZWQiXSwiQWlyIExhZyBFeHBsb2l0IjpbZmFsc2VdLCJSYW5kb21pemF0aW9uXG5jdXN0b21faml0dGVyX3JhbmRvbWl6YXRpb25fU3RhbmRpbmciOlswXSwiWWF3XG5jdXN0b21feWF3X01vdmluZyI6WyJPZmYiXSwiXG5jdXN0b21feWF3X29mZnNldF9TbG93IFdhbGsiOlswXSwiXG5ndWkuc2VsZWN0aW9uIjpbIkhvbWUiXSwiXG5jdXN0b21fYm9keV95YXdfb2Zmc2V0X0Zha2UgTGFnIjpbMF0sIlBpdGNoXG5jdXN0b21fcGl0Y2hfTW92aW5nIjpbIk9mZiJdLCJEZWxheVxuY3VzdG9tX0RlbGF5X01vdmluZyI6WzVdLCJSaWdodCBvZmZzZXRcbmN1c3RvbV95YXdfcmlnaHRfQ3JvdWNoZWQiOlswXSwiLSBJdGVtc1xud2lkZ2V0czo6aXRlbXMiOltbIldhdGVybWFyayIsIktleWJpbmRzIiwiVmVsb2NpdHkgV2FybmluZyIsIkNyb3NzaGFpciBJbmRpY2F0b3IiLCJEYW1hZ2UgSW5kaWNhdG9yIiwiSGl0IFJhdGUiXV0sIkxlZnQgb2Zmc2V0XG5jdXN0b21feWF3X2xlZnRfRmFrZSBMYWciOlswXSwiUmFuZG9taXphdGlvblxuY3VzdG9tX2ppdHRlcl9yYW5kb21pemF0aW9uX0FpciBDcm91Y2hlZCI6WzBdLCJZYXdcbmN1c3RvbV95YXdfU3RhbmRpbmciOlsiT2ZmIl0sIlxuY3VzdG9tX3lhd19vZmZzZXRfTW92aW5nIjpbMF0sIkRlbGF5IEN5Y2xlXG5jdXN0b21fZGVsYXlfY3ljbGVfTW92ZSBDcm91Y2hlZCI6WzUwXSwiXG5jdXN0b21feWF3X29mZnNldF9BaXIiOlswXSwiXG5KaXR0ZXIgb2Zmc2V0XG5jdXN0b21faml0dGVyX29mZnNldF9TbG93IFdhbGsiOlswXSwiWWF3IGJhc2VcbmN1c3RvbV95YXdfYmFzZV9Dcm91Y2hlZCI6WyJMb2NhbCB2aWV3Il0sIkFudGkgQWltIEJ1aWxkZXIiOlsiUmVjb21tZW5kZWQiXSwiWWF3IGppdHRlclxuY3VzdG9tX3lhd19qaXR0ZXJfU2xvdyBXYWxrIjpbIk9mZiJdLCJXaWRnZXRzIjpbdHJ1ZV0sIlxuY3VzdG9tX3BpdGNoX29mZnNldF9Nb3ZlIENyb3VjaGVkIjpbMF0sIk1hbnVhbCBDb2xvciI6WzExMywxNTIsMjU1LDI1NV0sIi0gUGl0Y2hcbmRlZmVuc2l2ZTo6cGl0Y2giOlsiUmFuZG9tIl0sIlxuY3VzdG9tX2ppdHRlcl9tb2RlX0FpciI6WyIyLVdheSJdLCJTYWZlIFlhd1xuY3VzdG9tX3NhZmVfeWF3X01vdmUgQ3JvdWNoZWQiOltmYWxzZV0sIkRlbGF5XG5jdXN0b21fRGVsYXlfQWlyIENyb3VjaGVkIjpbNV0sIlR3ZWFrcyI6W3RydWVdLCJCb2R5IHlhd1xuY3VzdG9tX2JvZHlfeWF3X1Nsb3cgV2FsayI6WyJPZmYiXSwiUGl0Y2hcbmN1c3RvbV9waXRjaF9TdGFuZGluZyI6WyJPZmYiXSwiRGVsYXkgQ3ljbGVcbmN1c3RvbV9kZWxheV9jeWNsZV9TdGFuZGluZyI6WzUwXSwiU2FmZSBIZWFkIjpbdHJ1ZV0sIkRlbGF5IFRpbWVcbmN1c3RvbV9hY2lkX2RlbGF5U3RhbmRpbmciOlsxNV0sIlNoYXJlZCBMb2dvIjpbdHJ1ZV0sIllhd1xuY3VzdG9tX3lhd19TbG93IFdhbGsiOlsiT2ZmIl0sIkZyZWVzdGFuZGluZyBib2R5IHlhd1xuY3VzdG9tX2ZyZWVzdGFuZGluZ19ib2R5X3lhd19TbG93IFdhbGsiOltmYWxzZV0sIllhdyBqaXR0ZXJcbmN1c3RvbV95YXdfaml0dGVyX0FpciI6WyJPZmYiXSwiUGl0Y2hcbmN1c3RvbV9waXRjaF9BaXIiOlsiT2ZmIl0sIllhdyBiYXNlXG5jdXN0b21feWF3X2Jhc2VfTWFpbiI6WyJMb2NhbCB2aWV3Il0sIlxuSml0dGVyIG9mZnNldFxuY3VzdG9tX2ppdHRlcl9vZmZzZXRfTW92ZSBDcm91Y2hlZCI6WzBdLCJMZWZ0IG9mZnNldFxuY3VzdG9tX3lhd19sZWZ0X1Nsb3cgV2FsayI6WzBdLCJTdGF0ZSI6WyJNYWluIl0sIlNhZmUgWWF3XG5jdXN0b21fc2FmZV95YXdfTWFpbiI6W2ZhbHNlXSwiU2Vjb25kYXJ5IHdlYXBvbiI6WyJSOCBcLyBEZWFnbGUiXSwiLSBEaXNhYmxlIE9uXG5mc19kaXNhYmxlcnM6OnN0YXRlcyI6W3t9XSwiUmFuZG9taXphdGlvblxuY3VzdG9tX2ppdHRlcl9yYW5kb21pemF0aW9uX01vdmUgQ3JvdWNoZWQiOlswXSwiRGVsYXkgQ3ljbGVcbmN1c3RvbV9kZWxheV9jeWNsZV9Dcm91Y2hlZCI6WzUwXSwiTWFudWFsIFlhdyI6W2ZhbHNlXSwiQm9keSB5YXdcbmN1c3RvbV9ib2R5X3lhd19BaXIiOlsiT2ZmIl0sIkNvbG9yIjpbMjU1LDI1NSwyNTUsMjU1XSwiXG5KaXR0ZXIgb2Zmc2V0XG5jdXN0b21faml0dGVyX29mZnNldF9NYWluIjpbMF0sIlxuY3VzdG9tX2ppdHRlcl9tb2RlX01vdmUgQ3JvdWNoZWQiOlsiMi1XYXkiXSwiRGVsYXkgQ3ljbGVcbmN1c3RvbV9kZWxheV9jeWNsZV9TbG93IFdhbGsiOls1MF0sIkVuYWJsZSBTbG93IFdhbGsiOltmYWxzZV0sIkxlZnQgb2Zmc2V0XG5jdXN0b21feWF3X2xlZnRfQ3JvdWNoZWQiOlswXSwiRnJlZXN0YW5kaW5nIGJvZHkgeWF3XG5jdXN0b21fZnJlZXN0YW5kaW5nX2JvZHlfeWF3X0Zha2UgTGFnIjpbZmFsc2VdLCJcbmN1c3RvbV95YXdfMTgwbHJfbW9kZV9Dcm91Y2hlZCI6WyJTaWRlIGJhc2VkIl0sIlxuSml0dGVyIG9mZnNldFxuY3VzdG9tX2ppdHRlcl9vZmZzZXRfU3RhbmRpbmciOlswXSwiRnJlZXN0YW5kaW5nIGJvZHkgeWF3XG5jdXN0b21fZnJlZXN0YW5kaW5nX2JvZHlfeWF3X01vdmluZyI6W2ZhbHNlXSwiXG5jdXN0b21fcGl0Y2hfb2Zmc2V0X0Zha2UgTGFnIjpbMF0sIlNhZmUgWWF3XG5jdXN0b21fc2FmZV95YXdfU3RhbmRpbmciOltmYWxzZV0sIkJvZHkgeWF3XG5jdXN0b21fYm9keV95YXdfRmFrZSBMYWciOlsiT2ZmIl0sIlNhZmUgWWF3XG5jdXN0b21fc2FmZV95YXdfRmFrZSBMYWciOltmYWxzZV0sIkJvZHkgeWF3XG5jdXN0b21fYm9keV95YXdfTWFpbiI6WyJPZmYiXSwiTGVmdCBvZmZzZXRcbmN1c3RvbV95YXdfbGVmdF9Nb3ZpbmciOlswXSwiRGVsYXkgVGltZVxuY3VzdG9tX2FjaWRfZGVsYXlGYWtlIExhZyI6WzE1XSwiQm9keSB5YXdcbmN1c3RvbV9ib2R5X3lhd19Nb3ZpbmciOlsiT2ZmIl0sIlJpZ2h0IG9mZnNldFxuY3VzdG9tX3lhd19yaWdodF9Nb3ZlIENyb3VjaGVkIjpbMF0sIlJhbmRvbWl6YXRpb25cbmN1c3RvbV9qaXR0ZXJfcmFuZG9taXphdGlvbl9GYWtlIExhZyI6WzBdLCJcbkppdHRlciBvZmZzZXRcbmN1c3RvbV9qaXR0ZXJfb2Zmc2V0X0Zha2UgTGFnIjpbMF0sIlxuY3VzdG9tX2ppdHRlcl9tb2RlX0Zha2UgTGFnIjpbIjItV2F5Il0sIkZyZWVzdGFuZGluZyBib2R5IHlhd1xuY3VzdG9tX2ZyZWVzdGFuZGluZ19ib2R5X3lhd19BaXIiOltmYWxzZV0sIkxlZnQgb2Zmc2V0XG5jdXN0b21feWF3X2xlZnRfQWlyIENyb3VjaGVkIjpbMF0sIkZyZWVzdGFuZGluZyBib2R5IHlhd1xuY3VzdG9tX2ZyZWVzdGFuZGluZ19ib2R5X3lhd19Dcm91Y2hlZCI6W2ZhbHNlXSwiRW5hYmxlIFN0YW5kaW5nIjpbZmFsc2VdLCJEZWxheSBUaW1lXG5jdXN0b21fYWNpZF9kZWxheUFpciBDcm91Y2hlZCI6WzE1XSwiUmlnaHQgb2Zmc2V0XG5jdXN0b21feWF3X3JpZ2h0X0Zha2UgTGFnIjpbMF0sIktleWJpbmRzIjpbZmFsc2VdLCJSYW5kb21pemF0aW9uXG5jdXN0b21faml0dGVyX3JhbmRvbWl6YXRpb25fTWFpbiI6WzBdLCItIERpc3BsYXlcbndpZGdldHM6OmRpc3BsYXkiOltbIlVzZXJuYW1lIiwiTGF0ZW5jeSIsIlRpbWUiLCJGUFMiLCJTZXJ2ZXIgZnJhbWV0aW1lIl1dLCJEZWxheVxuY3VzdG9tX0RlbGF5X0FpciI6WzVdLCJNb2RlIjpbIkRlZmF1bHQiXSwiWWF3XG5jdXN0b21feWF3X0Zha2UgTGFnIjpbIk9mZiJdLCJZYXdcbmN1c3RvbV95YXdfQWlyIENyb3VjaGVkIjpbIk9mZiJdLCJFbmFibGUgRmFrZSBMYWciOltmYWxzZV0sIkRlbGF5IFRpbWVcbmN1c3RvbV9hY2lkX2RlbGF5TW92aW5nIjpbMTVdLCJEZWxheSBUaW1lXG5jdXN0b21fYWNpZF9kZWxheUNyb3VjaGVkIjpbMTVdLCJSaWdodCBvZmZzZXRcbmN1c3RvbV95YXdfcmlnaHRfQWlyIENyb3VjaGVkIjpbMF0sIkZyZWVzdGFuZGluZyBib2R5IHlhd1xuY3VzdG9tX2ZyZWVzdGFuZGluZ19ib2R5X3lhd19BaXIgQ3JvdWNoZWQiOltmYWxzZV0sIlxuY3VzdG9tX2JvZHlfeWF3X29mZnNldF9BaXIgQ3JvdWNoZWQiOlswXSwiQ3VzdG9tIE5hbWUiOltmYWxzZV0sIkJvZHkgeWF3XG5jdXN0b21fYm9keV95YXdfQWlyIENyb3VjaGVkIjpbIk9mZiJdLCJcbmN1c3RvbV9qaXR0ZXJfbW9kZV9Nb3ZpbmciOlsiMi1XYXkiXSwiXG5jdXN0b21fYm9keV95YXdfb2Zmc2V0X01vdmluZyI6WzBdLCJcbmN1c3RvbV9qaXR0ZXJfbW9kZV9Dcm91Y2hlZCI6WyIyLVdheSJdLCJEZWxheSBDeWNsZVxuY3VzdG9tX2RlbGF5X2N5Y2xlX0FpciBDcm91Y2hlZCI6WzUwXSwiXG5KaXR0ZXIgb2Zmc2V0XG5jdXN0b21faml0dGVyX29mZnNldF9BaXIgQ3JvdWNoZWQiOlswXSwiWWF3IGppdHRlclxuY3VzdG9tX3lhd19qaXR0ZXJfRmFrZSBMYWciOlsiT2ZmIl0sIkxlZnQgb2Zmc2V0XG5jdXN0b21feWF3X2xlZnRfU3RhbmRpbmciOlswXSwiRnJlZXN0YW5kaW5nIGJvZHkgeWF3XG5jdXN0b21fZnJlZXN0YW5kaW5nX2JvZHlfeWF3X1N0YW5kaW5nIjpbZmFsc2VdLCJcdTAwMDdiNmI2NjVmZkd1YXJkaWFuIjpbdHJ1ZV0sIkVuYWJsZSBBaXIiOltmYWxzZV0sIlxuY3VzdG9tX3lhd19vZmZzZXRfQWlyIENyb3VjaGVkIjpbMF0sIlBpdGNoXG5jdXN0b21fcGl0Y2hfRmFrZSBMYWciOlsiT2ZmIl0sIkNsaWVudC1TaWRlIE5pY2tuYW1lIjpbZmFsc2VdLCJcbmN1c3RvbV9waXRjaF9vZmZzZXRfQWlyIENyb3VjaGVkIjpbMF0sIlBpdGNoXG5jdXN0b21fcGl0Y2hfQWlyIENyb3VjaGVkIjpbIk9mZiJdLCJSYW5kb21pemF0aW9uXG5jdXN0b21faml0dGVyX3JhbmRvbWl6YXRpb25fQ3JvdWNoZWQiOlswXSwiRW5hYmxlIEFpciBDcm91Y2hlZCI6W2ZhbHNlXSwiXG5jdXN0b21faml0dGVyX21vZGVfQWlyIENyb3VjaGVkIjpbIjItV2F5Il0sIkxlZnQgb2Zmc2V0XG5jdXN0b21feWF3X2xlZnRfTW92ZSBDcm91Y2hlZCI6WzBdLCJEZWxheSBUaW1lXG5jdXN0b21fYWNpZF9kZWxheU1haW4iOlsxNV0sIkFwcGx5Ijp7fSwiXG5jdXN0b21fcGl0Y2hfb2Zmc2V0X0FpciI6WzBdLCJTYWZlIFlhd1xuY3VzdG9tX3NhZmVfeWF3X0FpciI6W2ZhbHNlXSwiRGVsYXkgVGltZVxuY3VzdG9tX2FjaWRfZGVsYXlBaXIiOlsxNV0sIlxuY3VzdG9tX3lhd19vZmZzZXRfTWFpbiI6WzBdLCJcbmN1c3RvbV9waXRjaF9vZmZzZXRfU2xvdyBXYWxrIjpbMF0sIllhdyBqaXR0ZXJcbmN1c3RvbV95YXdfaml0dGVyX01vdmUgQ3JvdWNoZWQiOlsiT2ZmIl0sIllhdyBqaXR0ZXJcbmN1c3RvbV95YXdfaml0dGVyX1N0YW5kaW5nIjpbIk9mZiJdLCJCb2R5IHlhd1xuY3VzdG9tX2JvZHlfeWF3X0Nyb3VjaGVkIjpbIk9mZiJdLCJEZWxheSBUaW1lXG5jdXN0b21fYWNpZF9kZWxheU1vdmUgQ3JvdWNoZWQiOlsxNV0sIlNhZmUgWWF3XG5jdXN0b21fc2FmZV95YXdfQ3JvdWNoZWQiOltmYWxzZV0sIkFuaW1hdGlvbiBCcmVha2VycyI6W3RydWVdLCJTYWZlIFlhd1xuY3VzdG9tX3NhZmVfeWF3X1Nsb3cgV2FsayI6W2ZhbHNlXSwiRGVsYXkgQ3ljbGVcbmN1c3RvbV9kZWxheV9jeWNsZV9NYWluIjpbNTBdLCJcbmN1c3RvbV95YXdfb2Zmc2V0X01vdmUgQ3JvdWNoZWQiOlswXSwiUmlnaHQgb2Zmc2V0XG5jdXN0b21feWF3X3JpZ2h0X0FpciI6WzBdLCJcbmN1c3RvbV95YXdfb2Zmc2V0X0Nyb3VjaGVkIjpbMF0sIllhdyBiYXNlXG5jdXN0b21feWF3X2Jhc2VfQWlyIjpbIkxvY2FsIHZpZXciXSwiXG5jdXN0b21faml0dGVyX21vZGVfU3RhbmRpbmciOlsiMi1XYXkiXSwiUmFuZG9taXphdGlvblxuY3VzdG9tX2ppdHRlcl9yYW5kb21pemF0aW9uX01vdmluZyI6WzBdLCJMZWZ0IG9mZnNldFxuY3VzdG9tX3lhd19sZWZ0X0FpciI6WzBdLCJGcmVlc3RhbmRpbmcgYm9keSB5YXdcbmN1c3RvbV9mcmVlc3RhbmRpbmdfYm9keV95YXdfTW92ZSBDcm91Y2hlZCI6W2ZhbHNlXSwiQ3VzdG9tIFNjb3BlIE92ZXJsYXkiOlt0cnVlXSwiXG5jdXN0b21feWF3XzE4MGxyX21vZGVfTW92ZSBDcm91Y2hlZCI6WyJTaWRlIGJhc2VkIl0sIi0gU3RhdGVzXG5zYWZlX2hlYWQ6OnN0YXRlcyI6W1siQWlyIEtuaWZlIiwiU3RhbmRpbmciLCJDcm91Y2hlZCJdXSwiWWF3XG5jdXN0b21feWF3X0FpciI6WyJPZmYiXSwiRGVmZW5zaXZlIEFBIjpbdHJ1ZV0sIkVuYWJsZSBDcm91Y2hlZCI6W2ZhbHNlXSwiXG5jdXN0b21feWF3XzE4MGxyX21vZGVfQWlyIENyb3VjaGVkIjpbIlNpZGUgYmFzZWQiXSwiXG5jdXN0b21feWF3XzE4MGxyX21vZGVfQWlyIjpbIlNpZGUgYmFzZWQiXSwiRGVsYXlcbmN1c3RvbV9EZWxheV9Nb3ZlIENyb3VjaGVkIjpbNV0sIkRlbGF5IEN5Y2xlXG5jdXN0b21fZGVsYXlfY3ljbGVfTW92aW5nIjpbNTBdLCJQcmltYXJ5IHdlYXBvbiI6WyJTY291dCJdLCJZYXcgYmFzZVxuY3VzdG9tX3lhd19iYXNlX0FpciBDcm91Y2hlZCI6WyJMb2NhbCB2aWV3Il0sIllhdyBiYXNlXG5jdXN0b21feWF3X2Jhc2VfU2xvdyBXYWxrIjpbIkxvY2FsIHZpZXciXSwiRGVsYXkgVGltZVxuY3VzdG9tX2FjaWRfZGVsYXlTbG93IFdhbGsiOlsxNV0sIlxuSml0dGVyIG9mZnNldFxuY3VzdG9tX2ppdHRlcl9vZmZzZXRfTW92aW5nIjpbMF0sIlxuY3VzdG9tX2JvZHlfeWF3X29mZnNldF9Nb3ZlIENyb3VjaGVkIjpbMF0sIlxuY3VzdG9tX2JvZHlfeWF3X29mZnNldF9BaXIiOlswXSwiWWF3XG5jdXN0b21feWF3X01vdmUgQ3JvdWNoZWQiOlsiT2ZmIl0sIi0gTW9kZVxuZGVmZW5zaXZlOjptb2RlIjpbWyJPbiBTaG90IEFudGkgQWltIiwiRG91YmxlIFRhcCJdXSwiXG5jdXN0b21fcGl0Y2hfb2Zmc2V0X01haW4iOlswXSwiWWF3IGJhc2VcbmN1c3RvbV95YXdfYmFzZV9Nb3ZlIENyb3VjaGVkIjpbIkxvY2FsIHZpZXciXSwiUGl0Y2hcbmN1c3RvbV9waXRjaF9Nb3ZlIENyb3VjaGVkIjpbIk9mZiJdLCJFbmFibGUgTW92ZSBDcm91Y2hlZCI6W2ZhbHNlXSwiLSBGdW5jdGlvbnNcbnNldHRpbmdzOjp0d2Vha3MiOltbIlVubXV0ZSBTaWxlbmNlZCBQbGF5ZXJzIiwiQ29uc29sZSBGaWx0ZXIiLCJEYW1hZ2UgTWFya2VyIl1dLCJEZWxheVxuY3VzdG9tX0RlbGF5X0Zha2UgTGFnIjpbNV0sIi0gT3B0aW9uc1xubWFudWFsX2RpcmVjdGlvbjo6b3B0aW9ucyI6W1siRGlzYWJsZSBZYXcgTW9kaWZpZXJzIiwiRnJlZXN0YW5kaW5nIEJvZHkgWWF3IiwiRHVjayBFeHBsb2l0Il1dLCJcbmN1c3RvbV9qaXR0ZXJfbW9kZV9NYWluIjpbIjItV2F5Il0sIkRlbGF5XG5jdXN0b21fRGVsYXlfU2xvdyBXYWxrIjpbNV0sIlxuY3VzdG9tX2JvZHlfeWF3X29mZnNldF9Dcm91Y2hlZCI6WzBdLCJCdXkgQm90IjpbdHJ1ZV0sIkVuYWJsZSBNb3ZpbmciOltmYWxzZV0sIllhd1xuY3VzdG9tX3lhd19NYWluIjpbIk9mZiJdLCJGZWF0dXJlcyI6W3RydWVdLCJcbmN1c3RvbV9ib2R5X3lhd19vZmZzZXRfU2xvdyBXYWxrIjpbMF0sIkRlbGF5XG5jdXN0b21fRGVsYXlfU3RhbmRpbmciOls1XSwiWWF3IGJhc2VcbmN1c3RvbV95YXdfYmFzZV9Nb3ZpbmciOlsiTG9jYWwgdmlldyJdLCJcbk9mZnNldCI6WzEwXSwiWWF3IGppdHRlclxuY3VzdG9tX3lhd19qaXR0ZXJfTWFpbiI6WyJPZmYiXSwiRGVsYXlcbmN1c3RvbV9EZWxheV9NYWluIjpbNV0sIlJpZ2h0IG9mZnNldFxuY3VzdG9tX3lhd19yaWdodF9NYWluIjpbMF0sIlNhZmUgWWF3XG5jdXN0b21fc2FmZV95YXdfQWlyIENyb3VjaGVkIjpbZmFsc2VdLCJNYW51YWwgQXJyb3dzIjpbdHJ1ZV0sIlBpdGNoXG5jdXN0b21fcGl0Y2hfTWFpbiI6WyJPZmYiXSwiLSBJbiBBaXIiOlsiU3RhdGljIl0sIlBpdGNoXG5jdXN0b21fcGl0Y2hfQ3JvdWNoZWQiOlsiT2ZmIl0sIlJpZ2h0IG9mZnNldFxuY3VzdG9tX3lhd19yaWdodF9Nb3ZpbmciOlswXSwiWWF3IGppdHRlclxuY3VzdG9tX3lhd19qaXR0ZXJfTW92aW5nIjpbIk9mZiJdLCJOaWNrbmFtZSI6WyIiXSwiWWF3IGppdHRlclxuY3VzdG9tX3lhd19qaXR0ZXJfQ3JvdWNoZWQiOlsiT2ZmIl0sIkRlbGF5IEN5Y2xlXG5jdXN0b21fZGVsYXlfY3ljbGVfRmFrZSBMYWciOls1MF0sIi0gTGVnIE1vdmVtZW50IjpbIlN0YXRpYyJdLCJcbmN1c3RvbV95YXdfMTgwbHJfbW9kZV9Nb3ZpbmciOlsiU2lkZSBiYXNlZCJdLCJcbmN1c3RvbV95YXdfb2Zmc2V0X0Zha2UgTGFnIjpbMF0sIi0gVGlja3MiOlsxMF0sIkZyZWVzdGFuZGluZyBib2R5IHlhd1xuY3VzdG9tX2ZyZWVzdGFuZGluZ19ib2R5X3lhd19NYWluIjpbZmFsc2VdLCJSYW5kb21pemF0aW9uXG5jdXN0b21faml0dGVyX3JhbmRvbWl6YXRpb25fU2xvdyBXYWxrIjpbMF0sIlxuY3VzdG9tX3BpdGNoX29mZnNldF9Nb3ZpbmciOlswXSwiTGVmdCBvZmZzZXRcbmN1c3RvbV95YXdfbGVmdF9NYWluIjpbMF0sIkRlbGF5IEN5Y2xlXG5jdXN0b21fZGVsYXlfY3ljbGVfQWlyIjpbNTBdLCJcbmN1c3RvbV9ib2R5X3lhd19vZmZzZXRfU3RhbmRpbmciOlswXSwiUmFuZG9taXphdGlvblxuY3VzdG9tX2ppdHRlcl9yYW5kb21pemF0aW9uX0FpciI6WzBdLCJZYXcgYmFzZVxuY3VzdG9tX3lhd19iYXNlX1N0YW5kaW5nIjpbIkxvY2FsIHZpZXciXSwiQm9keSB5YXdcbmN1c3RvbV9ib2R5X3lhd19Nb3ZlIENyb3VjaGVkIjpbIk9mZiJdLCJTYWZlIFlhd1xuY3VzdG9tX3NhZmVfeWF3X01vdmluZyI6W2ZhbHNlXSwiWWF3XG5jdXN0b21feWF3X0Nyb3VjaGVkIjpbIk9mZiJdLCJcbmN1c3RvbV9waXRjaF9vZmZzZXRfU3RhbmRpbmciOlswXSwiXG5jdXN0b21feWF3XzE4MGxyX21vZGVfU2xvdyBXYWxrIjpbIlNpZGUgYmFzZWQiXSwiXG5KaXR0ZXIgb2Zmc2V0XG5jdXN0b21faml0dGVyX29mZnNldF9Dcm91Y2hlZCI6WzBdLCItIFlhd1xuZGVmZW5zaXZlOjp5YXciOlsiU3BpbmJvdCJdLCJZYXcgaml0dGVyXG5jdXN0b21feWF3X2ppdHRlcl9BaXIgQ3JvdWNoZWQiOlsiT2ZmIl0sIlJpZ2h0IG9mZnNldFxuY3VzdG9tX3lhd19yaWdodF9TbG93IFdhbGsiOlswXSwiXG5jdXN0b21faml0dGVyX21vZGVfU2xvdyBXYWxrIjpbIjItV2F5Il0sIlxuY3VzdG9tX3BpdGNoX29mZnNldF9Dcm91Y2hlZCI6WzBdLCJcbmN1c3RvbV9ib2R5X3lhd19vZmZzZXRfTWFpbiI6WzBdLCJQaXRjaFxuY3VzdG9tX3BpdGNoX1Nsb3cgV2FsayI6WyJPZmYiXSwiLSBDb2xvclxud2lkZ2V0czo6Y29sb3JfcGlja2VyIjpbMTEzLDE1MiwyNTUsMjU1XSwiXG5jdXN0b21feWF3XzE4MGxyX21vZGVfU3RhbmRpbmciOlsiU2lkZSBiYXNlZCJdfQ==_acid'
            )
        end):config_ignore()

        function graphics.text(x, y, r, g, b, a, flags, max_width, ...)
            local text = string_alpha_mod(merge {...}, a * alpha_unit)
            renderer.text(x, y, r, g, b, a, flags, max_width, text)
        end

        function graphics.rectangle(x, y, w, h, r, g, b, a, radius)
            if radius ~= nil and radius > 1 then
                local offset = radius * 2

                renderer.rectangle(x + radius, y, w - offset, h, r, g, b, a)

                renderer.rectangle(x, y + radius, radius, h - offset, r, g, b, a)
                renderer.rectangle(x + w, y + radius, -radius, h - offset, r, g, b, a)

                renderer.circle(x + radius, y + radius, r, g, b, a, radius, 180, 0.25)
                renderer.circle(x + radius, y + h - radius, r, g, b, a, radius, 270, 0.25)
                renderer.circle(x + w - radius, y + h - radius, r, g, b, a, radius, 0, 0.25)
                renderer.circle(x + w - radius, y + radius, r, g, b, a, radius, 90, 0.25)

                return
            end

            renderer.rectangle(x, y, w, h, r, g, b, a)
        end

        function graphics.rectangle_outline(x, y, w, h, r, g, b, a, radius, thickness)
            radius = radius or 0
            thickness = thickness or 1

            renderer.rectangle(x + radius, y, w - radius * 2, thickness, r, g, b, a)
            renderer.rectangle(x + radius, y + h - thickness, w - radius * 2, thickness, r, g, b, a)

            renderer.rectangle(x, y + radius, thickness, h - radius * 2, r, g, b, a)
            renderer.rectangle(x + w - thickness, y + radius, thickness, h - radius * 2, r, g, b, a)

            renderer.circle_outline(x + radius, y + radius, r, g, b, a, radius, 180, 0.25, thickness)
            renderer.circle_outline(x + radius, y + h - radius, r, g, b, a, radius, 90, 0.25, thickness)
            renderer.circle_outline(x + w - radius, y + h - radius, r, g, b, a, radius, 0, 0.25, thickness)
            renderer.circle_outline(x + w - radius, y + radius, r, g, b, a, radius, 270, 0.25, thickness)
        end

        function graphics.blur(x, y, w, h)
            -- if true then
            --     return
            -- end

            -- renderer.blur(x, y, w, h)
        end

        function graphics.header(x, y, w, thickness, rounding, r, g, b, a)
            renderer.rectangle(x + rounding, y - thickness, w - (rounding + thickness), thickness, r, g, b, a)

            if rounding ~= 0 then
                -- outer rounding
                local add_rounding = vector(rounding, rounding)
                renderer.circle_outline(x + rounding, y + rounding, r, g, b, a, rounding + thickness, -180, 0.25, thickness)
                renderer.circle_outline(x + w - rounding, y + rounding, r, g, b, a, rounding + thickness, -90, 0.25, thickness)

                -- gradient lines
                local thickness_dv = thickness / 2 - 1
                renderer.gradient(x - thickness, y + rounding, thickness, rounding + 7, r, g, b, a, r, g, b, 0, false)
                renderer.gradient(x + w, y + rounding, thickness, rounding + 7, r, g, b, a, r, g, b, 0, false)
            end
        end

        function graphics.glow(x, y, w, h, r, g, b, a, thickness, radius)
            -- if graphics.low_fps_mitigations:have_key("Glow") then
            -- if true then
            --     return
            -- end

            -- if radius == nil then
            --     return
            -- end

            -- if radius < 1 then
            --     radius = 1
            -- end

            -- thickness = thickness / 2

            -- local t = 1.0
            -- local step = 1 / (thickness - 1)

            -- local offset = radius * 2

            -- renderer.gradient(x + radius, y, w - offset, -thickness, r, g, b, a, r, g, b, 0, false)
            -- renderer.gradient(x + radius, y + h, w - offset, thickness, r, g, b, a, r, g, b, 0, false)
            -- renderer.gradient(x, y + radius, -thickness, h - offset, r, g, b, a, r, g, b, 0, true)
            -- renderer.gradient(x + w, y + radius, thickness, h - offset, r, g, b, a, r, g, b, 0, true)

            -- for i = 1, thickness do
            --     local opacity = a * t

            --     renderer.circle_outline(x + w - radius, y + h - radius, r, g, b, opacity, radius + i, 0, 0.25, 1)
            --     renderer.circle_outline(x + radius, y + h - radius, r, g, b, opacity, radius + i, 90, 0.25, 1)
            --     renderer.circle_outline(x + radius, y + radius, r, g, b, opacity, radius + i, 180, 0.25, 1)
            --     renderer.circle_outline(x + w - radius, y + radius, r, g, b, opacity, radius + i, 270, 0.25, 1)

            --     t = t - step
            -- end
        end
    end

    --- region decorations
    do
        local function u8(s)
            return string.gsub(s, "[\128-\191]", "")
        end

        function decorations.wave(s, clock, r1, g1, b1, a1, r2, g2, b2, a2)
            local buffer = { }

            local len = #u8(s)
            local div = 1 / (len - 1)

            local add_r = r2 - r1
            local add_g = g2 - g1
            local add_b = b2 - b1
            local add_a = a2 - a1

            for char in string.gmatch(s, ".[\128-\191]*") do
                local t = utils.breathe(clock)

                local r = r1 + add_r * t
                local g = g1 + add_g * t
                local b = b1 + add_b * t
                local a = a1 + add_a * t

                buffer[#buffer + 1] = "\a"
                buffer[#buffer + 1] = utils.to_hex(r, g, b, a)
                buffer[#buffer + 1] = char

                clock = clock + div
            end

            return merge(buffer)
        end
    end

    --- region exploit
    do
        local LAG_COMPENSATION_TELEPORTED_DISTANCE_SQR = 64 * 64

        local data = {
            old_origin = vector(),
            old_simtime = 0.0,

            shift = false,
            breaking_lc = false,

            defensive = {
                begin = 0,
                duration = 0
            },

            lagcompensation = {
                distance = 0.0,
                teleport = false
            },

            defensive_tk = 0
        }

        local function update_tickbase(me)
            local tickcount = globals.tickcount()
            local m_nTickBase = entity.get_prop(me, "m_nTickBase")

            data.shift = tickcount > m_nTickBase
        end

        local function update_defensive(tick)
            data.breaking_lc = true

            data.defensive.begin = globals.tickcount()
            data.defensive.duration = tick
        end

        local function update_teleport(old_origin, new_origin)
            local delta = new_origin - old_origin
            local distance = delta:lengthsqr()

            local is_teleport = distance > LAG_COMPENSATION_TELEPORTED_DISTANCE_SQR

            data.breaking_lc = is_teleport

            data.lagcompensation.distance = distance
            data.lagcompensation.teleport = is_teleport
        end

        local function update_lagcompensation(me)
            local old_origin = data.old_origin
            local old_simtime = data.old_simtime

            local origin = vector(entity.get_origin(me))
            local simtime = toticks(entity.get_prop(me, "m_flSimulationTime"))

            if old_simtime ~= nil then
                local delta = simtime - old_simtime

                if delta < 0 or delta > 0 and delta <= 64 then
                    local tick = delta - 1

                    update_teleport(old_origin, origin)

                    if delta < 0 then
                        update_defensive(math.abs(tick))
                    end
                end
            end

            data.old_origin = origin
            data.old_simtime = simtime
        end

        function exploit.get()
            return data
        end

        function exploit.setup_command(cmd)
            local me = entity.get_local_player()
            update_tickbase(me)
        end

        function exploit.net_update()
            local me = entity.get_local_player()

            if me == nil then
                return
            end

            update_lagcompensation(me)
        end

        local native_GetClientEntity = vtable_bind('client.dll', 'VClientEntityList003', 3, 'void*(__thiscall*)(void*, int)')

        function exploit.handle_defensive()
            local lp = entity.get_local_player()

            if lp == nil or not entity.is_alive(lp) then
                return
            end

            local Entity = native_GetClientEntity(lp)
            local m_flOldSimulationTime = ffi.cast("float*", ffi.cast("uintptr_t", Entity) + 0x26C)[0]
            local m_flSimulationTime = entity.get_prop(lp, "m_flSimulationTime")

            local delta = m_flOldSimulationTime - m_flSimulationTime

            if delta > 0 then
                data.defensive_tk = globals.tickcount() + toticks(delta - client.real_latency())
                return
            end
        end
    end

    --- region localplayer
    do
        local MOVING_LIMIT = 1.1 * 3.3
        local DUCK_PEEK_LIMIT = 0.79

        local pre_flags = 0
        local post_flags = 0

        local function get_body_yaw(animstate)
            local body_yaw = animstate.eye_angles_y - animstate.goal_feet_yaw
            body_yaw = utils.normalize_yaw(body_yaw)

            return body_yaw
        end

        localplayer.flags = 0
        localplayer.packets = 0
        localplayer.choking = 1
        localplayer.choking_bool = false

        localplayer.body_yaw = 0
        localplayer.duck_amount = 0

        localplayer.movetype = 0
        localplayer.velocity = 0

        localplayer.is_onground = false
        localplayer.is_crouched = false

        localplayer.is_moving = false
        localplayer.is_landing = false
        localplayer.is_airborne = false

        function localplayer.pre_predict_command(e)
            local me = entity.get_local_player()
            pre_flags = entity.get_prop(me, "m_fFlags")
        end

        function localplayer.predict_command(e)
            local me = entity.get_local_player()
            post_flags = entity.get_prop(me, "m_fFlags")
        end

        function localplayer.net_update()
            local me = entity.get_local_player()
            if me == nil then return end

            local my_data = c_entity(me)
            if my_data == nil then return end

            local animstate = c_entity.get_anim_state(my_data)
            if animstate == nil then return end

            local chokedcommands = globals.chokedcommands()

            local m_fFlags = entity.get_prop(me, "m_fFlags")
            local m_movetype = entity.get_prop(me, "m_movetype")
            local m_flDuckAmount = entity.get_prop(me, "m_flDuckAmount")

            localplayer.flags = m_fFlags
            localplayer.movetype = m_movetype
            localplayer.velocity = animstate.m_velocity

            if chokedcommands == 0 then
                localplayer.packets = localplayer.packets + 1
                localplayer.choking = localplayer.choking * -1
                localplayer.choking_bool = not localplayer.choking_bool

                localplayer.body_yaw = get_body_yaw(animstate)
                localplayer.duck_amount = m_flDuckAmount
            end

            localplayer.is_onground = animstate.on_ground
            localplayer.is_crouched = localplayer.duck_amount > DUCK_PEEK_LIMIT

            localplayer.is_moving = localplayer.velocity > MOVING_LIMIT
            localplayer.is_landing = animstate.hit_in_ground_animation
            localplayer.is_airborne = bit.band(pre_flags, post_flags, 1) == 0
        end
    end

    --- region statement
    do
        local list = { }

        local function add(state)
            list[#list + 1] = state
        end

        local function update_onground()
            if localplayer.is_moving then
                add "Moving"

                if localplayer.is_crouched then
                    return
                end

                if localplayer.is_airborne then
                    return
                end

                if software.is_slow_motion() then
                    add "Slow Walk"
                end

                return
            end

            add "Standing"
        end

        local function update_crouched()
            if not localplayer.is_crouched then
                return
            end

            add "Crouched"

            if localplayer.is_moving then
                add "Move Crouched"
            end
        end

        local function update_airborne()
            if not localplayer.is_airborne then
                return
            end

            add "Air"

            if localplayer.is_crouched then
                add "Air Crouched"
            end
        end

        local function update_exploit()
            if exploit.get().shift or (software.is_double_tap() or software.is_on_shot_antiaim()) then
                return
            end

            add "Fake Lag"
        end

        function statement.get()
            return list
        end

        function statement.add(state)
            add(state)
        end

        function statement.setup_command()
            table.clear(list)

            update_onground()
            update_crouched()
            update_airborne()
            update_exploit()
        end
    end

    --- region antiaim
    do
        local ctx = { }

        -- Guardian AA anti-overlap + anti-onshot pre-protect
        -- Integrated into the existing ctx pipeline, so it does not fight the override system.
        antiaim.overlap = {}
        antiaim.overlap.enabled = menu.new_item(ui.new_checkbox, "AA", "Anti-aimbot angles", "AA Anti-Overlap Desync")
        : record("aa", "aa_overlap::enabled")
        : save()

        antiaim.overlap.onshot = menu.new_item(ui.new_checkbox, "AA", "Anti-aimbot angles", "- On-shot AA improver")
        : record("aa", "aa_overlap::onshot")
        : save()

        antiaim.overlap.onshot_mode = menu.new_item(ui.new_combobox, "AA", "Anti-aimbot angles", "- On-shot mode", { "Flip side", "Force left", "Force right" })
        : record("aa", "aa_overlap::onshot_mode")
        : save()

        antiaim.overlap.onshot_limit = menu.new_item(ui.new_slider, "AA", "Anti-aimbot angles", "- On-shot desync", 0, 60, 60, true, "°")
        : record("aa", "aa_overlap::onshot_limit")
        : save()

        antiaim.overlap.onshot_hold = menu.new_item(ui.new_slider, "AA", "Anti-aimbot angles", "- On-shot hold", 1, 10, 4, true, "t")
        : record("aa", "aa_overlap::onshot_hold")
        : save()

        antiaim.overlap.pre_onshot = menu.new_item(ui.new_checkbox, "AA", "Anti-aimbot angles", "- Anti-onshot pre-protect")
        : record("aa", "aa_overlap::pre_onshot")
        : save()

        antiaim.overlap.pre_onshot_hold = menu.new_item(ui.new_slider, "AA", "Anti-aimbot angles", "- Pre-protect hold", 1, 8, 3, true, "t")
        : record("aa", "aa_overlap::pre_onshot_hold")
        : save()

        antiaim.overlap.protect_fd = menu.new_item(ui.new_checkbox, "AA", "Anti-aimbot angles", "- Protect fakeduck")
        : record("aa", "aa_overlap::protect_fd")
        : save()

        antiaim.overlap.fd_limit = menu.new_item(ui.new_slider, "AA", "Anti-aimbot angles", "- Fakeduck desync", 0, 60, 60, true, "°")
        : record("aa", "aa_overlap::fd_limit")
        : save()

        antiaim.overlap.fakelag = menu.new_item(ui.new_checkbox, "AA", "Anti-aimbot angles", "- Fake lag desync")
        : record("aa", "aa_overlap::fakelag")
        : save()

        antiaim.overlap.fakelag_limit = menu.new_item(ui.new_slider, "AA", "Anti-aimbot angles", "- Fake lag desync", 0, 60, 60, true, "°")
        : record("aa", "aa_overlap::fakelag_limit")
        : save()

        antiaim.overlap.disable_jitter = menu.new_item(ui.new_checkbox, "AA", "Anti-aimbot angles", "- Disable jitter while fakeduck")
        : record("aa", "aa_overlap::disable_jitter")
        : save()

        antiaim.overlap.avoid_real_fake = menu.new_item(ui.new_checkbox, "AA", "Anti-aimbot angles", "- Avoid real/fake overlap")
        : record("aa", "aa_overlap::avoid_real_fake")
        : save()

        antiaim.overlap.min_real_fake_gap = menu.new_item(ui.new_slider, "AA", "Anti-aimbot angles", "- Min real/fake gap", 10, 90, 35, true, "°")
        : record("aa", "aa_overlap::min_real_fake_gap")
        : save()

        antiaim.overlap.debug = menu.new_item(ui.new_checkbox, "AA", "Anti-aimbot angles", "- Debug AA overlap")
        : record("aa", "aa_overlap::debug")
        : save()

        local aa_overlap_state = {
            side = 0,
            limit = 0,
            source = "none",
            priority = 0,
            lock_until = 0,
            last_shot_time = 0,
            last_shot_tick = 0,
            last_trigger_tick = -1,
            prelock_until = 0,
            prepared_onshot = false,
            visible_tick = -1,
            visible_cache = false,
            onshot_side = 1,
            attack_down = false
        }

        local aa_overlap_priority = {
            manual = 100,
            fakeduck = 98,
            onshot = 97,
            pre_onshot = 96,
            defensive = 90,
            freestanding = 80,
            fakelag = 75,
            edge = 70,
            jitter = 60,
            default = 10
        }

        local function aa_overlap_priority_of(source)
            return aa_overlap_priority[source] or aa_overlap_priority.default
        end

        local function aa_overlap_request(source, side, limit, hold_ticks)
            local tick = globals.tickcount()
            local new_priority = aa_overlap_priority_of(source)
            local old_priority = aa_overlap_state.priority or 0

            side = side or 0
            limit = utils.clamp(limit or 0, 0, 180)
            hold_ticks = hold_ticks or 2

            -- A stronger active AA state should not be overwritten by weaker jitter/freestanding/default logic.
            if tick < (aa_overlap_state.lock_until or 0) and old_priority > new_priority then
                return false
            end

            -- Prevent weak instant left/right flips while a lock is still fresh.
            if aa_overlap_state.side ~= 0 and side ~= 0 and aa_overlap_state.side ~= side then
                if new_priority < old_priority + 15 and tick < (aa_overlap_state.lock_until or 0) + 2 then
                    return false
                end
            end

            aa_overlap_state.side = side
            aa_overlap_state.limit = limit
            aa_overlap_state.source = source
            aa_overlap_state.priority = new_priority
            aa_overlap_state.lock_until = tick + hold_ticks

            return true
        end

        local function aa_overlap_pick_onshot_side()
            local mode = antiaim.overlap.onshot_mode:get()
            if mode == "Flip side" then
                aa_overlap_state.onshot_side = -aa_overlap_state.onshot_side
            elseif mode == "Force left" then
                aa_overlap_state.onshot_side = -1
            elseif mode == "Force right" then
                aa_overlap_state.onshot_side = 1
            end
        end

        local function aa_overlap_prepare_onshot(tick)
            local pre_hold = antiaim.overlap.pre_onshot_hold:get() or 3

            -- Pick one side when entering the pre-protect window, then keep it.
            -- This prevents pre-protect from flipping every tick while you are peeking.
            if not aa_overlap_state.prepared_onshot or tick > (aa_overlap_state.prelock_until or 0) then
                aa_overlap_pick_onshot_side()
            end

            aa_overlap_state.prepared_onshot = true
            aa_overlap_state.prelock_until = tick + pre_hold

            aa_overlap_request("pre_onshot", aa_overlap_state.onshot_side, antiaim.overlap.onshot_limit:get(), pre_hold)
        end

        local function aa_overlap_trigger_onshot(tick)
            -- Multiple detectors can fire for the same shot. Do not flip twice on the same tick.
            if aa_overlap_state.last_trigger_tick == tick then
                return
            end

            aa_overlap_state.last_trigger_tick = tick
            aa_overlap_state.last_shot_tick = tick

            -- If pre-protect already chose a side, keep that same side for the shot.
            -- If not prepared, pick a side now.
            if not aa_overlap_state.prepared_onshot or tick > ((aa_overlap_state.prelock_until or 0) + 1) then
                aa_overlap_pick_onshot_side()
            end

            aa_overlap_state.prepared_onshot = false
            aa_overlap_request("onshot", aa_overlap_state.onshot_side, antiaim.overlap.onshot_limit:get(), antiaim.overlap.onshot_hold:get())
        end

        -- More reliable for ragebot/DT shots than only checking cmd.in_attack.
        -- aim_fire fires when the cheat actually takes a shot, while setup_command input
        -- can be swallowed/changed by DT or defensive logic.
        function antiaim.aa_overlap_aim_fire(e)
            if antiaim.overlap == nil then return end
            if not antiaim.overlap.enabled:get() then return end
            if not antiaim.overlap.onshot:get() then return end

            aa_overlap_trigger_onshot(globals.tickcount())
        end

        local function aa_overlap_enemy_visible(lp)
            local tick = globals.tickcount()
            if aa_overlap_state.visible_tick == tick then
                return aa_overlap_state.visible_cache
            end

            aa_overlap_state.visible_tick = tick
            aa_overlap_state.visible_cache = false

            if lp == nil then
                return false
            end

            local ex, ey, ez = utils.get_eye_position(lp)
            if ex == nil then
                return false
            end

            local enemies = entity.get_players(true)
            if enemies == nil then
                return false
            end

            for i = 1, #enemies do
                local enemy = enemies[i]
                if entity.is_alive(enemy) and not entity.is_dormant(enemy) then
                    local tx, ty, tz = utils.get_eye_position(enemy)
                    if tx ~= nil then
                        local fraction, ent = client.trace_line(lp, ex, ey, ez, tx, ty, tz)
                        if ent == enemy or (fraction ~= nil and fraction > 0.97) then
                            aa_overlap_state.visible_cache = true
                            return true
                        end
                    end
                end
            end

            return false
        end

        local function aa_overlap_request_pre_onshot(cmd)
            if not antiaim.overlap.onshot:get() or not antiaim.overlap.pre_onshot:get() then
                aa_overlap_state.prepared_onshot = false
                return
            end

            local lp = entity.get_local_player()
            if lp == nil or not entity.is_alive(lp) then
                aa_overlap_state.prepared_onshot = false
                return
            end

            local tick = globals.tickcount()
            local attack = cmd and (cmd.in_attack == true or cmd.in_attack == 1)

            -- Direct attack input is the earliest warning, so prepare before m_fLastShotTime updates.
            if attack then
                aa_overlap_prepare_onshot(tick)
                return
            end

            local vx, vy = entity.get_prop(lp, "m_vecVelocity")
            local speed = (vx ~= nil and vy ~= nil) and math.sqrt(vx * vx + vy * vy) or 0

            local exploit_ready = software.is_double_tap() or software.is_on_shot_antiaim()
            local peeking = software.is_quick_peek_assist()
                or (cmd and cmd.force_defensive)
                or ((globals.chokedcommands() or 0) > 0)
                or speed > 10

            -- Anti-onshot needs to happen before the shot, so when DT/OSAA is active and
            -- you are peeking a visible enemy, reserve the onshot side before aim_fire.
            if exploit_ready and peeking and aa_overlap_enemy_visible(lp) then
                aa_overlap_prepare_onshot(tick)
            end
        end

        local function aa_overlap_request_onshot(cmd)
            if not antiaim.overlap.onshot:get() then
                aa_overlap_state.attack_down = false
                return
            end

            local lp = entity.get_local_player()
            if lp == nil or not entity.is_alive(lp) then
                aa_overlap_state.attack_down = false
                return
            end

            local tick = globals.tickcount()
            local curtime = globals.curtime()

            -- setup_command sees the shot input before m_fLastShotTime updates.
            -- This makes on-shot AA win while DT/defensive is already active.
            local attack = cmd and (cmd.in_attack == true or cmd.in_attack == 1)
            if attack and not aa_overlap_state.attack_down then
                aa_overlap_trigger_onshot(tick)
            end
            aa_overlap_state.attack_down = attack and true or false

            -- Backup detection for held attack / DT shots, where in_attack may stay held.
            local weapon = entity.get_player_weapon(lp)
            if weapon ~= nil then
                local last_shot = entity.get_prop(weapon, "m_fLastShotTime")
                if last_shot ~= nil and last_shot > 0 and last_shot ~= aa_overlap_state.last_shot_time then
                    aa_overlap_state.last_shot_time = last_shot

                    if curtime - last_shot <= 0.25 then
                        aa_overlap_trigger_onshot(tick)
                    end
                end
            end

            local hold = antiaim.overlap.onshot_hold:get()
            local ticks_since = tick - (aa_overlap_state.last_shot_tick or 0)

            if ticks_since >= 0 and ticks_since <= hold then
                aa_overlap_request("onshot", aa_overlap_state.onshot_side, antiaim.overlap.onshot_limit:get(), hold)
            end
        end

        local function aa_overlap_request_manual()
            local manual = manual_direction.get()
            if manual == nil then
                return
            end

            -- manual_direction: 0 = left, 1 = right, 2 = forward.
            if manual == 0 then
                aa_overlap_request("manual", -1, antiaim.overlap.onshot_limit:get(), 4)
            elseif manual == 1 then
                aa_overlap_request("manual", 1, antiaim.overlap.onshot_limit:get(), 4)
            end
        end

        local function aa_overlap_request_fakeduck()
            if not antiaim.overlap.protect_fd:get() then
                return
            end

            if not software.is_duck_peek_assist() then
                return
            end

            local side = aa_overlap_state.side ~= 0 and aa_overlap_state.side or aa_overlap_state.onshot_side or 1
            aa_overlap_request("fakeduck", side, antiaim.overlap.fd_limit:get(), 3)
        end

        local function aa_overlap_request_fakelag()
            if not antiaim.overlap.fakelag:get() then
                return
            end

            local states = statement.get()
            local in_state_fakelag = states and contains(states, "Fake Lag")
            local choking = (globals.chokedcommands() or 0) > 0 or localplayer.choking_bool
            local exploit_active = software.is_double_tap() or software.is_on_shot_antiaim()

            -- Do not rely only on Guardian's "Fake Lag" state. With DT/OSAA/defensive,
            -- the state often stays Standing/Moving while commands are still being shifted/choked.
            if not in_state_fakelag and not choking and not exploit_active then
                return
            end

            local side = aa_overlap_state.side ~= 0 and aa_overlap_state.side or aa_overlap_state.onshot_side or 1
            aa_overlap_request("fakelag", side, antiaim.overlap.fakelag_limit:get(), 2)
        end

        local function aa_overlap_request_defensive(cmd)
            if cmd and cmd.force_defensive then
                local side = aa_overlap_state.side ~= 0 and aa_overlap_state.side or aa_overlap_state.onshot_side or 1
                -- Defensive is a fallback lock, so use the fakelag/fallback slider.
                -- On-shot still overrides this because onshot has higher priority.
                aa_overlap_request("defensive", side, antiaim.overlap.fakelag_limit:get(), 3)
            end
        end

        local function aa_overlap_build_body_offset(ctx, side, limit)
            side = side or 1

            -- UI slider is "desync strength" style: 0-60.
            -- Guardian applies through Body yaw offset, whose native value is -180 to 180.
            -- So 0-60 strength maps to 0-180 body-yaw offset.
            local desync_strength = utils.clamp(limit or 0, 0, 60)
            local body_offset = utils.clamp(desync_strength * 3, 0, 180)
            local real = utils.normalize_yaw(ctx.yaw_offset or 0)
            local applied
            local min_gap = antiaim.overlap.min_real_fake_gap:get() or 35
            local forced_gap = false

            if antiaim.overlap.avoid_real_fake:get() then
                -- Real/fake anti-overlap mode:
                -- keep the fake/body offset at least min_gap away from real yaw.
                -- body_yaw_offset is relative to real yaw (engine adds it), so do NOT add real here.
                local desired_gap = utils.clamp(math.max(body_offset, min_gap), 0, 180)
                forced_gap = body_offset < min_gap
                applied = utils.normalize_yaw(side * desired_gap)
            else
                -- Normal mode: apply the mapped body-yaw offset directly.
                applied = utils.normalize_yaw(side * body_offset)
            end

            local final_gap = math.abs(applied)

            aa_overlap_state.debug_real = real
            aa_overlap_state.debug_fake = applied
            aa_overlap_state.debug_gap = final_gap
            aa_overlap_state.debug_min_gap = min_gap
            aa_overlap_state.debug_forced_gap = forced_gap
            aa_overlap_state.debug_desync_strength = desync_strength

            return applied
        end

        local function aa_overlap_apply(ctx)
            local tick = globals.tickcount()

            if tick > (aa_overlap_state.lock_until or 0) then
                aa_overlap_state.side = 0
                aa_overlap_state.limit = 0
                aa_overlap_state.source = "none"
                aa_overlap_state.priority = 0
                return
            end

            local side = aa_overlap_state.side or 0
            local limit = aa_overlap_state.limit or 0
            if side == 0 or limit <= 0 then
                return
            end

            -- Apply through Guardian's ctx. The existing setup() will push it to native AA refs safely.
            ctx.body_yaw = "Static"
            ctx.body_yaw_offset = aa_overlap_build_body_offset(ctx, side, limit)
            ctx.freestanding_body_yaw = false
            aa_overlap_state.applied_offset = ctx.body_yaw_offset

            if antiaim.overlap.disable_jitter:get() then
                ctx.yaw_jitter = "Off"
                ctx.jitter_offset = 0
            end
        end

        local function aa_overlap_debug()
            if not antiaim.overlap.debug:get() then
                return
            end

            if aa_overlap_state.source ~= "none" then
                renderer.indicator(150, 200, 255, 255,
                    "AA LOCK: " .. tostring(aa_overlap_state.source)
                    .. " | raw " .. tostring(aa_overlap_state.limit or 0)
                    .. " | set " .. tostring(aa_overlap_state.applied_offset or ((aa_overlap_state.side or 0) * (aa_overlap_state.limit or 0)))
                    .. " | gap " .. tostring(utils.round(aa_overlap_state.debug_gap or 0))
                    .. "/" .. tostring(aa_overlap_state.debug_min_gap or 0)
                    .. (aa_overlap_state.debug_forced_gap and " FIX" or "")
                    .. " | choke " .. tostring(globals.chokedcommands() or 0))
            end
        end

        local function aa_overlap_update_onshot(cmd, ctx)
            if not antiaim.overlap.enabled:get() or not antiaim.overlap.onshot:get() then
                aa_overlap_state.side = 0
                aa_overlap_state.limit = 0
                aa_overlap_state.source = "none"
                aa_overlap_state.priority = 0
                aa_overlap_state.lock_until = 0
                aa_overlap_state.prepared_onshot = false
                aa_overlap_state.attack_down = false
                return
            end

            aa_overlap_request_onshot(cmd)
            aa_overlap_apply(ctx)
        end


        local acidyaw_ways = {
            ["2-Way"] = { -0.5, 0.5 },
            ["3-Way"] = { -0.5, 0, 0.5 },
            ["5-Way"] = { -0.75, 1, 0, 0.4, -0.25 }
        }

        local function calculate_jitter_way(n, offset)
            local fmod = localplayer.packets % n
            local center = n / 2

            if n % 2 ~= 0 then
                center = math.floor(center)
            elseif fmod >= center then
                fmod = fmod + 1
            end

            local delta = fmod - center
            local weight = delta / center

            if weight ~= weight or weight == 0 then
                return 0
            end

            return offset * weight
        end

        local function get_statement()
            if not exploit.get().shift and not (software.is_double_tap() or software.is_on_shot_antiaim()) then
                return 'Fake Lag'
            end

            if localplayer.is_airborne then
                return localplayer.is_crouched and "Air Crouched" or 'Air'
            end

            if localplayer.is_crouched then
                return localplayer.is_moving and "Move Crouched" or 'Crouched'
            end

            if localplayer.is_moving then
                return software.is_slow_motion() and 'Slow Walk' or "Moving"
            end

            return 'Standing'
        end

        local function modify_yaw()
            if ctx.yaw == "180 LR" then
                ctx.yaw = "180"

                if ctx.yaw_left == nil then return end
                if ctx.yaw_right == nil then return end

                if ctx.yaw_offset == nil then
                    ctx.yaw_offset = 0
                end

                local inverted = localplayer.body_yaw < 0

                if ctx.yaw_180lr_mode == "Switch delay" then
                    local delay = ctx.yaw_delay
                    local target = delay * 2

                    inverted = (localplayer.packets % target) >= delay

                    ctx.body_yaw = "Static"
                    ctx.body_yaw_offset = inverted and
                        1 or -1
                end

                local yaw_add = inverted and
                    ctx.yaw_right or ctx.yaw_left

                ctx.yaw_offset = ctx.yaw_offset + yaw_add
                return
            end
        end

        local safe_head_presets = {
            [1] = {
                [3] = {
                    -- base = "At Target" !!!
                    offset = 15,

                    inverter = false,

                    left_limit = 24,
                    right_limit = 24
                },

                [2] = {
                    offset = 15,

                    inverter = false,

                    left_limit = 24,
                    right_limit = 24
                }
            },
        }

        local randomized
        local val = 180
        local function modify_jitter()
            if ctx.jitter_randomization ~= nil then
                if localplayer.packets % 2 == 0 or randomized == nil then
                    randomized = client.random_int(0, (ctx.jitter_offset > 0 and 1 or -1) * ctx.jitter_randomization)
                end

                ctx.jitter_offset = utils.normalize_yaw(ctx.jitter_offset + randomized)
            end

            if ctx.body_yaw == 'Randomize Jitter' then
                ctx.body_yaw = 'Static'

                if localplayer.choking_bool then
                    local rand = client.random_int(0, 1)
                    val = rand == 1 and 180 or -180
                end

                ctx.body_yaw_offset = val
            end

            if ctx.yaw_jitter == "Guardian" then
                local yaw = ctx.yaw_offset
                local state = get_statement()
                local delay_data = delay_data_all[state]

                delay_data.ticks = delay_data.ticks + 1

                local acid_mode  = ctx.jitter_mode
                local acid_cycle = ctx.acid_cycle
                local acid_delay = ctx.acid_delay

                local ways = acidyaw_ways[acid_mode]
                local way = ways[(localplayer.packets % #ways) + 1]

                -- god ( qhose ) forgive me for the piece of code below
                --- region lulz diagnostics disable@

                local byaw = localplayer.body_yaw

                if acid_cycle ~= 4 and not delay_data.is_delay and delay_data.ticks % acid_cycle == 0 then
                    delay_data.is_delay = true
                end

                local ignore_yaw = false
                if delay_data.is_delay then
                    if delay_data.current < acid_delay then
                        delay_data.current = delay_data.current + 1

                        if ctx.acid_safe then
                            local lp = entity.get_local_player()
                            local current_preset = safe_head_presets[1]
                            local preset_for_team = current_preset[entity.get_prop(lp, 'm_iTeamNum')]

                            yaw = 0 --preset_for_team.offset
                            ctx.body_yaw = 'Static'
                            ctx.body_yaw_offset = 0

                            ignore_yaw = true
                        end

                       yaw = yaw
                    else
                        delay_data.is_delay = false
                        delay_data.ticks = 0
                        delay_data.current = 0
                        delay_data.previous_angle = 0
                    end
                else
                    local angle = 0
                    if acid_mode == "2-Way" and (ctx.body_yaw == "Jitter" or ctx.body_yaw == 'Randomize Jitter') then
                        angle = utils.normalize_yaw(yaw + (byaw < 0 and ctx.jitter_offset / 2 or ctx.jitter_offset * -1 / 2))
                    else
                        angle = utils.normalize_yaw(yaw + ctx.jitter_offset * way)
                    end


                    delay_data.previous_angle = angle
                end

                if not ignore_yaw then
                    yaw = delay_data.previous_angle
                end

                ctx.yaw_offset = yaw
                ctx.yaw_jitter = 'Off'
            end

        end

        local function shutdown()
            override.unset(software.aa.angles.enabled)
            override.unset(software.aa.angles.pitch[1])
            override.unset(software.aa.angles.pitch[2])

            override.unset(software.aa.angles.yaw_base)

            override.unset(software.aa.angles.yaw[1])
            override.unset(software.aa.angles.yaw[2])

            override.unset(software.aa.angles.yaw_jitter[1])
            override.unset(software.aa.angles.yaw_jitter[2])

            override.unset(software.aa.angles.body_yaw[1])
            override.unset(software.aa.angles.body_yaw[2])

            override.unset(software.aa.angles.freestanding_body_yaw)

            override.unset(software.aa.angles.edge_yaw)

            override.unset(software.aa.angles.freestanding[1])
            override.unset(software.aa.angles.freestanding[2])

            override.unset(software.aa.angles.roll)
        end

        local function setup()
            yaw_direction.is_freestanding = false
            if ctx.enabled ~= nil then
                override.set(software.aa.angles.enabled, ctx.enabled)
            else
                override.set(software.aa.angles.enabled, true)
            end

            if ctx.pitch ~= nil then
                override.set(software.aa.angles.pitch[1], ctx.pitch)
            end

            if ctx.yaw_base ~= nil then
                override.set(software.aa.angles.yaw_base, ctx.yaw_base)
            end

            if ctx.yaw ~= nil then
                override.set(software.aa.angles.yaw[1], ctx.yaw)
            end

            if ctx.body_yaw ~= nil then
                override.set(software.aa.angles.body_yaw[1], ctx.body_yaw)
            end

            if ctx.edge_yaw ~= nil then
                override.set(software.aa.angles.edge_yaw, ctx.edge_yaw)
            end

            if ctx.freestanding ~= nil then
                yaw_direction.is_freestanding = ctx.freestanding
                override.set(software.aa.angles.freestanding[1], ctx.freestanding)
                override.set(software.aa.angles.freestanding[2], ctx.freestanding and
                    "Always on" or "On hotkey")
            end

            if ctx.roll ~= nil then
                override.set(software.aa.angles.roll, ctx.roll)
            end

            local pitch_value = ui.get(software.aa.angles.pitch[1])
            local yaw_value = ui.get(software.aa.angles.yaw[1])
            local body_yaw_value = ui.get(software.aa.angles.body_yaw[1])

            if pitch_value == "Custom" then
                if ctx.pitch_offset ~= nil then
                    override.set(software.aa.angles.pitch[2], utils.clamp(ctx.pitch_offset, -89, 89))
                end
            end

            if yaw_value ~= "Off" then
                if ctx.yaw_offset ~= nil then
                    override.set(software.aa.angles.yaw[2], utils.normalize_yaw(ctx.yaw_offset))
                end

                if ctx.yaw_jitter ~= nil then
                    override.set(software.aa.angles.yaw_jitter[1], ctx.yaw_jitter)
                end

                local yaw_jitter_val = ui.get(software.aa.angles.yaw_jitter[1])

                if yaw_jitter_val ~= "Off" then
                    if ctx.jitter_offset ~= nil then
                        override.set(software.aa.angles.yaw_jitter[2], utils.normalize_yaw(ctx.jitter_offset))
                    end
                end
            end

            if body_yaw_value ~= "Off" then
                if body_yaw_value ~= "Opposite" then
                    if ctx.body_yaw_offset ~= nil then
                        override.set(software.aa.angles.body_yaw[2], utils.normalize_yaw(ctx.body_yaw_offset))
                    end
                end

                if ctx.freestanding_body_yaw ~= nil then
                    override.set(software.aa.angles.freestanding_body_yaw, ctx.freestanding_body_yaw)
                end
            end
        end

        local function think(e)
            -- break_lc.think(e)
        end

        local function update(e)
            angles.update(ctx)
            yaw_direction.update(ctx)
            auto_peek.perform(ctx)
            manual_direction.update(ctx)

            safe_head.update(e, ctx)
            defensive.handle(e, ctx)
            air_exploit.handle(ctx, e)
            avoid_backstab.update(ctx)
            disablers.update(e, ctx)
            fs_disablers.update(ctx)
        end

        function antiaim.shutdown()
            shutdown()
        end

        function antiaim.setup_command(e)
            if not gui.enabled:get() then
                return
            end

            table.clear(ctx)
            shutdown()

            think(e)
            update(e)

            modify_yaw()
            modify_jitter()

            aa_overlap_update_onshot(e, ctx)

            setup()
        end

        function antiaim.frame()
            if gui.enabled:get() and antiaim.overlap.enabled:get() then
                aa_overlap_debug()
            end
        end

        gui.enabled:set_callback(function(item)
            if not ui.get(item) then
                shutdown()
            end
        end)
    end

    ---region settings tweaks
    do
        settings.tweaks_enable = menu.new_item(ui.new_checkbox, "AA", "Anti-aimbot angles", "Features")
        : record("settings", "settings::tweaks_enable")
        : save()

        settings.tweaks = menu.new_item(ui.new_multiselect, 'AA', 'Anti-aimbot angles', merge { "- Functions", "\n", "settings::tweaks" }, { 'Log Aimbot Shots', 'Trashtalk', 'Unmute Silenced Players', 'Console Filter', 'Damage Marker' })
        : record("settings", "settings::tweaks")
        : save()
    end

    --- region widgets
    do
        widgets.enabled = menu.new_item(ui.new_checkbox, "AA", "Anti-aimbot angles", "Widgets")
        : record("visuals", "widgets::enabled")
        : save()

        widgets.color_picker = menu.new_item(ui.new_color_picker, "AA", "Anti-aimbot angles", merge { "- Color", "\n", "widgets::color_picker" }, 113, 152, 255, 255)
        : record("visuals", "keybinds::color_picker")
        : save()

        widgets.items = menu.new_item(ui.new_multiselect, "AA", "Anti-aimbot angles", merge { "- Items", "\n", "widgets::items" }, { "Watermark", "Keybinds", "Velocity Warning", "Crosshair Indicator", "Damage Indicator", "On-Screen Logs", 'Hit Rate' })
        : record("visuals", "widgets::items")
        : save()

        widgets.display = menu.new_item(ui.new_multiselect, "AA", "Anti-aimbot angles", merge { "- Display", "\n", "widgets::display" }, { "Username", "Latency", "Time", "FPS", "Server frametime" })
        : record("visuals", "widgets::display")
        : save()

        widgets.custom_name = menu.new_item(ui.new_checkbox, "AA", "Anti-aimbot angles", "Custom Name", { "Username", "Latency", "Time", "FPS", "Server frametime" })
        : record("visuals", "widgets::custom_name")
        : save()

        widgets.custom_name_value = menu.new_item(ui.new_textbox, "AA", "Anti-aimbot angles", "Nickname")
        : record("visuals", "widgets::custom_name_value")
        : save()
    end

    --- region fast ladder
    do
        aa_tweaks.enable = menu.new_item(ui.new_checkbox, "AA", "Anti-aimbot angles", "Tweaks")
        : record("settings", "aa_tweaks::enable")
        : save()

        aa_tweaks.items = menu.new_item(ui.new_multiselect, "AA", "Anti-aimbot angles", "- Options", { 'Disable on Warmup', 'Disable While No Enemies', 'Avoid Backstab', 'Fast Ladder', 'Edge Yaw on FD', 'Hide Shots on Crouch', "Auto Peek Improvements" })
        : record("aa", "aa_tweaks::items")
        : save()

        client.set_event_callback('setup_command', function (cmd)
            if not aa_tweaks.enable:get() then
                return
            end

            if not aa_tweaks.items:have_key('Fast Ladder') then
                return
            end

            local lp = entity.get_local_player()
            if lp == nil then
                return
            end

            if entity.get_prop(lp, 'm_MoveType') ~= 9 then
                return
            end

            local weapon = entity.get_player_weapon(lp)
            if weapon == nil then
                return
            end

            local throw_time = entity.get_prop(weapon, 'm_fThrowTime')

            if throw_time ~= nil and throw_time ~= 0 then
                return
            end

            if cmd.forwardmove > 0 then
                if cmd.pitch < 45 then
                    cmd.pitch = 89
                    cmd.in_moveright = 1
                    cmd.in_moveleft = 0
                    cmd.in_forward = 0
                    cmd.in_back = 1

                    if cmd.sidemove == 0 then
                        cmd.yaw = cmd.yaw + 90
                    end

                    if cmd.sidemove < 0 then
                        cmd.yaw = cmd.yaw + 150
                    end

                    if cmd.sidemove > 0 then
                        cmd.yaw = cmd.yaw + 30
                    end
                end
            elseif cmd.forwardmove < 0 then
                cmd.pitch = 89
                cmd.in_moveleft = 1
                cmd.in_moveright = 0
                cmd.in_forward = 1
                cmd.in_back = 0

                if cmd.sidemove == 0 then
                    cmd.yaw = cmd.yaw + 90
                end

                if cmd.sidemove > 0 then
                    cmd.yaw = cmd.yaw + 150
                end

                if cmd.sidemove < 0 then
                    cmd.yaw = cmd.yaw + 30
                end
            end
        end)

        client.set_event_callback('setup_command', function (cmd)
            if not aa_tweaks.enable:get() or not aa_tweaks.items:have_key('Hide Shots on Crouch') then
                override.unset(software.aa.other.on_shot_antiaim[1])
                override.unset(software.aa.other.on_shot_antiaim[2])
                override.unset(software.rage.aimbot.double_tap[1])
                return
            end

            local lp = entity.get_local_player()
            if lp == nil or not entity.is_alive(lp) then
                override.unset(software.aa.other.on_shot_antiaim[1])
                override.unset(software.aa.other.on_shot_antiaim[2])
                override.unset(software.rage.aimbot.double_tap[1])
                return
            end

            local duck_amount = entity.get_prop(lp, 'm_flDuckAmount') or 0
            local flags = entity.get_prop(lp, 'm_fFlags') or 0
            local is_on_ground = bit.band(flags, 1) == 1
            local is_crouching = is_on_ground and (duck_amount > 0.65 or cmd.in_duck == 1)

            if is_crouching then
                -- Ground-only crouch should prefer Hide Shots, so temporarily disable Double Tap.
                -- The override system restores your previous DT value when you stand up or leave ground.
                override.set(software.rage.aimbot.double_tap[1], false)
                override.set(software.aa.other.on_shot_antiaim[1], true)
                override.set(software.aa.other.on_shot_antiaim[2], 'Always on')
            else
                override.unset(software.aa.other.on_shot_antiaim[1])
                override.unset(software.aa.other.on_shot_antiaim[2])
                override.unset(software.rage.aimbot.double_tap[1])
            end
        end)
    end

    --- region idiot
    do
        air_exploit.enabled = menu.new_item(ui.new_checkbox, "AA", "Anti-aimbot angles", "Air Lag Exploit", 1, 30, 18, true, 't')
        : record("aa", "air_exploit::enabled")
        : save()

        air_exploit.key = menu.new_item(ui.new_hotkey, "AA", "Anti-aimbot angles", "\nAir Lag Exploit", true)
        : record("aa", "air_exploit::key")
        : save()

        air_exploit.ticks = menu.new_item(ui.new_slider, "AA", "Anti-aimbot angles", "- Ticks", 1, 30, 10, true, 't')
        : record("aa", "air_exploit::ticks")
        : save()


        air_exploit.reset = false

        local weapons = { "Global", "G3SG1 / SCAR-20", "SSG 08", "AWP", "R8 Revolver", "Desert Eagle", "Pistol", "Zeus", "Rifle", "Shotgun", "SMG", "Machine gun" }

        function air_exploit.backups()
            if air_exploit.reset then
                local prev = ui.get(software.rage.weapon.weapon_type)

                for _, weapon in next, weapons do
                    ui.set(software.rage.weapon.weapon_type, weapon)
                    ui.set(software.rage.aimbot.enabled[1], true)
                end

                ui.set(software.rage.weapon.weapon_type, prev)

                override.unset(software.rage.other.duck_peek_assist)
                override.unset(software.aa.fakelag.limit)
                override.unset(software.misc.settings.sv_maxusrcmdprocessticks)
                air_exploit.reset = false
            end
        end

        function air_exploit.handle(ctx, cmd)
            if not air_exploit.enabled:get() then
                return air_exploit.backups()
            end

            local is_active = air_exploit.key:rawget()
            if not is_active then
                return air_exploit.backups()
            end

            if not software.is_double_tap() then
                return air_exploit.backups()
            end

            if not localplayer.is_airborne then
                return air_exploit.backups()
            end

            local exploit = exploit.get()

            override.set(software.misc.settings.sv_maxusrcmdprocessticks, 19)
            override.set(software.aa.fakelag.limit, 17)

            if exploit.shift then
                ui.set(software.rage.aimbot.enabled[1], true)
                cmd.discharge_pending = true
            else
                ui.set(software.rage.aimbot.enabled[1], false)
                override.set(software.rage.other.duck_peek_assist, globals.tickcount() % air_exploit.ticks:get() == 0 and 'Always on' or 'On hotkey')
            end

            air_exploit.reset = true
        end
    end

    --- region defensive
    do
        local function get_statement()
            if localplayer.is_airborne then
                return "Air";
            end

            if localplayer.is_crouched then
                return "Crouched";
            end

            if localplayer.is_moving then
                if software.is_slow_motion() then
                    return "Slow Walk";
                end

                return "Moving";
            end

            return "Standing"
        end

        defensive.enabled = menu.new_item(ui.new_checkbox, "AA", "Anti-aimbot angles", "Defensive AA")
        : record("aa", "defensive::enabled")
        : save()

        defensive.mode = menu.new_item(ui.new_multiselect, "AA", "Anti-aimbot angles", merge { "- Mode", "\n", "defensive::mode" }, { "On Shot Anti Aim", "Double Tap" })
        : record("aa", "defensive::mode")
        : save()

        defensive.state = menu.new_item(ui.new_multiselect, "AA", "Anti-aimbot angles", merge { "- State", "\n", "defensive::state" }, { "Air", "Standing", "Moving", "Slow Walk", "Crouched", "On Peek" })
        : record("aa", "defensive::state")
        : save()

        defensive.pitch = menu.new_item(ui.new_combobox, "AA", "Anti-aimbot angles", merge { "- Pitch", "\n", "defensive::pitch" }, { "Default", "Zero", "Up", "Up Switch", "Down Switch", "Random" })
        : record("aa", "defensive::pitch")
        : save()

        defensive.yaw = menu.new_item(ui.new_combobox, "AA", "Anti-aimbot angles", merge { "- Yaw", "\n", "defensive::yaw" }, { "Default", "Sideways", "Forward", "Spinbot", "3-Way", "5-Way", "Random" })
        : record("aa", "defensive::pitch")
        : save()

        local modes = {
            ['Double Tap'] = software.is_double_tap,
            ['On Shot Anti Aim'] = software.is_on_shot_antiaim
        }

        local manual_bebra = {
            [0] = 90,
            [1] = -90,
            [2] = 0
        }

        local defensive_3_way = { 90, 180, -90, 180, 90 }
        local defensive_5_way = { 90, 135, 180, 225, 270 }

        function defensive.handle(cmd, ctx)
            if not defensive.enabled:get() then
                return
            end

            local lp = entity.get_local_player()
            if lp == nil then
                return
            end

            local work_on_mode = false
            for idx, mode in next, defensive.mode:get() do
                if modes[ mode ] and modes[ mode ]() then
                    work_on_mode = true
                    break
                end
            end

            local double_tap = exploit.get()
            if not work_on_mode or not double_tap.shift then
                return
            end

            local lp_state = get_statement()

            local should_work = false
            local on_peek = false
            for _, condition in next, defensive.state:get() do
                if condition == 'On Peek' then
                    should_work = true
                    on_peek = true
                    break
                else
                    if condition == lp_state then
                        should_work = true
                        break
                    end
                end
            end

            if not should_work then
                return
            end

            local weapon = entity.get_player_weapon(lp)
            if weapon == nil then
                return
            end

            local wpn_info = csgo_weapons(weapon)
            if wpn_info == nil then
                return
            end

            if wpn_info.is_revolver then
                return
            end

            if not on_peek then
                cmd.force_defensive = true
            end

            local freestanding = yaw_direction.is_freestanding
            local manual_yaw = manual_direction.get()
            local should_flick = lp_state == 'Crouched' and manual_direction.options:have_key('Duck Exploit')
            local should_ignore = freestanding or (manual_yaw ~= nil and not should_flick)

            if should_flick then
                ctx.body_yaw = 'Static'
                ctx.body_yaw_offset = 180
            end

            local pitch_value, pitch_mode = 0, 'Default'
            do
                local val = defensive.pitch:get()
                if val == 'Zero' then
                    pitch_value, pitch_mode = 0, 'Custom'
                elseif val == 'Up' then
                    pitch_value, pitch_mode = 0, 'Up'
                elseif val == 'Up Switch' then
                    pitch_value, pitch_mode = client.random_float(45, 60) * -1, 'Custom'
                elseif val == 'Down Switch' then
                    pitch_value, pitch_mode = client.random_float(45, 60), 'Custom'
                elseif val == 'Random' then
                    pitch_value, pitch_mode = client.random_float(-89, 89), 'Custom'
                end

                if manual_yaw ~= nil and should_flick then
                    pitch_value, pitch_mode = client.random_float(-5, 10), 'Custom'
                end
            end

            local yaw_value, yaw_mode = 0, '180'
            do
                local val = defensive.yaw:get()
                if val == 'Sideways' then
                    yaw_value = localplayer.choking * 90 + client.random_float(-30, 30)
                elseif val == 'Forward' then
                    yaw_value = localplayer.choking * 180 + client.random_float(-30, 30)
                elseif val == 'Spinbot' then
                    yaw_value = -180 + (globals.tickcount() % 16) * 22.5 + client.random_float(-45, 45)
                elseif val == '3-Way' then
                    yaw_value = defensive_3_way[localplayer.packets % 5 + 1] + client.random_float(-15, 15)
                elseif val == '5-Way' then
                    yaw_value = defensive_5_way[localplayer.packets % 5 + 1] + client.random_float(-15, 15)
                elseif val == 'Random' then
                    yaw_value = utils.normalize(math.random(-180, 180), -180, 180)
                end

                if manual_yaw ~= nil and should_flick then
                    yaw_value = manual_bebra[ manual_yaw ] + client.random_float(0, 10)
                end
            end

            -- client.color_log(255, 255, 255, f('\nDefensive: %s\nShould Ignore: %s\nAvoid Backstab: %s\nForce Defensive: %s\nFreestanding: %s', globals.tickcount() > double_tap.defensive_tk - 2, should_ignore, avoid_backstab.get(), cmd.force_defensive, software.is_freestanding()))

            if globals.tickcount() > double_tap.defensive_tk - 2 then
                return
            end

            if avoid_backstab.get() or should_ignore then
                return
            end

            ctx.pitch = pitch_mode
            ctx.pitch_offset = pitch_value
            ctx.yaw = yaw_mode
            ctx.yaw_offset = yaw_value
        end
    end

    ---region disable on warmup
    do

        function disablers.count_alive()
            local alive = 0

            for i = 1, globals.maxplayers() do
                if entity.get_classname(i) ~= 'CCSPlayer' then
                    goto skip
                end

                if not entity.is_alive(i) or not entity.is_enemy(i) then
                    goto skip
                end

                alive = alive + 1
                ::skip::
            end

            return alive
        end


        function disablers.update(cmd, ctx)
            local lp = entity.get_local_player()
            if lp == nil then
                return
            end

            if not aa_tweaks.enable:get() then
                return
            end

            local game_rules = entity.get_game_rules()
            if game_rules == nil then
                return
            end

            local should_disable = false

            if aa_tweaks.items:have_key('Disable on Warmup') and entity.get_prop(game_rules, 'm_bWarmupPeriod') == 1 then
                should_disable = true
            end

            local players = disablers.count_alive()

            if aa_tweaks.items:have_key('Disable While No Enemies') and players == 0 and cmd.in_use ~= 1 then
                should_disable = true
            end

            if not should_disable then
                return
            end

            ctx.enabled = false
        end
    end
    
    --- region avoid_backstab
    do
        local is_active = false
        local AVOID_BACKSTAB_MAX_DISTANCE_SQR = 220 * 220

        local function get_enemies_with_knife()
            local enemies = entity.get_players(true)
            if next(enemies) == nil then return { } end

            local list = { }

            for i = 1, #enemies do
                local enemy = enemies[i]
                local wpn = entity.get_player_weapon(enemy)

                if wpn == nil then
                    goto continue
                end

                local wpn_class = entity.get_classname(wpn)

                if wpn_class == "CKnife" then
                    list[#list + 1] = enemy
                end

                ::continue::
            end

            return list
        end

        local function get_closest_target(me)
            local targets = get_enemies_with_knife()
            if next(targets) == nil then return end

            local best_delta
            local best_target

            local my_origin = vector(entity.get_origin(me))
            local best_distance = AVOID_BACKSTAB_MAX_DISTANCE_SQR

            for i = 1, #targets do
                local target = targets[i]

                local origin = vector(entity.get_origin(target))
                local delta = origin - my_origin

                local distance = delta:lengthsqr()

                if distance < best_distance then
                    best_delta = delta
                    best_target = target

                    best_distance = distance
                end
            end

            return best_target, best_delta
        end

        function avoid_backstab.get()
            return is_active
        end

        function avoid_backstab.update(ctx)
            is_active = false
            if not aa_tweaks.enable:get() then
                return
            end

            if not aa_tweaks.items:have_key('Avoid Backstab') then
                return
            end

            local me = entity.get_local_player()
            local target, delta = get_closest_target(me)

            if target == nil then return end
            if delta == nil then return end

            local view = vector(client.camera_angles())
            local angle = vector(delta:angles())

            local yaw = angle.y - view.y + 180

            if ctx.yaw_offset == nil then
                ctx.yaw_offset = 0
            end

            ctx.yaw_base = "Local view"
            ctx.yaw_offset = ctx.yaw_offset + yaw

            ctx.edge_yaw = false
            ctx.freestanding = false
            is_active = true
        end
    end

    --- region safe_head
    do
        local is_active = false

        local presets = {
            ["Standing"] = {
                [2] = function(e, ctx, me)
                    ctx.yaw_offset = -6

                    ctx.body_yaw = "Static"
                    ctx.body_yaw_offset = 0
                end,

                [3] = function(e, ctx, me)
                    ctx.yaw_offset = 8

                    ctx.body_yaw = "Static"
                    ctx.body_yaw_offset = 0
                end
            },

            ["Crouched"] = {
                [2] = function(e, ctx, me)
                    ctx.yaw_offset = 0

                    ctx.body_yaw = "Static"
                    ctx.body_yaw_offset = 0
                end,

                [3] = function(e, ctx, me)
                    ctx.yaw_offset = 40

                    ctx.body_yaw = "Static"
                    ctx.body_yaw_offset = 180
                end
            },

            ["Crouched Air"] = {
                [2] = function(e, ctx, me)
                    ctx.yaw_offset = 0

                    ctx.body_yaw = "Static"
                    ctx.body_yaw_offset = -120
                end,

                [3] = function(e, ctx, me)
                    ctx.yaw_offset = 0

                    ctx.body_yaw = "Static"
                    ctx.body_yaw_offset = 120
                end
            },

            ["Air Knife"] = {
                [2] = function(e, ctx, me)
                    ctx.yaw_offset = 45

                    ctx.body_yaw = "Static"
                    ctx.body_yaw_offset = 180
                end,

                [3] = function(e, ctx, me)
                    ctx.yaw_offset = 35

                    ctx.body_yaw = "Static"
                    ctx.body_yaw_offset = 180
                end
            },

            ["Air Zeus"] = {
                [2] = function(e, ctx, me)
                    ctx.yaw_offset = 23

                    ctx.body_yaw = "Static"
                    ctx.body_yaw_offset = 0
                end,

                [3] = function(e, ctx, me)
                    ctx.yaw_offset = 10

                    ctx.body_yaw = "Static"
                    ctx.body_yaw_offset = 0
                end
            }
        }

        local sv_gravity = cvar.sv_gravity
        local function extrapolate_entity(ent, pos)
            local tick_interval = globals.tickinterval()

            local velocity = vector(entity.get_prop(ent, "m_vecVelocity"))
            local new_pos = pos:clone()

            local ticks = 25
            if #velocity < 32 then
                ticks = 40
            end

            new_pos.x = new_pos.x + velocity.x * tick_interval * ticks
            new_pos.y = new_pos.y + velocity.y * tick_interval * ticks

            if entity.get_prop(ent, "m_hGroundEntity") == nil then
                new_pos.z = new_pos.z + velocity.z * tick_interval * ticks - sv_gravity:get_float() * tick_interval
            end

            return new_pos
        end

        local function get_statement(me)
            if localplayer.is_airborne then
                local wpn = entity.get_player_weapon(me)
                if wpn == nil then return end

                local classname = entity.get_classname(wpn)

                if classname == "CKnife" then
                    return "Air Knife"
                end

                if classname == "CWeaponTaser" then
                    return "Air Zeus"
                end

                if localplayer.duck_amount == 1.0 then
                    return "Crouched Air"
                end

                return nil
            end

            if localplayer.is_crouched then
                return "Crouched"
            end

            if not localplayer.is_moving then
                return "Standing"
            end

            return nil
        end

        safe_head.enabled = menu.new_item(ui.new_checkbox, "AA", "Anti-aimbot angles", "Safe Head")
        : record("aa", "safe_head::enabled")
        : save()

        safe_head.states = menu.new_item(ui.new_multiselect, "AA", "Anti-aimbot angles", merge { "- States", "\n", "safe_head::states" }, { "Air Knife", "Air Zeus", "Standing", "Crouched", "Crouched Air" })
        : record("aa", "safe_head::states")
        : save()

        function safe_head.get()
            return is_active
        end

        function safe_head.update(e, ctx)
            is_active = false

            if not safe_head.enabled:get() then
                return
            end

            local me = entity.get_local_player()

            if manual_direction.get() then
                return
            end

            local team = entity.get_prop(me, "m_iTeamNum")
            if team == nil then
                return
            end

            local wpn = entity.get_player_weapon(me)
            if wpn == nil then
                return
            end

            local threat = client.current_threat()
            if threat == nil then
                return
            end

            local statement = get_statement(me)
            if statement == nil then
                return
            end

            if not safe_head.states:have_key(statement) then
                return
            end

            local should_continue = false
            if statement == "Air Zeus" or statement == "Air Knife" then
                should_continue = true
            else
                local eye_pos = extrapolate_entity(threat, vector(utils.get_eye_position(threat)))
                local head_pos = vector(entity.hitbox_position(me, 0))

                eye_pos.z = eye_pos.z + 5

                if head_pos.z > eye_pos.z then
                    local entindex, damage = client.trace_bullet(threat, eye_pos.x, eye_pos.y, eye_pos.z, head_pos.x, head_pos.y, head_pos.z + 6, threat)

                    should_continue = damage > 0
                end
            end

            if not should_continue then
                return
            end

            local preset = presets[statement]
            if preset == nil then
                return
            end

            local fn = preset[team]
            if fn == nil then
                return
            end

            ctx.pitch = "Default"
            ctx.yaw_base = "At targets"

            ctx.yaw = "180"
            ctx.yaw_offset = 22

            ctx.yaw_jitter = "Off"

            ctx.body_yaw = "Static"
            ctx.body_yaw_offset = 120

            ctx.freestanding_body_yaw = false

            fn(e, ctx, me)

            is_active = true
        end
    end

    --- region manual_yaw
    do
        local LEFT    = 0
        local RIGHT   = 1
        local FORWARD = 2

        local idx
        local data = { }

        local directions = {
            [LEFT]    = -90,
            [RIGHT]   = 90,
            [FORWARD] = 180
        }

        local function get_value(ref)
            local prev_active = data[ref]
            local active, mode, key = ui.get(ref)

            if prev_active == nil then
                data[ref] = active
                return
            end

            if mode == 0 then return end
            if mode == 3 then return end
            if key == nil then return end

            if prev_active ~= active then
                data[ref] = active
                return active, mode, key
            end
        end

        local function update_hotkey(ref, value)
            local active, mode = get_value(ref)
            if active == nil then return end

            if mode == 1 then
                if not active then
                    idx = nil
                    return
                end

                idx = value
                return
            end

            if mode == 2 then
                if idx == value then
                    idx = nil
                    return
                end

                idx = value
                return
            end
        end

        local function think()
            if get_value(manual_direction.disabled_manual.ref) ~= nil then
                idx = nil
                return
            end

            update_hotkey(manual_direction.left_manual.ref, LEFT)
            update_hotkey(manual_direction.right_manual.ref, RIGHT)
            update_hotkey(manual_direction.forward_manual.ref, FORWARD)
        end

        manual_direction.enabled = menu.new_item(ui.new_checkbox, "AA", "Anti-aimbot angles", "Manual Yaw")
        : record("aa", "manual_direction::enabled")

        manual_direction.arrows = menu.new_item(ui.new_checkbox, "AA", "Anti-aimbot angles", "Manual Arrows")
        : record("aa", "manual_direction::arrows")
        : save()

        manual_direction.color = menu.new_item(ui.new_color_picker, "AA", "Anti-aimbot angles", "Manual Color")
        : record("aa", "manual_direction::color")
        : save()

        manual_direction.options = menu.new_item(ui.new_multiselect, "AA", "Anti-aimbot angles", merge { "- Options", "\n", "manual_direction::options" }, {
            "Disable Yaw Modifiers",
            "Freestanding Body Yaw",
            'Duck Exploit'
        })
        : record("aa", "manual_direction::options")
        : save()

        manual_direction.left_manual = menu.new_item(ui.new_hotkey, "AA", "Anti-aimbot angles", merge { "- Left Manual", "\n", "manual_direction::left_manual" })
        : record("aa", "manual_direction::left_manual")

        manual_direction.right_manual = menu.new_item(ui.new_hotkey, "AA", "Anti-aimbot angles", merge { "- Right Manual", "\n", "manual_direction::right_manual" })
        : record("aa", "manual_direction::right_manual")

        manual_direction.forward_manual = menu.new_item(ui.new_hotkey, "AA", "Anti-aimbot angles", merge { "- Forward Manual", "\n", "manual_direction::forward_manual" })
        : record("aa", "manual_direction::forward_manual")

        manual_direction.disabled_manual = menu.new_item(ui.new_hotkey, "AA", "Anti-aimbot angles", merge { "- Disabled Manual", "\n", "manual_direction::disabled_manual" })
        : record("aa", "manual_direction::disabled_manual")

        manual_direction.left_manual:set("Toggle")
        manual_direction.right_manual:set("Toggle")
        manual_direction.forward_manual:set("Toggle")
        manual_direction.disabled_manual:set("Toggle")

        function manual_direction.get()
            return idx
        end

        function manual_direction.frame()
            think()
        end

        function manual_direction.update(ctx)
            if idx == nil then
                return false
            end

            if avoid_backstab.get() then
                return false
            end

            local offset = directions[idx]

            if offset == nil then
                return false
            end

            if ctx.yaw_offset == nil then
                ctx.yaw_offset = 0
            end

            ctx.yaw_base = "Local view"
            ctx.yaw_offset = offset

            if manual_direction.options:have_key("Disable Yaw Modifiers") then
                ctx.yaw_jitter = "Off"
                ctx.body_yaw = "Static"
            end

            if manual_direction.options:have_key("Freestanding Body Yaw") then
                ctx.body_yaw = "Static"
                ctx.body_yaw_offset = 120

                ctx.freestanding_body_yaw = true
            end

            ctx.edge_yaw = false
            ctx.freestanding = false

            return true
        end
    end

    --- region log_aimbot_shots
    do
        local DURATION = 7.0

        local inferno = { }
        local regular = { }

        local function draw_event_log(...)
            if not settings.tweaks_enable:get() then
                return
            end

            eventlogs.add(...)
        end

        local function push_event_log(data)
            if #regular > 8 then
                table.remove(regular, 1)
            end

            regular[#regular + 1] = data
        end

        local function weapon_to_action(weapon)
            if weapon == "knife" then
                return "Knifed"
            end

            if weapon == "hegrenade" then
                return "Naded"
            end

            return "Hit"
        end

        local function find_inferno_info(ent)
            for i = 1, #inferno do
                local data = inferno[i]

                if data.entity == ent then
                    return data
                end
            end

            return nil
        end

        local function get_miss_color(reason)
            if reason == "spread" then
                return eventlogs.spread_color_picker:rawget()
            end

            if reason == "death" or reason == "unregistered shot" then
                return eventlogs.unregistered_color_picker:rawget()
            end

            return eventlogs.miss_color_picker:rawget()
        end

        local function create_event_message(action, hitgroup, ent, damage)
            local name = entity.get_player_name(ent)
            local hitgroup_name = e_hitgroup[hitgroup]

            if action == "Hit" then
                return f(
                    "%s ${%s} in the ${%s} for ${%s} damage",
                    action, name, hitgroup_name, damage
                )
            end

            return f(
                "%s ${%s} for ${%s} damage",
                action, name, damage
            )
        end

        local function create_inferno_info(ent, damage)
            local data = { }

            data.entity = ent
            data.damage = damage

            data.alpha = 0.0
            data.duration = 7.0

            data.flash_amount = 1.0

            return data
        end

        local function create_event_info(action, hitgroup, ent, damage)
            local data = { }

            data.msg = create_event_message(action, hitgroup, ent, damage)

            data.alpha = 0.0
            data.duration = 7.0

            return data
        end

        local function create_miss_info(reason)
            if reason == "?" then
                reason = "correction"
            end

            local data = { }

            data.msg = f(
                "Missed shot due to ${%s}",
                reason
            )

            data.reason = reason

            data.alpha = 0.0
            data.duration = 7.0

            return data
        end

        local function update_inferno_logs(dt)
            local r, g, b = widgets.color_picker:rawget()

            for i = #inferno, 1, -1 do
                local data = inferno[i]

                data.duration = math.max(0, data.duration - dt)
                data.alpha = motion.interp(data.alpha, data.duration > 0, 0.045)

                if data.alpha <= 0 then
                    table.remove(inferno, i)
                end
            end

            for i = 1, #inferno do
                local data = inferno[i]

                local name = entity.get_player_name(data.entity)
                local damage = data.damage

                draw_event_log(r, g, b, 255 * data.alpha, f("Burned ${%s} for ${%d} damage", name, damage))
            end
        end

        local function update_regular_logs(dt)
            local r, g, b = widgets.color_picker:rawget()

            for i = #regular, 1, -1 do
                local data = regular[i]

                data.duration = math.max(0, data.duration - dt)
                data.alpha = motion.interp(data.alpha, data.duration > 0, 0.045)

                if data.alpha <= 0 then
                    table.remove(regular, i)
                end
            end

            for i = 1, #regular do
                local data = regular[i]

                local col_r = r
                local col_g = g
                local col_b = b

                if data.reason ~= nil then
                    col_r, col_g, col_b = get_miss_color(data.reason)
                end

                draw_event_log(col_r, col_g, col_b, 255 * data.alpha, data.msg)
            end
        end

        local function handle_input()
            if not settings.tweaks_enable:get() then
                return
            end

            if settings.tweaks:have_key('Log Aimbot Shots') then
                override.set(software.misc.settings.output, false)
            else
                override.unset(software.misc.settings.output)
            end
        end

        settings.tweaks:set_callback(handle_input)
        settings.tweaks_enable:set_callback(handle_input)
        ui.set_callback(software.misc.settings.output, handle_input)
        handle_input()

        function log_aimbot_shots.player_hurt(e)
            if not settings.tweaks_enable:get() then
                return
            end

            local me = entity.get_local_player()

            local userid = client.userid_to_entindex(e.userid)
            local attacker = client.userid_to_entindex(e.attacker)

            local weapon = e["weapon"]
            local damage = e["dmg_health"]

            local hitgroup = e["hitgroup"]

            if userid == me or attacker ~= me then
                return
            end

            if weapon == "inferno" then
                local data = find_inferno_info(userid)

                if data ~= nil then
                    data.damage = data.damage + damage
                    data.duration = DURATION

                    data.flash_amount = 1.0

                    return
                end

                inferno[#inferno + 1] = create_inferno_info(userid, damage)
                return
            end

            local action = weapon_to_action(weapon)
            push_event_log(create_event_info(action, hitgroup, userid, damage))
        end

        function log_aimbot_shots.aim_miss(e)
            if not settings.tweaks_enable:get() then
                return
            end

            push_event_log(create_miss_info(e.reason))
        end

        function log_aimbot_shots.frame()
            local dt = globals.frametime()

            update_inferno_logs(dt)
            update_regular_logs(dt)
        end
    end

    --- region eventlogs
    do
        local ALPHA_UNIT = 1 / 255

        local queue = { }
        local preview_alpha = 0.0

        local function replacement(s, col_a, col_b)
            local hex_a = utils.to_hex(unpack(col_a))
            local hex_b = utils.to_hex(unpack(col_b))

            local repl = f("\a%s%%1\a%s", hex_a, hex_b)
            local result = string.gsub(s, "${(.-)}", repl)

            return result
        end

        local function update_preview()
            local can_show_preview = widgets.enabled:get() and ui.is_menu_open() and #queue == 0
            preview_alpha = motion.interp(preview_alpha, can_show_preview, 0.045)

            if preview_alpha > 0.0 then
                local alpha = 255 * preview_alpha

                -- hit example
                do
                    local r, g, b = widgets.color_picker:rawget()

                    eventlogs.add(r, g, b, alpha, "Hit ${vladislav} for ${10} damage")
                    eventlogs.add(r, g, b, alpha, "Hit ${monster} in the ${head} for ${103} damage")
                end

                -- miss example
                do
                    local r, g, b = eventlogs.miss_color_picker:rawget()

                    eventlogs.add(r, g, b, alpha, "Missed shot due to ${correction}")
                    eventlogs.add(r, g, b, alpha, "Missed shot due to ${prediction error}")
                    eventlogs.add(r, g, b, alpha, "Missed shot due to ${lagcomp failure}")
                end

                -- spread example
                do
                    local r, g, b = eventlogs.spread_color_picker:rawget()

                    eventlogs.add(r, g, b, alpha, "Missed shot due to ${spread}")
                end

                -- network example
                do
                    local r, g, b = eventlogs.unregistered_color_picker:rawget()

                    eventlogs.add(r, g, b, alpha, "Missed shot due to ${unregistered shot}")
                    eventlogs.add(r, g, b, alpha, "Missed shot due to ${player death}")
                    eventlogs.add(r, g, b, alpha, "Missed shot due to ${death}")
                end
            end
        end

        local widget = windows.new("##Event Logs", .55, 0.78)
        widget:set_size(vector(330, 125))

        local hovered_alpha = 0

        local function draw_eventlogs()
            if not widgets.enabled:get() or not widgets.items:have_key("On-Screen Logs") then
                return
            end

            local screen = vector(client.screen_size())
            local flags = "d"

            local window = widget
            window.pos.x = screen.x * .5 - 165

            local pos = window.pos:clone()
            local size = window.size:clone()

            local position = vector(pos.x + size.x / 2, pos.y)

            hovered_alpha = motion.interp(hovered_alpha, ui.is_menu_open() and window:is_hovering(), 0.095)
            if hovered_alpha ~= 0 then
                renderer.text(pos.x + size.x * .5, pos.y - 10, 255, 255, 255, 255 * hovered_alpha, 'c', nil, 'You can drag widget vertically.')
                renderer.rectangle(pos.x + 50, pos.y - 2, size.x - 103, 1, 255, 255, 255, 100 * hovered_alpha)
            end

            for i = 1, #queue do
                local log = queue[i]

                local r, g, b, a = log.r, log.g, log.b, log.a
                local alpha = a * ALPHA_UNIT

                local text = log.msg do
                    text = replacement(text, { r, g, b, 255 }, { 255, 255, 255, 255 })
                end

                local text_size = vector(renderer.measure_text(flags, text))
                local rect_size = vector(text_size.x, text_size.y)

                local text_position = vector(position.x - text_size.x * 0.5, position.y)
                -- local rect_position = vector(position.x - rect_size.x * 0.5, position.y + text_size.y * 0.5)

                -- graphics.glow(rect_position.x, rect_position.y - 2, rect_size.x, 4, r, g, b, a * 0.1, 10, 1)
                -- renderer.rectangle(rect_position.x, rect_position.y - 2, rect_size.x, 4, r, g, b, a * 0.1)

                graphics.text(text_position.x, text_position.y, 255, 255, 255, 255 * alpha, flags, 0, text)

                position.y = position.y + (text_size.y + 1) * alpha
            end

            window:update()
        end

        local function get_color(self)
            return self.r, self.g, self.b
        end

        local wr, wg, wb = widgets.color_picker:rawget()

        eventlogs.hit_color_picker = {
            r = wr, g = wg, b = wb,

            rawget = get_color
        }

        eventlogs.spread_color_picker = {
            r = 255, g = 225, b = 115,

            rawget = get_color
        }

        eventlogs.miss_color_picker = {
            r = 255, g = 98, b = 98,

            rawget = get_color
        }

        eventlogs.unregistered_color_picker = {
            r = 100, g = 100, b = 255,

            rawget = get_color
        }

        function eventlogs.add(r, g, b, a, text)
            local log = { }

            log.r = r
            log.g = g
            log.b = b
            log.a = a

            log.msg = text

            table.insert(queue, log)
            return log
        end

        function eventlogs.pre_frame()
            table.clear(queue)
        end

        function eventlogs.post_frame()
            update_preview()
            draw_eventlogs()
        end
    end

    local print_dev do
        print_dev = {
            data = { }
        }

        function print_dev.add(text, time)
            print_dev.data[#print_dev.data+1] = {
                text = text,
                time = time + globals.realtime(),
                alpha = 0.01,
                offset = 0
            }
        end
    
        client.set_event_callback('paint', function ()
            local realtime = globals.realtime()
            local frametime = globals.frametime()
            local offset = 0
    
            for i = #print_dev.data, 1, -1 do
                local log = print_dev.data[i]
                if not log then
                    goto skip
                end
    
                if log.offset ~= offset then
                    log.offset = utils.clamp(log.offset < offset and log.offset + (200 * frametime) or offset, 0, offset)
                end
    
                local difference = log.time - realtime
                log.alpha = motion.interp(log.alpha, difference > 0, 0.045)
                if log.alpha <= 0 and difference < 0 then
                    table.remove(print_dev.data, i)
                    goto skip
                end
    
                local text_sz = vector(renderer.measure_text('d', log.text))
    
                graphics.text(8, 5 + log.offset, 255, 255, 255, 255 * log.alpha, 'd', nil, log.text)
    
                offset = offset + text_sz.y + 1
                ::skip::
            end
    
            for i = 1, #print_dev.data do
                local log_count = #print_dev.data - i
    
                if log_count > 7 then
                    print_dev.data[ i ].time = 0
                end
            end
        end)
    
        client.set_event_callback('round_prestart', function ()
            print_dev.data = { }
        end)
    
        setmetatable(print_dev, {
            __call = function (self, ...)
                print_dev.add(...)
            end
        })
    end

    ---region log aim 4ots
    do
        local hitgroup_str = {
            [0] = 'generic',
            'head', 'chest', 'stomach',
            'left arm', 'right arm',
            'left leg', 'right leg',
            'neck', 'generic', 'gear'
        }

        local weapon_verb = {
            ['hegrenade'] = 'Naded',
            ['inferno'] = 'Burned',
            ['knife'] = 'Knifed',
        }

        local hex_to_rgb = function( hex )
            hex = hex:gsub('#', '')
            return tonumber('0x' .. hex:sub(1, 2)), tonumber('0x' .. hex:sub(3, 4)), tonumber('0x' .. hex:sub(5, 6))
        end

        local function clean_up(str)
            local text = str:gsub('(\a%x%x%x%x%x%x)%x%x', '%1')
            return text
        end

    	local function printc(...)
    		for i, v in ipairs{...} do
    			local r = "\aD9D9D9" .. v
    			for col, text in r:gmatch("\a(%x%x%x%x%x%x)([^\a]*)") do
                    local r, g, b = hex_to_rgb(col)
    				client.color_log(r, g, b, string.format('%s\0', text))
    			end
                client.color_log(255, 255, 255, '\n\0')
    		end
    	end

        local wanted_damage, wanted_hitgroup, backtrack = 0, 0, 0

        client.set_event_callback("aim_fire", function (e)
            if not settings.tweaks_enable:get() then
                return
            end

            if not settings.tweaks:have_key('Log Aimbot Shots') then
                return
            end

            wanted_damage = e.damage
            wanted_hitgroup = e.hitgroup
            backtrack = globals.tickcount() - e.tick
        end)

        client.set_event_callback('aim_hit', function (shot)
            if not settings.tweaks_enable:get() then
                return
            end

            if not settings.tweaks:have_key('Log Aimbot Shots') then
                return
            end

            local target = shot.target
            if target == nil then
                return
            end

            local info = {
                '\rHit ',
                f('\a[nick]%s\r\'s ', entity.get_player_name(target)),
                'in the ',
                shot.hitgroup ~= wanted_hitgroup and f('\a[highlight]%s\r(\a[highlight]%s\r) ', hitgroup_str[ shot.hitgroup ], hitgroup_str[ wanted_hitgroup ]) or f('\a[highlight]%s\r ', hitgroup_str[ shot.hitgroup ]),
                'for ',
                shot.damage ~= wanted_damage and f('\a[highlight]%d\r(\a[highlight]%d\r) ', shot.damage, wanted_damage) or f('\a[highlight]%d\r ', shot.damage),
                'damage ',
                f('(hc: \a[highlight]%d%% \a[idle]· \rhistory: \a[highlight]%dt\r)', shot.hit_chance, backtrack)
            }

            local str = utils.format(table.concat(info, ''), 255, 255, 255, 255)
            printc(f('\aB6E717[gamesense] \aFFFFFF%s', clean_up(str)))
            print_dev(str, 8)
        end)

        client.set_event_callback('aim_miss', function (shot)
            if not settings.tweaks_enable:get() then
                return
            end

            if not settings.tweaks:have_key('Log Aimbot Shots') then
                return
            end

            local target = shot.target
            if target == nil then
                return
            end

            local info = {
                '\rMissed ',
                f('\a[nick]%s\r\'s ', entity.get_player_name(target)),
                f('\a[highlight]%s\r ', hitgroup_str[ shot.hitgroup ]),
                'due to ',
                f('\a[miss]%s\r ', shot.reason),
                f('(hc: \a[highlight]%d%% \a[idle]· \rhistory: \a[highlight]%dt\r)', shot.hit_chance, backtrack)
            }

            local str = utils.format(table.concat(info, ''), 255, 255, 255, 255)
            printc(f('\aB6E717[gamesense] \aFFFFFF%s', clean_up(str)))
            print_dev(str, 8)
        end)

        client.set_event_callback('player_hurt', function (e)
            if not settings.tweaks_enable:get() then
                return
            end

            if not settings.tweaks:have_key('Log Aimbot Shots') then
                return
            end

            local lp = entity.get_local_player()
            local victim = client.userid_to_entindex(e.userid)
            local attacker = client.userid_to_entindex(e.attacker)
            if victim == nil or attacker == nil or victim == lp or attacker ~= lp then
                return
            end

            local hitgroup = hitgroup_str[ e.hitgroup ]

            local verb = weapon_verb[ e.weapon ]
            if verb == nil then
                return
            end

            local info = {
                '\r' .. verb,
                f(' \a[nick]%s\r ', entity.get_player_name(victim)),
                'for ',
                f('\a[highlight]%d \rdamage ', e.dmg_health or 0),
                f('(\a[highlight]%d \rhealth remaining)', e.health or 0)
            }

            local str = utils.format(table.concat(info, ''), 255, 255, 255, 255)
            printc(f('\aB6E717[gamesense] \aFFFFFF%s', clean_up(str)))
            print_dev(str, 8)
        end)
    end

    ---region неопознан
    do
        local shots do
            shots = {
                total = 0,
                hits = 0,

                reasons = {
                    ['prediction error'] = true,
                    ['death'] = true
                }
            }

            client.set_event_callback('aim_fire', function (shot)
                shots.total = shots.total + 1
            end)

            client.set_event_callback('aim_hit', function (shot)
                shots.hits = shots.hits + 1
            end)

            client.set_event_callback('player_connect_full', function (e)
                if client.userid_to_entindex(e['userid']) ~= entity.get_local_player() then
                    return
                end

                shots.hits = 0
                shots.total = 0
            end)
        end

        client.set_event_callback('paint_ui', function ()
            local lp = entity.get_local_player()
            if lp == nil then
                return
            end

            if not widgets.enabled:get() or not widgets.items:have_key('Hit Rate') then
                return
            end

            local hit_rate = shots.total ~= 0 and (shots.hits / shots.total * 100) or 100

            renderer.indicator(255, 255, 255, 200, f('%s%d%%', hit_rate <= 50 and '◣_◢ ' or '', hit_rate))
        end)
    end

    ---region trashtalk
    do
        local phrases = {
            "₁", "１", "𝟷", "𝟭", "𝟏", '(☞ ͡° ͜ʖ ͡°)☞ 1 ♥♥', '✴.·´¯`·.·★  🎀1🎀  ★·.·`¯´·.✴', '❚█══1══█❚',
            '»»» 𝟭 ¯\\_(ツ)_/¯', '¯`·.¸¸.·´¯`·.¸¸.1.¸¸.·`¯´·.¸¸.·`¯💣', '»»»»1»»»»', '∙∙·▫▫ᵒᴼᵒ▫ₒₒ▫ᵒᴼ①ᴼᵒ▫ₒₒ▫ᵒᴼᵒ▫▫·∙∙'
        }

        local function talk()
            client.exec("say " .. phrases[globals.tickcount() % #phrases + 1])
        end

        local my_killer = -1
        client.set_event_callback('player_death', function (event)
            if not settings.tweaks_enable:get() then
                return
            end

            if not settings.tweaks:have_key('Trashtalk') then
                return
            end

            local game_rules = entity.get_game_rules()
            if not game_rules then
                return
            end

            if entity.get_prop(game_rules, 'm_bWarmupPeriod') == 1 then
                return
            end

            local lp = entity.get_local_player()
            if lp == nil then
                return
            end

            local victim, attacker = client.userid_to_entindex(event["userid"]), client.userid_to_entindex(event["attacker"])
            if victim == attacker then
                return
            end

            do
                if victim == lp then
                    my_killer = attacker
                end

                if my_killer ~= -1 and attacker ~= lp then
                    if my_killer == victim then
                        talk()
                        my_killer = -1
                    end
                end
            end

            if attacker == lp then
                talk()
            end
        end)

        client.set_event_callback('round_prestart', function ()
            my_killer = -1
        end)
    end

    --- region unmute
    do
        local function handle_unmute()
            if not settings.tweaks_enable:get() then
                return
            end

            if not settings.tweaks:have_key('Unmute Silenced Players') then
                return
            end

            for i = 1, globals.maxplayers() do
                if entity.get_classname(i) ~= 'CCSPlayer' then
                    goto skip
                end

                utils.unmute(i)
                ::skip::
            end
        end

        settings.tweaks:set_callback(handle_unmute)
        settings.tweaks_enable:set_callback(handle_unmute)
        client.set_event_callback('player_connect_full', handle_unmute)
    end

    ---region autopeek
    do
        function auto_peek.perform(ctx)
            if not aa_tweaks.enable:get() then
                return
            end

            if not aa_tweaks.items:have_key('Auto Peek Improvements')  then
                return
            end

            if not software.is_quick_peek_assist() then
                return
            end

            ctx.yaw_offset = 0
            ctx.yaw_jitter = 'Off'
            ctx.body_yaw = 'Off'
            ctx.freestanding = true
        end
    end

    --- region watermark
    do
        local FRAMERATE_AVG_FRAC = 0.9
        
        local cl_updaterate = cvar["cl_updaterate"]
        
        local alpha = 0.0
        local offset = vector(6, 5)
        
        local timer = 0.0
        local framerate = 0.0
        
        local last_ping = 0.0
        local last_framerate = 1 / globals.absoluteframetime()
        
        local last_server_framerate = 0.0
        local last_server_var = 0.0
        
        local texture do
            http.get("https://i.imgur.com/6viN9T2.png", function(status, response)
                if not status then
                    return
                end
        
                local code = response.status
        
                if code >= 200 and code < 300 then
                    texture = renderer.load_png(response.body, 22, 22)
                end
            end)
        end
        
        local function get_flags()
            return "d"
        end
        
        local function get_ping(nci)
            if inetchannel.is_loopback(nci) then
                return nil
            end
        
            local ping = math.max(0, last_ping * 1000)
            ping = math.floor(ping)
        
            return f("%dms", ping)
        end
        
        local function get_framerate()
            framerate = FRAMERATE_AVG_FRAC * framerate + (1.0 - FRAMERATE_AVG_FRAC) * globals.absoluteframetime()
            return last_framerate
        end
        
        local function get_remote_framerate()
            return last_server_framerate, last_server_var
        end
        
        local function update_timer(nci, dt)
            timer = timer - dt
            if timer > 0 then return end
        
            do
                local latency = inetchannel.get_latency(nci, 0)
                local update_rate = cl_updaterate:get_float()
        
                if update_rate > 0.001 then
                    local adjustment = -0.5 / update_rate
                    latency = latency + adjustment
                end
        
                last_ping = latency
            end
        
            last_server_framerate, last_server_var = inetchannel.get_remote_framerate(nci)
            last_framerate = framerate > 0 and framerate or 1
        
            timer = timer + 1.0
        end
        
        function watermark.frame()
            local can_show_watermark = widgets.enabled:get() and widgets.items:have_key("Watermark")
            alpha = motion.interp(alpha, can_show_watermark, 0.045)
        
            if alpha <= 0 then
                return
            end
        
            local lp = entity.get_local_player()
            if lp == nil then
                return
            end
        
            local nci = iengineclient.get_net_channel_info()
            update_timer(nci, globals.frametime())
        
            if nci == nil then
                return
            end
        
            local screen = vector(client.screen_size())
            local pos = vector(screen.x - 9, 9)
        
            local flags = get_flags()
            local r, g, b = widgets.color_picker:rawget()
        
            local a = 255
        
            local radius = 5
        
            local drawlist = { }
        
            do
                local label = "Guardian"
                local build = BUILD
        
                if texture ~= nil then
                    label = ""
                end
        
                if build == 'beta' then        
                    build = f("[%s]", build)
                    build = decorations.wave(build, globals.realtime(), 255, 255, 255, 255, r, g, b, a)
                    build = f("%s\affffffff", build)
                    
                    drawlist[#drawlist + 1] = merge({ label, build }, "\x20")
                else    
                    drawlist[#drawlist + 1] = label
                end
            end
        
            if widgets.display:have_key("Username") then
                local nickname = USERNAME
        
                if widgets.custom_name:get() then
                    local chosen_nickname = ui.get(widgets.custom_name_value:get_ref())
        
                    if #chosen_nickname ~= 0 then
                        nickname = chosen_nickname
                    end
                end
        
                drawlist[#drawlist + 1] = nickname
            end
        
            if widgets.display:have_key("Latency") then
                drawlist[#drawlist + 1] = get_ping(nci)
            end
        
            if widgets.display:have_key("FPS") then
                drawlist[#drawlist + 1] = f("%dfps", 1 / get_framerate())
            end
        
            if widgets.display:have_key("Server frametime") then
                drawlist[#drawlist + 1] = f("sv: %.1f (%.1fms)", get_remote_framerate())
            end
        
            if widgets.display:have_key("Time") then
                drawlist[#drawlist + 1] = f("%02d:%02d", client.system_time())
            end
        
            local left_padding = 0
        
            if texture ~= nil then
                left_padding = 20
            end
        
            local text = merge(drawlist, " ∙ ")
            local text_size = vector(renderer.measure_text(flags, text))
        
            local rect_size = vector(text_size.x + offset.x * 2, text_size.y + offset.y * 2)
            rect_size.x = rect_size.x + left_padding
        
            pos.x = pos.x - rect_size.x
        
            graphics.header(pos.x, pos.y, rect_size.x, 2, 5, r, g, b, a * alpha)
            --graphics.glow(pos.x, pos.y, rect_size.x, rect_size.y, r, g, b, a * 0.3 * alpha, thickness, radius)
            graphics.rectangle(pos.x, pos.y, rect_size.x, rect_size.y, 0, 0, 0, 100 * alpha, radius)
        
            if texture ~= nil then
                renderer.texture(texture, pos.x + offset.x - 1, pos.y + (rect_size.y - 21) * 0.5, 22, 22, 255, 255, 255, 255 * alpha, "f")
            end
        
            graphics.text(
                pos.x + left_padding + offset.x - 1,
                pos.y + (rect_size.y - text_size.y) * 0.5,
                255, 255, 255, 255 * alpha,
                flags, 0, text
            )
        end
    end

    --- region keybinds
    do
        local alpha = 0.0
        local width = 0.0
        local holding = 0.0
        
        local all_hotkeys = {
            {
                ref = { ui.reference("Legit", "Aimbot", "Enabled") },
                name = "Legit Aimbot",
                offset = 2
            },
        
            {
                ref = { ui.reference("Legit", "Triggerbot", "Enabled") },
                name = "Legit Triggerbot",
                offset = 2
            },
        
            {
                ref = { ui.reference("Rage", "Aimbot", "Enabled") },
                name = "Rage Aimbot",
                offset = 2
            },
        
            {
                ref = { ui.reference("Rage", "Aimbot", "Minimum damage override") },
                name = "Minimum Damage",
                offset = 2
            },
        
            {
                ref = { ui.reference("Rage", "Aimbot", "Force safe point") },
                name = "Safe Point",
                offset = 1
            },
        
            {
                ref = { ui.reference("Rage", "Aimbot", "Force body aim") },
                name = "Force Body Aim",
                offset = 1
            },
        
            {
                ref = { ui.reference("Rage", "Aimbot", "Double tap") },
                name = "Double Tap",
                offset = 2
            },
        
            {
                ref = { ui.reference("Rage", "Aimbot", "Quick stop") },
                name = "Quick Stop",
                offset = 2
            },
        
            {
                ref = { ui.reference("Rage", "Other", "Quick peek assist") },
                name = "Quick Peek Assist",
                offset = 2
            },
        
            {
                ref = { ui.reference("Rage", "Other", "Duck peek assist") },
                name = "Duck Peek Assist",
                offset = 1
            },
        
            {
                ref = { ui.reference("AA", "Anti-aimbot angles", "Freestanding") },
                name = "Freestanding",
                offset = 2
            },
        
            {
                ref = { ui.reference("AA", "Other", "Slow motion") },
                name = "Slow Motion",
                offset = 2
            },
        
            {
                ref = { ui.reference("AA", "Other", "On shot anti-aim") },
                name = "On Shot Anti-aim",
                offset = 2
            },
        
            {
                ref = { ui.reference("AA", "Other", "Fake peek") },
                name = "Fake Peek",
                offset = 2
            },
        
            {
                ref = { ui.reference("Misc", "Movement", "Z-Hop") },
                name = "Z-Hop",
                offset = 2
            },
        
            {
                ref = { ui.reference("Misc", "Movement", "Pre-speed") },
                name = "Pre-speed",
                offset = 2
            },
        
            {
                ref = { ui.reference("Misc", "Movement", "Blockbot") },
                name = "Blockbot",
                offset = 2
            },
        
            {
                ref = { ui.reference("Misc", "Movement", "Jump at edge") },
                name = "Jump At Edge",
                offset = 2
            },
        
            {
                ref = { ui.reference("Misc", "Miscellaneous", "Last second defuse") },
                name = "Last Second Defuse",
                offset = 1
            },
        
            {
                ref = { ui.reference("Misc", "Miscellaneous", "Free look") },
                name = "Free Look",
                offset = 1
            },
        
            {
                ref = { ui.reference("Misc", "Miscellaneous", "Ping spike") },
                name = "Ping Spike",
                offset = 2
            },
        
            {
                ref = { ui.reference("Misc", "Miscellaneous", "Automatic grenade release") },
                name = "Grenade Release",
                offset = 2
            },
        
            {
                ref = { ui.reference("Visuals", "Player ESP", "Activation type") },
                name = "Visuals",
                offset = 1
            }
        }
        
        local active_keys = { }
        local hotkey_modes = { "holding", "toggled", "disabled" }
        
        local function get_flags()
            return "d"
        end
        
        local function get_handle()
            local flags = get_flags()
            local existent_keys = { }
        
            local all_active = false
            local name_width, mode_width = 0, 0
        
            for i = 1, #all_hotkeys do
                local hotkey = all_hotkeys[i]
                local unique_id = hotkey.ref[1]
        
                local name = hotkey.name
                local offset = hotkey.offset or 1
        
                local active = true
                local collected = { }
        
                for j = 1, offset do
                    collected[j] = hotkey.ref[j]
                end
        
                for j = 1, offset do
                    if not ui.get(collected[j]) then
                        active = false
                        break
                    end
                end
        
                if active then
                    existent_keys[unique_id] = true
                    all_active = true
                end
        
                local _, mode = ui.get(collected[#collected])
                if mode == 0 then goto continue end
        
                mode = hotkey_modes[mode] or "~"
                mode = merge { "[", mode, "]" }
        
                if active_keys[unique_id] == nil then
                    active_keys[unique_id] = {
                        alpha = 0,
                        height = 0,
        
                        name_width = 0,
                        mode_width = 0,
        
                        name = name,
                        mode = mode
                    }
                end
        
                local value = active_keys[unique_id] do
                    local name_size = vector(renderer.measure_text(flags, name))
                    local mode_width = vector(renderer.measure_text(flags, mode))
        
                    value.name = name
                    value.mode = mode
        
                    value.height = math.max(name_size.y, mode_width.y)
        
                    value.name_width = name_size.x
                    value.mode_width = mode_width.x
                end
        
                ::continue::
            end
        
            for k, v in pairs(active_keys) do
                local active = existent_keys[k] ~= nil
        
                v.alpha = motion.interp(v.alpha, active, 0.045)
        
                if v.alpha <= 0 then
                    active_keys[k] = nil
                elseif active or v.alpha >= 0.25 then
                    if name_width < v.name_width then
                        name_width = v.name_width
                    end
        
                    if mode_width < v.mode_width then
                        mode_width = v.mode_width
                    end
                end
            end
        
            return active_keys, all_active, name_width, mode_width
        end
        
        keybinds.enabled = menu.new_item(ui.new_checkbox, "AA", "Anti-aimbot angles", "Keybinds")
        : record("visuals", "keybinds::enabled")
        : save()
        
        keybinds.window = windows.new("##keybinds", 0.025, 0.415)
        keybinds.window:set_size(vector(125, 22))
        
        function keybinds.frame()
            local me = entity.get_local_player()
            if me == nil then return end
        
            local window = keybinds.window
            local hotkeys, all_active, name_width, mode_width = get_handle()
        
            local menu_check = ui.is_menu_open() or (next(hotkeys) ~= nil and all_active)
            local can_show_hotkeys = widgets.enabled:get() and widgets.items:have_key("Keybinds") and menu_check
        
            alpha = motion.interp(alpha, can_show_hotkeys, 0.045)
            holding = motion.interp(holding, (can_show_hotkeys and window:is_dragging()) and 0.6 or 1.0, 0.045)
        
            if alpha <= 0 then
                return
            end
        
            local flags = get_flags()
            local r, g, b = widgets.color_picker:get()
        
            local a = 255
        
            local radius = 5
            local thickness = 10
        
            local offset_ins = vector(10, 5)
        
            local keyval_gap = 20
            local keyval_rounding = math.floor(radius * .5)
        
            -- header
            local pos = window.pos
        
            local text = "keybinds"
            local text_size = vector(renderer.measure_text(flags, text))
            local text_size_base = vector(renderer.measure_text(flags, "\v"))
        
            width = motion.interp(width, math.max(
                offset_ins.x * 4 + text_size.x * (text_size.y / text_size_base.y),
                keyval_rounding * 2 + name_width + mode_width + keyval_gap,
                125
            ), 0.045)
        
            local max_width = math.floor(width + 0.85)
            local rect_size = vector(max_width, text_size.y + offset_ins.y * 2)
        
            if alpha > 0.5 then
                graphics.blur(pos.x, pos.y, rect_size.x, rect_size.y)
            end
        
            graphics.header(pos.x, pos.y, rect_size.x, 2, 5, r, g, b, a * alpha * holding)
            graphics.glow(pos.x, pos.y, rect_size.x, rect_size.y, r, g, b, a * 0.3 * alpha * holding, thickness, radius)
            graphics.rectangle(pos.x, pos.y, rect_size.x, rect_size.y, 0, 0, 0, 100 * alpha * holding, radius)
        
            renderer.text(
                pos.x + (rect_size.x - text_size.x) * 0.5,
                pos.y + (rect_size.y - text_size.y) * 0.5,
                255, 255, 255, 255 * alpha * holding,
                flags, 0, text
            )
        
            -- contents
            local offset = 2
        
            for _, v in pairs(active_keys) do
                local alpha = alpha * v.alpha
                local text_size, text_alpha = vector(v.name_width, v.height), 0
        
                if alpha >= 0.25 then
                    text_alpha = math.min(1.0, utils.map(alpha, 0.25, 1.0, 0.0, 1.2))
                end
        
                local text_position = vector(pos.x + keyval_rounding, pos.y + rect_size.y + 4 + offset)
        
                local value_start = rect_size.x - v.mode_width
                local value_alpha = utils.map(value_start - v.name_width, 0.0, keyval_gap, 0.0, 1.0, true)
        
                local h_alpha = text_alpha * holding
        
                renderer.text(text_position.x, text_position.y, 255, 255, 255, 255 * h_alpha, flags, 0, v.name)
                renderer.text(text_position.x + rect_size.x - keyval_rounding * 2 - v.mode_width, text_position.y, 255, 255, 255, 255 * h_alpha * value_alpha, flags, 0, v.mode)
        
                offset = offset + text_alpha * (text_size.y + text_size.y * 0.35)
            end
        
            window:set_size(rect_size)
            window:update()
        end
    end

    --- region indicators
    do
        local alpha = 0.0
        local align = 0.0
        
        local damage_alpha = 0.0
        local damage_value = 0.0
        local damage_moving = 0.0
        local damage_holding = 0.0
        
        local screen = vector(client.screen_size())
        local window = windows.new("##damage", 0.5 + 15 / screen.x, 0.5 - 15 / screen.y)
        
        window:set_anchor(vector(0.0, 1.0))
        window:set_size(vector(22, 22))
        
        local features = {
            {
                get = software.is_double_tap,
                text = "DT",
                alpha = 0
            },
        
            {
                get = software.is_on_shot_antiaim,
                text = "HS",
                alpha = 0
            },
        
            {
                get = software.is_duck_peek_assist,
                text = "FD",
                alpha = 0
            },
        
            {
                get = software.is_minimum_damage_override,
                text = "DMG",
                alpha = 0
            }
        }
        
        local function get_statement()
            if software.is_edge() then
                return 'EDGE'
            end
        
            if safe_head.get() then
                return "SAFE"
            end
        
            if localplayer.is_airborne then
                return "AIR"
            end
        
            if localplayer.is_crouched then
                return "CROUCH"
            end
        
            if localplayer.is_moving then
                if software.is_slow_motion() then
                    return "S.WALK"
                end
        
                return "RUN"
            end
        
            return "STAND"
        end
        
        ctx_bebra.condition = get_statement
        
        function indicators.frame()
            local me = entity.get_local_player()
            if me == nil then return end
        
            local wpn = entity.get_player_weapon(me)
            if wpn == nil then return end
        
            local wpn_info = csgo_weapons(wpn)
            if wpn_info == nil then return end
        
            local menu_check = ui.is_menu_open()
            local alive_check = entity.is_alive(me)
        
            local scoped_check = entity.get_prop(me, "m_bIsScoped")
            local grenade_check = wpn_info.weapon_type_int == 9
        
            local damage = software.get_minimum_damage()
        
            local can_show_indicators = widgets.enabled:get() and widgets.items:have_key("Crosshair Indicator") and alive_check
            local can_move_indicators = can_show_indicators and scoped_check == 1
        
            local can_show_damage = widgets.enabled:get() and widgets.items:have_key("Damage Indicator") and not (wpn_info.weapon_type_int == 0 or wpn_info.weapon_type_int == 9)
            local can_move_damage = can_show_damage and menu_check
        
            alpha = motion.interp(alpha, can_show_indicators and (grenade_check and 0.4 or 1.0) or 0.0, 0.045)
            align = motion.interp(align, can_move_indicators, 0.045)
        
            damage_alpha = motion.interp(damage_alpha, can_show_damage, 0.045)
            damage_value = motion.interp(damage_value, damage, 0.045)
            damage_moving = motion.interp(damage_moving, can_move_damage, 0.045)
            damage_holding = motion.interp(damage_holding, (can_move_damage and window:is_dragging()) and 0.6 or 1.0, 0.045)
        
            local flags = "-d"
            local clock = globals.realtime()
        
            local screen = vector(client.screen_size())
            local center = screen * 0.5
        
            local r1, g1, b1 = widgets.color_picker:rawget()
            local r2, g2, b2, a2 = 255, 255, 255, 255
        
            local r, g, b, a = utils.color_lerp(
                r1, g1, b1, 255,
                r2, g2, b2, a2,
                utils.breathe(clock + 0.5 - 0.5 * align)
            )
        
            -- damage
            if damage_alpha > 0 then
                local value = utils.round(damage_value)
                local text = f("%d", value)
        
                if damage == 0 then
                    text = "AUTO"
                end
        
                if value > 100 then
                    text = f("HP +%d", value - 100)
                end
        
                local measure = vector(renderer.measure_text(flags, text))
                measure.x = measure.x + 1
        
                local pos = window.pos:clone()
                local rect_size = vector(measure.x + 18, measure.y + 16)
        
                local text_position = pos:clone()
        
                text_position.x = text_position.x + (rect_size.x - measure.x) * 0.5
                text_position.y = text_position.y + (rect_size.y - measure.y) * 0.5
        
                if damage_moving > 0 then
                    graphics.rectangle_outline(pos.x, pos.y, rect_size.x, rect_size.y, 255, 255, 255, 128 * damage_moving * damage_holding, 7)
                end
        
                local r3, g3, b3 = r, g, b
                if not can_show_indicators then
                    r3 = r1
                    g3 = g1
                    b3 = b1
                end
        
                renderer.text(text_position.x - 1, text_position.y, r3, g3, b3, a * damage_alpha * damage_holding, flags, 0, text)
        
                window:set_size(rect_size)
                window:update()
            end
        
            if alpha <= 0 then
                return
            end
        
            -- header
            local pos = center:clone()
        
            pos.x = pos.x + utils.round(10 * align)
            pos.y = pos.y + 20
        
            do
                local text = "G U A R D I A N"
        
                local measure = vector(renderer.measure_text(flags, text))
                measure.x = measure.x + 1
        
                local text_position = pos:clone()
                local text_offset = (measure.x * 0.5) * (1 - align)
        
                text_position.x = text_position.x - utils.round(text_offset)
        
                -- graphics.glow(text_position.x + 1, text_position.y + 2, measure.x, 4, r, g, b, a * alpha * 0.1, 10, 1)
                -- renderer.rectangle(text_position.x + 1, text_position.y + 2, measure.x, 4, r, g, b, a * alpha * 0.1)
        
                text = decorations.wave(text, clock, r1, g1, b1, 255, r2, g2, b2, a2)
                graphics.text(text_position.x, text_position.y, r, g, b, a * alpha, flags, 0, text)
        
                pos.y = pos.y + measure.y
            end
        
            do
                local text = get_statement()
        
                local measure = vector(renderer.measure_text(flags, text))
                measure.x = measure.x + 1
        
                local text_position = pos:clone()
                local text_offset = (measure.x * 0.5) * (1 - align)
        
                text_position.x = text_position.x - utils.round(text_offset)
        
                renderer.text(text_position.x, text_position.y, r, g, b, a * alpha, flags, 0, text)
                pos.y = pos.y + measure.y
            end
        
            for i = 1, #features do
                local feature = features[i]
        
                local value_check = feature.get()
                local can_show_feature = can_show_indicators and value_check
        
                feature.alpha = motion.interp(feature.alpha, can_show_feature, 0.045)
        
                if feature.alpha <= 0 then
                    goto continue
                end
        
                local text = feature.text
                local alpha = feature.alpha * alpha
        
                local measure = vector(renderer.measure_text(flags, text))
                measure.x = measure.x + 1
        
                local text_position = pos:clone()
                local text_offset = (measure.x * 0.5) * (1 - align)
        
                text_position.x = text_position.x - utils.round(text_offset)
        
                renderer.text(text_position.x, text_position.y, r, g, b, a * alpha, flags, 0, text)
                pos.y = pos.y + utils.round(measure.y * feature.alpha)
        
                ::continue::
            end
        end
    end

    ---region arrows
    do
        local alpha = 0
        local left_alpha = 0
        local right_alpha = 0
        
        local screen = vector(client.screen_size()) * .5
        
        function arrows.frame()
            local lp = entity.get_local_player()
            if lp == nil then
                return
            end
        
            local wpn = entity.get_player_weapon(lp)
            if wpn == nil then return end
        
            local wpn_info = csgo_weapons(wpn)
            if wpn_info == nil then return end
        
            local can_show_arrows = manual_direction.enabled:get() and manual_direction.arrows:get() and entity.is_alive(lp)
            local can_move_indicators = can_show_indicators and scoped_check == 1
        
            alpha = motion.interp(alpha, can_show_arrows and (wpn_info.weapon_type_int == 9 and 0.4 or 1.0) or 0.0, 0.045)
            if alpha <= 0 then
                return
            end
        
            local r, g, b, a = manual_direction.color:rawget()
            a = 255 * alpha
        
            local manual_direction = manual_direction.get()
        
            left_alpha = motion.interp(left_alpha, manual_direction == 0 and 1 or 0, 0.045)
            if left_alpha ~= 0 then
                renderer.text(screen.x - 50, screen.y - 16, r, g, b, a * left_alpha, '+', nil, '<')
            end
        
            right_alpha = motion.interp(right_alpha, manual_direction == 1 and 1 or 0, 0.045)
            if right_alpha ~= 0 then
                renderer.text(screen.x + 39, screen.y - 16, r, g, b, a * right_alpha, '+', nil, '>')
            end
        end
    end

    --- region velocity_warning
    do
        local alpha = 0.0
        local holding = 0.0
        local hovering = 0.0

        local function renderer_bar(x, y, w, h, r, g, b, a, pct)
            --graphics.glow(x, y, w, h, r, g, b, a * 0.15, 222, h * 0.5)
            renderer.rectangle(x, y, w, h, 0, 0, 0, a)
            renderer.rectangle(x + 1, y + 1, (w - 2) * pct, h - 2, r, g, b, a)
        end

        velocity_warning.window = windows.new("##velocity_warning", 0.5, 0.3)

        velocity_warning.window:set_anchor(vector(0.5, 0.0))
        velocity_warning.window:set_size(vector(180, 4))

        function velocity_warning.frame()
            local me = entity.get_local_player()
            if me == nil then return end

            local window = velocity_warning.window
            local modifier = entity.get_prop(me, "m_flVelocityModifier")

            local menu_check = ui.is_menu_open()

            local alive_check = entity.is_alive(me)
            local velocity_check = modifier < 1.0

            local is_dragging = window:is_dragging()
            local is_hovering = window:is_hovering()

            local can_show_warning = widgets.enabled:get() and widgets.items:have_key("Velocity Warning") and ((alive_check and velocity_check) or menu_check)

            alpha = motion.interp(alpha, can_show_warning, 0.045)
            holding = motion.interp(holding, (can_show_warning and is_dragging) and 0.6 or 1.0, 0.045)
            hovering = motion.interp(hovering, (can_show_warning and is_hovering and not is_dragging) and 1.0 or 0.0, 0.045)

            if alpha <= 0 then
                return
            end

            if menu_check and (not velocity_check or not alive_check) then
                modifier = math.min(1, globals.tickcount() % 200 / 150)
            end

            local flags = "d"
            local percent = (1 - modifier) * 100

            local r, g, b = widgets.color_picker:get()

            local a = 255

            if modifier < 1.0 then
                r = utils.lerp(255, r, modifier)
                g = utils.lerp(75, g, modifier)
                b = utils.lerp(75, b, modifier)
            end

            -- indication
            local pos = window.pos:clone()
            local size = window.size:clone()

            local text = f("Max velocity was reduced by %d%%", percent)
            local text_size = vector(renderer.measure_text(flags, text))

            renderer.text(
                pos.x + (size.x - text_size.x) * 0.5,
                pos.y,
                255, 255, 255, 255 * alpha * holding,
                flags, 0, text
            )

            pos.y = pos.y + text_size.y
            pos.y = pos.y + 5

            local bar_pos = pos:clone()
            local bar_size = vector(text_size.x + 28, 4)

            renderer_bar(bar_pos.x, bar_pos.y, bar_size.x, bar_size.y, r, g, b, a * alpha * holding, modifier)
            pos.y = pos.y + bar_size.y + 5

            if hovering > 0 then
                renderer.text(
                    pos.x,
                    pos.y,
                    255, 255, 255, 255 * alpha * hovering,
                    flags, 0, "Press M2 to center."
                )
            end

            local window_size = vector(math.max(text_size.x, bar_size.x), text_size.y + bar_size.y + 5)

            if is_hovering and not is_dragging and client.key_state(0x02) then
                local screen = vector(client.screen_size())

                window:set_pos(vector(
                    (screen.x - size.x) * 0.5,
                    window.pos.y
                ))
            end

            window:set_size(window_size)
            window:update()
        end
    end

    --- region custom scope
    do
        custom_scope.enabled = menu.new_item(ui.new_checkbox, "AA", "Anti-aimbot angles", "Custom Scope Overlay")
        : record("aa", "custom_scope::enabled")
        : save()
        
        custom_scope.color = menu.new_item(ui.new_color_picker, "AA", "Anti-aimbot angles", "Color", 255, 255, 255, 255)
        : record("aa", "custom_scope::color")
        : save()
        
        custom_scope.mode = menu.new_item(ui.new_combobox, "AA", "Anti-aimbot angles", "Mode", { 'Default', 'T' })
        : record("aa", "custom_scope::mode")
        : save()
        
        custom_scope.position = menu.new_item(ui.new_slider, "AA", "Anti-aimbot angles", "\nPosition", 0, 500, 50, true, 'px')
        : record("aa", "custom_scope::position")
        : save()
        
        custom_scope.offset = menu.new_item(ui.new_slider, "AA", "Anti-aimbot angles", "\nOffset", 0, 500, 10, true, 'px')
        : record("aa", "custom_scope::offset")
        : save()
        
        local alpha = 0
        client.set_event_callback('paint_ui', function ()
            ui.set(software.visuals.scope_overlay, true)
        end)
        
        client.set_event_callback('paint', function ()
            if not custom_scope.enabled:get() then
                return
            end
        
            ui.set(software.visuals.scope_overlay, false)
        
            local lp = entity.get_local_player()
            if lp == nil then
                return
            end
        
            local width, height = client.screen_size()
            local offset, position = custom_scope.offset:get() * height / 1080, custom_scope.position:get() * height / 1080
        
            local condition = entity.get_prop(lp, 'm_bIsScoped') == 1 and entity.get_prop(lp, 'm_bResumeZoom') == 0
            alpha = motion.interp(alpha, condition, 0.045)
            if alpha < 0.001 then
                return
            end
        
            local clr = { custom_scope.color:rawget() }
        
            local clr1 = { clr[1], clr[2], clr[3], 0 }
            local clr2 = { clr[1], clr[2], clr[3], clr[4] * alpha }
            local mode = custom_scope.mode:get()
        
            if mode ~= 'T' then
                renderer.gradient(
                    width / 2, height / 2 - position + 2,
                    1, position - offset,
                    clr1[1], clr1[2], clr1[3], clr1[4],
                    clr2[1], clr2[2], clr2[3], clr2[4],
                    false
                )
            end
        
            renderer.gradient(
                width / 2, height / 2 + offset,
                1, position - offset,
                clr2[1], clr2[2], clr2[3], clr2[4],
                clr1[1], clr1[2], clr1[3], clr1[4],
                false
            )
        
            renderer.gradient(
                width / 2 - position + 2, height / 2,
                position - offset, 1,
                clr1[1], clr1[2], clr1[3], clr1[4],
                clr2[1], clr2[2], clr2[3], clr2[4],
                true
            )
        
            renderer.gradient(
                width / 2 + offset, height / 2,
                position - offset, 1,
                clr2[1], clr2[2], clr2[3], clr2[4],
                clr1[1], clr1[2], clr1[3], clr1[4],
                true
            )
        end)
        
        defer(function ()
            ui.set_visible(software.visuals.scope_overlay, true)
        end)
    end

    --- hit marker Guardian
    do
        local ctx = {
            target = 0,
            pos = vector()
        }

        local pending_markers = { }

        function hit_marker.frame()
            if not settings.tweaks_enable:get() then
                return
            end

            if not settings.tweaks:have_key('Damage Marker') then
                return
            end

            local realtime = globals.realtime()
            for i, data in ipairs(pending_markers) do
                local diff = data[3] - realtime

                local alpha = math.min(1, diff)--diff < 1 and math.max(0, diff) or 1

                local x, y = renderer.world_to_screen(data[1].x, data[1].y, data[1].z)

                local r, g, b = unpack(data[4])
                renderer.text(x, y, r, g, b, 255 * alpha, "c", nil, data[2])

                if data[3] < realtime then
                    table.remove(pending_markers, i)
                end
            end
        end

        function hit_marker.aim_fire(e)
            if not settings.tweaks_enable:get() then
                return
            end

            if not settings.tweaks:have_key('Damage Marker') then
                return
            end

            ctx.target = e.target
            ctx.pos = vector(e.x, e.y, e.z)
        end

        function hit_marker.aim_hit(e)
            if not settings.tweaks_enable:get() then
                return
            end

            if not settings.tweaks:have_key('Damage Marker') then
                return
            end

            if ctx.target == e.target then
                table.insert(
                    pending_markers,
                    {
                        ctx.pos, tostring(e.damage),
                        globals.realtime() + 3,
                        e.hitgroup == 1 and { widgets.color_picker:rawget() } or { 240, 240, 240 }
                    }
                )
            end
        end

        function hit_marker.round_prestart()
            table.clear(pending_markers)
        end
    end

    ---region advertise
    do
        local kills = 0
        
        client.set_event_callback('player_death', function (e)
            if client.userid_to_entindex(e.attacker) ~= entity.get_local_player() then
                return
            end
        
            kills = kills + 1
        end)
        
        local x, y = client.screen_size()
        
        client.set_event_callback('paint', function ()
            local enabled = widgets.enabled:get() and (widgets.items:have_key('Watermark') or widgets.items:have_key('Crosshair Indicator'))
            if enabled then
                return
            end
        
            if kills < 2 then
                return
            end
        
            local r, g, b, a = widgets.color_picker:rawget()
        
            local str = decorations.wave('Guardian', globals.realtime(), r, g, b, 200, 255, 255, 255, 200)
        
            renderer.text(x * .5, y - 15, 255, 255, 255, a, 'cd', nil, str)
        end)
        
        client.set_event_callback('round_end', function (e)
            kills = 0
        end)
    end

    --- region console filter
    do
        cvar.con_filter_text:set_string("[gamesense]")

        local function apply_con_filter()
            cvar.con_filter_enable:set_raw_int(
                (settings.tweaks_enable:get() and settings.tweaks:have_key('Console Filter'))
                    and 1 or 0
            )
        end

        settings.tweaks:set_callback(apply_con_filter)
        settings.tweaks_enable:set_callback(apply_con_filter)
        apply_con_filter()

        defer(function ()
            cvar.con_filter_enable:set_raw_int(0)
        end)
    end
    
    ---region anim_breakers
    do
        anim_breakers.enabled = menu.new_item(ui.new_checkbox, "AA", "Anti-aimbot angles", "Animation Breakers")
        : record("aa", "anim_breakers::enabled")
        : save()

        anim_breakers.ground = menu.new_item(ui.new_combobox, "AA", "Anti-aimbot angles", '- Leg Movement', { "Default", 'Static', 'Walking' })
        : record("aa", "anim_breakers::ground")
        : save()

        anim_breakers.air = menu.new_item(ui.new_combobox, "AA", "Anti-aimbot angles", '- In Air', { "Default", 'Static', 'Walking' })
        : record("aa", "anim_breakers::air")
        : save()

        local native_GetClientEntity = vtable_bind('client.dll', 'VClientEntityList003', 3, 'void*(__thiscall*)(void*, int)')

        local char_ptr = ffi.typeof('char*')
        local nullptr = ffi.new('void*')
        local class_ptr = ffi.typeof('void***')

        local animation_layer_t = ffi.typeof([[
            struct {										char pad0[0x18];
                uint32_t	sequence;
                float		prev_cycle;
                float		weight;
                float		weight_delta_rate;
                float		playback_rate;
                float		cycle;
                void		*entity;						char pad1[0x4];
            } **
        ]])

        client.set_event_callback('net_update_end', function ()
            if not anim_breakers.enabled:get() then
                override.unset(software.aa.other.leg_movement)
                return
            end

            local lp = entity.get_local_player()
            if lp == nil then
                return
            end

            local player_ptr = ffi.cast(class_ptr, native_GetClientEntity(lp))
            if player_ptr == nullptr then
                return
            end

            local anim_layers = ffi.cast(animation_layer_t, ffi.cast(char_ptr, player_ptr) + 0x2990)[0]

            do
                local mode = anim_breakers.ground:get()
                if mode ~= 'Disabled' then
                    if mode == 'Static' then
                        entity.set_prop(lp, 'm_flPoseParameter', 1, 0)
                        override.set(software.aa.other.leg_movement, 'Always slide')
                    elseif mode == 'Walking' then
                        entity.set_prop(lp, 'm_flPoseParameter', 0.5, 7)
                        override.set(software.aa.other.leg_movement, 'Never slide')
                    end
                else
                    override.unset(software.aa.other.leg_movement)
                end
            end

            do
                local mode = anim_breakers.air:get()
                if mode ~= 'Disabled' and ctx_bebra.condition() == 'AIR' then
                    if mode == 'Static' then
                        entity.set_prop(lp, 'm_flPoseParameter', 1, 6)
                    elseif mode == 'Walking' then
                        anim_layers[6]['weight'] = 1
                    end
                end
            end
        end)
    end

    ---region bombsite fix
    do
        client.set_event_callback('setup_command', function (cmd)
            local lp = entity.get_local_player()
            if lp == nil then
                return
            end
        
            local weapon = entity.get_player_weapon(lp)
            if weapon == nil then
                return
            end
        
            if entity.get_classname(weapon) == 'CC4' then
                return
            end
        
            if entity.get_prop(lp, 'm_bInBombZone') == 1 then
                cmd.in_use = 0
            end
        end)
    end

    --- region angles
    do
        local function set_custom_list(ctx, list)
            if list.pitch ~= nil then
                ctx.pitch = list.pitch:get()
                ctx.pitch_offset = list.pitch_offset:get()
            end

            if list.yaw_base ~= nil then
                ctx.yaw_base = list.yaw_base:get()
            end

            ctx.yaw = list.yaw:get()
            ctx.yaw_offset = list.yaw_offset:get()

            if ctx.yaw == "180 LR" then
                ctx.yaw_offset = 0
            end

            ctx.yaw_180lr_mode = list.yaw_180lr_mode:get()
            ctx.yaw_delay = list.yaw_delay:get()
            ctx.yaw_left = list.yaw_left:get()
            ctx.yaw_right = list.yaw_right:get()

            ctx.yaw_jitter = list.yaw_jitter:get()
            ctx.jitter_mode = list.jitter_mode:get()
            ctx.acid_cycle = list.acid_cycle:get()
            ctx.acid_delay = list.acid_delay:get()
            ctx.acid_safe = list.acid_safe:get()
            ctx.jitter_offset = list.jitter_offset:get()
            ctx.jitter_randomization = list.jitter_randomization:get()

            ctx.body_yaw = list.body_yaw:get()
            ctx.body_yaw_offset = list.body_yaw_offset:get()
            ctx.freestanding_body_yaw = list.freestanding_body_yaw:get()
        end

        angles.type = menu.new_item(ui.new_combobox, "AA", "Anti-aimbot angles", "Anti Aim Builder", {
            "Off",
            "Custom",
            "Recommended"
        })
        : record("aa", "angles::type")
        : save()

        local conds = { 'Standing', 'Moving', 'Slow Walk', 'Crouched', 'Move Crouched', 'Air', 'Air Crouched', 'Fake Lag'}

        local function reset_delay()
            for _, condition in next, conds do
                delay_data_all[condition] = {
                    ticks = 0,
                    is_active = false,
                    current = 0,
                    previous_angle = 0
                }
            end
        end

        reset_delay()

        angles.custom = { } do
            angles.custom.state = menu.new_item(ui.new_combobox, "AA", "Anti-aimbot angles", "State", { unpack(e_statement, 0) })
            : record("aa", "custom::state")

            for i = 0, #e_statement do
                local list = { }
                local state = e_statement[i]

                if i ~= 0 then
                    list.enabled = menu.new_item(ui.new_checkbox, "AA", "Anti-aimbot angles", merge { "Enable", "\x20", state })
                    : record("aa", merge { "custom", "::", state, "::", "enabled" })
                    : save()
                end

                if i ~= 10 then
                    local pitch_list = { "Off", "Default", "Up", "Down", "Minimal", "Random", "Custom" }

                    list.pitch = menu.new_item(ui.new_combobox, "AA", "Anti-aimbot angles", merge { "Pitch", "\n", "custom_", "pitch_", state }, pitch_list)
                    : record("aa", merge { "custom", "::", state, "::", "pitch" })
                    : save()

                    list.pitch_offset = menu.new_item(ui.new_slider, "AA", "Anti-aimbot angles", merge { "\n", "custom_", "pitch_offset_", state }, -89, 89, 0, true, "°")
                    : record("aa", merge { "custom", "::", state, "::", "pitch_offset" })
                    : save()

                    list.yaw_base = menu.new_item(ui.new_combobox, "AA", "Anti-aimbot angles", merge { "Yaw base", "\n", "custom_", "yaw_base_", state }, { "Local view", "At targets" })
                    : record("aa", merge { "custom", "::", state, "::", "yaw_base" })
                    : save()
                end

                list.yaw = menu.new_item(ui.new_combobox, "AA", "Anti-aimbot angles", merge { "Yaw", "\n", "custom_", "yaw_", state }, { "Off", "180", "Spin", "Static", "180 Z", "Crosshair", "180 LR" })
                : record("aa", merge { "custom", "::", state, "::", "yaw" })
                : save()

                list.yaw_offset = menu.new_item(ui.new_slider, "AA", "Anti-aimbot angles", merge { "\n", "custom_", "yaw_offset_", state }, -180, 180, 0, true, "°")
                : record("aa", merge { "custom", "::", state, "::", "yaw_offset" })
                : save()

                list.yaw_180lr_mode = menu.new_item(ui.new_combobox, "AA", "Anti-aimbot angles", merge { "\n", "custom_", "yaw_180lr_mode_", state }, { "Side based", "Switch delay" })
                : record("aa", merge { "custom", "::", state, "::", "yaw_180lr_mode" })
                : save()

                list.yaw_left = menu.new_item(ui.new_slider, "AA", "Anti-aimbot angles", merge { "Left offset", "\n", "custom_", "yaw_left_", state }, -180, 180, 0, true, "°")
                : record("aa", merge { "custom", "::", state, "::", "yaw_left" })
                : save()

                list.yaw_right = menu.new_item(ui.new_slider, "AA", "Anti-aimbot angles", merge { "Right offset", "\n", "custom_", "yaw_right_", state }, -180, 180, 0, true, "°")
                : record("aa", merge { "custom", "::", state, "::", "yaw_right" })
                : save()

                list.yaw_delay = menu.new_item(ui.new_slider, "AA", "Anti-aimbot angles", merge { "Delay", "\n", "custom_", "Delay_", state }, 2, 10, 5, true, "t")
                : record("aa", merge { "custom", "::", state, "::", "yaw_delay" })
                : save()

                list.yaw_jitter = menu.new_item(ui.new_combobox, "AA", "Anti-aimbot angles", merge { "Yaw jitter", "\n", "custom_", "yaw_jitter_", state }, { "Off", "Offset", "Center", "Random", "Skitter", "Guardian" })
                : record("aa", merge { "custom", "::", state, "::", "yaw_jitter" })
                : save()

                list.jitter_mode = menu.new_item(ui.new_combobox, "AA", "Anti-aimbot angles", merge { "\n", "custom_", "jitter_mode_", state }, { "2-Way", "3-Way", "5-Way" })
                : record("aa", merge { "custom", "::", state, "::", "jitter_mode" })
                : save()

                list.jitter_offset = menu.new_item(ui.new_slider, "AA", "Anti-aimbot angles", merge { "\nJitter offset", "\n", "custom_", "jitter_offset_", state }, -180, 180, 0, true, "°")
                : record("aa", merge { "custom", "::", state, "::", "jitter_offset" })
                : save()

                list.jitter_randomization = menu.new_item(ui.new_slider, "AA", "Anti-aimbot angles", merge { "Randomization", "\n", "custom_", "jitter_randomization_", state }, 0, 180, 0, true, "°", 1, { [0] = "Off" })
                : record("aa", merge { "custom", "::", state, "::", "jitter_randomization" })
                : save()

                list.acid_cycle = menu.new_item(ui.new_slider, "AA", "Anti-aimbot angles", merge { "Delay Cycle", "\n", "custom_", "delay_cycle_", state }, 5, 200, 50, true, '', 1, { [5] = "Off" })
                : record("aa", merge { "custom", "::", state, "::", "acid_cycle" })
                : save()

                list.acid_delay = menu.new_item(ui.new_slider, "AA", "Anti-aimbot angles", merge { "Delay Time", "\n", "custom_", "acid_delay", state }, 5, 30, 15)
                : record("aa", merge { "custom", "::", state, "::", "acid_delay" })
                : save()

                list.acid_safe = menu.new_item(ui.new_checkbox, "AA", "Anti-aimbot angles", merge { "Safe Yaw", "\n", "custom_", "safe_yaw_", state })
                : record("aa", merge { "custom", "::", state, "::", "acid_safe" })
                : save()

                list.body_yaw = menu.new_item(ui.new_combobox, "AA", "Anti-aimbot angles", merge { "Body yaw", "\n", "custom_", "body_yaw_", state }, { "Off", "Opposite", "Jitter", "Static", 'Randomize Jitter' })
                : record("aa", merge { "custom", "::", state, "::", "body_yaw" })
                : save()

                list.body_yaw_offset = menu.new_item(ui.new_slider, "AA", "Anti-aimbot angles", merge { "\n", "custom_", "body_yaw_offset_", state }, -180, 180, 0, true, "°")
                : record("aa", merge { "custom", "::", state, "::", "body_yaw_offset" })
                : save()

                list.freestanding_body_yaw = menu.new_item(ui.new_checkbox, "AA", "Anti-aimbot angles", merge { "Freestanding body yaw", "\n", "custom_", "freestanding_body_yaw_", state })
                : record("aa", merge { "custom", "::", state, "::", "freestanding_body_yaw" })
                : save()


                list.acid_safe:set_callback(reset_delay)
                list.acid_delay:set_callback(reset_delay)
                list.acid_cycle:set_callback(reset_delay)

                angles.custom[state] = list
            end
        end

        angles.recommended = {
            ['Standing'] = function (ctx)
                ctx.pitch = 'Default'
                ctx.yaw_base = 'At targets'
                ctx.yaw = '180'
                ctx.yaw_offset = 8
                ctx.yaw_jitter = 'Center'
                ctx.jitter_offset = 24
                ctx.jitter_randomization = 8
                ctx.body_yaw = 'Jitter'
                ctx.body_yaw_offset = -42
            end,

            ['Moving'] = function (ctx)
                ctx.pitch = 'Default'
                ctx.yaw_base = 'At targets'
                ctx.yaw = '180'
                ctx.yaw_offset = 6
                ctx.yaw_jitter = 'Center'
                ctx.jitter_offset = 28
                ctx.jitter_randomization = 12
                ctx.body_yaw = 'Jitter'
                ctx.body_yaw_offset = -38
            end,

            ['Slow Walk'] = function (ctx)
                ctx.pitch = 'Default'
                ctx.yaw_base = 'At targets'
                ctx.yaw = '180'
                ctx.yaw_offset = 10
                ctx.yaw_jitter = 'Guardian'
                ctx.jitter_mode = '3-Way'       -- Changed from 2-Way
                ctx.jitter_offset = 22
                ctx.jitter_randomization = 18
                ctx.acid_cycle = 28             -- Adjusted
                ctx.acid_delay = 16             -- Adjusted
                ctx.acid_safe = true
                ctx.body_yaw = 'Jitter'
                ctx.body_yaw_offset = -45
            end,

            ['Crouched'] = function (ctx)
                ctx.pitch = 'Default'
                ctx.yaw_base = 'At targets'
                ctx.yaw = '180'
                ctx.yaw_offset = 12
                ctx.yaw_jitter = 'Center'
                ctx.jitter_offset = 26
                ctx.jitter_randomization = 10
                ctx.body_yaw = 'Static'         -- Changed from Jitter
                ctx.body_yaw_offset = 120       -- Adjusted
            end,

            ['Move Crouched'] = function (ctx)
                ctx.pitch = 'Default'
                ctx.yaw_base = 'At targets'
                ctx.yaw = '180'
                ctx.yaw_offset = 8
                ctx.yaw_jitter = 'Center'
                ctx.jitter_offset = 25
                ctx.jitter_randomization = 8
                ctx.body_yaw = 'Jitter'
                ctx.body_yaw_offset = -40
            end,

            ['Air'] = function (ctx)
                ctx.pitch = 'Default'
                ctx.yaw_base = 'At targets'
                ctx.yaw = '180'
                ctx.yaw_offset = 0
                ctx.yaw_jitter = 'Off'
                ctx.jitter_offset = 0
                ctx.body_yaw = 'Opposite'
                ctx.body_yaw_offset = 0
                ctx.freestanding_body_yaw = true
            end,

            ['Air Crouched'] = function (ctx)
                ctx.pitch = 'Default'
                ctx.yaw_base = 'At targets'
                ctx.yaw = '180'
                ctx.yaw_offset = 0
                ctx.yaw_jitter = 'Off'
                ctx.jitter_offset = 0
                ctx.body_yaw = 'Static'          -- Changed
                ctx.body_yaw_offset = 120        -- Added
                ctx.freestanding_body_yaw = true
            end,

            ['Fake Lag'] = function (ctx)
                ctx.pitch = 'Default'
                ctx.yaw_base = 'At targets'
                ctx.yaw = '180'
                ctx.yaw_offset = 0
                ctx.yaw_jitter = 'Off'
                ctx.jitter_offset = 0
                ctx.body_yaw = 'Opposite'
                ctx.body_yaw_offset = 0
                ctx.freestanding_body_yaw = true
            end
        }

        function angles.set(ctx, state)
            if angles.type:get() == "Custom" then
                local list = angles.custom[state]

                if list ~= nil then
                    -- if not enabled in menu
                    if list.enabled ~= nil then
                        if not list.enabled:get() then
                            return false
                        end
                    end

                    set_custom_list(ctx, list)
                    return true
                end

                return false
            end

            if angles.type:get() == "Recommended" then
                local fn = angles.recommended[state]

                if fn ~= nil then
                    fn(ctx)
                    return true
                end

                return false
            end

            return false
        end

        function angles.update(ctx)
            local list = statement.get()

            for i = #list, 1, -1 do
                local state = list[i]

                if angles.set(ctx, state) then
                    return
                end
            end

            angles.set(ctx, "Main")
        end
    end

    --- region yaw_direction
    do

        yaw_direction.edge_yaw = menu.new_item(ui.new_hotkey, "AA", "Anti-aimbot angles", merge { "Edge Yaw", "\n", "yaw_direction::edge_yaw" })
        : record("aa", "yaw_direction::edge_yaw")

        yaw_direction.freestanding = menu.new_item(ui.new_hotkey, "AA", "Anti-aimbot angles", merge { "Freestanding", "\n", "yaw_direction::freestanding" })
        : record("aa", "yaw_direction::freestanding")

        fs_disablers.states = menu.new_item(ui.new_multiselect, "AA", "Anti-aimbot angles", merge { "- Disable On", "\n", "fs_disablers::states" }, {"Standing", "Moving", "Slow Walk", "Crouched", "Air" })
        : record("aa", "fs_disablers::states")
        : save()

        function yaw_direction.update(ctx)
            if not aa_tweaks.enable:get() then
                return
            end

            if aa_tweaks.items:have_key('Edge Yaw on FD') and software.is_duck_peek_assist() then
                ctx.edge_yaw = true, 1
            else
                ctx.edge_yaw = yaw_direction.edge_yaw:rawget()
            end

            ctx.freestanding = yaw_direction.freestanding:rawget()
        end
    end

    --- region freestqand disablers
    do
        local function get_statement()
            if localplayer.is_airborne then
                return "Air"
            end

            if localplayer.is_crouched then
                return "Crouched"
            end

            if localplayer.is_moving then
                if software.is_slow_motion() then
                    return "Slow Walk"
                end

                return "Moving"
            end

            return "Standing"
        end

        function fs_disablers.update(ctx)
            local state = get_statement()
            if state == nil then
                return
            end

            if not fs_disablers.states:have_key(state) then
                return
            end

            ctx.freestanding = false
        end
    end

    --- clientside nickname
    do
        clientside_nickname.enabled = menu.new_item(ui.new_checkbox, "AA", "Anti-aimbot angles", "Client-Side Nickname")
        : record("visuals", "clientside_nickname::enabled")
        : save()

        clientside_nickname.nickname = menu.new_item(ui.new_textbox, "AA", "Anti-aimbot angles", "Nickname")
        : record("visuals", "clientside_nickname::nickname")
        : save()

        local panorama = panorama.open()

        local native_BaseLocalClient_base = ffi.cast("uintptr_t**", memory.pattern_scan("engine.dll", "A1 ? ? ? ? 0F 28 C1 F3 0F 5C 80 ? ? ? ? F3 0F 11 45 ? A1 ? ? ? ? 56 85 C0 75 04 33 F6 EB 26 80 78 14 00 74 F6 8B 4D 08 33 D2 E8 ? ? ? ? 8B F0 85 F6", 1))

        local player_info_t = ffi.typeof([[
            struct {
                int64_t         unknown;
                int64_t         steamID64;
                char            szName[128];
                int             userId;
                char            szSteamID[20];
                char            pad_0x00A8[0x10];
                unsigned long   iSteamID;
                char            szFriendsName[128];
                bool            fakeplayer;
                bool            ishltv;
                unsigned int    customfiles[4];
                unsigned char   filesdownloaded;
            }
        ]])

        local native_GetStringUserData = vtable_thunk(11, ffi.typeof("$*(__thiscall*)(void*, int, int*)", player_info_t))

        local previous_name
        local function apply_nickname(name)
            local local_player = entity.get_local_player()
            if not local_player then
                return
            end

            local native_BaseLocalClient = native_BaseLocalClient_base[0][0]
            if not native_BaseLocalClient then
                return
            end

            local native_UserInfoTable = ffi.cast("void***", native_BaseLocalClient + 0x52C0)[0]
            if not native_UserInfoTable then
                return
            end

            local data = native_GetStringUserData(native_UserInfoTable, local_player - 1, nil)
            if not data then
                return
            end

            local this_name = ffi.string(data[0].szName)
            if name ~= this_name and previous_name == nil then
                previous_name = this_name
            end

            data[0].szName = ffi.new("char[128]", name)
        end

        local was_applied = false
        local function callback()
            local chosen_nick = ui.get(clientside_nickname.nickname:get_ref()):sub(0, 32)
            clientside_nickname.nickname:set(chosen_nick)

            if not clientside_nickname.enabled:get() or #chosen_nick == 0 then
                if was_applied then
                    was_applied = false
                    apply_nickname(previous_name or panorama["MyPersonaAPI"]["GetName"]())
                    previous_name = nil
                end

                return
            end

            was_applied = true

            apply_nickname(chosen_nick)
        end

        clientside_nickname.apply = menu.new_item(ui.new_button, "AA", "Anti-aimbot angles", "Apply", callback)
        : record("visuals", "clientside_nickname::apply")

        clientside_nickname.enabled:set_callback(callback)

        client.set_event_callback('round_prestart', callback)
        client.set_event_callback('player_connect_full', callback)

        callback()
    end

    --- region shared
    do
        shared.enabled = menu.new_item(ui.new_checkbox, 'AA', 'Anti-aimbot angles', 'Shared Logo')
        :record('settings', 'shared::enabled')
        :save()

        shared.socket = nil
        shared.data = { }
        shared.icon_data = { }
        shared.link = "wss://mishkat.cloud/acid/ws"
        shared.failed_connections = 0

        local scoreboard = panorama.loadstring([[
            let _get_xuid = function(entity_index) {
                let xuid = GameStateAPI.GetPlayerXuidStringFromEntIndex(entity_index);
                return xuid;
            }

            let _set_icon = function(entity_index, icon) {
                let xuid = GameStateAPI.GetPlayerXuidStringFromEntIndex(entity_index);
                let context_panel = $.GetContextPanel();
                let ctx = context_panel.FindChildTraverse('ScoreboardContainer').FindChildTraverse('Scoreboard') || context_panel.FindChildTraverse('id-eom-scoreboard-container').FindChildTraverse('Scoreboard')
                if (ctx == null)
                    return;

                ctx.FindChildrenWithClassTraverse('sb-row').forEach(function(e) {
                    if (e.m_xuid != xuid)
                        return false;

                    e.Children().forEach(function(child) {
                        let attribute = child.GetAttributeString('data-stat', '');
                        if (attribute != 'rank')
                            return false;

                        var image = child.FindChildTraverse('image');
                        if (!image || !image.IsValid())
                            return false;

                        image.SetImage(icon === null ? '' : icon)
                        return true;
                    })
                })

                return xuid;
            }

            return {
                xuid: _get_xuid,
                set_icon: _set_icon
            }
        ]], 'CSGOHud')()

        local panorama = panorama.open()

        shared.retrieve = function ()
            local info = json.stringify({
                steam = tostring(panorama.MyPersonaAPI.GetXuid()),
                logo = 'bebra'
            })

            return base64.encode(info)
        end

        shared.callbacks = {
            open = function(ws)
                ws:send(shared.retrieve())

                shared.socket = ws
            end,

            message = function(ws, data)
                local success, data = pcall(base64.decode, data)
                if not success or type(data) ~= 'string' then
                    return
                end

                local success, data = pcall(json.parse, data)
                if not success then
                    return
                end

                local online = 0

                for _, object in next, data do
                    if type(object) == 'string' then
                        online = online + 1
                    end
                end

                shared.online_label:set(string.format('Current Online: %d', online))

                shared.data = data
            end,

            close = function (ws)
                shared.socket = nil
                client.delay_call(10, websockets.connect, shared.link, shared.callbacks)
            end
        }

        shared.send = function ()
            if not shared.socket then
                return
            end

            shared.socket:send(shared.retrieve())
        end

        shared.attach = function (condition)
            local enabled = shared.enabled:get() and not condition

            for i = 1, globals.maxplayers() do
                if entity.get_classname(i) ~= 'CCSPlayer' then
                    goto skip
                end

                local steam_id = scoreboard.xuid(i)

                if not enabled then
                    if not shared.icon_data[ steam_id ] then
                        scoreboard.set_icon(i)
                        shared.icon_data[ steam_id ] = true
                    end

                    goto skip
                end

                local logo_id = shared.data[ steam_id ]

                if logo_id then
                    scoreboard.set_icon(i, string.format("https://mishkat.cloud/acid/icons/%s.png", logo_id))
                    shared.icon_data[ steam_id ] = false
                else
                    if not shared.icon_data[ steam_id ] then
                        scoreboard.set_icon(i)
                        shared.icon_data[ steam_id ] = true
                    end
                end

                ::skip::
            end
        end

        shared.init = function ()
            websockets.connect(shared.link, shared.callbacks)

            shared.send()
            shared.enabled:set_callback(shared.send)
            client.delay_call(2, shared.send)

            client.set_event_callback('paint', function ()
                shared.attach()
            end)

            client.set_event_callback('shutdown', function ()
                shared.attach(true)
            end)
        end

        shared.init()
    end

    --- region buy bot
    do
        local primary_console = {
            ["Autosnipers"] = "scar20",
            ["Scout"] = "ssg08",
            ["AWP"] = "awp",
            ["AK-47 / M4"]  = "ak47",
            ["AUG / SG553"] = "sg556",
            ['Famas'] = 'famas',
            ["Negev"] = "negev",
            ['M249'] = 'm249',
            ['MP7 / MP5'] = 'mp7',
            ['MP9 / Mac-10'] = 'mp9',
            ['UMP-45'] = 'ump45',
            ['P90'] = 'p90',
            ['Bizon'] = 'bizon',
            ['Nova'] = 'nova',
            ['XM1014'] = 'XM1014',
            ['Mag7 / Sawed-Off'] = 'mag7'
        }

        local secondary_console = {
            ["R8 / Deagle"] = "deagle",
            ["Tec-9 / Five-S / CZ-75"] = "tec9",
            ["P-250"] = "p250",
            ["Duals"] = "elite"
        }

        local utility_console = {
            ["Kevlar"] = "vest",
            ['Helmet'] = 'vesthelm',
            ["Defuser"] = "defuser",
            ["Taser"] = "taser",
            ["HE"] = "hegrenade",
            ["Molotov"] = "molotov",
            ["Smoke"] = "smokegrenade",
            ["Flashbang"] = "flashbang",
            ["Decoy"] = "decoy"
        }

        buy_bot.enabled = menu.new_item(ui.new_checkbox, "AA", "Anti-aimbot angles", "Buy Bot")
        : record("settings", "buy_bot::enabled")
        : save()

        buy_bot.primary = menu.new_item(ui.new_combobox, "AA", "Anti-aimbot angles", 'Primary weapon', { 'None', 'Autosnipers', 'Scout', 'AWP', 'AK-47 / M4',  'AUG / SG553', 'Famas', 'Negev', 'M249', 'MP7 / MP5', 'MP9 / Mac-10', 'UMP-45', 'P90', 'Bizon', 'Nova', 'XM1014', 'Mag7 / Sawed-Off' })
        : record("settings", "buy_bot::primary")
        : save()

        buy_bot.secondary = menu.new_item(ui.new_combobox, "AA", "Anti-aimbot angles", 'Secondary weapon', { 'None', 'R8 / Deagle', 'Tec-9 / Five-S / CZ-75', 'P-250', 'Duals' })
        : record("settings", "buy_bot::secondary")
        : save()

        buy_bot.utility = menu.new_item(ui.new_multiselect, "AA", "Anti-aimbot angles", 'Utility weapon', { 'Kevlar', 'Helmet', 'Defuser', 'Taser', 'HE', 'Molotov', 'Smoke', 'Flashbang', 'Decoy' })
        : record("settings", "buy_bot::utility")
        : save()

        buy_bot.skip_pistol = menu.new_item(ui.new_checkbox, "AA", "Anti-aimbot angles", "Skip pistol round")
        : record("settings", "buy_bot::skip_pistol")
        : save()

        buy_bot.skip_pistol:set(true)

        local function is_pistol_round(money)
            local game_rules = entity.get_game_rules and entity.get_game_rules()
            local rounds_played = game_rules and entity.get_prop(game_rules, "m_totalRoundsPlayed") or nil

            local max_rounds = 30
            if cvar and cvar.mp_maxrounds then
                max_rounds = cvar.mp_maxrounds:get_int()
            end

            local half_round = math.floor(max_rounds / 2)

            -- First pistol + second-half pistol
            if rounds_played ~= nil then
                if rounds_played == 0 or rounds_played == half_round then
                    return true
                end
            end

            -- Fallback for normal pistol money
            return money ~= nil and money <= 800
        end

        client.set_event_callback("player_spawn", function (e)
            if client.userid_to_entindex(e.userid) ~= entity.get_local_player() then
                return
            end

            client.delay_call(0.5, function ()
                local lp = entity.get_local_player()
                if not lp then return end

                local money = entity.get_prop(lp, "m_iAccount") or 0

                if not buy_bot.enabled:get() then
                    return
                end

                if buy_bot.skip_pistol:get() and is_pistol_round(money) then
                    return
                end

                if money <= 800 then
                    return
                end
    
                local buy = ''
                local primary = buy_bot.primary:get()
                local secondary = buy_bot.secondary:get()
                local util = buy_bot.utility:get()
    
                buy = primary == 'None' and buy or buy .. 'buy ' .. primary_console[primary] .. '; '
                buy = secondary == 'None' and buy or buy .. 'buy ' .. secondary_console[secondary] .. '; '
    
                for i = 1, #util do
                    local item = utility_console[ util[i] ]
                    buy = buy .. "buy " .. item .. "; "
                end
    
                if buy == '' then
                    return
                end
    
                client.exec(buy)
            end)
        end)
    end

    client.set_event_callback("net_update_end", exploit.handle_defensive)
    client.set_event_callback("net_update_end", exploit.net_update)
    client.set_event_callback("net_update_end", localplayer.net_update)
    client.set_event_callback("shutdown", gui.shutdown)
    client.set_event_callback("shutdown", antiaim.shutdown)

    client.set_event_callback("paint_ui", gui.frame)
    client.set_event_callback("paint_ui", windows.frame)

    client.set_event_callback("paint_ui", manual_direction.frame)
    client.set_event_callback("paint_ui", antiaim.frame)

    client.set_event_callback("paint_ui", watermark.frame)
    client.set_event_callback("paint_ui", keybinds.frame)
    client.set_event_callback("paint_ui", indicators.frame)
    client.set_event_callback("paint_ui", arrows.frame)
    client.set_event_callback("paint_ui", velocity_warning.frame)
    client.set_event_callback("paint_ui", hit_marker.frame)

    client.set_event_callback("paint_ui", eventlogs.pre_frame)
    client.set_event_callback("paint_ui", log_aimbot_shots.frame)
    client.set_event_callback("paint_ui", eventlogs.post_frame)

    client.set_event_callback("pre_predict_command", localplayer.pre_predict_command)
    client.set_event_callback("predict_command", localplayer.predict_command)

    client.set_event_callback("setup_command", exploit.setup_command)
    client.set_event_callback("setup_command", statement.setup_command)
    client.set_event_callback("setup_command", antiaim.setup_command)

    client.set_event_callback("aim_miss", log_aimbot_shots.aim_miss)

    client.set_event_callback("aim_hit", hit_marker.aim_hit)
    client.set_event_callback("aim_fire", hit_marker.aim_fire)
    client.set_event_callback("aim_fire", antiaim.aa_overlap_aim_fire)

    client.set_event_callback("player_hurt", log_aimbot_shots.player_hurt)
    client.set_event_callback("round_prestart", hit_marker.round_prestart)

    menu.set_callback(function()
        gui.enabled:display()
    
        if not gui.enabled:get() then
            return
        end
    
        shared.online_label:display()
        gui.selection:display()
    
        if gui.selection:get() == "Home" then
    
            graphics.config_export:display()
            graphics.config_import:display()
            graphics.config_default:display()
        end
    
        if gui.selection:get() == "Settings" then
    
            air_exploit.enabled:display()
    
            if air_exploit.enabled:get() then
                air_exploit.key:display()
                air_exploit.ticks:display()
            end
    
            settings.tweaks_enable:display()
    
            if settings.tweaks_enable:get() then
                settings.tweaks:display()
            end
    
            -- do
            --     hitchance.enabled:display()
    
            --     if hitchance.enabled:get() then
            --         hitchance.weapon_list:display()
    
            --         for _, weapon in next, hitchance.weapons do
            --             if hitchance.weapon_list:get() == weapon then
            --                 hitchance['Enabled_' .. weapon]:display()
    
            --                 if hitchance['Enabled_' .. weapon]:get() then
            --                     hitchance['Modes_' .. weapon]:display()
    
            --                     if hitchance['Modes_' .. weapon]:have_key('No Scope') then
            --                         hitchance['Distance_' .. weapon]:display()
            --                         hitchance['No Scope_' .. weapon]:display()
            --                     end
    
            --                     if hitchance['Modes_' .. weapon]:have_key('In Air') then
            --                         hitchance['In Air_' .. weapon]:display()
            --                     end
            --                 end
            --             end
            --         end
            --     end
            -- end
    
            shared.enabled:display()
    
            widgets.enabled:display()
    
            if widgets.enabled:get() then
                widgets.items:display()
    
                if widgets.items:have_key("Watermark") then
                    widgets.display:display()
                    widgets.custom_name:display()
    
                    if widgets.custom_name:get() then
                        widgets.custom_name_value:display()
                    end
                end
    
                if #widgets.items:get() > 0 then
                    widgets.color_picker:display()
                end
            end
    
            custom_scope.enabled:display()
    
            if custom_scope.enabled:get() then
                custom_scope.color:display()
                custom_scope.mode:display()
                custom_scope.position:display()
                custom_scope.offset:display()
            end
    
            buy_bot.enabled:display()
    
            if buy_bot.enabled:get() then
                buy_bot.skip_pistol:display()
                buy_bot.primary:display()
                buy_bot.secondary:display()
                buy_bot.utility:display()
            end
    
            clientside_nickname.enabled:display()
    
            if clientside_nickname.enabled:get() then
                clientside_nickname.nickname:display()
                clientside_nickname.apply:display()
            end
        end
    
        if gui.selection:get() == "Anti-aim" then
    
            safe_head.enabled:display()
    
            aa_tweaks.enable:display()
            if aa_tweaks.enable:get() then
                aa_tweaks.items:display()
            end
    
    
            antiaim.overlap.enabled:display()
            if antiaim.overlap.enabled:get() then
                antiaim.overlap.onshot:display()
                if antiaim.overlap.onshot:get() then
                    antiaim.overlap.onshot_mode:display()
                    antiaim.overlap.onshot_limit:display()
                    antiaim.overlap.onshot_hold:display()
                end

                antiaim.overlap.disable_jitter:display()
                antiaim.overlap.avoid_real_fake:display()
                if antiaim.overlap.avoid_real_fake:get() then
                    antiaim.overlap.min_real_fake_gap:display()
                end
                antiaim.overlap.debug:display()
            end

            fs_disablers.states:display()
    
            if safe_head.enabled:get() then
                safe_head.states:display()
            end
    
            yaw_direction.edge_yaw:display()
            yaw_direction.freestanding:display()
    
            manual_direction.enabled:display()
    
            if manual_direction.enabled:get() then
                manual_direction.options:display()
                manual_direction.arrows:display()
    
                if manual_direction.arrows:get() then
                    manual_direction.color:display()
                end
    
                manual_direction.left_manual:display()
                manual_direction.right_manual:display()
                manual_direction.forward_manual:display()
                manual_direction.disabled_manual:display()
            end
    
            defensive.enabled:display()
            anim_breakers.enabled:display()
    
    
            if anim_breakers.enabled:get() then
                anim_breakers.ground:display()
                anim_breakers.air:display()
            end
    
            if defensive.enabled:get() then
                defensive.mode:display()
                defensive.state:display()
                defensive.pitch:display()
                defensive.yaw:display()
            end
    
            angles.type:display()
    
            if angles.type:get() == "Custom" then
                angles.custom.state:display()
    
                local state = angles.custom.state:get()
                local list = angles.custom[state]
    
                if list.enabled ~= nil then
                    list.enabled:display()
    
                    if not list.enabled:get() then
                        goto continue
                    end
                end
    
                if list.pitch ~= nil then
                    local pitch = list.pitch:get()
                    list.pitch:display()
    
                    if pitch == "Custom" then
                        list.pitch_offset:display()
                    end
                end
    
                if list.yaw_base ~= nil then
                    list.yaw_base:display()
                end
    
                local yaw_value = list.yaw:get()
                list.yaw:display()
    
                if yaw_value ~= "Off" then
    
                    if yaw_value == '180 LR' then
                        list.yaw_180lr_mode:display()
                        list.yaw_left:display()
                        list.yaw_right:display()
    
                        if list.yaw_180lr_mode:get() == 'Switch delay' then
                            list.yaw_delay:display()
                        end
                    else
                        list.yaw_offset:display()
                    end
    
                    list.yaw_jitter:display()
    
                    if list.yaw_jitter:get() ~= "Off" then
                        list.jitter_offset:display()
                        list.jitter_randomization:display()
    
                        if list.yaw_jitter:get() == "Guardian" then
                            list.jitter_mode:display()
                            list.acid_safe:display()
                            list.acid_cycle:display()
                            list.acid_delay:display()
    
                            ui.set_enabled(list.acid_delay.ref, list.acid_cycle:get() ~= 5)
                        end
                    end
                end
    
                local body_yaw = list.body_yaw:get()
                list.body_yaw:display()
    
                if body_yaw ~= "Off" then
                    if body_yaw ~= "Opposite" then
                        list.body_yaw_offset:display()
                    end
    
                    list.freestanding_body_yaw:display()
                end
    
                ::continue::
            end
        end
    end)
    
    menu.update()

    return {
        stop = function()
            gui.enabled:set(false)
            antiaim.shutdown()
            air_exploit.backups()
            override.clear()
            gui.shutdown()

            ui.set(software.visuals.scope_overlay, true)
            cvar.con_filter_enable:set_raw_int(0)
            client.set_clan_tag("")

            if shared.socket then
                pcall(function() shared.socket:close() end)
                shared.socket = nil
            end
            pcall(shared.attach, true)

            local items = menu.get_items()
            for i = 1, #items do
                pcall(ui.set_visible, items[i].ref, false)
            end
        end
    }
end)()
