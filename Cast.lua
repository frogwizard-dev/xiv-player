local ADDON, ns = ...
local Cast = {}
ns.Cast = Cast

-- Your cast bar, FFXIV-style: a gauge above the player bar with the spell name over its left
-- end and the time left over its right. Cast data can be secret, so the fill runs on the
-- engine's timer (SetTimerDuration) and the text only goes through SetText/SetFormattedText.
-- Reading the cast, and when the bar shows (the cast, an interrupt held in red, a sample while
-- unlocked), are FrogLib's (FrogLib.Cast, shared with the target bars); the look is ours.

local Lib = FrogLib.Cast
local issecret = FrogLib.issecret

local STARTS = {
    UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_CHANNEL_START = true, UNIT_SPELLCAST_EMPOWER_START = true,
}
local CAST_COLOR = { 1, 0.78, 0.36 }
local FAIL_COLOR = { 0.85, 0.2, 0.15 }

------------------------------------------------------------------------------
-- Blizzard's own cast bar
------------------------------------------------------------------------------

-- Hidden by FrogLib's Hider (a hidden parent out of combat, opacity 0 at all times), or through
-- EllesmereUI's shared switch when it's loaded, so the two agree on who hides it.
-- There are two: with the gamepad interface on, the game shows GamepadPlayerCastingBarFrame
-- and PlayerCastingBarFrame ignores your casts, so hiding only the usual one did nothing for
-- gamepad players. The usual one is also re-parented by Blizzard's bottom-of-screen layout
-- whenever that lays out, which in combat put it back on screen until the fight ended; the
-- opacity layer now covers that.
local function SuppressBlizzard(on)
    if _G.EllesmereUI and EllesmereUI.SetPlayerCastBarSuppressed then
        EllesmereUI.SetPlayerCastBarSuppressed("XIVPlayer", on)
    else
        FrogLib.Hider.Set(ADDON, "PlayerCastingBarFrame", on)
    end
    FrogLib.Hider.Set(ADDON, "GamepadPlayerCastingBarFrame", on)
end

------------------------------------------------------------------------------
-- Build and layout
------------------------------------------------------------------------------

local function Text(parent)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.9)
    return fs
end

function Cast:Init()
    -- Its own frame on UIParent, so it stays bright while the player bar is dimmed.
    local f = CreateFrame("Frame", "XIVPlayerCastBar", UIParent)
    f:SetSize(1, 1)
    self.frame = f
    local g = ns.CreateGauge(f)
    g.bar:SetPoint("BOTTOMLEFT")
    g.bar:SetPoint("BOTTOMRIGHT")
    self.gauge = g
    self.name = Text(f)
    self.name:SetPoint("BOTTOMLEFT", g.bar, "TOPLEFT", 1, 5)
    self.name:SetJustifyH("LEFT")
    self.name:SetWordWrap(false)
    self.time = Text(f)
    self.time:SetPoint("BOTTOMRIGHT", g.bar, "TOPRIGHT", -1, 5)
    self.time:SetJustifyH("RIGHT")

    -- Latency: the share of the cast your connection eats, shaded at the end the cast finishes
    -- (the right for a cast, the left for a channel, which drains). Once the fill reaches it,
    -- the next cast can already be sent.
    self.lag = g.bar:CreateTexture(nil, "OVERLAY", nil, -1)
    self.lag:Hide()

    -- The spell's icon, left of the bar, in a thin dark frame.
    self.iconBorder = f:CreateTexture(nil, "BACKGROUND")
    self.iconBorder:SetColorTexture(0, 0, 0, 0.85)
    self.icon = f:CreateTexture(nil, "ARTWORK")
    self.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    self.iconBorder:SetPoint("TOPLEFT", self.icon, -1, 1)
    self.iconBorder:SetPoint("BOTTOMRIGHT", self.icon, 1, -1)

    -- What's on the bar, as FrogLib's driver decides.
    self.driver = Lib.NewDriver({
        show = function(info) self:ShowCast(info) end,
        hold = function(event) self:ShowHold(event) end,
        sample = function() self:ShowSample() end,
        hide = function() f:Hide() end,
        refresh = function() self:Update() end, -- a hold is over
    })

    -- Remaining time: the timer object can be secret, so it goes straight into the text.
    g.bar:SetScript("OnUpdate", function(bar)
        local d = self.driver
        if d.sample then return end
        if not ns.db.cast.showTime or not d.casting then
            self.time:SetText("")
            return
        end
        Lib.ShowTime(bar, self.time)
    end)

    for _, event in ipairs(Lib.EVENTS) do
        pcall(f.RegisterUnitEvent, f, event, "player")
    end
    pcall(f.RegisterUnitEvent, f, "UNIT_SPELLCAST_SENT", "player")
    f:SetScript("OnEvent", function(_, event)
        if event == "UNIT_SPELLCAST_SENT" then
            self.sentAt = GetTime()
        else
            if STARTS[event] then self:MeasureLatency() end
            self:Update(event)
        end
    end)
    f:Hide()
