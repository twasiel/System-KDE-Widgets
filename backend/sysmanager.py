#!/usr/bin/env python3
"""
Sys Manager backend - hardware information and live usage for Linux.

Pure standard library: everything is read from /proc, /sys and udev data, so
it works without root and without extra Python packages.

Usage:
    sysmanager.py json [SECTION ...] [--client ID] [--pretty]
    sysmanager.py info             # static hardware summary (models)
    sysmanager.py tui              # interactive terminal monitor
    sysmanager.py                  # same as "tui" when run in a terminal

Sections: system cpu ram gpu disk net sensors procs   (default: all but procs)

Rates and percentages (CPU %, GPU %, network/disk speed) need two samples.
When called repeatedly with the same --client ID, the previous sample is kept
in $XDG_RUNTIME_DIR/sys-manager/ so each call measures the interval since the
last call. Without previous data, two samples are taken 0.25 s apart.
"""

import argparse
import fcntl
import glob
import json
import os
import re
import shutil
import socket
import struct
import subprocess
import sys
import time

VERSION = "1.0.0"
ALL_SECTIONS = ["system", "cpu", "ram", "gpu", "disk", "net", "sensors", "procs"]
DEFAULT_SECTIONS = [s for s in ALL_SECTIONS if s != "procs"]

CACHE_DIR = os.path.join(os.environ.get("XDG_CACHE " \
"_HOME") or os.path.expanduser("~/.cache"), "sys-manager")
RUNTIME_DIR = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or CACHE_DIR, "sys-manager")
CLK_TCK = os.sysconf("SC_CLK_TCK")
PAGE_SIZE = os.sysconf("SC_PAGE_SIZE")
STALE_AFTER = 60.0  # seconds; older previous samples are discarded

GPU_VENDORS = {"0x8086": "Intel", "0x1002": "AMD", "0x10de": "NVIDIA", "0x1af4": "Virtio",
               "0x15ad": "VMware", "0x1234": "QEMU", "0x5143": "Qualcomm", "0x13b5": "ARM"}
REAL_FS = {"ext2", "ext3", "ext4", "btrfs", "xfs", "f2fs", "vfat", "exfat", "ntfs", "ntfs3",
           "fuseblk", "zfs", "jfs", "reiserfs", "bcachefs", "hfsplus", "nilfs2"}


# --------------------------------------------------------------------------- helpers

def read(path, default=None):
    try:
        with open(path, errors="replace") as f:
            return f.read().strip()
    except OSError:
        return default


def read_int(path, default=None):
    try:
        return int(read(path))
    except (TypeError, ValueError):
        return default


def parse_cpu_list(text):
    """'0-3,8,10-11' -> [0,1,2,3,8,10,11]"""
    out = []
    for part in (text or "").split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            a, b = part.split("-", 1)
            out.extend(range(int(a), int(b) + 1))
        else:
            out.append(int(part))
    return out


def pct(part, whole):
    if not whole:
        return None
    return round(max(0.0, min(100.0, 100.0 * part / whole)), 1)


def fmt_bytes(n, digits=1):
    if n is None:
        return "-"
    n = float(n)
    for unit in ("B", "KiB", "MiB", "GiB", "TiB", "PiB"):
        if abs(n) < 1024 or unit == "PiB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.{digits}f} {unit}"
        n /= 1024


def fmt_duration(sec):
    sec = int(sec)
    d, sec = divmod(sec, 86400)
    h, sec = divmod(sec, 3600)
    m, _ = divmod(sec, 60)
    if d:
        return f"{d}d {h}h {m}m"
    if h:
        return f"{h}h {m}m"
    return f"{m}m"


def atomic_write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = f"{path}.{os.getpid()}.tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, separators=(",", ":"))
    os.replace(tmp, path)


def load_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


# --------------------------------------------------------------------------- pci.ids

PCI_IDS_PATHS = [
    "/usr/share/hwdata/pci.ids", "/usr/share/misc/pci.ids", "/usr/share/pci.ids",
    "/usr/local/share/hwdata/pci.ids", "/run/current-system/sw/share/hwdata/pci.ids",
    "/run/current-system/sw/share/pci.ids",
]


def find_pci_ids():
    for p in PCI_IDS_PATHS:
        if os.path.isfile(p):
            return p
    # NixOS: the hwdata package lives in the store but is often not linked anywhere.
    hits = glob.glob("/nix/store/*-hwdata-*/share/hwdata/pci.ids")
    return sorted(hits)[-1] if hits else None


def pci_lookup(vendor_id, device_id):
    """Return (vendor_name, device_name) from pci.ids, or (None, None)."""
    path = find_pci_ids()
    if not path:
        return None, None
    v = vendor_id.lower().replace("0x", "")
    d = device_id.lower().replace("0x", "")
    vendor_name = None
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            in_vendor = False
            for line in f:
                if not line.strip() or line.startswith("#"):
                    continue
                if not line.startswith("\t"):
                    if in_vendor:
                        break  # left our vendor block without finding the device
                    if line[:4].lower() == v:
                        in_vendor = True
                        vendor_name = line[4:].strip()
                    continue
                if in_vendor and not line.startswith("\t\t") and line[1:5].lower() == d:
                    return vendor_name, line[5:].strip()
    except OSError:
        pass
    return vendor_name, None


def pretty_gpu_name(vendor_short, pci_name):
    """'Raptor Lake-P [Iris Xe Graphics]' -> ('Intel Iris Xe Graphics', 'Raptor Lake-P')"""
    if not pci_name:
        return None, None
    m = re.match(r"^(.*?)\s*\[(.+)\]\s*(.*)$", pci_name)
    if m:
        codename, marketing = m.group(1).strip(), m.group(2).strip()
        if m.group(3):
            marketing += " " + m.group(3).strip()
    else:
        codename, marketing = None, pci_name
    if vendor_short and not marketing.lower().startswith(vendor_short.lower()):
        marketing = f"{vendor_short} {marketing}"
    return marketing, codename


# --------------------------------------------------------------------------- static info

def boot_id():
    return read("/proc/sys/kernel/random/boot_id", "")


