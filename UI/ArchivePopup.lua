-- UI/ArchivePopup.lua
--
-- The "archive this season" confirmation dialog. Kept separate from the main
-- window because archiving is a destructive-feeling action that any window
-- may need to offer, and the caller decides what happens afterwards.

local SYL = _G.ShowUsYourLoot

local ArchivePopup = {}
SYL.ArchivePopup = ArchivePopup

local DIALOG_KEY = "SHOWUSYOURLOOT_ARCHIVE_SEASON"

StaticPopupDialogs[DIALOG_KEY] = {
    text = "Archive the current season and enter the name of the new active season.",

    button1 = "Archive",
    button2 = "Cancel",

    hasEditBox = true,
    editBoxWidth = 240,

    OnShow = function(self)
        self.EditBox:SetText("New Season")
        self.EditBox:HighlightText()
        self.EditBox:SetFocus()
    end,

    OnAccept = function(self)
        local newSeasonName = self.EditBox:GetText()

        if not newSeasonName or newSeasonName == "" then
            newSeasonName = "New Season"
        end

        local archivedSeason, newSeason =
            SYL.ArchiveCurrentSeason(newSeasonName)

        if not archivedSeason then
            return
        end

        SYL:Print(
            "Archived "
            .. archivedSeason.name
            .. " with "
            .. #(archivedSeason.loot or {})
            .. " records."
        )

        SYL:Print("New active season: " .. newSeason.name)

        if ArchivePopup.onArchived then
            ArchivePopup.onArchived()
        end
    end,

    EditBoxOnEnterPressed = function(self)
        self:GetParent().button1:Click()
    end,

    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,

    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- onArchived runs only when a season was actually archived, so the caller can
-- move its view back to the new active season.
function ArchivePopup.Show(onArchived)
    ArchivePopup.onArchived = onArchived

    StaticPopup_Show(DIALOG_KEY)
end
