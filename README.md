# Gondor PvP

A PvP card binder and guild help system for **Gondor Calls for Raid** on WoW Forever. The addon targets interface 16001 and has no required addon dependencies.

**Compatibility status:** The rules and interface have offline tests, but gameplay has not been verified in a live Forever client. In particular, automatic PvP death classification, custom-channel sending, map pins, and precise distance data depend on the APIs the live client makes available. Test these with guildmates before depending on points or distributing this as a final release.

## Download

**[Download Gondor PvP 0.9.15 beta (78.1 MiB ZIP)](https://github.com/GM-King/Gondor_pvp/releases/download/v0.9.15-beta/Gondor_PvP.zip)**

Visit the [Gondor PvP website](https://gm-king.github.io/Gondor_pvp/) for installation instructions and an overview.

The player ZIP includes the card catalog and all textures. The public source contains gameplay code and website files. Card identities, artwork and review materials are retained locally and excluded from Git history. To run a source checkout, install the matching player ZIP first and overlay the source files.

## Getting started

1. Install the `Gondor_PvP` folder in the Forever `Interface/AddOns` directory and enable it at character selection.
2. Type `/gpvp` to open the card binder. Right-click the female orc minimap button for Menu, Personal KoS and Guild KoS. Left-click it for Muster Rohirrim (Zone) or Light Beacons (World). Settings remain available in the binder.
3. Open Settings and opt in to **PvP death alerts** and/or **incoming Kill Share offers**. Both are off by default. The default announcement channel is `gcfrpvp`; the addon joins it when sending. Choose a different custom channel, `GUILD`, `PARTY`, or `RAID` in settings.
4. Configure incoming offer expiry from 5 to 60 seconds; the default is 60.

## Cards

Lifetime honorable-kill milestones unlock 69 cards for each character. The first unlocks at 5 kills and the last at 1,000. Unlocks are derived from the character's game-reported lifetime total. Existing lifetime kills count when you join the guild with the addon enabled. Unseen cards show only a question mark in the binder; click an unlocked card to inspect it. Multiple newly earned cards appear in a queue.

## Alerts and Kill Share

With PvP death alerts enabled, confirmed and uncertain PvP deaths ask whether to request help. Choose **Muster Rohirrim (Zone)** for online guildmates in your zone or **Light Beacons (World)** for the whole guild. Both announce your zone and death coordinates in the configured channel. Your own character is excluded. **Decline**, Escape, or letting the prompt expire sends nothing. Declining a later death leaves any earlier request and responding helpers active. Open **Kill Share** in the binder to request help and see your active fare and responding guildmates, or use `/gpvp request` to choose an audience. Manual requests have a ten-minute cooldown; each new death reduces the remaining cooldown by five minutes.

Incoming fare popups appear at the lower right and wait until combat ends. Expiry continues while hidden, so expired or withdrawn offers do not reappear. Upgrading changes the former 15-second default to 60 seconds once; other saved durations are preserved. Character names are displayed without realm suffixes.

Guildmates who enabled offers receive a popup with the requester's name, race, class, location and potential reward. Multiple helpers may accept a request, but each helper can hold only one accepted fare at a time. `/gpvp cancel` cancels your accepted fare; `/gpvp cancelrequest` withdraws your own request. These controls are also in the Points panel. The map marker follows the requester's position after resurrection.

Cancellation notices are retried for up to 24 hours, including after a reload, until the other player's addon acknowledges them. Automated messages wait for confirmed online status, and player-not-found feedback stops further attempts until fresh online evidence arrives. Both players need to come online within that period for a missed notice to be delivered; a player can always cancel a fare locally.

When another death updates an active request, existing helpers keep their original quoted rewards. If the newer alert has not expired when a helper finishes or cancels the earlier fare, it appears as a new offer; the ten-minute pair limit still applies. Guildmates should use the same current release for reliable handling of these repeated alerts.

To complete a fare, both characters must be alive, in the same phase, within five feet, and visible to each other's addons. If the game cannot identify a nearby player automatically, both players should target each other. If the client withholds exact three-dimensional positions, the addon leaves the fare pending and does not award points. Requests and fares expire 30 minutes after the original request. Later alerts cannot extend that deadline. They survive UI reloads but are cancelled when either participant logs out; one helper leaving does not cancel other helpers. The Kill Share window shows time remaining.

## PvP Points

Points are a non-spendable tally earned only for fulfilled Kill Shares. The offer quotes the reward at acceptance from straight-line travel distance: 10–20 points in the same zone, 21–49 in a different zone on the same continent, and 50 on a different continent. A helper earns points from the same requester at most once every ten minutes. A repeat fare can still be fulfilled for zero points.

Points and card presentation records are saved per character. Guild receipt backups provide recovery when an updated guildmate has a copy. The addon rejects duplicate completions and checks guild membership and proximity, but a player who controls their local addon files can alter local data. No addon-only mechanism can make those files tamper-proof.


## Updates, reinstalls and a second computer

Replacing or deleting only Interface/AddOns/Gondor_PvP preserves WoW's separate character save. Existing settings, card reveals and fare points load again after reinstalling. Cards now unlock for every character from the game-reported lifetime honorable kills, including characters outside the guild. A fresh character save reveals all earned cards in order, one at a time as you close each card.

Version 0.9.3 automatically backs up completed fare receipts through other guild members running this version. Existing receipts are shared when you upgrade. Online guildmates keep account-wide copies separately from their own points. On login, the addon asks for your character's missing receipts and repeats the request about every two minutes. Restored receipts merge with your local history without counting a fare twice. The Points panel shows your known balance and whether a guild backup has responded. Kill Share still requires Gondor Calls for Raid membership.

Before changing computers or discarding a save, run the update on the original computer alongside an updated guildmate and allow the backup transfer to finish. Recovery requires a guildmate who received a copy to come online again. Fare history is shared within the guild. Settings, card presentation history and active fares stay in your own character save. These peer copies are trusted guild data and are editable local files.

For an independent backup, exit WoW completely and copy WTF/Account/<account>/<realm>/<character>/SavedVariables/Gondor_PvP.lua to the corresponding character directory on the other computer. Copy the account-level WTF/Account/<account>/SavedVariables/Gondor_PvP.lua too if you want to transfer guild backup copies. Keep both files outside the game folder as a backup. If every copy of a fare receipt is lost, honorable kills cannot restore its points.

## Commands

- `/gpvp` or `/gondorpvp`: open the binder.
- `/gpvp settings`: configure alerts, offers, channel and expiry.
- `/gpvp request`: choose Zone or World help.
- `/gpvp retry`: retry a failed announcement within ten seconds without repeating guild offers. The Kill Share panel also has a Retry announcement button.
- `/gpvp status`: show channel readiness, settings, cooldown, last death classification and delivery outcomes.
- `/gpvp cancel`: cancel your accepted fare.
- `/gpvp cancelrequest`: withdraw your own request.
- `/gpvp help`: show command help.

Version 0.9.5 enables death/fare alerts and incoming Kill Share offer popups by default for new character settings. Existing saved on/off choices are preserved.

## Development and verification

The source project retains the original card images, build scripts, offline tests and review sheets under `reference_images`, `Development` and `tests`. Run `Development/build_cards.ps1` to regenerate the card atlases and review sheets, then `Development/verify_atlases.ps1` to compare every atlas cell with its full-size review image. Run `python -B -m unittest discover -s tests -v` from the addon directory to run the Lua 5.1 tests; the supplied tests use the adjacent PetMaxxing test runtime. Run `Development/build_release.ps1` to create a distribution ZIP excluding source images, previews and tests.

Before release, verify in Forever: addon loading and saved settings; card reveals and locked binder slots; death detection and channel delivery; offers and expiry; Zone/World audiences, including party and raid members; simultaneous helpers; world-map and minimap pins; player position and phase checks; cancellation and reconnect; and correct one-time rewards. Test both same-zone and cross-continent fares.

The source project's `Development/FOREVER_TEST_GUIDE.md` provides a detailed guild test procedure and result-recording checklist.


## 0.9.11 beta — shared Kill on Sight

Open **Kill on Sight** in the binder or use `/gpvp kos`. Gondor members can right-click an identifiable Alliance target portrait and choose **Gondor KoS**. Reasons allow 100 characters and cannot be edited after addition. Click a name to see its reason, contributor, race, class and last-seen level. Missing attributes display as Unknown until observed. Manual deletion requires confirmation. Entries expire after ten days without a newer guild sighting; editing a reason does not extend that time.

The shared list holds 100 active players. Nearby nameplates, targets, focus and mouseover provide open-world sightings when the client exposes identities. Sightings update across the guild through paced addon messages. Each member hears the supplied warning locally, while coordinated channel announcements have a ten-minute cooldown per target. The KoS window has a local sound toggle.

A verified player/pet killing blow on an active KoS target adds five points. Distinct later kills can award again. KoS reward receipts survive reload and are backed up through updated guildmates. Restricted or missing killer/victim identifiers cannot award points; inspect KoS status and record this as a blocked live test. Existing fare rewards remain separate.

This beta includes the shared Kill on Sight list. Offline checks pass; live-client compatibility still requires guild testing. No live verification is claimed.

Manual KoS removals announce the target and deleting member in `gcfrpvp`. The deleting player gets an Undo window for 60 seconds and can reopen it with **Undo deletes** in the KoS screen. The deadline survives reload. Undo restores the original reason, contributor, attributes and sighting time, and announces the restoration. A full list must have a slot freed before the deadline; an entry already replaced or deleted again cannot be undone. Automatic ten-day expiry stays quiet.

## KoS statistics and help audiences

The Guild KoS page has **Kill Leaderboard** and **Latest Kill** buttons. The leaderboard posts up to five guildmates by total credit across the current list. Latest Kill lists everyone credited at the newest kill time today, along with the target, time elapsed and who added the target. Today starts at realm midnight. Both reports post to guild chat.

Each target death counts once. Every guildmate the client can verify within 40 yards of the killer gets credit in the Guild Kill Breakdown and leaderboard, including guildmates outside the group. Only the killing blow earns five PvP points. Updated clients can share presence and show the full breakdown.

### Nearby KoS targets

The **KoS Targets** box appears at the top centre when a living KoS player is detected locally through a nameplate, target, focus or mouseover in the open world. Click a head portrait to target that player; hover for their name and KoS reason. Portraits remain for 30 seconds after detection is lost. A guild sighting alone does not open the box.

Drag the header outside combat to move it; the position is saved per character. The X dismisses the current encounter, including during combat. It automatically returns after all nearby targets have cleared and a fresh encounter begins. **Show nearby targets** in the Kill on Sight window reopens a dismissed encounter manually. During combat, existing portraits remain clickable while additions, removals and movement wait until combat ends. These controls require live Forever verification.

The KoS table has Name, Level, Last Seen, and Total Kills columns, class-coloured names, and a draggable scrollbar. Click a heading to sort; click again to reverse. Unknown levels stay last. The sort choice is saved per character. Click a target name for compact details and a separate scrollable Guildmate/Kills table. Guildmate names use roster class colours when available. Verified killing blows count once, and pets credit their owners. Totals cover the current listing: removing or expiring and freshly adding a target resets the total; Undo restores it. Earned points remain intact. Older kill records use the listing creation time as their cutoff. New KoS kills announce once in gcfrpvp; synchronization and backup recovery stay silent.

Zone offers use private addon messages to online guildmates whose roster zone matches the request zone. Subzones share their containing zone. Recipients must still be in the zone when the offer appears or is accepted. Unknown zone or roster data never causes a World broadcast. Both choices still post the configured-channel announcement. World offers include party and raid members. Saved offer opt-outs and instance restrictions still apply. Updated addons are required for Zone offers and precise listing attribution.

The death prompt offers both audiences and Decline, expires after 15 seconds, and uses the location captured at death. Escape and timeout send nothing. The minimap button uses the existing orc artwork on Horde red; dragging retains the saved position. Target/focus KoS crosshairs are now 36 pixels.

These changes are verified offline only; live Forever compatibility remains unverified.

## Request windows and fare tracker

Zone/World choices and death prompts open in the upper-middle. The X or Escape closes without requesting help; death prompts still expire after 15 seconds. Incoming offers stay bottom-right and show approximate straight-line yards to the requested location. Incompatible or unavailable locations show Distance unavailable.

Accepted fares appear in a compact bottom-right tracker, including while the binder is closed or during combat. It shows your requester and responding helpers, with distance updates. Positions older than ten seconds show Updating location. Each row's X cancels that fare only; other helpers and your request remain active. Drag the header to move it; the position is saved per character. Scroll to see more than five fares. Completion acknowledgements remain visible until finished. The minimap artwork and red background share a circular mask inside the existing border.

## 0.9.15 beta — KoS portrait targeting

Adds the movable nearby KoS Targets box and fixes its portrait clicks for Forever’s regional two-part names: `/targetexact First Lastname` now uses a space instead of the identity separator dash. Realm-qualified names on other clients retain their dash. Offline regression checks cover both name modes and combat deferral; live Forever verification remains pending.

## 0.9.16 beta — Personal KoS and guild kill reports

Right-click the minimap icon for Menu, Personal KoS or Guild KoS. Personal KoS is private to your account, shared across characters on the same realm, holds 1,000 enemies and has no expiry. Search it by name, add a first and last name with a reason, view kill history, remove entries, or push a verified enemy to Guild KoS. Existing additions made by each of your characters are imported as those characters log in.

Typed names remain unverified until a local living, visible open-world encounter supplies the matching player GUID. Encounters with unlisted enemies are remembered for this session. Proof attached to a personal entry survives reloads and is shared with your alts. An active Guild KoS entry also verifies the matching personal entry. A red [Guild KoS] badge beside its name shows current guild membership. Verification persists when the guild entry later expires or is removed. Portrait additions attempt both lists and report capacity or duplicate failures. Verified pushes can restore expired or removed guild entries, with earlier guild history and your characters’ private kills credited once. Private kills grant no points. Updated guild clients are needed to receive the new statistics-only history packets. Addon saves remain editable local data.

Personal-only targets trigger your local sound, crosshair and nearby portrait box. Guild announcements and five-point rewards require an active Guild KoS entry. Existing combat restrictions and the 30-second nearby sighting grace still apply. Live testing in WoW Forever is still pending.
