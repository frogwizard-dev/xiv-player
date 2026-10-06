# XIVPlayer

## 0.6.0

### Mana in real time
- The MP gauge and its number now move in real time, the way Blizzard's own mana bar does, instead of jumping every couple of seconds. The gauge eases smoothly to each new value.
- New: your **mana regen** after the MP number, live (for example "+7.5/s"), straight from the game's own figure (the character sheet's Mana Regen). It can show per 5 seconds instead ("+37 mp5").
- New: the **five-second rule**. After you spend mana a thin strip fills under the MP gauge for the five seconds until your regen starts again, and the regen number dims meanwhile.
- Both are on the Text tab and can be turned off. They follow your mana onto the extra MP gauge in bear and cat form.

### Swing timers
- New **Swing timer** tab: main hand, off hand (when you dual wield) and ranged timers in the same FFXIV look as the cast bar (same gauge style, texture and font, the hand's name on the left and the time to your next swing on the right).
- Show them in combat, with an enemy targeted, either, or always. Each hand can be turned on or off, and the size, colours, name and time text are yours to set.
- Out of range of your target, a timer dims and its time turns red.
- Can hide Blizzard's own swing timers.
- Off until you turn it on. Unlock the bar (Layout tab) to see samples and drag the timers where you want them.

### HP and MP further apart
- The gap between the HP and MP gauges now goes up to the width of your screen, with a slider. With a wide gap the two sit either side of your action bars, which suits gamepad players. A new button centres the bar across the screen so they spread out evenly. Shift-click - or + for bigger steps.
- Clicking the gauges to target yourself now only works on the gauges themselves, so the space between them (your action bars) gets its own clicks.
- Existing layouts don't change.

### Fixes
- The cast bar no longer errors when the game hides the spell's start and end times: the latency shade is simply left off for that cast. While unlocked, a cast of yours shows over the sample.
- **Hide Blizzard's cast bar** now works with the gamepad interface. The game uses a separate cast bar in gamepad mode, and only the usual one was being hidden.
- **Hide Blizzard's cast bar** and **Hide Blizzard's player frame** now hold during combat as well. Before, when the game re-laid out the bottom of the screen mid-fight, Blizzard's cast bar could come back until the fight ended. They're now also hidden again after loading screens and Edit Mode layout changes.
- With Blizzard's cast bar locked under the player frame (Edit Mode), hiding the player frame no longer hides that cast bar along with it.
- Hiding Blizzard's frames now goes through code shared with the other Frog Wizard add-ons, so two of them hiding the same frame (FrogUI or FrogFrames hiding the player frame, say) agree: it stays hidden until neither wants it hidden. A cast bar you lock under the player frame while it's hidden now stays on screen too.
- The spell ID line on tooltips no longer causes an error when the game hides an aura's spell.
- HP and MP number templates with more than six words now keep updating.

### Under the hood
- The click buttons, power colours, percentages and text templates are FrogLib's, shared with the other Frog Wizard add-ons.

## 0.5.3

### Under the hood
- Shares its options page and its texture and font lists with the other Frog Wizard add-ons (one copy of the code, so a fix reaches them all at once). Nothing changes in how it looks or works.

## 0.5.2

### Options
- Listed with the rest of Frog Wizard's add-ons: under a "Frog Wizard" heading in the AddOn list, and in its own "Frog Wizard" section of Options > AddOns, whose page lists them all with a button to each one's settings.

## 0.5.1

### Fixes
- Fixed a "file not found" font error after EllesmereUI is turned off or removed while its font (Expressway) is chosen. The game's standard font is used until you pick another.
- Hiding Blizzard's player frame now works alongside other add-ons that hide it the same way, instead of the two undoing each other.

## 0.5.0

### Mana in forms
- In a druid's bear or cat form, a third **MP** gauge beside the form's resource shows the mana you'll have back in caster form. Shadow priests and Elemental shamans get it too.
- Can be turned off on the Layout tab ("Show my mana in forms").

### Blizzard's player frame
- New **Hide Blizzard's player frame** setting (Layout tab), off by default. Your pet frame and totems stay where they were. Turned on or off in combat, it takes effect once combat ends.

## 0.4.2

### Debuffs
- New **Hide if over** setting (Debuffs tab): hides debuffs lasting longer than the minutes you choose, e.g. 30 to hide Boosted Rest's hour. Combat debuffs and short lockouts still show.
- The game only lets addons hide a few of your own debuffs by name, so the "Debuffs to hide" list often can't hide one (like Boosted Rest). The Debuffs tab now says so and points to Hide if over.

## 0.4.1

- No changes in the game. From this version, releases are published automatically to CurseForge and GitHub.

## 0.4.0

### Cast bar
- Shows your latency: the end of the bar your connection takes up is shaded (on the left for channels), so you can see when it's safe to queue your next cast. Its colour can be changed.
- Can show the spell's icon to the left of the bar, at a size of your choosing.

### Options
- Now listed in the game's Options > AddOns, with a button that opens its settings and a list of its slash commands.

### Fixes
- Fixed a "forbidden object" error that could appear when status-effect text updated in restricted content (for example in combat).
