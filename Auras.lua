local _, ns = ...
local UI = ns.UI
local Auras = {}
ns.Auras = Auras

-- Your buffs and debuffs above the gauges: whitelisted buffs over HP, every debuff except a
-- blacklist over MP. Rendered by 12.1's AuraContainer, like PersonalResourceTweaks and
-- XIVTarget: the engine picks and draws the auras from a spell-ID filter, so it keeps working
-- where addons can't read aura data. Lessons carried over: position a container before setting
-- it up, never anchor anything to it, and size its buttons ourselves (the engine makes them 0x0).

local issecret = issecretvalue or function() return false end
local KINDS = { "buffs", "debuffs" }
local SORT = AuraContainerSortMethod and AuraContainerSortMethod.Default
local SORT_DIR = AuraContainerSortDirection and AuraContainerSortDirection.Normal
-- Timers and stacks use the narrow bundled face; Michroma is too wide for a gap one icon wide.
local TIMER_FONT = "Interface\\AddOns\\XIVPlayer\\Fonts\\SourceSans3.ttf"
local TIMER_ROOM = 12 -- the countdown prints under each icon, FFXIV-style

local containers, signatures, groupKeys = {}, {}, {}
local styled = { buffs = {}, debuffs = {} }

local formatter
local function DurationFormatter()
    if formatter ~= nil then return formatter or nil end
    formatter = false
    local R = Enum.NumericRuleFormatRounding
    if C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and R then
        local f = C_StringUtil.CreateNumericRuleFormatter()
        if pcall(f.SetBreakpoints, f, {
            { threshold = 0, format = "%d", step = 1, rounding = R.Up },
            { threshold = 60, format = "%dm", step = 1, rounding = R.Up, components = { { div = 60 } } },
            { threshold = 61, format = "%dm", step = 1, rounding = R.Down, components = { { div = 60 } } },
            { threshold = 3600, format = "%dh", step = 1, rounding = R.Down, components = { { div = 3600 } } },
        }) then
            formatter = f
        end
    end
    return formatter or nil
end

-- Blizzard renamed the container layout setters mid-12.1 (SetAuraLayout* -> SetFlowLayout*).
local function CallEither(c, newName, oldName, ...)
    local f = c[newName] or c[oldName]
    if f then pcall(f, c, ...) end
end

local function StyleButton(d)
    local cfg = ns.db[d.kind]
    -- Denied while auras are secret; retried on the next restyle.
    if d.size ~= cfg.size and pcall(d.button.SetSize, d.button, cfg.size, cfg.size) then
        d.size = cfg.size
    end
    local size = math.max(9, math.floor(cfg.size * 0.46))
    ns.Media:SetFont(d.stack, TIMER_FONT, size, ns.db.outline)
    ns.Media:SetFont(d.duration, TIMER_FONT, size, ns.db.outline)
    d.duration:SetShown(cfg.showTimer)
end

-- Runs once per engine-made button. Fonts go on before the regions are handed over, because
-- handing them over makes the engine write text straight away.
local function MakeInit(kind)
    return function(button)
        local d = { kind = kind, button = button }
        d.border = button:CreateTexture(nil, "BACKGROUND")
        d.border:SetAllPoints()
        if kind == "debuffs" then
            d.border:SetColorTexture(0.75, 0.12, 0.08, 1)
        else
            d.border:SetColorTexture(0, 0, 0, 1)
        end
        d.icon = button:CreateTexture(nil, "ARTWORK")
        d.icon:SetPoint("TOPLEFT", 1, -1)
        d.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        d.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        d.cooldown:SetAllPoints(d.icon)
        d.cooldown:SetDrawEdge(false)
        d.cooldown:SetReverse(true)
        d.cooldown:SetHideCountdownNumbers(true)
        local carrier = CreateFrame("Frame", nil, button)
        carrier:SetAllPoints()
        carrier:SetFrameLevel(d.cooldown:GetFrameLevel() + 1)
        carrier:EnableMouse(false)
        d.stack = carrier:CreateFontString(nil, "OVERLAY")
        d.stack:SetPoint("BOTTOMRIGHT", -1, 1)
        d.duration = carrier:CreateFontString(nil, "OVERLAY")
        d.duration:SetPoint("TOP", button, "BOTTOM", 0, -1)
        StyleButton(d)

        -- Clicks off so icons never eat clicks meant for the world; hover tooltips stay.
        pcall(button.SetMouseClickEnabled, button, false)
        button:SetIcon(d.icon)
        button:SetDurationCooldown(d.cooldown)
        button:SetApplicationCount(d.stack, {})
        if not pcall(button.SetDurationText, button, d.duration, { textFormatter = DurationFormatter() }) then
            pcall(button.SetDurationText, button, d.duration, {})
        end
        table.insert(styled[kind], d)
    end
