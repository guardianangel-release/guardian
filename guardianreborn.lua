local pui = require("gamesense/pui")
local base64 = require "gamesense/base64"
local json = require "json"
local vector = require "vector"
local ffi = require "ffi"
local c_entity = require "gamesense/entity"
local exploits = require "gamesense/extended_exploits"

local math_floor = math.floor
local math_sqrt = math.sqrt
local math_abs = math.abs
local math_min = math.min
local math_max = math.max
-- ============================================================================
-- FFI DEFINITIONS
-- ============================================================================
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

-- ============================================================================
-- CORE UTILITIES & CONTEXT BALANCERS
-- ============================================================================
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
    for i=1, #tbl do if tbl[i] == val then return true end end
    return false
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
    return normalize_angle(a - b)
end

local function create_circular_buffer(size)
    return {
        data = {}, index = 1, size = size, max_index = 0,
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
            for i = 0, self.max_index - 1 do table.insert(result, self:get(i)) end
            return result
        end,
        clear = function(self) self.data = {}; self.index = 1; self.max_index = 0 end
    }
end

-- ============================================================================
-- CLEAN PUI MENU INTERFACE ARCHITECTURE
-- ============================================================================
local groups = {
    main = pui.group("RAGE", "Other", "Guardian"),
    resolver = pui.group("RAGE", "Other", "Resolver"),
    defensive = pui.group("RAGE", "Other", "Defensive"),
    rage = pui.group("RAGE", "Other", "Ragebot"),
    visuals = pui.group("RAGE", "Other", "Visuals"),
    config = pui.group("RAGE", "Other", "Config")
}

local ui = {}

ui.enable = groups.main:checkbox("Enable Guardian Enhanced")
ui.accent = groups.main:color_picker("Accent Color", 100, 200, 255, 255)
ui.tabs = groups.main:combobox("Tab", {"Home", "Resolver", "Anti-Aim", "Rage", "Visuals", "Config"})

-- Home Tab Configuration
ui.home = {}
ui.home.info = groups.main:label("Guardian Enhanced")
ui.home.mode = groups.main:combobox("Resolver Mode", {"Automatic", "AI", "Adaptive", "Bruteforce", "Smart", "Override"})
ui.home.indicator = groups.main:checkbox("Show Indicators")

-- Resolver Tab Configuration
ui.resolver = {}
ui.resolver.detection = groups.resolver:multiselect("Detection Methods", {
    "Animation Analysis", "Movement Tracking", "LBY Analysis", "Velocity Prediction",
    "Pose Parameters", "Layer Weight", "Micro Movement", "Standing Detection", 
    "Pattern Recognition", "Desync Break Detection"
})
ui.resolver.brute_mode = groups.resolver:combobox("Brute Mode", {"Sequential", "Random", "Smart", "Adaptive", "Intelligent"})
ui.resolver.brute_phases = groups.resolver:slider("Brute Phases", 2, 7, 5, true)
ui.resolver.brute_reset = groups.resolver:slider("Reset After", 1, 5, 3, true)
ui.resolver.advanced = groups.resolver:multiselect("Advanced Features", {
    "Anti-Freestand", "Body Aim Fix", "Low Delta Detect", "Jitter Detection",
    "Micro Movement", "Standing Resolver", "Smart Prediction", "Animation Fix",
    "Pattern Analysis", "Context Awareness", "Peek Prediction", "Adaptive Learning", "Weapon Awareness"
})
ui.resolver.override_left = groups.resolver:hotkey("Force Left")
ui.resolver.override_right = groups.resolver:hotkey("Force Right")
ui.resolver.override_center = groups.resolver:hotkey("Force Center")
ui.resolver.desync_strength = groups.resolver:slider("Desync Strength", 1, 100, 60, true, "%")
ui.resolver.confidence = groups.resolver:slider("Confidence Threshold", 50, 100, 75, true, "%")
ui.resolver.reaction_time = groups.resolver:slider("Reaction Time", 0, 100, 20, true, "ms")
ui.resolver.ai_aggression = groups.resolver:slider("AI Aggression", 0, 100, 50, true, "%")
ui.resolver.ai_learning = groups.resolver:slider("AI Learning Rate", 0, 100, 75, true, "%")

-- Defensive Tab Configuration
ui.defensive = {}
ui.defensive.enable = groups.defensive:checkbox("Defensive Resolver")
ui.defensive.options = groups.defensive:multiselect("Defensive Options", {
    "Simulation Check", "Lag Compensation", "Velocity Exploit", "Teleport Detection", 
    "Smart Backtrack", "Prediction Fix", "Layer Correlation"
})
ui.defensive.peek_fix = groups.defensive:checkbox("Force Defensive on Peek")
ui.defensive.peek_time = groups.defensive:slider("Peek Prediction", 50, 500, 250, true, "ms")
ui.defensive.peek_min_damage = groups.defensive:slider("Minimum Peek Damage", 10, 100, 25, true, "hp")
ui.defensive.peek_auto_enable = groups.defensive:multiselect("Auto-Enable Weapons", {
    "Enemy has AWP", "Enemy has Scout", "You have AWP/Scout", "Low health (<50HP)"
})
ui.defensive.delay_head = groups.defensive:checkbox("Delay Head Until Safe (Experimental)")

-- Rage Tab Configuration
ui.rage = {}
ui.rage.smart_baim = groups.rage:checkbox("Smart Body Aim")
ui.rage.mode = groups.rage:combobox("Playstyle Presets", {"Default", "Aggressive", "Defensive"})
ui.rage.lethal_enable = groups.rage:checkbox("Force Body on Lethal")
ui.rage.lethal_threshold = groups.rage:slider("Lethal HP Threshold", 1, 100, 80, true, "hp")
ui.rage.accuracy_threshold = groups.rage:slider("Min Shot Accuracy", 0, 100, 75, true, "%")
ui.rage.lethal_mode = groups.rage:combobox("Lethal Behavior", {"Force body (strict)", "Prefer body (flexible)", "Smart (adjust by accuracy)"})
ui.rage.lethal_override_mindmg = groups.rage:checkbox("Override Min Damage on Lethal (Scout Only)")
ui.rage.ideal_tick = groups.rage:checkbox("Ideal Tick Detection")
ui.rage.smart_fakelag = groups.rage:checkbox("Smart Fakelag Optimizer")
ui.rage.predictive_autostop = groups.rage:checkbox("Predictive Autostop [EXPERIMENTAL]")

-- Visuals Tab Configuration
ui.visuals = {}
ui.visuals.clantag = groups.visuals:checkbox("Clantag")
ui.visuals.watermark = groups.visuals:checkbox("Watermark Rendering")
ui.visuals.watermark_color = groups.visuals:color_picker("Watermark Color", 150, 200, 255, 255)
ui.visuals.indicator_style = groups.visuals:combobox("Indicator Style", {"Simple", "Detailed", "Minimal", "Debug", "Analytics", "Weapon Info"})
ui.visuals.resolver_flags = groups.visuals:checkbox("Resolver ESP Flags")
ui.visuals.show_lethal_flag = groups.visuals:checkbox("Show Lethal ESP Flag")
ui.visuals.lethal_flag_style = groups.visuals:combobox("Lethal Flag Style", {"Simple", "Detailed", "Box highlight", "All"})
ui.visuals.lethal_flag_color = groups.visuals:color_picker("Lethal Flag Color", 255, 0, 0, 255)
ui.visuals.debug = groups.visuals:checkbox("Debug Core Overlay")
ui.visuals.console_log = groups.visuals:checkbox("Console Internal Logging")
ui.visuals.killsay = groups.visuals:checkbox("Guardian Killsay")

-- Config Tab Configuration
ui.config = {}
ui.config.preset = groups.config:combobox("Config Preset", {"Custom", "Default", "Aggressive", "Defensive"})
ui.config.description = groups.config:label("Select a preset configuration profile")
ui.config.load = groups.config:button("Load Selective Profile")
ui.config.export = groups.config:button("Export Configuration Matrix")
ui.config.import = groups.config:button("Import Configuration Matrix")

-- Dependencies Handling
pui.traverse({ui.resolver, ui.defensive, ui.rage, ui.visuals, ui.config}, function(item)
    item:depend(ui.enable)
end)

-- ============================================================================
-- GLOBAL TELEMETRY ENGINE ENVIRONMENT TRACKING
-- ============================================================================
ui.killsay_state = { phrases = {
    "𝕝𝕚𝕗𝕖 𝕚𝕤 𝕒 𝕘𝕒𝕞𝕖, 𝕤𝕥𝕖𝕒𝕞 𝕝𝕖𝕧𝕖𝕝 𝕚𝕤 𝕙𝕠𝕨 𝕨𝕖 𝕜𝕖𝕖𝕡 𝕥𝕙𝕖 𝕤𝕔𝕠𝕣𝕖 ♛ 𝕞𝕒𝕜𝕖 𝕣𝕚𝕔𝕙 𝕞𝕒𝕚𝕟𝕤, 𝕟𝕠𝕥 𝕗𝕣𝕚𝕖𝕟𝕕𝕤",
    "𝙒𝙝𝙚𝙣 𝙄'𝙢 𝙥𝙡𝙖𝙮 𝙈𝙈 𝙄'𝙢 𝙥𝙡𝙖𝙮 𝙛𝙤𝙧 𝙬𝙞𝙣, 𝙙𝙤𝙣'𝙩 𝙨𝙘𝙖𝙧𝙚 𝙛𝙤𝙧 𝙨𝙥𝙞𝙣, 𝙞 𝙞𝙣𝙟𝙚𝙘𝙩 𝙧𝙖𝙜𝙚 ♕",
    "𝒯𝒽𝑒 𝓅𝓇𝑜𝒷𝓁𝑒𝓂 𝒾𝓈 𝓉𝒽𝒶𝓉 𝒾 𝑜𝓃𝓁𝓎 𝒾𝓃𝒿𝑒𝒸𝓉 𝒸𝒽𝑒𝒶𝓉𝓈 𝑜𝓃 𝓂𝓎 𝓂𝒶𝒾𝓃 𝓉𝒽𝒶𝓉 𝒽𝒶𝓋𝑒 𝓃𝒶𝓂𝑒𝓈 𝓉𝒽𝒶𝓉 𝓈𝓉𝒶𝓇𝓉 𝓌𝒾𝓉𝒽 𝓰 𝒶𝓃𝒹 𝑒𝓃𝒹 𝓌𝒾𝓉𝒽 𝓪𝓶𝓮𝓼𝓮𝓷𝓼𝓮",
    "(◣◢) 𝕐𝕠𝕦 𝕒𝕨𝕒𝕝𝕝 𝕗𝕚𝕣𝕤𝕥? 𝕆𝕜 𝕝𝕖𝕥𝕤 𝕗𝕦𝕟 slightsmile (◣◢)",
    "ｉ ｃａｎｔ ｌｏｓｅ ｏｎ ｏｆｆｉｃｅ ｉｔ ｍｙ ｈｏｍｅ",
    "𝕞𝕒𝕚𝕟 𝕟𝕖𝕨= 𝕔𝕒𝕟 𝕓𝕦𝕪.. 𝕙𝕧𝕙 𝕨𝕚𝕟? 𝕕𝕠𝕟𝕥 𝕥𝕙𝕚𝕟𝕜 𝕚𝕞 𝕔𝕒𝕟, 𝕚𝕞 𝕝𝕠𝕒𝕕 𝕣𝕒𝕘𝕖 ♕",
    "♛Ａｌｌ   Ｆａｍｉｌｙ   ｉｎ   ｇｓ♛",
    "u will 𝕣𝕖𝕘𝕣𝕖𝕥 rage vs me when i go on ｌｏｌｚ．ｇｕｒｕ acc.",
    "𝔻𝕠𝕟𝕥 𝕒𝕕𝕕 𝕞𝕖 𝕥𝕠 𝕨𝕒𝕣 𝕠𝕟 𝕞𝕪 𝕤𝕞𝕦𝕣𝕗 (◣◢) 𝕘𝕒𝕞𝕖𝕤𝕖𝕟𝕤𝕖 𝕒𝕝𝕨𝕒𝕪𝕤 𝕣𝕖𝕒𝕕𝕪 ♛",
    "♛ 𝓽𝓾𝓻𝓴𝓲𝓼𝓱 𝓽𝓻𝓾𝓼𝓽 𝓯𝓪𝓬𝓽𝓸𝓻 ♛",
    "𝕕𝕦𝕞𝕓 𝕕𝕠𝕘, 𝕪𝕠𝕦 𝕒𝕨𝕒𝕜𝕖 𝕥𝕙𝕖 ᴅʀᴀɢᴏɴ ʜᴠʜ ᴍᴀᴄʜɪɴᴇ, 𝕟𝕠𝕨 𝕪𝕠𝕦 𝕝𝕠𝕤𝕖 𝙖𝙘𝙘 𝕒𝕟𝕕 𝚐𝚊𝚖𝚎 ♕",
    "♛ 𝕞𝕪 𝕙𝕧𝕙 𝕥𝕖𝕒𝕞 𝕚𝕤 𝕣𝕖𝕒𝕕𝕪 𝕘𝕠 𝟙𝕩𝟙 𝟚𝕩𝟚 𝟛𝕩𝟛 𝟜𝕩𝟜 𝟝𝕩𝟝 (◣◢)",
    "ᴀɢᴀɪɴ ɴᴏɴᴀᴍᴇ ᴏɴ ᴍʏ ꜱᴛᴇᴀᴍ ᴀᴄᴄᴏᴜɴᴛ. ɪ ꜱᴇᴇ ᴀɢᴀɪɴ ᴀᴄᴛɪᴠɪᴛʏ.",
    "ɴᴏɴᴀᴍᴇ ʟɪꜱᴛᴇɴ ᴛᴏ ᴍᴇ ! ᴍʏ ꜱᴛᴇᴀᴍ ᴀᴄᴄᴏᴜɴᴛ ɪꜱ ɴᴏᴛ ʏᴏᴜʀ ᴘʀᴏᴘᴇʀᴛʏ.",
    "𝙋𝙤𝙤𝙧 𝙖𝙘𝙘 𝙙𝙤𝙣’𝙩 𝙘𝙤𝙢𝙢𝙚𝙣𝙩 𝙥𝙡𝙚𝙖𝙨𝙚 ♛",
    "𝕥𝕣𝕪 𝕥𝕠 𝕥𝕖𝕤𝕥 𝕞𝕖? (◣◢) 𝕞𝕪 𝕞𝕚𝕕𝕕𝕝𝕖 𝕟𝕒𝕞𝕖 𝕚𝕤 𝕘𝕖𝕟𝕦𝕚𝕟𝕖 𝕡𝕚𝕟 ♛",
    "𝓭𝓸𝓷𝓽 𝓝𝓝",
    "𝐻𝒱𝐻 𝐿𝑒𝑔𝑒𝓃𝒹𝑒𝓃 𝟤𝟢𝟤𝟤 𝑅𝐼𝒫 𝐿𝒾𝓁 𝒫𝑒𝑒𝓅 & 𝒳𝓍𝓍𝓉𝑒𝒶𝓃𝒸𝒾𝑜𝓃 & 𝒥𝓊𝒾𝒸𝑒 𝒲𝓇𝓁𝒹",
    "𝕚 𝕘𝕤 𝕦𝕤𝕖𝕣, 𝕟𝕠 𝕘𝕤 𝕟𝕠 𝕥𝕒𝕝𝕜",
    "𝐨𝐮𝐫 𝐥𝐢𝐟𝐞 𝐦𝐨𝐭𝐨 𝐢𝐬 𝐖𝐈𝐍 > 𝐀𝐂𝐂",
    "𝕗𝕦𝕔𝕜 𝕪𝕠𝕦𝕣 𝕗𝕒𝕞𝕚𝕝𝕪 𝕒𝕟𝕕 𝕗𝕣𝕚𝕖𝕟𝕕𝕤, 𝕜𝕖𝕖𝕡 𝕥𝕙𝕖 𝕤𝕥𝕖𝕒𝕞 𝕝𝕖𝕧𝕖𝕝 𝕦𝕡 ♚",
    "𝚜𝚎𝚖𝚒𝚛𝚊𝚐𝚎 𝚝𝚒𝚕𝚕 𝚢𝚘𝚞 𝚍𝚒𝚎, 𝚋𝚞𝚝 𝚠𝚎 𝚕𝚒𝚟𝚎 𝚏𝚘𝚛𝚎𝚟𝚎𝚛 (◣◢)",
    "𝔂𝓸𝓾 𝓭𝓸𝓷𝓽 𝓷𝓮𝓮𝓭 𝓯𝓻𝓲𝓮𝓷𝓭𝓼 𝔀𝓱𝓮𝓷 𝔂𝓸𝓾 𝓱𝓪𝓿𝓮 𝓰𝓪𝓶𝓮𝓼𝓮𝓷𝓼𝓮",
    "-ᴀᴄᴄ? ᴡʜᴏ ᴄᴀʀꜱ ɪᴍ ʀɪᴄʜ ʜʜʜʜʜʜ",
    "𝚢𝚘𝚞 𝚊𝚠𝚊𝕝𝕝 𝚏𝚒𝚛𝚜𝚝? 𝚘𝚔 𝚕𝚎𝚝𝚜 𝚏𝚞𝚗 :)",
    "𝕤𝕠𝕣𝕣𝕪 𝕔𝕒𝕟𝕥 𝕙𝕖𝕒𝕣 𝕤𝕜𝕖𝕖𝕥𝕝𝕖𝕤𝕤",
    "𝔂𝓸𝓾 𝓬𝓪𝓶𝓽 𝓺𝓾𝓲𝓬𝓴 𝓹𝓮𝓪𝓴 𝓱𝓿𝓱 𝓴𝓲𝓷𝓰",
    "ｎｉｃｅ ｔｒｙ ｐｏｏｒ ｄｏｇ",
    "𝔸𝕃𝕃 𝔻𝕆𝔾𝕊 𝕃𝕆𝕊𝔼 𝕋𝕆 𝔾𝕊",
    "𝙼𝚈 𝙱𝙾𝚃𝙽𝙴𝚃 𝙳𝙾𝙴𝚂𝙽𝚃 𝙲𝙰𝚁𝙴 𝙰𝙱𝙾𝚄𝚃 𝚈𝙾𝚄𝚁 𝙵𝙴𝙴𝙻𝙸𝙽𝙶𝚂",
    "𝕚𝕟 𝟝𝕧𝕤𝟝 𝕚𝕞 𝕒𝕝𝕨𝕒𝕪𝕤 𝕤𝕡𝕖𝕒𝕜 𝕗𝕠𝕣 𝕥𝕖𝕒𝕞, 𝔻𝕆ℕ𝕋 𝕘𝕠𝕚𝕟𝕘 𝕗𝕠𝕣 𝕙𝕖𝕒𝕕𝕤, 𝔹𝕆𝔻𝕐𝔸𝕀𝕄𝕊, 𝕓𝕦𝕥 𝕕𝕠𝕘𝕤 𝕟𝕖𝕧𝕖𝕣 𝕨𝕒𝕟𝕥 𝕝𝕚𝕤𝕥𝕖𝕟",
    "Ｙｏｕｒ ｃｈｅａｔ ｉｓ ｎｏｔ ｔｈｅ ｐｒｏｂｌｅｍ， ｂｕｔ ｔｈａｔ ｙｏｕ ｗｅｒｅ ｂｏｒｎ．",
    "𝐓𝐡𝐞 𝐨𝐧𝐥𝐲 𝐭𝐡𝐢𝐧𝐠 𝐥𝐨𝐰𝐞𝐫 𝐭𝐡𝐚𝐧 𝐲𝐨𝐮𝐫 𝐤/𝐝 𝐫𝐚𝐭𝐢𝐨 𝐢𝐬 𝐲𝐨𝐮𝐫 𝐩𝐞𝐧𝐢𝐬 𝐬𝐢𝐳𝐞.",
    "˜”°•.˜”°• ʏᴏᴜʀ ᴍᴏᴛʜᴇʀ ᴡᴏᴜʟᴅ ʜᴀᴠᴇ ᴅᴏɴᴇ ʙᴇᴛᴛᴇʀ ᴛᴏ ꜱᴡᴀʟʟᴏᴡ ʏᴏᴜ. •°”˜.•°”˜",
    "𝓘 𝓯𝓾𝓬𝓴𝓮𝓭 𝔂𝓸𝓾 𝓾𝓹.",
    "ｙｏｕ ｔａｌｋ ｔｏｏ ｍｕｃｈ ｆｏｒ ａ ｌｉｔｔｌｅ ｂｏｙ",
    "ｔｒａｓｈ ｔａｌｋ ｌｕａ? ｈａｈａｈ ｙｏｕｒｅ ｍｏｔｈｅｒ ｔｒａｓｈ",
    "1Ҳ1 MƖƦƛƓЄ ƝЄᐯЄƦ ƠᐯЄƦƤƛƧƧ",
    "кεερ тɑlкιиg lιкε тнɑт ι'м ςlσѕε",
    "♛ 𝔻𝕠𝕟'𝕥 𝕘𝕖𝕥 𝕔𝕣𝕖𝕒𝕞𝕖𝕕 𝕚𝕗 𝕚 𝕓𝕣𝕖𝕒𝕜 𝕃ℂ ♛",
    "⌜guardian aa + guardian predict + guardian resolve BOSS MODE ONLINE⌝"
}, last_time = 0, last_index = 0 }

