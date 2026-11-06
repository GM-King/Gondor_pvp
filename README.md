# Gondor PvP

A PvP card binder and guild help system for **Gondor Calls for Raid** on WoW Forever. The addon targets interface 16001 and has no required addon dependencies.

**Compatibility status:** The rules and interface have offline tests, but gameplay has not been verified in a live Forever client. In particular, automatic PvP death classification, custom-channel sending, map pins, and precise distance data depend on the APIs the live client makes available. Test these with guildmates before depending on points or distributing this as a final release.

## Download

**[Download Gondor PvP 0.9.4 beta (75.0 MiB ZIP)](https://github.com/GM-King/Gondor_pvp/releases/download/v0.9.4-beta/Gondor_PvP.zip)**

Visit the [Gondor PvP website](https://gm-king.github.io/Gondor_pvp/) for installation instructions and an overview.

The player ZIP includes the card catalog and all textures. The public source contains gameplay code and website files. Card identities, artwork and review materials are retained locally and excluded from Git history. To run a source checkout, install the matching player ZIP first and overlay the source files.

## Getting started

1. Install the `Gondor_PvP` folder in the Forever `Interface/AddOns` directory and enable it at character selection.
2. Type `/gpvp` to open the card binder. Left-click the murloc minimap button for the binder or right-click it for settings.
3. Open Settings and opt in to **PvP death alerts** and/or **incoming Kill Share offers**. Both are off by default. The default announcement channel is `gcfrpvp`; the addon joins it when sending. Choose a different custom channel, `GUILD`, `PARTY`, or `RAID` in settings.
4. Configure incoming offer expiry from 5 to 60 seconds; the default is 15.

## Cards

Lifetime honorable-kill milestones unlock 69 cards for each character. The first unlocks at 5 kills and the last at 1,000. Unlocks are derived from the character's game-reported lifetime total. Existing lifetime kills count when you join the guild with the addon enabled. Unseen cards show only a question mark in the binder; click an unlocked card to inspect it. Multiple newly earned cards appear in a queue.

## Alerts and Kill Share

An enabled death alert announces your zone and map coordinates and sends an addon request to your guild. If the client does not expose a reliable PvP classification, a confirmation asks whether to send the alert. Open **Kill Share** in the binder to request help and see your active fare and responding guildmates, or use `/gpvp request`. Manual requests have a ten-minute cooldown; each new death reduces the remaining cooldown by five minutes.

Guildmates who enabled offers receive a popup with the requester's name, race, class, location and potential reward. Multiple helpers may accept a request, but each helper can hold only one accepted fare at a time. `/gpvp cancel` cancels your accepted fare; `/gpvp cancelrequest` withdraws your own request. These controls are also in the Points panel. The map marker follows the requester's position after resurrection.

Cancellation notices are retried for up to 24 hours, including after a reload, until the other player's addon acknowledges them. Both players need to come online within that period for a missed notice to be delivered; a player can always cancel a fare locally.

When another death updates an active request, existing helpers keep their original quoted rewards. If the newer alert has not expired when a helper finishes or cancels the earlier fare, it appears as a new offer; the ten-minute pair limit still applies. Guildmates should use the same current release for reliable handling of these repeated alerts.

To complete a fare, both characters must be alive, in the same phase, within five feet, and visible to each other's addons. If the game cannot identify a nearby player automatically, both players should target each other. If the client withholds exact three-dimensional positions, the addon leaves the fare pending and does not award points. The request and fare can be cancelled; they survive ordinary addon reloads.

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
- `/gpvp request`: manually request help.
- `/gpvp cancel`: cancel your accepted fare.
- `/gpvp cancelrequest`: withdraw your own request.
- `/gpvp help`: show command help.

## Development and verification

The source project retains the original card images, build scripts, offline tests and review sheets under `reference_images`, `Development` and `tests`. Run `Development/build_cards.ps1` to regenerate the card atlases and review sheets, then `Development/verify_atlases.ps1` to compare every atlas cell with its full-size review image. Run `python -B -m unittest discover -s tests -v` from the addon directory to run the Lua 5.1 tests; the supplied tests use the adjacent PetMaxxing test runtime. Run `Development/build_release.ps1` to create a distribution ZIP excluding source images, previews and tests.

Before release, verify in Forever: addon loading and saved settings; card reveals and locked binder slots; death detection and channel delivery; offers and expiry; party/zone suppression; simultaneous helpers; world-map and minimap pins; player position and phase checks; cancellation and reconnect; and correct one-time rewards. Test both same-zone and cross-continent fares.

The source project's `Development/FOREVER_TEST_GUIDE.md` provides a detailed guild test procedure and result-recording checklist.

