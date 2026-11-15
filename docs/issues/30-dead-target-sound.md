# Issue #30: dead-target deselection sound

Implemented on the shared `issue-fixes-1.6.1` branch for release 1.6.1.

The opt-in setting `muteDeadTargetSound` is off by default. It is exposed as
**Mute target-clearing sound** in the native settings layout and the fallback
Target markers tab. Hardware-click preparation mutes only FileDataID 567520
(`Sound/Interface/iDeselectTarget.ogg`) when the prepared targeting macro
contains `/cleartarget`, or replaces a readable dead NPC. The macro bytes and
targeting behavior are unchanged.

## Follow-up on repeated clicks

The maintainer reported alternating silent and audible clicks. The old
eligibility check required a dead NPC at the start of PreClick. It therefore
skipped a search that began without a target, acquired a corpse with
`/targetexact`, and cleared it with `/cleartarget [dead]` in that same action.
The initial target could also be alive while a later match was dead.

An automated regression reproduced the eligibility failure with alternating
dead/no-target states and the real master button click handlers. The revised
check also inspects the planned clearing commands. It preserves the existing
100 ms timing and serial-based cleanup instead of assuming a timing problem.
The setting text now reflects that an explicit search can also clear a living
initial target. Direct living-target selection, marker-only actions, a player
target, unreadable data, and the disabled setting remain outside suppression.

The Forever TargetFrame source was rechecked. `OnHide_TargetFrame` plays the
lost-target effect, while `PLAYER_TARGET_CHANGED` uses separate selection
sounds. This supports the proposed mechanism, but does not establish which
sound the maintainer heard or prove the duration sufficient in-game.

The maintainer subsequently confirmed that the repeated-click fix works in
their client. A remaining acquisition sound was reported. The setting mutes
the lost-target file only; native target-selection sounds remain audible.
A visible nameplate can be checked for death before selection, but a name
search can only confirm its match's state after selecting it. Consequently,
this option cannot selectively suppress acquisition audio only for dead
matches. This is a limitation of the current per-click deselection mute,
not a claim that all target-selection audio is impossible to mute globally.
The player-facing notice is recorded in `docs/curseforge/1.6.1.md`.

Covered input paths: master, focused quest, quest rows, Questie target buttons,
RestedXP, and the ItemTree target button/hotkey. Combat preparation reads the
already configured macro and does not write protected attributes. Standalone
action-bar macros do not pass through these handlers and are excluded.

Each qualifying input renews a 100 ms window. Only one mute is acquired across
overlapping clicks; stale cleanup timers cannot release a newer window. Timer
scheduling failure and PLAYER_LOGOUT (including normal UI reload) release the
addon's mute. Missing APIs or unreadable unit data leave audio untouched.

This is a file-level mute, so another playback of the same file in that window
is also suppressed. The duration is a conservative starting value, not a
measured guarantee about native event delivery. A real-client check is required
for each flavor: dead NPC to live NPC, dead NPC to no match, living target
changes, repeated clicks, combat, option off, and reload during suppression.
No in-game verification is claimed.

References consulted:

- Local XERJ lookup for `MuteSoundFile Core.ClickMacro` could not run: XERJ is
  not installed. Native UI sources and local `rg` were used instead.
- Blizzard TargetFrameMixin, `PLAYER_TARGET_CHANGED` and
  `OnHide_TargetFrame`/Classic `OnHide`: the lost-target sound is distinct from
  the selection sounds. See [Blizzard UI source](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_UnitFrame/Mainline/TargetFrame.lua).
- The extracted sound listings identify iDeselectTarget as file 567520 for
  [Retail](https://www.wowhead.com/sound=206823/ideselecttarget) and
  [Classic](https://www.wowhead.com/classic/sound=900/interfacesound-losttargetunit).
  SoundKit IDs differ from this FileDataID and must not be passed as file IDs.

Automated coverage checks the real Lua click preparation, unchanged 255-byte
macro text, dead/living/player/absent/secret targets, disabled/missing APIs,
overlapping cleanup, timer failure, logout, combat attribute preservation, and
native/fallback settings, six consecutive alternating dead/no-target search
clicks and explicit clearing searches starting with a living target. The full
suite passed 231 tests. Mocks establish lifecycle behavior, not audio output.
