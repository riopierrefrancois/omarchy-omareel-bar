# Omareel bar widget for Omarchy

A record button for the Omarchy bar that drives [Omareel](https://github.com/omacom/omareel).

- **Idle:** a record icon. Click it for a menu laid out like Omareel's launcher: one big **Record** button that offers **Full screen** or **Window**, then **System audio**, **Microphone** and **Camera** switches, with pickers for the microphone and the camera, plus **Open Omareel** and **Edit last recording**.
- **Recording:** the icon turns red with the elapsed time. Click to stop (Omareel opens the editor); the menu also offers **Discard**.
- **Middle-click** records the full screen straight away, or stops.
- Menu keys: R full screen, W window, A system audio, M microphone, C camera, E edit last; arrows move, left/right open device lists, Esc goes back.

Source choices are saved in Omareel's own settings (`~/.config/omareel/settings.json`), so the launcher and `omareel record` use them too.

## Install

```bash
omarchy plugin add https://github.com/riopierrefrancois/omarchy-omareel-bar.git --enable
```

It goes beside the clock (`centerBegin`). Needs `omareel`, `jq` and `gpu-screen-recorder`.

## Commands

`omarchy-shell omareel record | window | stop | cancel | toggle | status` — handy for keybindings.

## Files

- `manifest.json` — the plugin's manifest (id `omareel.recorder`).
- `Panel.qml` — the bar button and menu.
- `tools.sh` — reads and writes Omareel's settings and lists cameras and microphones.

After editing, `omarchy restart shell` shows the change.
