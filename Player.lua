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
    -- Between the HP and MP gauges, up to the screen's width, so the two can sit either side of the
    -- action bars (the bar is centred on its position, so they spread out evenly).
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
    -- Heals on their way to you, on the HP gauge past your health, up to where it'll be once they
    -- land (FrogLib.Predict, as Blizzard's personal resource display shows them). Teal, like its.
    heals = true,
    healColor = { r = 0.0, g = 0.66, b = 0.61 },
    -- While your gauge shows another resource (a druid's bear or cat form, Shadow, Elemental),
    -- a third gauge to its right shows your mana.
    shiftMana = true,
    -- Above the gauges: buffs over HP, debuffs over MP (all of them except a blacklist). Buffs
    -- go by mode: "whitelist" shows only `list` (in order, empty until you add some),
    -- "blacklist" every one except `blacklist`.
    buffs = { enabled = true, mode = "whitelist", list = {}, blacklist = {}, max = 32, maxMinutes = 0,
        size = 24, spacing = 2, offsetY = 4, showTimer = true },
    -- maxMinutes: hide auras lasting longer than this (0 = off); see Auras.lua for why.
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
        local wowR, wowG, wowB = Color.PowerToken(token)
        if wowR then r, g, b = wowR, wowG, wowB end
    end
    return r, g, b
end

local CopyDefaults = FrogLib.Util.CopyDefaults

------------------------------------------------------------------------------
-- Gauge blocks: gauge on top, small label and large number underneath (FFXIV's layout)
------------------------------------------------------------------------------

local function Block(parent, label)
    local block = { gauge = FrogLib.Gauge.New(parent) }
    block.label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    block.label:SetText(label)
    block.label:SetShadowOffset(1, -1)
    block.number = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    block.number:SetShadowOffset(1, -1)
    block.number:SetPoint("BOTTOMLEFT", block.label, "BOTTOMRIGHT", 5, -2)
    return block
end

-- sizes: the gauge's width and height and the label and number sizes (the pet frame has its
-- own; the player bar's are in db). The style, texture and font are always the player bar's.
local function StyleBlock(block, db, sizes)
    sizes = sizes or db
    block.gauge:SetStyle(db.style)
    block.gauge:SetHeight(sizes.height)
    block.gauge:SetTexture(db.texture)
    block.gauge.bar:SetWidth(sizes.width)
    ns.Media:SetFont(block.label, db.font, sizes.labelSize, db.outline)
    ns.Media:SetFont(block.number, db.font, sizes.numberSize, db.outline)
    -- The label sits low so its baseline lines up with the big number beside it; the gold
    -- rim of the framed style needs a little more clearance.
    local clearance = db.style == "framed" and 7 or 4
    block.label:ClearAllPoints()
    block.label:SetPoint("TOPLEFT", block.gauge.bar, "BOTTOMLEFT", 2, -clearance - sizes.numberSize + sizes.labelSize)
end

local function Tint(block, r, g, b)
    block.gauge:SetColor(r, g, b)
    -- Text in a light version of the gauge colour, as FFXIV does.
    block.label:SetTextColor(Color.Lighten(r, g, b, 0.55))
    block.number:SetTextColor(1, 1, 1)
end

-- The label and number belong to the bar's frame, not the gauge, so each is shown on its own.
local function ShowBlock(block, shown)
    block.gauge.bar:SetShown(shown)
    block.label:SetShown(shown)
    block.number:SetShown(shown)
end

-- The same blocks and colours for the pet frame (Pet.lua).
ns.Block, ns.StyleBlock, ns.Tint, ns.ShowBlock = Block, StyleBlock, Tint, ShowBlock
ns.POWER, ns.PowerColor = POWER, PowerColor

------------------------------------------------------------------------------
-- The bar
------------------------------------------------------------------------------

local Player = {}
ns.Player = Player

function Player:Init()
    local frame = CreateFrame("Frame", "XIVPlayerFrame", UIParent)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    -- Dragged while unlocked; the tint marks it (FrogLib's Mover.lua).
    FrogLib.Mover.Make(frame, { save = function(point) ns.db.point = point end, tint = 6 })
    self.frame = frame

    self.health = Block(frame, "HP")
    self.power = Block(frame, "MP")
    self.mana = Block(frame, "MP")
    ShowBlock(self.mana, false)
    self.health.gauge.bar:SetPoint("TOPLEFT")
    self.health.gauge:EnableHeal()
    self.health.gauge:EnableAbsorb()
    local shield = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    shield:SetShadowOffset(1, -1)
    shield:SetPoint("BOTTOMLEFT", self.health.number, "BOTTOMRIGHT", 6, 1)
    self.health.shield = shield
    self.last = { power = {}, mana = {} }
    ns.Regen:Init(frame)
    ns.Cast:Init()
    ns.Swing:Init()
    ns.Pet:Init()
    ns.Rest:Init(frame, self.health.gauge)

    frame:RegisterUnitEvent("UNIT_HEALTH", "player")
    frame:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
    frame:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", "player")
    pcall(frame.RegisterUnitEvent, frame, "UNIT_HEAL_PREDICTION", "player")
    frame:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
    pcall(frame.RegisterUnitEvent, frame, "UNIT_POWER_FREQUENT", "player")
    frame:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    frame:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_ABSORB_AMOUNT_CHANGED"
            or event == "UNIT_HEAL_PREDICTION" then
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

    -- Your power read every frame, as Blizzard's own player frame does: UNIT_POWER_UPDATE comes far
    -- less often, so mana regen showed in steps. The gauge eases to each new value.
    local poller = CreateFrame("Frame", nil, frame)
    poller:SetScript("OnUpdate", function(_, elapsed)
        self:PollPower()
        ns.Regen:Update(elapsed)
    end)
    self:Apply()
end

function Player:Apply()
    local db = ns.db
    local frame = self.frame
    frame:SetScale(db.scale)
    frame:ClearAllPoints()
    frame:SetPoint(db.point[1], UIParent, db.point[3], db.point[4], db.point[5])
    frame:SetSize(db.width * 2 + db.spacing, db.height + db.numberSize + 8)
    frame:EnableMouse(not db.locked)
    frame.unlockTint:SetShown(not db.locked)

    StyleBlock(self.health, db)
    StyleBlock(self.power, db)
    StyleBlock(self.mana, db)
    ns.Media:SetFont(self.health.shield, db.font, math.max(db.labelSize + 2, math.floor(db.numberSize * 0.6)), db.outline)
    self.power.gauge.bar:ClearAllPoints()
    self.power.gauge.bar:SetPoint("LEFT", self.health.gauge.bar, "RIGHT", db.spacing, 0)
    -- Outside the frame's bounds on purpose: growing it would move the gauges, and the click button
    -- can't be resized in combat. With the gauges spread far apart it stays near MP.
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
    ns.Pet:Apply()
    ns.Rest:Apply()
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

------------------------------------------------------------------------------
-- Clicks: secure buttons over the bar target you on left-click and open your menu on right-click
-- (FrogLib.Secure's), copying the bar's place rather than anchoring to it (that would protect it)
------------------------------------------------------------------------------

-- How far across a frame its anchor point lies (0 = left, 1 = right).
local function AcrossFraction(point)
    return point:find("LEFT") and 0 or point:find("RIGHT") and 1 or 0.5
end

-- Places the button over the part of the bar from `left` to `left + width` (its full height), with
-- the bar's own anchor point and offsets, so it follows the bar through UI scale changes.
local function PlaceOver(button, db, frameWidth, frameHeight, left, width)
    local point = db.point
    local across = AcrossFraction(point[1])
    button:SetScale(db.scale)
    button:ClearAllPoints()
    button:SetPoint(point[1], UIParent, point[3], point[4] + left + width * across - frameWidth * across, point[5])
    button:SetSize(width, frameHeight)
    button:SetHitRectInsets(-4, -4, -6, -4)
end

-- Two buttons, one over each gauge, sharing one menu, so with the gauges spread either side of the
-- action bars those still take their own clicks. Placed and shown out of combat only.
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
    local frameWidth, frameHeight = self.frame:GetSize()
    -- Each half reaches into the gap by up to 16, so at the usual gap they meet in the middle
    -- and cover the whole bar, as the single button did before.
    local reach = math.min(db.spacing / 2, 16)
    PlaceOver(self.click, db, frameWidth, frameHeight, 0, db.width + reach)
    PlaceOver(self.clickPower, db, frameWidth, frameHeight, db.width + db.spacing - reach, db.width + reach)
    -- Off while unlocked, so the bar can be dragged.
    local shown = db.clicks and db.locked
    self.click:SetShown(shown)
    self.clickPower:SetShown(shown)
end

------------------------------------------------------------------------------
-- Health and power
------------------------------------------------------------------------------

function Player:UpdateHealth(instant)
    local db = ns.db
    local value, max = UnitHealth("player"), UnitHealthMax("player")
    local gauge = self.health.gauge
    gauge:SetValues(value, max, instant)
    gauge:ShowHeal(db.heals)
    if db.heals then
        local healColor = db.healColor
        gauge:SetHealColor(healColor.r, healColor.g, healColor.b)
        gauge:UpdateHeal("player", instant)
    end
    -- The shield total can be secret; it only ever goes into the gauge's status bars.
    local shield = (UnitGetTotalAbsorbs and UnitGetTotalAbsorbs("player")) or 0
    local absorbColor = db.absorbColor
    gauge:ShowAbsorb(db.absorb)
    if db.absorb then
        gauge:SetAbsorb(shield, max)
        gauge:SetAbsorbColor(absorbColor.r, absorbColor.g, absorbColor.b)
    end
    -- "+X" only while there's a shield. A secret amount can't be compared with 0, but
    -- TruncateWhenZero writes nothing for zero and GetText is then nil, and testing that is allowed.
    local shieldText = self.health.shield
    shieldText:SetText("")
    if db.absorbText and C_StringUtil and C_StringUtil.TruncateWhenZero then
        shieldText:SetText(C_StringUtil.TruncateWhenZero(shield))
        if shieldText:GetText() then shieldText:SetFormattedText("+%d", shield) end
    end
    shieldText:SetTextColor(absorbColor.r, absorbColor.g, absorbColor.b)
    local healthColor = db.healthColor
    Tint(self.health, healthColor.r, healthColor.g, healthColor.b)
    -- The values may be secret: FrogLib's template only hands them to SetFormattedText.
    UI.SetTemplateText(self.health.number, db.healthText,
        { value = value, max = max, percent = Unit.HealthPercent("player") })
end

-- A block's gauge and number from your power of that type; instant: no easing (a change of form
-- or a reload). The values may be secret: they only go to the gauge and the text.
local function PaintPower(block, powerType, value, max, instant)
    block.gauge:SetValues(value, max, instant)
    UI.SetTemplateText(block.number, ns.db.powerText,
        { value = value, max = max, percent = Unit.PowerPercent("player", powerType) })
    if powerType == MANA then ns.Regen:OnMana(value, max) end
end

function Player:UpdatePower(instant)
    local db = ns.db
    local powerType, token = UnitPowerType("player")
    self.powerType = powerType
    local value, max = UnitPower("player", powerType), UnitPowerMax("player", powerType)
    local info = POWER[token]
    self.power.label:SetText(info and info[1] or (token and token:sub(1, 2)) or "PW")
    Tint(self.power, PowerColor(token, db))
    PaintPower(self.power, powerType, value, max, instant)
    self.last.power = {}
    self:UpdateMana(powerType, instant)
    -- The regen display goes on whichever gauge shows your mana.
    local block, r, g, b = nil, nil, nil, nil
    if powerType == MANA then
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
function Player:UpdateMana(powerType, instant)
    local db = ns.db
    local value, max = UnitPower("player", MANA), UnitPowerMax("player", MANA)
    local _, class = UnitClass("player")
    -- A secret max can't be compared; only these classes get here, and they all have mana.
    local shown = db.shiftMana and powerType ~= MANA and SHIFT_MANA_CLASSES[class]
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
function Player:PollBlock(block, powerType, last, force, due)
    local value, max = UnitPower("player", powerType), UnitPowerMax("player", powerType)
    if issecret(value) or issecret(max) then
        if not (force or due) then return end
        last.value, last.max = nil, nil
    else
        if not force and last.value == value and last.max == max then return end
        last.value, last.max = value, max
    end
    PaintPower(block, powerType, value, max)
end

-- Every frame, and on UNIT_POWER_FREQUENT (force).
function Player:PollPower(force)
    if self.powerType == nil then return end
    local now = GetTime()
    local due = now - (self.polledAt or 0) >= SECRET_POLL
    if due then self.polledAt = now end
    self:PollBlock(self.power, self.powerType, self.last.power, force, due)
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
    local db, frame = ns.db, self.frame
    local bottom = frame:GetBottom()
    if not bottom then return end
    db.point = { "BOTTOM", "UIParent", "BOTTOM", 0, math.floor(bottom + 0.5) }
    ns.Refresh()
end

local function BuildLayout(page)
    local db = ns.db
    local place = UI.Placer()
    place(UI.Checkbox(page, "Unlock to move (drag the bar)",
        function() return not db.locked end, function(value) db.locked = not value end), 28)
    place(UI.Checkbox(page, "Click to target yourself, right-click for your menu", db, "clicks"), 28)
    place(UI.Checkbox(page, "Hide Blizzard's player frame", db, "hidePlayerFrame"), 34)
    place(UI.Stepper(page, "Scale", 0.5, 2, 0.05, db, "scale", "%.2f"), 26)
    place(UI.Stepper(page, "Gauge width", 80, 500, 10, db, "width"), 26)
    place(UI.Stepper(page, "Gauge height", 2, 20, 1, db, "height"), 26)
    -- Up to the whole screen: the gauges can sit either side of the action bars.
    place(UI.Slider(page, "Gap between gauges", 0, 120, 2, db, "spacing", MaxGap), 28)
    local centre = UI.Button(page, "Centre the bar across the screen", 230)
    place(centre, 26, 150)
    centre:SetScript("OnClick", function() Player:CentreHorizontally() end)
    place(UI.Help(page, "A wide gap puts HP and MP either side of your action bars; centre the bar to "
        .. "spread them evenly. Shift-click - or + for bigger steps.", 400), 30)
    place(UI.Dropdown(page, "Gauge style", STYLES, db, "style"), 30)
    place(UI.Dropdown(page, "Bar texture", function() return ns.Media:List("statusbar") end, db, "texture"), 30)
    place(UI.Dropdown(page, "Power colours", COLOR_MODES, db, "colorMode"), 30)
    place(UI.Checkbox(page, "Show my mana in forms (bear, cat, Shadow, Elemental)", db, "shiftMana"), 30)
    place(UI.ColorSwatch(page, "HP colour", db, "healthColor"), 30)
    place(UI.Checkbox(page, "Show incoming heals on the HP gauge", db, "heals"), 26)
    place(UI.ColorSwatch(page, "Incoming heal colour", db, "healColor"), 30)
    place(UI.Checkbox(page, "Show shields (absorbs) on the HP gauge", db, "absorb"), 26)
    place(UI.Checkbox(page, "Show the shield as \"+X\" after the HP number", db, "absorbText"), 28)
    place(UI.ColorSwatch(page, "Shield colour", db, "absorbColor"), 36)
    place(UI.Checkbox(page, "Dim out of combat", db, "fade"), 28)
    place(UI.Stepper(page, "Dimmed opacity", 0, 1, 0.05, db, "fadeAlpha", "%.2f"), 26)
end

local function BuildText(page)
    local db = ns.db
    local place = UI.Placer()
    place(UI.TextBox(page, "HP number", db, "healthText"), 28)
    place(UI.TextBox(page, "Power number", db, "powerText"), 30)
    place(UI.Help(page, "Words: |cffffd100value|r, |cffffd100max|r, |cffffd100percent|r (|cffffd100percent.1|r "
        .. "for a decimal). For example: value / max", 400), 36, 4)
    place(UI.Dropdown(page, "Font", function() return ns.Media:List("font") end, db, "font"), 30)
    place(UI.Dropdown(page, "Font outline", UI.OUTLINES, db, "outline"), 30)
    place(UI.Stepper(page, "Label size (HP/MP)", 8, 24, 1, db, "labelSize"), 26)
    place(UI.Stepper(page, "Number size", 10, 48, 1, db, "numberSize"), 34)

    local regen = db.regen
    place(UI.Label(page, "Mana regen"), 22)
    place(UI.Checkbox(page, "Show my mana regen after the MP number (live)", regen, "rate"), 28)
    place(UI.Dropdown(page, "Regen shown", REGEN_UNITS, regen, "per"), 30)
    place(UI.Checkbox(page, "Show the five-second rule under the MP gauge", regen, "rule"), 28)
    place(UI.Help(page, "After you spend mana, regen stops for five seconds; a strip under the gauge fills "
        .. "until it starts again. The rate is the game's own (the character sheet's Mana Regen).", 400), 36)
    ns.Rest.BuildSettings(page, place)
end

local function BuildCast(page)
    local cast = ns.db.cast
    local place = UI.Placer()
    place(UI.Checkbox(page, "Show my cast bar", cast, "enabled"), 28)
    place(UI.Checkbox(page, "Hide Blizzard's cast bar", cast, "hideBlizzard"), 28)
    place(UI.Checkbox(page, "Show time left", cast, "showTime"), 28)
    place(UI.Checkbox(page, "Show latency (shaded end of the bar)", cast, "showLatency"), 28)
    place(UI.ColorSwatch(page, "Latency colour", cast, "latencyColor"), 30)
    place(UI.Checkbox(page, "Show the spell icon", cast, "showIcon"), 28)
    place(UI.Stepper(page, "Icon size", 10, 64, 1, cast, "iconSize"), 34)
    place(UI.Stepper(page, "Width", 80, 600, 10, cast, "width"), 26)
    place(UI.Stepper(page, "Height", 2, 20, 1, cast, "height"), 26)
    place(UI.Stepper(page, "Move left / right", -600, 600, 2, cast, "x"), 26)
    place(UI.Stepper(page, "Move up / down", -300, 600, 2, cast, "y"), 34)
    place(UI.Help(page, "It uses the gauge style, texture and font from the other tabs. Unlock the bar "
        .. "(Layout) to see a sample cast while you place it.", 400), 36)
end

function ns.ToggleConfig()
    if not ns.window then
        ns.window = UI.Window("XIVPlayerConfig", "XIVPlayer", 800, 720, {
            { "layout", "Layout", BuildLayout },
            { "text", "Text", BuildText },
            { "cast", "Cast bar", BuildCast },
            { "swing", "Swing timer", ns.Swing.BuildPage },
            { "buffs", "Buffs", function(page) ns.Auras.BuildPage(page, "buffs") end },
            { "debuffs", "Debuffs", function(page) ns.Auras.BuildPage(page, "debuffs") end },
            { "pet", "Pet", ns.Pet.BuildPage },
            { "pettarget", "Pet's target", ns.Pet.BuildTargetPage },
        }, { fitTabs = true })
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
loader:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" and addonName == ADDON then
        XIVPlayerDB = XIVPlayerDB or {}
        local db = XIVPlayerDB
        -- 0.1 -> 0.2: framed style, Michroma and new sizes, where the old defaults were untouched.
        if not db.version then
            local old = { height = 5, width = 200, labelSize = 12, numberSize = 24,
                font = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF" }
            for key, value in pairs(old) do
                if db[key] == value then db[key] = nil end
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

-- Its entry in the game's Options > AddOns list (FrogLib's Options.lua).
FrogLib.Options.Add("XIVPlayer", ns, {
    open = function()
        if not (ns.window and ns.window:IsShown()) then ns.ToggleConfig() end
    end,
    commands = { { "/xivp", "open or close the settings" } },
})
