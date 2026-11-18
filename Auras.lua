local _, ns = ...
local UI = ns.UI
local Auras = {}
ns.Auras = Auras

-- Your buffs and debuffs above the gauges: buffs over HP (a whitelist, or every buff except a
-- blacklist), every debuff except a blacklist over MP. Drawn by 12.1's AuraContainer (FrogLib.Auras), as Personal Resource Tweaks and
-- XIVTarget do: the engine picks and draws the auras from a spell-ID filter, so it keeps working
-- where addons can't read aura data.

local issecret = FrogLib.issecret
local AuraKit = FrogLib.Auras
local KINDS = { "buffs", "debuffs" }
local SORT = AuraContainerSortMethod and AuraContainerSortMethod.Default
local SORT_DIR = AuraContainerSortDirection and AuraContainerSortDirection.Normal
-- Timers and stacks use the narrow bundled face; Michroma is too wide for a gap one icon wide.
local TIMER_FONT = "Interface\\AddOns\\XIVPlayer\\Fonts\\SourceSans3.ttf"
local TIMER_ROOM = 12 -- the countdown prints under each icon, FFXIV-style

local containers, signatures, groupKeys = {}, {}, {}
local styled = { buffs = {}, debuffs = {} }

local function StyleButton(parts)
    local settings = ns.db[parts.kind]
    -- Denied while auras are secret; retried on the next restyle.
    if parts.size ~= settings.size and pcall(parts.button.SetSize, parts.button, settings.size, settings.size) then
        parts.size = settings.size
    end
    local size = math.max(9, math.floor(settings.size * 0.46))
    ns.Media:SetFont(parts.stack, TIMER_FONT, size, ns.db.outline)
    ns.Media:SetFont(parts.duration, TIMER_FONT, size, ns.db.outline)
    parts.duration:SetShown(settings.showTimer)
end

-- Runs once per engine-made button. Fonts go on before the regions are handed over, because
-- handing them over makes the engine write text straight away.
local function MakeInit(kind)
    return function(button)
        local parts = AuraKit.InitButton(button, { border = kind == "debuffs" and { 0.75, 0.12, 0.08 } or nil,
            style = function(new)
                new.kind = kind
                StyleButton(new)
            end })
        table.insert(styled[kind], parts)
    end
end

local function Layout(settings)
    return { elementWidth = settings.size, elementHeight = settings.size, elementSpacing = settings.spacing,
        lineSpacing = settings.spacing + (settings.showTimer and TIMER_ROOM or 0) }
end

-- Whatever changes which groups exist; groups can't be removed, so a change means a rebuild.
-- Buffs in whitelist mode: one group per listed spell, in order. Everything else: one group of all
-- but a blacklist.
local function Ordered(kind)
    return kind == "buffs" and ns.db.buffs.mode ~= "blacklist"
end

local function Signature(kind)
    local settings = ns.db[kind]
    if Ordered(kind) then return "w|" .. table.concat(settings.list, ",") end
    return "b|" .. settings.max .. "|" .. (settings.maxMinutes or 0) .. "|" .. table.concat(settings.blacklist, ",")
end

