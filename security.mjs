// Security helpers for gamisn.plugin-manager.
//
// Untrusted-input rule: for this manager, an installed plugin's manifest and
// git config are untrusted input, not configuration. Anything read out of
// ~/.config/omarchy/plugins reaches a Process only as an argv element and a
// Text only with textFormat: Text.PlainText, and is length-capped.
//
// This module is deliberately dependency-free so it can be unit-tested
// standalone in the QML V4 engine (see the marketplace review thread).

// A plugin's git remote URL is attacker-controllable (git places no
// restrictions on remote URLs), so accept only bounded plain https URLs
// with no whitespace, control, or shell/URI mischief characters.
export function isSafeSourceUrl(url) {
  var s = String(url === null || url === undefined ? "" : url)
  if (!s || s.length > 200) return false
  if (s.indexOf("https://") !== 0) return false
  for (var i = 0; i < s.length; i++) {
    var c = s.charCodeAt(i)
    if (c <= 0x20 || c === 0x7f) return false
  }
  if (/["'`\\<>{}|$;&*!^]/.test(s)) return false
  return true
}

export function boundString(v, cap) {
  var s = (v === null || v === undefined) ? "" : String(v)
  if (s.length > cap) s = s.substring(0, cap) + "…"
  return s
}

// Consumer caps: bound item count and every field before it reaches a model.
// Markup characters are not stripped here — rendering is made inert with
// textFormat: Text.PlainText at every Text element; this only bounds size.
export function sanitizePlugins(parsed, maxPlugins, maxFieldLen) {
  if (typeof parsed === "string" || !parsed || parsed.length === undefined)
    return []
  var arr = parsed
  var n = Math.min(arr.length, maxPlugins)
  var out = []
  for (var i = 0; i < n; i++) {
    var p = arr[i]
    if (!p || typeof p !== "object") continue
    var kinds = []
    if (p.kinds && typeof p.kinds !== "string" && p.kinds.length !== undefined) {
      var m = Math.min(p.kinds.length, 8)
      for (var k = 0; k < m; k++) kinds.push(boundString(p.kinds[k], 32))
    }
    out.push({
      id: boundString(p.id, maxFieldLen),
      name: boundString(p.name, maxFieldLen),
      kinds: kinds,
      enabled: p.enabled === true,
      active: p.active === true,
      canDisable: p.canDisable !== false,
      firstParty: p.firstParty === true,
      clonedFrom: boundString(p.clonedFrom, maxFieldLen),
      description: boundString(p.description, 300),
      author: boundString(p.author, maxFieldLen),
      version: boundString(p.version, 64),
      sourceUrl: boundString(p.sourceUrl, 200)
    })
  }
  return out
}