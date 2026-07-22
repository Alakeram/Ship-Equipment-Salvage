# Ship Equipment Salvaging

**Author:** Alakeram  
**Game:** X4: Foundations 9.00  
**Release:** v3.70<br>
**Scope:** Production S/M salvage, native refitting, persistent inventory, and Black Market trading

**Public release notes:** [PUBLIC_RELEASE_CHANGELOG.md](PUBLIC_RELEASE_CHANGELOG.md)

Ship Equipment Salvaging adds a close-range EVA salvage and refit loop to X4.
Strip working equipment from eligible ships, keep the exact recovered parts in
a persistent inventory, weld them onto player-owned S/M ships, or trade them
through a dedicated Black Market parts network.

Shipyards call it theft. Scrappers call it recovery. The Black Market calls it
demand.

## What Was Fixed in v3.70

- Fixed saved weapons, shields, and turrets being rejected when older or
  user-provided saves stored their ware and macro identity in a different X4
  value shape.
- Fixed final installation rejecting equipment when the ship already had one
  or more copies of the exact same weapon, shield, or turret installed.
- Preserved exact compatibility, slot, post-install gain, inventory, and
  Bonding Catalyst safety checks.
- Live-tested save slot 2 without saving: the target installed both planned TER
  beam turrets from 2/4 to 4/4, and the complete plan finished 7/7 with zero
  skipped rows.

## What Was Fixed in v3.68

- Fixed the native salvage-results window displaying raw localization tokens
  instead of the result status and recovery reason.
- Resolved Mission Director text before passing stored values, result tables,
  and labels into Lua or native UI surfaces.
- Applied the same localization-boundary repair to operational gate messages,
  notifications, the tool-mode choice, Black Market labels, salvage
  confirmation, and result counters.
- Kept inventory accounting, catalysts, planner behavior, ship mutations, and
  existing translated catalog wording unchanged.

## What Was Added in v3.67

- Restored installed weapons, shields, engines, thrusters, and turrets to the
  native top-right Overview panel in the read-only salvage and welding menus.
- Added compact maker prefixes such as `ARG`, `BOR`, `PAR`, `SPL`, `TEL`, and
  `TER` to equipment captions without duplicating prefixes already supplied by
  X4.
- Kept equipment tiles inside their native two-line layout: the fitted X4 name
  stays on the first line and `Saved: N` or `Installed: N` stays on the second.
- Restored literal extension name and description metadata so the Extensions
  menu no longer displays unresolved localization references.

## What Was Fixed in v3.64

- Fixed compatible saved weapons and shields being accepted by the planner but
  rejected during installation.
- Applied the same typed-macro and complete-category planning repair to
  turrets, preventing an empty-slot install from replacing an existing row.
- Kept inventory and Bonding Catalysts unchanged unless the requested item and
  total loadout both gain exactly the planned quantity.
- Added the production translation catalog and routed player-facing SES text
  through X4 text page `1171361`.
- Fixed formatted completion and confirmation text appearing as raw references
  such as `{1171361,625}` in the logbook.

## What Was Added in v3.61

The complete salvage and welding workflow now uses X4's native Ship
Configuration interface through Kuertee UI Extensions:

- Select weapons, shields, engines, thrusters, and turrets through native
  category and slot controls.
- Preview every accepted weld or salvage choice immediately on the 3D ship,
  Overview panel, category gauges, icons, and Ship Statistics.
- See live saved-stock quantities, catalyst costs, reservations, and remaining
  inventory while building a plan.
- Use one **Install Loadout** action to open the final detailed weld
  confirmation.
- Confirm salvage through X4's compact native question window, with a safe
  **Back to Plan** option.
- Prevent incompatible equipment, missile/gun slot mismatches, duplicate stock
  reservations, occupied-slot replacement, and over-capacity plans before
  mutation.
- Process confirmed work for one second per planned item, with a three-second
  minimum and fifteen-second maximum. You can move normally, but must remain in
  EVA and within 100 m until the operation completes.
- Block either regulator while a confirmed weld or salvage operation is still
  running.
- Receive clear HUD feedback for range, ownership, active pilots, boarding,
  unsupported ships, invalid targets, missing tools, cooldowns, full equipment,
  and empty salvage targets.
- Receive weld-completion feedback with a list of successfully attached items.

The native planners are public and always enabled. They are no longer behind an
experimental setting.

## Core Features

- Salvage installed equipment from eligible S and M ships.
- Preserve exact equipment identity, including ware, macro, manufacturer,
  faction restrictions, size, and Mk tier.
- Store recovered parts in a persistent salvage inventory that survives
  save/load.
- Browse salvaged parts from the Player Information menu.
- Drop salvaged items into secure containers when needed.
- Build multi-item salvage and installation plans before committing anything.
- Use native Ship Configuration categories, slot tabs, filters, component
  previews, Overview changes, and statistics.
- Revalidate target state, range, inventory, catalysts, slot capacity, exact
  macros, and post-mutation counts before spending or crediting resources.
- Review successful and failed salvage results after extraction.
- Install only into empty, compatible slots on player-owned S/M ships.
- Recover and install these production equipment categories:
  - weapons;
  - shield generators;
  - engines;
  - thrusters;
  - turrets.
- Use illegal Avarice regulator tools and consumable catalysts from Black
  Market contacts.
- Unlock a dedicated salvaged-parts shop after the first successful recovery
  and delayed GalNet report.
- Sell recovered parts, buy back previously sold equipment, and purchase
  rotating official S/M equipment stock.
- Preserve player-sold quantities independently when generated dealer stock
  rotates.

## Salvage Workflow

1. Obtain the **Avarice Beam Regulator** and Beam Catalysts through the Black
   Market.
