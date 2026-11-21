# RareScanner minimap targeting (Forever)

Adds an automatically enabled integration to QuestTargets when RareScanner is
installed on Forever. Plain left-click attempts `/targetexact` with the localized
NPC name. It does not clear the existing target, mark a target, or target on hover.
Treasure, event and world-map pins are excluded.

Source references inspected in the installed Forever RareScanner:

- `Core/Service/RSMinimap.lua`: `AddMinimapPin` assigns `pin.POI`, and uses
  `HereBeDragons-Pins-2.0:AddMinimapIconMap` for pooled minimap frames.
- `Core/Plugins/MapPlugin/RSMinimapPinTemplate.xml` and
  `RSMinimapPinMixin.lua`: minimap frames expose `OnEnter`/`OnLeave` tooltips
  but have no secure targeting action.
- `Core/Service/POI/RSNpcPOI.lua`: NPC POIs provide `isNpc` and localized `name`.
- QuestTargets `Core.SafeName` validates names before building the macro.

XERJ retrieval was attempted. The local project indices were absent and the
reference corpus had no live indices. Native WoW UI-source retrieval was also
unavailable, so the installed source and local `rg` reads supplied references.
No upstream implementation was copied.

A single secure button uses a separate UIParent child as its combat visibility
gate. It is positioned using screen coordinates, never parented or anchored to
pooled RareScanner pins. This avoids making their pool protected. A state driver
hides the gate during combat; all insecure mutations return during lockdown.
Leaving combat discards the previous hover target. The overlay forwards original
tooltip scripts, validates reused POIs, and follows pin movement at 20 Hz.

Verification: Lua 5.1 behavior tests cover name targeting, macro injection,
pool reuse, hidden pins, new pins, foreign pins, combat guards and client gating.
The package test verifies that the integration file is included. WoW MCP lint
reports no errors but conservatively flags combat mutations despite their guards;
live-client secure execution and mouse/tooltip behavior still need an in-game test.

The RareScanner PostClick handler now displays a brief expanding ring at the pin.
It is independent of the target result and stays centered where the click occurred.
The minimap mouse-up hook also checks visible RareScanner pins when the native
minimap receives the click. It displays the pulse and prepares the secure
button for the next click. The native click itself remains a minimap action.
The XERJ search for `RareScanner PostClick` located the existing click path.

The world map button follows active spawn overlays. RareScanner's
`RSEntityPinMixin:ShowOverlay` and `RSGroupPinMixin:ShowOverlay` add entries to
`RSGeneralDB.AddOverlayActive` and acquire `RSOverlayTemplate` pins. Quest
Targets observes `RSOverlayMixin:OnAcquired` for the NPC identity and reads the
AceAddon instance's character overlay state. It never writes RareScanner data.
Known NPC names and locale are retained only while the corresponding overlay
is active. `UI.LayoutTargetButtons` (located via XERJ) includes the purple
compass with the other target buttons. With no resolved marked NPC the compass
is gray and has no targeting action. The button searches all active marked
NPC names using the existing `Core.EntryMacro` builder (located via XERJ).
If the list exceeds the macro budget, later clicks continue at the next name.

Zone search is opt-in. It uses the player's UI map from
`C_Map.GetBestMapForUnit("player")` and reads the NPC filter entries built by
RareScanner's installed `RSWorldMapButtonMixin:SetupMenu`. That menu reads
`RSNpcDB.GetActiveNpcIDsWithNamesByMapID`, including undiscovered NPCs. Quest
Targets supplies a menu description collector and never invokes the filter
callbacks. This bridge depends on RareScanner's menu structure and the
client's dropdown generator. If the reader fails, the zone button stays idle
until a successful refresh. XERJ did not locate this upstream path, so the
references are the installed RareScanner source and
[Blizzard's dropdown implementation](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Menu/DropdownButton.lua).

In party instances, the zone option merges native floor maps from
`C_Map.GetMapGroupMembersInfo` with RareScanner's synthetic dungeon map IDs.
The latter are keyed by the instance map ID from `GetInstanceInfo`. The
crosswalk follows the installed RareScanner `Tables/DungeonMapsTables.lua`
and `Tables/ZoneTables.lua`. RareScanner's `RSEventHandler` also uses these
synthetic maps for Dungeon NPCs. Classic wings can share one instance map
ID, so their lists are combined and normal targeting range still applies.
XERJ returned no matches for the search entry and zone reader.

The RareScanner hotkeys share the native binding path used for ItemTree in
`UI.lua` and `Bindings.xml`. Both slots invoke the same secure click as the
bar button. Its state driver disables the action during combat, and the
button remains visible in its slot. The separate minimap overlay still uses
its own combat visibility driver. The XERJ reference corpus was unavailable,
so the existing local ItemTree binding served as the reference.

Before replacing the macro on a bar click, RareScanner uses
`Core.ValidCurrentTarget` to check that the current target is a living NPC
in the active list. A valid target suppresses that click's macro and leaves
the page cursor in place. XERJ located the shared target check in `Core.lua`.

The button reads spawn markers through the installed RareScanner
`RSExplorerRareList:OnElementSelectionChanged` on a local drawing surface.
It also reads active overlay coordinates from `RSOverlayMixin:OnAcquired`
and uses the last sighting when no spawn point is available. None of these
paths opens RareScanner UI or changes its filters or marks. Map points are
projected to world coordinates and ranked by the closest point per name.
Unprojectable points (including synthetic dungeon maps) use the existing
QuestieDB distance or alphabetical fallback. XERJ did not locate the current
ordering code, so the reference is `QuestTargets/Proximity.lua` and the
installed `Core/Plugins/ExplorerPlugin/RSExplorerMixin.lua`.

Only out-of-combat search clicks and bindings read the player position. After any
movement, the next macro starts at the top of the list even if the ranking
hasn't changed. Stationary clicks continue with the next macro page. Both
the RareScanner button and the shared click path use the position sampler.
XERJ located the shared click path in `QuestTargets/Core.lua` and the
distance sorting in `QuestTargets/Proximity.lua`.
