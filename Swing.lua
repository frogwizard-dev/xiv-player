local ADDON, ns = ...
local Swing = {}
ns.Swing = Swing

-- Swing timers in the cast bar's look: a gauge per hand (main, off hand when dual wielding, ranged
-- with a ranged weapon), stacked, the hand's name over the left end and the time to the next swing
-- over the right. Out of range a bar dims and its time turns red, as Blizzard's do. The workings are
-- FrogLib.Swing's (FrogUI's swing timer uses them too); the gauges are XIVPlayer's.

local SwingKit = FrogLib.Swing
local Shadowed = FrogLib.Text.Shadowed
local HANDS = SwingKit.HANDS
Swing.hands = HANDS
local OUT_OF_RANGE_ALPHA = 0.4
local IMMEDIATE = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
local ROW_GAP = 3

local rows = {} -- by swing type

local function SetFill(row, value)
    row.gauge.bar:SetValue(value, IMMEDIATE)
end

------------------------------------------------------------------------------
-- Which bars, and when
------------------------------------------------------------------------------

function Swing:Wanted()
    local settings = ns.db.swing
    if not settings.enabled then return false end
    if not ns.db.locked then return true end -- samples to place
    return SwingKit.Wanted(settings.show, self.tracker and self.tracker.inCombat)
end

function Swing:UpdateShown()
    if self.frame then self.frame:SetShown(self:Wanted()) end
end

------------------------------------------------------------------------------
-- Swings
------------------------------------------------------------------------------

-- Empty until the next swing.
local function Clear(row)
    if Swing.tracker then Swing.tracker:Clear(row.hand) end
    SetFill(row, 0)
    row.time:SetText("")
end

local function UpdateRange()
    local settings = ns.db.swing
    for _, row in pairs(rows) do
        local out = settings.dimOutOfRange and ns.db.locked and SwingKit.OutOfRange(row.hand) or false
        row:SetAlpha(out and OUT_OF_RANGE_ALPHA or 1)
        if out then row.time:SetTextColor(1, 0.3, 0.25) else row.time:SetTextColor(1, 0.97, 0.9) end
    end
end

local sinceRange = 0
local function OnUpdate(_, elapsed)
    if not ns.db.locked then return end -- samples stand still
    local now = GetTime()
    for _, row in pairs(rows) do
        local done, left = Swing.tracker:Progress(row.hand, now)
        if done then
            SetFill(row, done)
            if ns.db.swing.showTime then row.time:SetFormattedText("%.1f", left) end
        elseif left then
            Clear(row) -- it has run out this moment
        end
    end
    sinceRange = sinceRange + elapsed
    if sinceRange > 0.2 then
        sinceRange = 0
        UpdateRange()
    end
end

-- Blizzard's bars, faded out: opacity only, so they keep their place in Edit Mode's layout.
local function FadeBlizzard()
    SwingKit.FadeBlizzard(ADDON, ns.db.swing.enabled and ns.db.swing.hideBlizzard)
end

------------------------------------------------------------------------------
-- Building and layout
------------------------------------------------------------------------------

-- Where it sits: its top centre, from the bottom centre of the player bar.
function Swing:Anchor()
    local frame, settings = self.frame, ns.db.swing
    frame:ClearAllPoints()
    frame:SetPoint("TOP", ns.Player.frame, "BOTTOM", settings.x, settings.y)
end

function Swing:SavePosition()
    local frame, playerFrame, settings = self.frame, ns.Player.frame, ns.db.swing
    local centreX, top = frame:GetCenter(), frame:GetTop()
    local playerX, bottom = playerFrame:GetCenter(), playerFrame:GetBottom()
    -- Both are on UIParent at the bar's scale, so their coordinates are in the same units.
    if centreX and top and playerX and bottom then
        settings.x = math.floor(centreX - playerX + 0.5)
        settings.y = math.floor(top - bottom + 0.5)
    end
    self:Anchor()
end

function Swing:Init()
    local frame = CreateFrame("Frame", "XIVPlayerSwingTimer", UIParent)
    frame:SetSize(1, 1)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(dragged)
        dragged:StopMovingOrSizing()
        dragged:SetUserPlaced(false)
        Swing:SavePosition()
    end)
    frame.tint = frame:CreateTexture(nil, "BACKGROUND")
    frame.tint:SetPoint("TOPLEFT", -6, 6)
    frame.tint:SetPoint("BOTTOMRIGHT", 6, -6)
    frame.tint:SetColorTexture(0.3, 0.6, 1, 0.2)
    self.frame = frame

    for _, hand in ipairs(HANDS) do
        local row = CreateFrame("Frame", nil, frame)
        row.hand = hand
        row.gauge = FrogLib.Gauge.New(row)
        row.name = Shadowed(row)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.time = Shadowed(row)
        row.time:SetJustifyH("RIGHT")
        rows[hand.type] = row
        Clear(row)
    end
    frame:SetScript("OnUpdate", OnUpdate)

    -- Swings, combat, target, range, weapons and Blizzard's bars loading, from FrogLib's tracker.
    self.tracker = SwingKit.NewTracker({
        accept = function() return ns.db.locked end, -- the samples stand still
        onShown = function() self:UpdateShown() end,
        onRange = UpdateRange,
        onLayout = function() self:Layout() end,
        onBlizzard = FadeBlizzard,
    })
    frame:Hide()