2. Approach an eligible S/M ship in your spacesuit.
3. Select the Beam Regulator mode and strike the hull with the EVA Hand Laser.
4. Use the native Ship Configuration screen to choose installed equipment for
   removal.
5. Watch the model, Overview, gauges, statistics, catalyst total, and pending
   plan update with each click.
6. Select **Complete Salvage**, review the compact confirmation, and begin the
   operation.
7. Remain in EVA and within 100 m during the dynamic three-to-fifteen-second
   work phase.
8. Review the results and recovered inventory after the verified mutation
   scheduler finishes.

## Welding Workflow

1. Obtain the **Avarice Bonding Regulator** and Bonding Catalysts.
2. Approach a player-owned S/M ship in your spacesuit.
3. Select the Bonding Regulator mode and strike the hull with the EVA Hand
   Laser.
4. Choose compatible salvaged equipment through the native slot and category
   controls. Occupied slots cannot be replaced; salvage the installed component
   first.
5. Preview each accepted component immediately and monitor saved stock and
   catalyst costs.
6. Select **Install Loadout**, review the detailed Apply Plan window, and
   confirm.
7. Remain in EVA and within 100 m until the dynamic work phase completes.
8. Receive a completion notice and installed-item list after exact ship,
   inventory, and catalyst changes are verified.

## Eligible Targets and Safety Rules

Salvage supports eligible S/M ships that are:

- abandoned or ownerless;
- player-owned;
- not wrecks or construction frames;
- not involved in an active boarding operation;
- within regulator range while the player is in EVA.

Welding is limited to player-owned S/M ships. Active faction ships and occupied
foreign ships are not free loot: ownership, pilot, boarding, range, and target
state are checked when the tool is fired and again before mutation.

Leaving EVA, changing sector, losing the target, or drifting beyond 100 m
during confirmed work cancels the operation before equipment or catalysts are
changed.

## Balance and Economy

- Regulators and catalysts are illegal Black Market goods.
- Salvage consumes Beam Catalysts; installation consumes Bonding Catalysts.
- Extraction success depends on equipment grade:
  - Mk1: 94%;
  - Mk2: 86%;
  - Mk3: 80%;
  - Mk4: 64%.
- A failed extraction can still strip the source component without producing a
  usable recovered part.
- Black Market sales pay 60% of average ware value.
- Dealer purchases and buybacks cost 120% of average ware value.
- Each eligible contact carries 4-10 generated equipment rows that refresh
  every 3-5 in-game hours.
- Player-sold buyback quantities persist independently of generated-stock
  rotation.

## Requirements

- **X4: Foundations 9.00**
- [Kuertee UI Extensions and HUD](https://www.nexusmods.com/x4foundations/mods/552),
  v9.0.0.8 or newer. Use the latest available build containing the Ship
  Configuration callbacks.
- [SirNukes Mod Support APIs / Simple Menu API](https://steamcommunity.com/sharedfiles/filedetails/?id=2042901274)
- [Options Helper 1.10 or newer](https://steamcommunity.com/sharedfiles/filedetails/?id=3715253556)

The dependency IDs are enforced by `content.xml`. SirNukes support APIs remain
a manifest requirement for support/options and compatibility paths; the public
salvage and welding planners themselves use the native Ship Configuration UI.

## Installation

1. Install and enable every requirement listed above.
2. Extract the release archive into the X4 `extensions` directory.
3. Confirm the final path is:
   `X4 Foundations/extensions/ship_equipment_salvaging/content.xml`
4. Enable **Ship Equipment Salvaging** in X4's Extensions menu.
5. Restart X4 when requested.

For a clean update, fully close X4 before replacing the existing
`ship_equipment_salvaging` folder. Keep Kuertee's Protected UI mode enabled.

## Compatibility and Scope

- Built as a proper X4 extension; no vanilla files are modified.
- SES-specific UI behavior remains inside the SES extension and consumes
  published Kuertee UIX callbacks.
- Kuertee UI Extensions itself is not patched by the release package.
- Current tested gameplay scope is S and M ships.
- L/XL recovery, detailed component condition, automation, and salvage-fleet
  gameplay remain future scope.
- Deployables, countermeasures, mines, satellites, probes, beacons, internal
  wares, restricted ship-specific equipment, and L/XL dealer equipment are not
  treated as normal recoverable S/M components.
- The extension stores persistent state in saves. Back up important saves
  before installing or removing save-persistent mods.

## Translations

SES reserves X4 text page `1171361` and ships an English fallback catalog at
`t/0001.xml`. Community translators can add a language file without editing
gameplay code; German uses `t/0001-l049.xml`.

See [TRANSLATING.md](TRANSLATING.md) for the file naming convention,
placeholder rules, validation requirements, and test checklist. Translation
files must preserve all text IDs and `%s`/`%d` format tokens.

## Troubleshooting

- **No planner opens:** verify all requirements are enabled, keep Protected UI
  enabled, and restart X4 after changing extension state.
- **The regulator reports it cannot reach the mounts:** move closer to the
  target.
- **Equipment slots are full:** salvage an installed component before welding a
  replacement.
- **No items left to salvage:** the target has no supported recoverable
  equipment remaining.
- **Work is interrupted:** remain in EVA, in the same sector, and within 100 m
  until the timer completes.

## Credits

- **Alakeram** - design and development.
- **Kuertee** and UI Extensions contributors - shared UI callback framework.
- **SirNukes** - Mod Support APIs.
- **JLPH / Options Helper contributors** - extension options framework.

## Short Storefront Description

Recover exact weapons, shields, engines, thrusters, and turrets from eligible
S/M ships, store them in a persistent salvage inventory, preview and install
them through X4's native Ship Configuration interface, or trade them through a
dedicated Black Market parts network.