def static_cpu():
    model = None
    vendor = None
    cpuinfo = read("/proc/cpuinfo", "")
    for line in cpuinfo.splitlines():
        key, _, val = line.partition(":")
        key = key.strip()
        if key == "model name" and not model:
            model = val.strip()
        elif key == "vendor_id" and not vendor:
            vendor = val.strip()
        elif key in ("Hardware", "Model") and not model:  # ARM
            model = val.strip()
    if not model:
        model = read("/sys/firmware/devicetree/base/model", "Unknown CPU").strip("\x00")
    model = re.sub(r"\s+", " ", model)

    cpus = sorted(int(m.group(1)) for p in glob.glob("/sys/devices/system/cpu/cpu[0-9]*")
                  if (m := re.search(r"cpu(\d+)$", p)))
    threads = len(cpus) or os.cpu_count() or 1
    cores = set()
    for c in cpus:
        sib = read(f"/sys/devices/system/cpu/cpu{c}/topology/core_cpus_list") or \
            read(f"/sys/devices/system/cpu/cpu{c}/topology/thread_siblings_list") or str(c)
        pkg = read(f"/sys/devices/system/cpu/cpu{c}/topology/physical_package_id", "0")
        cores.add((pkg, sib))
    max_khz = max((read_int(f"/sys/devices/system/cpu/cpu{c}/cpufreq/cpuinfo_max_freq", 0) for c in cpus), default=0)
    min_khz = min((read_int(f"/sys/devices/system/cpu/cpu{c}/cpufreq/cpuinfo_min_freq", 0) for c in cpus), default=0)

    # Intel hybrid (P-cores / E-cores)
    hybrid = None
    p_cpus = parse_cpu_list(read("/sys/devices/cpu_core/cpus"))
    e_cpus = parse_cpu_list(read("/sys/devices/cpu_atom/cpus"))
    if p_cpus and e_cpus:
        def core_count(lst):
            return len({read(f"/sys/devices/system/cpu/cpu{c}/topology/core_cpus_list", str(c)) for c in lst})
        hybrid = {"p_cores": core_count(p_cpus), "e_cores": core_count(e_cpus),
                  "p_threads": len(p_cpus), "e_threads": len(e_cpus)}

    cache = {}
    for idx in glob.glob("/sys/devices/system/cpu/cpu0/cache/index*"):
        level, ctype, size = read(f"{idx}/level"), read(f"{idx}/type"), read(f"{idx}/size")
        if level and size:
            name = f"L{level}" + ("d" if ctype == "Data" else "i" if ctype == "Instruction" else "")
            cache[name] = size
    l3 = read("/sys/devices/system/cpu/cpu0/cache/index3/size")
    if l3:
        cache["L3"] = l3

    return {
        "model": model, "vendor": vendor, "arch": os.uname().machine,
        "cores": len(cores) or threads, "threads": threads, "hybrid": hybrid,
        "freq_max_mhz": round(max_khz / 1000) if max_khz else None,
        "freq_min_mhz": round(min_khz / 1000) if min_khz else None,
        "cache": cache,
    }


def udev_dmi_properties():
    props = {}
    text = read("/run/udev/data/+dmi:id")
    if text is None and shutil.which("udevadm"):
        try:
            text = subprocess.run(["udevadm", "info", "--query=property", "/sys/devices/virtual/dmi/id"],
                                  capture_output=True, text=True, timeout=2).stdout
            text = "\n".join("E:" + l for l in text.splitlines())
        except (OSError, subprocess.SubprocessError):
            text = ""
    for line in (text or "").splitlines():
        if line.startswith("E:") and "=" in line:
            k, v = line[2:].split("=", 1)
            props[k] = v.strip()
    return props


def static_ram():
    props = udev_dmi_properties()
    modules = {}
    for k, v in props.items():
        m = re.match(r"MEMORY_DEVICE_(\d+)_(.+)", k)
        if m:
            modules.setdefault(int(m.group(1)), {})[m.group(2)] = v
    out = []
    for i in sorted(modules):
        mod = modules[i]
        size = int(mod.get("SIZE", "0") or 0)
        if not size or mod.get("PRESENT") == "0":
            continue
        speed = mod.get("CONFIGURED_SPEED_MTS") or mod.get("SPEED_MTS")
        out.append({
            "slot": mod.get("LOCATOR"), "bank": mod.get("BANK_LOCATOR"), "size": size,
            "type": mod.get("TYPE"), "form_factor": mod.get("FORM_FACTOR"),
            "speed_mts": int(speed) if speed and speed.isdigit() else None,
            "manufacturer": mod.get("MANUFACTURER"), "part_number": (mod.get("PART_NUMBER") or "").strip() or None,
            "rank": mod.get("RANK"),
        })
    summary = None
    if out:
        types = sorted({m["type"] for m in out if m["type"]})
        speeds = sorted({m["speed_mts"] for m in out if m["speed_mts"]})
        makers = sorted({m["manufacturer"] for m in out if m["manufacturer"] and m["manufacturer"] not in ("Unknown", "Not Specified")})
        parts = sorted({m["part_number"] for m in out if m["part_number"]})
        bits = []
        if makers:
            bits.append("/".join(makers))
        if types:
            bits.append("/".join(types))
        if speeds:
            bits.append("/".join(str(s) for s in speeds) + " MT/s")
        summary = {"text": " ".join(bits) or None, "modules": len(out), "part_numbers": parts,
                   "installed": sum(m["size"] for m in out),
                   "max_capacity": int(props["MEMORY_ARRAY_MAX_CAPACITY"]) if props.get("MEMORY_ARRAY_MAX_CAPACITY", "").isdigit() else None}
    return {"modules": out, "summary": summary}


def gpu_cards():
    cards = []
    for card in sorted(glob.glob("/sys/class/drm/card[0-9]*")):
        if "-" in os.path.basename(card):
            continue  # connector, e.g. card1-eDP-1
        dev = os.path.realpath(os.path.join(card, "device"))
        vendor = read(f"{dev}/vendor")
        if not vendor:
            continue
        driver = os.path.basename(os.path.realpath(f"{dev}/driver")) if os.path.exists(f"{dev}/driver") else None
        uevent = dict(l.split("=", 1) for l in (read(f"{dev}/uevent", "") or "").splitlines() if "=" in l)
        cards.append({"card": card, "dev": dev, "vendor_id": vendor, "device_id": read(f"{dev}/device"),
                      "driver": driver or uevent.get("DRIVER"), "pci_slot": uevent.get("PCI_SLOT_NAME"),
                      "boot_vga": read(f"{dev}/boot_vga") == "1"})
    return cards


def nvidia_smi(fields, slot=None):
    exe = shutil.which("nvidia-smi")
    if not exe:
        return None
    cmd = [exe, f"--query-gpu=pci.bus_id,{','.join(fields)}", "--format=csv,noheader,nounits"]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=3).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    for line in out.splitlines():
        vals = [v.strip() for v in line.split(",")]
        if slot is None or vals[0].lower().endswith(slot.lower()[-7:]):
            return dict(zip(fields, vals[1:]))
    return None


