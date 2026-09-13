.pragma library

// Pure helpers for the Window Switcher plugin. No QML imports here so this
// file stays a plain JS library (see .pragma library above).

// Browser window titles usually end with the browser name. The desktop entry
// name is passed in too, so any window whose title ends in " - <App Name>"
// gets cleaned even when it is not a known browser.
var BROWSER_SUFFIX = /\s+[-\u2013\u2014]\s+(Google Chrome|Chromium|Mozilla Firefox|Firefox|Brave|Brave Browser|Microsoft Edge|Vivaldi|Opera|LibreWolf|Waterfox|qutebrowser|Zen Browser)\s*$/i

var GENERIC_LAST_SEGMENTS = {
  desktop: true,
  app: true,
  client: true,
  gtk: true
}

// App ids/classes that identify a terminal emulator, used to decide whether
// the cwd/command enrichment is worth showing.
var TERMINAL_IDS = [
  "kitty", "foot", "alacritty", "ghostty", "wezterm", "konsole",
  "gnome-terminal", "xfce4-terminal", "xterm", "st", "tmux", "termite",
  "rio", "contour", "blackbox", "hyper"
]

function escapeRegExp(value) {
  return String(value || "").replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
}

function key(value) {
  return String(value || "").toLowerCase().replace(/[^a-z0-9]+/g, "")
}

function normalizeId(value) {
  var s = String(value || "").trim().toLowerCase()
  if (s.slice(-8) === ".desktop") s = s.slice(0, -8)
  return s
}

// Best-effort human name from a raw appId/class when no desktop entry matches.
// "google-chrome" -> "Google Chrome", "org.telegram.desktop" -> "Telegram".
function fallbackName(appId) {
  var raw = String(appId || "").trim()
  if (!raw) return "Unknown"

  var segments = raw.split(".")
  var base = segments[segments.length - 1] || raw
  if (segments.length > 1 && GENERIC_LAST_SEGMENTS[base.toLowerCase()])
    base = segments[segments.length - 2] || base

  base = base.replace(/[-_]+/g, " ").replace(/\s+/g, " ").trim()
  if (!base) base = raw
  return base.replace(/\b\w/g, function(c) { return c.toUpperCase() })
}

// The "what it's doing" line: the window title with the app name / browser
// suffix stripped, e.g. "Inbox - Google Chrome" -> "Inbox".
function activity(title, appName) {
  var raw = String(title || "").trim()
  if (!raw) return ""

  var cleaned = raw
  var name = String(appName || "").trim()
  if (name) {
    var suffix = new RegExp("\\s+[-\u2013\u2014]\\s*" + escapeRegExp(name) + "\\s*$", "i")
    cleaned = cleaned.replace(suffix, "").trim()
  }
  cleaned = cleaned.replace(BROWSER_SUFFIX, "").trim()

  return cleaned.length > 0 ? cleaned : raw
}

function isTerminal(appId) {
  var value = String(appId || "").toLowerCase()
  if (!value) return false
  for (var i = 0; i < TERMINAL_IDS.length; i++) {
    if (value.indexOf(TERMINAL_IDS[i]) !== -1) return true
  }
  return false
}

// "~" for the home directory, shortening long paths from the left.
function shortenPath(path, home) {
  var value = String(path || "").trim()
  if (!value) return ""
  var h = String(home || "").replace(/\/+$/, "")
  if (h && (value === h || value.indexOf(h + "/") === 0))
    value = "~" + value.slice(h.length)
  var parts = value.split("/")
  if (parts.length > 4) value = "…/" + parts.slice(parts.length - 3).join("/")
  return value
}

// Activity line for a terminal with cwd/command enrichment.
function terminalActivity(cwd, cmd, home, fallback) {
  var dir = shortenPath(cwd, home)
  var command = String(cmd || "").trim()
  if (!dir && !command) return String(fallback || "")
  return command ? dir + " · " + command : dir
}
