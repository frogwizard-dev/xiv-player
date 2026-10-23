local _, ns = ...
local Rest = {}
ns.Rest = Rest

-- "Zzz" by the HP gauge while you're resting (an inn or a city: where rested XP builds up and
-- you can log out at once), as Blizzard's player frame shows. In the bar's font, a soft pulse if
-- you like; shown as a sample while the bar is unlocked, so it can be placed.

ns.defaults.rest = {
    enabled = true,
    text = "Zzz",
    size = 14,
    x = 0, y = 0,       -- nudge from its place just left of the HP gauge
    pulse = true,       -- breathes slowly in and out
    color = { r = 0.60, g = 0.78, b = 1.00 }, -- FFXIV's rested blue, lightened
}

local function Cfg() return ns.db.rest end

function Rest:Init(parent, gauge)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetShadowOffset(1, -1)
    fs:SetJustifyH("RIGHT")
    fs:Hide()
    self.text, self.gauge = fs, gauge

    local pulse = fs:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.35)
    fade:SetDuration(1.4)
    fade:SetSmoothing("IN_OUT")
    self.pulse = pulse

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    pcall(ev.RegisterEvent, ev, "PLAYER_UPDATE_RESTING")
    ev:SetScript("OnEvent", function() self:Update() end)
end

function Rest:Apply()
    local fs = self.text
    if not fs then return end
    local db, cfg = ns.db, Cfg()
    ns.Media:SetFont(fs, db.font, cfg.size, db.outline)
    fs:ClearAllPoints()
    fs:SetPoint("RIGHT", self.gauge.bar, "LEFT", -6 + cfg.x, cfg.y)
    fs:SetText(cfg.text)
    fs:SetTextColor(cfg.color.r, cfg.color.g, cfg.color.b)
    self:Update()
end

function Rest:Update()
    local fs = self.text
    if not fs then return end
    local cfg = Cfg()
    local shown = cfg.enabled and (IsResting() or not ns.db.locked) and true or false
    fs:SetShown(shown)
    if shown and cfg.pulse then
        if not self.pulse:IsPlaying() then self.pulse:Play() end
    else
        self.pulse:Stop()
        fs:SetAlpha(1)
    end
end

-- Its settings, on the Text page (place: that page's placer).
function Rest.BuildSettings(p, place)
    local UI, cfg = ns.UI, Cfg()
    place(UI.Label(p, "Resting"), 22)
    place(UI.Checkbox(p, "Show \"Zzz\" while I'm resting (an inn or a city: rested XP builds)",
        function() return cfg.enabled end, function(v) cfg.enabled = v end), 28)
    place(UI.TextBox(p, "Its text", function() return cfg.text end, function(v) cfg.text = v end), 28)
    place(UI.Stepper(p, "Size", 8, 32, 1, function() return cfg.size end, function(v) cfg.size = v end), 26)
    place(UI.Pair(p, "Nudge", { "x", -300, 300, function() return cfg.x end, function(v) cfg.x = v end },
        { "y", -100, 100, function() return cfg.y end, function(v) cfg.y = v end }), 30)
    place(UI.ColorSwatch(p, "Colour", function() return cfg.color end,
        function(r, g, b) cfg.color = { r = r, g = g, b = b } end), 30)
    place(UI.Checkbox(p, "Pulse slowly", function() return cfg.pulse end, function(v) cfg.pulse = v end), 28)
    place(UI.Help(p, "It sits just left of the HP gauge; unlock the bar (Layout) to see it while you nudge it.",
        400), 24)
end
