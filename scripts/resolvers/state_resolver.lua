-- scripts/resolvers/state_resolver.lua
local BaseResolver = require("resolvers/base_resolver")
local OFFICIAL_KEYS = {
    KEY_TAB = 9, KEY_KP_0 = 256, KEY_KP_1 = 257, KEY_KP_2 = 258, KEY_KP_3 = 259,
    KEY_KP_4 = 260, KEY_KP_5 = 261, KEY_KP_6 = 262, KEY_KP_7 = 263, KEY_KP_8 = 264,
    KEY_KP_9 = 265, KEY_KP_PERIOD = 266, KEY_KP_DIVIDE = 267, KEY_KP_MULTIPLY = 268,
    KEY_KP_MINUS = 269, KEY_KP_PLUS = 270, KEY_KP_ENTER = 271, KEY_KP_EQUALS = 272,
    KEY_MINUS = 45, KEY_EQUALS = 61, KEY_SPACE = 32, KEY_ENTER = 13, KEY_ESCAPE = 27,
    KEY_HOME = 278, KEY_INSERT = 277, KEY_DELETE = 127, KEY_END = 279, KEY_PAUSE = 19,
    KEY_PRINT = 316, KEY_CAPSLOCK = 301, KEY_SCROLLOCK = 302, KEY_RSHIFT = 303,
    KEY_LSHIFT = 304, KEY_RCTRL = 305, KEY_LCTRL = 306, KEY_RALT = 307, KEY_LALT = 308,
    KEY_LSUPER = 311, KEY_RSUPER = 312, KEY_ALT = 400, KEY_CTRL = 401, KEY_SHIFT = 402,
    KEY_BACKSPACE = 8, KEY_PERIOD = 46, KEY_SLASH = 47, KEY_SEMICOLON = 59,
    KEY_LEFTBRACKET = 91, KEY_BACKSLASH = 92, KEY_RIGHTBRACKET = 93, KEY_TILDE = 96,
    KEY_A = 97, KEY_B = 98, KEY_C = 99, KEY_D = 100, KEY_E = 101, KEY_F = 102,
    KEY_G = 103, KEY_H = 104, KEY_I = 105, KEY_J = 106, KEY_K = 107, KEY_L = 108,
    KEY_M = 109, KEY_N = 110, KEY_O = 111, KEY_P = 112, KEY_Q = 113, KEY_R = 114,
    KEY_S = 115, KEY_T = 116, KEY_U = 117, KEY_V = 118, KEY_W = 119, KEY_X = 120,
    KEY_Y = 121, KEY_Z = 122, KEY_F1 = 282, KEY_F2 = 283, KEY_F3 = 284, KEY_F4 = 285,
    KEY_F5 = 286, KEY_F6 = 287, KEY_F7 = 288, KEY_F8 = 289, KEY_F9 = 290, KEY_F10 = 291,
    KEY_F11 = 292, KEY_F12 = 293, KEY_UP = 273, KEY_DOWN = 274, KEY_RIGHT = 275,
    KEY_LEFT = 276, KEY_PAGEUP = 280, KEY_PAGEDOWN = 281, KEY_0 = 48, KEY_1 = 49,
    KEY_2 = 50, KEY_3 = 51, KEY_4 = 52, KEY_5 = 53, KEY_6 = 54, KEY_7 = 55,
    KEY_8 = 56, KEY_9 = 57,
}

local KEYCODE_TO_NAME = {}
for name, code in pairs(OFFICIAL_KEYS) do
    KEYCODE_TO_NAME[code] = name
end
local StateResolver = Class(BaseResolver, function(self, defs)
    self._resolver_type = "state"
    BaseResolver._ctor(self, defs)
end)

function StateResolver:OnDefAdded(state, def)
    if def.keys then
        local bindings = {}
        for k, v in pairs(def.keys) do
            local key_code = k
            if type(k) == "string" and rawget(_G, k) ~= nil then
                key_code = rawget(_G, k)
            end
            bindings[key_code] = v
        end
        def.keys = bindings
    end
end

function StateResolver:GetBadges(state)
    local def = self:GetDef(state)
    return def and def.badges or nil
end

function StateResolver:GetSkills(state)
    local def = self:GetDef(state)
    return def and def.skills or {}
end

function StateResolver:BuildWikiItemsByIds(ids)
    local items = {}
    for _, id in ipairs(ids) do
        local def = self:GetDef(id)
        if def then
            -- 核心：把数字 Key 重新转回字符串，避免 JSON 生成 null 数组
            local formatted_keys = nil
            if def.keys and next(def.keys) then
                formatted_keys = {}
                for code, skill_id in pairs(def.keys) do
                    local key_name = tostring(code)
                    if type(code) == "number" and KEYCODE_TO_NAME[code] then
                        key_name = KEYCODE_TO_NAME[code]
                    end
                    formatted_keys[key_name] = skill_id
                end
            end
            table.insert(items, {
                id = id,
                skills = def.skills,
                tags = def.tags,
                keys = formatted_keys, -- 输出为 {"KEY_Z": "fireball"} 对象形式
            })
        end
    end
    return items
end
return StateResolver