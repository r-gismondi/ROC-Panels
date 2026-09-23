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

Panel `N` (1-based) is `network_prefix.(host_offset + N - 1):port`. Panel 1 is `192.168.0.1:1515`.

If `display_id` is omitted, the probe tries display ids 0, 1, and the panel number, and keeps the first id that answers. Set `"display_id"` to skip that search.

## Run

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