def static_gpu():
    out = []
    for c in gpu_cards():
        vshort = GPU_VENDORS.get(c["vendor_id"])
        vname, dname = pci_lookup(c["vendor_id"], c["device_id"] or "")
        name, codename = pretty_gpu_name(vshort or vname, dname)
        if c["driver"] == "nvidia":
            smi = nvidia_smi(["name"], c["pci_slot"])
            if smi and smi.get("name"):
                name = smi["name"] if smi["name"].startswith("NVIDIA") else "NVIDIA " + smi["name"]
        if c["driver"] == "amdgpu":
            pn = read(f"{c['dev']}/product_name")
            if pn:
                name = pn
        if not name:
            name = f"{vshort or 'Unknown'} GPU [{c['vendor_id'][2:]}:{(c['device_id'] or '')[2:]}]"
        integrated = c["driver"] in ("i915", "xe") and c["pci_slot"] and c["pci_slot"].startswith("0000:00:")
        if c["driver"] == "amdgpu":
            vram_total = read_int(f"{c['dev']}/mem_info_vram_total", 0)
            integrated = vram_total and vram_total <= 2 * 1024 ** 3 and c["pci_slot"] and c["boot_vga"] is not None and \
                read_int(f"{c['dev']}/mem_info_vis_vram_total", 0) == vram_total
        out.append({"name": name, "codename": codename, "vendor": vshort or vname, "driver": c["driver"],
                    "pci_slot": c["pci_slot"], "pci_id": f"{c['vendor_id'][2:]}:{(c['device_id'] or '')[2:]}",
                    "card": os.path.basename(c["card"]), "integrated": bool(integrated), "primary": c["boot_vga"]})
    return out


def static_system():
    osr = {}
    for line in (read("/etc/os-release", "") or "").splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            osr[k] = v.strip().strip('"')
    dmi = lambda n: (read(f"/sys/class/dmi/id/{n}") or "").strip()
    junk = {"", "To Be Filled By O.E.M.", "Default string", "System Product Name", "Not Applicable", "None", "System manufacturer"}
    vendor = dmi("sys_vendor")
    product = " ".join(x for x in (dmi("product_family"), dmi("product_name")) if x not in junk)
    board = " ".join(x for x in (dmi("board_vendor"), dmi("board_name")) if x not in junk)
    u = os.uname()
    plasma = None
    if shutil.which("plasmashell"):
        try:
            plasma = subprocess.run(["plasmashell", "--version"], capture_output=True, text=True, timeout=3).stdout.split()[-1]
        except (OSError, subprocess.SubprocessError, IndexError):
            pass
    return {"os": osr.get("PRETTY_NAME") or osr.get("NAME") or "Linux", "kernel": u.release,
            "hostname": u.nodename, "arch": u.machine,
            "vendor": vendor if vendor not in junk else None, "product": product or None, "board": board or None,
            "bios": " ".join(x for x in (dmi("bios_vendor"), dmi("bios_version")) if x) or None,
            "desktop": os.environ.get("XDG_CURRENT_DESKTOP"), "plasma": plasma,
            "session": os.environ.get("XDG_SESSION_TYPE")}


def static_drives():
    out = []
    for blk in sorted(glob.glob("/sys/block/*")):
        name = os.path.basename(blk)
        if re.match(r"^(loop|ram|zram|dm-|md|sr|fd|nbd)", name):
            continue
        size = read_int(f"{blk}/size", 0) * 512
        if not size:
            continue
        model = (read(f"{blk}/device/model") or read(f"{blk}/device/name") or "").strip()
        vendor = (read(f"{blk}/device/vendor") or "").strip()
        if vendor and model and not model.lower().startswith(vendor.lower()) and vendor not in ("ATA",):
            model = f"{vendor} {model}"
        kind = "NVMe SSD" if name.startswith("nvme") else "eMMC" if name.startswith("mmcblk") else \
            ("HDD" if read(f"{blk}/queue/rotational") == "1" else "SSD")
        if read(f"{blk}/removable") == "1" or "usb" in os.path.realpath(blk):
            kind = "Removable"
        out.append({"name": name, "model": model or name, "size": size, "type": kind})
    return out


def get_static(refresh=False):
    """Hardware models etc. Cached per boot in ~/.cache/sys-manager/static.json."""
    path = os.path.join(CACHE_DIR, "static.json")
    bid = boot_id()
    if not refresh:
        cached = load_json(path)
        if cached and cached.get("boot_id") == bid and cached.get("version") == VERSION:
            return cached
    data = {"version": VERSION, "boot_id": bid, "cpu": static_cpu(), "ram": static_ram(),
            "gpu": static_gpu(), "system": static_system(), "drives": static_drives()}
    try:
        atomic_write_json(path, data)
    except OSError:
        pass
    return data


# --------------------------------------------------------------------------- raw samples (for deltas)

def raw_cpu():
    out = {}
    for line in (read("/proc/stat", "") or "").splitlines():
        if line.startswith("cpu"):
            parts = line.split()
            out[parts[0]] = [int(x) for x in parts[1:9]]
    return out


def raw_drm_clients():
    """Sum per-client engine time from /proc/*/fdinfo (works for i915, xe, amdgpu, msm, ...)."""
    clients = {}  # (pdev, client_id) -> {engine: [busy, total_or_None], ...}
    meta = {}     # pdev -> {"capacity": {engine: n}, "mem": bytes}
    mem_seen = set()
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            fds = os.listdir(fd_dir)
        except OSError:
            continue
        for fd in fds:
            try:
                if not os.readlink(f"{fd_dir}/{fd}").startswith("/dev/dri/"):
                    continue
                with open(f"/proc/{pid}/fdinfo/{fd}") as f:
                    info = f.read()
            except OSError:
                continue
            kv = {}
            for line in info.splitlines():
                k, _, v = line.partition(":")
                kv[k.strip()] = v.strip()
            cid, pdev = kv.get("drm-client-id"), kv.get("drm-pdev")
            if not cid or not pdev:
                continue
            key = f"{pdev}|{cid}"
            if key in clients:
                continue
            engines = {}
            m = meta.setdefault(pdev, {"capacity": {}, "mem": 0})
            for k, v in kv.items():
                if k.startswith("drm-engine-capacity-"):
                    m["capacity"][k[20:]] = int(v or 1)
                elif k.startswith("drm-engine-"):
                    engines[k[11:]] = [int(v.split()[0]), None]
                elif k.startswith("drm-cycles-"):
                    eng = k[11:]
                    tot = kv.get(f"drm-total-cycles-{eng}")
                    engines[eng] = [int(v.split()[0]), int(tot.split()[0]) if tot else None]
                elif k.startswith("drm-resident-") and key not in mem_seen:
                    num, _, unit = v.partition(" ")
                    mult = {"KiB": 1024, "MiB": 1024 ** 2, "GiB": 1024 ** 3}.get(unit, 1)
                    try:
                        m["mem"] += int(num) * mult
                    except ValueError:
                        pass
            mem_seen.add(key)
            clients[key] = engines
    return clients, meta


