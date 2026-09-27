# Layouts for 192.168.0.101

Copy the `layouts` folder to `C:\layouts` on this computer, so these files live in `C:\layouts\computer-101`. Double-click a preset there. The windows have to open on this computer's desktop.

Display 1 must be the left monitor (HDMI 1) and display 2 the right monitor (HDMI 2). Both are 1920×1080, landscape, 100% scale, with the tops aligned.

| HDMI 1 | HDMI 2 |
|---|---|
| TV1, TV2 | TV3, TV4 |
| TV5, TV6 | TV7, TV8 |

| File | What you should see |
|---|---|
| `Independent.bat` | Eight windows, one per screen TV1–TV8 |
| `Split.bat` | Left monitor filled, right monitor filled |
| `Focus.bat` | Left column, a center block across both monitors, right column |
| `Focus-Split.bat` | TV1, TV5, the center block, TV4, and TV8 |
| `Full.bat` | One window across both monitors |
| `Close.bat` | Closes the colored test windows |

Press Esc in a colored test window to close that preset.

Edge presets open https://ccv2.mtllc.us/landing in the normal signed-in Edge profile, one window per section. Run `Edge-Close.bat` between tests. Leave the command window open while a preset is on screen.

| File | Edge windows |
|---|---|
| `Edge-Independent.bat` | Eight windows, one per screen TV1–TV8 |
| `Edge-Split.bat` | One window on HDMI 1 and one on HDMI 2 |
| `Edge-Focus.bat` | Left column, center block, right column |
| `Edge-Focus-Split.bat` | TV1, TV5, the center block, TV4, and TV8 |
| `Edge-Full.bat` | One window across both monitors |
| `Edge-Close.bat` | Closes the Edge windows for this computer |
