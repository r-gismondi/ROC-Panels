# Layout test for 192.168.0.102

Copy this folder onto computer 2 and double-click a preset there. The windows have to open on that computer's desktop.

Display 1 must be the left monitor (HDMI 1) and display 2 the right monitor (HDMI 2). Both are 1920×1080, landscape, 100% scale, with the tops aligned.

| File | What you should see on computer 2 |
|---|---|
| `Independent.bat` | Eight windows, one per screen TV9–TV12 and TV14–TV17 |
| `Dual-Focus-1.bat` | HDMI 1 filled, plus two columns on HDMI 2 |
| `Dual-Focus-2.bat` | One window on HDMI 1 and one on HDMI 2 |
| `Dual-Focus-3.bat` | Left column, a center block across both monitors, right column |
| `Full.bat` | One window across both monitors |
| `Close.bat` | Closes the colored test windows |

Press Esc in a colored test window to close that preset.

Edge presets open https://ccv2.mtllc.us/landing in the normal signed-in Edge profile, one window per section. The window frame and the browser bar are clipped off so the page fills the section. Run `Edge-Close.bat` to close only those windows. An Edge window you opened yourself stays open.

| File | Edge windows |
|---|---|
| `Edge-Independent.bat` | Eight windows, one per screen TV9–TV12 and TV14–TV17 |
| `Edge-Dual-Focus-1.bat` | Three windows: HDMI 1, then two columns on HDMI 2 |
| `Edge-Dual-Focus-2.bat` | One window on HDMI 1 and one on HDMI 2 |
| `Edge-Dual-Focus-3.bat` | Left column, center block, right column |
| `Edge-Full.bat` | One window across both monitors |
| `Edge-Close.bat` | Closes the Edge test windows |

TV13 and TV18 are on 192.168.0.103, so these files do not cover them.