def raw_gpu():
    data = {"clients": {}, "meta": {}, "rc6": {}, "energy": {}}
    cards = gpu_cards()
    if any(c["driver"] not in ("nvidia",) for c in cards):
        data["clients"], data["meta"] = raw_drm_clients()
    for c in cards:
        slot = c["pci_slot"]
        rc6 = read_int(f"{c['card']}/gt/gt0/rc6_residency_ms") or read_int(f"{c['card']}/power/rc6_residency_ms")
        if rc6 is not None:
            data["rc6"][slot] = rc6
        for e in glob.glob(f"{c['dev']}/hwmon/hwmon*/energy1_input"):
            v = read_int(e)
            if v is not None:
                data["energy"][slot] = v
    return data


def raw_net():
    out = {}
    for line in (read("/proc/net/dev", "") or "").splitlines()[2:]:
        name, _, rest = line.partition(":")
        name = name.strip()
        f = rest.split()
        if len(f) >= 9:
            out[name] = [int(f[0]), int(f[8])]
    return out


def raw_disk():
    out = {}
    whole = {os.path.basename(p) for p in glob.glob("/sys/block/*")}
    for line in (read("/proc/diskstats", "") or "").splitlines():
        f = line.split()
        if len(f) >= 10 and f[2] in whole and not re.match(r"^(loop|ram|zram|dm-|sr|fd)", f[2]):
            out[f[2]] = [int(f[5]) * 512, int(f[9]) * 512, int(f[12]) if len(f) > 12 else 0]
    return out


def raw_procs():
    out = {}
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open(f"/proc/{pid}/stat") as f:
                s = f.read()
        except OSError:
            continue
        r = s.rfind(")")
        name = s[s.find("(") + 1:r]
        f = s[r + 2:].split()
        try:
            out[pid] = [int(f[11]) + int(f[12]), int(f[21]) * PAGE_SIZE, name]
        except (IndexError, ValueError):
            pass
    return out


RAW_FUNCS = {"cpu": raw_cpu, "gpu": raw_gpu, "net": raw_net, "disk": raw_disk, "procs": raw_procs}


def take_raw(sections):
    raw = {"t": time.monotonic(), "boot_id": boot_id()}
    for s in sections:
        if s in RAW_FUNCS:
            raw[s] = RAW_FUNCS[s]()
    return raw


# --------------------------------------------------------------------------- live sections

def hwmon_sensors():
    out = []
    for hw in sorted(glob.glob("/sys/class/hwmon/hwmon*")):
        chip = read(f"{hw}/name", os.path.basename(hw))
        for t in sorted(glob.glob(f"{hw}/temp*_input")):
            v = read_int(t)
            if v is None:
                continue
            base = t[:-6]
            out.append({"chip": chip, "kind": "temp", "label": read(f"{base}_label") or os.path.basename(base),
                        "value": round(v / 1000, 1), "unit": "°C",
                        "crit": (read_int(f"{base}_crit") or 0) / 1000 or None,
                        "path": hw})
        for fan in sorted(glob.glob(f"{hw}/fan*_input")):
            v = read_int(fan)
            if v is None:
                continue
            base = fan[:-6]
            out.append({"chip": chip, "kind": "fan", "label": read(f"{base}_label") or os.path.basename(base),
                        "value": v, "unit": "RPM", "path": hw})
    return out


def cpu_temp(sensors):
    prefs = [("coretemp", "Package id 0"), ("k10temp", "Tctl"), ("k10temp", "Tdie"), ("zenpower", "Tdie"),
             ("zenpower", "Tctl"), ("cpu_thermal", None), ("acpitz", None)]
    for chip, label in prefs:
        for s in sensors:
            if s["kind"] == "temp" and s["chip"] == chip and (label is None or s["label"] == label):
                return s["value"]
    for z in glob.glob("/sys/class/thermal/thermal_zone*"):
        if read(f"{z}/type") in ("x86_pkg_temp", "cpu-thermal", "soc_thermal"):
            v = read_int(f"{z}/temp")
            if v:
                return round(v / 1000, 1)
    return None


def section_cpu(static, prev, now, sensors):
    st = static["cpu"]
    usage, per_core = None, []
    if prev and "cpu" in prev:
        for name, cur in now["cpu"].items():
            old = prev["cpu"].get(name)
            if not old:
                continue
            total = sum(cur) - sum(old)
            idle = (cur[3] + cur[4]) - (old[3] + old[4])
            u = pct(total - idle, total) if total > 0 else 0.0
            if name == "cpu":
                usage = u
                d = [c - o for c, o in zip(cur, old)]
                breakdown = {"user": pct(d[0] + d[1], total), "system": pct(d[2] + d[5] + d[6], total),
                             "iowait": pct(d[4], total), "steal": pct(d[7], total)} if total > 0 else {}
            else:
                per_core.append(u)
    freqs = []
    for c in range(st["threads"]):
        v = read_int(f"/sys/devices/system/cpu/cpu{c}/cpufreq/scaling_cur_freq")
        if v:
            freqs.append(v / 1000)
    if not freqs:
        for line in (read("/proc/cpuinfo", "") or "").splitlines():
            if line.startswith("cpu MHz"):
                freqs.append(float(line.split(":")[1]))
    load = (read("/proc/loadavg", "0 0 0 0/0") or "0 0 0").split()
    governor = read("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor")
    epp = read("/sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference")
    procs_running, procs_total = (load[3].split("/") + ["0"])[:2] if len(load) > 3 else ("0", "0")
    return {
        **st,
        "usage": usage, "per_core": per_core,
        "breakdown": breakdown if usage is not None else {},
        "freq_mhz": round(sum(freqs) / len(freqs)) if freqs else None,
        "freq_peak_mhz": round(max(freqs)) if freqs else None,
        "temp_c": cpu_temp(sensors),
        "load": [float(x) for x in load[:3]],
        "processes": int(procs_total) if procs_total.isdigit() else None,
        "governor": governor, "epp": epp,
    }


