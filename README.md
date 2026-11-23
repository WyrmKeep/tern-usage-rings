<h1 align="center">Usage Rings</h1>

<p align="center">
  A <a href="https://stencil.so/tern">Tern</a> plugin that shows how much of each AI coding subscription you have used.
</p>

<p align="center">
  <img src="screenshots/card.png" width="440" alt="Four usage rings under the tab list, with the Claude card open above them">
</p>

Each provider gets a ring under your tab list. The ring fills as your accounts get used, and hovering it lists every account behind it. The figures come from `omp usage`, so there are no API keys to paste and nothing to set up.

## Install

```sh
tern plugin install github.com/WyrmKeep/tern-usage-rings
```

Open the command palette, run **Choose usage providers**, and pick the rings you want.

You need Tern 0.9.26 with omp signed in to at least one account.

## Reading a ring

| You see | It means |
| --- | --- |
| A coloured arc | The share you have used. Green turns amber at 50%, orange at 80% and red at 95%. |
| `38%` | The same share as a number. |
| `22h05m` under a full ring | The limit is used up and resets in 22 hours and 5 minutes. |
| `$36` | A prepaid balance, for providers that sell credits. |
| `n/a` | omp has no figure for this provider. |
| A purple dot | One account is signed out. Sign in again with omp. |
| A dimmed icon | The figure is old. The last refresh failed, or omp only had it in its history. |

If you have several accounts with one provider, the ring pools them. It counts all of them together, in whichever limit is closest to running out.

Hover a ring to open its card, or click to pin it. The card shows the pool, then each account with its plan, limits and reset times.

## Choosing providers

<p align="center">
  <img src="screenshots/picker.png" width="560" alt="The provider picker, with a check beside each provider that has a ring">
</p>

Press Enter to show or hide a provider. The picker stays open so you can change several.

Claude, Codex, Gemini, OpenCode and Grok are always listed. Any other provider omp reports, such as Devin or Kimi Code, appears under its own name.

## Where the rings sit

| Your tabs | The rings |
| --- | --- |
| Down the side | Dock under the tab filter, four to a row, up to sixteen. |
| Down the side, hidden until hover | Line up along the top edge in the Rail and Float layouts, and stay in the widget bar in Tiles and Studio. |
| Along the top | Stay in the widget bar at a smaller size. |

The rings are ordinary widgets named `usage-rings/<provider>`, so Tern's widget editor can reorder them.

## On a Stream Deck

<p align="center">
  <img src="https://raw.githubusercontent.com/WyrmKeep/tern-stream-deck/main/screenshots/deck.jpg" width="440" alt="A Stream Deck showing the usage rings above keys for Tern sessions and agents">
</p>

[Tern Stream Deck](https://github.com/WyrmKeep/tern-stream-deck) puts the same rings on the keys of an Elgato Stream Deck, beside a key for each Tern session and a count of working agents. It shows the reading this plugin keeps, so the deck and the window show the same figures.

## Good to know

- Figures refresh every five minutes. There is no manual refresh.
- The plugin only runs `omp usage`. It makes no network requests of its own.
- It keeps the last reading, account emails included, in Tern's plugin data folder so a new window can draw at once.
- It has a window half only. Install it on the machine that shows the Tern window.
- Linux is the only tested platform. The plugin also looks for omp in Tern's macOS and Windows folders, but it has not run on either.
- The dock restyles Tern's own `#sidebar` and `#widgetbar`. A Tern update that renames them will need an update here.

<details>
<summary>How it works</summary>

`window.luau` runs `omp usage --json` and keeps the answer in the plugin's key-value store. Every Tern window shares that store, so only one window asks omp per interval.

When omp's live report has no limits for a provider, the plugin reads the newest figures from `omp usage --history` instead and says so on the card.

`lib/model.luau` turns omp's JSON into one state per ring. It does no I/O. The pool comes from omp's own `capacity` figures, or from the mean across accounts when omp gives none. A limit for one model tier, such as Claude's Fable limit, appears on the card but only moves the ring when it is the account's only limit.

Tern's widgets and cards carry no class per row, so `lib/sheet.luau` writes a small sheet of custom properties addressed by widget name and row number. `usage-rings.css` reads them and does the drawing.

</details>

<details>
<summary>Development</summary>

Link the checkout so Tern loads it in place and reloads it when a file changes.

```sh
tern plugin link .
```

To work from a file instead of live accounts, save a report and start Tern with it. Quit a running Tern first.

```sh
omp usage --json --redact > usage.json
USAGE_RINGS_FIXTURE=$PWD/usage.json tern
```

`USAGE_RINGS_HISTORY_FIXTURE` does the same for `omp usage --history --json`. `tern plugin types .` writes `tern.d.luau` for luau-lsp.

</details>

## Remove

```sh
tern plugin remove usage-rings
```

## License

[MIT](LICENSE)
