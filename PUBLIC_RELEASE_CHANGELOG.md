# Public Release Changelog

This is the authoritative player-facing changelog for Ship Equipment
Salvaging. Entries are added only for an explicitly approved public release,
patch, or hotfix. Internal development versions are compiled into one entry
under the final public version rather than listed individually.

## v3.72 - 2026-07-26

**Localization update since public release v3.70**

### German Localization

- Added a complete German translation for all 191 SES text entries, covering
  the native salvage and welding planners, saved-parts inventory, Black Market,
  regulator tools and feedback, confirmations, results, and GalNet reports.
- Credited **TheSylance** for the community translation contribution.
- Normalized the contributed file to SES's required X4 diff-catalog structure
  and restored the one text entry added after the translation was started.

### GalNet Localization

- Added five localized GalNet announcements introduced after v3.70, including
  the initial salvaging report and the later Black Market parts-network story.
- Kept the announcement timing, unlock conditions, inventory, economy, and
  equipment behavior unchanged.

### Verification

- Validated all 18 XML files and the extracted X4 9.00 Mission Director, diff,
  and UI addon schemas.
- Confirmed exact English/German parity across 191 IDs, with no missing,
  duplicate, unknown, placeholder, or intentional-line-break mismatches.
- Built v3.72 and verified the packaged catalog against the canonical source
  and deployed runtime.

## v3.70 - 2026-07-22

**Gamebreaking install hotfix since public release v3.68**

### Saved Equipment Identity

- Fixed valid saved weapons, shields, and turrets from older or user-provided
  saves being rejected before compatibility planning when their ware or macro
  identity was persisted as an X4 object instead of a text ID, or vice versa.
- Added one shared resolver that prefers the authoritative persisted ware,
  supports legacy ID fallbacks, and canonicalizes macro objects and macro-ID
  strings throughout dropdown publication, inventory checks, plan creation,
  and final apply validation.
- Kept existing inventory rows intact merely by opening the save.

### Existing Matching Equipment

- Fixed final installation rejecting a weapon, shield, or turret when the ship
  already had one or more copies of that exact equipment macro installed.
- Validated the selected equipment total as the existing count plus the
  requested item, matching X4's regenerated complete-category loadout.
- Preserved slot snapshots, exact plan shape, post-apply equipment gain,
  inventory debit, and Bonding Catalyst debit safeguards.

### Verification

- Validated all 17 XML files and the extracted X4 9.00 Mission Director, diff,
  and UI addon schemas.
- Live-tested save slot 2 without saving: both planned TER beam turrets
  installed from 2/4 to 4/4, the matching shield case succeeded, and the full
  loadout completed 7/7 items with zero skipped rows.
- Built and deployed v3.70 with synchronized manifest and loose-UI runtime
  markers.

## v3.68 - 2026-07-20

**Hotfix changes since public release v3.67**

### Localization Results and Messages

- Fixed the native salvage-results window displaying unresolved text-page
  references such as `{1171361,703}` and `{1171361,722}` instead of the
  localized result status and recovery reason.
- Resolved localized text through Mission Director `readtext` before storing
  it in variables, lists, and result tables passed to Lua or native UI.
- Applied the same repair to tool-gate feedback, direct notifications, the
  tool-mode choice, Black Market labels, salvage confirmation, result counts,
  statuses, and reasons.
- Preserved text-aware X4 ware and macro references, catalog wording, planner
  behavior, inventory accounting, catalysts, and ship mutation logic.

### Verification

- Validated all 17 XML files and the extracted X4 9.00 Mission Director, diff,
  and UI addon schemas.
- Built and deployed the v3.68 package with synchronized manifest and loose-UI
  runtime markers.

## v3.67 - 2026-07-18

**UI and localization fixes since public release v3.64**

### Native Equipment Presentation

- Restored the ship's installed weapons, shields, engines, thrusters, and
  turrets to X4's native top-right Overview panel in the SES salvage and
  welding menus.
- Preserved fitted equipment rows while rebuilding the read-only SES catalogue,
  preventing unchanged hardware categories from disappearing from Overview.
- Added compact maker prefixes such as `ARG`, `BOR`, `PAR`, `SPL`, `TEL`, and
  `TER` to equipment names, while avoiding duplicate prefixes when X4 already
  provides one.
- Kept native equipment tiles inside their intended two-line geometry by using
  X4's fitted first-line caption and reserving the second line for the live
  `Saved: N` or `Installed: N` receipt.

### Extensions Menu

- Restored literal extension name and description metadata because X4's
  Extensions menu displays those manifest fields directly instead of resolving
  text-page references.

### Verification

- Confirmed in game that the native Overview shows engines, thrusters, shield
  generators, weapons, turrets, software, and consumables together.