def section_ram(static):
    mi = {}
    for line in (read("/proc/meminfo", "") or "").splitlines():
        k, _, v = line.partition(":")
        parts = v.split()
        if parts:
            mi[k] = int(parts[0]) * 1024
    total = mi.get("MemTotal", 0)
    avail = mi.get("MemAvailable", mi.get("MemFree", 0))
    used = total - avail
    cached = mi.get("Cached", 0) + mi.get("SReclaimable", 0) - mi.get("Shmem", 0)
    swap_total = mi.get("SwapTotal", 0)
    swap_used = swap_total - mi.get("SwapFree", 0)
    zram = []
    for z in glob.glob("/sys/block/zram*"):
        mm = (read(f"{z}/mm_stat") or "").split()
        if mm:
            zram.append({"name": os.path.basename(z), "orig": int(mm[0]), "compressed": int(mm[1])})
    return {
        **static["ram"],
        "total": total, "used": used, "available": avail, "free": mi.get("MemFree", 0),
        "usage": pct(used, total), "cached": max(cached, 0), "buffers": mi.get("Buffers", 0),
        "shared": mi.get("Shmem", 0),
        "swap_total": swap_total, "swap_used": swap_used, "swap_usage": pct(swap_used, swap_total) if swap_total else None,
        "zram": zram,
    }


def amd_sclk(dev):
    cur = mx = None
    for line in (read(f"{dev}/pp_dpm_sclk", "") or "").splitlines():
        m = re.search(r"(\d+)\s*Mhz", line, re.I)
        if m:
            v = int(m.group(1))
            mx = max(mx or 0, v)
            if "*" in line:
                cur = v
    return cur, mx


def section_gpu(static, prev, now):
    out = []
    raw = now.get("gpu", {})
    old = (prev or {}).get("gpu")
    dt = (now["t"] - prev["t"]) if prev else None
    cards = {c["pci_slot"]: c for c in gpu_cards()}
    for g in static["gpu"]:
        c = cards.get(g["pci_slot"])
        if not c:
            continue
        dev, card, slot = c["dev"], c["card"], g["pci_slot"]
        info = {**g, "usage": None, "engines": {}, "freq_mhz": None, "freq_max_mhz": None,
                "mem_used": None, "mem_total": None, "mem_label": "VRAM", "temp_c": None,
                "power_w": None, "rc6": None}

        # --- per-engine utilisation from DRM fdinfo (delta over clients present in both samples)
        if old and dt and dt > 0:
            busy, cap = {}, raw.get("meta", {}).get(slot, {}).get("capacity", {})
            for key, engines in raw.get("clients", {}).items():
                if not key.startswith(slot + "|"):
                    continue
                o = old.get("clients", {}).get(key)
                if not o:
                    continue
                for eng, (val, tot) in engines.items():
                    if eng not in o:
                        continue
                    ov, ot = o[eng]
                    if tot is not None and ot is not None:  # xe: cycles / total cycles
                        frac = (val - ov) / (tot - ot) if tot > ot else 0
                    else:  # ns of busy time
                        frac = (val - ov) / (dt * 1e9)
                    busy[eng] = busy.get(eng, 0) + max(frac, 0)
            for eng, frac in busy.items():
                info["engines"][eng] = round(min(100.0, 100.0 * frac / max(cap.get(eng, 1), 1)), 1)
            if info["engines"]:
                info["usage"] = max(info["engines"].values())
            elif raw.get("clients") is not None:
                info["usage"] = 0.0
            # RC6 = GPU powered-down residency (Intel)
            if slot in raw.get("rc6", {}) and slot in old.get("rc6", {}):
                info["rc6"] = pct(raw["rc6"][slot] - old["rc6"][slot], dt * 1000)
            if slot in raw.get("energy", {}) and slot in old.get("energy", {}):
                info["power_w"] = round((raw["energy"][slot] - old["energy"][slot]) / 1e6 / dt, 1)

        drv = g["driver"]
        if drv == "i915":
            info["freq_mhz"] = read_int(f"{card}/gt_act_freq_mhz")
            info["freq_max_mhz"] = read_int(f"{card}/gt_RP0_freq_mhz") or read_int(f"{card}/gt_max_freq_mhz")
        elif drv == "xe":
            for fq in sorted(glob.glob(f"{dev}/tile0/gt0/freq0")):
                info["freq_mhz"] = read_int(f"{fq}/act_freq")
                info["freq_max_mhz"] = read_int(f"{fq}/rp0_freq") or read_int(f"{fq}/max_freq")
        elif drv == "amdgpu":
            b = read_int(f"{dev}/gpu_busy_percent")
            if b is not None:
                info["usage"] = float(b)
            info["freq_mhz"], info["freq_max_mhz"] = amd_sclk(dev)
            info["mem_used"] = read_int(f"{dev}/mem_info_vram_used")
            info["mem_total"] = read_int(f"{dev}/mem_info_vram_total")
            if g["integrated"]:
                info["mem_label"] = "VRAM (carve-out)"
        elif drv == "nvidia":
            smi = nvidia_smi(["utilization.gpu", "memory.used", "memory.total", "temperature.gpu",
                              "power.draw", "clocks.gr", "clocks.max.gr"], slot)
            if smi:
                num = lambda k: float(smi[k]) if re.match(r"^[\d.]+$", smi.get(k, "")) else None
                info["usage"] = num("utilization.gpu")
                info["mem_used"] = int(num("memory.used") * 1024 ** 2) if num("memory.used") is not None else None
                info["mem_total"] = int(num("memory.total") * 1024 ** 2) if num("memory.total") is not None else None
                info["temp_c"] = num("temperature.gpu")
                info["power_w"] = num("power.draw")
                info["freq_mhz"] = num("clocks.gr")
                info["freq_max_mhz"] = num("clocks.max.gr")

        if info["mem_used"] is None and slot in raw.get("meta", {}):
            # integrated GPU: system RAM currently held by GPU clients
            info["mem_used"] = raw["meta"][slot].get("mem") or None
            info["mem_label"] = "Shared memory"

        # hwmon on the device (amdgpu, discrete Intel, nouveau)
        for hw in glob.glob(f"{dev}/hwmon/hwmon*"):
            if info["temp_c"] is None:
                t = read_int(f"{hw}/temp1_input")
                if t:
                    info["temp_c"] = round(t / 1000, 1)
            if info["power_w"] is None:
                p = read_int(f"{hw}/power1_average") or read_int(f"{hw}/power1_input")
                if p:
                    info["power_w"] = round(p / 1e6, 1)
        info["mem_usage"] = pct(info["mem_used"], info["mem_total"]) if info["mem_total"] else None
        out.append(info)
    # discrete / primary first
    out.sort(key=lambda x: (x["integrated"], not x["primary"]))
    return out


