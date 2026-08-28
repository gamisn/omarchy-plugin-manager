# Plugin Manager

A simple Omarchy panel that lists your installed plugins and lets you remove them — a lightweight alternative to a full storefront.

## Install

```bash
omarchy plugin add https://github.com/gamisn/omarchy-plugin-manager.git --enable --yes
```

## Summon

The plugin adds a **gear icon (⚙) to the bar** — click it to open the manager panel.

You can also summon it from the terminal:

```bash
omarchy-shell shell toggle gamisn.plugin-manager
```

Or bind a key in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + P", "Plugin Manager", "omarchy-shell shell toggle gamisn.plugin-manager")
```

## What it does

- Adds a gear icon to the bar that opens the manager panel
- Lists every installed plugin with its **description, author, version, and source link**
- Third-party plugins show a clickable **"Open source ↗"** link to their GitHub repo
- Removes a plugin with one click (`omarchy plugin remove <id> --yes`)
- Shows the **remove command output** in a log area at the bottom (e.g. "Removed X.", "Restored Y.")

## Notes

- Removing a plugin is permanent — it deletes the plugin's folder under `~/.config/omarchy/plugins/<id>/`.
- First-party plugins (shipped with Omarchy) can also be removed; they are restored on the next Omarchy update.
