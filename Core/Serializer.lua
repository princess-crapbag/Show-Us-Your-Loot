-- Core/Serializer.lua
--
-- Turns arbitrary Lua values into text. Used by the developer tools to dump
-- whatever Blizzard hands us without knowing its shape in advance, so it must
-- survive cycles, deep nesting and non-string keys.

local SYL = _G.ShowUsYourLoot

local Serializer = {}
SYL.Serializer = Serializer

local MAX_DEPTH = 8

local JSON_ESCAPES = {
    ['"'] = '\\"',
    ["\\"] = "\\\\",
    ["\b"] = "\\b",
    ["\f"] = "\\f",
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t",

    -- A raw pipe is WoW's escape-sequence marker. Left alone, the edit box
    -- renders |cff...|Hitem:...|h[Name]|h|r as the colored link text and the
    -- item ID is lost the moment the JSON is copied out. | is valid JSON
    -- that decodes back to "|", and the renderer leaves it alone.
    ["|"] = "\\u007c",
}

local function EscapeJSONString(text)
    return (text:gsub('[%c"\\|]', function(character)
        return JSON_ESCAPES[character]
            or string.format("\\u%04x", character:byte())
    end))
end

-- A table counts as an array only when its keys are exactly 1..n, which is how
-- Blizzard returns list results such as the drops for an encounter.
local function IsArray(value)
    local count = 0

    for key in pairs(value) do
        if type(key) ~= "number" then
            return false
        end

        count = count + 1
    end

    return count == #value
end

local function EncodeJSONValue(value, depth, seen)
    local valueType = type(value)

    if value == nil then
        return "null"
    end

    if valueType == "boolean" then
        return tostring(value)
    end

    if valueType == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return '"' .. tostring(value) .. '"'
        end

        return tostring(value)
    end

    if valueType == "string" then
        return '"' .. EscapeJSONString(value) .. '"'
    end

    if valueType ~= "table" then
        return '"<' .. valueType .. '>"'
    end

    if seen[value] then
        return '"<cycle>"'
    end

    if depth >= MAX_DEPTH then
        return '"<max depth reached>"'
    end

    seen[value] = true

    local pieces = {}

    if IsArray(value) then
        for index = 1, #value do
            table.insert(
                pieces,
                EncodeJSONValue(value[index], depth + 1, seen)
            )
        end

        seen[value] = nil

        return "[" .. table.concat(pieces, ",") .. "]"
    end

    for _, key in ipairs(SYL.Utilities.GetSortedKeys(value)) do
        local encodedValue =
            EncodeJSONValue(value[key], depth + 1, seen)

        table.insert(
            pieces,
            '"' .. EscapeJSONString(tostring(key)) .. '":' .. encodedValue
        )
    end

    seen[value] = nil

    return "{" .. table.concat(pieces, ",") .. "}"
end

function Serializer.ToJSON(value)
    local success, result = pcall(function()
        return EncodeJSONValue(value, 0, {})
    end)

    if not success then
        return '{"error":"serialization failed"}'
    end

    return result
end

local function DescribeScalar(value)
    local valueType = type(value)

    if valueType == "string" then
        return '"' .. value .. '"'
    end

    if valueType == "number" or valueType == "boolean" then
        return tostring(value)
    end

    return "<" .. valueType .. ">"
end

local function AppendText(lines, value, depth, seen, label)
    local indent = string.rep("  ", depth)

    if type(value) ~= "table" then
        table.insert(lines, indent .. label .. DescribeScalar(value))
        return
    end

    if seen[value] then
        table.insert(lines, indent .. label .. "<cycle>")
        return
    end

    if depth >= MAX_DEPTH then
        table.insert(lines, indent .. label .. "<max depth reached>")
        return
    end

    seen[value] = true

    local keys = SYL.Utilities.GetSortedKeys(value)

    if #keys == 0 then
        table.insert(lines, indent .. label .. "{}")
        seen[value] = nil
        return
    end

    table.insert(lines, indent .. label .. "{")

    for _, key in ipairs(keys) do
        AppendText(
            lines,
            value[key],
            depth + 1,
            seen,
            tostring(key) .. " = "
        )
    end

    table.insert(lines, indent .. "}")

    seen[value] = nil
end

-- Indented, human-readable dump for the developer window.
function Serializer.ToText(value, label)
    local lines = {}

    local success = pcall(
        AppendText,
        lines,
        value,
        0,
        {},
        label and (label .. " = ") or ""
    )

    if not success then
        return "<serialization failed>"
    end

    return table.concat(lines, "\n")
end