end

function Cast:Apply()
    local db, cfg = ns.db, ns.db.cast
    local f, g = self.frame, self.gauge
    f:SetScale(db.scale)
    f:SetWidth(cfg.width)
    f:SetHeight(cfg.height + 20)
    f:ClearAllPoints()
    f:SetPoint("BOTTOM", ns.Player.frame, "TOP", cfg.x, cfg.y)
    g:SetStyle(db.style)
    g:SetHeight(cfg.height)
    g:SetTexture(db.texture)
    ns.Media:SetFont(self.name, db.font, db.labelSize + 1, db.outline)
    ns.Media:SetFont(self.time, db.font, db.labelSize + 1, db.outline)
    self.name:SetWidth(cfg.width * 0.75)
    local c = cfg.latencyColor
    self.lag:SetColorTexture(c.r, c.g, c.b, 0.65)
    -- The icon sits left of the bar, its bottom level with the bar's.
    self.icon:SetSize(cfg.iconSize, cfg.iconSize)
    self.icon:ClearAllPoints()
    self.icon:SetPoint("BOTTOMRIGHT", g.bar, "BOTTOMLEFT", -6, 0)
    SuppressBlizzard(cfg.enabled and cfg.hideBlizzard)
    self:Update()
end

-- How long the server took to start your cast: from sending it (UNIT_SPELLCAST_SENT) to its
-- start. Without a recent send (a cast started by the game itself), the world latency.
function Cast:MeasureLatency()
    local now = GetTime()
    if self.sentAt and now - self.sentAt < 1.5 then
        self.latency = now - self.sentAt
    else
        local _, _, home, world = GetNetStats()
        self.latency = ((world and world > 0) and world or home or 0) / 1000
    end
    self.sentAt = nil
end

-- Shades the latency share of the cast. Needs the cast's start and end times, which can be
-- secret; then it's left off.
function Cast:ShowLatency(channel, startMS, endMS)
    local lag = self.lag
    -- Secret first: a secret time mustn't be tested.
    if not ns.db.cast.showLatency or not self.latency or issecret(startMS) or issecret(endMS)
        or not startMS or not endMS then
        lag:Hide()
        return
    end
    local total = (endMS - startMS) / 1000
    -- The bar spans the frame, so its width is the setting (its measured width can lag a
    -- frame behind a resize).
    local w = total > 0 and ns.db.cast.width * math.min(self.latency / total, 1) or 0
    if w < 1 then
        lag:Hide()
        return
    end
    local side = channel and "LEFT" or "RIGHT"
    lag:ClearAllPoints()
    lag:SetPoint("TOP" .. side)
    lag:SetPoint("BOTTOM" .. side)
    lag:SetWidth(w)
    lag:Show()
end

function Cast:ShowIcon(texture)
    local show = ns.db.cast.showIcon and Lib.SetIcon(self.icon, texture) or false
    self.icon:SetShown(show)
    self.iconBorder:SetShown(show)
end

------------------------------------------------------------------------------
-- Updates
------------------------------------------------------------------------------

function Cast:Paint(r, g, b)
    self.gauge:SetColor(r, g, b)
    self.name:SetTextColor(r + (1 - r) * 0.6, g + (1 - g) * 0.6, b + (1 - b) * 0.6)
    self.time:SetTextColor(1, 0.97, 0.9)
end

function Cast:ShowCast(info)
    Lib.Fill(self.gauge.bar, info)
    self.name:SetText(info.text)
    self:Paint(unpack(CAST_COLOR))
    self:ShowLatency(info.channel, info.startMS, info.endMS)
    self:ShowIcon(info.texture)
    self.frame:Show()
end

-- Held briefly in red so an interrupt is noticed.
function Cast:ShowHold(event)
    local bar = self.gauge.bar
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    self:Paint(unpack(FAIL_COLOR))
    self.lag:Hide()
    self.name:SetText(event == "UNIT_SPELLCAST_FAILED" and FAILED or INTERRUPTED)
    self.time:SetText("")
end

-- Unlocked: a sample cast to place and style against, with a sample latency share and icon.
function Cast:ShowSample()
    local bar = self.gauge.bar
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0.6)
    self:Paint(unpack(CAST_COLOR))
    self.name:SetText("Spell name")
    self.time:SetText(ns.db.cast.showTime and "1.4" or "")
    self.latency = 0.15
    self:ShowLatency(false, 0, 1000)
    self:ShowIcon(134400)
    self.frame:Show()
end

function Cast:Update(event)
    if not ns.db.cast.enabled then
        self.frame:Hide()
        return
    end
    -- Unlocked: the sample, or a real cast of yours over it.
    self.driver:Update("player", event, not ns.db.locked)
end
