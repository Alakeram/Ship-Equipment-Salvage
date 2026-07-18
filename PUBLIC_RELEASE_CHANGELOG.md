# Public Release Changelog

This is the authoritative player-facing changelog for Ship Equipment
Salvaging. Entries are added only for an explicitly approved public release,
patch, or hotfix. Internal development versions are compiled into one entry
under the final public version rather than listed individually.

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

