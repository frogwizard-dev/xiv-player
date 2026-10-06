local _, ns = ...
local Regen = {}
ns.Regen = Regen

-- Mana regen on whichever gauge shows your mana (the MP gauge, or the forms' mana gauge):
--   * the rate, beside the MP number: "+7.5/s" (or "+37 mp5"), from GetManaRegen, the game's
--     own number (the character sheet's Mana Regen). Forever regenerates mana continuously
--     (Blizzard's own player frame polls UnitPower every frame and moves smoothly), so a live
--     rate says more than a tick marker would. While the five-second rule holds it shows the
--     while-casting rate (usually nothing at all), dimmed.
--   * the five-second rule: spending mana stops regen for five seconds; a thin strip under the
--     gauge fills across those seconds, a spark at its tip, and goes when regen starts again.
-- Secret-safe: the rate can be secret in combat, so it only ever goes into SetFormattedText;
-- the five-second timer starts from spell data (the cast's mana cost), not from your mana; for a
-- spell the game keeps secret, from the drop in your mana that comes with it (FrogLib.FSR, which
-- Personal Resource Tweaks uses too).

local issecret = FrogLib.issecret
local RULE = FrogLib.FSR.RULE
local SPARK = "Interface\\CastingBar\\UI-CastingBar-Spark"
local RATE_EVERY = 0.5 -- seconds between rate refreshes (it changes with buffs and gear)

function Regen:Init(parent)
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetHeight(2)
    strip.track = strip:CreateTexture(nil, "BACKGROUND")
    strip.track:SetAllPoints()
    strip.track:SetColorTexture(0, 0, 0, 0.5)
    strip.fill = strip:CreateTexture(nil, "ARTWORK")
    strip.fill:SetPoint("TOPLEFT")
    strip.fill:SetPoint("BOTTOMLEFT")
    strip.spark = strip:CreateTexture(nil, "OVERLAY")
    strip.spark:SetTexture(SPARK)
    strip.spark:SetBlendMode("ADD")
    strip.spark:SetSize(8, 10)
    strip:Hide()
    self.strip = strip

    local rate = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    rate:SetShadowOffset(1, -1)
    rate:Hide()
    self.rate = rate
    self.since = RATE_EVERY
end

-- block: the gauge block showing your mana, or nil when none does (rage, energy).
function Regen:Attach(block, r, g, b)
    self.block = block
    local db = ns.db
    local strip, rate = self.strip, self.rate
    if not block then
        strip:Hide()
        rate:Hide()
        return
    end
    -- Just under the gauge (and its gold rim in the framed style), above the big number.
    local below = db.style == "framed" and 5 or 2
    strip:ClearAllPoints()
    strip:SetPoint("TOPLEFT", block.gauge.bar, "BOTTOMLEFT", 0, -below)
    strip:SetPoint("TOPRIGHT", block.gauge.bar, "BOTTOMRIGHT", 0, -below)
    local lr, lg, lb = r + (1 - r) * 0.45, g + (1 - g) * 0.45, b + (1 - b) * 0.45
    strip.fill:SetColorTexture(lr, lg, lb, 0.95)
    strip.spark:SetVertexColor(lr, lg, lb)
    self.color = { r + (1 - r) * 0.55, g + (1 - g) * 0.55, b + (1 - b) * 0.55 }

    ns.Media:SetFont(rate, db.font, math.max(db.labelSize, math.floor(db.numberSize * 0.5)), db.outline)
    rate:ClearAllPoints()
    rate:SetPoint("BOTTOMLEFT", block.number, "BOTTOMRIGHT", 6, 1)
    self.since = RATE_EVERY -- refresh on the next frame
end

-- The five-second rule starts (or starts over).
function Regen:Start(at)
    self.ruleEnds = (at or GetTime()) + RULE
    self.since = RATE_EVERY
end

Regen.fsr = FrogLib.FSR.NewWatcher(function(at) Regen:Start(at) end)

function Regen:InRule()
    return self.ruleEnds ~= nil and GetTime() < self.ruleEnds
end

-- UNIT_SPELLCAST_SUCCEEDED. A secret spell ID can't be looked up; then a drop in your mana
-- just before or after the cast (when your mana isn't secret) starts the timer instead.
function Regen:OnCast(spellID)
    self.fsr:OnCast(spellID)
end

-- Every change to your mana the gauges see, with values that may be secret.
function Regen:OnMana(value, max)
    self.fsr:OnMana(value, max)
end

function Regen:UpdateRate()
    local cfg, rate = ns.db.regen, self.rate
    if not (cfg.rate and self.block and GetManaRegen) then
        rate:Hide()
        return
    end
    local ok, base, casting = pcall(GetManaRegen)
    -- No and/or or nil tests on the rates themselves: either may be secret.
    local inRule = self:InRule()
    local v
    if inRule then v = casting else v = base end
    if not ok or (not issecret(v) and type(v) ~= "number") then
        rate:Hide()
        return
    end
    rate:Show()
    if cfg.per == 5 and not issecret(v) then
        rate:SetFormattedText("+%d mp5", math.floor(v * 5 + 0.5))
    else
        -- Per second; also the fallback for mp5 while the rate is secret (no arithmetic on it).
        pcall(rate.SetFormattedText, rate, "+%.1f/s", v)
    end
    if inRule then
        rate:SetTextColor(0.6, 0.6, 0.6)
    else
        local c = self.color or { 1, 1, 1 }
        rate:SetTextColor(c[1], c[2], c[3])
    end
end

-- Every frame (from the player bar's poller).
function Regen:Update(elapsed)
    local strip = self.strip
    if not strip then return end
    local cfg = ns.db.regen
    local left
    if self.ruleEnds then
        left = self.ruleEnds - GetTime()
        if left <= 0 then
            self.ruleEnds, left = nil, nil
            self.since = RATE_EVERY -- regen is back: show its rate now
        end
    end
    -- Unlocked: a sample, to see where it sits.
    if not left and not ns.db.locked then left = RULE * 0.4 end
    if left and cfg.rule and self.block then
        local width = strip:GetWidth() or 0
        local x = (1 - left / RULE) * width
        strip.fill:SetWidth(math.max(0.01, x))
        strip.spark:ClearAllPoints()
        strip.spark:SetPoint("CENTER", strip, "LEFT", x, 0)
        strip:Show()
    else
        strip:Hide()
    end

    self.since = self.since + (elapsed or 0)
    if self.since >= RATE_EVERY then
        self.since = 0
        self:UpdateRate()
    end
end
