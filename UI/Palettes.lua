-- UI/Palettes.lua
--
-- The colour schemes the window can wear. Theme.lua owns the mechanics of
-- applying one; this file is only the values, so adding a scheme never means
-- touching frame code.
--
-- Every palette states all of its own keys rather than inheriting from a base.
-- That is more lines, but a light scheme needs dark text and dark overlays,
-- and any inheritance scheme that has to invert half its values is harder to
-- read than simply writing them out.
--
-- Overlay note: rowAlt, rowHover, button and buttonHover sit *on top of* the
-- window colour. On dark schemes they are white at low alpha; on light ones
-- they must be black, or they wash out to invisible.

local SYL = _G.ShowUsYourLoot

local Palettes = {}
SYL.Palettes = Palettes

Palettes.list = {
    {
        key = "graphite",
        name = "Graphite",
        note = "Neutral dark grey",
        colors = {
            window = { 0.145, 0.150, 0.160, 0.97 },
            border = { 0.32, 0.33, 0.35, 1 },
            headerBar = { 0.195, 0.200, 0.215, 1 },
            separator = { 1, 1, 1, 0.14 },
            accent = { 0.20, 0.95, 0.60, 1 },
            accentMuted = { 0.20, 0.95, 0.60, 0.22 },
            rowAlt = { 1, 1, 1, 0.045 },
            rowHover = { 1, 1, 1, 0.11 },
            button = { 1, 1, 1, 0.11 },
            buttonHover = { 1, 1, 1, 0.20 },
            textPrimary = { 0.96, 0.97, 0.98, 1 },
            textSecondary = { 0.78, 0.80, 0.83, 1 },
            textMuted = { 0.58, 0.60, 0.64, 1 },
        },
    },
    {
        key = "slate",
        name = "Slate",
        note = "Cool blue-grey, mid tone",
        colors = {
            window = { 0.225, 0.265, 0.320, 0.97 },
            border = { 0.40, 0.46, 0.54, 1 },
            headerBar = { 0.275, 0.320, 0.385, 1 },
            separator = { 1, 1, 1, 0.16 },
            accent = { 1.00, 0.72, 0.30, 1 },
            accentMuted = { 1.00, 0.72, 0.30, 0.24 },
            rowAlt = { 1, 1, 1, 0.055 },
            rowHover = { 1, 1, 1, 0.13 },
            button = { 1, 1, 1, 0.13 },
            buttonHover = { 1, 1, 1, 0.22 },
            textPrimary = { 0.97, 0.98, 1.00, 1 },
            textSecondary = { 0.83, 0.86, 0.91, 1 },
            textMuted = { 0.66, 0.70, 0.77, 1 },
        },
    },
    {
        key = "rose",
        name = "Dusty Rose",
        note = "Muted pink, mid tone",
        colors = {
            window = { 0.505, 0.345, 0.395, 0.97 },
            border = { 0.68, 0.52, 0.575, 1 },
            headerBar = { 0.575, 0.415, 0.465, 1 },
            separator = { 1, 1, 1, 0.16 },
            accent = { 0.10, 0.62, 0.38, 1 },
            accentMuted = { 0.10, 0.62, 0.38, 0.24 },
            rowAlt = { 1, 1, 1, 0.06 },
            rowHover = { 1, 1, 1, 0.13 },
            button = { 1, 1, 1, 0.13 },
            buttonHover = { 1, 1, 1, 0.23 },
            textPrimary = { 1, 0.98, 0.985, 1 },
            textSecondary = { 0.92, 0.85, 0.875, 1 },
            textMuted = { 0.82, 0.73, 0.76, 1 },
        },
    },
    {
        key = "nightfall",
        name = "Nightfall",
        note = "Deep indigo",
        colors = {
            window = { 0.170, 0.145, 0.275, 0.97 },
            border = { 0.38, 0.33, 0.55, 1 },
            headerBar = { 0.220, 0.190, 0.340, 1 },
            separator = { 1, 1, 1, 0.15 },
            accent = { 0.55, 0.85, 1.00, 1 },
            accentMuted = { 0.55, 0.85, 1.00, 0.22 },
            rowAlt = { 1, 1, 1, 0.05 },
            rowHover = { 1, 1, 1, 0.12 },
            button = { 1, 1, 1, 0.12 },
            buttonHover = { 1, 1, 1, 0.21 },
            textPrimary = { 0.97, 0.96, 1.00, 1 },
            textSecondary = { 0.82, 0.79, 0.92, 1 },
            textMuted = { 0.64, 0.61, 0.78, 1 },
        },
    },
    {
        key = "moss",
        name = "Moss",
        note = "Deep green",
        colors = {
            window = { 0.135, 0.215, 0.175, 0.97 },
            border = { 0.30, 0.44, 0.36, 1 },
            headerBar = { 0.175, 0.270, 0.220, 1 },
            separator = { 1, 1, 1, 0.15 },
            accent = { 1.00, 0.78, 0.35, 1 },
            accentMuted = { 1.00, 0.78, 0.35, 0.22 },
            rowAlt = { 1, 1, 1, 0.05 },
            rowHover = { 1, 1, 1, 0.12 },
            button = { 1, 1, 1, 0.12 },
            buttonHover = { 1, 1, 1, 0.21 },
            textPrimary = { 0.96, 0.99, 0.97, 1 },
            textSecondary = { 0.80, 0.88, 0.83, 1 },
            textMuted = { 0.62, 0.72, 0.66, 1 },
        },
    },
    {
        -- The one genuinely light scheme. Text and overlays invert, and the
        -- window sits a little more opaque because a pale panel over a bright
        -- game world loses its edges otherwise.
        key = "parchment",
        name = "Parchment",
        note = "Light, warm",
        colors = {
            window = { 0.925, 0.905, 0.870, 0.98 },
            border = { 0.62, 0.58, 0.50, 1 },
            headerBar = { 0.855, 0.830, 0.785, 1 },
            separator = { 0, 0, 0, 0.16 },
            accent = { 0.10, 0.45, 0.72, 1 },
            accentMuted = { 0.10, 0.45, 0.72, 0.20 },
            rowAlt = { 0, 0, 0, 0.045 },
            rowHover = { 0, 0, 0, 0.10 },
            button = { 0, 0, 0, 0.10 },
            buttonHover = { 0, 0, 0, 0.18 },
            textPrimary = { 0.13, 0.11, 0.09, 1 },
            textSecondary = { 0.32, 0.29, 0.25, 1 },
            textMuted = { 0.48, 0.45, 0.40, 1 },
        },
    },
}

-- Nightfall, picked by the person who actually stares at this during raid.
-- The default matters more than it looks: it is what anyone installing this
-- sees before they know the setting exists.
Palettes.DEFAULT = "nightfall"

function Palettes.Get(key)
    for _, palette in ipairs(Palettes.list) do
        if palette.key == key then
            return palette
        end
    end

    return nil
end

-- Used by the settings row, which cycles rather than opening a menu.
function Palettes.Next(key)
    for index, palette in ipairs(Palettes.list) do
        if palette.key == key then
            local following = Palettes.list[index + 1] or Palettes.list[1]

            return following.key
        end
    end

    return Palettes.DEFAULT
end