local resolver_data = {}
local lag_records = {}
local defensive_records = {}
local speed_cache = {}
local speed_cache_time = {}
local damage_cache = {}
local damage_cache_time = {}
local eye_angle_data = {}
local defensive_check_cache = {}
local defensive_check_time = {}
local resolver_cache = {}
local prev_simtime = {}

local entity_cache = {}
local entity_cache_time = {}
local ENTITY_CACHE_TICKS = 1
local CACHE_DURATION = 2
local DEFENSIVE_CACHE_DURATION = 4
local AA_CHECK_CACHE_DURATION = 32
local RESOLVER_CACHE_TICKS = 0

local last_target = nil
local last_mindmg_value = nil
local original_mindmg_per_weapon = {}
local last_weapon_id = nil
local last_peek_check = 0
local last_peek_result = false
local PEEK_CHECK_INTERVAL = 4
local lethal_flag_pulse = 0

local ref_mindmg = pui.reference("RAGE", "Aimbot", "Minimum damage")
local ref_mindmg_override_enable = pui.reference("RAGE", "Aimbot", "Minimum damage override")
local fakelag_ref = pui.reference("AA", "Fake lag", "Limit")
local f_duck_ref = pui.reference("RAGE", "Other", "Duck peek assist")

-- ============================================================================
-- HARDWARE INTERFACE CONNECTIONS
-- ============================================================================
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

-- ============================================================================
-- COMPREHENSIVE UTILITIES TRACKING RETRIEVERS
-- ============================================================================
local function get_cached_prop(ent, prop, default)
    local key = ent .. "_" .. prop
    local tick = globals.tickcount()
    
    -- If the array exists in cache, unpack all stored return channels
    if entity_cache[key] and (tick - (entity_cache_time[key] or 0)) < ENTITY_CACHE_TICKS then
        return unpack(entity_cache[key])
    end
    
    -- Capture every single return value dynamically into a data array
    local results = { entity.get_prop(ent, prop) }
    if results[1] == nil then results = { default } end
    
    entity_cache[key] = results
    entity_cache_time[key] = tick
    
    return unpack(results)
end

local function get_choke_from_simtime(player)
    local sim = entity.get_prop(player, "m_flSimulationTime")
    if not sim then return 0 end
    local last = prev_simtime[player]
    prev_simtime[player] = sim
    if not last then return 0 end
    local dt = sim - last
    if dt <= 0 then return 0 end
    local choke = math.floor(dt / globals.tickinterval())
    return choke < 0 and 0 or choke
end

local function get_player_speed_cached(player)
    local tick = globals.tickcount()
    if get_choke_from_simtime(player) > 5 then speed_cache[player] = nil end
    if speed_cache[player] and (tick - (speed_cache_time[player] or 0)) < CACHE_DURATION then
        return speed_cache[player]
    end
    local vx, vy = get_cached_prop(player, "m_vecVelocity", 0)
    local speed = (vx and vy) and math.sqrt(vx*vx + vy*vy) or 0
    speed_cache[player] = speed; speed_cache_time[player] = tick
    return speed
end

local function get_local_ping()
    local lat = client.latency()
    if not lat or lat <= 0 then return 50 end
    return math.min(math.floor(lat * 1000 + 0.5), 300)
end

local function get_player_ping(player)
    if not player then return 50 end
    local pr = entity.get_player_resource()
    if not pr then return 50 end
    local ping = entity.get_prop(pr, "m_iPing", player)
    if not ping or ping < 0 then return 50 end
    return math.min(ping, 300)
end