end

-- Rows, sizes and samples, from the settings.
function Swing:Layout()
    local frame = self.frame
    if not frame then return end
    local db, settings = ns.db, ns.db.swing
    local unlocked = not db.locked
    local framed = db.style == "framed"
    local rim = framed and 4 or 1               -- the gold rim (or line glow) beyond the bar
    local textSize = db.labelSize
    local textRoom = (settings.showLabel or settings.showTime) and (textSize + 4) or 0
    local rowHeight = textRoom + settings.height + rim * 2
    local y, any = 0, false
    for _, hand in ipairs(HANDS) do
        local row = rows[hand.type]
        local on = settings[hand.key] and (unlocked or SwingKit.HasWeapon(hand)) or false
        row:SetShown(on)
        if on then
            any = true
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
            row:SetSize(settings.width, rowHeight)
            local gauge = row.gauge
            gauge.bar:ClearAllPoints()
            gauge.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, rim)
            gauge.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, rim)
            gauge:SetStyle(db.style)
            gauge:SetHeight(settings.height)
            gauge:SetTexture(db.texture)
            gauge.bar:SetMinMaxValues(0, 1)
            local color = settings.colors[hand.key]
            gauge:SetColor(color.r, color.g, color.b)
            for _, text in ipairs({ row.name, row.time }) do
                ns.Media:SetFont(text, db.font, textSize, db.outline)
            end
            row.name:ClearAllPoints()
            row.name:SetPoint("BOTTOMLEFT", gauge.bar, "TOPLEFT", 1, rim + 1)
            row.name:SetWidth(settings.width * 0.7)
            row.name:SetText(hand.label)
            row.name:SetTextColor(color.r + (1 - color.r) * 0.6, color.g + (1 - color.g) * 0.6, color.b + (1 - color.b) * 0.6)
            row.name:SetShown(settings.showLabel)
            row.time:ClearAllPoints()
            row.time:SetPoint("BOTTOMRIGHT", gauge.bar, "TOPRIGHT", -1, rim + 1)
            row.time:SetShown(settings.showTime)
            if unlocked then
                self.tracker:Clear(hand)
                SetFill(row, 0.6)
                row.time:SetText("1.4")
            elseif not self.tracker:Running(hand) then
                Clear(row)
            end
            y = y + rowHeight + ROW_GAP
        end
    end
    frame:SetSize(settings.width, any and (y - ROW_GAP) or 1)
    self:UpdateShown()
    UpdateRange()
end

function Swing:Apply()
    local frame = self.frame
    if not frame then return end
    local db = ns.db
    frame:SetScale(db.scale)
    self:Anchor()
    local unlocked = not db.locked and db.swing.enabled
    frame:EnableMouse(unlocked)
    frame.tint:SetShown(unlocked)
    if db.locked and self.wasUnlocked then
        -- Leaving the samples: back to empty bars until the next swing.
        for _, row in pairs(rows) do Clear(row) end
    end
    self.wasUnlocked = not db.locked
    FadeBlizzard()
    self:Layout()
end

------------------------------------------------------------------------------
-- Settings page
------------------------------------------------------------------------------

local SHOW = ns.UI.Options("combat", "In combat", "target", "With an enemy targeted",
    "either", "In combat or with an enemy targeted", "always", "Always")

function Swing.BuildPage(page)
    local UI = ns.UI
    local settings = ns.db.swing
    local place = UI.Placer()
    place(UI.Checkbox(page, "Show swing timers", settings, "enabled"), 28)
    place(UI.Checkbox(page, "Hide Blizzard's swing timers", settings, "hideBlizzard"), 30)
    place(UI.Dropdown(page, "Show", SHOW, settings, "show"), 32)
    for _, hand in ipairs(HANDS) do
        local key = hand.key
        local text = key == "main" and "Main hand" or key == "off" and "Off hand (when dual wielding)"
            or "Ranged (with a ranged weapon)"
        place(UI.Checkbox(page, text, settings, key), 26)
    end
    place(UI.Checkbox(page, "Show the hand's name", settings, "showLabel"), 26)
    place(UI.Checkbox(page, "Show time to the next swing", settings, "showTime"), 26)
    place(UI.Checkbox(page, "Dim when your target is out of range", settings, "dimOutOfRange"), 32)
    place(UI.Stepper(page, "Width", 60, 600, 10, settings, "width"), 26)
    place(UI.Stepper(page, "Height", 2, 20, 1, settings, "height"), 26)
    place(UI.Stepper(page, "Move left / right", -1200, 1200, 2, settings, "x"), 26)
    place(UI.Stepper(page, "Move up / down", -600, 600, 2, settings, "y"), 32)
    for _, hand in ipairs(HANDS) do
        place(UI.ColorSwatch(page, hand.label .. " colour", settings.colors, hand.key), 28)
    end
    place(UI.Help(page, "Uses the gauge style, texture and font from the other tabs. Unlock the bar "
        .. "(Layout) to see samples and drag the timers into place.", 400), 36, 0)
end