end

local function Layout(cfg)
    return { elementWidth = cfg.size, elementHeight = cfg.size, elementSpacing = cfg.spacing,
        lineSpacing = cfg.spacing + (cfg.showTimer and TIMER_ROOM or 0) }
end

-- Whatever changes which groups exist; groups can't be removed, so a change means a rebuild.
local function Signature(kind)
    local cfg = ns.db[kind]
    if kind == "buffs" then return "w|" .. table.concat(cfg.list, ",") end
    return "b|" .. cfg.max .. "|" .. (cfg.maxMinutes or 0) .. "|" .. table.concat(cfg.blacklist, ",")
end

local function Build(kind)
    local cfg = ns.db[kind]
    local old = containers[kind]
    if old then
        pcall(old.SetUnit, old, "none")
        old:Hide()
        containers[kind] = nil
    end
    if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        C_AddOns.LoadAddOn("Blizzard_AuraContainer")
    end
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, ns.Player.frame, "CustomAuraContainerTemplate")
    if not ok then return end

    -- Placed before anything else: a container without a renderable rect never shows an aura.
    c:SetSize(1, 1)
    containers[kind] = c
    Auras:Anchor()
    CallEither(c, "SetFlowLayoutAnchorPoint", "SetAuraLayoutAnchorPoint", "BOTTOMLEFT")
    CallEither(c, "SetFlowLayoutGrowthDirection", "SetAuraLayoutGrowthDirection",
        AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Up)

    styled[kind] = {}
    local keys, init, layout = {}, MakeInit(kind), Layout(cfg)
    local function add(key, filter, opts)
        opts.sortMethod, opts.sortDirection = SORT, SORT_DIR
        opts.initializeFrame, opts.layout = init, layout
        if pcall(c.AddAuraGroup, c, key, filter, opts) then keys[#keys + 1] = key end
    end
    if kind == "buffs" then
        -- One single-slot group per spell keeps the whitelist's order.
        for i, id in ipairs(cfg.list) do
            add("w" .. i, "HELPFUL", { maxFrameCount = 1, candidateFilters = { includeSpellIDs = { [id] = true } } })
        end
    else
        -- The engine ignores spell-ID filters for debuffs on a unit you can assist, yourself
        -- included, except for the few spells it never hides from addons (EllesmereUI calls it
        -- the identity gate). So the blacklist only catches those; duration does work on you,
        -- so long debuffs (Boosted Rest's hour, say) are hidden by a duration cap instead.
        -- maxDuration also drops debuffs with no duration at all.
        local filters = {}
        local exclude = {}
        for _, id in ipairs(cfg.blacklist) do exclude[id] = true end
        if next(exclude) then filters.excludeSpellIDs = exclude end
        if (cfg.maxMinutes or 0) > 0 then filters.maxDuration = cfg.maxMinutes * 60 end
        add("all", "HARMFUL", { maxFrameCount = cfg.max, candidateFilters = next(filters) and filters or nil })
    end
    groupKeys[kind] = keys
    -- Unit last: the engine only listens for aura events once the container has groups.
    c:SetUnit("player")
    c:UpdateAllAuras()
    signatures[kind] = Signature(kind)
end

-- Buffs over the HP gauge, debuffs over the MP gauge.
function Auras:Anchor()
    local over = { buffs = ns.Player.health.gauge.bar, debuffs = ns.Player.power.gauge.bar }
    for kind, c in pairs(containers) do
        local cfg = ns.db[kind]
        c:ClearAllPoints()
        c:SetPoint("BOTTOMLEFT", over[kind], "TOPLEFT", 0, cfg.offsetY + (cfg.showTimer and TIMER_ROOM or 0))
    end
end

function Auras:Apply()
    for _, kind in ipairs(KINDS) do
        local cfg = ns.db[kind]
        if not containers[kind] or signatures[kind] ~= Signature(kind) then Build(kind) end
        local c = containers[kind]
        if c then
            local layout = Layout(cfg)
            for _, key in ipairs(groupKeys[kind]) do
                pcall(c.SetAuraGroupLayout, c, key, layout)
            end
            CallEither(c, "SetFlowLayoutMaximumLineSize", "SetAuraLayoutRowWidth", ns.db.width + 0.4)
            c:SetShown(cfg.enabled)
            for _, d in ipairs(styled[kind]) do pcall(StyleButton, d) end
        end
    end
    self:Anchor()
end

------------------------------------------------------------------------------
-- Settings pages: the spell lists
------------------------------------------------------------------------------

local ROW_H = 26

local function SpellInfo(id)
    return C_Spell.GetSpellName(id), C_Spell.GetSpellTexture(id)
end

-- Mouse-wheel scroll list of icon + text rows; callers add their own buttons per row.
local function ScrollList(parent, w, h)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    sf:SetSize(w, h)
    local bg = sf:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.3)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(w, 1)
    sf:SetScrollChild(child)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local max = math.max(0, child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * ROW_H)))
    end)
    sf.child, sf.rows, sf.w = child, {}, w
    return sf
