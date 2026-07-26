# How to Translate Ship Equipment Salvaging

Ship Equipment Salvaging (SES) supports community translations through X4's
normal `t`-file system. A translation is one XML file containing the localized
version of every player-facing SES text entry. No Lua, Mission Director, or
gameplay code changes are required.

This guide covers translations contributed directly to SES. If you want to
publish and maintain a separate translation extension, follow
[`PUBLISHING_TRANSLATION_MOD.md`](PUBLISHING_TRANSLATION_MOD.md) instead. A
standalone translation needs its own `content.xml` and must declare SES as its
dependency.

SES reserves X4 text page **1171361**. The page ID and every numeric text ID are
part of the mod's code contract and must never be changed.

## Quick Start: German

1. Find the SES `t` folder.
2. Copy `0001.xml` and name the copy `0001-l049.xml`.
3. Translate only the player-facing text inside the `<t>` elements.
4. Keep page `1171361`, every `<t id="...">`, every `%s`/`%d`, and every
   literal `\n` unchanged.
5. Save the file as UTF-8 XML.
6. Test it with X4 running in German.
7. Submit only `0001-l049.xml` unless another project file genuinely needs a
   correction.

## 1. Find the Correct Folder

The folder name depends on how you received the project:

- Public GitHub checkout:
  `ship_equipment_salvaging/t/`
- Maintainer development workspace:
  `extension/t/`
- Installed mod: find the `ship_equipment_salvaging` folder containing
  `content.xml`, then use or create its `t` subfolder.

In this guide, `<mod-root>` means the folder containing `content.xml`.

The expected public-repository layout is:

```text
Ship-Equipment-Salvage/
|-- TRANSLATING.md
`-- ship_equipment_salvaging/
    |-- content.xml
    `-- t/
        |-- 0001.xml
        `-- 0001-l049.xml   <- German translation
```

## 2. Choose the X4 Language Filename

Use this exact pattern:

```text
0001-lNNN.xml
```

`NNN` is X4's zero-padded numeric language code. Use a lowercase `l` in new
SES files so the project and validator stay consistent.

| Language | X4 code | SES filename |
| --- | ---: | --- |
| German | 049 | `0001-l049.xml` |
| French | 033 | `0001-l033.xml` |
| English | 044 | `0001-l044.xml` |

SES already ships `0001.xml` as its English fallback and includes the German
catalog contributed by **TheSylance**, so separate English or German files are
normally unnecessary. For another language, use the same `lNNN` code
found on X4's own `t/0001-lNNN.xml` file for that language. Do not use names
such as `german.xml`, `de.xml`, or `0001-de.xml`.

X4 loads the matching language file when it exists. If no matching SES file is
present, X4 uses `0001.xml` as the English fallback. Do not rely on per-line
fallback inside a partial translation: every shipped language file must be
complete.

## 3. Copy the English Catalog

Start from the newest `0001.xml` included with the SES version you are
translating. Do not start from an older community translation because it may be
missing newer text IDs.

For German in a public GitHub checkout, PowerShell can make the copy with:

```powershell
Copy-Item `
  .\ship_equipment_salvaging\t\0001.xml `
  .\ship_equipment_salvaging\t\0001-l049.xml
```

You may also copy and rename the file in File Explorer.

Keep the copied XML structure exactly as supplied:

```xml
<?xml version="1.0" encoding="utf-8"?>
<diff>
  <add sel="/language">
    <page id="1171361" title="Ship Equipment Salvaging" descr="Ship Equipment Salvaging player-facing text" voice="no">
      <!-- text entries -->
    </page>
  </add>
</diff>
```

The filename selects the language. Do not replace this structure with a new
`<language>` root and do not add a different page ID.

## 4. Translate Only the Human-Readable Text

Translate the text between each opening and closing `<t>` tag:

```xml
<!-- English -->
<t id="101">Shield Generators</t>

<!-- German -->
<t id="101">Schildgeneratoren</t>
```

The page `title` and `descr` attributes may also be translated. Leave these
parts unchanged:

- `<diff>` and `<add sel="/language">`
- Page ID `1171361`
- Every numeric `<t id="...">`
- XML element and attribute names
- Internal comments, unless changing a comment helps the translator

Do not translate or edit gameplay identifiers, ware IDs, macro IDs, Lua event
names, Mission Director variable names, debug markers, or `content.xml`.

Some names shown by SES come directly from X4, including ship and equipment
names. X4 localizes those through its own catalogs; they should not be copied
into the SES translation.

The extension name and description in `content.xml` intentionally remain
literal English because X4's Extensions menu does not resolve text-page
references in those manifest fields.

## 5. Preserve Placeholders and Layout Codes

Some entries contain values inserted by the game at runtime:

- `%s` inserts text, a name, or another formatted value.
- `%d` inserts an integer.
- `\n` creates an intentional line break.

Keep each placeholder exactly as written, with the same type, number, and
order. Do not translate it, delete it, change `%s` to `%d`, or replace the
literal `\n` characters with an XML line break.

Example:

```xml
<!-- English -->
<t id="413">Target: %s\nRecovered: %d / %d    Success: %d    Partial: %d    Failed: %d    Blocked: %d</t>

