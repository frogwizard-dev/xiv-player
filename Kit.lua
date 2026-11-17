local ADDON, ns = ...

-- What every file uses: FrogLib's settings controls (every change calls ns.Refresh), and the bar
-- textures and fonts the settings offer (FrogLib's Media), this addon's own fonts listed first.
ns.UI = FrogLib.UI.Kit({ refresh = function() ns.Refresh() end })

local FONTS = "Interface\\AddOns\\" .. ADDON .. "\\Fonts\\"
ns.Media = FrogLib.Media.New({
    fonts = {
        { "Michroma (wide)", FONTS .. "Michroma.ttf" }, -- wide, like FFXIV's gauge numbers
        { "Source Sans 3 (Myriad-like)", FONTS .. "SourceSans3.ttf" },
    },
})
