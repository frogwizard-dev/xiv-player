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
    x = 0, y = 0,       -- nudge from its place left of the HP gauge
    pulse = true,       -- breathes slowly in and out
    color = { r = 0.60, g = 0.78, b = 1.00 }, -- FFXIV's rested blue, lightened
}

local function Settings() return ns.db.rest end

function Rest:Init(parent, gauge)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetShadowOffset(1, -1)
    text:SetJustifyH("RIGHT")
    text:Hide()
    self.text, self.gauge = text, gauge

    local pulse = text:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.35)
    fade:SetDuration(1.4)
    fade:SetSmoothing("IN_OUT")
    self.pulse = pulse

    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    pcall(events.RegisterEvent, events, "PLAYER_UPDATE_RESTING")
    events:SetScript("OnEvent", function() self:Update() end)
end

function Rest:Apply()
    local text = self.text
    if not text then return end
    local db, settings = ns.db, Settings()
    ns.Media:SetFont(text, db.font, settings.size, db.outline)
    text:ClearAllPoints()
    text:SetPoint("RIGHT", self.gauge.bar, "LEFT", -6 + settings.x, settings.y)
    text:SetText(settings.text)
    text:SetTextColor(settings.color.r, settings.color.g, settings.color.b)
    self:Update()
end

function Rest:Update()
    local text = self.text
    if not text then return end
    local settings = Settings()
    local shown = settings.enabled and (IsResting() or not ns.db.locked) and true or false
    text:SetShown(shown)
    if shown and settings.pulse then
        if not self.pulse:IsPlaying() then self.pulse:Play() end
    else
        self.pulse:Stop()
        text:SetAlpha(1)
    end
end

-- Its settings, on the Text page (place: that page's placer).
function Rest.BuildSettings(page, place)
    local UI, settings = ns.UI, Settings()
    place(UI.Label(page, "Resting"), 22)
    place(UI.Checkbox(page, "Show \"Zzz\" while I'm resting (an inn or a city: rested XP builds)", settings, "enabled"), 28)
    place(UI.TextBox(page, "Its text", settings, "text"), 28)
    place(UI.Stepper(page, "Size", 8, 32, 1, settings, "size"), 26)
    place(UI.Pair(page, "Nudge", { "x", -300, 300, settings, "x" }, { "y", -100, 100, settings, "y" }), 30)
    place(UI.ColorSwatch(page, "Colour", settings, "color"), 30)
    place(UI.Checkbox(page, "Pulse slowly", settings, "pulse"), 28)
    place(UI.Help(page, "It sits left of the HP gauge; unlock the bar (Layout) to see it while you nudge it.",
        400), 24)
end