<!-- Valid translated structure: wording changes, tokens do not -->
<t id="413">Ziel: %s\nGeborgen: %d / %d    Erfolg: %d    Teilweise: %d    Fehlgeschlagen: %d    Blockiert: %d</t>
```

The project validator compares the ordered `%s` and `%d` sequence in every
translation against the English source and rejects mismatches.

Native equipment tiles have limited space. Prefer concise terminology where
the English source is a short label, button, receipt, or equipment caption.
Longer descriptions and result reasons may be translated naturally.

## 6. Keep the XML Valid

Save the file as UTF-8. Escape reserved XML characters used as normal text:

| Character | Write as |
| --- | --- |
| `&` | `&amp;` |
| `<` | `&lt;` |
| `>` | `&gt;` |

Normal accented characters, umlauts, and non-Latin scripts should remain as
real UTF-8 text rather than being converted to numeric character references.

Each translation must contain:

- Exactly one SES page with ID `1171361`
- Every text ID present in the current English `0001.xml`
- No duplicate IDs
- No unknown or retired IDs
- The same ordered `%s` and `%d` tokens for every matching line

If a line cannot be translated accurately, do not publish a partial language
file. An absent language file safely falls back to English; an incomplete file
can produce missing text in game.

## 7. Validate the File

### Quick XML check

From the public repository root, this PowerShell command confirms that the
German file is well-formed XML:

```powershell
[xml](Get-Content -LiteralPath `
  .\ship_equipment_salvaging\t\0001-l049.xml -Raw) | Out-Null
```

No output means the XML parsed successfully. This quick check does not compare
IDs or placeholders.

### Full SES validation

Maintainers using the full development workspace must run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\Validate-Extension.ps1
```

The full validator checks XML structure, page `1171361`, duplicate IDs,
missing IDs, unknown IDs, and ordered `%s`/`%d` tokens. A translation is not
release-ready until this command passes.

## 8. Test in X4

1. Close X4 before adding or replacing the translation file.
2. Put `0001-lNNN.xml` in `<mod-root>/t/`. If the installed package has no loose
   `t` folder, create it next to `content.xml`.
3. Start X4 in the target language using the normal platform/game language
   setting.
4. Confirm SES and its required extensions are enabled, then load a safe test
   save.
5. Restart X4 after every translation-file change so the text catalog reloads.

Check these player-facing surfaces:

- SES Tool Mode dropdown and descriptions
- Avarice Beam and Bonding Regulator item names/descriptions
- Native weld planner, buttons, receipts, and confirmation
- Native salvage planner, confirmation, timer feedback, and results
- Salvage Inventory
- Black Market parts screen
- Range, ownership, pilot, eligibility, busy, full-slot, and empty-target
  notifications
- Welding completion notification and attached-item list

During testing, look specifically for:

- Raw references such as `{1171361,703}`
- Visible `%s`, `%d`, or `\n` that should have been processed
- Blank labels or `ReadText` errors
- Truncated buttons or captions that obscure their meaning
- Inconsistent official X4 terms for ships, equipment, factions, and actions

## 9. Submit the Translation

A translation contribution should normally contain only:

```text
ship_equipment_salvaging/t/0001-lNNN.xml
```

For a GitHub pull request, a clear title is:

```text
Add German translation
```

Include the following in the submission description:

- Language and X4 language code
- SES version used as the English source
- Whether every text ID is translated
- Which in-game surfaces were tested
- The translator name or credit requested for release notes

Do not change the SES version, English catalog, README release number, or public
changelog as part of a translation-only contribution. The maintainer will run
the full validator, package the file, and add release-facing credit when the
translation is accepted for a public release.

## Updating an Existing Translation

When SES changes `0001.xml`, compare the new English catalog with the last
translated version and update the language file before it ships again. Add all
new IDs, update lines whose English meaning changed, and remove any retired
IDs. The full validator will identify missing, unknown, duplicate, or
placeholder-incompatible entries.

Do not assume an older translation remains complete just because it still
loads in X4.