def section_disk(static, prev, now):
    mounts, seen = [], {}
    for line in (read("/proc/mounts", "") or "").splitlines():
        f = line.split()
        if len(f) < 3 or f[2] not in REAL_FS:
            continue
        src, mnt = f[0], f[1].replace("\\040", " ")
        if mnt.startswith(("/nix/store", "/snap/", "/var/lib/docker", "/run/")):
            continue
        try:
            st = os.statvfs(mnt)
        except OSError:
            continue
        total = st.f_blocks * st.f_frsize
        if not total:
            continue
        free = st.f_bavail * st.f_frsize
        used = total - st.f_bfree * st.f_frsize
        entry = {"mount": mnt, "device": src, "fs": f[2], "total": total, "used": used, "free": free,
                 "usage": pct(used, used + free)}
        if src in seen:  # btrfs subvolumes / bind mounts: keep the shortest mount path
            if len(mnt) < len(seen[src]["mount"]):
                seen[src].update(entry)
            continue
        seen[src] = entry
        mounts.append(entry)
    mounts.sort(key=lambda m: (m["mount"] != "/", m["mount"]))

    read_bps = write_bps = None
    per_drive = {}
    if prev and "disk" in prev:
        dt = now["t"] - prev["t"]
        if dt > 0:
            read_bps = write_bps = 0
            for name, (r, w, busy_ms) in now["disk"].items():
                o = prev["disk"].get(name)
                if not o:
                    continue
                rb, wb = max(r - o[0], 0) / dt, max(w - o[1], 0) / dt
                read_bps += rb
                write_bps += wb
                per_drive[name] = {"read_bps": round(rb), "write_bps": round(wb),
                                   "busy": pct(busy_ms - o[2], dt * 1000)}
    drives = [{**d, **per_drive.get(d["name"], {})} for d in static["drives"]]
    return {"mounts": mounts, "drives": drives,
            "read_bps": round(read_bps) if read_bps is not None else None,
            "write_bps": round(write_bps) if write_bps is not None else None}


def iface_ipv4(name):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        res = fcntl.ioctl(s.fileno(), 0x8915, struct.pack("256s", name[:15].encode()))  # SIOCGIFADDR
        return socket.inet_ntoa(res[20:24])
    except OSError:
        return None
    finally:
        s.close()


def default_iface():
    for line in (read("/proc/net/route", "") or "").splitlines()[1:]:
        f = line.split()
        if len(f) > 2 and f[1] == "00000000":
            return f[0]
    return None


def wifi_info(name):
    for line in (read("/proc/net/wireless", "") or "").splitlines()[2:]:
        if line.strip().startswith(name + ":"):
            f = line.split()
            try:
                quality = float(f[2].rstrip("."))
                signal = float(f[3].rstrip("."))
                return {"quality": round(min(100, quality / 70 * 100)), "signal_dbm": signal}
            except (IndexError, ValueError):
                return None
    return None


def section_net(prev, now):
    dt = (now["t"] - prev["t"]) if prev and "net" in prev else None
    default = default_iface()
    ifaces, rx_total, tx_total = [], 0, 0
    for name, (rx, tx) in now["net"].items():
        if name == "lo":
            continue
        base = f"/sys/class/net/{name}"
        physical = os.path.exists(f"{base}/device")
        virtual_prefix = name.startswith(("veth", "docker", "br-", "virbr", "vnet", "tap", "tun"))
        state = read(f"{base}/operstate", "unknown")
        rx_bps = tx_bps = None
        if dt and dt > 0 and name in prev["net"]:
            o = prev["net"][name]
            rx_bps, tx_bps = max(rx - o[0], 0) / dt, max(tx - o[1], 0) / dt
            if not virtual_prefix:
                rx_total += rx_bps
                tx_total += tx_bps
        wireless = os.path.exists(f"{base}/wireless") or os.path.exists(f"{base}/phy80211")
        speed = read_int(f"{base}/speed")
        ifaces.append({"name": name, "state": state, "physical": physical, "virtual": virtual_prefix,
                       "wireless": wireless, "ipv4": iface_ipv4(name), "mac": read(f"{base}/address"),
                       "speed_mbps": speed if speed and speed > 0 else None,
                       "wifi": wifi_info(name) if wireless else None,
                       "rx_bps": round(rx_bps) if rx_bps is not None else None,
                       "tx_bps": round(tx_bps) if tx_bps is not None else None,
                       "rx_total": rx, "tx_total": tx, "default": name == default})
    ifaces.sort(key=lambda i: (not i["default"], i["virtual"], not i["physical"], i["name"]))
    return {"interfaces": ifaces, "default": default,
            "rx_bps": round(rx_total) if dt else None, "tx_bps": round(tx_total) if dt else None}


def battery_info():
    for b in sorted(glob.glob("/sys/class/power_supply/*")):
        if read(f"{b}/type") != "Battery" or read(f"{b}/scope") == "Device":
            continue
        power = read_int(f"{b}/power_now")
        if power is None:
            cur, volt = read_int(f"{b}/current_now"), read_int(f"{b}/voltage_now")
            power = cur * volt / 1e6 if cur and volt else None
        full = read_int(f"{b}/energy_full") or read_int(f"{b}/charge_full")
        design = read_int(f"{b}/energy_full_design") or read_int(f"{b}/charge_full_design")
        return {"name": os.path.basename(b), "capacity": read_int(f"{b}/capacity"), "status": read(f"{b}/status"),
                "power_w": round(power / 1e6, 1) if power else None,
                "health": pct(full, design) if full and design else None,
                "model": " ".join(x for x in (read(f"{b}/manufacturer"), read(f"{b}/model_name")) if x) or None}
    return None


def section_system(static):
    up = float((read("/proc/uptime", "0") or "0").split()[0])
    return {**static["system"], "uptime": up, "uptime_text": fmt_duration(up), "battery": battery_info(),
            "time": time.strftime("%Y-%m-%d %H:%M:%S")}


def section_procs(static, prev, now, limit=8):
    if not prev or "procs" not in prev:
        return {"top_cpu": [], "top_mem": []}
    dt = now["t"] - prev["t"]
    threads = static["cpu"]["threads"]
    rows = []
    for pid, (ticks, rss, name) in now["procs"].items():
        o = prev["procs"].get(pid)
        cpu = ((ticks - o[0]) / CLK_TCK / dt * 100 / threads) if o and dt > 0 else 0.0
        rows.append({"pid": int(pid), "name": name, "cpu": round(max(cpu, 0), 1), "rss": rss})
    top_cpu = sorted(rows, key=lambda r: r["cpu"], reverse=True)[:limit]
    top_mem = sorted(rows, key=lambda r: r["rss"], reverse=True)[:limit]
    for r in top_cpu + top_mem:
        r["name"] = proc_display_name(r["pid"], r["name"])
    return {"top_cpu": top_cpu, "top_mem": top_mem, "count": len(rows)}