local function Build(kind)
    local settings = ns.db[kind]
    AuraKit.Release(containers[kind])
    containers[kind] = nil
    local container = AuraKit.NewContainer(ns.Player.frame)
    if not container then return end

    -- Placed before anything else: a container without a renderable rect never shows an aura.
    containers[kind] = container
    Auras:Anchor()
    AuraKit.Flow(container, "BOTTOMLEFT", "RIGHT", "UP")

    styled[kind] = {}
    local keys, init, layout = {}, MakeInit(kind), Layout(settings)
    local function Add(key, filter, opts)
        opts.sortMethod, opts.sortDirection = SORT, SORT_DIR
        opts.initializeFrame, opts.layout = init, layout
        if pcall(container.AddAuraGroup, container, key, filter, opts) then keys[#keys + 1] = key end
    end
    if Ordered(kind) then
        -- One single-slot group per spell keeps the whitelist's order.
        for i, spellID in ipairs(settings.list) do
            Add("w" .. i, "HELPFUL", { maxFrameCount = 1, candidateFilters = { includeSpellIDs = { [spellID] = true } } })
        end
    else
        -- On a unit you can assist (you too) the engine ignores spell-ID filters for debuffs, but for
        -- the few it never hides from addons (EllesmereUI's "identity gate"); buffs take them. Duration
        -- works on both, so long auras (Boosted Rest's hour) can go by a cap instead; it also drops
        -- those with no duration.
        local filters = {}
        local exclude = {}
        for _, spellID in ipairs(settings.blacklist) do exclude[spellID] = true end
        if next(exclude) then filters.excludeSpellIDs = exclude end
        if (settings.maxMinutes or 0) > 0 then filters.maxDuration = settings.maxMinutes * 60 end
        Add("all", kind == "buffs" and "HELPFUL" or "HARMFUL",
            { maxFrameCount = settings.max, candidateFilters = next(filters) and filters or nil })
    end
    groupKeys[kind] = keys
    -- Unit last: the engine only listens for aura events once the container has groups.
    container:SetUnit("player")
    container:UpdateAllAuras()
    signatures[kind] = Signature(kind)
end

-- Buffs over the HP gauge, debuffs over the MP gauge.
function Auras:Anchor()
    local over = { buffs = ns.Player.health.gauge.bar, debuffs = ns.Player.power.gauge.bar }
    for kind, container in pairs(containers) do
        local settings = ns.db[kind]
        container:ClearAllPoints()
        container:SetPoint("BOTTOMLEFT", over[kind], "TOPLEFT", 0, settings.offsetY + (settings.showTimer and TIMER_ROOM or 0))
    end
end

function Auras:Apply()
    for _, kind in ipairs(KINDS) do
        local settings = ns.db[kind]
        if not containers[kind] or signatures[kind] ~= Signature(kind) then Build(kind) end
        local container = containers[kind]
        if container then
            local layout = Layout(settings)
            for _, key in ipairs(groupKeys[kind]) do
                pcall(container.SetAuraGroupLayout, container, key, layout)
            end
            AuraKit.SetLineSize(container, ns.db.width + 0.4)
            container:SetShown(settings.enabled)
            for _, parts in ipairs(styled[kind]) do pcall(StyleButton, parts) end
        end
    end
    self:Anchor()
end

------------------------------------------------------------------------------
-- Settings pages: the spell lists, and a picker of the auras on you now (so a spell can be added
-- without knowing its ID)
------------------------------------------------------------------------------

local SpellInfo, ScrollList, Fill = UI.SpellInfo, UI.ScrollList, UI.FillList
local function Say(text) FrogLib.Util.Say("|cfff5dc8fXIVPlayer|r: " .. text) end -- in combat, after it
local function ShowPicker(window, kind, onAdd)
    UI.AuraPicker(window, kind, onAdd, Say)
end

local BUFF_MODES = UI.Options("whitelist", "Whitelist: only these", "blacklist", "Blacklist: all except these")

-- One settings page: buffs are a whitelist (shown in order) or a blacklist, debuffs a blacklist.
function Auras.BuildPage(page, kind)
    local settings = ns.db[kind]
    local buffs = kind == "buffs"
    local place = UI.Placer()
    local RefreshList, Relabel

    local function SpellIDs()
        return Ordered(kind) and settings.list or settings.blacklist
    end

    place(UI.Checkbox(page, "Show " .. kind, settings, "enabled"), 26)
    place(UI.Checkbox(page, "Show countdown under the icons", settings, "showTimer"), 30)
    if buffs then
        place(UI.Dropdown(page, "Buffs shown", BUFF_MODES, function() return settings.mode end, function(value)
            settings.mode = value
            Relabel()
            RefreshList()
        end), 30)
    end
    place(UI.Stepper(page, "Icon size", 14, 48, 2, settings, "size"), 26)
    -- Only for a blacklist; hidden on the buff page while it's a whitelist (they'd do nothing).
    local most = UI.Stepper(page, "Most shown", 1, 40, 1, settings, "max")
    place(most, 26)
    local cap = UI.Stepper(page, "Hide if over (mins)", 0, 120, 5, settings, "maxMinutes")
    place(cap, 26)
    place(UI.Stepper(page, "Spacing", 0, 12, 1, settings, "spacing"), 26)
    place(UI.Stepper(page, "Raise above the gauge", -20, 80, 2, settings, "offsetY"), 30)

    local header = UI.Label(page, "")
    place(header, 18)
    local help = UI.Help(page, "", 400)
    place(help, 30)

    function Relabel()
        local ordered = Ordered(kind)
        most:SetShown(not ordered)
        cap:SetShown(not ordered)
        if ordered then
            header:SetText("Whitelist: only these buffs show (in this order)")
            help:SetText("Hover any buff or spell to see its Spell ID, or pick from what's on you now.")
        elseif buffs then
            header:SetText("Blacklist: every buff shows except these")
            help:SetText("Hover any buff or spell to see its Spell ID, or pick from what's on you now. "
                .. "\"Hide if over\" drops long ones (an hour's food) but also any that never run out "
                .. "(forms, auras); 0 turns it off.")
        else
            -- The game skips spell-ID lists for debuffs on you (see Build), so say so plainly.
            header:SetText("Debuffs to hide")
            help:SetText("The game only lets addons hide a few debuffs on you by name. For long ones "
                .. "like Boosted Rest (an hour), set \"Hide if over\" above, e.g. to 30. 0 turns it off.")
        end
    end
    Relabel()

    local function AddID(spellID)
        spellID = tonumber(spellID)
        if not spellID then return end
        if not SpellInfo(spellID) then
            Say("No spell with ID " .. tostring(spellID))
            return
        end
        local spellIDs = SpellIDs()
        for _, listed in ipairs(spellIDs) do
            if listed == spellID then return end
        end
        table.insert(spellIDs, spellID)
        RefreshList()
        ns.Refresh()
    end

    local idBox = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    idBox:SetSize(90, 20)
    idBox:SetAutoFocus(false)
    idBox:SetNumeric(true)
    place(idBox, 22, 6)
    local add = UI.Button(page, "Add ID", 70)
    add:SetPoint("LEFT", idBox, "RIGHT", 6, 0)
    local pick = UI.Button(page, "Pick from my current " .. kind, 190)
    pick:SetPoint("LEFT", add, "RIGHT", 6, 0)
    local preview = UI.Label(page, "", "GameFontHighlightSmall")
    place(preview, 20, 6)
    idBox:SetScript("OnTextChanged", function(self)
        preview:SetText(SpellInfo(tonumber(self:GetText()) or 0) or "")
    end)
    idBox:SetScript("OnEnterPressed", function(self)
        AddID(self:GetText())
        self:SetText("")
        self:ClearFocus()
    end)
    idBox:SetScript("OnEscapePressed", idBox.ClearFocus)
    add:SetScript("OnClick", function()
        AddID(idBox:GetText())
        idBox:SetText("")
    end)
    pick:SetScript("OnClick", function() ShowPicker(ns.window, kind, AddID) end)
    page:HookScript("OnHide", function()
        local picker = ns.window and ns.window.frogPicker
        if picker then picker:Hide() end
    end)

    local list = ScrollList(page, 400, buffs and 130 or 104)
    place(list, 0)

    function RefreshList()
        local spellIDs, ordered = SpellIDs(), Ordered(kind)
        Fill(list, spellIDs, function(row, spellID, i)
            local name, icon = SpellInfo(spellID)
            row.icon:SetTexture(icon or 134400)
            row.text:SetText((name or "Unknown spell") .. " |cff888888(" .. spellID .. ")|r")
            if not row.remove then
                row.remove = UI.Button(row, "X", 24, 20)
                row.remove:SetPoint("RIGHT", -2, 0)
                row.down = UI.Button(row, "Dn", 36, 20)
                row.down:SetPoint("RIGHT", row.remove, "LEFT", -2, 0)
                row.up = UI.Button(row, "Up", 36, 20)
                row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)
            end
            row.up:SetShown(ordered)
            row.down:SetShown(ordered)
            row.up:SetEnabled(i > 1)
            row.down:SetEnabled(i < #spellIDs)
            row.remove:SetScript("OnClick", function()
                table.remove(spellIDs, i)
                RefreshList()
                ns.Refresh()
            end)
            row.up:SetScript("OnClick", function()
                spellIDs[i], spellIDs[i - 1] = spellIDs[i - 1], spellIDs[i]
                RefreshList()
                ns.Refresh()
            end)
            row.down:SetScript("OnClick", function()
                spellIDs[i], spellIDs[i + 1] = spellIDs[i + 1], spellIDs[i]
                RefreshList()
                ns.Refresh()
            end)
        end)
    end
    RefreshList()
end

-- Spell IDs on aura and spell tooltips, so adding to a list is "hover, read, type". Left to
-- Personal Resource Tweaks when it's loaded, which adds the same line.
local idFrame = CreateFrame("Frame")
idFrame:RegisterEvent("PLAYER_LOGIN")
idFrame:SetScript("OnEvent", function()
    if FrogLib.Loaded("PersonalResourceTweaks") then return end
    if not (TooltipDataProcessor and Enum.TooltipDataType) then return end
    local function AddID(tooltip, data)
        local spellID = data and data.id
        if issecret(spellID) or not spellID then return end
        tooltip:AddLine("Spell ID: " .. spellID, 0.5, 0.8, 1)
    end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.UnitAura, AddID)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, AddID)
end)