end

local function Fill(sf, items, setup)
    for i, item in ipairs(items) do
        local r = sf.rows[i]
        if not r then
            r = CreateFrame("Frame", nil, sf.child)
            r:SetSize(sf.w - 8, ROW_H)
            r:SetPoint("TOPLEFT", 4, -(i - 1) * ROW_H - 2)
            r.icon = r:CreateTexture(nil, "ARTWORK")
            r.icon:SetSize(22, 22)
            r.icon:SetPoint("LEFT")
            r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            r.text = UI.Label(r, "", "GameFontHighlight")
            r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
            r.text:SetWidth(sf.w - 150)
            r.text:SetJustifyH("LEFT")
            r.text:SetWordWrap(false)
            sf.rows[i] = r
        end
        setup(r, item, i)
        r:Show()
    end
    for i = #items + 1, #sf.rows do sf.rows[i]:Hide() end
    sf.child:SetHeight(math.max(1, #items * ROW_H + 4))
    local max = math.max(0, sf.child:GetHeight() - sf:GetHeight())
    if sf:GetVerticalScroll() > max then sf:SetVerticalScroll(max) end
end

-- Lists the auras on you right now, so a spell can be added without knowing its ID.
local picker
local function ShowPicker(window, kind, onAdd)
    if InCombatLockdown() then
        print("|cfff5dc8fXIVPlayer|r: Leave combat to browse your current auras.")
        return
    end
    if not picker then
        picker = CreateFrame("Frame", nil, window, "BasicFrameTemplateWithInset")
        picker:SetSize(320, 420)
        picker:SetPoint("TOPLEFT", window, "TOPRIGHT", 4, 0)
        picker.title = UI.Label(picker, "")
        picker.title:SetPoint("TOP", 0, -5)
        picker.list = ScrollList(picker, 296, 370)
        picker.list:SetPoint("TOPLEFT", 12, -32)
    end
    picker.title:SetText("Your current " .. kind)
    local items = {}
    for i = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, kind == "buffs" and "HELPFUL" or "HARMFUL")
        if not ok or not aura then break end
        if not issecret(aura.spellId) then items[#items + 1] = aura end
    end
    Fill(picker.list, items, function(r, aura)
        r.icon:SetTexture(aura.icon)
        r.text:SetText(aura.name .. " |cff888888(" .. aura.spellId .. ")|r")
        if not r.add then
            r.add = UI.Button(r, "Add", 44, 20)
            r.add:SetPoint("RIGHT", -2, 0)
        end
        r.add:SetScript("OnClick", function() onAdd(aura.spellId) end)
    end)
    picker:Show()
end

-- One settings page: buffs are a whitelist (shown in order), debuffs a blacklist.
function Auras.BuildPage(p, kind)
    local cfg = ns.db[kind]
    local whitelist = kind == "buffs"
    local ids = whitelist and cfg.list or cfg.blacklist
    local place = UI.Placer()
    local refreshList

    place(UI.Checkbox(p, "Show " .. kind .. (whitelist and " (only the ones listed below)" or ""),
        function() return cfg.enabled end, function(v) cfg.enabled = v end), 26)
    place(UI.Checkbox(p, "Show countdown under the icons",
        function() return cfg.showTimer end, function(v) cfg.showTimer = v end), 30)
    place(UI.Stepper(p, "Icon size", 14, 48, 2, function() return cfg.size end, function(v) cfg.size = v end), 26)
    if not whitelist then
        place(UI.Stepper(p, "Most shown", 1, 40, 1, function() return cfg.max end, function(v) cfg.max = v end), 26)
        place(UI.Stepper(p, "Hide if over (mins)", 0, 120, 5, function() return cfg.maxMinutes or 0 end,
            function(v) cfg.maxMinutes = v end), 26)
    end
    place(UI.Stepper(p, "Spacing", 0, 12, 1, function() return cfg.spacing end, function(v) cfg.spacing = v end), 26)
    place(UI.Stepper(p, "Raise above the gauge", -20, 80, 2, function() return cfg.offsetY end,
        function(v) cfg.offsetY = v end), 30)

    place(UI.Label(p, whitelist and "Buffs to show (in this order)" or "Debuffs to hide"), 18)
    if whitelist then
        place(UI.Help(p, "Hover any buff or spell to see its Spell ID, or pick from what's on you now.", 400), 20)
    else
        -- The game skips spell-ID lists for debuffs on you (see Build), so say so plainly.
        place(UI.Help(p, "The game only lets addons hide a few debuffs on you by name. For long ones "
            .. "like Boosted Rest (an hour), set \"Hide if over\" above, e.g. to 30. 0 turns it off.", 400), 30)
    end

    local function AddID(id)
        id = tonumber(id)
        if not id then return end
        if not SpellInfo(id) then
            print("|cfff5dc8fXIVPlayer|r: No spell with ID", id)
            return
        end
        for _, v in ipairs(ids) do
            if v == id then return end
        end
        table.insert(ids, id)
        refreshList()
        ns.Refresh()
    end

    local eb = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    eb:SetSize(90, 20)
    eb:SetAutoFocus(false)
    eb:SetNumeric(true)
    place(eb, 22, 6)
    local add = UI.Button(p, "Add ID", 70)
    add:SetPoint("LEFT", eb, "RIGHT", 6, 0)
    local pick = UI.Button(p, "Pick from my current " .. kind, 190)
    pick:SetPoint("LEFT", add, "RIGHT", 6, 0)
    local preview = UI.Label(p, "", "GameFontHighlightSmall")
    place(preview, 20, 6)
    eb:SetScript("OnTextChanged", function(self)
        preview:SetText(SpellInfo(tonumber(self:GetText()) or 0) or "")
    end)
    eb:SetScript("OnEnterPressed", function(self)
        AddID(self:GetText())
        self:SetText("")
        self:ClearFocus()
    end)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    add:SetScript("OnClick", function()
        AddID(eb:GetText())
        eb:SetText("")
    end)
    pick:SetScript("OnClick", function() ShowPicker(ns.window, kind, AddID) end)
    p:HookScript("OnHide", function() if picker then picker:Hide() end end)

    local list = ScrollList(p, 400, whitelist and 130 or 104)
    place(list, 0)

    function refreshList()
        Fill(list, ids, function(r, id, i)
            local name, icon = SpellInfo(id)
            r.icon:SetTexture(icon or 134400)
            r.text:SetText((name or "Unknown spell") .. " |cff888888(" .. id .. ")|r")
            if not r.remove then
                r.remove = UI.Button(r, "X", 24, 20)
                r.remove:SetPoint("RIGHT", -2, 0)
                r.down = UI.Button(r, "Dn", 36, 20)
                r.down:SetPoint("RIGHT", r.remove, "LEFT", -2, 0)
                r.up = UI.Button(r, "Up", 36, 20)
                r.up:SetPoint("RIGHT", r.down, "LEFT", -2, 0)
            end
            r.up:SetShown(whitelist)
            r.down:SetShown(whitelist)
            r.up:SetEnabled(i > 1)
            r.down:SetEnabled(i < #ids)
            r.remove:SetScript("OnClick", function()
                table.remove(ids, i)
                refreshList()
                ns.Refresh()
            end)
            r.up:SetScript("OnClick", function()
                ids[i], ids[i - 1] = ids[i - 1], ids[i]
                refreshList()
                ns.Refresh()
            end)
            r.down:SetScript("OnClick", function()
                ids[i], ids[i + 1] = ids[i + 1], ids[i]
                refreshList()
                ns.Refresh()
            end)
        end)
    end
    refreshList()
end

-- Spell IDs on aura and spell tooltips, so adding to a list is "hover, read, type". Left to
-- PersonalResourceTweaks when it's loaded, which adds the same line.
local idFrame = CreateFrame("Frame")
idFrame:RegisterEvent("PLAYER_LOGIN")
idFrame:SetScript("OnEvent", function()
    if C_AddOns.IsAddOnLoaded("PersonalResourceTweaks") then return end
    if not (TooltipDataProcessor and Enum.TooltipDataType) then return end
    local function AddID(tooltip, data)
        local id = data and data.id
        if not id or issecret(id) then return end
        tooltip:AddLine("Spell ID: " .. id, 0.5, 0.8, 1)
    end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.UnitAura, AddID)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, AddID)
end)