-- ============================================================================
-- ADVANCED MATH ANALYSIS SUBSYSTEMS
-- ============================================================================
local function calculate_angle_stats(angles)
    if #angles == 0 then return 0, 0 end
    local sum = 0
    for i = 1, #angles do sum = sum + angles[i] end
    local mean = sum / #angles
    local variance_sum = 0
    for i = 1, #angles do variance_sum = variance_sum + (angles[i] - mean) ^ 2 end
    return mean, math.sqrt(variance_sum / #angles)
end

local function calculate_variance(angles, mean)
    if #angles == 0 then return 0 end
    local variance_sum = 0
    for i = 1, #angles do variance_sum = variance_sum + (angles[i] - mean) ^ 2 end
    return variance_sum / #angles
end

local function detect_oscillation(angles, cycle_length)
    if #angles < cycle_length * 2 or cycle_length > 16 then return false end
    local patterns = {}
    for i = 1, #angles - cycle_length + 1 do
        local pattern = {}
        for j = 0, cycle_length - 1 do table.insert(pattern, angles[i + j]) end
        table.insert(patterns, pattern)
    end
    for i = 1, #patterns - 1 do
        local match = true
        for j = 1, cycle_length do
            if math.abs(patterns[i][j] - patterns[i + 1][j]) > 5 then match = false; break end
        end
        if match then return true end
    end
    return false
end

local function detect_consistent_side(angles, min_ticks)
    if #angles < min_ticks then return 0 end
    local pos, neg = 0, 0
    for i = 1, min_ticks do
        if angles[i] > 0 then pos = pos + 1 elseif angles[i] < 0 then neg = neg + 1 end
    end
    if pos >= min_ticks * 0.8 then return 1 elseif neg >= min_ticks * 0.8 then return -1 end
    return 0
end

-- ============================================================================
-- HVH SPECIFIC STRATEGY DATA ENGINES
-- ============================================================================
local function get_weapon_type(weapon_ent)
    if not weapon_ent then return "unknown" end
    local weapon_id = entity.get_prop(weapon_ent, "m_iItemDefinitionIndex")
    if not weapon_id then return "unknown" end
    if weapon_id == 9 then return "awp" end
    if weapon_id == 40 then return "scout" end
    if weapon_id == 11 or weapon_id == 38 then return "auto" end
    if weapon_id == 1 then return "deagle" end
    if weapon_id == 64 then return "revolver" end
    if contains({2, 3, 4, 30, 32, 36, 61, 63}, weapon_id) then return "pistol" end
    if contains({7, 8, 10, 13, 16, 39, 60}, weapon_id) then return "rifle" end
    if contains({17, 19, 24, 26, 33, 34}, weapon_id) then return "smg" end
    return "unknown"
end

local function count_teammates() return #(entity.get_players(false) or {}) end
local function count_enemies() return #(entity.get_players(true) or {}) end

local function get_nearest_site(x, y, z)
    local pr = entity.get_player_resource()
    if not pr then return nil end
    local ax, ay, az = entity.get_prop(pr, "m_bombsiteCenterA")
    local bx, by, bz = entity.get_prop(pr, "m_bombsiteCenterB")
    if not ax or not bx then return nil end
    return ((x-ax)^2 + (y-ay)^2 + (z-az)^2) < ((x-bx)^2 + (y-by)^2 + (z-bz)^2) and "A" or "B"
end

local function get_bomb_site(player)
    local x, y, z
    local bomb = entity.get_all("CPlantedC4")[1]
    if bomb then x, y, z = entity.get_prop(bomb, "m_vecOrigin")
    else
        local lp = entity.get_local_player()
        if lp then x, y, z = entity.get_prop(lp, "m_vecOrigin") end
    end
    if not x or not y or not z then return "unknown" end
    return get_nearest_site(x, y, z) or "unknown"
end

-- ============================================================================
-- ANTI-AIM JITTER STEP TRACKER (EXTRACTOR)
-- ============================================================================
local function extract_jitter_bounds(player, data, current_magnitude)
    if not data.jitter_magnitude_history then
        data.jitter_magnitude_history = {}
    end
    
    -- Insert current raw animation delta magnitude
    table.insert(data.jitter_magnitude_history, 1, current_magnitude)
    if #data.jitter_magnitude_history > 6 then
        table.remove(data.jitter_magnitude_history)
    end

    if #data.jitter_magnitude_history < 4 then
        return 58, 58 -- Default fallback until we have enough data samples
    end

    -- Isolate the two most frequent mathematical clusters in history
    local bound_a = data.jitter_magnitude_history[1]
    local bound_b = nil

    for i = 2, #data.jitter_magnitude_history do
        local val = data.jitter_magnitude_history[i]
        if math_abs(val - bound_a) > 4.5 then -- 4.5° variance threshold to identify a true state change
            bound_b = val
            break
        end
    end

    -- If no secondary bound is captured, the user isn't magnitude jittering
    if not bound_b then
        return bound_a, bound_a
    end

    -- Sort the bounds so bound_a always holds the wider magnitude extreme
    if bound_b > bound_a then
        bound_a, bound_b = bound_b, bound_a
    end

    return bound_a, bound_b
end

-- ============================================================================
-- DYNAMIC BODY YAW POSE PARAMETER EXTRACTION ENGINE
-- ============================================================================
local function get_dynamic_body_yaw(player)
    local by = entity.get_prop(player, "m_flPoseParameter", 11)
    if not by then return 0 end
    
    local ptr = get_entity_address(player)
    local anim = get_anim_state(ptr)
    
    local min_yaw = -60
    local max_yaw = 60
    
    if anim then
        min_yaw = anim.flMinBodyYaw
        max_yaw = anim.flMaxBodyYaw
    end
    
    -- Map the 0.0 to 1.0 pose parameter cleanly into the true structural bounds
    return by * (max_yaw - min_yaw) + min_yaw
end

-- ============================================================================
-- SPATIAL EXTRACTOR DAMAGE TRACKING LOGIC
-- ============================================================================
local function extrapolate_position(xpos, ypos, zpos, ticks, player, data)
    local x, y, z = get_cached_prop(player, "m_vecVelocity", 0)
    if not x or not y or not z then return xpos, ypos, zpos end
    
    local ax, ay, az = 0, 0, 0
    local records = lag_records[player]
    
    -- Use network packets directly to calculate realistic simulation-acceleration
    if records and #records >= 2 and records[1] and records[2] then
        local current = records[1]
        local previous = records[2]
        
        if current.simtime and previous.simtime and current.velocity and previous.velocity then
            -- Calculate the REAL time delta between network ticks instead of assuming 1 client tick
            local dt = current.simtime - previous.simtime
            
            -- Network Failsafe: Only calculate acceleration if a real update happened (dt > 0)
            -- and choke telemetry bounds to prevent anomalous ticks from corrupting values
            if dt > 0 and dt < 1.0 then
                local cv = current.velocity
                local pv = previous.velocity
                
                ax = (cv.x - pv.x) / dt
                ay = (cv.y - pv.y) / dt
                az = (cv.z - pv.z) / dt
            end
        end
    end
    
    local t = ticks * globals.tickinterval()
    
    -- Physics Kinematic Engine: s = ut + 0.5at^2
    return xpos + (x * t) + (0.5 * ax * t * t), 
           ypos + (y * t) + (0.5 * ay * t * t), 
           zpos + (z * t) + (0.5 * az * t * t)
end

local function get_adaptive_extrapolation_ticks(player, data)
    local ping = entity.get_prop(player, "m_iPing")
    if not ping then return 4 end
    return math.min(4 + math.floor((ping + get_local_ping()) / 30) + math.min(get_choke_from_simtime(player) / 2, 4), 12)
end

local baim_hitboxes = {3, 4, 5, 6}
local function calculate_body_damage(ent, localplayer)
    local tick = globals.tickcount()
    if damage_cache[ent] and (tick - (damage_cache_time[ent] or 0)) < CACHE_DURATION then return damage_cache[ent] end
    local final_damage = 0
    local eyepos_x, eyepos_y, eyepos_z = client.eye_position()
    if not eyepos_x then return 0 end
    
    local data = resolver_data[ent] or {}
    eyepos_x, eyepos_y, eyepos_z = extrapolate_position(eyepos_x, eyepos_y, eyepos_z, get_adaptive_extrapolation_ticks(ent, data), localplayer, data)
    
    for _, v in pairs(baim_hitboxes) do
        local hx, hy, hz = entity.hitbox_position(ent, v)
        if hx then
            local _, dmg = client.trace_bullet(localplayer, eyepos_x, eyepos_y, eyepos_z, hx, hy, hz, true)
            if dmg and dmg > final_damage then final_damage = dmg end
        end
    end
    if final_damage < 50 then
        local hx, hy, hz = entity.hitbox_position(ent, 2)
        if hx then
            local _, dmg = client.trace_bullet(localplayer, eyepos_x, eyepos_y, eyepos_z, hx, hy, hz, true)
            if dmg and dmg > final_damage then final_damage = dmg end
        end
    end
    damage_cache[ent] = final_damage; damage_cache_time[ent] = tick
    return final_damage
end

-- ============================================================================
-- SYSTEM STABILIZERS DEFENSIVE PEEK PREDICTIONS
-- ============================================================================
local function should_force_defensive_peek()
    if not ui.defensive.peek_fix:get() then return false end
    
    local tickcount = globals.tickcount()
    if tickcount - last_peek_check < PEEK_CHECK_INTERVAL then return last_peek_result end
    
    local local_player = entity.get_local_player()
    if not local_player or not entity.is_alive(local_player) then
        last_peek_result = false; last_peek_check = tickcount; return false
    end
    
    local auto_enable = ui.defensive.peek_auto_enable:get()
    local should_auto_enable = false
    local enemies = entity.get_players(true)
    
    if #auto_enable > 0 then
        if contains(auto_enable, "Low health (<50HP)") and (entity.get_prop(local_player, "m_iHealth") or 100) < 50 then 
            should_auto_enable = true 
        elseif contains(auto_enable, "You have AWP/Scout") then
            local w_type = get_weapon_type(entity.get_player_weapon(local_player))
            if w_type == "awp" or w_type == "scout" then should_auto_enable = true end
        end
        
        if not should_auto_enable and enemies and (contains(auto_enable, "Enemy has AWP") or contains(auto_enable, "Enemy has Scout")) then
            for i = 1, #enemies do
                if entity.is_alive(enemies[i]) then
                    local ew_type = get_weapon_type(entity.get_player_weapon(enemies[i]))
                    if (contains(auto_enable, "Enemy has AWP") and ew_type == "awp") or (contains(auto_enable, "Enemy has Scout") and ew_type == "scout") then
                        should_auto_enable = true; break
                    end
                end
            end
        end
        
        if not should_auto_enable then
            last_peek_result = false; last_peek_check = tickcount; return false
        end
    end
    
    if not enemies or #enemies == 0 then
        last_peek_result = false; last_peek_check = tickcount; return false
    end
    
    local eye_x, eye_y, eye_z = client.eye_position()
    if not eye_x then
        last_peek_result = false; last_peek_check = tickcount; return false
    end
    
    local vx, vy, vz = entity.get_prop(local_player, "m_vecVelocity")
    if not vx then last_peek_result = false; last_peek_check = tickcount; return false end
    
    -- Cache tick values to prevent multiple C++ API boundary calls
    local tickinterval = globals.tickinterval()
    local pred_ticks = math_floor(ui.defensive.peek_time:get() / (tickinterval * 1000))
    local time_pred = tickinterval * pred_ticks
    
    -- Flat variable calculation instead of table allocation
    local p_eye_x = eye_x + (vx * time_pred)
    local p_eye_y = eye_y + (vy * time_pred)
    local p_eye_z = eye_z + (vz * time_pred)
    
    local min_dmg = ui.defensive.peek_min_damage:get()
    
    for i = 1, #enemies do
        local player = enemies[i]
        if entity.is_alive(player) then
            local evx, evy, evz = entity.get_prop(player, "m_vecVelocity")
            local hx, hy, hz = entity.hitbox_position(player, 0)
            
            if evx and hx then
                -- Flat variable calculation for prediction
                local p_head_x = hx + (evx * time_pred)
                local p_head_y = hy + (evy * time_pred)
                local p_head_z = hz + (evz * time_pred)
                
                local frac, ent = client.trace_line(local_player, p_eye_x, p_eye_y, p_eye_z, p_head_x, p_head_y, p_head_z)
                if frac < 1.0 and ent == player then
                    local _, damage = client.trace_bullet(local_player, p_eye_x, p_eye_y, p_eye_z, p_head_x, p_head_y, p_head_z)
                    if damage and damage >= min_dmg then
                        last_peek_result = true; last_peek_check = tickcount; return true
                    end
                end
            end
        end
    end
    
    last_peek_result = false; last_peek_check = tickcount; return false
end

-- ============================================================================
-- SYSTEM SUBSURFACE INTERNAL DATA LAYOUT MANAGEMENT
-- ============================================================================
local function init_player_data(player)
    if resolver_data[player] then return resolver_data[player] end
    resolver_data[player] = {
        misses = 0, hits = 0, shots = 0, hit_rate = 0, brute_phase = 1, brute_locked = false, brute_working = false,
        last_update = globals.tickcount(), last_resolve = 0, desync_side = 0, predicted_side = 0, last_lby = 0,
        lby_delta = 0, last_simtime = 0, last_velocity = {x = 0, y = 0, z = 0}, standing_ticks = 0, moving_ticks = 0,
        confidence = 0, reliability = 0, is_defensive = false, defensive_ticks = 0, defensive_active = false,
        resolved_angle = 0, body_yaw = 0, last_layers = {}, last_anim_state = nil, last_position = nil,
        movement_delta = 0, layer_data = { move_weight = 0, move_cycle = 0, stand_cycle = 0 }, recent_angles = {},
        patterns = { oscillation = false, consistent_side = 0, mean_angle = 0, variability = 0 },
        method_weights = { lby_delta = 0.25, movement = 0.20, animation = 0.15, velocity = 0.15, historical = 0.15, pattern = 0.10 },
        last_successful_method = "", last_failed_method = "", recent_positions = {}, predicted_position = nil,
        movement_acceleration = 0, fake_desync_detected = false, true_lby = 0, last_lby_update = 0,
        brute_patterns = { sequential = {phases = {}, success_rate = 0}, random = {phases = {}, success_rate = 0}, smart = {phases = {}, success_rate = 0}, adaptive = {phases = {}, success_rate = 0} },
        layer_correlations = {}, suspicious_animation = false, resolver_context = "balanced", likely_peek_type = "unknown",
        peek_aggression = 0.5, expected_desync = "unknown", 
        analytics = { method_success = {}, angle_success = {}, timing_success = {}, total_resolves = 0, successful_resolves = 0, overall_success_rate = 0 },
        learning_phase = "initial", brute_aggression = 0.5, player_profile = { playstyle = "unknown", desync_habits = {}, movement_patterns = {} },
        weapon_threat = 50, current_weapon = "unknown",
        reliable_angles = { left_angles = {}, right_angles = {}, last_reliable_angle = 0, last_reliable_tick = 0, confidence_threshold = 70 },
        peek_state = { last_speed = 0, last_direction = 0, acceleration = 0, direction_changes = 0, peek_type = "none", peek_confidence = 0 },
        body_aimable = false, body_aim_priority = false, health_threshold = 100, last_damage_dealt = 0, lethal_shot_available = false,
        lethal_mindmg_override = nil, lethal_mindmg_required = nil, estimated_body_damage = 0, last_shot_time = 0, shot_accuracy = 100,
        last_known_health = nil, shot_snapshot_angle = 0, shot_snapshot_time = 0, last_weapon_shot_time = 0,
        choke_history = create_circular_buffer(10), choke_stability = 1.0, pose_history = create_circular_buffer(5),
        jitter_detected = false, jitter_side_preference = 0, layer6_weight_history = {}, last_lby_update_time = 0,
        lby_update_imminent = false, brute_phase_success = { [1] = {hits = 0, time = 0, misses = 0}, [2] = {hits = 0, time = 0, misses = 0}, [3] = {hits = 0, time = 0, misses = 0}, [4] = {hits = 0, time = 0, misses = 0}, [5] = {hits = 0, time = 0, misses = 0} },
        hitgroup_angles = {}, preferred_head_angle = 0, velocity_history = create_circular_buffer(8), predicted_flip_angle = 0,
        flip_predicted = false, flip_predict_time = 0, last_resolved_side = 0, last_eye_angles = nil, defensive_flick_detected = false,
        last_good_angle = 0, defensive_suspicious = false, defensive_suspicion_score = 0, local_ping = 50, effective_ping = 50,
        air_state = nil, crouch_state = nil, sim_history = {}, pitch_history = {}, pitch_exploit_detected = false
    }
    return resolver_data[player]
end

local function init_lag_record(player)
    if not lag_records[player] then lag_records[player] = {} end
    
    local vx, vy, vz = get_cached_prop(player, "m_vecVelocity", 0)
    
    table.insert(lag_records[player], 1, {
        time = globals.curtime(), 
        tickcount = globals.tickcount(), 
        origin = { entity.get_prop(player, "m_vecOrigin") },
        velocity = { x = vx or 0, y = vy or 0, z = vz or 0 }, 
        simtime = entity.get_prop(player, "m_flSimulationTime"),
        lby = entity.get_prop(player, "m_flLowerBodyYawTarget"), 
        layers = nil, 
        anim_state = nil
    })
    while #lag_records[player] > 16 do table.remove(lag_records[player]) end
end

-- ============================================================================
-- ADAPTIVE HITBOX MATRIX MANAGEMENT AND OVERRIDES
-- ============================================================================
local function get_local_weapon_id()
    local me = entity.get_local_player()
    if not me or not entity.is_alive(me) then return nil end
    local weapon = entity.get_player_weapon(me)
    return weapon and entity.get_prop(weapon, "m_iItemDefinitionIndex") or nil
end

local function save_current_mindmg()
    local weapon_id = get_local_weapon_id()
    if not weapon_id or not ref_mindmg then return end
    if last_mindmg_value == nil then original_mindmg_per_weapon[weapon_id] = ref_mindmg:get() end
end

local function restore_mindmg()
    local weapon_id = get_local_weapon_id()
    if not weapon_id or not ref_mindmg then return end
    local saved = original_mindmg_per_weapon[weapon_id]
    if saved then ref_mindmg:set(saved) end
end

local function calculate_shot_accuracy(player)
    local local_player = entity.get_local_player()
    if not local_player then return 100 end
    local weapon = entity.get_player_weapon(local_player)
    if not weapon then return 100 end
    return math.max(0, 100 - ((entity.get_prop(weapon, "m_fAccuracyPenalty") or 0) * 200))
end

local function update_weapon_priority(player, data)
    local weapon_type = get_weapon_type(entity.get_player_weapon(player))
    local priority = { ["awp"] = 90, ["scout"] = 85, ["auto"] = 80, ["deagle"] = 75, ["revolver"] = 70, ["rifle"] = 65, ["pistol"] = 60, ["smg"] = 50, ["unknown"] = 50 }
    data.weapon_threat = priority[weapon_type] or 50
    data.current_weapon = weapon_type
end

local function should_delay_shot(player, data)
    if exploits:in_recharge() or exploits:is_lagcomp_broken() then return true end
    if data.last_shot_time and (globals.curtime() - data.last_shot_time) < 0.2 then
        if calculate_shot_accuracy(player) < ui.rage.accuracy_threshold:get() then return true end
    end
    return false
end

local function get_resolver_context(player)
    if not player or not entity.is_alive(player) then return "balanced" end
    local rules = entity.get_game_rules()
    local start, planted = 0, false
    if rules then
        start = entity.get_prop(rules, "m_fRoundStartTime") or 0
        planted = entity.get_prop(rules, "m_bBombPlanted") or false
    end
    local hp = get_cached_prop(player, "m_iHealth", 100)
    if planted and hp < 50 then return "aggressive"
    elseif count_teammates() > count_enemies() then return "defensive"
    else return "balanced" end
end

local function predict_peek_behavior(player, data)
    if not player or not entity.is_alive(player) then
        data.likely_peek_type = "unknown"; data.peek_aggression = 0.5; data.expected_desync = "unknown"; data.resolver_context = "balanced"; return
    end
    data.resolver_context = get_resolver_context(player)
    local w_type = get_weapon_type(entity.get_player_weapon(player))
    
    if w_type == "awp" then data.likely_peek_type = "shoulder"; data.peek_aggression = 0.3; data.expected_desync = "maximum"
    elseif w_type == "scout" then data.likely_peek_type = "jiggle"; data.peek_aggression = 0.6; data.expected_desync = "dynamic"
    elseif w_type == "auto" then data.likely_peek_type = "hold"; data.peek_aggression = 0.4; data.expected_desync = "minimum"
    elseif w_type == "deagle" then data.likely_peek_type = "crouch"; data.peek_aggression = 0.7; data.expected_desync = "medium"
    elseif w_type == "revolver" then data.likely_peek_type = "delayed"; data.peek_aggression = 0.5; data.expected_desync = "medium"
    else data.likely_peek_type = "wide"; data.peek_aggression = 0.7; data.expected_desync = "medium" end
    
    if get_cached_prop(player, "m_iHealth", 100) < 50 then data.peek_aggression = data.peek_aggression * 0.7 end
end

local function weapon_aware_resolution(player, data, base_angle)
    local w_type = get_weapon_type(entity.get_player_weapon(player))
    if w_type == "scout" and data.patterns.oscillation then return base_angle * 1.2
    elseif w_type == "auto" then return base_angle * 0.9
    elseif w_type == "deagle" and data.likely_peek_type == "crouch" then return base_angle * 1.1
    elseif w_type == "pistol" then return base_angle * 1.15 end
    return base_angle
end

local function analyze_desync_patterns(player, data)
    local recent = data.recent_angles or {}
    table.insert(recent, 1, data.resolved_angle)
    if #recent > 32 then table.remove(recent) end
    data.recent_angles = recent
    
    if #recent >= 8 then
        local mean, std_dev = calculate_angle_stats(recent)
        data.patterns = {
            oscillation = detect_oscillation(recent, 3),
            consistent_side = detect_consistent_side(recent, 8),
            mean_angle = mean, variability = std_dev
        }
        return true
    end
    return false
end

local function adaptive_confidence_system(player, data)
    local weights = data.method_weights
    if data.hit_rate > 0.7 then
        for m, _ in pairs(weights) do if data.last_successful_method == m then weights[m] = weights[m] * 1.3 end end
    elseif data.hit_rate < 0.3 then
        for m, _ in pairs(weights) do if data.last_failed_method == m then weights[m] = weights[m] * 0.7 end end
    end
    local total = 0
    for _, w in pairs(weights) do total = total + w end
    for m, w in pairs(weights) do weights[m] = w / total end
    data.method_weights = weights
    return weights
end

local function predict_movement_trajectory(player, data)
    local positions = data.recent_positions or {}
    local x, y, z = entity.get_prop(player, "m_vecOrigin")
    if not x or not y then return end
    table.insert(positions, 1, {x = x, y = y, z = z, time = globals.curtime()})
    if #positions > 16 then table.remove(positions) end
    data.recent_positions = positions
    
    if #positions >= 3 then
        local vel1 = { x = positions[1].x - positions[2].x, y = positions[1].y - positions[2].y, z = positions[1].z - positions[2].z }
        local vel2 = { x = positions[2].x - positions[3].x, y = positions[2].y - positions[3].y, z = positions[2].z - positions[3].z }
        local acc = { x = vel1.x - vel2.x, y = vel1.y - vel2.y, z = vel1.z - vel2.z }
        data.predicted_position = { x = positions[1].x + vel1.x + acc.x * 0.5, y = positions[1].y + vel1.y + acc.y * 0.5, z = positions[1].z + vel1.z + acc.z * 0.5 }
        data.movement_acceleration = math.sqrt(acc.x^2 + acc.y^2 + acc.z^2)
    end
end

local function detect_desync_break(player, data)
    local curr = entity.get_prop(player, "m_flLowerBodyYawTarget") or 0
    if math.abs(angle_diff(curr, data.last_lby)) > 60 and data.last_lby_update and (globals.curtime() - data.last_lby_update) < 0.2 then
        data.fake_desync_detected = true; data.true_lby = data.last_lby; return true
    end
    data.last_lby_update = globals.curtime()
    return false
end

-- ============================================================================
-- ADVANCED RECON ENGINES DEFENSIVE EXTRACTION
-- ============================================================================
local function get_ping_thresholds(enemy_ping, local_ping)
    local eff = math.max(enemy_ping or 50, local_ping or 50)
    local th = { teleport_dist = 64, velocity_max = 320, simtime_gap = 14, suspicion_base = 60, ping_category = "low", enemy_ping = enemy_ping, local_ping = local_ping, effective_ping = eff }
    if eff < 50 then th.ping_category = "low"; th.teleport_dist = 64
    elseif eff < 100 then th.ping_category = "medium"; th.teleport_dist = 90; th.suspicion_base = 65
    elseif eff < 150 then th.ping_category = "high"; th.teleport_dist = 120; th.suspicion_base = 70
    else th.ping_category = "very_high"; th.teleport_dist = 150; th.suspicion_base = 80 end
    return th
end

local function is_using_antiaim(player)
    if not player or not entity.is_alive(player) then return false end
    local data = init_player_data(player)
    if data.aa_detected then return true end
    if data.aa_check_result ~= nil and globals.tickcount() - (data.aa_check_time or 0) < AA_CHECK_CACHE_DURATION then return data.aa_check_result end
    data.aa_check_time = globals.tickcount()
    local ey, by = entity.get_prop(player, "m_angEyeAngles[1]"), entity.get_prop(player, "m_flLowerBodyYawTarget")
    if ey and by and math.abs(angle_diff(ey, by)) > 20 then data.aa_detected = true; data.aa_check_result = true; return true end
    data.aa_check_result = false; return true
end

local function is_valid_defensive_detection(player, data, detection)
    if not detection or not detection.detected or exploits:in_defensive() or exploits:in_recharge() then return false end
    if (exploits:is_lagcomp_broken() and 92 or 85) < 85 then return false end
    if data.last_damage_time and (globals.curtime() - data.last_damage_time) < 0.25 then return false end
    if data.last_shot_time and (globals.curtime() - data.last_shot_time) < 0.2 then return false end
    if detection.confidence < 92 then
        data.defensive_suspicion_ticks = (data.defensive_suspicion_ticks or 0) + 1
        if data.defensive_suspicion_ticks < 2 then return false end
    else data.defensive_suspicion_ticks = 0 end
    return true
end

local function create_detection_result(detected, confidence, method, ticks, angle)
    return { detected = detected, confidence = confidence, method = method, ticks = ticks or 0, angle = angle }
end

local function detect_exploit_doubletap(player, data)
    local sim = entity.get_prop(player, "m_flSimulationTime")
    local old = entity.get_prop(player, "m_flOldSimulationTime")
    if not sim or not old then return create_detection_result(false, 0, "none", 0) end
    
    if not data.sim_history then data.sim_history = {} end
    table.insert(data.sim_history, 1, { sim_time = sim, old_sim_time = old, tick = globals.tickcount() })
    if #data.sim_history > 10 then table.remove(data.sim_history) end
    
    -- Calculate the exact tick differential
    local diff = math_floor((sim - old) / globals.tickinterval() + 0.5)
    
    -- 1. TICKBASE ROLLBACK (Defensive AA / Defensive DT)
    -- If simulation time goes BACKWARD, they are 100% manipulating tickbase.
    if diff < 0 then 
        return create_detection_result(true, 100, "negative_simtime", math_min(math_abs(diff) + 2, 14), data.last_good_angle or 0) 
    end
    
    -- 2. INSTANT LAG COMP START (Massive Choke Spike)
    if diff >= 14 then 
        return create_detection_result(true, 98, "instant_lc", 14, data.last_good_angle or 0) 
    end
    
    -- 3. SOURCE ENGINE BREAK-LC (Teleport Detection)
    -- The server instantly breaks lag compensation if the distance between ticks exceeds 64 units (4096 sqr units).
    if data.last_position then
        local ox, oy, oz = entity.get_prop(player, "m_vecOrigin")
        if ox and oy and oz then
            local dist_sqr = (ox - data.last_position.x)^2 + (oy - data.last_position.y)^2 + (oz - data.last_position.z)^2
            if dist_sqr > 4096 then
                return create_detection_result(true, 100, "break_lc_teleport", 8, data.last_good_angle or 0)
            end
        end
    end
    
    -- 4. RAPID DOUBLETAP RECOVERY
    if #data.sim_history >= 4 then
        local p1 = math_floor((data.sim_history[2].sim_time - data.sim_history[2].old_sim_time) / globals.tickinterval() + 0.5)
        local p2 = math_floor((data.sim_history[3].sim_time - data.sim_history[3].old_sim_time) / globals.tickinterval() + 0.5)
        
        -- If they choked 12+ ticks, then immediately sent 1-2 ticks, they just rapid-fired.
        if p1 >= 12 and diff <= 2 and p2 <= 2 then 
            return create_detection_result(true, 93, "fakelag_break", 6, data.last_good_angle or 0) 
        end
    end
    
    return create_detection_result(false, 0, "none", 0)
end

local function detect_eye_angle_flick(player, data)
    local pitch, yaw = entity.get_prop(player, "m_angEyeAngles[0]"), entity.get_prop(player, "m_angEyeAngles[1]")
    if not pitch or not yaw then return create_detection_result(false, 0, "none", 0) end
    if not eye_angle_data[player] then eye_angle_data[player] = { history = {}, last_update = globals.tickcount(), buffer = create_circular_buffer(5) } end
    
    local eye_data = eye_angle_data[player]
    eye_data.buffer:push({ pitch = pitch, yaw = yaw, tick = globals.tickcount() })
    eye_data.history = eye_data.buffer:get_all()
    if #eye_data.history < 2 then return create_detection_result(false, 0, "none", 0) end
    
    local curr, prev = eye_data.history[1], eye_data.history[2]
    local pd, yd = math.abs(curr.pitch - prev.pitch), math.abs(normalize_angle(curr.yaw - prev.yaw))
    local ping = get_player_ping(player)
    
    if yd > 33 then data.flick_direction = normalize_angle(curr.yaw - prev.yaw) > 0 and 1 or -1; return create_detection_result(true, 100, "yaw_flick", 6, prev.yaw) end
    if math.abs(curr.pitch) < 5 and math.abs(prev.pitch) > 45 then return create_detection_result(true, 98, "zero_pitch", 5, prev.yaw) end
    if pd > (ping < 100 and 50 or 65) then return create_detection_result(true, 95, "custom_pitch", 5, prev.yaw) end
    
    if #eye_data.history >= 4 then
        if math.abs(eye_data.history[1].pitch - eye_data.history[2].pitch) > 40 and math.abs(eye_data.history[3].pitch - eye_data.history[4].pitch) > 40 and math.abs(eye_data.history[1].pitch - eye_data.history[3].pitch) < 10 then
            return create_detection_result(true, 93, "switch_pitch", 6, prev.yaw)
        end
        local tot_y = 0
        for i = 1, 3 do tot_y = tot_y + math.abs(normalize_angle(eye_data.history[i].yaw - eye_data.history[i+1].yaw)) end
        if tot_y > 180 then return create_detection_result(true, 88, "oscillation", 4, prev.yaw) end
    end
    return create_detection_result(false, 0, "none", 0)
end

local function detect_defensive_spin(player, data)
    if not eye_angle_data[player] or not eye_angle_data[player].history or #eye_angle_data[player].history < 4 then return create_detection_result(false, 0, "none", 0) end
    local hist = eye_angle_data[player].history
    local r1, r2, r3 = normalize_angle(hist[1].yaw - hist[2].yaw), normalize_angle(hist[2].yaw - hist[3].yaw), normalize_angle(hist[3].yaw - hist[4].yaw)
    local pos = (r1 > 0 and r2 > 0 and r3 > 0)
    local neg = (r1 < 0 and r2 < 0 and r3 < 0)
    local tot = math.abs(r1) + math.abs(r2) + math.abs(r3)
    if (pos or neg) and tot > 45 then data.spin_direction = pos and 1 or -1; return create_detection_result(true, 89, "spin", 5, data.last_good_angle or 0) end
    if (pos or neg) and tot > 25 then
        data.spin_sequence = (data.spin_sequence or 0) + 1
        if data.spin_sequence >= 3 then return create_detection_result(true, 85, "slow_spin", 4, data.last_good_angle or 0) end
    else data.spin_sequence = 0 end
    return create_detection_result(false, 0, "none", 0)
end

local function detect_pitch_exploit(player, data)
    local pitch, yaw = entity.get_prop(player, "m_angEyeAngles[0]"), entity.get_prop(player, "m_angEyeAngles[1]")
    if not pitch or not yaw then return create_detection_result(false, 0, "none", 0) end
    if not data.pitch_history then data.pitch_history = {} end
    table.insert(data.pitch_history, 1, { pitch = pitch, yaw = yaw, tick = globals.tickcount() })
    if #data.pitch_history > 10 then table.remove(data.pitch_history) end
    if #data.pitch_history < 3 then return create_detection_result(false, 0, "none", 0) end
    
    if math.abs(pitch - 89) < 2 then return create_detection_result(true, 97, "fake_up", 5, data.last_good_angle or 0) end
    if math.abs(pitch + 89) < 2 then return create_detection_result(true, 97, "fake_down", 5, data.last_good_angle or 0) end
    
    local chg, tot = 0, 0
    for i = 1, math.min(3, #data.pitch_history - 1) do
        local d = math.abs(data.pitch_history[i].pitch - data.pitch_history[i+1].pitch)
        tot = tot + d; if d > 40 then chg = chg + 1 end
    end
    if chg >= 2 and tot > 100 then return create_detection_result(true, 94, "pitch_oscillation", 6, data.last_good_angle or 0) end
    
    if math.abs(pitch) < 3 then
        local weapon = entity.get_player_weapon(player)
        if weapon and (globals.curtime() - (entity.get_prop(weapon, "m_fLastShotTime") or 0)) < 0.15 then return create_detection_result(true, 96, "zero_pitch_shot", 5, data.last_good_angle or 0) end
    end
    return create_detection_result(false, 0, "none", 0)
end

local function detect_defensive_choke(player, data)
    local sim, old = entity.get_prop(player, "m_flSimulationTime"), entity.get_prop(player, "m_flOldSimulationTime")
    if not sim or not old then return create_detection_result(false, 0, "none", 0) end
    local choke = math.floor((sim - old) / globals.tickinterval())
    if not data.choke_pattern_history then data.choke_pattern_history = {} end
    table.insert(data.choke_pattern_history, 1, choke)
    if #data.choke_pattern_history > 16 then table.remove(data.choke_pattern_history) end
    
    local ping = get_player_ping(player)
    if choke >= (ping < 100 and 15 or 18) then return create_detection_result(true, 92, "choke_instant", 6, data.last_good_angle or 0) end
    if #data.choke_pattern_history >= 4 then
        local avg = (data.choke_pattern_history[2] + data.choke_pattern_history[3] + data.choke_pattern_history[4]) / 3
        if avg < 3 and choke > (ping < 100 and 12 or 15) then return create_detection_result(true, 87, "choke_spike", 5, data.last_good_angle or 0) end
        local vr = 0
        for i = 1, 4 do vr = vr + math.abs(data.choke_pattern_history[i] - avg) end
        if (vr / 4) > 6 and choke > 10 then data.choke_jitter_detected = true; return create_detection_result(true, 83, "choke_jitter", 4, data.last_good_angle or 0) end
    end
    return create_detection_result(false, 0, "none", 0)
end

local function predict_body_yaw_update(player, data)
    local body_yaw = entity.get_prop(player, "m_flPoseParameter", 11)
    if not body_yaw then return false, nil end
    body_yaw = body_yaw * 120 - 60
    if not data.body_yaw_history then data.body_yaw_history = {} end
    table.insert(data.body_yaw_history, 1, { value = body_yaw, time = globals.curtime(), tick = globals.tickcount() })
    if #data.body_yaw_history > 10 then table.remove(data.body_yaw_history) end
    if #data.body_yaw_history < 3 then return false, nil end
    
    local d1 = data.body_yaw_history[1].value - data.body_yaw_history[2].value
    local d2 = data.body_yaw_history[2].value - data.body_yaw_history[3].value
    if (d1 > 30 and d2 < -30) or (d1 < -30 and d2 > 30) then
        data.confidence = math.min(100, data.confidence + (15 * (data.velocity_reliability or 0.5)))
        return true, body_yaw > 0 and -58 or 58
    end
    return false, nil
end

local function update_velocity_confidence(player, data, hit_success)
    if not data.velocity_confidence then data.velocity_confidence = 0.5 end
    if data.last_resolve_method == "velocity" then
        data.velocity_confidence = hit_success and math.min(1.0, data.velocity_confidence + 0.1) or math.max(0.1, data.velocity_confidence - 0.15)
    end
    data.velocity_reliability = data.velocity_confidence
    return data.velocity_confidence
end

local function predict_strafe_continuation(player, data)
    if not data.velocity_history then return nil end
    local hist = data.velocity_history:get_all()
    if not hist or #hist < 3 or not hist[1] or not hist[2] or not hist[3] then return nil end
    local a1, a2, a3 = math.deg(math.atan2(hist[1].y, hist[1].x)), math.deg(math.atan2(hist[2].y, hist[2].x)), math.deg(math.atan2(hist[3].y, hist[3].x))
    local d1, d2 = normalize_angle(a1 - a2), normalize_angle(a2 - a3)
    if math.abs(d1 - d2) < 15 then
        local p = (d1 + d2) / 2
        if p > 5 then return -1 elseif p < -5 then return 1 end
    end
    return nil
end

local function is_velocity_stable(player, data)
    if not data.velocity_history then return false end
    local hist = data.velocity_history:get_all()
    if not hist or #hist < 4 then return false end
    local sp = {}
    for i = 1, 4 do if not hist[i] then return false end; sp[i] = math.sqrt(hist[i].x^2 + hist[i].y^2) end
    local avg = (sp[1] + sp[2] + sp[3] + sp[4]) / 4
    local vr = 0
    for i = 1, 4 do vr = vr + (sp[i] - avg)^2 end
    return (vr / 4) < 100
end

local function resolve_by_velocity_advanced(player, data)
    local vx, vy, vz = get_cached_prop(player, "m_vecVelocity", 0)
    if not vx or not vy then return false, nil end
    local speed = math.sqrt(vx*vx + vy*vy)
    if not is_velocity_stable(player, data) and speed > 100 then data.confidence = math.max(40, data.confidence - 10) end
    if not data.velocity_pattern then data.velocity_pattern = {} end
    table.insert(data.velocity_pattern, 1, { x = vx, y = vy, z = vz, speed = speed, time = globals.curtime(), tick = globals.tickcount() })
    if #data.velocity_pattern > 8 then table.remove(data.velocity_pattern) end
    if speed < 5 then return false, nil end
    
    local anim = get_anim_state(get_entity_address(player))
    if not anim then return false, nil end
    local m_yaw, f_yaw = anim.flMoveYaw, anim.flGoalFeetYaw
    local delta = normalize_angle(math.deg(math.atan2(vy, vx)) - f_yaw)
    local str_type = "none"
    if math.abs(delta) > 45 and math.abs(delta) < 135 then str_type = speed > 220 and "fast_strafe" or (speed > 150 and "normal_strafe" or "slow_strafe") end
    
    if str_type == "fast_strafe" then
        local side = delta > 0 and -1 or 1
        data.confidence = math.min(100, data.confidence + ((entity.get_prop(player, "m_fFlags") and bit.band(entity.get_prop(player, "m_fFlags"), 1) == 0 and 30 or 25) * (data.velocity_reliability or 0.5)))
        return true, side * (bit.band(entity.get_prop(player, "m_fFlags"), 1) == 0 and 60 or 58)
    end
    if str_type == "normal_strafe" then data.confidence = math.min(100, data.confidence + (20 * (data.velocity_reliability or 0.5))); return true, (delta > 0 and -1 or 1) * 55 end
    if str_type == "slow_strafe" then
        local side = delta > 0 and -1 or 1
        local is_duck = (entity.get_prop(player, "m_fFlags") and bit.band(entity.get_prop(player, "m_fFlags"), 2) ~= 0)
        data.confidence = math.min(100, data.confidence + ((is_duck and 22 or 18) * (data.velocity_reliability or 0.5)))
        return true, side * (is_duck and 45 or 50)
    end
    
    if m_yaw > 175 or m_yaw < -175 then
        local by = entity.get_prop(player, "m_flPoseParameter", 11)
        if by then by = by * 120 - 60
            if data.reliable_angles then
                if by > 0 and #data.reliable_angles.left_angles > 0 then return true, data.reliable_angles.left_angles[1]
                elseif by < 0 and #data.reliable_angles.right_angles > 0 then return true, data.reliable_angles.right_angles[1] end
            end
            return true, by > 0 and -55 or 55
        end
    end
    local sc = predict_strafe_continuation(player, data)
    if sc then data.confidence = math.min(100, data.confidence + 20); data.last_resolved_side = sc; return true, sc * 58 end
    return false, nil
end

local function resolve_standing_improved(player, data, lby)
    if data.standing_ticks < 16 then return false, nil end
    local flg = entity.get_prop(player, "m_fFlags")
    if flg and bit.band(flg, 2) ~= 0 and (entity.get_prop(player, "m_flDuckAmount") or 0) > 0.9 then return false, nil end
    local vx, vy = get_cached_prop(player, "m_vecVelocity", 0)
    local speed = (vx and vy) and math.sqrt(vx*vx + vy*vy) or 0
    if speed > 0.1 and speed < 1.5 then speed = 0; data.standing_ticks = data.standing_ticks + 1 end
    if speed > 1.5 then data.standing_ticks = 0; return false, nil end
    if not data.standing_lby_history then data.standing_lby_history = {} end
    table.insert(data.standing_lby_history, 1, { lby = lby, tick = globals.tickcount(), time = globals.curtime() })
    if #data.standing_lby_history > 8 then table.remove(data.standing_lby_history) end
    local by = entity.get_prop(player, "m_flPoseParameter", 11)
    if by then by = by * 120 - 60 end
    
    if #data.standing_lby_history >= 2 and math.abs(angle_diff(data.standing_lby_history[1].lby, data.standing_lby_history[2].lby)) > 25 then
        local side = (by and math.abs(by) > 10) and (by > 0 and -1 or 1) or (lby > 0 and -1 or 1)
        data.confidence = 98; data.last_lby_update_time = globals.curtime(); data.lby_update_tick = globals.tickcount(); data.lby_just_updated = true
        data.standing_locked_angle = side * 60; data.standing_lock_until = globals.tickcount() + 8
        return true, side * 60
    end
    if data.standing_locked_angle and data.standing_lock_until and globals.tickcount() <= data.standing_lock_until then data.confidence = 96; return true, data.standing_locked_angle end
    
    local cyc = (globals.curtime() - (data.last_lby_update_time or 0)) % 1.1
    if cyc >= 0.8 and cyc <= 1.1 then
        local side = (by and math.abs(by) > 10) and (by > 0 and -1 or 1) or (lby > 0 and -1 or 1)
        data.confidence = 92; data.lby_update_predicted = true; return true, side * 58
    end
    local side = (by and math.abs(by) > 10) and (by > 0 and -1 or 1) or (lby > 0 and -1 or 1)
    if data.standing_ticks >= 50 then data.confidence = 96; return true, side * 60 end
    if data.standing_ticks >= 30 then data.confidence = 88; return true, side * 58 end
    data.confidence = 74; return true, side * 54
end

local function analyze_lean_layer(player, data)
    local ptr = get_entity_address(player)
    if not ptr then return false, nil end
    local layers = get_anim_layers(ptr)
    if not layers then return false, nil end
    if not data.lean_history then data.lean_history = {} end
    table.insert(data.lean_history, 1, { weight = layers[12].m_weight, cycle = layers[12].m_cycle, move_weight = layers[6].m_weight, tick = globals.tickcount() })
    if #data.lean_history > 6 then table.remove(data.lean_history) end
    if #data.lean_history < 2 then return false, nil end
    
    local diff = data.lean_history[1].weight - data.lean_history[2].weight
    if math.abs(diff) > 0.15 then data.confidence = math.min(100, data.confidence + 18); return true, (diff > 0 and 1 or -1) * 58 end
    if math.abs((data.lean_history[1].weight / (data.lean_history[1].move_weight + 0.001)) - (data.lean_history[2].weight / (data.lean_history[2].move_weight + 0.001))) > 3.0 then
        data.suspicious_animation = true; data.is_defensive = true; data.defensive_ticks = 3
    end
    return false, nil
end

local function smooth_resolved_angle(player, data, raw_angle)
    if not raw_angle or raw_angle == 0 then return raw_angle end
    if not data.angle_smooth_history then data.angle_smooth_history = {} end
    table.insert(data.angle_smooth_history, 1, raw_angle)
    if #data.angle_smooth_history > 2 then table.remove(data.angle_smooth_history) end
    if #data.angle_smooth_history >= 2 and math.abs(data.angle_smooth_history[1] - data.angle_smooth_history[2]) < 30 then
        data.confidence = math.min(100, data.confidence + 10)
        return (data.angle_smooth_history[1] + data.angle_smooth_history[2]) / 2
    end
    return raw_angle
end

local function detect_animation_break_enhanced(player, data)
    local ptr = get_entity_address(player)
    if not ptr then return false end
    local layers = get_anim_layers(ptr)
    if not layers then return false end
    if not data.layer_history then data.layer_history = {} end
    table.insert(data.layer_history, 1, { move_weight = layers[6].m_weight, move_cycle = layers[6].m_cycle, lean_weight = layers[12].m_weight, adjust_cycle = layers[3].m_cycle, tick = globals.tickcount() })
    if #data.layer_history > 8 then table.remove(data.layer_history) end
    if #data.layer_history < 2 then return false end
    
    local curr, prev = data.layer_history[1], data.layer_history[2]
    if math.abs(curr.move_weight - prev.move_weight) > 0.5 and math.abs(curr.move_cycle - prev.move_cycle) < 0.01 then data.is_defensive = true; data.defensive_ticks = 5; return true end
    if curr.move_cycle < prev.move_cycle - 0.5 then data.is_defensive = true; data.defensive_ticks = 4; return true end
    if math.abs((curr.move_weight / (curr.move_cycle + 0.001)) - (curr.lean_weight / (curr.adjust_cycle + 0.001))) > 8.0 then data.is_defensive = true; data.defensive_ticks = 3; return true end
    return false
end

local function detect_defensive_comprehensive(player, data)
    local tick = globals.tickcount()
    
    -- If our own cheat is currently actively recharging or shifting, abort to prevent desyncing ourselves
    if exploits:in_defensive() or exploits:in_recharge() then return false end
    
    -- Retrieve cached network validation threshold
    if defensive_check_cache[player] and (tick - (defensive_check_time[player] or 0)) < DEFENSIVE_CACHE_DURATION then 
        return defensive_check_cache[player] 
    end
    
    -- Run ONLY the true Source Engine Tickbase/LC Break detector.
    -- We completely removed the pitch, spin, and flick false-positive detectors.
    local best = detect_exploit_doubletap(player, data)
    
    -- Do not override physical damage/shot registry windows unless confidence is absolute
    if data.last_shot_time and (globals.curtime() - data.last_shot_time) < 0.15 and best.confidence < 95 then return false end
    if data.last_damage_time and (globals.curtime() - data.last_damage_time) < 0.25 and best.confidence < 95 then return false end
    
    if best and best.detected and best.confidence >= 95 then
        data.is_defensive = true
        
        -- THREAT DECAY SYSTEM: Actively stack delay ticks for real teleports
        data.defensive_ticks = math_max(data.defensive_ticks or 0, best.ticks)
        
        data.defensive_method = best.method
        data.defensive_suspicion_score = best.confidence
        data.defensive_type = best.method
        
        if best.angle and best.angle ~= 0 then 
            data.last_good_angle = best.angle 
        end
        
        data.last_defensive_detect = tick
        defensive_check_cache[player] = true
        defensive_check_time[player] = tick
        return true
    end
    
    defensive_check_cache[player] = false
    return false
end

local function detect_airborne_state(player, data)
    local flg = entity.get_prop(player, "m_fFlags")
    if not flg then return false end
    local air = bit.band(flg, 1) == 0
    if not data.air_state then data.air_state = { is_airborne = false, air_ticks = 0, last_ground_angle = 0, takeoff_velocity = {x=0,y=0,z=0}, apex_reached = false, landing_predicted = false } end
    local vx, vy, vz = get_cached_prop(player, "m_vecVelocity", 0)
    
    if air and not data.air_state.is_airborne then data.air_state.takeoff_velocity = {x=vx,y=vy,z=vz}; data.air_state.last_ground_angle = data.resolved_angle or 0; data.air_state.air_ticks = 0; data.air_state.apex_reached = false end
    data.air_state.is_airborne = air
    if air then data.air_state.air_ticks = data.air_state.air_ticks + 1; if not data.air_state.apex_reached and vz < 0 and data.air_state.air_ticks > 3 then data.air_state.apex_reached = true end else data.air_state.air_ticks = 0; data.air_state.apex_reached = false end
    return air
end

local function resolve_airborne(player, data)
    if not data.air_state or not data.air_state.is_airborne then return false, nil end
    
    local vx, vy, vz = get_cached_prop(player, "m_vecVelocity", 0)
    local anim = get_anim_state(get_entity_address(player))
    local yaw = entity.get_prop(player, "m_angEyeAngles[1]")
    if not vx or not anim or not yaw then return false, nil end
    
    local delta = normalize_angle(math.deg(math.atan2(vy, vx)) - yaw)
    
    -- SYSTEM FIX 1: Tapping into the FFI dynamic boundary matrix instead of hardcoded 120-60
    local by = get_dynamic_body_yaw(player) 
    
    -- SYSTEM FIX 2: Air-Duck Scaling Component
    -- If a target is crouch-jumping, the engine forcefully shrinks their maximum desync limit
    local duck_amt = entity.get_prop(player, "m_flDuckAmount") or 0
    local max_air_limit = (duck_amt > 0.5) and 42 or 58
    
    -- Phase 1: Early Flight Initialization (First 3 ticks of a jump)
    if data.air_state.air_ticks <= 3 then 
        data.confidence = 85 
        return true, data.air_state.last_ground_angle 
    end
    
    -- Phase 2: Active Air-Strafe Telemetry Tracking
    if math.abs(delta) > 60 and math.abs(delta) < 120 then 
        data.confidence = 95 
        local side = delta > 0 and -1 or 1
        return true, side * max_air_limit 
    end
    
    -- Phase 3: FFI Real-time Bound Resolution
    if math_abs(by) > 4.5 then
        data.confidence = 88
        local side = by > 0 and -1 or 1
        -- Cap the resolved value to the current crouch-compressed maximum boundary
        return true, side * math_min(max_air_limit, math_abs(by))
    end
    
    -- Phase 4: Apex/Drop Low-Delta Air Stall Fallback
    -- Forces the airborne player to remain isolated here instead of slipping into walking filters
    data.confidence = 60
    return true, (yaw > 0 and -1 or 1) * 35 
end

local function detect_crouch_state(player, data)
    local flg = entity.get_prop(player, "m_fFlags")
    if not flg then return false end
    local duck = bit.band(flg, 2) ~= 0
    local amt = entity.get_prop(player, "m_flDuckAmount")
    if not data.crouch_state then data.crouch_state = { is_crouching = false, crouch_ticks = 0, duck_amount = 0, last_duck_amount = 0, crouch_type = "none" } end
    
    if duck or (amt and amt > 0.1) then
        data.crouch_state.crouch_ticks = data.crouch_state.crouch_ticks + 1
        if amt then
            data.crouch_state.last_duck_amount = data.crouch_state.duck_amount; data.crouch_state.duck_amount = amt
            data.crouch_state.crouch_type = amt > 0.9 and "full" or (math.abs(amt - data.crouch_state.last_duck_amount) > 0.5 and "fakeduck" or "partial")
        end
        data.crouch_state.is_crouching = true
    else data.crouch_state.crouch_ticks = 0; data.crouch_state.is_crouching = false; data.crouch_state.crouch_type = "none" end
    return data.crouch_state.is_crouching
end

local function resolve_crouching(player, data)
    if not data.crouch_state or not data.crouch_state.is_crouching then return false, nil end
    local by = entity.get_prop(player, "m_flPoseParameter", 11)
    if not by then return false, nil end; by = by * 120 - 60
    if data.crouch_state.crouch_type == "fakeduck" then data.confidence = 95; data.is_defensive = true; data.defensive_ticks = 3; return true, 0 end
    if data.crouch_state.crouch_type == "full" then data.confidence = 85; return true, by > 0 and -45 or 45 end
    data.confidence = 80; return true, by > 0 and -58 or 58
end

local function resolve_defensive(player, data)
    if not data.is_defensive or data.defensive_ticks <= 0 then return nil end
    if contains({"yaw_flick", "spin", "slow_spin", "oscillation"}, data.defensive_type) and data.last_good_angle and data.last_good_angle ~= 0 then
        local res = data.last_good_angle + (data.flick_direction and (data.flick_direction * -60) or 0)
        if (data.defensive_type == "spin" or data.defensive_type == "slow_spin") and data.spin_direction then res = res - (data.spin_direction * 45) end
        data.confidence = 90; return normalize_angle(res)
    end
    if contains({"zero_pitch", "custom_pitch", "switch_pitch", "metaset_primary", "metaset_teleport"}, data.defensive_type) and data.last_good_angle and data.last_good_angle ~= 0 then
        data.confidence = 90; return normalize_angle(data.last_good_angle)
    end
    if data.last_good_angle and data.last_good_angle ~= 0 and (globals.tickcount() - (data.last_good_angle_tick or 0)) < 16 then data.confidence = 85; return normalize_angle(data.last_good_angle) end
    if data.shot_snapshot_angle and data.shot_snapshot_time and (globals.curtime() - data.shot_snapshot_time) < 0.4 then data.confidence = 80; return normalize_angle(data.shot_snapshot_angle) end
    if data.last_lby then data.confidence = 70; return (data.last_lby > 0 and -1 or 1) * 58 end
    local lby = entity.get_prop(player, "m_flLowerBodyYawTarget")
    if lby then data.confidence = 60; return (lby > 0 and -1 or 1) * 55 end
    return 0
end

-- ============================================================================
-- BRUTEFORCE MATRIX RESOLVER MODULES
-- ============================================================================
local function intelligent_bruteforce(player, data)
    local best, b_rate = "sequential", 0
    for m, p in pairs(data.brute_patterns) do if p.success_rate > b_rate then b_rate = p.success_rate; best = m end end
    local base = ui.resolver.brute_phases:get()
    return best, data.hit_rate < 0.2 and math.min(7, base + 2) or (data.hit_rate > 0.6 and math.max(2, base - 1) or base)
end

local function analyze_layer_correlations(player, data)
    local ptr = get_entity_address(player)
    if not ptr then return {} end
    local layers = get_anim_layers(ptr)
    if not layers then return {} end
    local corr = {}
    for i = 0, 12 do
        if layers[i] then corr[i] = { ratio = layers[i].m_weight / (layers[i].m_cycle + 0.001), vel = layers[i].m_playback_rate * 1000, act = layers[i].m_activity } end
    end
    if corr[6] and corr[12] and math.abs(corr[6].ratio - corr[12].ratio) > 5.0 then data.suspicious_animation = true end
    data.layer_correlations = corr
    return corr
end

local function update_resolver_analytics(player, data, hit_success, method_used)
    if not data.analytics then data.analytics = { method_success = {}, angle_success = {}, timing_success = {}, total_resolves = 0, successful_resolves = 0, overall_success_rate = 0 } end
    data.analytics.total_resolves = data.analytics.total_resolves + 1
    if hit_success then
        data.analytics.successful_resolves = data.analytics.successful_resolves + 1
        data.analytics.method_success[method_used] = (data.analytics.method_success[method_used] or 0) + 1
        data.last_successful_method = method_used
    else data.last_failed_method = method_used end
    data.analytics.overall_success_rate = data.analytics.successful_resolves / math.max(1, data.analytics.total_resolves)
end

local function adaptive_learning(player, data)
    if data.analytics.total_resolves < 5 then return end
    local rate = data.analytics.overall_success_rate
    if rate < 0.3 then
        data.learning_phase = "experimental"; data.brute_aggression = math.min(1.0, data.brute_aggression + 0.2)
        data.method_weights = { lby_delta = 0.25, movement = 0.20, animation = 0.15, velocity = 0.15, historical = 0.15, pattern = 0.10 }
    elseif rate < 0.5 then data.learning_phase = "experimental"; data.brute_aggression = math.min(1.0, data.brute_aggression + 0.15)
    elseif rate > 0.75 then
        data.learning_phase = "refinement"; data.brute_aggression = math.max(0.3, data.brute_aggression - 0.08)
        if data.last_successful_method and data.method_weights[data.last_successful_method] then
            data.method_weights[data.last_successful_method] = math.min(0.4, data.method_weights[data.last_successful_method] * 1.2)
            local total = 0
            for _, w in pairs(data.method_weights) do total = total + w end
            for m, w in pairs(data.method_weights) do data.method_weights[m] = w / total end
        end
    else data.learning_phase = "stable" end
    
    local vr, sp, smp = data.patterns.variability or 0, 0, 0
    if data.velocity_pattern then for i = 1, math.min(5, #data.velocity_pattern) do sp = sp + data.velocity_pattern[i].speed; smp = smp + 1 end; sp = sp / smp end
    data.player_profile.playstyle = (vr > 30 and sp > 180) and "aggressive" or ((vr < 10 and sp < 80) and "passive" or "balanced")
    if data.patterns.oscillation then data.player_profile.desync_habits.jitter = true end
    if data.patterns.consistent_side ~= 0 then data.player_profile.desync_habits.consistent_side = data.patterns.consistent_side end
    
    if data.player_profile.playstyle == "aggressive" then
        data.method_weights.velocity = math.min(0.3, data.method_weights.velocity * 1.2); data.method_weights.pattern = math.min(0.2, data.method_weights.pattern * 1.3)
    elseif data.player_profile.playstyle == "passive" then
        data.method_weights.lby_delta = math.min(0.35, data.method_weights.lby_delta * 1.2); data.method_weights.historical = math.min(0.2, data.method_weights.historical * 1.1)
    end
    local total = 0
    for _, w in pairs(data.method_weights) do total = total + w end
    for m, w in pairs(data.method_weights) do data.method_weights[m] = w / total end
end

local function apply_defensive_shot_delay(player, data)
    if not ui.defensive.delay_head:get() then data.block_shots = false; return false end
    local delay = (data.is_defensive and data.defensive_ticks > 0) or (data.defensive_wait_until and globals.tickcount() < data.defensive_wait_until)
    if delay then plist.set(player, "Override safe point", "On"); data.block_shots = true; return true
    else data.block_shots = false; plist.set(player, "Override safe point", "-"); return false end
end

-- ============================================================================
-- SMART PRESET LOADER CORE STRUCTS
-- ============================================================================
local smart_baim_presets = {
    ["Default"] = { speed_threshold = 280, confidence_threshold = 40, miss_mode = "Prefer after 1 miss", reset_on_hit = true, description = "Default preset by Tama" },
    ["Aggressive"] = { speed_threshold = 240, confidence_threshold = 50, miss_mode = "Force after 1 miss", reset_on_hit = true, description = "Best for Scout/Deagle rushes" },
    ["Defensive"] = { speed_threshold = 320, confidence_threshold = 30, miss_mode = "Prefer after 2 miss", description = "Best for AWP/Auto holding" }
}

local function apply_smart_baim_preset()
    return smart_baim_presets[ui.rage.mode:get()] or smart_baim_presets["Default"]
end

local function apply_smart_hitbox_override(player, data)
    if not ui.rage.smart_baim:get() then
        plist.set(player, "Override prefer body aim", "-"); plist.set(player, "Override safe point", "-")
        data.baim_reason = nil; data.lethal_mindmg_required = nil; return
    end
    
    local speed = get_player_speed_cached(player)
    local local_player = entity.get_local_player()
    if not local_player then return end
    
    local my_w_type = get_weapon_type(entity.get_player_weapon(local_player))
    local hp = get_cached_prop(player, "m_iHealth", 100)
    local is_lethal = hp <= ui.rage.lethal_threshold:get()
    
    data.body_aimable = is_lethal
    data.lethal_shot_available = is_lethal
    
    -- If they aren't lethal, reset overrides and aim normally
    if not is_lethal then 
        plist.set(player, "Override prefer body aim", "-"); plist.set(player, "Override safe point", "-"); 
        data.baim_reason = "HEAD"; data.lethal_mindmg_required = nil; return 
    end
    
    local l_mode, baim, safe, reason = ui.rage.lethal_mode:get(), false, false, nil
    local acc = calculate_shot_accuracy(player)
    
    -- ==========================================
    -- VISIBILITY CHECK: Is the body actually hittable?
    -- ==========================================
    local est_body_damage = calculate_body_damage(player, local_player)
    
    if est_body_damage < hp and est_body_damage < 5 then
        baim = false
        reason = "LETHAL_BODY_OCCLUDED" 
    else
        if l_mode == "Force body (strict)" then 
            baim = true; reason = "LETHAL_STRICT"
        elseif l_mode == "Prefer body (flexible)" then 
            if data.confidence >= 90 and speed < 5 and acc >= ui.rage.accuracy_threshold:get() then 
                baim = false; reason = "LETHAL_HEAD_OVERRIDE" 
            else 
                baim = true; reason = "LETHAL_PREFER" 
            end
        elseif l_mode == "Smart (adjust by accuracy)" then 
            if acc < ui.rage.accuracy_threshold:get() then 
                baim = true; reason = "LETHAL_SMART_LOW_ACC" 
            elseif data.confidence < 75 then 
                baim = true; reason = "LETHAL_SMART_LOW_CONF" 
            else 
                baim = false; reason = "LETHAL_SMART_HIGH_ACC" 
            end 
        end
    end
    
    if data.misses >= 2 or (acc < 70 and is_lethal) then 
        safe = true; reason = (reason or "LETHAL") .. "_SAFEPOINT" 
    end
    
    -- Apply the hitbox safety overrides to the aimbot
    plist.set(player, "Override prefer body aim", baim and "Force" or "-")
    plist.set(player, "Override safe point", safe and "On" or "-")
    
    -- ==========================================
    -- SCOUT-ONLY MIN DAMAGE OVERRIDE
    -- ==========================================
    if is_lethal and baim and ui.rage.lethal_override_mindmg:get() and my_w_type == "scout" then 
        data.lethal_mindmg_required = math.min(hp + (entity.get_prop(player, "m_ArmorValue") > 0 and 5 or 0), 100) 
    else 
        data.lethal_mindmg_required = nil 
    end
    
    data.baim_reason = reason
end

-- ============================================================================
-- PRIMARY RESOLVER LOGIC MULTI METHOD SUBROUTINES
-- ============================================================================
local function ai_resolve(player, data)
    -- Start with a baseline confidence instead of 0
    local conf = 30
    
    -- Run analysis modules
    analyze_desync_patterns(player, data)
    adaptive_confidence_system(player, data)
    predict_movement_trajectory(player, data)
    detect_desync_break(player, data)
    analyze_layer_correlations(player, data)
    predict_peek_behavior(player, data)
    update_weapon_priority(player, data)
    
    local w = data.method_weights
    local lby = entity.get_prop(player, "m_flLowerBodyYawTarget") or 0
    local by = get_dynamic_body_yaw(player) -- Dynamically mapped via C++ engine structures
    local speed = get_player_speed_cached(player)
    
    -- ==========================================
    -- PHASE 1: SIDE VOTING (Left vs Right)
    -- ==========================================
    local vote_left, vote_right = 0, 0
    
    -- 1. LBY Analysis Vote
    local d_lby = angle_diff(lby, data.last_lby)
    if math_abs(d_lby) > 35 then 
        if d_lby > 0 then vote_right = vote_right + w.lby_delta
        else vote_left = vote_left + w.lby_delta end
        conf = conf + 25 * w.lby_delta 
    end
    
    -- 2. Movement Analysis Vote
    if speed > 5 then
        local anim = get_anim_state(get_entity_address(player))
        if anim then 
            local my = anim.flMoveYaw
            if my >= -180 and my < 0 then vote_right = vote_right + w.movement
            else vote_left = vote_left + w.movement end
            conf = conf + 20 * w.movement 
        end
    else
        -- Standing Fallback Vote
        if lby > 0 then vote_right = vote_right + 0.3
        else vote_left = vote_left + 0.3 end
    end
    
    -- 3. Pattern Recognition Vote
    if data.patterns.consistent_side ~= 0 then 
        if data.patterns.consistent_side > 0 then vote_left = vote_left + w.pattern
        else vote_right = vote_right + w.pattern end
        conf = conf + 15 * w.pattern 
    end

    -- Tally the votes to get the definitive side
    local final_side = (vote_left > vote_right) and 1 or -1
    
    -- ==========================================
    -- PHASE 2: DYNAMIC MAGNITUDE DETERMINATION
    -- ==========================================
    local magnitude = 58 -- Baseline Fallback
    local advanced_settings = ui.resolver.advanced:get()
    
    -- Isolate the dynamic base magnitude from the animation state
    local raw_magnitude = by and math_abs(by) or 58
    
    -- Check if target is actively oscillating (Jittering)
    if data.patterns.oscillation and raw_magnitude > 5 then
        -- Trigger Jitter Engine: Parse out Bound A and Bound B from telemetry
        local bound_a, bound_b = extract_jitter_bounds(player, data, raw_magnitude)
        
        -- Predict active state based on tick count alternation parity
        if globals.tickcount() % 2 == 0 then
            magnitude = bound_a
        else
            magnitude = bound_b
        end
        conf = conf + 35 -- Boost confidence since we have fully mapped their jitter spectrum
    elseif by and math_abs(by) > 5 then
        -- Stable custom desync tracking (Non-Jitter)
        if not data.fake_desync_detected and not data.suspicious_animation then
            magnitude = raw_magnitude
            conf = conf + 15
        end
    end

    -- Low Delta Override
    if speed < 5 and contains(advanced_settings, "Low Delta Detect") and magnitude < 35 then
        conf = conf + 25
        final_side = by > 0 and -1 or 1 
    end

    -- Contextual Scaling (Slight situational adjustments)
    if data.resolver_context == "aggressive" then 
        magnitude = math_min(60, magnitude + 2)
    elseif data.resolver_context == "defensive" then 
        magnitude = math_max(15, magnitude - 5)
    end
    
    -- ==========================================
    -- PHASE 3: FINAL CALCULATION
    -- ==========================================
    local res = final_side * magnitude
    
    -- Failsafe
    if math_abs(res) < 5 then res = lby > 0 and -58 or 58 end

    -- Real-World Performance Scaler: Deduct confidence based on verified whiffs
    if data.misses and data.misses > 0 then
        conf = conf - (data.misses * 25)
    end
    if data.hits and data.hits > 0 then
        conf = conf + (data.hits * 15)
    end
    
    data.confidence = clamp(conf, 0, 100)
    data.resolved_angle = clamp(res, -60, 60)
    
    return data.resolved_angle
end

local function analyze_animation_layers(player, data)
    local layers = get_anim_layers(get_entity_address(player))
    if not layers then return false end
    data.layer_data.move_weight = layers[6].m_weight; data.layer_data.move_cycle = layers[6].m_cycle; data.layer_data.move_playback = layers[6].m_playback_rate
    data.layer_data.stand_cycle = layers[3].m_cycle; data.layer_data.stand_weight = layers[3].m_weight
    return true
end

local function get_move_direction_side(player, data)
    local vx, vy = get_cached_prop(player, "m_vecVelocity", 0)
    if not vx or not vy or math.sqrt(vx*vx + vy*vy) < 1 then return 0 end
    local anim = get_anim_state(get_entity_address(player))
    if not anim then return 0 end
    local my = anim.flMoveYaw
    if my > 5 and my <= 180 then return -1 elseif my >= -180 and my < -5 then return 1
    elseif my > 175 or my < -175 then return -1
    elseif math.abs(my) < 5 then return (entity.get_prop(player, "m_flPoseParameter", 11) * 120 - 60) > 0 and -1 or 1 end
    return 0
end

local function detect_peek_state(player, data)
    local vx, vy = get_cached_prop(player, "m_vecVelocity", 0)
    if not vx or not vy then return "unknown", 0 end
    local speed = math.sqrt(vx*vx + vy*vy)
    local peek = data.peek_state
    peek.acceleration = speed - peek.last_speed
    local cur_dir = math.deg(math.atan2(vy, vx))
    peek.direction_changes = math.abs(normalize_angle(cur_dir - peek.last_direction)) > 90 and (speed > 50 and peek.direction_changes + 1 or peek.direction_changes) or math.max(0, peek.direction_changes - 0.1)
    
    if peek.direction_changes > 2 and speed > 100 and speed < 220 then peek.peek_type = "jiggle"; peek.peek_confidence = 90
    elseif speed > 220 and peek.acceleration > 50 then peek.peek_type = "fast_peek"; peek.peek_confidence = 85
    elseif speed > 50 and speed < 150 and peek.acceleration < -30 then peek.peek_type = "shoulder"; peek.peek_confidence = 80
    elseif speed > 200 and math.abs(peek.acceleration) < 20 then peek.peek_type = "wide"; peek.peek_confidence = 75
    elseif peek.last_speed > 100 and speed < 30 then peek.peek_type = "stop"; peek.peek_confidence = 85
    elseif speed < 5 then peek.peek_type = "holding"; peek.peek_confidence = 95
    else peek.peek_type = "moving"; peek.peek_confidence = 60 end
    peek.last_speed = speed; peek.last_direction = cur_dir
    return peek.peek_type, peek.peek_confidence
end

local function resolve_peek_adaptive(player, data, peek_type, peek_confidence)
    local vx, vy = get_cached_prop(player, "m_vecVelocity", 0)
    if not vx or not vy then return false, nil end
    local speed = math.sqrt(vx*vx + vy*vy)
    local lby = entity.get_prop(player, "m_flLowerBodyYawTarget") or 0
    local by = entity.get_prop(player, "m_flPoseParameter", 11)
    if by then by = by * 120 - 60 end
    local reliable = data.reliable_angles
    
    if peek_type ~= "jiggle" and peek_type ~= "fast_peek" and speed > 5 and speed < 200 then
        local cur_ang = (by and math.abs(by) > 20) and by or (lby and (lby > 0 and -58 or 58) or 0)
        if cur_ang ~= 0 then
            local target_bucket = cur_ang > 0 and reliable.right_angles or reliable.left_angles
            table.insert(target_bucket, 1, cur_ang); if #target_bucket > 10 then table.remove(target_bucket) end
            reliable.last_reliable_angle = cur_ang; reliable.last_reliable_tick = globals.tickcount()
        end
    end
    
    if peek_type == "jiggle" then
        local l_avg, r_avg = 0, 0
        if #reliable.left_angles > 0 then local s = 0; for i=1,#reliable.left_angles do s=s+reliable.left_angles[i] end; l_avg = s/#reliable.left_angles end
        if #reliable.right_angles > 0 then local s = 0; for i=1,#reliable.right_angles do s=s+reliable.right_angles[i] end; r_avg = s/#reliable.right_angles end
        if (globals.tickcount() - reliable.last_reliable_tick) < 64 and reliable.last_reliable_angle ~= 0 then data.confidence = 85; return true, reliable.last_reliable_angle end
        if #reliable.left_angles > 3 or #reliable.right_angles > 3 then
            local left_larger = #reliable.left_angles > #reliable.right_angles
            data.confidence = math.min(95, 75 + (left_larger and #reliable.left_angles or #reliable.right_angles) * 2)
            return true, left_larger and l_avg or r_avg
        end
        data.confidence = 55; return true, lby > 0 and -58 or 58
    elseif peek_type == "fast_peek" then
        local delta = normalize_angle(math.deg(math.atan2(vy, vx)) - (entity.get_prop(player, "m_angEyeAngles[1]") or 0))
        if math.abs(delta) > 45 and math.abs(delta) < 135 then
            local target_bucket = delta > 0 and reliable.right_angles or reliable.left_angles
            if #target_bucket > 0 then local s = 0; for i=1,math.min(3,#target_bucket) do s=s+target_bucket[i] end; data.confidence = 82; return true, s/math.min(3,#target_bucket) end
            data.confidence = 70; return true, delta > 0 and 58 or -58
        end
        if by and math.abs(by) > 20 then data.confidence = 68; return true, by > 0 and -55 or 55 end
    elseif peek_type == "shoulder" then
        if reliable.last_reliable_angle ~= 0 and (globals.tickcount() - reliable.last_reliable_tick) < 32 then data.confidence = 88; return true, reliable.last_reliable_angle end
        if by and math.abs(by) > 20 then data.confidence = 75; return true, by > 0 and -58 or 58 end
    elseif peek_type == "stop" then data.confidence = 92; return true, lby > 0 and -60 or 60
    elseif peek_type == "wide" then
        local anim = get_anim_state(get_entity_address(player))
        if anim and math.abs(anim.flMoveYaw) < 30 then data.confidence = 78; return true, by and (by > 0 and -40 or 40) or 0 end
        data.confidence = 75; return true, anim and (anim.flMoveYaw > 0 and 50 or -50) or 0
    end
    return false, nil
end

local function smart_resolve(player, data)
    local dec = ui.resolver.detection:get()
    local conf, side, offset = 40, 0, 0
    local vx, vy = get_cached_prop(player, "m_vecVelocity", 0)
    local speed = (vx and vy) and math.sqrt(vx*vx + vy*vy) or 0
    local lby = entity.get_prop(player, "m_flLowerBodyYawTarget") or 0
    
    local p_type, p_conf = detect_peek_state(player, data)
    local p_res, p_ang = resolve_peek_adaptive(player, data, p_type, p_conf)
    if p_res and p_ang then data.last_peek_type = p_type; data.resolved_angle = p_ang; return p_ang end
    if speed > 220 and entity.get_prop(player, "m_angEyeAngles[1]") then
        local sd = normalize_angle(math.deg(math.atan2(vy, vx)) - entity.get_prop(player, "m_angEyeAngles[1]"))
        if math.abs(sd) > 60 and math.abs(sd) < 120 then data.confidence = 92; data.resolved_angle = sd > 0 and -58 or 58; return data.resolved_angle end
    end
    
    if detect_defensive_comprehensive(player, data) and is_valid_defensive_detection(player, data, { detected = true, confidence = data.defensive_suspicion_score or 0 }) and data.defensive_ticks > 2 then
        local d_ang = resolve_defensive(player, data)
        if d_ang then data.resolved_angle = d_ang; return d_ang end
    end
    detect_airborne_state(player, data)
    local air_res, air_ang = resolve_airborne(player, data)
    if air_res and air_ang then return air_ang end
    detect_crouch_state(player, data)
    local cr_res, cr_ang = resolve_crouching(player, data)
    if cr_res and cr_ang then return cr_ang end
    
    if contains(dec, "Pattern Recognition") then analyze_desync_patterns(player, data) end
    adaptive_confidence_system(player, data); predict_movement_trajectory(player, data)
    if contains(dec, "Desync Break Detection") then detect_desync_break(player, data) end
    analyze_layer_correlations(player, data)
    if data.fake_desync_detected then lby = data.true_lby end
    if contains(dec, "Peek Prediction") then predict_peek_behavior(player, data) end
    if contains(dec, "Weapon Awareness") then update_weapon_priority(player, data) end
    
    if contains(dec, "LBY Analysis") and math.abs(angle_diff(lby, data.last_lby)) > 35 then side = angle_diff(lby, data.last_lby) > 0 and -1 or 1; conf = conf + 25 end
    if contains(dec, "Movement Tracking") then
        if speed > 2.0 then local ms = get_move_direction_side(player, data); if ms ~= 0 then side = ms; conf = conf + 20; data.moving_ticks = data.moving_ticks + 1; data.standing_ticks = 0 end else data.standing_ticks = data.standing_ticks + 1; data.moving_ticks = 0 end
    end
    if contains(dec, "Standing Detection") and data.standing_ticks > 32 then side = lby > 0 and -1 or 1; conf = conf + 30 end
    if contains(dec, "Animation Analysis") and analyze_animation_layers(player, data) then conf = conf + 15 end
    if contains(dec, "Pattern Recognition") and data.patterns.consistent_side ~= 0 then side = data.patterns.consistent_side; conf = conf + 20 end
    if contains(dec, "Pose Parameters") then local b_pred, b_ang = predict_body_yaw_update(player, data); if b_pred and b_ang then side = b_ang > 0 and 1 or -1; conf = conf + 20; offset = b_ang end end
    if contains(dec, "Velocity Prediction") then local v_res, v_ang = resolve_by_velocity_advanced(player, data); if v_res and v_ang then side = v_ang > 0 and 1 or -1; conf = conf + 25; offset = v_ang end end
    if contains(dec, "Standing Detection") then
        local s_res, s_ang = resolve_standing_improved(player, data, lby)
        if s_res and s_ang then
            if data.standing_locked_angle and data.standing_lock_until and globals.tickcount() <= data.standing_lock_until then data.confidence = math.min(100, conf + 50); data.resolved_angle = s_ang; return s_ang end
            side = s_ang > 0 and 1 or -1; conf = conf + 35; offset = s_ang
        end
    end
    if contains(dec, "Layer Weight") then local ln_res, ln_ang = analyze_lean_layer(player, data); if ln_res and ln_ang then side = ln_ang > 0 and 1 or -1; conf = conf + 18; offset = ln_ang end end
    if contains(dec, "Micro Movement") and speed < 3 and speed > 0.1 then
        local ptr = get_entity_address(player); local ly = ptr and get_anim_layers(ptr) or nil
        if ly and ly[6].m_playback_rate * 100000 > 5.9 then side = 1 else side = -1 end; conf = conf + 20
    end
    
    if data.last_update then
        local dt = globals.curtime() - data.last_update
        if dt > 0.3 then conf = conf * math.exp(-(data.hit_rate > 0.7 and 0.08 or (data.hit_rate < 0.3 and 0.25 or 0.15)) * dt) end
    end
    data.last_update = globals.curtime(); data.desync_side = side; data.confidence = math.min(100, conf); data.last_lby = lby
    
    if data.recent_angles and #data.recent_angles >= 3 then
        local cs = true; for i=1,3 do if data.recent_angles[i] and math.abs(data.recent_angles[i] - offset) > 25 then cs = false; break end end
        if cs then data.confidence = math.min(100, data.confidence + 15) end
    end
    if data.last_predicted_side == side then data.confidence = math.min(100, data.confidence + 5) end; data.last_predicted_side = side
    offset = side * (ui.resolver.desync_strength:get() * 0.6)
    if math.abs(offset) < 5 then offset = lby > 0 and -58 or 58; data.confidence = 50 end
    if not data.is_defensive and data.confidence > 60 and data.resolved_angle and data.resolved_angle ~= 0 then data.last_good_angle = data.resolved_angle; data.last_good_angle_tick = globals.tickcount() end
    if data.last_successful_angle and data.last_successful_time and (globals.curtime() - data.last_successful_time) < 2.0 and conf < 50 then data.confidence = 65; return data.last_successful_angle end
    return offset
end

local function bruteforce_resolve(player, data)
    local mode, max_ph = ui.resolver.brute_mode:get(), ui.resolver.brute_phases:get()
    if data.brute_working and data.brute_locked then return data.resolved_angle end
    if mode == "Intelligent" then mode, max_ph = intelligent_bruteforce(player, data) end
    local offset = 0
    if mode == "Sequential" then offset = -60 + (data.brute_phase - 1) * (120 / max_ph)
    elseif mode == "Random" then offset = math.random(-60, 60)
    elseif mode == "Smart" then
        if data.shots > 0 then data.hit_rate = data.hits / data.shots; if data.hit_rate > 0.5 then data.brute_working = true; data.brute_locked = true else data.desync_side = -data.desync_side end end
        offset = data.desync_side * 60
    elseif mode == "Adaptive" then
        local lby = entity.get_prop(player, "m_flLowerBodyYawTarget") or 0
        if data.shots > 2 and data.hit_rate > 0.6 then data.brute_locked = true else data.desync_side = lby > 0 and -1 or 1 end
        offset = data.desync_side * (40 + data.brute_phase * 5)
    end
    data.resolved_angle = offset; return offset
end

local function detect_shot_timing(player, data)
    local wp = entity.get_player_weapon(player)
    if not wp then return false, nil end
    local lst = entity.get_prop(wp, "m_fLastShotTime")
    if not lst then return false, nil end
    local dt = globals.curtime() - lst
    if dt < 0.2 then
        local by = entity.get_prop(player, "m_flPoseParameter", 11)
        if by then by = by * 120 - 60; data.shot_snapshot_angle = by > 0 and 58 or -58; data.shot_snapshot_time = globals.curtime(); data.shot_locked = true; data.confidence = 98; return true, data.shot_snapshot_angle end
    else data.shot_locked = false end
    if data.shot_snapshot_time and (globals.curtime() - data.shot_snapshot_time) < 0.3 then data.confidence = 95; return true, data.shot_snapshot_angle end
    return false, nil
end

local function analyze_choke_stability(player, data)
    local choke = get_choke_from_simtime(player)
    if choke == 0 then return 1.0 end
    data.choke_history:push(choke)
    if choke >= 12 then data.confidence = math.min(100, data.confidence + 15); return 0.8
    elseif choke <= 3 then data.confidence = math.max(50, data.confidence - 10); return 1.2 end
    return 1.0
end

local function predict_lby_update(player, data)
    if not entity.is_alive(player) or entity.is_dormant(player) then return false, nil end
    
    local lby = entity.get_prop(player, "m_flLowerBodyYawTarget") or 0
    local speed = get_player_speed_cached(player)
    local cur_time = globals.curtime()
    
    -- Initialize state variables if missing
    if data.was_moving == nil then data.was_moving = true end
    
    -- ==========================================
    -- ENGINE STATE TRACKING (THE STOPWATCH)
    -- ==========================================
    if speed > 1.5 then
        -- Target is actively moving; reset stationary timelines
        data.was_moving = true
        data.time_entered_stationary = nil
        data.lby_update_imminent = false
        data.last_lby = lby
        return false, nil
    else
        -- Target just transitioned to a full stop
        if data.was_moving then
            data.was_moving = false
            data.time_entered_stationary = cur_time
            data.next_predicted_lby_update = cur_time + 0.22 -- Hard lock onto the initial 0.22s window
            data.is_in_cyclical_lby_loop = false
        end
    end
    
    -- Failsafe: If stopwatch data was lost, abort calculation
    if not data.time_entered_stationary then return false, nil end
    
    local time_stopped = cur_time - data.time_entered_stationary
    local update_imminent = false
    local confidence_payout = 0
    
    -- ==========================================
    -- TIMELINE EVALUATION ENGINE
    -- ==========================================
    if not data.is_in_cyclical_lby_loop then
        -- CRITICAL STATE 1: Evaluating the Initial 0.22-second Stop-Flick
        if time_stopped >= 0.18 and time_stopped <= 0.24 then
            update_imminent = true
            confidence_payout = 96 -- Absolute high confidence peak
        elseif time_stopped > 0.24 then
            -- Initial 0.22s window has passed; advance to standard 1.1s loops
            data.is_in_cyclical_lby_loop = true
            data.next_predicted_lby_update = data.time_entered_stationary + 0.22 + 1.1
        end
    else
        -- CRITICAL STATE 2: Evaluating the 1.1-second Cyclical Loops
        local time_in_cycles = time_stopped - 0.22
        local cycle_progress = time_in_cycles % 1.1
        
        -- Check if current tick aligns with the 1.1s update boundary (with a 0.05s tolerance window)
        if cycle_progress >= 1.05 or cycle_progress <= 0.05 then
            update_imminent = true
            confidence_payout = 92
        end
    end
    
    -- Check if server network metrics confirm a manual value change occurred independently
    if math_abs(angle_diff(lby, data.last_lby)) > 35 then
        data.last_lby = lby
        -- Reset cyclical stopwatch back to 1.1s relative to the value skip
        if data.is_in_cyclical_lby_loop then
            data.time_entered_stationary = cur_time - 0.22
        end
    end
    
    -- ==========================================
    -- VALUE PROJECTION
    -- ==========================================
    if update_imminent then
        data.confidence = math_max(data.confidence, confidence_payout)
        data.lby_update_imminent = true
        
        -- When LBY updates on stationary targets, resolve directly OPPOSITE of the target value
        local resolved_angle = lby > 0 and -58 or 58
        return true, resolved_angle
    end
    
    data.lby_update_imminent = false
    return false, nil
end

local function track_pose_delta_speed(player, data)
    local cp = entity.get_prop(player, "m_flPoseParameter", 11) * 120 - 60
    data.pose_history:push({ value = cp, time = globals.curtime() })
    local hist = data.pose_history:get_all()
    if #hist >= 3 then
        local d1, d2 = math.abs(hist[1].value - hist[2].value), math.abs(hist[2].value - hist[3].value)
        if d1 > 80 and d2 > 80 then data.jitter_detected = true; data.jitter_side_preference = hist[1].value > 0 and 1 or -1; return true, (data.jitter_side_preference * 58) end
        if (math.abs(hist[1].value - hist[3].value) / (hist[1].time - hist[3].time)) < 60 then data.confidence = math.min(100, data.confidence + 10) end
    end
    return false, nil
end

local function get_contextual_phase_bias(player, data)
    local vx, vy = get_cached_prop(player, "m_vecVelocity", 0)
    local speed = (vx and vy) and math.sqrt(vx*vx + vy*vy) or 0
    local bias = {}
    if speed < 5 then bias[3] = 1.3; bias[2] = 1.1; bias[4] = 1.1; bias[1] = 0.9; bias[5] = 0.9
    elseif speed > 220 then bias[1] = 1.3; bias[5] = 1.3; bias[3] = 0.7; bias[2] = 1.0; bias[4] = 1.0
    else for i=1,5 do bias[i] = 1.0 end end
    return bias
end

local function detect_brute_counter(player, data)
    if not data.phase_hit_pattern then data.phase_hit_pattern = {} end
    table.insert(data.phase_hit_pattern, 1, { phase = data.brute_phase, hit = data.last_shot_hit, time = globals.curtime() })
    if #data.phase_hit_pattern > 10 then table.remove(data.phase_hit_pattern) end
    if #data.phase_hit_pattern >= 6 then
        local ms = 0; for i=1,6 do if not data.phase_hit_pattern[i].hit then ms = ms + 1 end end
        if ms >= 5 then data.brute_counter_detected = true; data.brute_counter_time = globals.curtime(); return true end
    end
    return false
end

local function predict_best_brute_phase(player, data)
    if detect_brute_counter(player, data) then return math.random(1, 5) end
    if not data.brute_phase_success then return 1 end
    local scr, ct, bias = {}, globals.curtime(), get_contextual_phase_bias(player, data)
    
    for p = 1, 5 do
        local pd = data.brute_phase_success[p]
        if not pd or ((pd.hits or 0) + (pd.misses or 0)) == 0 then scr[p] = 0
        else
            local age = ct - (pd.time or 0); local fresh = math.exp(-age / 10)
            local rate = (pd.hits * fresh) / ((pd.hits + pd.misses) * fresh)
            local p_bonus = (data.jitter_detected and math.abs(p - (data.last_brute_phase or 1)) >= 2) and 0.2 or 0
            local v_bonus = 0; local vx, vy = get_cached_prop(player, "m_vecVelocity", 0)
            if vx then local s = math.sqrt(vx*vx + vy*vy); if s > 200 and (p==1 or p==5) then v_bonus = 0.15 elseif s < 5 and p==3 then v_bonus = 0.2 end end
            scr[p] = ((rate * 100 * math.exp(-age / 5) * (data.confidence < 50 and 1.3 or 1.0)) + (p_bonus * 50) + (v_bonus * 50)) * (bias[p] or 1.0)
        end
    end
    
    local viable = {}
    for p = 1, 5 do local pd = data.brute_phase_success[p]; if not (pd and ((pd.hits or 0) + (pd.misses or 0)) > 5 and (pd.hits / (pd.hits + pd.misses)) < 0.15) then table.insert(viable, p) end end
    if #viable == 0 then viable = {1, 2, 3, 4, 5} end
    local b_ph, b_scr = 1, -1
    for _, p in ipairs(viable) do if scr[p] > b_scr then b_ph = p; b_scr = scr[p] end end
    if data.brute_phase and scr[data.brute_phase] and b_scr < scr[data.brute_phase] * 1.3 then return data.brute_phase end
    data.last_brute_phase = b_ph; return b_ph
end

local function calculate_ideal_tick(player, data)
    if not ui.rage.ideal_tick:get() then return 0 end
    local chk = get_choke_from_simtime(player)
    if chk >= 2 and chk <= 12 then data.confidence = math.min(100, data.confidence + 15); data.ideal_tick = true; return 1
    elseif chk > 12 then data.confidence = math.max(20, data.confidence - 15); data.ideal_tick = false; return -1 end
    data.ideal_tick = false; return 0
end

local function get_best_backtrack_tick(player, data)
    if not lag_records[player] or #lag_records[player] == 0 then return nil end
    
    local best, b_scr = nil, -1
    local is_jittering = data.patterns and data.patterns.oscillation
    
    for i = 1, math.min(#lag_records[player], 12) do
        local rec = lag_records[player][i]
        if rec then
            local age = globals.tickcount() - rec.tickcount
            
            -- Ensure the record is still physically valid within the standard 200ms backtrack window
            if age >= 0 and age <= 12 then
                -- Base score starts high, degrades smoothly with age to prevent ghost-hitting
                local scr = 100 - (age * 6)
                
                -- Velocity Stability Bonus (Slower hitboxes have less interpolation drag/distortion)
                if rec.velocity and rec.velocity.x and rec.velocity.y then 
                    local s = math.sqrt(rec.velocity.x^2 + rec.velocity.y^2)
                    scr = scr + (s < 10 and 35 or (s < 100 and 15 or 0)) 
                end
                
                -- Simtime Freshness Bonus (Directly combats Fake Lag desync)
                if rec.simtime then
                    local sim_age = globals.curtime() - rec.simtime
                    if sim_age < 0.2 then scr = scr + 40
                    elseif sim_age < 0.4 then scr = scr + 20 end
                end
                
                -- LBY Matching Logic (Nerfed for Jitter, applied strictly for stable targets)
                if not is_jittering and rec.lby and data.last_lby then 
                    local d = math.abs(angle_diff(rec.lby, data.last_lby))
                    -- Only grant a minor bonus for stable LBY, never enough to override physical freshness
                    scr = scr + (d < 10 and 15 or 0) 
                end
                
                if scr > b_scr then 
                    b_scr = scr
                    best = rec 
                    best.score = scr -- Save score for the hint_best_backtrack_tick analyzer
                end
            end
        end
    end
    
    return best
end

local function hint_best_backtrack_tick(player, data)
    local best = get_best_backtrack_tick(player, data)
    if not best then data.backtrack_ticks = nil; data.backtrack_score = nil; return end
    local age = globals.tickcount() - best.tickcount
    if age < 0 or age > 12 then data.backtrack_ticks = nil; data.backtrack_score = nil; return end
    data.backtrack_ticks = age; data.backtrack_score = best.score or 100
    if age <= 3 and data.backtrack_score > 150 then data.confidence = math.min(100, data.confidence + 15)
    elseif age <= 5 and data.backtrack_score > 120 then data.confidence = math.min(100, data.confidence + 10)
    elseif age >= 8 or data.backtrack_score < 80 then data.confidence = math.max(30, data.confidence - 8) end
end

local local_velocity_history = {}
local fakelag_fluctuation = 0
local fakelag_send_count = 0
local fakelag_last_send_tick = -1

local function optimize_fakelag(cmd)
    if not ui.rage.smart_fakelag:get() then
        fakelag_ref:override()
        return
    end

    local me = entity.get_local_player()
    if not me or not entity.is_alive(me) then
        fakelag_ref:override()
        return
    end

    if f_duck_ref and f_duck_ref:get() then
        fakelag_ref:override(15)
        return
    end

    if exploits:in_recharge() then
        fakelag_ref:override(1)
        return
    end

    if exploits:in_defensive() then
        fakelag_ref:override(15)
        return
    end

    local lat = (client.latency() or 0) * 1000
    local vx, vy = entity.get_prop(me, "m_vecVelocity")
    local speed = (vx and vy) and math.sqrt(vx * vx + vy * vy) or 0

    local prev_speed = local_velocity_history[me] or speed
    local acceleration = speed - prev_speed
    local_velocity_history[me] = speed

    local tick = globals.tickcount()
    if cmd and cmd.chokedcommands == 0 and fakelag_last_send_tick ~= tick then
        fakelag_last_send_tick = tick
        fakelag_send_count = fakelag_send_count + 1
        if fakelag_send_count % 3 == 0 then
            fakelag_fluctuation = (fakelag_fluctuation + 1) % 3
        end
    end

    local limit
    if acceleration > 25 then
        limit = 12 + (fakelag_fluctuation % 2)
    elseif speed > 100 then
        limit = 10 + fakelag_fluctuation
    elseif speed < 5 then
        limit = 3 + (fakelag_fluctuation % 2)
    else
        limit = 6 + fakelag_fluctuation
    end

    if lat > 140 then
        limit = math_min(limit, 5)
    elseif lat > 120 then
        limit = math_min(limit, 7)
    elseif lat > 80 then
        limit = math_min(limit, 10)
    end

    fakelag_ref:override(limit)
end

local firearm_ids = {1,2,3,4,7,8,9,10,11,13,14,16,17,19,24,25,26,27,28,29,30,32,33,34,35,36,38,39,40,60,61,63,64}
local pistol_ids = {1,2,3,4,30,32,36,61,63,64}
local sniper_ids = {9,11,38,40}
local autostop_was_viable = false
local autostop_last_threat = nil
local autostop_burst_until = 0

local function apply_predictive_autostop(cmd, threat)
    if not ui.rage.predictive_autostop:get() or not threat or not entity.is_alive(threat) or entity.is_dormant(threat) then
        autostop_was_viable = false
        autostop_last_threat = nil
        return
    end

    local me = entity.get_local_player()
    if not me or not entity.is_alive(me) then return end

    local flags = entity.get_prop(me, "m_fFlags") or 0
    local move_type = entity.get_prop(me, "m_MoveType")
    if bit.band(flags, 1) == 0 or move_type == 8 or move_type == 9 then return end

    local weapon = entity.get_player_weapon(me)
    if not weapon then return end
    local weapon_id = bit.band(entity.get_prop(weapon, "m_iItemDefinitionIndex") or 0, 0xFFFF)
    if not contains(firearm_ids, weapon_id) then return end

    local clip = entity.get_prop(weapon, "m_iClip1")
    if clip ~= nil and clip <= 0 then return end

    local ready_at = math_max(
        entity.get_prop(me, "m_flNextAttack") or 0,
        entity.get_prop(weapon, "m_flNextPrimaryAttack") or 0
    )
    if ready_at > globals.curtime() + globals.tickinterval() * 3 then return end

    local eye_x, eye_y, eye_z = client.eye_position()
    if not eye_x then return end
    local viable = false
    local hitboxes = contains(pistol_ids, weapon_id) and {0} or {0, 2, 4}
    for _, hitbox in ipairs(hitboxes) do
        local hit_x, hit_y, hit_z = entity.hitbox_position(threat, hitbox)
        if hit_x then
            local hit_entity, damage = client.trace_bullet(me, eye_x, eye_y, eye_z, hit_x, hit_y, hit_z, false)
            if hit_entity == threat and damage and damage > 0 then
                viable = true
                break
            end
        end
    end
    if not viable then
        autostop_was_viable = false
        return
    end

    local tick = globals.tickcount()
    if not autostop_was_viable or autostop_last_threat ~= threat then
        local stop_ticks = contains(sniper_ids, weapon_id) and 12 or (contains(pistol_ids, weapon_id) and 5 or 8)
        autostop_burst_until = tick + stop_ticks
    end
    autostop_was_viable = true
    autostop_last_threat = threat
    local attacking = cmd.in_attack == 1 or cmd.in_attack == true
    if tick > autostop_burst_until and not attacking then return end

    local vx, vy = entity.get_prop(me, "m_vecVelocity")
    if not vx or not vy then return end
    local speed = math.sqrt(vx * vx + vy * vy)
    if speed < 5 then
        autostop_burst_until = tick - 1
        return
    end

    local view_yaw = cmd.yaw
    if view_yaw == nil then
        local _, camera_yaw = client.camera_angles()
        view_yaw = camera_yaw or 0
    end

    local direction = math.rad(view_yaw - math.deg(math.atan2(vy, vx)))
    local counter_speed = speed < 34 and math_min(450, speed * 12) or 450
    cmd.forwardmove = math.cos(direction) * -counter_speed
    cmd.sidemove = math.sin(direction) * -counter_speed
end

local function apply_backtrack_compensation(player, data, base_angle)
    if not data.backtrack_ticks or not data.backtrack_score then return base_angle end
    if data.backtrack_ticks >= 10 then return base_angle * 0.85 end
    if data.backtrack_ticks <= 3 and data.backtrack_score > 150 then return base_angle * 1.1 end
    return data.backtrack_score < 80 and base_angle * 0.7 or base_angle
end

-- ============================================================================
-- MAIN CORE RESOLVER PIPELINE EXECUTION ENGINE
-- ============================================================================
local function resolve_player(player)
    if not ui.enable:get() then return end
    if not entity.is_alive(player) then
        plist.set(player, "Force body yaw", false); plist.set(player, "Force body yaw value", 0); plist.set(player, "Correction active", true); return
    end
    
    local res_ang, method, s_act, s_ang, l_act, l_ang, j_act, j_ang, chk_mod = 0, "unknown", false, nil, false, nil, false, nil, 1.0
    local data = init_player_data(player)
    hint_best_backtrack_tick(player, data)
    local mode = ui.home.mode:get()
    
    local hp = get_cached_prop(player, "m_iHealth", 100)
    if data.last_known_health and hp > data.last_known_health + 50 then data.body_aimable = false; data.lethal_shot_available = false; data.estimated_body_damage = 0 end
    data.last_known_health = hp; init_lag_record(player)
    
    local x, y, z = entity.get_prop(player, "m_vecOrigin")
    if x then data.last_position = {x = x, y = y, z = z} end
    calculate_ideal_tick(player, data)
    
    if mode == "Override" then
        if ui.resolver.override_left:get() then plist.set(player, "Force body yaw", true); plist.set(player, "Force body yaw value", -60); return
        elseif ui.resolver.override_right:get() then plist.set(player, "Force body yaw", true); plist.set(player, "Force body yaw value", 60); return
        elseif ui.resolver.override_center:get() then plist.set(player, "Force body yaw", true); plist.set(player, "Force body yaw value", 0); return end
    end
    
    if ui.defensive.enable:get() then
        detect_defensive_comprehensive(player, data)
        if data.defensive_ticks > 0 then
            local old_t = data.defensive_ticks; data.defensive_ticks = data.defensive_ticks - 1
            if old_t > 0 and data.defensive_ticks <= 0 then
                data.is_defensive = false
                if ui.defensive.delay_head:get() then
                    local wait = contains({"fake_up", "fake_down", "pitch_oscillation", "custom_pitch", "switch_pitch"}, data.defensive_type) and 10 or (contains({"teleport", "yaw_flick", "spin"}, data.defensive_type) and 6 or 4)
                    data.defensive_wait_until = globals.tickcount() + (data.confidence < 60 and wait + 3 or (data.confidence > 85 and math.max(2, wait - 2) or wait))
                end
            end
        end
    end
    
    s_act, s_ang = detect_shot_timing(player, data); if s_act and s_ang then res_ang = s_ang; method = "shot_timing"; goto apply_res end
    l_act, l_ang = predict_lby_update(player, data); if l_act and l_ang then res_ang = l_ang; method = "lby_prediction"; goto apply_res end
    j_act, j_ang = track_pose_delta_speed(player, data); if j_act and j_ang then res_ang = j_ang; method = "jitter_detect"; goto apply_res end
    chk_mod = analyze_choke_stability(player, data)
    
    if mode == "AI" then res_ang = ai_resolve(player, data); method = "ai"
    elseif mode == "Smart" or mode == "Automatic" then res_ang = smart_resolve(player, data); method = "smart"
    elseif mode == "Bruteforce" then
        if ui.resolver.brute_mode:get() == "Intelligent" or ui.resolver.brute_mode:get() == "Adaptive" then data.brute_phase = predict_best_brute_phase(player, data) end
        res_ang = bruteforce_resolve(player, data); method = "bruteforce"
    elseif mode == "Adaptive" then
        if data.confidence > ui.resolver.confidence:get() then res_ang = smart_resolve(player, data); method = "smart"
        else data.brute_phase = predict_best_brute_phase(player, data); res_ang = bruteforce_resolve(player, data); method = "bruteforce" end
    end
    res_ang = res_ang * chk_mod
    
    ::apply_res::
    if contains(ui.resolver.advanced:get(), "Adaptive Learning") then adaptive_learning(player, data) end
    if contains(ui.resolver.advanced:get(), "Weapon Awareness") then update_weapon_priority(player, data) end
    res_ang = apply_backtrack_compensation(player, data, res_ang)
    data.resolved_angle = smooth_resolved_angle(player, data, res_ang)
    data.last_resolved_side = data.resolved_angle > 0 and 1 or -1
    
    plist.set(player, "Correction active", false); plist.set(player, "Force body yaw", true); plist.set(player, "Force body yaw value", data.resolved_angle)
    if not apply_defensive_shot_delay(player, data) and ui.rage.smart_baim:get() then apply_smart_hitbox_override(player, data) end
    update_resolver_analytics(player, data, nil, method)
end

-- ============================================================================
-- SYSTEM EVENT INTERACTION LISTENER HOOKS
-- ============================================================================
local function on_aim_miss(e)
    if not ui.enable:get() then return end
    local target = e.target
    if not entity.is_alive(target) or entity.get_prop(target, "m_bDormant") then return end
    local data = init_player_data(target)
    data.last_shot_time = globals.curtime()
    local rsn = e.reason or "?"
    local is_res_miss = not contains({"spread", "prediction error", "death"}, rsn) and (rsn ~= "?" or (e.hit_chance or 0) >= 75)
    
    data.shots = data.shots + 1; data.misses = data.misses + 1; data.last_shot_hit = false
    if is_res_miss and data.brute_phase_success[data.brute_phase] then data.brute_phase_success[data.brute_phase].misses = data.brute_phase_success[data.brute_phase].misses + 1 end
    
    local mode = ui.home.mode:get()
    local cur_spd = get_player_speed_cached(target)
    if data.last_miss_speed and math.abs(cur_spd - data.last_miss_speed) > 150 then
        data.brute_phase = 1; data.misses = 0; data.confidence = 40
        if ui.visuals.console_log:get() then client.log("↻ Reset: Player changed movement style") end
    end
    data.last_miss_speed = cur_spd
    
    if is_res_miss and contains({"Bruteforce", "Adaptive", "AI"}, mode) then
        if data.confidence >= 30 then
            data.brute_phase = data.brute_phase + 1
            if data.brute_phase > ui.resolver.brute_phases:get() then data.brute_phase = 1; data.misses = 0 end
        end
        if data.misses >= (ui.resolver.brute_phases:get() * ui.resolver.brute_reset:get()) then
            data.brute_phase = 1; data.misses = 0; data.confidence = 0; data.brute_locked = false; data.brute_working = false
        end
    end
    
    if ui.visuals.console_log:get() then
        client.log(string.format("┌─ [Guardian] Miss on %s [%s: %s]", entity.get_player_name(target), is_res_miss and "RESOLVER" or "OTHER", rsn))
        client.log(string.format("│ Mode: %s | Phase: %d/%d", mode, data.brute_phase, ui.resolver.brute_phases:get()))
        client.log(string.format("└─ Resolved Angle: %d° | Side: %d | Conf: %d%%", math.floor(data.resolved_angle), data.desync_side, data.confidence))
    end
    if is_res_miss then data.desync_side = -data.desync_side end
    if data.shots > 0 then data.hit_rate = data.hits / data.shots end
    update_velocity_confidence(target, data, false)
end

local function on_aim_hit(e)
    if not ui.enable:get() then return end
    local target = e.target; local data = init_player_data(target)
    data.hits = data.hits + 1; data.shots = data.shots + 1; data.confidence = math.min(100, data.confidence + 10); data.last_shot_hit = true
    update_velocity_confidence(target, data, true)
    data.last_successful_angle = data.resolved_angle; data.last_successful_time = globals.curtime()
    if apply_smart_baim_preset().reset_on_hit then data.misses = 0 end
    update_resolver_analytics(target, data, true, data.last_successful_method or "unknown")
    if data.shots > 0 then data.hit_rate = data.hits / data.shots end
    if data.hit_rate > 0.6 then data.brute_working = true end
    
    local cp = data.brute_phase
    if data.brute_phase_success[cp] then data.brute_phase_success[cp].hits = data.brute_phase_success[cp].hits + 1; data.brute_phase_success[cp].time = globals.curtime() end
    local hg_names = { [0] = "generic", [1] = "head", [2] = "chest", [3] = "stomach", [4] = "left arm", [5] = "right arm", [6] = "left leg", [7] = "right leg" }
    local hg = hg_names[e.hitgroup] or "unknown"
    if not data.hitgroup_angles[hg] then data.hitgroup_angles[hg] = {} end
    table.insert(data.hitgroup_angles[hg], data.resolved_angle); if #data.hitgroup_angles[hg] > 10 then table.remove(data.hitgroup_angles[hg], 1) end
end

local function on_round_start()
    last_target = nil; last_mindmg_override = nil; last_weapon_id = nil; restore_mindmg()
    client.delay_call(0.5, function() save_current_mindmg() end)
    eye_angle_data = {}; entity_cache = {}; entity_cache_time = {}
    for p, _ in pairs(resolver_cache) do
        if not entity.is_alive(p) and not entity.is_dormant(p) then
            resolver_cache[p] = nil; speed_cache[p] = nil; damage_cache[p] = nil; defensive_check_cache[p] = nil
        end
    end
    for p, d in pairs(resolver_data) do
        d.misses = 0; d.hits = 0; d.shots = 0; d.hit_rate = 0; d.brute_phase = 1; d.confidence = 0; d.brute_locked = false; d.brute_working = false; d.is_defensive = false; d.defensive_ticks = 0
        d.standing_ticks = 0; d.moving_ticks = 0; d.fake_desync_detected = false; d.suspicious_animation = false; d.defensive_wait_until = nil
        if d.analytics then d.analytics.overall_success_rate = 0; d.analytics.total_resolves = 0; d.analytics.successful_resolves = 0 end
        d.body_aimable = false; d.lethal_shot_available = false; d.estimated_body_damage = 0; d.last_known_health = nil; d.baim_reason = nil
        pcall(function() plist.set(p, "Override prefer body aim", "-"); plist.set(p, "Minimum damage override", 0); plist.set(p, "Override safe point", "-"); plist.set(p, "Force body yaw", false); plist.set(p, "Force body yaw value", 0) end)
    end
    speed_cache = {}; damage_cache = {}
end

-- ============================================================================
-- CLANTAG ANIMATION SYSTEM
-- ============================================================================
local clantag_base = "guardian debug "
local clantag_suffix = "+"
local clantag_frames = {}

for i = 1, #clantag_base do
    clantag_frames[#clantag_frames + 1] = clantag_base:sub(1, i) .. clantag_suffix
end
clantag_frames[#clantag_frames + 1] = clantag_base .. clantag_suffix
for i = #clantag_base - 1, 1, -1 do
    clantag_frames[#clantag_frames + 1] = clantag_base:sub(1, i) .. clantag_suffix
end

local last_clantag_frame = -1
local clantag_cleared = false

local function handle_clantag()
    if not ui.enable:get() or not ui.visuals.clantag:get() then
        if not clantag_cleared then
            client.set_clan_tag("")
            last_clantag_frame = -1
            clantag_cleared = true
        end
        return
    end

    clantag_cleared = false
    local frame = math_floor(globals.curtime() * 2.5) % #clantag_frames + 1
    if frame ~= last_clantag_frame then
        client.set_clan_tag(clantag_frames[frame])
        last_clantag_frame = frame
    end
end

-- ============================================================================
-- CANVAS GRAPHICS RENDERING SYSTEM INTERFACE INDICATORS
-- ============================================================================
local function draw_indicator()
    if not ui.home.indicator:get() then return end
    local sw, sh = client.screen_size()
    local x, y, style = sw / 2, sh / 2 + 50, ui.visuals.indicator_style:get()
    local target = client.current_threat()
    
    -- If there are no enemies, show the idle state
    if not target or not entity.is_alive(target) then 
        renderer.text(x, y, 255, 255, 255, 200, "c", 0, "No Target")
        return 
    end
    
    local data = init_player_data(target)
    local r, g, b = unpack(data.confidence > 75 and {0, 255, 0} or (data.confidence > 50 and {255, 255, 0} or {255, 100, 100}))
    
    if style == "Weapon Info" then
        renderer.text(x, y, r, g, b, 255, "c", 0, string.format("Guardian - %s", entity.get_player_name(target)))
        renderer.text(x, y + 15, r, g, b, 255, "c", 0, string.format("Weapon: %s | Threat: %d", data.current_weapon:upper(), data.weapon_threat))
        renderer.text(x, y + 30, r, g, b, 255, "c", 0, string.format("Mode: %s | Peek: %s", ui.home.mode:get(), data.likely_peek_type))
    
    elseif style == "Analytics" then
        renderer.text(x, y, r, g, b, 255, "c", 0, string.format("Guardian Analytics: %d%%", data.confidence))
        renderer.text(x, y + 15, r, g, b, 255, "c", 0, string.format("Success Rate: %.1f%%", (data.analytics.overall_success_rate or 0) * 100))
    
    elseif style == "Detailed" then
        renderer.text(x, y, r, g, b, 255, "c", 0, string.format("Target: %s [%d%%]", entity.get_player_name(target), data.confidence))
        renderer.text(x, y + 15, r, g, b, 255, "c", 0, string.format("Mode: %s | Phase: %d/%d", ui.home.mode:get(), data.brute_phase, ui.resolver.brute_phases:get()))
        renderer.text(x, y + 30, r, g, b, 255, "c", 0, string.format("Angle: %d° | Hit Rate: %.1f%%", data.resolved_angle, (data.hit_rate or 0) * 100))
        if data.is_defensive then renderer.text(x, y + 45, 255, 50, 50, 255, "c", 0, "DEFENSIVE AA DETECTED") end
    
    elseif style == "Debug" then
        renderer.text(x, y, r, g, b, 255, "c", 0, string.format("Guardian Debug - %s", entity.get_player_name(target)))
        renderer.text(x, y + 15, 255, 255, 255, 255, "c", 0, string.format("Angle: %d° | Side: %d | Conf: %d%%", data.resolved_angle, data.desync_side, data.confidence))
        renderer.text(x, y + 30, 255, 255, 255, 255, "c", 0, string.format("Hits: %d | Misses: %d | Standing: %dt", data.hits, data.misses, data.standing_ticks))
        if data.is_defensive then renderer.text(x, y + 45, 255, 50, 50, 255, "c", 0, string.format("DEFENSIVE ACTIVE: %s", data.defensive_type or "unknown")) end
    
    elseif style == "Simple" then
        renderer.text(x, y, r, g, b, 255, "c", 0, string.format("%s | %d%%", entity.get_player_name(target), data.confidence))
    
    elseif style == "Minimal" then
        renderer.text(x, y, r, g, b, 255, "c", 0, string.format("[%d%%]", data.confidence))
    end
end

local function draw_debug_info()
    if not ui.visuals.debug:get() then return end
    local target = client.current_threat()
    if not target or not entity.is_alive(target) then return end
    local x, y, data = 10, 200, init_player_data(target)
    
    renderer.text(x, y, 150, 200, 255, 255, "", 0, "=== Guardian Reborn Matrix Debug ==="); y = y + 15
    renderer.text(x, y, 255, 255, 255, 255, "", 0, string.format("Side Preference: %d | Angle: %d°", data.desync_side, data.resolved_angle)); y = y + 15
    renderer.text(x, y, 255, 255, 255, 255, "", 0, string.format("Brute State Cycle: %d | Hits/Shots: %d/%d", data.brute_phase, data.hits, data.shots)); y = y + 15
    renderer.text(x, y, 255, 50, 50, 255, "", 0, string.format("Defensive Subsystems Active: %s (%s)", tostring(data.is_defensive), tostring(data.defensive_type)))
end

local function draw_watermark()
    if not ui.visuals.watermark:get() then return end
    
    local screen_width, screen_height = client.screen_size()
    local watermark_text = "Guardian Enhanced"
    local x = screen_width / 2
    local y = screen_height - 20
    
    local highlight_fraction = (globals.realtime() / 2 % 1.2 * 2) - 1.2
    local output = ""
    
    local r1, g1, b1, a1 = ui.visuals.watermark_color:get()
    local r2, g2, b2 = r1 * 0.25, g1 * 0.25, b1 * 0.25
    
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
        
        output = output .. string.format('\a%02x%02x%02x%02x%s', math_floor(r_s), math_floor(g_s), math_floor(b_s), a1, character)
    end
    
    renderer.text(x, y, 255, 255, 255, 255, "c", 0, output)
end

local function draw_lethal_flags()
    if not ui.visuals.show_lethal_flag:get() or not ui.rage.smart_baim:get() or not ui.rage.lethal_enable:get() then return end
    local enemies = entity.get_players(true)
    if not enemies then return end
    local style = ui.visuals.lethal_flag_style:get()
    local r, g, b, a = ui.visuals.lethal_flag_color:get()
    
    lethal_flag_pulse = (lethal_flag_pulse + 0.05) % (math.pi * 2)
    local p_alpha = math.floor(a * (0.6 + math.abs(math.sin(lethal_flag_pulse)) * 0.4))
    
    for i = 1, #enemies do
        local player = enemies[i]
        if entity.is_alive(player) then
            local data = init_player_data(player)
            if not data.last_lethal_check or (globals.tickcount() - data.last_lethal_check) > 5 then
                local hp = get_cached_prop(player, "m_iHealth", 100)
                if hp <= ui.rage.lethal_threshold:get() then
                    local lp = entity.get_local_player()
                    if lp and calculate_body_damage(player, lp) >= hp then data.lethal_shot_available = true else data.lethal_shot_available = false end
                else data.lethal_shot_available = false end
                data.last_lethal_check = globals.tickcount()
            end
            
            if data.lethal_shot_available then
                local bx1, by1, bx2, by2 = entity.get_bounding_box(player)
                local sx, sy = bx1 and (bx1 + bx2) / 2 or nil, bx1 and by1 - 15 or nil
                if not sx then
                    local x, y, z = entity.get_prop(player, "m_vecOrigin")
                    if x then sx, sy = renderer.world_to_screen(x, y, z + 75) end
                end
                
                if sx and sy then
                    if style == "Simple" then renderer.text(sx, sy, r, g, b, p_alpha, "c", 0, "LETHAL")
                    elseif style == "Detailed" then renderer.text(sx, sy, r, g, b, p_alpha, "c", 0, string.format("LETHAL: %d HP", entity.get_prop(player, "m_iHealth") or 0))
                    elseif style == "Box highlight" or style == "All" then
                        renderer.rectangle(sx - 25, sy - 2, 50, 14, 0, 0, 0, 150)
                        renderer.text(sx, sy, r, g, b, 255, "c", 0, "⚠ LETHAL ⚠")
                    end
                end
            end
        end
    end
end

-- ============================================================================
-- ESP REGISTRATION LABELS INTERFACE CONNECTIONS
-- ============================================================================
client.register_esp_flag("Resolved ✓", 0, 255, 0, function(ent)
    if not ui.enable:get() or not ui.visuals.resolver_flags:get() or not entity.is_enemy(ent) or not entity.is_alive(ent) then return false end --
    local d = resolver_data[ent] --[cite: 1]
    if not d then return false end --[cite: 1]
    
    -- Telemetry Validation Matrix:
    -- 1. If we haven't shot at them yet, only show resolved if pattern data is perfectly stable
    if d.shots == 0 then --[cite: 1]
        return d.confidence >= 80 and d.standing_ticks > 32 and not d.patterns.oscillation --[cite: 1]
    end --[cite: 1]
    
    -- 2. If we ARE actively fighting them, ignore the scanner score entirely. 
    -- Only light up green if our real weapon hit-rate is above 50%
    return d.hit_rate >= 0.50 and d.misses < 2
end)

client.register_esp_flag("", 255, 255, 255, function(ent)
    if not ui.enable:get() or not ui.visuals.resolver_flags:get() or not entity.is_enemy(ent) or not entity.is_alive(ent) then return false end
    local d = resolver_data[ent]; if not d or not d.resolved_angle then return false end
    return d.resolved_angle > 5 and "Right Desync →" or (d.resolved_angle < -5 and "Left Desync ←" or false)
end)

client.register_esp_flag("DEFENSIVE AA ⚠", 255, 50, 50, function(ent)
    if not ui.enable:get() or not ui.visuals.resolver_flags:get() or not entity.is_enemy(ent) or not entity.is_alive(ent) then return false end
    return resolver_data[ent] and resolver_data[ent].is_defensive and resolver_data[ent].defensive_ticks > 0
end)

-- ============================================================================
-- SCRIPT CONFIGURATION IO SUBSYSTEMS
-- ============================================================================
local config_presets = {
    ["Default"] = {
        mode = "AI",
        indicator = false,
        detection = {
            "Animation Analysis", "Movement Tracking", "LBY Analysis", "Velocity Prediction", 
            "Pose Parameters", "Layer Weight", "Micro Movement", "Standing Detection", 
            "Pattern Recognition", "Desync Break Detection"
        },
        brute_mode = "Intelligent",
        brute_phases = 5,
        brute_reset = 2,
        advanced = {
            "Anti-Freestand", "Body Aim Fix", "Low Delta Detect", "Jitter Detection", 
            "Micro Movement", "Standing Resolver", "Smart Prediction", "Animation Fix", 
            "Pattern Analysis", "Context Awareness", "Peek Prediction", "Adaptive Learning", 
            "Weapon Awareness"
        },
        desync_strength = 75,
        confidence = 70,
        reaction_time = 10,
        ai_aggression = 50,
        ai_learning = 100,
        defensive = true,
        defensive_options = {
            "Simulation Check", "Lag Compensation", "Velocity Exploit", "Teleport Detection", 
            "Smart Backtrack", "Prediction Fix", "Layer Correlation"
        },
        defensive_peek_fix = true,
        peek_prediction_time = 50,
        peek_min_damage = 10,
        peek_auto_enable = {
            "Enemy has AWP", "Enemy has Scout", "You have AWP/Scout", "Low health (<50HP)"
        },
        delay_head = true,
        smart_baim_enable = true,
        smart_baim_mode = "Default",
        lethal_enable = true,
        lethal_threshold = 80,
        accuracy_threshold = 75,
        lethal_mode = "Prefer body (flexible)",
        lethal_override_mindmg = false,
        ideal_tick_enable = true,
        fakelag_enable = true,
        predictive_autostop = true,
        clantag = true,
        watermark = true,
        watermark_color = {150, 200, 255, 255},
        resolver_flags = true,
        show_lethal_flag = true,
        lethal_flag_style = "Simple",
        debug = false,
        console_log = true,
        killsay = false,
        description = "Fully configured based on verified UI specifications"
    },
    ["Aggressive"] = { mode = "AI", detection = {"Animation Analysis", "LBY Analysis", "Pattern Recognition", "Desync Break Detection"}, defensive = true, brute_mode = "Adaptive", brute_phases = 7, brute_reset = 1, advanced = {"Jitter Detection", "Smart Prediction", "Peek Prediction", "Adaptive Learning", "Weapon Awareness"}, desync_strength = 85, confidence = 60, smart_baim_enable = true, smart_baim_mode = "Aggressive", ideal_tick_enable = true, fakelag_enable = true, defensive_peek_fix = true, peek_prediction_time = 120, peek_min_damage = 20, description = "Hyper-aggressive setting tuned for fast paced operations." },
    ["Defensive"] = { mode = "AI", detection = {"Animation Analysis", "Movement Tracking", "LBY Analysis", "Pattern Recognition"}, defensive = true, brute_mode = "Intelligent", brute_phases = 6, brute_reset = 2, advanced = {"Body Aim Fix", "Context Awareness", "Adaptive Learning", "Weapon Awareness"}, desync_strength = 75, confidence = 70, smart_baim_enable = true, smart_baim_mode = "Defensive", ideal_tick_enable = true, fakelag_enable = true, defensive_peek_fix = true, peek_prediction_time = 250, peek_min_damage = 30, description = "Conservative setting optimized for stable long range sniper usage." }
}

local config_system = {}
function config_system.get_current_config()
    local watermark_r, watermark_g, watermark_b, watermark_a = ui.visuals.watermark_color:get()
    return {
        mode = ui.home.mode:get(), indicator = ui.home.indicator:get(),
        detection = ui.resolver.detection:get(), brute_mode = ui.resolver.brute_mode:get(),
        brute_phases = ui.resolver.brute_phases:get(), brute_reset = ui.resolver.brute_reset:get(),
        advanced = ui.resolver.advanced:get(), desync_strength = ui.resolver.desync_strength:get(),
        confidence = ui.resolver.confidence:get(), reaction_time = ui.resolver.reaction_time:get(),
        ai_aggression = ui.resolver.ai_aggression:get(), ai_learning = ui.resolver.ai_learning:get(),
        defensive = ui.defensive.enable:get(), defensive_options = ui.defensive.options:get(),
        defensive_peek_fix = ui.defensive.peek_fix:get(), peek_prediction_time = ui.defensive.peek_time:get(),
        peek_min_damage = ui.defensive.peek_min_damage:get(), peek_auto_enable = ui.defensive.peek_auto_enable:get(),
        delay_head = ui.defensive.delay_head:get(), smart_baim_enable = ui.rage.smart_baim:get(),
        smart_baim_mode = ui.rage.mode:get(), lethal_enable = ui.rage.lethal_enable:get(),
        lethal_threshold = ui.rage.lethal_threshold:get(), accuracy_threshold = ui.rage.accuracy_threshold:get(),
        lethal_mode = ui.rage.lethal_mode:get(), lethal_override_mindmg = ui.rage.lethal_override_mindmg:get(),
        ideal_tick_enable = ui.rage.ideal_tick:get(), fakelag_enable = ui.rage.smart_fakelag:get(),
        predictive_autostop = ui.rage.predictive_autostop:get(),
        clantag = ui.visuals.clantag:get(), watermark = ui.visuals.watermark:get(),
        watermark_color = {watermark_r, watermark_g, watermark_b, watermark_a}, indicator_style = ui.visuals.indicator_style:get(),
        resolver_flags = ui.visuals.resolver_flags:get(), show_lethal_flag = ui.visuals.show_lethal_flag:get(),
        lethal_flag_style = ui.visuals.lethal_flag_style:get(), debug = ui.visuals.debug:get(),
        console_log = ui.visuals.console_log:get(), killsay = ui.visuals.killsay:get()
    }
end

function config_system.apply_config(cfg)
    if cfg.mode ~= nil then ui.home.mode:set(cfg.mode) end
    if cfg.indicator ~= nil then ui.home.indicator:set(cfg.indicator) end
    if cfg.detection ~= nil then ui.resolver.detection:set(cfg.detection) end
    if cfg.brute_mode ~= nil then ui.resolver.brute_mode:set(cfg.brute_mode) end
    if cfg.brute_phases ~= nil then ui.resolver.brute_phases:set(cfg.brute_phases) end
    if cfg.brute_reset ~= nil then ui.resolver.brute_reset:set(cfg.brute_reset) end
    if cfg.advanced ~= nil then ui.resolver.advanced:set(cfg.advanced) end
    if cfg.desync_strength ~= nil then ui.resolver.desync_strength:set(cfg.desync_strength) end
    if cfg.confidence ~= nil then ui.resolver.confidence:set(cfg.confidence) end
    if cfg.reaction_time ~= nil then ui.resolver.reaction_time:set(cfg.reaction_time) end
    if cfg.ai_aggression ~= nil then ui.resolver.ai_aggression:set(cfg.ai_aggression) end
    if cfg.ai_learning ~= nil then ui.resolver.ai_learning:set(cfg.ai_learning) end
    if cfg.defensive ~= nil then ui.defensive.enable:set(cfg.defensive) end
    if cfg.options ~= nil then ui.defensive.options:set(cfg.options) end
    if cfg.defensive_options ~= nil then ui.defensive.options:set(cfg.defensive_options) end
    if cfg.defensive_peek_fix ~= nil then ui.defensive.peek_fix:set(cfg.defensive_peek_fix) end
    if cfg.peek_prediction_time ~= nil then ui.defensive.peek_time:set(cfg.peek_prediction_time) end
    if cfg.peek_min_damage ~= nil then ui.defensive.peek_min_damage:set(cfg.peek_min_damage) end
    if cfg.peek_auto_enable ~= nil then ui.defensive.peek_auto_enable:set(cfg.peek_auto_enable) end
    if cfg.delay_head ~= nil then ui.defensive.delay_head:set(cfg.delay_head) end
    if cfg.smart_baim_enable ~= nil then ui.rage.smart_baim:set(cfg.smart_baim_enable) end
    if cfg.smart_baim_mode ~= nil then ui.rage.mode:set(cfg.smart_baim_mode) end
    if cfg.lethal_enable ~= nil then ui.rage.lethal_enable:set(cfg.lethal_enable) end
    if cfg.lethal_threshold ~= nil then ui.rage.lethal_threshold:set(cfg.lethal_threshold) end
    if cfg.accuracy_threshold ~= nil then ui.rage.accuracy_threshold:set(cfg.accuracy_threshold) end
    if cfg.lethal_mode ~= nil then ui.rage.lethal_mode:set(cfg.lethal_mode) end
    if cfg.lethal_override_mindmg ~= nil then ui.rage.lethal_override_mindmg:set(cfg.lethal_override_mindmg) end
    if cfg.ideal_tick_enable ~= nil then ui.rage.ideal_tick:set(cfg.ideal_tick_enable) end
    if cfg.fakelag_enable ~= nil then ui.rage.smart_fakelag:set(cfg.fakelag_enable) end
    if cfg.predictive_autostop ~= nil then ui.rage.predictive_autostop:set(cfg.predictive_autostop) end
    if cfg.clantag ~= nil then ui.visuals.clantag:set(cfg.clantag) end
    if cfg.watermark ~= nil then ui.visuals.watermark:set(cfg.watermark) end
    if cfg.watermark_color ~= nil then ui.visuals.watermark_color:set(unpack(cfg.watermark_color)) end
    if cfg.indicator_style ~= nil then ui.visuals.indicator_style:set(cfg.indicator_style) end
    if cfg.resolver_flags ~= nil then ui.visuals.resolver_flags:set(cfg.resolver_flags) end
    if cfg.show_lethal_flag ~= nil then ui.visuals.show_lethal_flag:set(cfg.show_lethal_flag) end
    if cfg.lethal_flag_style ~= nil then ui.visuals.lethal_flag_style:set(cfg.lethal_flag_style) end
    if cfg.debug ~= nil then ui.visuals.debug:set(cfg.debug) end
    if cfg.console_log ~= nil then ui.visuals.console_log:set(cfg.console_log) end
    if cfg.killsay ~= nil then ui.visuals.killsay:set(cfg.killsay) end
end

-- ============================================================================
-- ENVIRONMENT INTERACTION UI MANAGEMENT VISIBILITY VISUALIZER
-- ============================================================================
local function handle_menu_visibility()
    local enabled = ui.enable:get()
    local tab = ui.tabs:get()
    
    -- Traversal visibility states driven by standard PUI mapping elements
    ui.home.info:set_visible(enabled and tab == "Home")
    ui.home.mode:set_visible(enabled and tab == "Home")
    ui.home.indicator:set_visible(enabled and tab == "Home")
    
    local is_res_tab = enabled and tab == "Resolver"
    local m_mode = ui.home.mode:get()
    ui.resolver.detection:set_visible(is_res_tab and contains({"Smart", "Automatic", "Adaptive", "AI"}, m_mode))
    ui.resolver.brute_mode:set_visible(is_res_tab and contains({"Bruteforce", "Adaptive", "AI"}, m_mode))
    ui.resolver.brute_phases:set_visible(is_res_tab and contains({"Bruteforce", "Adaptive", "AI"}, m_mode))
    ui.resolver.brute_reset:set_visible(is_res_tab and contains({"Bruteforce", "Adaptive", "AI"}, m_mode))
    ui.resolver.advanced:set_visible(is_res_tab)
    ui.resolver.override_left:set_visible(is_res_tab and m_mode == "Override")
    ui.resolver.override_right:set_visible(is_res_tab and m_mode == "Override")
    ui.resolver.override_center:set_visible(is_res_tab and m_mode == "Override")
    ui.resolver.desync_strength:set_visible(is_res_tab)
    ui.resolver.confidence:set_visible(is_res_tab and contains({"Adaptive", "AI"}, m_mode))
    ui.resolver.reaction_time:set_visible(is_res_tab)
    ui.resolver.ai_aggression:set_visible(is_res_tab and m_mode == "AI")
    ui.resolver.ai_learning:set_visible(is_res_tab and m_mode == "AI")
    
    local is_def_tab = enabled and tab == "Anti-Aim"
    ui.defensive.enable:set_visible(is_def_tab)
    ui.defensive.options:set_visible(is_def_tab and ui.defensive.enable:get())
    ui.defensive.peek_fix:set_visible(is_def_tab)
    ui.defensive.peek_time:set_visible(is_def_tab and ui.defensive.peek_fix:get())
    ui.defensive.peek_min_damage:set_visible(is_def_tab and ui.defensive.peek_fix:get())
    ui.defensive.peek_auto_enable:set_visible(is_def_tab and ui.defensive.peek_fix:get())
    ui.defensive.delay_head:set_visible(is_def_tab)
    
    local is_rage_tab = enabled and tab == "Rage"
    ui.rage.smart_baim:set_visible(is_rage_tab)
    local baim_on = is_rage_tab and ui.rage.smart_baim:get()
    ui.rage.mode:set_visible(baim_on)
    ui.rage.lethal_enable:set_visible(baim_on)
    local leth_on = baim_on and ui.rage.lethal_enable:get()
    ui.rage.lethal_threshold:set_visible(leth_on)
    ui.rage.accuracy_threshold:set_visible(leth_on)
    ui.rage.lethal_mode:set_visible(leth_on)
    ui.rage.lethal_override_mindmg:set_visible(leth_on)
    ui.rage.ideal_tick:set_visible(is_rage_tab)
    ui.rage.smart_fakelag:set_visible(is_rage_tab)
    ui.rage.predictive_autostop:set_visible(is_rage_tab)
    
    local is_vis_tab = enabled and tab == "Visuals"
    ui.visuals.clantag:set_visible(is_vis_tab)
    ui.visuals.watermark:set_visible(is_vis_tab)
    ui.visuals.watermark_color:set_visible(is_vis_tab and ui.visuals.watermark:get())
    ui.visuals.indicator_style:set_visible(is_vis_tab and ui.home.indicator:get())
    ui.visuals.resolver_flags:set_visible(is_vis_tab)
    ui.visuals.show_lethal_flag:set_visible(is_vis_tab and ui.rage.smart_baim:get())
    local flg_on = is_vis_tab and ui.rage.smart_baim:get() and ui.visuals.show_lethal_flag:get()
    ui.visuals.lethal_flag_style:set_visible(flg_on)
    ui.visuals.lethal_flag_color:set_visible(flg_on)
    ui.visuals.debug:set_visible(is_vis_tab)
    ui.visuals.console_log:set_visible(is_vis_tab)
    ui.visuals.killsay:set_visible(is_vis_tab)
    
    local is_cfg_tab = enabled and tab == "Config"
    ui.config.preset:set_visible(is_cfg_tab)
    ui.config.description:set_visible(is_cfg_tab)
    ui.config.load:set_visible(is_cfg_tab)
    ui.config.export:set_visible(is_cfg_tab)
    ui.config.import:set_visible(is_cfg_tab)
end

-- ============================================================================
-- SYSTEM SUBORDINATION EVENT INTERACTION CALL CONNECTIONS
-- ============================================================================
client.set_event_callback("paint", function()
    handle_clantag()
    if not ui.enable:get() then return end
    draw_indicator()
    draw_debug_info()
    draw_watermark()
    draw_lethal_flags()
end)

client.set_event_callback("net_update_end", function()
    if not ui.enable:get() then
        local p = entity.get_players(true)
        if p then for i=1,#p do plist.set(p[i], "Force body yaw", false) end end; return
    end
    
    if exploits:is_defensive_ended() then for _, c in pairs(resolver_cache) do if c then c.result = nil; c.tick = nil end end end
    for p, d in pairs(resolver_data) do
        if not entity.is_alive(p) or entity.is_dormant(p) then
            d.dormant_ticks = (d.dormant_ticks or 0) + 1
            if d.dormant_ticks > 32 then
                resolver_data[p] = nil; lag_records[p] = nil; defensive_records[p] = nil; speed_cache[p] = nil; damage_cache[p] = nil; eye_angle_data[p] = nil; resolver_cache[p] = nil; defensive_check_cache[p] = nil
            end
        else d.dormant_ticks = 0 end
    end
    
    local enemies = entity.get_players(true)
    if not enemies or #enemies == 0 then return end
    for i = 1, #enemies do
        local enemy = enemies[i]
        if entity.is_alive(enemy) then plist.set(enemy, "Correction active", true); resolve_player(enemy) else plist.set(enemy, "Force body yaw", false) end
    end
end)

client.set_event_callback("setup_command", function(cmd)
    if not ui.enable:get() then
        fakelag_ref:override()
        return
    end
    local cur_w = get_local_weapon_id()
    if cur_w and cur_w ~= last_weapon_id then save_current_mindmg(); last_weapon_id = cur_w end
    optimize_fakelag(cmd)
    exploits:should_force_defensive(should_force_defensive_peek())
    
    local threat = client.current_threat()
    apply_predictive_autostop(cmd, threat)
    if threat then exploits:allow_unsafe_charge(not (resolver_data[threat] and resolver_data[threat].confidence > 80)) end
    
    local p = entity.get_players(true)
    if p then
        for i=1,#p do
            local enemy = p[i]; local d = resolver_data[enemy]
            if d and entity.is_alive(enemy) then
                if ui.rage.smart_baim:get() then apply_smart_hitbox_override(enemy, d) end
                if ui.defensive.delay_head:get() and d.block_shots then
                    local me = entity.get_local_player()
                    if me and entity.get_player_weapon(me) then
                        local wid = entity.get_prop(entity.get_player_weapon(me), "m_iItemDefinitionIndex")
                        if wid and contains({1,2,3,4,7,8,9,10,11,13,14,16,17,19,24,25,26,27,28,29,30,32,33,34,35,36,38,39,40,60,61,63,64}, wid) then cmd.in_attack = false end
                    end
                end
            end
        end
    end
    
    if ui.rage.smart_baim:get() and ui.rage.lethal_enable:get() and ui.rage.lethal_override_mindmg:get() and threat and entity.is_alive(threat) then
        local d = resolver_data[threat]
        if d and d.lethal_mindmg_required then
            local req = d.lethal_mindmg_required
            if threat ~= last_target or req ~= last_mindmg_value then if ref_mindmg then save_current_mindmg(); ref_mindmg:set(req); last_mindmg_value = req; last_target = threat end end
        else if last_mindmg_value ~= nil then restore_mindmg(); last_mindmg_value = nil end end
    else if last_mindmg_value ~= nil then restore_mindmg(); last_mindmg_value = nil; last_target = nil end end
end)

client.set_event_callback("weapon_fire", function(e)
    if not ui.enable:get() or not ui.defensive.peek_fix:get() then return end
    local lp = entity.get_local_player()
    if client.userid_to_entindex(e.userid) == lp then
        local ox, oy, oz = entity.get_prop(lp, "m_vecOrigin")
        if ox then entity.set_prop(lp, "m_vecOrigin", ox, oy, oz) end
    end
end)

client.set_event_callback("player_hurt", function(e)
    local vic = client.userid_to_entindex(e.userid)
    if vic and resolver_data[vic] then resolver_data[vic].last_damage_time = globals.curtime() end
end)

function ui.send_killsay()
    local state = ui.killsay_state
    if globals.realtime() - state.last_time < 0.75 or #state.phrases == 0 then return end
    local index = math.random(1, #state.phrases)
    if #state.phrases > 1 and index == state.last_index then
        index = index % #state.phrases + 1
    end
    local phrase = state.phrases[index]:gsub("[;\r\n\"]", "")
    if phrase == "" then return end
    client.exec("say " .. phrase)
    state.last_time = globals.realtime()
    state.last_index = index
end

client.set_event_callback("player_death", function(e)
    local vic = client.userid_to_entindex(e.userid)
    local attacker = client.userid_to_entindex(e.attacker)
    local local_player = entity.get_local_player()
    local should_killsay = ui.enable:get()
        and ui.visuals.killsay:get()
        and attacker == local_player
        and vic ~= local_player
        and vic ~= nil
        and entity.is_enemy(vic)
    if vic and resolver_data[vic] then
        pcall(function() plist.set(vic, "Force body yaw", false); plist.set(vic, "Force body yaw value", 0); plist.set(vic, "Correction active", true); plist.set(vic, "Override prefer body aim", "-"); plist.set(vic, "Override safe point", "-"); plist.set(vic, "Minimum damage override", 0) end)
    end
    if should_killsay then ui.send_killsay() end
end)

client.set_event_callback("player_disconnect", function(e)
    local p = client.userid_to_entindex(e.userid)
    if not p then return end
    resolver_data[p] = nil; lag_records[p] = nil; defensive_records[p] = nil; speed_cache[p] = nil; damage_cache[p] = nil; eye_angle_data[p] = nil; resolver_cache[p] = nil; defensive_check_cache[p] = nil
    pcall(function() plist.set(p, "Force body yaw", false); plist.set(p, "Force body yaw value", 0); plist.set(p, "Override prefer body aim", "-"); plist.set(p, "Override safe point", "-") end)
end)

-- this is for the console logging dont mind it
client.set_event_callback("aim_miss", on_aim_miss)
client.set_event_callback("aim_hit", on_aim_hit)
client.set_event_callback("round_start", on_round_start)

-- callback assignment connections
ui.enable:set_callback(handle_menu_visibility)
ui.tabs:set_callback(handle_menu_visibility)
ui.home.mode:set_callback(handle_menu_visibility)
ui.home.indicator:set_callback(handle_menu_visibility)
ui.defensive.enable:set_callback(handle_menu_visibility)
ui.defensive.peek_fix:set_callback(handle_menu_visibility)
ui.rage.smart_baim:set_callback(handle_menu_visibility)
ui.rage.lethal_enable:set_callback(handle_menu_visibility)
ui.visuals.watermark:set_callback(handle_menu_visibility)
ui.visuals.show_lethal_flag:set_callback(handle_menu_visibility)

ui.config.preset:set_callback(function()
    local sel = ui.config.preset:get()
    ui.config.description:set(sel == "Custom" and "Custom configuration matrix profile." or (config_presets[sel] and config_presets[sel].description or "No baseline overview description defined."))
end)
ui.config.load:set_callback(function() config_system.load_preset() end)
ui.config.export:set_callback(function() config_system.export_config() end)
ui.config.import:set_callback(function() config_system.import_config() end)

function config_system.load_preset()
    local sel = ui.config.preset:get()
    if sel == "Custom" then return end
    local pr = config_presets[sel]
    if pr then config_system.apply_config(pr); client.delay_call(0.1, function() ui.config.preset:set("Custom") end) end
end

function config_system.export_config()
    local cfg = config_system.get_current_config()
    clipboard_util.set(base64.encode(json.stringify(cfg)))
    client.log("Guardian Reborn: Configuration exported.")
end

function config_system.import_config()
    local enc = clipboard_util.get()
    if not enc then return end
    local s, js = pcall(base64.decode, enc)
    if not s then return end
    local s2, cfg = pcall(json.parse, js)
    if s2 then config_system.apply_config(cfg); client.log("Guardian Reborn: Imported.") end
end

client.set_event_callback("shutdown", function()
    if last_mindmg_value ~= nil then restore_mindmg() end
    fakelag_ref:override()
    client.set_clan_tag("")
    local p = entity.get_players(true)
    if p then for i=1,#p do pcall(function() plist.set(p[i], "Force body yaw", false); plist.set(p[i], "Force body yaw value", 0); plist.set(p[i], "Override prefer body aim", "-"); plist.set(p[i], "Override safe point", "-") end) end end
    client.log("Guardian Reborn successfully shut down and state parameters cleared.")
end)

-- ============================================================================
-- INITIALIZATION PIPELINE DEPLOYMENT
-- ============================================================================
handle_menu_visibility()
client.log("Guardian Reborn | V1.0")
