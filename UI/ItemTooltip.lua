-- UI/ItemTooltip.lua
--
-- Adds "won by X" to any item tooltip in the game, if this addon has seen
-- that item drop.
--
-- The point is that the answer finds you: hovering an item in a bag, in the
-- auction house or in someone's chat link tells you whether the guild has
-- had one and who took it, without opening anything.

local SYL = _G.ShowUsYourLoot
local Utilities = SYL.Utilities

local ItemTooltip = {}
SYL.ItemTooltip = ItemTooltip

local MAX_LINES = 4

-- itemID -> that item's drops, newest first. Nil until something asks.
--
-- This used to run per tooltip, and a tooltip is not a rare event: mousing
-- across a full bag fires dozens a second, and each one called GetAllDrops —
-- which allocates a fresh array and copies every drop from the active season
-- and every archive into it — then filtered and sorted the result. A season's
-- history, rebuilt and re-sorted, to answer a question about one item.
--
-- Indexed once instead. Drops are written in exactly two places, and a season
-- changing replaces the array wholesale, so the invalidation points are
-- countable rather than hopeful.
local index

function ItemTooltip.Invalidate()
    index = nil
end

local function BuildIndex()
    index = {}

    for _, record in ipairs(SYL.GetAllDrops()) do
        local itemID = record.itemID

        if itemID and not record.excludedFromAnalytics then
            local matches = index[itemID]

            if not matches then
                matches = {}
                index[itemID] = matches
            end

            table.insert(matches, record)
        end
    end

    for _, matches in pairs(index) do
        table.sort(matches, function(left, right)
            return (left.timestamp or 0) > (right.timestamp or 0)
        end)
    end
end

local function BuildHistory(itemID)
    if not index then
        BuildIndex()
    end

    return index[itemID] or {}
end

local function AddHistoryLines(tooltip, itemID)
    local matches = BuildHistory(itemID)

    if #matches == 0 then
        return
    end

    tooltip:AddLine(" ")

    tooltip:AddLine(
        "Show Us Your Loot — "
        .. #matches
        .. (#matches == 1 and " drop recorded" or " drops recorded"),
        0.20, 0.86, 0.56
    )

    for index = 1, math.min(MAX_LINES, #matches) do
        local record = matches[index]

        local winner = record.allPassed
            and "everyone passed"
            or tostring(record.winnerName or "Unknown")

        local winType =
            SYL.LootHistoryAPI.ShortRollState(record.winnerState)

        tooltip:AddDoubleLine(
            winner .. (winType and ("  (" .. winType .. ")") or ""),
            Utilities.FormatDateOnly(record.timestamp),
            0.92, 0.85, 0.875,
            0.72, 0.66, 0.68
        )
    end

    if #matches > MAX_LINES then
        tooltip:AddLine(
            "and " .. (#matches - MAX_LINES) .. " more",
            0.72, 0.66, 0.68
        )
    end
end

local function OnTooltipItem(tooltip, data)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then
        return
    end

    local itemID = data and data.id

    if not itemID then
        local _, link = tooltip:GetItem()

        itemID = Utilities.GetItemIDFromLink(link)
    end

    if itemID then
        AddHistoryLines(tooltip, itemID)
    end
end

function ItemTooltip.Enable()
    -- The modern hook. Older clients used HookScript on OnTooltipSetItem, so
    -- both paths are attempted and whichever exists wins.
    if TooltipDataProcessor
        and TooltipDataProcessor.AddTooltipPostCall
        and Enum
        and Enum.TooltipDataType
    then
        TooltipDataProcessor.AddTooltipPostCall(
            Enum.TooltipDataType.Item,
            OnTooltipItem
        )

        return true
    end

    if GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetItem", function(self)
            local _, link = self:GetItem()
            local itemID = Utilities.GetItemIDFromLink(link)

            if itemID then
                AddHistoryLines(self, itemID)
            end
        end)

        return true
    end

    return false
end
