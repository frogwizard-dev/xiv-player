local _, ns = ...
local Cast = {}
ns.Cast = Cast

-- Your cast bar, FFXIV-style: a gauge above the player bar with the spell name over its left
-- end and the time left over its right. Cast data can be secret, so the fill runs on the
-- engine's timer (SetTimerDuration) and the text only goes through SetText/SetFormattedText.

local ELAPSED = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.ElapsedTime
local REMAINING = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
local IMMEDIATE = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
local issecret = issecretvalue or function() return false end

local EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_UPDATE",
    "UNIT_SPELLCAST_EMPOWER_STOP",
}
local STARTS = {
    UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_CHANNEL_START = true, UNIT_SPELLCAST_EMPOWER_START = true,
}
local CAST_COLOR = { 1, 0.78, 0.36 }
local FAIL_COLOR = { 0.85, 0.2, 0.15 }

------------------------------------------------------------------------------
-- Blizzard's own cast bar
------------------------------------------------------------------------------

-- Hidden by moving it under a hidden frame, as EllesmereUI does (and through EllesmereUI's
-- shared switch when it's loaded, so the two agree on who hides it). Not while in combat or
-- Edit Mode: re-parenting there runs Blizzard's layout code under our taint. Edit Mode also
-- puts it back when it lays frames out, so it's hidden again afterwards.
local hiddenParent, origParent, suppressed, hooked

local function SuppressBlizzard(on)
    if _G.EllesmereUI and EllesmereUI.SetPlayerCastBarSuppressed then
        EllesmereUI.SetPlayerCastBarSuppressed("XIVPlayer", on)
        return
    end
    local bar = PlayerCastingBarFrame
    if not bar then return end
    suppressed = on
    if InCombatLockdown() or (EditModeManagerFrame and EditModeManagerFrame:IsShown()) then
        Cast.pending = true
        return
    end
    Cast.pending = nil
    if on then
        if not hiddenParent then
            hiddenParent = CreateFrame("Frame")
            hiddenParent:Hide()
        end
        if bar:GetParent() ~= hiddenParent then
            origParent = bar:GetParent()
            bar:SetParent(hiddenParent)
        end
        if not hooked then
            hooked = true
            hooksecurefunc(bar, "SetParent", function(self, parent)
                if suppressed and parent ~= hiddenParent then
                    C_Timer.After(0, function() SuppressBlizzard(suppressed) end)
                end
            end)
        end
    elseif origParent and bar:GetParent() == hiddenParent then
        bar:SetParent(origParent)
    end
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

    -- Remaining time: the timer object can be secret, so it goes straight into the text.
    g.bar:SetScript("OnUpdate", function(bar)
        if not ns.db.cast.showTime or self.holdUntil or not self.casting then
            self.time:SetText("")
            return
        end
        local ok, duration = pcall(bar.GetTimerDuration, bar)
        if ok and duration then
            pcall(self.time.SetFormattedText, self.time, "%.1f", duration:GetRemainingDuration())
        end
    end)

    for _, event in ipairs(EVENTS) do
        pcall(f.RegisterUnitEvent, f, event, "player")
    end
    pcall(f.RegisterUnitEvent, f, "UNIT_SPELLCAST_SENT", "player")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            if self.pending then SuppressBlizzard(ns.db.cast.enabled and ns.db.cast.hideBlizzard) end
        elseif event == "UNIT_SPELLCAST_SENT" then
            self.sentAt = GetTime()
        else
            if STARTS[event] then self:MeasureLatency() end
            self:Update(event)
        end
    end)
    if EventRegistry then
        EventRegistry:RegisterCallback("EditMode.Exit", function()
            if suppressed then SuppressBlizzard(true) end
        end)
    end
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
    if not ns.db.cast.showLatency or not self.latency or not startMS or not endMS
        or issecret(startMS) or issecret(endMS) then
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
    local show = ns.db.cast.showIcon and texture ~= nil
    if show then show = pcall(self.icon.SetTexture, self.icon, texture) end
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

function Cast:Update(event)
    local cfg, f, bar = ns.db.cast, self.frame, self.gauge.bar
    if not cfg.enabled then
        f:Hide()
        return
    end
    -- Unlocked: a sample cast to place and style against.
    if not ns.db.locked then
        self.casting, self.holdUntil = false, nil
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0.6)
        self:Paint(unpack(CAST_COLOR))
        self.name:SetText("Spell name")
        self.time:SetText(cfg.showTime and "1.4" or "")
        -- A sample latency share and icon, so both can be judged while placing the bar.
        self.latency = 0.15
        self:ShowLatency(false, 0, 1000)
        self:ShowIcon(134400)
        f:Show()
        return
    end

    local _, text, texture, startMS, endMS = UnitCastingInfo("player")
    local duration, direction, channel
    if text then
        duration, direction = UnitCastingDuration and UnitCastingDuration("player"), ELAPSED
    else
        _, text, texture, startMS, endMS = UnitChannelInfo("player")
        if text then
            duration, direction, channel = UnitChannelDuration and UnitChannelDuration("player"), REMAINING, true
        end
    end

    if text and duration then
        self.casting, self.holdUntil = true, nil
        pcall(bar.SetTimerDuration, bar, duration, IMMEDIATE, direction)
        self.name:SetText(text)
        self:Paint(unpack(CAST_COLOR))
        self:ShowLatency(channel, startMS, endMS)
        self:ShowIcon(texture)
        f:Show()
    elseif (event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED") and self.casting then
        -- Hold the bar briefly in red so an interrupt is noticed.
        self.casting = false
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(1)
        self:Paint(unpack(FAIL_COLOR))
        self.lag:Hide()
        self.name:SetText(event == "UNIT_SPELLCAST_FAILED" and FAILED or INTERRUPTED)
        local hold = GetTime() + 0.8
        self.holdUntil = hold
        C_Timer.After(0.8, function()
            if self.holdUntil == hold then
                self.holdUntil = nil
                f:Hide()
            end
        end)
    elseif not self.holdUntil then
        self.casting = false
        f:Hide()
    end
end