def proc_display_name(pid, comm):
    """comm is cut to 15 chars; use argv[0] and undo NixOS '.foo-wrapped' wrapper names."""
    name = comm
    cmd = read(f"/proc/{pid}/cmdline", "") or ""
    argv0 = cmd.split("\x00")[0]
    if argv0:
        base = os.path.basename(argv0.split(" ")[0])
        if base and (base.startswith(comm[:8]) or len(comm) >= 15 or comm.startswith(".")):
            name = base
    m = re.match(r"^\.(.+)-wrapped$", name)
    return m.group(1) if m else name


# --------------------------------------------------------------------------- collector

class Collector:
    """Keeps the previous raw sample so rates can be computed."""

    def __init__(self, client=None):
        self.client = re.sub(r"[^A-Za-z0-9_.-]", "_", client) if client else None
        self.prev = None
        if self.client:
            self.state_path = os.path.join(RUNTIME_DIR, f"state-{self.client}.json")
            self.prev = load_json(self.state_path)

    def collect(self, sections):
        static = get_static()
        need_delta = [s for s in sections if s in RAW_FUNCS]
        prev = self.prev
        if prev and (prev.get("boot_id") != boot_id() or time.monotonic() - prev.get("t", 0) > STALE_AFTER
                     or any(s not in prev for s in need_delta)):
            prev = None
        if need_delta and prev is None:
            prev = take_raw(need_delta)
            time.sleep(0.25)
        now = take_raw(need_delta)
        self.prev = now
        if self.client:
            try:
                atomic_write_json(self.state_path, now)
            except OSError:
                pass

        sensors = hwmon_sensors() if ("sensors" in sections or "cpu" in sections) else []
        out = {"version": VERSION, "timestamp": time.time(), "interval": round(now["t"] - prev["t"], 3) if prev else None}
        for s in sections:
            if s == "system":
                out["system"] = section_system(static)
            elif s == "cpu":
                out["cpu"] = section_cpu(static, prev, now, sensors)
            elif s == "ram":
                out["ram"] = section_ram(static)
            elif s == "gpu":
                out["gpu"] = section_gpu(static, prev, now)
            elif s == "disk":
                out["disk"] = section_disk(static, prev, now)
            elif s == "net":
                out["net"] = section_net(prev, now)
            elif s == "sensors":
                out["sensors"] = [{k: v for k, v in x.items() if k != "path"} for x in sensors]
            elif s == "procs":
                out["procs"] = section_procs(static, prev, now)
        return out


# --------------------------------------------------------------------------- text / TUI

def info_text():
    st = get_static(refresh=True)
    c, r, s = st["cpu"], st["ram"], st["system"]
    lines = [f"System : {' '.join(x for x in (s['vendor'], s['product']) if x) or '-'}",
             f"OS     : {s['os']}  (kernel {s['kernel']}, {s['arch']})"]
    if s.get("plasma"):
        lines.append(f"Desktop: KDE Plasma {s['plasma']} ({s.get('session') or '?'})")
    hy = c.get("hybrid")
    cores = f"{c['cores']} cores / {c['threads']} threads"
    if hy:
        cores += f"  ({hy['p_cores']}P + {hy['e_cores']}E)"
    lines.append(f"CPU    : {c['model']}  -  {cores}" + (f", up to {c['freq_max_mhz']} MHz" if c["freq_max_mhz"] else ""))
    for g in st["gpu"]:
        extra = f" ({g['codename']})" if g.get("codename") else ""
        lines.append(f"GPU    : {g['name']}{extra}  [{g['driver']}, {g['pci_id']}]")
    total = int((read("/proc/meminfo", "MemTotal: 0 kB") or "").split()[1]) * 1024
    if r["summary"]:
        sm = r["summary"]
        lines.append(f"RAM    : {fmt_bytes(sm['installed'], 0)} {sm['text'] or ''}  ({sm['modules']} modules"
                     + (f", part {', '.join(sm['part_numbers'])}" if sm["part_numbers"] else "") + ")")
    else:
        lines.append(f"RAM    : {fmt_bytes(total)}")
    for d in st["drives"]:
        lines.append(f"Drive  : {d['model']}  {fmt_bytes(d['size'], 0)} {d['type']}")
    return "\n".join(lines)


