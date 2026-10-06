local ADDON, ns = ...
local UI = ns.UI
local issecret = FrogLib.issecret
local Color, Unit, Secure = FrogLib.Color, FrogLib.Unit, FrogLib.Secure

ns.defaults = {
    locked = true,
    point = { "BOTTOM", "UIParent", "BOTTOM", 0, 230 },
    scale = 1,
    width = 220,   -- per gauge
    height = 8,
    -- Between the HP and MP gauges. Up to the width of the screen, so the two can sit either
    -- side of the action bars (the bar is centred on its position, so they spread out evenly).
    spacing = 28,
    style = "framed", -- "framed": FFXIV's gold-rimmed parameter bar; "line": thin glowing line
    texture = "Interface\\Buttons\\WHITE8X8",
    colorMode = "xiv", -- "xiv": FFXIV colours; "wow": WoW's power colours
    healthColor = { r = 0.45, g = 0.80, b = 0.30 },
    -- Michroma, bundled: a wide, open face like FFXIV's gauge numbers.
    font = "Interface\\AddOns\\XIVPlayer\\Fonts\\Michroma.ttf",
    outline = "OUTLINE",
    labelSize = 11,
    numberSize = 22,
    -- Number templates: value, max, percent (percent.1 for a decimal).
    healthText = "value",
    powerText = "value",
    fade = false,     -- dim out of combat
    fadeAlpha = 0.4,
    clicks = true,    -- left-click the bar to target yourself, right-click for your menu
    hidePlayerFrame = false, -- hide Blizzard's player frame (its pet and totem frames stay)
    absorb = true,    -- shields drawn on the HP gauge as a striped fill
    absorbText = true, -- and "+X" after the HP number, in the shield colour
    absorbColor = { r = 1, g = 1, b = 1 },
    -- While your gauge shows another resource (a druid's bear or cat form, Shadow, Elemental),
    -- a third gauge to its right shows your mana.
    shiftMana = true,
    -- Above the gauges: buffs over HP (a whitelist, empty until you add some), debuffs over MP
    -- (all of them except a blacklist).
    buffs = { enabled = true, list = {}, size = 24, spacing = 2, offsetY = 4, showTimer = true },
    -- maxMinutes: hide debuffs lasting longer than this (0 = off); see Auras.lua for why.
    debuffs = { enabled = true, blacklist = {}, max = 16, size = 24, spacing = 2, offsetY = 4, showTimer = true,
        maxMinutes = 0 },
    -- Your cast bar, centred above the player bar (x/y from the bar's top edge).
    -- Latency: the end of the cast already safe to cast through, shaded. Icon: left of the bar.
    cast = { enabled = true, hideBlizzard = true, width = 260, height = 6, x = 0, y = 70, showTime = true,
        showLatency = true, latencyColor = { r = 0.9, g = 0.15, b = 0.1 }, showIcon = false, iconSize = 24 },
    -- Mana regen on the gauge showing your mana (Regen.lua): the live rate after the number
    -- (per second, or per 5 seconds: per = 5), and the five-second rule as a strip under it.
    regen = { rate = true, rule = true, per = 1 },
    -- Swing timers (Swing.lua), under the player bar (x/y from its bottom edge). Off until
    -- turned on: casters have no use for them.
    swing = { enabled = false, hideBlizzard = true, show = "combat", main = true, off = true, ranged = true,
        width = 220, height = 4, x = 0, y = -10, showLabel = true, showTime = true, dimOutOfRange = true,
        colors = { main = { r = 0.95, g = 0.80, b = 0.40 }, off = { r = 0.95, g = 0.58, b = 0.30 },
            ranged = { r = 0.45, g = 0.82, b = 0.62 } } },
}

-- FFXIV names: HP, MP, and TP for the energy-like resource. Colours match its gauges.
local POWER = {
    MANA = { "MP", { 0.90, 0.45, 0.85 } },
    ENERGY = { "TP", { 0.95, 0.80, 0.40 } },
    RAGE = { "RP", { 0.95, 0.38, 0.32 } },
    FOCUS = { "FP", { 0.95, 0.62, 0.32 } },
    RUNIC_POWER = { "RP", { 0.35, 0.80, 0.95 } },
}

local MANA = Enum.PowerType and Enum.PowerType.Mana or 0
-- Power is polled every frame, as Blizzard's player frame does; values the game keeps secret
-- can't be compared with the last ones, so those are re-sent at most this often (seconds).
local SECRET_POLL = 0.05
-- The old top of the gap setting: a forms' mana gauge stays at most this far right of MP.
local OLD_MAX_GAP = 120
-- Classes whose gauge can show something other than the mana they still have underneath.
local SHIFT_MANA_CLASSES = { DRUID = true, PRIEST = true, SHAMAN = true }

local function PowerColor(token, db)
    local info = POWER[token]
    local r, g, b = 0.7, 0.7, 0.7
    if info then r, g, b = unpack(info[2]) end
    if db.colorMode == "wow" then
        local wr, wg, wb = Color.PowerToken(token)
        if wr then r, g, b = wr, wg, wb end
    end
    return r, g, b
end

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

------------------------------------------------------------------------------
-- Gauge blocks: gauge on top, small label and large number underneath (FFXIV's layout)
------------------------------------------------------------------------------

local function Block(parent, label)
    local b = { gauge = ns.CreateGauge(parent) }
    b.label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetText(label)
    b.label:SetShadowOffset(1, -1)
    b.number = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.number:SetShadowOffset(1, -1)
    b.number:SetPoint("BOTTOMLEFT", b.label, "BOTTOMRIGHT", 5, -2)
    return b
end

local function StyleBlock(b, db)
    b.gauge:SetStyle(db.style)
    b.gauge:SetHeight(db.height)
    b.gauge:SetTexture(db.texture)
    b.gauge.bar:SetWidth(db.width)
    ns.Media:SetFont(b.label, db.font, db.labelSize, db.outline)
    ns.Media:SetFont(b.number, db.font, db.numberSize, db.outline)
    -- The label sits low so its baseline lines up with the big number beside it; the gold
    -- rim of the framed style needs a little more clearance.
    local clearance = db.style == "framed" and 7 or 4
    b.label:ClearAllPoints()
    b.label:SetPoint("TOPLEFT", b.gauge.bar, "BOTTOMLEFT", 2, -clearance - db.numberSize + db.labelSize)
end

local function Tint(b, r, g, bl)
    b.gauge:SetColor(r, g, bl)
    -- Text in a light version of the gauge colour, as FFXIV does.
    b.label:SetTextColor(Color.Lighten(r, g, bl, 0.55))
    b.number:SetTextColor(1, 1, 1)
end

-- The label and number belong to the bar's frame, not the gauge, so each is shown on its own.
local function ShowBlock(b, shown)
    b.gauge.bar:SetShown(shown)
    b.label:SetShown(shown)
    b.number:SetShown(shown)
end

------------------------------------------------------------------------------
-- The bar
------------------------------------------------------------------------------

local Player = {}
ns.Player = Player

function Player:Init()
    local f = CreateFrame("Frame", "XIVPlayerFrame", UIParent)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        local p, _, rp, x, y = frame:GetPoint()
        ns.db.point = { p, "UIParent", rp, x, y }
    end)
    f.unlockTint = f:CreateTexture(nil, "BACKGROUND")
    f.unlockTint:SetPoint("TOPLEFT", -6, 6)
    f.unlockTint:SetPoint("BOTTOMRIGHT", 6, -6)
    f.unlockTint:SetColorTexture(0.3, 0.6, 1, 0.2)
    self.frame = f

    self.health = Block(f, "HP")
    self.power = Block(f, "MP")
    self.mana = Block(f, "MP")
    ShowBlock(self.mana, false)
    self.health.gauge.bar:SetPoint("TOPLEFT")
    self.health.gauge:EnableAbsorb()
    local shield = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    shield:SetShadowOffset(1, -1)
    shield:SetPoint("BOTTOMLEFT", self.health.number, "BOTTOMRIGHT", 6, 1)
    self.health.shield = shield
    self.last = { power = {}, mana = {} }
    ns.Regen:Init(f)
    ns.Cast:Init()
    ns.Swing:Init()

    f:RegisterUnitEvent("UNIT_HEALTH", "player")
    f:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
    f:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", "player")
    f:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
    pcall(f.RegisterUnitEvent, f, "UNIT_POWER_FREQUENT", "player")
    f:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    f:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_ABSORB_AMOUNT_CHANGED" then
            self:UpdateHealth()
        elseif event == "UNIT_POWER_FREQUENT" or event == "UNIT_POWER_UPDATE" then
            self:PollPower(true)
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            ns.Regen:OnCast((select(3, ...)))
        elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
            if event == "PLAYER_REGEN_ENABLED" and self.clicksPending then self:SetupClicks() end
            self:UpdateFade(event == "PLAYER_REGEN_DISABLED")
        else
            self:UpdatePower(true)
            self:UpdateHealth(true)
        end
    end)

    -- Real time: your power is read every frame, as Blizzard's own player frame reads it, rather
    -- than only when UNIT_POWER_UPDATE comes (which the game sends far less often, so mana
    -- regen showed in steps). The gauge eases to each new value.
    local poller = CreateFrame("Frame", nil, f)
    poller:SetScript("OnUpdate", function(_, elapsed)
        self:PollPower()
        ns.Regen:Update(elapsed)
    end)
    self:Apply()
end

function Player:Apply()
    local db = ns.db
    local f = self.frame
    f:SetScale(db.scale)
    f:ClearAllPoints()
    f:SetPoint(db.point[1], UIParent, db.point[3], db.point[4], db.point[5])
    f:SetSize(db.width * 2 + db.spacing, db.height + db.numberSize + 8)
    f:EnableMouse(not db.locked)
    f.unlockTint:SetShown(not db.locked)

    StyleBlock(self.health, db)
    StyleBlock(self.power, db)
    StyleBlock(self.mana, db)
    ns.Media:SetFont(self.health.shield, db.font, math.max(db.labelSize + 2, math.floor(db.numberSize * 0.6)), db.outline)
    self.power.gauge.bar:ClearAllPoints()
    self.power.gauge.bar:SetPoint("LEFT", self.health.gauge.bar, "RIGHT", db.spacing, 0)
    -- Outside the frame's bounds on purpose: growing the frame when you shift would move the
    -- HP and power gauges too, and the click button can't be resized in combat. With the gauges
    -- spread far apart it stays near MP rather than drifting off the screen.
    self.mana.gauge.bar:ClearAllPoints()
    self.mana.gauge.bar:SetPoint("LEFT", self.power.gauge.bar, "RIGHT", math.min(db.spacing, OLD_MAX_GAP), 0)

    self:SetupClicks()
    -- The cast bar is kept out too when it's locked under the player frame (Edit Mode), so
    -- hiding the frame alone doesn't take Blizzard's cast bar with it.
    FrogLib.Hider.Set(ADDON, "PlayerFrame", db.hidePlayerFrame,
        { keep = { "PetFrame", "TotemFrame", "PlayerCastingBarFrame" } })
    ns.Auras:Apply()
    ns.Cast:Apply()
    ns.Swing:Apply()
    self.manaBlock = false -- re-attach the regen display, in the new style
    self:UpdateHealth(true)
    self:UpdatePower(true)
    self:UpdateFade()
    -- Font files load on first use; text set in that moment can render blank.
    C_Timer.After(0.1, function()
        self:UpdateHealth(true)
        self:UpdatePower(true)
    end)
end

-- Clicks: a secure button over the bar targets you on left-click and opens your unit menu on
-- right-click (FrogLib.Secure's). It copies the bar's place, scale and size instead of anchoring
-- to it (anything a secure frame is anchored to becomes protected). Two buttons, one over each
-- gauge, sharing one menu button, so with the gauges spread either side of the action bars the
-- space between them (the action bars) still takes its own clicks.

-- How far across and up a frame its anchor point lies (0 = left/bottom, 1 = right/top).
local function PointFractions(point)
    local fx = point:find("LEFT") and 0 or point:find("RIGHT") and 1 or 0.5
    local fy = point:find("BOTTOM") and 0 or point:find("TOP") and 1 or 0.5
    return fx, fy
end

-- Places button b over the part of the bar from `left` to `left + w` (its full height), with
-- the bar's own anchor point and offsets, so it follows the bar through UI scale changes.
local function PlaceOver(b, db, frameW, frameH, left, w)
    local p = db.point
    local fx = PointFractions(p[1])
    b:SetScale(db.scale)
    b:ClearAllPoints()
    b:SetPoint(p[1], UIParent, p[3], p[4] + left + w * fx - frameW * fx, p[5])
    b:SetSize(w, frameH)
    b:SetHitRectInsets(-4, -4, -6, -4)
end

-- Secure frames can only be placed and shown out of combat; changes made in combat wait.
function Player:SetupClicks()
    if InCombatLockdown() then
        self.clicksPending = true
        return
    end
    self.clicksPending = nil
    local db = ns.db
    if not self.click then
        self.click = Secure.UnitButton("XIVPlayerClick", "player")
        self.clickPower = Secure.UnitButton("XIVPlayerClickPower", "player", { menu = "XIVPlayerClickMenu" })
    end
    local W, H = self.frame:GetSize()
    -- Each half reaches into the gap by up to 16, so at the usual gap they meet in the middle
    -- and cover the whole bar, as the single button did before.
    local reach = math.min(db.spacing / 2, 16)
    PlaceOver(self.click, db, W, H, 0, db.width + reach)
    PlaceOver(self.clickPower, db, W, H, db.width + db.spacing - reach, db.width + reach)
    -- Off while unlocked, so the bar can be dragged.
    local shown = db.clicks and db.locked
    self.click:SetShown(shown)
    self.clickPower:SetShown(shown)
end

function Player:UpdateHealth(instant)
    local db = ns.db
    local value, max = UnitHealth("player"), UnitHealthMax("player")
    self.health.gauge:SetValues(value, max, instant)
    -- The shield total can be secret; it only ever goes into the gauge's status bars.
    local g = self.health.gauge
    local shield = (UnitGetTotalAbsorbs and UnitGetTotalAbsorbs("player")) or 0
    local ac = db.absorbColor
    g:ShowAbsorb(db.absorb)
    if db.absorb then
        g:SetAbsorb(shield, max)
        g:SetAbsorbColor(ac.r, ac.g, ac.b)
    end
    -- "+X" only while there's a shield. A secret amount can't be compared with 0, but
    -- TruncateWhenZero writes nothing for zero and GetText is then nil, and testing that is allowed.
    local fs = self.health.shield
    fs:SetText("")
    if db.absorbText and C_StringUtil and C_StringUtil.TruncateWhenZero then
        fs:SetText(C_StringUtil.TruncateWhenZero(shield))
        if fs:GetText() then fs:SetFormattedText("+%d", shield) end
    end
    fs:SetTextColor(ac.r, ac.g, ac.b)
    local c = db.healthColor
    Tint(self.health, c.r, c.g, c.b)
    -- The values may be secret: FrogLib's template only hands them to SetFormattedText.
    UI.SetTemplateText(self.health.number, db.healthText,
        { value = value, max = max, percent = Unit.HealthPercent("player") })
end

-- A block's gauge and number from your power of type pType; instant: no easing (a change of
-- form or a reload). The values may be secret: they only go to the gauge and the text.
local function PaintPower(b, pType, value, max, instant)
    b.gauge:SetValues(value, max, instant)
    UI.SetTemplateText(b.number, ns.db.powerText,
        { value = value, max = max, percent = Unit.PowerPercent("player", pType) })
    if pType == MANA then ns.Regen:OnMana(value, max) end
end

function Player:UpdatePower(instant)
    local db = ns.db
    local pType, token = UnitPowerType("player")
    self.pType = pType
    local value, max = UnitPower("player", pType), UnitPowerMax("player", pType)
    local info = POWER[token]
    self.power.label:SetText(info and info[1] or (token and token:sub(1, 2)) or "PW")
    Tint(self.power, PowerColor(token, db))
    PaintPower(self.power, pType, value, max, instant)
    self.last.power = {}
    self:UpdateMana(pType, instant)
    -- The regen display goes on whichever gauge shows your mana.
    local block, r, g, b = nil, nil, nil, nil
    if pType == MANA then
        block = self.power
        r, g, b = PowerColor(token, db)
    elseif self.manaShown then
        block = self.mana
        r, g, b = PowerColor("MANA", db)
    end
    if block ~= self.manaBlock then
        self.manaBlock = block
        ns.Regen:Attach(block, r, g, b)
    end
end

-- Your mana while the main gauge shows something else (bear or cat form, Shadow, Elemental).
function Player:UpdateMana(pType, instant)
    local db = ns.db
    local value, max = UnitPower("player", MANA), UnitPowerMax("player", MANA)
    local _, class = UnitClass("player")
    -- A secret max can't be compared; only these classes get here, and they all have mana.
    local shown = db.shiftMana and pType ~= MANA and SHIFT_MANA_CLASSES[class]
        and (issecret(max) or max > 0) or false
    if shown ~= self.manaShown then
        self.manaShown = shown
        ShowBlock(self.mana, shown)
        instant = true -- no sliding up from empty when it appears
    end
    self.last.mana = {}
    if not shown then return end
    Tint(self.mana, PowerColor("MANA", db))
    PaintPower(self.mana, MANA, value, max, instant)
end

-- One block, if its power changed (or, while the game keeps it secret, if `due`).
function Player:PollBlock(b, pType, last, force, due)
    local value, max = UnitPower("player", pType), UnitPowerMax("player", pType)
    if issecret(value) or issecret(max) then
        if not (force or due) then return end
        last.value, last.max = nil, nil
    else
        if not force and last.value == value and last.max == max then return end
        last.value, last.max = value, max
    end
    PaintPower(b, pType, value, max)
end

-- Every frame, and on UNIT_POWER_FREQUENT (force).
function Player:PollPower(force)
    if self.pType == nil then return end
    local now = GetTime()
    local due = now - (self.polledAt or 0) >= SECRET_POLL
    if due then self.polledAt = now end
    self:PollBlock(self.power, self.pType, self.last.power, force, due)
    if self.manaShown then self:PollBlock(self.mana, MANA, self.last.mana, force, due) end
end

-- inCombat comes from the combat events: while PLAYER_REGEN_DISABLED is being handled,
-- InCombatLockdown() still says false, so asking it there left the bar dimmed all fight.
function Player:UpdateFade(inCombat)
    local db = ns.db
    if inCombat == nil then inCombat = InCombatLockdown() or FrogLib.Safe(UnitAffectingCombat("player")) end
    local dim = db.fade and db.locked and not inCombat
    self.frame:SetAlpha(dim and db.fadeAlpha or 1)
end

------------------------------------------------------------------------------
-- Settings window
------------------------------------------------------------------------------

local COLOR_MODES = UI.Options("xiv", "FFXIV colours", "wow", "WoW power colours")
local STYLES = UI.Options("framed", "Framed (gold rim)", "line", "Line (thin glow)")
local REGEN_UNITS = UI.Options(1, "Per second (+7.5/s)", 5, "Per 5 seconds (+37 mp5)")

-- The widest gap that still fits both gauges on the screen, at the bar's scale.
local function MaxGap()
    local db = ns.db
    local screen = UIParent:GetWidth() / db.scale
    return math.max(OLD_MAX_GAP, math.floor((screen - db.width * 2 - 8) / 2) * 2)
end

-- Keeps the bar's height and puts its middle at the middle of the screen.
function Player:CentreHorizontally()
    local db, f = ns.db, self.frame
    local bottom = f:GetBottom()
    if not bottom then return end
    db.point = { "BOTTOM", "UIParent", "BOTTOM", 0, math.floor(bottom + 0.5) }
    ns.Refresh()
end

local function BuildLayout(p)
    local db = ns.db
    local place = UI.Placer()
    place(UI.Checkbox(p, "Unlock to move (drag the bar)",
        function() return not db.locked end, function(v) db.locked = not v end), 28)
    place(UI.Checkbox(p, "Click to target yourself, right-click for your menu",
        function() return db.clicks end, function(v) db.clicks = v end), 28)
    place(UI.Checkbox(p, "Hide Blizzard's player frame",
        function() return db.hidePlayerFrame end, function(v) db.hidePlayerFrame = v end), 34)
    place(UI.Stepper(p, "Scale", 0.5, 2, 0.05, function() return db.scale end, function(v) db.scale = v end, "%.2f"), 26)
    place(UI.Stepper(p, "Gauge width", 80, 500, 10, function() return db.width end, function(v) db.width = v end), 26)
    place(UI.Stepper(p, "Gauge height", 2, 20, 1, function() return db.height end, function(v) db.height = v end), 26)
    -- Up to the whole screen: the gauges can sit either side of the action bars.
    place(UI.Slider(p, "Gap between gauges", 0, 120, 2, function() return db.spacing end,
        function(v) db.spacing = v end, MaxGap), 28)
    local centre = UI.Button(p, "Centre the bar across the screen", 230)
    place(centre, 26, 150)
    centre:SetScript("OnClick", function() Player:CentreHorizontally() end)
    place(UI.Help(p, "A wide gap puts HP and MP either side of your action bars; centre the bar to "
        .. "spread them evenly. Shift-click - or + for bigger steps.", 400), 30)
    place(UI.Dropdown(p, "Gauge style", STYLES, function() return db.style end,
        function(v) db.style = v end), 30)
    place(UI.Dropdown(p, "Bar texture", function() return ns.Media:List("statusbar") end,
        function() return db.texture end, function(v) db.texture = v end), 30)
    place(UI.Dropdown(p, "Power colours", COLOR_MODES, function() return db.colorMode end,
        function(v) db.colorMode = v end), 30)
    place(UI.Checkbox(p, "Show my mana in forms (bear, cat, Shadow, Elemental)",
        function() return db.shiftMana end, function(v) db.shiftMana = v end), 30)
    place(UI.ColorSwatch(p, "HP colour", function() return db.healthColor end,
        function(r, g, b) db.healthColor = { r = r, g = g, b = b } end), 30)
    place(UI.Checkbox(p, "Show shields (absorbs) on the HP gauge",
        function() return db.absorb end, function(v) db.absorb = v end), 26)
    place(UI.Checkbox(p, "Show the shield as \"+X\" after the HP number",
        function() return db.absorbText end, function(v) db.absorbText = v end), 28)
    place(UI.ColorSwatch(p, "Shield colour", function() return db.absorbColor end,
        function(r, g, b) db.absorbColor = { r = r, g = g, b = b } end), 36)
    place(UI.Checkbox(p, "Dim out of combat",
        function() return db.fade end, function(v) db.fade = v end), 28)
    place(UI.Stepper(p, "Dimmed opacity", 0, 1, 0.05, function() return db.fadeAlpha end,
        function(v) db.fadeAlpha = v end, "%.2f"), 26)
end

local function BuildText(p)
    local db = ns.db
    local place = UI.Placer()
    place(UI.TextBox(p, "HP number", function() return db.healthText end, function(v) db.healthText = v end), 28)
    place(UI.TextBox(p, "Power number", function() return db.powerText end, function(v) db.powerText = v end), 30)
    place(UI.Help(p, "Words: |cffffd100value|r, |cffffd100max|r, |cffffd100percent|r (|cffffd100percent.1|r "
        .. "for a decimal). For example: value / max", 400), 36, 4)
    place(UI.Dropdown(p, "Font", function() return ns.Media:List("font") end,
        function() return db.font end, function(v) db.font = v end), 30)
    place(UI.Dropdown(p, "Font outline", UI.OUTLINES, function() return db.outline end,
        function(v) db.outline = v end), 30)
    place(UI.Stepper(p, "Label size (HP/MP)", 8, 24, 1, function() return db.labelSize end,
        function(v) db.labelSize = v end), 26)
    place(UI.Stepper(p, "Number size", 10, 48, 1, function() return db.numberSize end,
        function(v) db.numberSize = v end), 34)

    local regen = db.regen
    place(UI.Label(p, "Mana regen"), 22)
    place(UI.Checkbox(p, "Show my mana regen after the MP number (live)",
        function() return regen.rate end, function(v) regen.rate = v end), 28)
    place(UI.Dropdown(p, "Regen shown", REGEN_UNITS, function() return regen.per end,
        function(v) regen.per = v end), 30)
    place(UI.Checkbox(p, "Show the five-second rule under the MP gauge",
        function() return regen.rule end, function(v) regen.rule = v end), 28)
    place(UI.Help(p, "After you spend mana, regen stops for five seconds; a strip under the gauge fills "
        .. "until it starts again. The rate is the game's own (the character sheet's Mana Regen).", 400), 36)
end

local function BuildCast(p)
    local cfg = ns.db.cast
    local place = UI.Placer()
    place(UI.Checkbox(p, "Show my cast bar",
        function() return cfg.enabled end, function(v) cfg.enabled = v end), 28)
    place(UI.Checkbox(p, "Hide Blizzard's cast bar",
        function() return cfg.hideBlizzard end, function(v) cfg.hideBlizzard = v end), 28)
    place(UI.Checkbox(p, "Show time left",
        function() return cfg.showTime end, function(v) cfg.showTime = v end), 28)
    place(UI.Checkbox(p, "Show latency (shaded end of the bar)",
        function() return cfg.showLatency end, function(v) cfg.showLatency = v end), 28)
    place(UI.ColorSwatch(p, "Latency colour", function() return cfg.latencyColor end,
        function(r, g, b) cfg.latencyColor = { r = r, g = g, b = b } end), 30)
    place(UI.Checkbox(p, "Show the spell icon",
        function() return cfg.showIcon end, function(v) cfg.showIcon = v end), 28)
    place(UI.Stepper(p, "Icon size", 10, 64, 1, function() return cfg.iconSize end,
        function(v) cfg.iconSize = v end), 34)
    place(UI.Stepper(p, "Width", 80, 600, 10, function() return cfg.width end, function(v) cfg.width = v end), 26)
    place(UI.Stepper(p, "Height", 2, 20, 1, function() return cfg.height end, function(v) cfg.height = v end), 26)
    place(UI.Stepper(p, "Move left / right", -600, 600, 2, function() return cfg.x end, function(v) cfg.x = v end), 26)
    place(UI.Stepper(p, "Move up / down", -300, 600, 2, function() return cfg.y end, function(v) cfg.y = v end), 34)
    place(UI.Help(p, "It uses the gauge style, texture and font from the other tabs. Unlock the bar "
        .. "(Layout) to see a sample cast while you place it.", 400), 36)
end

function ns.ToggleConfig()
    if not ns.window then
        ns.window = UI.Window("XIVPlayerConfig", "XIVPlayer", 650, 660, {
            { "layout", "Layout", BuildLayout },
            { "text", "Text", BuildText },
            { "cast", "Cast bar", BuildCast },
            { "swing", "Swing timer", ns.Swing.BuildPage },
            { "buffs", "Buffs", function(p) ns.Auras.BuildPage(p, "buffs") end },
            { "debuffs", "Debuffs", function(p) ns.Auras.BuildPage(p, "debuffs") end },
        })
        return
    end
    ns.window:SetShown(not ns.window:IsShown())
end

------------------------------------------------------------------------------
-- Startup
------------------------------------------------------------------------------

function ns.Refresh()
    Player:Apply()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        XIVPlayerDB = XIVPlayerDB or {}
        local db = XIVPlayerDB
        -- 0.1 -> 0.2: framed style, Michroma and new sizes, where the old defaults were untouched.
        if not db.version then
            local old = { height = 5, width = 200, labelSize = 12, numberSize = 24,
                font = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF" }
            for k, v in pairs(old) do
                if db[k] == v then db[k] = nil end
            end
            if db.healthColor and db.healthColor.r == 0.55 and db.healthColor.g == 0.85 then db.healthColor = nil end
            db.version = 2
        end
        -- Krona One was bundled briefly and then removed; move anyone using it to Michroma.
        if type(db.font) == "string" and db.font:find("KronaOne", 1, true) then db.font = nil end
        CopyDefaults(ns.defaults, db)
        ns.db = db
    elseif event == "PLAYER_LOGIN" then
        Player:Init()
    end
end)

SLASH_XIVPLAYER1 = "/xivp"
SlashCmdList.XIVPLAYER = ns.ToggleConfig
function XIVPlayer_OnCompartmentClick() ns.ToggleConfig() end

-- Its entry in the game's Options > AddOns list (Options.lua).
FrogLib.Options.Add("XIVPlayer", ns, {
    open = function()
        if not (ns.window and ns.window:IsShown()) then ns.ToggleConfig() end
    end,
    commands = { { "/xivp", "open or close the settings" } },
})
