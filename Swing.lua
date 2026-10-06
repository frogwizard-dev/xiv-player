local ADDON, ns = ...
local Swing = {}
ns.Swing = Swing

-- Swing timers in the cast bar's look: one gauge per hand (main hand, off hand when you dual
-- wield, ranged with a ranged weapon), stacked, each with the hand's name over its left end and
-- the time to the next swing over its right. Driven by PLAYER_SWING, like Blizzard's own
-- (Blizzard_SwingTimer) and FrogUI's: each swing gives the time until the next one.
--   * Shown in combat, with an enemy targeted, either, or always.
--   * Out of range of your target, a bar dims and its time turns red, as Blizzard's do.
--   * Blizzard's swing bars can be faded out (opacity only: they keep their place in Edit Mode).
--   * Unlocked (Layout tab), every bar shows a sample and the group can be dragged.
-- The workings (each hand's timer, when to show, range, fading Blizzard's bars) are FrogLib's
-- (FrogLib.Swing, which FrogUI's swing timer uses too); the gauges are XIVPlayer's.

local Lib = FrogLib.Swing
local HANDS = Lib.HANDS
Swing.hands = HANDS
local OUT_OF_RANGE_ALPHA = 0.4
local IMMEDIATE = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
local ROW_GAP = 3

local rows = {} -- by swing type

local function Text(parent)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.9)
    return fs
end

local function SetFill(row, v)
    row.gauge.bar:SetValue(v, IMMEDIATE)
end

------------------------------------------------------------------------------
-- Which bars, and when
------------------------------------------------------------------------------

function Swing:Wanted()
    local cfg = ns.db.swing
    if not cfg.enabled then return false end
    if not ns.db.locked then return true end -- samples to place
    return Lib.Wanted(cfg.show, self.tracker and self.tracker.inCombat)
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
    local cfg = ns.db.swing
    for _, row in pairs(rows) do
        local out = cfg.dimOutOfRange and ns.db.locked and Lib.OutOfRange(row.hand) or false
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
            Clear(row) -- it has just run out
        end
    end
    sinceRange = sinceRange + elapsed
    if sinceRange > 0.2 then
        sinceRange = 0
        UpdateRange()
    end
end

------------------------------------------------------------------------------
-- Blizzard's bars: faded out (opacity only; they keep their place in Edit Mode's layout).
------------------------------------------------------------------------------

local function FadeBlizzard()
    Lib.FadeBlizzard(ADDON, ns.db.swing.enabled and ns.db.swing.hideBlizzard)
end

------------------------------------------------------------------------------
-- Building and layout
------------------------------------------------------------------------------

-- Where it sits: its top centre, from the bottom centre of the player bar.
function Swing:Anchor()
    local f, cfg = self.frame, ns.db.swing
    f:ClearAllPoints()
    f:SetPoint("TOP", ns.Player.frame, "BOTTOM", cfg.x, cfg.y)
end

function Swing:SavePosition()
    local f, pf, cfg = self.frame, ns.Player.frame, ns.db.swing
    local cx, top = f:GetCenter(), f:GetTop()
    local px, bottom = pf:GetCenter(), pf:GetBottom()
    -- Both are on UIParent at the bar's scale, so their coordinates are in the same units.
    if cx and top and px and bottom then
        cfg.x = math.floor(cx - px + 0.5)
        cfg.y = math.floor(top - bottom + 0.5)
    end
    self:Anchor()
end

function Swing:Init()
    local f = CreateFrame("Frame", "XIVPlayerSwingTimer", UIParent)
    f:SetSize(1, 1)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        frame:SetUserPlaced(false)
        Swing:SavePosition()
    end)
    f.tint = f:CreateTexture(nil, "BACKGROUND")
    f.tint:SetPoint("TOPLEFT", -6, 6)
    f.tint:SetPoint("BOTTOMRIGHT", 6, -6)
    f.tint:SetColorTexture(0.3, 0.6, 1, 0.2)
    self.frame = f

    for _, hand in ipairs(HANDS) do
        local row = CreateFrame("Frame", nil, f)
        row.hand = hand
        local g = FrogLib.Gauge.New(row)
        row.gauge = g
        row.name = Text(row)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.time = Text(row)
        row.time:SetJustifyH("RIGHT")
        rows[hand.type] = row
        Clear(row)
    end
    f:SetScript("OnUpdate", OnUpdate)

    -- Swings, combat, target, range, weapons and Blizzard's bars loading, from FrogLib's tracker.
    self.tracker = Lib.NewTracker({
        accept = function() return ns.db.locked end, -- the samples stand still
        onShown = function() self:UpdateShown() end,
        onRange = UpdateRange,
        onLayout = function() self:Layout() end,
        onBlizzard = FadeBlizzard,
    })
    f:Hide()
end