def run_tui(interval=1.0):
    import curses

    def bar(width, value):
        value = 0 if value is None else value
        filled = int(round(width * value / 100))
        return "█" * filled + "░" * (width - filled)

    def main(scr):
        nonlocal interval
        curses.curs_set(0)
        curses.use_default_colors()
        curses.start_color()
        for i, col in enumerate((curses.COLOR_GREEN, curses.COLOR_YELLOW, curses.COLOR_RED, curses.COLOR_CYAN, curses.COLOR_MAGENTA), 1):
            curses.init_pair(i, col, -1)
        scr.nodelay(True)
        coll = Collector()
        sections = ALL_SECTIONS
        coll.collect(sections)
        time.sleep(0.3)

        def col_for(v):
            v = v or 0
            return curses.color_pair(1 if v < 60 else 2 if v < 85 else 3)

        while True:
            d = coll.collect(sections)
            scr.erase()
            h, w = scr.getmaxyx()
            y = 0

            def put(text, attr=0, x=0):
                nonlocal y
                if y < h - 1:
                    try:
                        scr.addnstr(y, x, text, max(w - x - 1, 0), attr)
                    except curses.error:
                        pass

            def line(text="", attr=0):
                nonlocal y
                put(text, attr)
                y += 1

            def meter(label, value, suffix=""):
                nonlocal y
                bw = max(10, min(40, w - 40))
                put(f"{label:<8}", curses.A_BOLD)
                put(bar(bw, value), col_for(value), 9)
                put(f" {value if value is not None else '-':>5}% {suffix}", 0, 9 + bw)
                y += 1

            s, c, r = d["system"], d["cpu"], d["ram"]
            title = f" Sys Manager — {s['hostname']} — {s['os']} — up {s['uptime_text']} "
            line(title.center(w - 1, "─"), curses.color_pair(4) | curses.A_BOLD)
            bat = s.get("battery")
            if bat:
                line(f"Battery {bat['capacity']}% {bat['status']}" + (f", {bat['power_w']} W" if bat['power_w'] else "")
                     + (f", health {bat['health']}%" if bat['health'] else ""))
            line()
            hy = c.get("hybrid")
            line(f"CPU  {c['model']}  ({c['cores']}C/{c['threads']}T" + (f", {hy['p_cores']}P+{hy['e_cores']}E" if hy else "") + ")",
                 curses.color_pair(5) | curses.A_BOLD)
            meter("Usage", c["usage"], f"{c['freq_mhz'] or '-'} MHz  " + (f"{c['temp_c']}°C  " if c["temp_c"] else "")
                  + f"load {' '.join(f'{x:.2f}' for x in c['load'])}")
            cores = c["per_core"]
            per_row = max(1, (w - 2) // 14)
            for i in range(0, len(cores), per_row):
                put("  " + "".join(f"{j:>2} {bar(6, v)}{v:>3.0f}% "[:14] for j, v in enumerate(cores[i:i + per_row], i)))
                y += 1
            line()
            line(f"RAM  {fmt_bytes(r['total'])}" + (f"  {r['summary']['text']}" if r.get("summary") and r["summary"]["text"] else "")
                 + (f"  [{', '.join(r['summary']['part_numbers'])}]" if r.get("summary") and r["summary"]["part_numbers"] else ""),
                 curses.color_pair(5) | curses.A_BOLD)
            meter("Used", r["usage"], f"{fmt_bytes(r['used'])} / {fmt_bytes(r['total'])}  cache {fmt_bytes(r['cached'])}")
            if r["swap_total"]:
                meter("Swap", r["swap_usage"], f"{fmt_bytes(r['swap_used'])} / {fmt_bytes(r['swap_total'])}")
            for g in d["gpu"]:
                line()
                line(f"GPU  {g['name']}" + (f" ({g['codename']})" if g.get("codename") else "") + f"  [{g['driver']}]",
                     curses.color_pair(5) | curses.A_BOLD)
                extra = []
                if g["freq_mhz"]:
                    extra.append(f"{g['freq_mhz']:.0f}/{g['freq_max_mhz'] or '?'} MHz")
                if g["temp_c"]:
                    extra.append(f"{g['temp_c']}°C")
                if g["power_w"]:
                    extra.append(f"{g['power_w']} W")
                if g["rc6"] is not None:
                    extra.append(f"RC6 {g['rc6']}%")
                meter("Usage", g["usage"], "  ".join(extra))
                if g["engines"]:
                    line("        " + "  ".join(f"{k} {v:.0f}%" for k, v in g["engines"].items()))
                if g["mem_used"] is not None:
                    if g["mem_total"]:
                        meter("VRAM", g["mem_usage"], f"{fmt_bytes(g['mem_used'])} / {fmt_bytes(g['mem_total'])}")
                    else:
                        line(f"{g['mem_label']}: {fmt_bytes(g['mem_used'])}")
            line()
            dk, n = d["disk"], d["net"]
            line(f"DISK  read {fmt_bytes(dk['read_bps'])}/s  write {fmt_bytes(dk['write_bps'])}/s", curses.color_pair(5) | curses.A_BOLD)
            for m in dk["mounts"][:4]:
                meter(m["mount"][:8], m["usage"], f"{fmt_bytes(m['used'])} / {fmt_bytes(m['total'])} {m['fs']}")
            line()
            line(f"NET  ↓ {fmt_bytes(n['rx_bps'])}/s  ↑ {fmt_bytes(n['tx_bps'])}/s", curses.color_pair(5) | curses.A_BOLD)
            for i in n["interfaces"][:3]:
                if i["state"] == "up" or i["ipv4"]:
                    line(f"  {i['name']:<12} {i['ipv4'] or '-':<16} ↓ {fmt_bytes(i['rx_bps'])}/s  ↑ {fmt_bytes(i['tx_bps'])}/s"
                         + (f"  signal {i['wifi']['signal_dbm']:.0f} dBm" if i.get("wifi") else ""))
            line()
            p = d["procs"]
            line(f"{'PID':>7}  {'CPU%':>5}  {'MEM':>9}  NAME", curses.A_REVERSE)
            for row in p["top_cpu"]:
                line(f"{row['pid']:>7}  {row['cpu']:>5.1f}  {fmt_bytes(row['rss']):>9}  {row['name']}")
            y = h - 1
            put(f" q: quit   +/-: refresh speed ({interval:g}s) ".ljust(w - 1), curses.A_REVERSE)
            scr.refresh()
            end = time.time() + interval
            while time.time() < end:
                ch = scr.getch()
                if ch in (ord("q"), ord("Q"), 27):
                    return
                if ch == ord("+"):
                    interval = max(0.25, interval / 2)
                elif ch == ord("-"):
                    interval = min(10, interval * 2)
                time.sleep(0.05)

    try:
        curses.wrapper(main)
    except KeyboardInterrupt:
        pass


# --------------------------------------------------------------------------- CLI

def main(argv=None):
    ap = argparse.ArgumentParser(prog="sys-manager", description="System monitor: CPU, RAM, GPU, disks, network.")
    sub = ap.add_subparsers(dest="cmd")
    j = sub.add_parser("json", help="print a JSON snapshot")
    j.add_argument("sections", nargs="*", help=f"any of: {' '.join(ALL_SECTIONS)}, or 'all'")
    j.add_argument("--client", help="id used to remember the previous sample between calls")
    j.add_argument("--pretty", action="store_true")
    sub.add_parser("info", help="print hardware models")
    t = sub.add_parser("tui", help="interactive terminal monitor")
    t.add_argument("-i", "--interval", type=float, default=1.0)
    ap.add_argument("--version", action="version", version=VERSION)
    args = ap.parse_args(argv)

    if args.cmd == "json":
        secs = args.sections or DEFAULT_SECTIONS
        if "all" in secs:
            secs = ALL_SECTIONS
        bad = [s for s in secs if s not in ALL_SECTIONS]
        if bad:
            ap.error(f"unknown section(s): {', '.join(bad)}")
        data = Collector(args.client).collect(secs)
        json.dump(data, sys.stdout, indent=2 if args.pretty else None, ensure_ascii=False)
        sys.stdout.write("\n")
    elif args.cmd == "info":
        print(info_text())
    elif args.cmd == "tui" or (args.cmd is None and sys.stdout.isatty()):
        run_tui(getattr(args, "interval", 1.0))
    else:
        ap.print_help()


if __name__ == "__main__":
    main()
