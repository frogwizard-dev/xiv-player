local _, ns = ...
local Regen = {}
ns.Regen = Regen

-- Mana regen on whichever gauge shows your mana: the rate beside the number ("+7.5/s" or "+37 mp5",
-- the game's own GetManaRegen, live as Forever regenerates continuously; dimmed while the five-second
-- rule holds), and that rule as a thin strip under the gauge filling across its five seconds. The rate
-- can be secret, so it only goes into SetFormattedText; the rule starts from the cast (FrogLib.FSR).

local issecret = FrogLib.issecret
local RULE = FrogLib.FSR.RULE
local RATE_EVERY = 0.5 -- seconds between rate refreshes (it changes with buffs and gear)

function Regen:Init(parent)
    self.strip = FrogLib.FSR.NewStrip(parent, 0.5)

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
    -- Under the gauge (and its gold rim in the framed style), above the big number.
    strip:Place(block.gauge.bar, db.style == "framed" and 5 or 2, 1)
    strip:SetColor(r + (1 - r) * 0.45, g + (1 - g) * 0.45, b + (1 - b) * 0.45, 0.95)
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

-- UNIT_SPELLCAST_SUCCEEDED. A secret spell ID can't be looked up; then a drop in your mana a moment
-- before or after the cast (when your mana isn't secret) starts the timer instead.
function Regen:OnCast(spellID)
    self.fsr:OnCast(spellID)
end

-- Every change to your mana the gauges see, with values that may be secret.
function Regen:OnMana(value, max)
    self.fsr:OnMana(value, max)
end

function Regen:UpdateRate()
    local settings, rate = ns.db.regen, self.rate
    if not (settings.rate and self.block and GetManaRegen) then
        rate:Hide()
        return
    end
    local ok, base, casting = pcall(GetManaRegen)
    -- No and/or or nil tests on the rates themselves: either may be secret.
    local inRule = self:InRule()
    local perSecond
    if inRule then perSecond = casting else perSecond = base end
    if not ok or (not issecret(perSecond) and type(perSecond) ~= "number") then
        rate:Hide()
        return
    end
    rate:Show()
    if settings.per == 5 and not issecret(perSecond) then
        rate:SetFormattedText("+%d mp5", math.floor(perSecond * 5 + 0.5))
    else
        -- Per second; also the fallback for mp5 while the rate is secret (no arithmetic on it).
        pcall(rate.SetFormattedText, rate, "+%.1f/s", perSecond)
    end
    if inRule then
        rate:SetTextColor(0.6, 0.6, 0.6)
    else
        local color = self.color or { 1, 1, 1 }
        rate:SetTextColor(color[1], color[2], color[3])
    end
end

-- Every frame (from the player bar's poller).
function Regen:Update(elapsed)
    local strip = self.strip
    if not strip then return end
    local settings = ns.db.regen
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
    strip:SetLeft(left and settings.rule and self.block and left or nil)

    self.since = self.since + (elapsed or 0)
    if self.since >= RATE_EVERY then
        self.since = 0
        self:UpdateRate()
    end
end
