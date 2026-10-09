import QtQuick
import qs.Commons
import qs.Commons as Commons
import ".."

// Hommie: the Omarchy mark as a face. The 15×15 frame from /usr/share/omarchy/icon.txt
// with a pair of eyes in its empty middle. Every color comes from the active
// Omarchy theme (tile = popup background; frame and eyes = accent, or the
// mood's status color), so it re-skins with `omarchy theme set`.
//
// Character contract (see FloatingBuddy.qml):
//   property string mood   idle | working | thinking | approval | question
//                          | error | ratelimit | finished | sleeping
//   property real lookX    -1 (left) … 1 (right); where the eyes point
//   property real lookY    -1 (up) … 1 (down)
//   property bool running  false pauses the frame loop
//   property string outfit optional: "" or an accessory (party, beanie, crown,
//                          santa, pumpkin, bow, glasses, sunglasses, scarf)
//   function poke()        reaction to a click
//   function emote(name)   optional: play a short emote (greet, celebrate,
//                          dizzy, wink, yawn, look); returns false when the
//                          mood does not allow it. Agent moods always win:
//                          approval, question, error, and ratelimit block
//                          emotes and cancel a running one.
Item {
  id: root

  property string mood: "idle"
  property real lookX: 0
  property real lookY: 0
  property bool running: true
  property string outfit: ""

  implicitWidth: 96
  implicitHeight: 96

  function poke() { engine.poke() }
  function emote(name) { return engine.startEmote(String(name)) }

  onMoodChanged: engine.setState(mood)
  onOutfitChanged: engine.setOutfit(outfit)
  Component.onCompleted: {
    engine.setState(mood, true)
    engine.setOutfit(outfit)
    engine.startEmote("greet")
  }

  StatusPalette { id: statusColors }

  QtObject {
    id: engine

    // The mark, row by row. '#' is frame.
    readonly property var mark: [
      "###############",
      "#......#......#",
      "#.######...##.#",
      "#.#.........#.#",
      "#.#.........#.#",
      "#.#.........#.#",
      "#.#.........#.#",
      "###.........#.#",
      "#.#.........#.#",
      "#.#.........#.#",
      "#.#.........#.#",
      "#.#.........#.#",
      "#.###########.#",
      "#......#......#",
      "########.######"
    ]
    readonly property int grid: 15
    // The inner ring as one path, in travel order for the thinking snake:
    // top edge leftward from the gap, down the left side, along the bottom,
    // up the right side, and back to the gap.
    readonly property var innerPath: {
      var path = [], i
      for (i = 7; i >= 2; i--) path.push({ col: i, row: 2 })
      for (i = 3; i <= 12; i++) path.push({ col: 2, row: i })
      for (i = 3; i <= 12; i++) path.push({ col: i, row: 12 })
      for (i = 11; i >= 2; i--) path.push({ col: 12, row: i })
      path.push({ col: 11, row: 2 })
      return path
    }
    // Every other frame cell: the outer ring and its connectors.
    readonly property var outerCells: {
      var inner = {}
      for (var i = 0; i < innerPath.length; i++) inner[innerPath[i].col + "," + innerPath[i].row] = true
      var list = []
      for (var row = 0; row < grid; row++) {
        for (var col = 0; col < grid; col++) {
          if (mark[row].charAt(col) === "#" && !inner[col + "," + row]) list.push({ col: col, row: row })
        }
      }
      return list
    }
    // Pixel "z" for the sleep animation.
    readonly property var zGlyph: ["####", "..#.", ".#..", "####"]

    // eye shape, badge, motion, and snake speed (inner-ring cells per second) per mood.
    readonly property var states: ({
      idle: { eye: "pill", badge: "" },
      working: { eye: "pill", badge: "dots", snake: 30 },
      thinking: { eye: "pill", badge: "dots", snake: 15 },
      approval: { eye: "wide", badge: "bang", bounces: true },
      question: { eye: "pill", badge: "question", tilt: 0.12 },
      error: { eye: "flat", badge: "dot" },
      ratelimit: { eye: "tired", badge: "dot", sweat: true },
      finished: { eye: "happy", badge: "dot" },
      sleeping: { eye: "dash", badge: "", bobs: true, zz: true }
    })

    function moodColor(name) {
      switch (name) {
        case "working": return statusColors.working
        case "thinking": return statusColors.working
        case "approval": return statusColors.warning
        case "question": return statusColors.attention
        case "error": return statusColors.error
        case "ratelimit": return statusColors.warning
        case "finished": return statusColors.success
        default: return Commons.Color.accent
      }
    }

    property var s: ({
      eyeX: 0, eyeY: 0, tilt: 0, open: 1, sx: 1, sy: 1, oy: 0, ox: 0, badgeS: 0, snakeAt: 0, snakeOn: 0, outfitS: 0,
      col: [0.6, 0.8, 0.4]
    })
    property var cfg: states.idle
    property string state: ""
    property string badge: ""
    property color badgeColor: Commons.Color.accent
    property var tweens: ({})
    property var particles: []
    property real clock: Math.random() * 5
    property real nextBlink: 1.5 + Math.random() * 2
    property real lastAmbient: 0

    // --- outfits -------------------------------------------------------------
    // Pixel-art accessories in the mark's own grid (one cell = one mark cell),
    // drawn inside the body transform so they tilt, squash, and hop with him.
    // Hats sit on the top edge, the scarf wraps the bottom edge, and glasses
    // follow the eyes. Cells: a accent, w warning, e error, s success,
    // k working, f text, i tile ink; "." is empty.
    readonly property var outfitGlyphs: ({
      party: { at: "top", rows: ["...w...", "...w...", "..eae..", "..aea..", ".eaeae.", ".aeaea.", "eaeaeae", "aeaeaea"] },
      beanie: { at: "top", rows: [".....w.....", "...aaaaa...", ".aaaaaaaaa.", ".aaaaaaaaa.", "akakakakaka", "kakakakakak"] },
      crown: { at: "top", rows: ["w...w...w", "ww.www.ww", "wwwwwwwww", "wewwswwew", "wwwwwwwww"] },
      santa: { at: "top", dx: 0.5, rows: ["..........ff", "........eeff", "......eeee..", "....eeeeee..", "..eeeeeeee..", ".eeeeeeeeee.", "ffffffffffff"] },
      pumpkin: { at: "top", rows: ["....s....", "...s.....", ".wwwwwww.", "wwiwwwiww", "wwwwwwwww", "wiwiwiwiw", ".wwwwwww."] },
      bow: { at: "top", dx: 4, rows: ["ee...ee", "eeeweee", "ee...ee"] },
      scarf: { at: "neck", rows: ["eeeeeeeeeeeeeeeee", "eeeeeeeeeeeeeeeee", "..ee.............", "..ff............."] },
      glasses: { at: "eyes" },
      sunglasses: { at: "eyes" }
    })
    property string outfitName: ""

    function setOutfit(next) {
      next = outfitGlyphs[next] ? String(next) : ""
      if (next === outfitName && (next === "" || s.outfitS > 0)) return
      // Shrink the old one away, then pop the new one in.
      anim("outfitS", [[0, 110, easeInOut]], function() {
        outfitName = next
        if (next !== "") anim("outfitS", [[1, 320, easeBack]])
      })
    }

    function outfitColor(cell) {
      switch (cell) {
        case "a": return rgba(Commons.Color.accent)
        case "w": return rgba(statusColors.warning)
        case "e": return rgba(statusColors.error)
        case "s": return rgba(statusColors.success)
        case "k": return rgba(statusColors.working)
        case "f": return rgba(Commons.Color.foreground)
        default: return rgba(Commons.Color.popups.background)
      }
    }

    function drawOutfit(ctx, u) {
      var outfit = outfitGlyphs[outfitName]
      if (!outfit || s.outfitS < 0.01) return
      ctx.save()
      if (outfit.at === "eyes") {
        drawGlasses(ctx, u, outfitName === "sunglasses")
        ctx.restore()
        return
      }
      var rows = outfit.rows
      var width = rows[0].length * u
      var x0 = 7.5 * u - width / 2 + (outfit.dx || 0) * u
      // Hats rest on the tile's top edge; the scarf covers the bottom row.
      var anchorY = outfit.at === "neck" ? 13.8 * u : -0.35 * u
      var y0 = outfit.at === "neck" ? anchorY : anchorY - rows.length * u
      ctx.translate(7.5 * u, anchorY)
      ctx.scale(s.outfitS, s.outfitS)
      ctx.translate(-7.5 * u, -anchorY)
      // One path per colour, like the mark, so neighbouring cells leave no seams.
      var colours = {}
      for (var row = 0; row < rows.length; row++) {
        for (var col = 0; col < rows[row].length; col++) {
          var cell = rows[row].charAt(col)
          if (cell !== ".") (colours[cell] = colours[cell] || []).push([col, row])
        }
      }
      for (var colour in colours) {
        ctx.beginPath()
        var cells = colours[colour]
        for (var i = 0; i < cells.length; i++) ctx.rect(x0 + cells[i][0] * u, y0 + cells[i][1] * u, u + 0.01, u + 0.01)
        ctx.fillStyle = outfitColor(colour)
        ctx.fill()
      }
      ctx.restore()
    }

    // Glasses ride the eyes, a little behind them, so they stay on his face.
    function drawGlasses(ctx, u, shades) {
      var gx = 7.5 * u + s.eyeX * u * 1.2
      var gy = 6.24 * u + s.eyeY * u * 1.2
      ctx.translate(gx, gy)
      ctx.scale(s.outfitS, s.outfitS)
      ctx.lineWidth = u * 0.35
      ctx.strokeStyle = rgba(Commons.Color.foreground)
      for (var side = -1; side <= 1; side += 2) {
        if (shades) {
          roundRect(ctx, side * u * 1.6 - u * 1.25, -u * 0.85, u * 2.5, u * 1.7, u * 0.5)
          ctx.fillStyle = rgba(s.col)
          ctx.fill()
          ctx.fillStyle = rgba(Commons.Color.popups.background, 0.7)
          ctx.fillRect(side * u * 1.6 - u * 0.75, -u * 0.5, u * 0.45, u * 0.3)
        } else {
          ctx.beginPath()
          ctx.arc(side * u * 1.6, 0, u * 1.25, 0, Math.PI * 2, false)
          ctx.stroke()
        }
      }
      // Bridge between the lenses.
      ctx.beginPath()
      ctx.moveTo(-u * 0.35, -u * 0.15)
      ctx.lineTo(u * 0.35, -u * 0.15)
      ctx.strokeStyle = shades ? rgba(s.col) : rgba(Commons.Color.foreground)
      ctx.stroke()
    }

    // --- emotes --------------------------------------------------------------
    // Short overlays on top of the mood: they change the eyes, tilt, and
    // motion for a moment and then hand back to the mood.

    /** Moods that need the user; they block emotes so nothing hides them. */
    readonly property var urgentStates: ["approval", "question", "error", "ratelimit"]
    /** Seconds each emote lasts. */
    readonly property var emoteLengths: ({ greet: 1.5, celebrate: 1.2, dizzy: 2.4, wink: 0.7, yawn: 1.7, look: 2.2 })
    /** Random emotes only play while idle. */
    readonly property var idleEmotes: ["wink", "yawn", "look"]
    property var emote: null
    property real nextIdleEmote: clock + 20 + Math.random() * 25
    /** Recent poke times; five within 2.5 s make him dizzy. */
    property var pokes: []

    function emoteAllowed(name) {
      if (urgentStates.indexOf(state) >= 0) return false
      if (idleEmotes.indexOf(name) >= 0) return state === "idle"
      // Asleep he only wakes to a greeting or a poke-induced spin.
      return state !== "sleeping" || name === "greet" || name === "dizzy"
    }

    function startEmote(name) {
      if (!emoteLengths[name] || !emoteAllowed(name)) return false
      emote = { name: name, start: clock, length: emoteLengths[name] }
      if (name === "greet") {
        // Pop in, then a quick wiggle.
        s.sx = 0.35
        s.sy = 0.35
        anim("sx", [[1.12, 260, easeOut], [1, 220, easeBack]])
        anim("sy", [[1.12, 260, easeOut], [1, 220, easeBack]])
        anim("tilt", [[0.16, 170, easeOut], [-0.13, 200, easeInOut], [0.08, 180, easeInOut], [0, 220, easeOut]])
      } else if (name === "celebrate") {
        if (!tweens.oy) anim("oy", [[-0.14, 170, easeOut], [0, 400, easeBack]])
        emit("spark", 5)
      } else if (name === "yawn") {
        anim("sy", [[1.08, 500, easeInOut], [1, 600, easeInOut]])
        anim("sx", [[0.96, 500, easeInOut], [1, 600, easeInOut]])
      } else if (name === "dizzy") {
        anim("oy", [[-0.08, 120, easeOut], [0, 260, easeBack]])
      }
      return true
    }

    function poke() {
      pokes = pokes.filter(function(time) { return clock - time < 2.5 }).concat([clock])
      if (pokes.length >= 5 && startEmote("dizzy")) {
        pokes = []
        return
      }
      squash()
      blink()
      if (!tweens.oy) anim("oy", [[-0.06, 90, easeOut], [0, 220, easeBack]])
    }

    /** 0 → 1 → 0 over the running emote, for effects that ease in and out. */
    function emoteWeight() {
      if (!emote) return 0
      var k = (clock - emote.start) / emote.length
      return Math.max(0, Math.min(1, Math.min(k / 0.15, (1 - k) / 0.2)))
    }

    /** The eye to draw for `side` (-1 left, 1 right): the emote's, else the mood's. */
    function eyeFor(side) {
      if (!emote) return cfg.eye
      switch (emote.name) {
        case "dizzy": return "swirl"
        case "wink": return side === 1 ? "dash" : cfg.eye
        case "yawn": return "dash"
        case "greet":
        case "celebrate": return "happy"
        default: return cfg.eye
      }
    }

    function easeOut(t) { return 1 - Math.pow(1 - t, 3) }
    function easeInOut(t) { return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2 }
    function easeBack(t) { var c1 = 1.7, c3 = c1 + 1; return 1 + c3 * Math.pow(t - 1, 3) + c1 * Math.pow(t - 1, 2) }
    function lerp(a, b, t) { return a + (b - a) * t }

    // keys: [[target, durationMs, ease], ...] played in order.
    function anim(prop, keys, done) {
      tweens[prop] = { keys: keys, index: 0, from: s[prop], start: clock * 1000, done: done || null }
    }

    function setState(next, force) {
      if (!states[next]) next = "idle"
      if (state === next && !force) return
      var previous = state
      state = next
      cfg = states[next]
      if (emote && !emoteAllowed(emote.name)) emote = null
      setBadge(cfg.badge, moodColor(next))

      if (next === "finished") {
        anim("oy", [[-0.12, 160, easeOut], [0, 380, easeBack]])
        emitLater("spark", 5, 200)
      } else if (next === "error") {
        anim("ox", [[0.06, 50, easeOut], [-0.06, 70, easeInOut], [0.04, 70, easeInOut], [0, 90, easeOut]])
      } else if (next === "approval") {
        anim("oy", [[-0.12, 150, easeOut], [0, 300, easeBack]])
      } else if (next === "ratelimit") {
        emit("sweat", 1)
      } else if (previous !== "") {
        blink()
      }
    }

    function setBadge(kind, color) {
      if (kind === badge && Qt.colorEqual(color, badgeColor)) return
      anim("badgeS", [[0, 90, easeInOut]], function() {
        badge = kind
        badgeColor = color
        if (kind !== "") anim("badgeS", [[1, 280, easeBack]])
      })
    }

    function blink() { anim("open", [[0.06, 70, easeInOut], [1, 130, easeOut]]) }

    function squash() {
      anim("sy", [[0.84, 70, easeOut], [1.07, 130, easeOut], [1, 170, easeInOut]])
      anim("sx", [[1.1, 70, easeOut], [0.96, 130, easeOut], [1, 170, easeInOut]])
    }

    function emitLater(type, count, delayMs) {
      particles.push({ type: "delay", fire: type, count: count, age: -delayMs / 1000, life: 0 })
    }

    function emit(type, count) {
      for (var i = 0; i < count; i++) {
        var isZ = type === "z"
        particles.push({
          type: type,
          x: isZ ? 0.85 : (Math.random() - 0.5) * 0.9,
          y: isZ ? -1.0 : -0.7 - Math.random() * 0.2,
          vx: isZ ? 0.12 + Math.random() * 0.06 : (Math.random() - 0.5) * 0.35,
          vy: isZ ? -(0.22 + Math.random() * 0.08) : -(0.45 + Math.random() * 0.35),
          age: -i * 0.14,
          life: 1.3 + Math.random() * 0.5,
          rot: Math.random() * Math.PI * 2,
          size: 0.15 + Math.random() * 0.08
        })
      }
    }

    function update(dt) {
      dt = Math.min(dt, 0.1)
      clock += dt
      var nowMs = clock * 1000

      for (var prop in tweens) {
        var tw = tweens[prop]
        var key = tw.keys[tw.index]
        var p = Math.min(1, Math.max(0, (nowMs - tw.start) / key[1]))
        s[prop] = tw.from + (key[0] - tw.from) * key[2](p)
        if (p >= 1) {
          tw.from = key[0]
          tw.index++
          tw.start = nowMs
          if (tw.index >= tw.keys.length) {
            delete tweens[prop]
            if (tw.done) tw.done()
          }
        }
      }

      var t = clock
      if (emote && t - emote.start > emote.length) emote = null
      // Now and then, while idle and nobody is pointing at him, play an emote.
      if (state !== "idle" || root.lookX !== 0 || root.lookY !== 0) {
        nextIdleEmote = Math.max(nextIdleEmote, t + 15)
      } else if (!emote && t > nextIdleEmote) {
        startEmote(idleEmotes[Math.floor(Math.random() * idleEmotes.length)])
        nextIdleEmote = t + 20 + Math.random() * 25
      }

      // Eyes follow the pointer; asleep, they settle in the middle.
      var tx = root.lookX
      var ty = root.lookY
      if (state === "sleeping") { tx = 0; ty = 0 }
      if (emote && emote.name === "look") {
        // Glance left, then right, then back.
        var lk = (t - emote.start) / emote.length
        tx = lk < 0.4 ? -0.9 : lk < 0.8 ? 0.9 : 0
        ty = -0.15
      }

      var kGen = 1 - Math.pow(0.0008, dt)
      var kLook = 1 - Math.pow(0.0025, dt)
      s.eyeX += (tx - s.eyeX) * kLook
      s.eyeY += (ty - s.eyeY) * kLook

      // Approval bounces; sleep bobs slowly up and down.
      var bounce = cfg.bounces ? -Math.abs(Math.sin(t * 5.2)) * 0.05
        : cfg.bobs ? Math.sin(t * 1.6) * 0.025 : 0
      if (!tweens.oy) s.oy += (bounce - s.oy) * kGen

      var tgSy = 1, tgSx = 1
      var wobble = emote && emote.name === "dizzy" ? Math.sin(t * 9) * 0.14 * emoteWeight() : 0
      if (!tweens.tilt) s.tilt += ((cfg.tilt || 0) + wobble - s.tilt) * (wobble !== 0 ? 1 - Math.pow(0.000001, dt) : kGen)
      if (!tweens.sy) s.sy += (tgSy - s.sy) * kGen
      if (!tweens.sx) s.sx += (tgSx - s.sx) * kGen

      // Snake running along the inner ring while working or thinking.
      if (cfg.snake) s.snakeAt = (s.snakeAt + dt * cfg.snake) % innerPath.length
      s.snakeOn += ((cfg.snake ? 1 : 0) - s.snakeOn) * kGen

      var target = moodColor(state)
      var kCol = 1 - Math.pow(0.002, dt)
      s.col = [lerp(s.col[0], target.r, kCol), lerp(s.col[1], target.g, kCol), lerp(s.col[2], target.b, kCol)]

      if (t > nextBlink) {
        if (state !== "sleeping") {
          blink()
          if (Math.random() < 0.22) emitLater("blink", 0, 230)
        }
        nextBlink = t + 2.2 + Math.random() * 3.2
      }

      if (t - lastAmbient > 1.3) {
        lastAmbient = t
        if (cfg.zz) emit("z", 1)
        if (cfg.sweat && Math.random() < 0.5) emit("sweat", 1)
      }

      var alive = []
      for (var i = 0; i < particles.length; i++) {
        var particle = particles[i]
        particle.age += dt
        if (particle.type === "delay") {
          if (particle.age < 0) alive.push(particle)
          else if (particle.fire === "blink") blink()
          else emit(particle.fire, particle.count)
        } else if (particle.age < particle.life) {
          alive.push(particle)
        }
      }
      particles = alive
    }

    function rgba(c, a) {
      var r = c.r !== undefined ? c.r : c[0]
      var g = c.g !== undefined ? c.g : c[1]
      var b = c.b !== undefined ? c.b : c[2]
      return "rgba(" + Math.round(r * 255) + "," + Math.round(g * 255) + "," + Math.round(b * 255) + "," + (a === undefined ? 1 : a) + ")"
    }

    function roundRect(ctx, x, y, w, h, r) {
      r = Math.max(0, Math.min(r, w / 2, h / 2))
      ctx.beginPath()
      ctx.moveTo(x + r, y)
      ctx.arcTo(x + w, y, x + w, y + h, r)
      ctx.arcTo(x + w, y + h, x, y + h, r)
      ctx.arcTo(x, y + h, x, y, r)
      ctx.arcTo(x, y, x + w, y, r)
      ctx.closePath()
    }

    function starPath(ctx, ro, ri) {
      ctx.beginPath()
      for (var i = 0; i < 10; i++) {
        var r = i % 2 ? ri : ro
        var a = -Math.PI / 2 + (i * Math.PI) / 5
        if (i === 0) ctx.moveTo(Math.cos(a) * r, Math.sin(a) * r)
        else ctx.lineTo(Math.cos(a) * r, Math.sin(a) * r)
      }
      ctx.closePath()
    }

    // W×H is the character's own size; the canvas is `overhang` larger on
    // every side, so drawing is shifted in by that much.
    function draw(ctx, W, H) {
      ctx.reset()
      ctx.translate(root.overhang, root.overhang)
      var side = Math.min(W, H) * 0.74
      var u = side / grid
      var R = side / 2
      var cx = W / 2 + s.ox * side
      var cy = H / 2 + s.oy * side + side * 0.04

      ctx.save()
      ctx.translate(cx, cy)
      if (s.tilt !== 0) ctx.rotate(s.tilt)
      ctx.scale(s.sx, s.sy)
      ctx.translate(-R, -R)

      // Tile, so the mark reads on any wallpaper.
      roundRect(ctx, -u * 0.6, -u * 0.6, side + u * 1.2, side + u * 1.2, u * 1.2)
      ctx.fillStyle = rgba(Commons.Color.popups.background)
      ctx.fill()

      // Outer ring, as one path so neighbouring cells don't leave seams.
      ctx.beginPath()
      for (var i = 0; i < outerCells.length; i++) ctx.rect(outerCells[i].col * u, outerCells[i].row * u, u + 0.01, u + 0.01)
      ctx.fillStyle = rgba(s.col)
      ctx.fill()

      // Inner ring: solid normally; while working or thinking it dims and
      // a bright snake with a fading tail runs along it.
      ctx.beginPath()
      for (var j = 0; j < innerPath.length; j++) ctx.rect(innerPath[j].col * u, innerPath[j].row * u, u + 0.01, u + 0.01)
      ctx.fillStyle = rgba(s.col, lerp(1, 0.22, s.snakeOn))
      ctx.fill()
      if (s.snakeOn > 0.02) {
        var tail = 7
        for (var k = 0; k <= tail; k++) {
          var at = s.snakeAt - k
          var index = ((Math.floor(at) % innerPath.length) + innerPath.length) % innerPath.length
          var glow = (1 - k / (tail + 1)) * s.snakeOn * 0.78
          ctx.fillStyle = rgba(s.col, glow)
          ctx.fillRect(innerPath[index].col * u, innerPath[index].row * u, u + 0.01, u + 0.01)
        }
      }

      drawEyes(ctx, u)
      drawOutfit(ctx, u)
      ctx.restore()

      if (badge !== "" && s.badgeS > 0.01) drawBadge(ctx, R, cx - R * 0.95 * s.sx, cy - R * 0.95 * s.sy)
      drawParticles(ctx, R, cx, cy)
      if (emote && emote.name === "dizzy") drawDizzyStars(ctx, R, cx, cy)
    }

    function drawEyes(ctx, u) {
      // Face area is the empty 9×9 middle (cells 3–11).
      var faceX = 3 * u, faceY = 3 * u, face = 9 * u
      var ex = s.eyeX * u * 1.6
      var ey = s.eyeY * u * 1.6
      ctx.fillStyle = rgba(s.col)
      ctx.strokeStyle = rgba(s.col)
      for (var side = -1; side <= 1; side += 2) {
        ctx.save()
        ctx.translate(faceX + face / 2 + side * u * 1.6 + ex, faceY + face * 0.36 + ey)
        drawEyeShape(ctx, eyeFor(side), u * 0.8, u * 1.8, side)
        ctx.restore()
      }
    }

    function drawEyeShape(ctx, shape, w, h, side) {
      if (shape === "wide") {
        drawEyeShape(ctx, "pill", w * 1.18, h * 1.12, side)
      } else if (shape === "pill") {
        var hh = Math.max(h * s.open, w * 0.3)
        ctx.fillRect(-w / 2, -hh / 2, w, hh)
      } else if (shape === "flat") {
        roundRect(ctx, -w * 0.8, -w * 0.22, w * 1.6, w * 0.44, w * 0.22)
        ctx.fill()
      } else if (shape === "happy") {
        ctx.lineWidth = w * 0.45
        ctx.lineCap = "round"
        ctx.beginPath()
        ctx.arc(0, h * 0.2, w * 0.85, Math.PI * 1.12, Math.PI * 1.88, false)
        ctx.stroke()
      } else if (shape === "swirl") {
        // Dizzy: a spinning spiral, the two eyes turning opposite ways.
        ctx.lineWidth = w * 0.32
        ctx.lineCap = "round"
        ctx.rotate(clock * 9 * side)
        ctx.beginPath()
        for (var a = 0; a <= Math.PI * 4; a += 0.35) {
          var r = w * 0.08 + a * w * 0.075
          if (a === 0) ctx.moveTo(Math.cos(a) * r, Math.sin(a) * r)
          else ctx.lineTo(Math.cos(a) * r, Math.sin(a) * r)
        }
        ctx.stroke()
      } else if (shape === "dash") {
        // Asleep: short flat dashes.
        ctx.fillRect(-w * 0.85, -w * 0.22, w * 1.7, w * 0.44)
      } else if (shape === "tired") {
        roundRect(ctx, -w / 2, -h * 0.02, w, h * 0.36, w / 2)
        ctx.fill()
        roundRect(ctx, -w * 0.65, -h * 0.1, w * 1.3, w * 0.22, w * 0.11)
        ctx.fill()
      }
    }

    function drawBadge(ctx, R, bx, by) {
      var t = clock
      var col = rgba(badgeColor)
      var ink = rgba(Commons.Color.popups.background)
      ctx.save()
      ctx.translate(bx, by)
      ctx.scale(s.badgeS, s.badgeS)
      if (badge === "dots") {
        var pw = R * 0.62, ph = R * 0.3
        roundRect(ctx, -pw / 2, -ph / 2, pw, ph, ph / 2)
        ctx.fillStyle = col
        ctx.fill()
        for (var i = 0; i < 3; i++) {
          var phase = (((t * 2.4 - i * 0.22) % 1) + 1) % 1
          var dotR = R * 0.048 * (1 + 0.4 * Math.max(0, Math.sin(phase * Math.PI * 2)))
          ctx.fillStyle = ink
          ctx.beginPath()
          ctx.arc((i - 1) * R * 0.16, 0, dotR, 0, Math.PI * 2, false)
          ctx.fill()
        }
      } else if (badge === "bang" || badge === "question") {
        ctx.fillStyle = ink
        ctx.beginPath()
        ctx.arc(0, 0, R * 0.26, 0, Math.PI * 2, false)
        ctx.fill()
        ctx.fillStyle = col
        ctx.beginPath()
        ctx.arc(0, 0, R * 0.2, 0, Math.PI * 2, false)
        ctx.fill()
        ctx.fillStyle = ink
        ctx.font = "bold " + Math.round(R * 0.28) + "px sans-serif"
        ctx.textAlign = "center"
        ctx.textBaseline = "middle"
        ctx.fillText(badge === "bang" ? "!" : "?", 0, R * 0.02)
      } else {
        ctx.fillStyle = ink
        ctx.beginPath()
        ctx.arc(0, 0, R * 0.17, 0, Math.PI * 2, false)
        ctx.fill()
        ctx.fillStyle = col
        ctx.beginPath()
        ctx.arc(0, 0, R * 0.115, 0, Math.PI * 2, false)
        ctx.fill()
      }
      ctx.restore()
    }

    // Three little stars circling above his head.
    function drawDizzyStars(ctx, R, cx, cy) {
      ctx.save()
      ctx.globalAlpha = emoteWeight()
      ctx.fillStyle = rgba(statusColors.warning)
      for (var i = 0; i < 3; i++) {
        var a = clock * 4 + i * Math.PI * 2 / 3
        ctx.save()
        ctx.translate(cx + Math.cos(a) * R * 0.75, cy - R * 1.1 + Math.sin(a) * R * 0.18)
        ctx.rotate(a)
        starPath(ctx, R * 0.13, R * 0.05)
        ctx.fill()
        ctx.restore()
      }
      ctx.restore()
    }

    function drawParticles(ctx, R, cx, cy) {
      for (var i = 0; i < particles.length; i++) {
        var p = particles[i]
        if (p.type === "delay" || p.age <= 0) continue
        var k = p.age / p.life
        var a = k < 0.2 ? k / 0.2 : 1 - (k - 0.2) / 0.8
        var sz = R * p.size * (1 + k * 0.4)
        ctx.save()
        ctx.translate(cx + (p.x + p.vx * p.age) * R * 1.3, cy + (p.y + p.vy * p.age) * R * 1.3)
        ctx.globalAlpha = Math.min(1, Math.max(0, a))
        if (p.type === "spark") {
          ctx.rotate(p.rot)
          ctx.fillStyle = rgba(statusColors.success)
          starPath(ctx, sz * 0.8, sz * 0.18)
          ctx.fill()
        } else if (p.type === "sweat") {
          ctx.fillStyle = rgba(statusColors.working)
          ctx.beginPath()
          ctx.moveTo(0, -sz)
          ctx.quadraticCurveTo(sz * 0.8, sz * 0.2, 0, sz * 0.6)
          ctx.quadraticCurveTo(-sz * 0.8, sz * 0.2, 0, -sz)
          ctx.fill()
        } else if (p.type === "z") {
          // Pixel-art z in the mark's color, big or small.
          var px = sz * (p.size > 0.19 ? 0.4 : 0.27)
          ctx.fillStyle = rgba(s.col)
          for (var zr = 0; zr < zGlyph.length; zr++) {
            for (var zc = 0; zc < zGlyph[zr].length; zc++) {
              if (zGlyph[zr].charAt(zc) === "#") ctx.fillRect((zc - 2) * px, (zr - 2) * px, px + 0.01, px + 0.01)
            }
          }
        }
        ctx.restore()
      }
    }
  }

  // Extra room around the character so rising z's, sparks, and sweat
  // drops aren't clipped. Drawing only: input still uses the item's bounds.
  readonly property real overhang: Math.round(Math.min(width, height) * 0.45)

  Canvas {
    id: canvas
    anchors.fill: parent
    anchors.margins: -root.overhang
    renderStrategy: Canvas.Cooperative
    onPaint: engine.draw(getContext("2d"), root.width, root.height)
  }

  FrameAnimation {
    running: root.running && root.visible
    onTriggered: {
      engine.update(frameTime)
      canvas.requestPaint()
    }
  }
}
