# Hommies

![Hommie in each of its moods](preview.png)

Hommie is a floating companion for the Omarchy desktop that watches your coding
agents (Claude Code, Codex, OpenCode, and Omacode). When an agent asks for a
permission, asks you a question, or finishes a turn, Hommie's mood changes and
the item shows up in a card beside it and in a bell in the top bar. You can
approve or decline permissions and answer questions from there, or leave the
answer to the agent's own prompt and use Hommie as a read-only mirror.

## Requirements

- Omarchy 4 (Quattro shell)
- Node.js 20.10 or newer
- The `@thisisayande/hommies` npm package, which provides the local bridge
  (`agent-fold-bridge`) this plugin starts and the hooks each agent reports through

## Install

1. Install the bridge package and pick the agents to hook up:

   ```sh
   npm install -g @thisisayande/hommies
   hommies setup
   ```

   `hommies setup` lists the agents it finds and lets you choose which ones to
   connect. Before it changes an agent's config, it saves a copy next to it as
   `<file>.agent-fold-backup-<time>`. For Codex, approve the new hooks in its
   `/hooks` screen; restart OpenCode to load its plugin. Omacode needs no setup.

2. Add the plugin:

   ```sh
   omarchy plugin add https://github.com/ayandexyz/hommies-plugin
   ```

   Then enable it and add **Hommies** to the bar from the Omarchy plugin
   settings.

## Remove

```sh
hommies uninstall
npm uninstall -g @thisisayande/hommies
omarchy plugin remove io.github.ayandexyz.hommies
```

Run `hommies uninstall` before removing the npm package: it takes out only the
hook entries setup added and keeps the rest of each config. Hooks left behind by
removing the package first do nothing, except OpenCode's `plugin` entry, which
you then delete from `~/.config/opencode/opencode.json` by hand.

## What it does on your machine

- Runs with your normal user permissions.
- The plugin starts one background process, `agent-fold-bridge`, and restarts it
  if it exits.
- The bridge listens on `127.0.0.1` only, on a random port, and every request must
  carry a random token. It writes the port and token to
  `$XDG_DATA_HOME/agent-fold/port.json`.
- Pending items are kept in memory and are lost when the bridge stops. Hommie's
  own preferences are saved in `$XDG_DATA_HOME/agent-fold/floating.json`.
- Desktop notifications use `notify-send`; optional sounds use `pw-play` or `paplay`.
- No telemetry, analytics, or update checks. Nothing leaves your machine.
- Agent configs are changed only when you run `hommies setup` or
  `hommies uninstall`, never by the plugin.

If the bridge is not running, every agent falls back to its own normal prompt.

## Settings

Right-click Hommie for its settings: whether questions are answered here or in
the agent's CLI, desktop notifications, sounds, showing over fullscreen windows,
and moving it to the next monitor. Drag it to move it. The bar bell has the same
answer-surface, notification, and sound settings.

## Source

The bridge, the agent hooks, and development notes live in
[ayandexyz/Hommies](https://github.com/ayandexyz/Hommies). Report issues there.

## License

MIT. See [LICENSE](LICENSE).
