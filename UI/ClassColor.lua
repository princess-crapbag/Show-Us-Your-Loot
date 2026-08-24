-- UI/ClassColor.lua
--
-- A character's name in their class color, everywhere a character's name is
-- drawn.
--
-- Aimee: "everywhere a character name is listed in the addon can it be in
-- their class color? its easier visually to register who it is."
--
-- ONE FUNCTION, NOT NINETEEN COPIES. Nineteen call sites across seventeen
-- files were already doing this, and all nineteen hand-rolled the same six
-- lines: GetClassColor, an if, SetCustomTextColor, an else, SetTextColor.
-- Thirteen of them were byte-identical. Every screen that gained a name
-- copied it again, and the three that were missed -- the "who is out" tile,
-- the absence name popup and every chat-captured row in the loot list --
-- were missed because copying is easy to forget and calling is not.
--
-- ITS OWN FILE BECAUSE UI/Theme.lua IS OVER THE SIZE LIMIT at 506 lines and
-- growing it to hold this would be using the escape hatch that does not exist
-- for it. GetClassColor and ClassLabel came here rather than staying behind,
-- because a subject with two homes is how two homes come to disagree; Theme
-- is 40 lines shorter for it.
--
-- THE FALLBACK BRANCH IS LOAD-BEARING AND MUST NOT BE SKIPPED.
--
-- Theme.SetCustomTextColor DEREGISTERS a font string from the palette repaint
-- list -- see its own note, which is about exactly this. Rows are pooled. So
-- a row that draws a class-colored raider and is then reused for somebody
-- whose class is unknown must call SetTextColor to put itself back on that
-- list. Skipping it leaves the previous raider's color on the new name AND
-- leaves that row deaf to a theme change for the rest of the session.
--
-- That is why Set returns a boolean rather than nothing: one caller
-- (UI/DashboardParts.lua) has its own color to fall back to and needs to know
-- whether it was used.

local SYL = _G.ShowUsYourLoot
local Theme = SYL.Theme

local ClassColor = {}
SYL.ClassColor = ClassColor

-- The client's own colors, so a name here matches the same name in the game's
-- raid frames rather than approximating it.
function ClassColor.Get(classFile)
    if not classFile or classFile == "" then
        return nil
    end

    local color

    if C_ClassColor and C_ClassColor.GetClassColor then
        color = C_ClassColor.GetClassColor(classFile)
    end

    if not color and RAID_CLASS_COLORS then
        color = RAID_CLASS_COLORS[classFile]
    end

    if not color then
        return nil
    end

    return { color.r, color.g, color.b }
end

-- Paints a font string, or puts it back on the palette. See the header for
-- why the else is not optional.
--
-- `fallbackKey` is a parameter rather than a constant because the sites do not
-- agree: UI/DropDetailWindow.lua falls back to "accent" and every other one to
-- "textPrimary". A hardcoded default would have silently changed that screen.
function ClassColor.Set(fontString, classFile, fallbackKey)
    if not fontString then
        return false
    end

    local color = ClassColor.Get(classFile)

    if color then
        Theme.SetCustomTextColor(fontString, color[1], color[2], color[3])

        return true
    end

    Theme.SetTextColor(fontString, fallbackKey or "textPrimary")

    return false
end

-- CHAT IS A DIFFERENT MECHANISM AND NEEDS A DIFFERENT FUNCTION.
--
-- SetTextColor does nothing to a chat line. The addon already colors chat, by
-- wrapping text in the escape codes in Main.lua's SYL.colors, and there is
-- exactly one precedent for coloring a NAME that way -- and it uses a fixed
-- green rather than a class color.
--
-- Returns nil rather than an empty string when the class is unknown, so a
-- caller has to decide what to do about it instead of silently emitting a
-- broken escape sequence.
function ClassColor.Code(classFile)
    local color = ClassColor.Get(classFile)

    if not color then
        return nil
    end

    return string.format(
        "|cff%02x%02x%02x",
        math.floor(color[1] * 255 + 0.5),
        math.floor(color[2] * 255 + 0.5),
        math.floor(color[3] * 255 + 0.5)
    )
end

-- A name ready to print into chat, colored when the class is known and plain
-- when it is not. The reset code is Main.lua's, so a colored name cannot leak
-- its color into the rest of the line.
function ClassColor.Name(name, classFile)
    local code = ClassColor.Code(classFile)

    if not code then
        return tostring(name or "")
    end

    return code .. tostring(name or "") .. (SYL.colors and SYL.colors.reset or "|r")
end

-- "DEATHKNIGHT" is what the roster stores, because it keys the colors above
-- and the buff lookups. "Death Knight" is what a person reads.
function ClassColor.Label(classFile)
    if not classFile or classFile == "" then
        return ""
    end

    local localized = _G.LOCALIZED_CLASS_NAMES_MALE

    return (localized and localized[classFile]) or classFile
end
