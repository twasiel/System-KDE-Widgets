# Sys Manager

System monitor for Linux / KDE Plasma 6: CPU, RAM, GPU, storage and network usage plus
hardware models (CPU, GPU, RAM modules, drives). Python backend (standard library only,
no root needed) + Plasma widgets in QML.

## Requirements

- KDE Plasma 6 (`kpackagetool6`)
- Python 3.8+ (standard library only)
- Optional: `nvidia-smi` for NVIDIA proprietary-driver GPUs, `pci.ids` (hwdata) for GPU names

## Install

```bash
git clone <this repo> && cd Sys-Manager
./install.sh            # build + install widgets, and the `sys-manager` command
./install.sh uninstall
```

Run it as your normal user — **not with sudo** (widgets are installed per user into
`~/.local/share/plasma/plasmoids`).

Then right-click the desktop or a panel → **Add or Manage Widgets** → search **"Sys Manager"**.
After updating already-placed widgets: `systemctl --user restart plasma-plasmashell`.

## Widgets

| Widget                       | Panel shows             | Expanded / desktop view |
|------------------------------|-------------------------|-------------------------|
| Sys Manager: CPU Monitor     | CPU %                   | model, usage gauge, frequency, temperature, P/E cores, load, governor, per-core bars |
| Sys Manager: Memory Monitor  | RAM % (or GiB)          | used/available/cached, swap, part numbers, installed modules (type, speed, maker) |
| Sys Manager: GPU Monitor     | GPU %                   | model + codename, usage, per-engine usage, frequency, VRAM/shared memory, temp, power |
| Sys Manager: Storage Monitor | root usage %            | drive models, read/write speed, per-mount usage |
| Sys Manager: Network Monitor | ↓/↑ speed               | interfaces, IPv4, Wi-Fi signal, totals |
| Sys Manager: System Overview | CPU/RAM/GPU (selectable)| everything above + system info, battery, top processes |

Every widget has settings (right-click → Configure): update interval, graph history,
panel label/graph, warning colors, and which sections the overview shows.

## Terminal

```bash
sys-manager            # interactive monitor (q quit, +/- refresh speed)
sys-manager info       # hardware models
sys-manager json cpu gpu --pretty
```

## How data is collected

- **CPU**: `/proc/stat`, cpufreq and topology in sysfs, hwmon (coretemp / k10temp)
- **RAM**: `/proc/meminfo`; module models from SMBIOS via udev (`/run/udev/data/+dmi:id`)
- **GPU**: model from `pci.ids`; usage from DRM fdinfo (Intel i915/xe, AMD, others),
  `gpu_busy_percent` (AMD), `nvidia-smi` (NVIDIA proprietary); Intel RC6 idle residency
- **Disk / Network**: `/proc/diskstats`, `/proc/mounts`, `/proc/net/dev`

Rates need two samples: each widget passes `--client <id>` and the previous sample is
kept in `$XDG_RUNTIME_DIR/sys-manager/`.

## Layout

```
backend/sysmanager.py       backend + terminal UI
plasma/common/              shared QML (sections, graphs, gauges, config pages)
plasma/widgets/<name>/      per-widget metadata.json and main.qml
install.sh                  builds packages into build/ and installs with kpackagetool6
```

## License

[MIT](LICENSE)
