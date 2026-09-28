# Samsung MDC probe

Read-only status probe for Samsung commercial displays that speak Multiple Display Control (MDC) over TCP.

The probe sends get requests only. Every packet has a data length of zero. It does not change power, backlight, input source, or video-wall layout.

## Address map

`config/panels.json` selects the subnet:

```json
{
  "network_prefix": "192.168.0",
  "host_offset": 1,
  "port": 1515
}
```

Panel `N` (1-based) is `network_prefix.(host_offset + N):port`. With this config, panel 1 is `192.168.0.2:1515` and panel 2 is `192.168.0.3:1515`.

If `display_id` is omitted, the probe tries display ids 0, 1, and the panel number, and keeps the first id that answers. Set `"display_id"` to skip that search.

## Wall desk prototype

The browser UI sends power and brightness to the selected Samsung screens. Window layouts open Edge on the wall computers.

```bash
cd web
npm install
npm run dev -- --hostname 0.0.0.0 --port 4721
```

Open `http://127.0.0.1:4721`.

Copy the `layouts` folder to `C:\layouts`. `layouts/computer-101/` is computer 1 (`192.168.0.101`): Independent, Split, Focus, Focus split, and Full on TV1–TV8. `layouts/computer-102/` is computer 2 (`192.168.0.102`) with the same presets on TV9–TV12 and TV14–TV17. `layouts/computer-103/` is computer 3 (`192.168.0.103`): Independent puts one page on TV13 and one on TV18, and Full covers both monitors. The `Edge-*.bat` files open those pages in Microsoft Edge.

## Probe

From this directory:

```bash
python -m samsung_controller.probe --panels 1
```

`--panels` takes 1-based numbers (`1`, `1,2`, or `1-4`). Add `--json` for a JSON report. Exit status is `0` when a panel answers, `2` when none do, and `1` when the config or arguments are invalid.

## Tests

```bash
python -m unittest tests.test_readonly_probe
```

The test stands up a local fake panel and checks that power, backlight, input, and wall commands arrive as empty gets.
