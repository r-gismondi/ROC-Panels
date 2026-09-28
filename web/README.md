# Wall desk

Preview UI for display power, brightness, and window layouts.

```bash
npm install
npm run dev -- --hostname 0.0.0.0 --port 4721
```

Open `http://127.0.0.1:4721`. Run this on a Windows computer that can reach the wall. Preset buttons start `C:\layouts\computer-101`, `computer-102`, and `computer-103` on 192.168.0.101, .102, and .103. Set `LAYOUT_USER` and `LAYOUT_PASSWORD` to the wall Administrator account before starting. On and Off, and the brightness bar, send those commands to the selected screens. The root README covers the display probe as well.