-- Rows, sizes and samples, from the settings.
function Swing:Layout()
    local f = self.frame
    if not f then return end
    local db, cfg = ns.db, ns.db.swing
    local unlocked = not db.locked
    local framed = db.style == "framed"
    local rim = framed and 4 or 1               -- the gold rim (or line glow) beyond the bar
    local textSize = db.labelSize
    local textRoom = (cfg.showLabel or cfg.showTime) and (textSize + 4) or 0
    local rowH = textRoom + cfg.height + rim * 2
    local y, any = 0, false
    for _, hand in ipairs(HANDS) do
        local row = rows[hand.type]
        local on = cfg[hand.key] and (unlocked or Lib.HasWeapon(hand)) or false
        row:SetShown(on)
        if on then
            any = true
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
            row:SetSize(cfg.width, rowH)
            local g = row.gauge
            g.bar:ClearAllPoints()
            g.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, rim)
            g.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, rim)
            g:SetStyle(db.style)
            g:SetHeight(cfg.height)
            g:SetTexture(db.texture)
            g.bar:SetMinMaxValues(0, 1)
            local c = cfg.colors[hand.key]
            g:SetColor(c.r, c.g, c.b)
            for _, fs in ipairs({ row.name, row.time }) do
                ns.Media:SetFont(fs, db.font, textSize, db.outline)
            end
            row.name:ClearAllPoints()
            row.name:SetPoint("BOTTOMLEFT", g.bar, "TOPLEFT", 1, rim + 1)
            row.name:SetWidth(cfg.width * 0.7)
            row.name:SetText(hand.label)
            row.name:SetTextColor(c.r + (1 - c.r) * 0.6, c.g + (1 - c.g) * 0.6, c.b + (1 - c.b) * 0.6)
            row.name:SetShown(cfg.showLabel)
            row.time:ClearAllPoints()
            row.time:SetPoint("BOTTOMRIGHT", g.bar, "TOPRIGHT", -1, rim + 1)
            row.time:SetShown(cfg.showTime)
            if unlocked then
                self.tracker:Clear(hand)
                SetFill(row, 0.6)
                row.time:SetText("1.4")
            elseif not self.tracker:Running(hand) then
                Clear(row)
            end
            y = y + rowH + ROW_GAP
        end
    end
    f:SetSize(cfg.width, any and (y - ROW_GAP) or 1)
    self:UpdateShown()
    UpdateRange()
end

function Swing:Apply()
    local f = self.frame
    if not f then return end
    local db = ns.db
    f:SetScale(db.scale)
    self:Anchor()
    local unlocked = not db.locked and db.swing.enabled
    f:EnableMouse(unlocked)
    f.tint:SetShown(unlocked)
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

function Swing.BuildPage(p)
    local UI = ns.UI
    local cfg = ns.db.swing
    local place = UI.Placer()
    place(UI.Checkbox(p, "Show swing timers",
        function() return cfg.enabled end, function(v) cfg.enabled = v end), 28)
    place(UI.Checkbox(p, "Hide Blizzard's swing timers",
        function() return cfg.hideBlizzard end, function(v) cfg.hideBlizzard = v end), 30)
    place(UI.Dropdown(p, "Show", SHOW, function() return cfg.show end, function(v) cfg.show = v end), 32)
    for _, hand in ipairs(HANDS) do
        local key = hand.key
        local text = key == "main" and "Main hand" or key == "off" and "Off hand (when dual wielding)"
            or "Ranged (with a ranged weapon)"
        place(UI.Checkbox(p, text, function() return cfg[key] end, function(v) cfg[key] = v end), 26)
    end
    place(UI.Checkbox(p, "Show the hand's name",
        function() return cfg.showLabel end, function(v) cfg.showLabel = v end), 26)
    place(UI.Checkbox(p, "Show time to the next swing",
        function() return cfg.showTime end, function(v) cfg.showTime = v end), 26)
    place(UI.Checkbox(p, "Dim when your target is out of range",
        function() return cfg.dimOutOfRange end, function(v) cfg.dimOutOfRange = v end), 32)
    place(UI.Stepper(p, "Width", 60, 600, 10, function() return cfg.width end, function(v) cfg.width = v end), 26)
    place(UI.Stepper(p, "Height", 2, 20, 1, function() return cfg.height end, function(v) cfg.height = v end), 26)
    place(UI.Stepper(p, "Move left / right", -1200, 1200, 2, function() return cfg.x end,
        function(v) cfg.x = v end), 26)
    place(UI.Stepper(p, "Move up / down", -600, 600, 2, function() return cfg.y end,
        function(v) cfg.y = v end), 32)
    for _, hand in ipairs(HANDS) do
        local key = hand.key
        place(UI.ColorSwatch(p, hand.label .. " colour", function() return cfg.colors[key] end,
            function(r, g, b) cfg.colors[key] = { r = r, g = g, b = b } end), 28)
    end
    place(UI.Help(p, "Uses the gauge style, texture and font from the other tabs. Unlock the bar "
        .. "(Layout) to see samples and drag the timers into place.", 400), 36, 0)
end
