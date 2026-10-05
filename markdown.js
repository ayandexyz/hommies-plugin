.pragma library

// Turns an agent's Markdown message into Qt StyledText for the panels.
// Everything from the agent is HTML-escaped first, and only the tags below are
// added back, so a message can never inject its own markup. In particular
// there is no <img> or <a>: rendering must not fetch anything or open links.

function escapeHtml(text) {
  return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
}

// Bold, italic, inline code, and links (shown as their text) inside one line.
function inline(line) {
  var parts = String(line).split("`")
  var out = ""
  for (var index = 0; index < parts.length; index++) {
    var part = parts[index]
    // Odd parts sit between backticks; an unmatched last backtick stays literal.
    if (index % 2 === 1 && index < parts.length - 1) {
      out += "<tt>" + escapeHtml(part) + "</tt>"
      continue
    }
    if (index % 2 === 1) out += "`"
    var text = escapeHtml(part)
    text = text.replace(/!?\[([^\]]+)\]\([^)\s]*\)/g, "$1")
    text = text.replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>")
    text = text.replace(/(^|[^*\w])\*([^*\s][^*]*)\*(?!\w)/g, "$1<i>$2</i>")
    out += text
  }
  return out
}

function codeLine(line) {
  return "<tt>" + escapeHtml(line).replace(/ /g, "&nbsp;") + "</tt>"
}

function toStyledText(markdown) {
  var lines = String(markdown || "").replace(/\r\n?/g, "\n").split("\n")
  var out = []
  var inCode = false
  for (var index = 0; index < lines.length; index++) {
    var line = lines[index]
    if (/^\s*```/.test(line)) {
      inCode = !inCode
      continue
    }
    if (inCode) {
      out.push(codeLine(line))
      continue
    }
    var heading = line.match(/^\s{0,3}#{1,6}\s+(.*?)\s*#*\s*$/)
    if (heading) {
      out.push("<b>" + inline(heading[1]) + "</b>")
      continue
    }
    if (/^\s{0,3}([-*_])(\s*\1){2,}\s*$/.test(line)) {
      out.push("───")
      continue
    }
    var bullet = line.match(/^(\s*)[-*+]\s+(.*)$/)
    if (bullet) {
      var depth = Math.min(3, Math.floor(bullet[1].length / 2))
      out.push(new Array(depth * 3 + 1).join("&nbsp;") + "• " + inline(bullet[2]))
      continue
    }
    var quote = line.match(/^\s*>\s?(.*)$/)
    if (quote) {
      out.push("<i>│ " + inline(quote[1]) + "</i>")
      continue
    }
    out.push(inline(line))
  }
  return out.join("<br>")
}