- Confirmed equipment slots use the expected compact faction-prefixed names and
  the Extensions menu displays the expected extension metadata.
- Validated all 17 XML files and the extracted X4 9.00 Mission Director, diff,
  and UI addon schemas.

## v3.64 - 2026-07-18

**Hotfix changes since public release v3.61**

### Compatible Equipment Installation

- Fixed compatible salvaged weapons and shields being accepted by the native
  planner but silently omitted by X4's authoritative loadout generation.
- Resolved persisted ware and macro ID strings to typed X4 objects at every
  preflight and apply boundary, and compare stable IDs instead of macro-object
  identity.
- Generate complete weapon, shield, and turret category plans containing the
  existing loadout plus the requested item, preventing an empty-slot install
  from replacing equipment already mounted in that category.
- Preserve the transaction safety gate: salvaged inventory and Bonding
  Catalysts are spent only after exact selected-item and total-loadout gains.

### Localization and UI Feedback

- Added the production English text catalog on X4 page `1171361` and the
  framework for community translations.
- Fixed formatted welding-completion, salvage-confirmation, and installed-item
  text appearing as unresolved references such as `{1171361,625}`.
- Resolve localized format templates through X4 `readtext` before substituting
  ship names, equipment names, quantities, and result lists.

### Verification

- Reproduced the reported failure with save slot 16 without overwriting it.
  A TER M Shield Generator Mk3 and SPL M Neutron Gatling Mk2 both installed,
  existing weapon and shield rows remained, inventory changed from one to zero
  for each item, and Bonding Catalysts changed from 20 to 16.
- Turrets use the same repaired category path. The test save had no stored
  turret for an independent mutation test, so turret coverage is schema-checked
  and shares the weapon/shield logic validated in game.

## v3.61 - 2026-07-15

**Changes since public release v3.13**

### Native Salvage and Welding

- Replaced the player-facing salvage and welding planners with X4's native Ship
  Configuration interface through Kuertee UI Extensions.
- Added native equipment categories, physical slot tabs, filters, component
  tiles, 3D ship presentation, Overview changes, category gauges, icons, and
  Ship Statistics previews.
- Added immediate per-click previews for accepted salvage removals and weld
  installations without mutating the ship until final confirmation.
- Added live saved-stock quantities, exact inventory reservations, catalyst
  totals, pending-plan summaries, Clear Plan controls, and remaining-count
  updates.
- Replaced the extra weld review stage with one **Install Loadout** action that
  opens the final detailed Apply Plan dialog.
- Replaced the salvage confirmation table with X4's compact native question
  window and a safe **Back to Plan** choice.

### Compatibility and Plan Safety

- Enforced exact native compatibility for weapons, launchers, shields,
  turrets, engines, and thrusters, including missile-only and conventional-gun
  slot restrictions.
- Corrected grouped weapon, shield, turret, and engine presentation so planned
  quantities match physical ship slots and displayed previews.
- Prevented duplicate inventory reservations, stock-one overbooking, stale
  preview acceptance, occupied-slot replacements, and plans beyond the ship's
  installed-plus-pending capacity.
- Corrected mounted-weapon classification so mines and other ammunition wares
  are not treated as installable ship weapons.
- Preserved Mission Director authority for target validation, inventory and
  catalyst spending, recovery credit, loadout mutation, and exact post-change
  verification.

### Work Phase and Feedback

- Added simulated salvage and welding work phases lasting one second per
  planned item, with a three-second minimum and fifteen-second maximum.
- Kept normal player movement during work while requiring the player to remain
  in EVA, in the same sector, and within 100 m until completion.
- Added safe cancellation before mutation if the player leaves range, changes
  sector, exits EVA, loses the target, or the target becomes invalid.
- Blocked both regulators while a confirmed work phase or verified mutation is
  already active.
- Added weld-completion notifications and an exact list of successfully
  attached components.
- Added lore-friendly HUD feedback for range, ownership, foreign pilots,
  boarding, unsupported ship sizes, wrecks, construction frames, invalid
  targets, missing tools, and active work.
- Added distinct terminal messages for fully equipped weld targets and stripped
  salvage targets: **Equipment slots are full.** and **No items left to
  salvage.**

### Reliability and Release Cleanup

- Moved work timing into Mission Director so closing a native menu cannot
  strand the regulator busy state or prevent final range validation.
- Added startup recovery for interrupted uncommitted work state without
  changing ship equipment, salvage inventory, or catalysts.
- Restricted development logbook diagnostics to the debug option while keeping
  intentional player-facing completion and shortage records.
- Graduated the complete native workflow from its experimental gate into the
  always-on public release path.
- Kept all SES-specific UI behavior inside the SES extension and consumed the
  published Kuertee callback surfaces without patching the installed UIX
  package.
