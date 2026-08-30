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

In the panel: `↑`/`↓` move row by row, `Page Up`/`Page Down` and `Home`/`End` jump, the mouse wheel pages (one notch ≈ 70% of the view), and the scrollbar on the right is draggable.

## What it does

- Adds a gear icon to the bar that opens the manager panel
- Lists every installed plugin with its **description, author, version, and source link**
- Third-party plugins show a clickable **"Open source ↗"** link to their GitHub repo
- Removes a plugin with one click (`omarchy plugin remove <id> --yes`)
- A **remove dialog** runs the command and **streams its output live** into the panel — you see the process as it happens, and the panel stays open throughout

## Notes

* Removing a plugin is permanent — it deletes the plugin's folder under `~/.config/omarchy/plugins/<id>/`.
* First-party plugins (shipped with Omarchy) can also be removed; they are restored on the next Omarchy update.
* Want a safe target for trying this out? Install the companion [Test Plugin](https://github.com/gamisn/omarchy-test-plugin) — it is deliberately harmless, so you can remove and reinstall it as often as you like.

## Security model

For this plugin specifically, an installed plugin's manifest and git config are **untrusted input**, not configuration:

* Everything read out of `~/.config/omarchy/plugins/` reaches a `Process` only as an **argv element** — never inside a shell string (`shell.run("cmd " + x)` resolves to `bash -lc`, so it is arbitrary execution for attacker-controlled values).
* All manifest fields are rendered with `textFormat: Text.PlainText` — markup in another plugin's manifest is never promoted to rich text inside the shell process.
* Source URLs must pass a strict https-only validation before the "Open source" link is shown or opened, and open argv-only via `Quickshell.execDetached(["xdg-open", url])`.
* The plugin-list pipeline is capped (2 MB stdout, 512 items, bounded string fields) with watchdog timers on both the list and remove processes.

The security helpers live in `security.mjs` and are covered by unit tests that run in the same QML V4 engine the shell uses:

```shell
qml6 tests/run.qml   # 32 checks, prints ALL PASS
```