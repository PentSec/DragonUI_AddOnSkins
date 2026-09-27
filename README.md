# DragonUI_AddOnSkins

A companion addon for **DragonUI** (World of Warcraft 3.3.5a) that reskins
third-party addons so they match DragonUI's visual theme.

It is a standalone project: it depends on DragonUI at runtime, but it does not
modify DragonUI or DragonUI_Options, and it never reads or writes their
SavedVariables.

---

## Addons Skinned

- **Details! Damage Meter skin** — a retail-style

## Requirements

- **[DragonUI](https://github.com/NeticSoul/DragonUI)**, installed and enabled (declared as a dependency).


## Installation

1. Copy the `DragonUI_AddOnSkins` folder into
   `World of Warcraft/Interface/AddOns/`.
2. Ensure `DragonUI` is installed and enabled.
3. Enable `DragonUI_AddOnSkins` in the addon list and log in.

## Usage

Open **DragonUI Options → Addons Skin**:

- **Details!** sub-tab — the enable toggle, the **Background Opacity** slider,
  and the **Apply** / **Restore** buttons.


Slash commands:

| Command | Description |
|---|---|
| `/duidetails` | Apply the Details! skin immediately. |
| `/duiaddonskins` | Print the current configuration state (diagnostics). |

Applying or removing a skin takes effect immediately; no reload is required.

### Support me ❤️ ⬎

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/D5R327PO99)

## License

MIT for project-authored code. Bundled third-party libraries keep their own
licenses;
