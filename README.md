# Bosgame M5 Fan Control

GTK4/libadwaita GUI and systemd service for controlling fans on Bosgame M5 / Sixunited AXB35-02 boards.

## Features

- Control 3 fans (CPU Fan 1, CPU Fan 2, System Fan)
- Fan modes: auto, fixed, curve
- Custom temperature curves with hysteresis
- APU power modes: quiet, balanced, performance
- GPU performance level (auto / low / high) without sudo prompts
- Real-time temperature monitoring (CPU, GPU, NVMe, WiFi, Ethernet)
- Systemd services for persistent settings and sysfs permissions

## Requirements

- Linux kernel with ec_su_axb35 driver (from [cmetz/ec-su_axb35-linux](https://github.com/cmetz/ec-su_axb35-linux))
- Python 3
- GTK4, libadwaita
- python-gobject

The EC driver is an out-of-tree module and is not DKMS-packaged: rebuild and
reinstall it after every kernel upgrade, otherwise the fan/power controls
disappear from the GUI (harmless - the EC falls back to its own fan curve).

## Installation

```bash
# Install the ec_su_axb35 driver first (see driver repo)

# Then install fan control:
sudo make install

# Enable autostart and the sysfs permission helper
sudo systemctl daemon-reload
sudo systemctl enable --now bosgame-fan-control.service
sudo systemctl enable --now amdgpu-perms.service
```

## Usage

### GUI
```bash
bosgame-fan-control
```

### Command Line
```bash
# Check status
sudo fan-control.sh status

# Apply settings from config
sudo fan-control.sh start
```

### Manual Control
```bash
# Set fan mode (auto/fixed/curve)
echo curve > /sys/class/ec_su_axb35/fan1/mode

# Set fan level (0-5)
echo 3 > /sys/class/ec_su_axb35/fan1/level

# Set custom curves (comma-separated temps for levels 1-5)
echo "60,70,80,88,95" > /sys/class/ec_su_axb35/fan1/rampup_curve
echo "50,60,70,78,85" > /sys/class/ec_su_axb35/fan1/rampdown_curve

# Set power mode (quiet/balanced/performance)
echo balanced > /sys/class/ec_su_axb35/apu/power_mode
```

## GPU Performance Level

Changing the GPU performance level in the GUI writes to

```
/sys/class/drm/card*/device/power_dpm_force_performance_level
```

which the kernel exposes as `root:root 0644`. The mode is recreated on every
boot, so a one-off `sudo chmod` only lasts until the next reboot. Writing it as
a normal user therefore fails with:

```
GPU-Einstellung erfordert root.
Führe aus: sudo chmod 666 /sys/class/drm/card1/device/power_dpm_force_performance_level
```

`amdgpu-perms.service` fixes this permanently. It is installed by `make install`
and must be enabled once:

```bash
sudo systemctl enable --now amdgpu-perms.service
```

What it does, and why it is a separate unit:

- runs `amdgpu-perms.sh`, which chmods `power_dpm_force_performance_level` (and
  `power_dpm_state`) on **every** boot;
- **waits** up to 60 s for the node to appear. On Strix Halo, amdgpu finishes
  initialising *after* `multi-user.target`, so a chmod issued at service start
  hits a path that does not exist yet and fails silently - this was the original
  bug, and it also affects `fan-control.sh` if it tries to do the same thing;
- does **not** depend on the `ec_su_axb35` driver, so it still works while that
  module is missing (for example right after a kernel upgrade);
- matches the node by `card*/` glob instead of hardcoding `card1`, because the
  DRM card index is not stable across boots.

Check it:

```bash
systemctl status amdgpu-perms.service
ls -l /sys/class/drm/card*/device/power_dpm_force_performance_level
```

Expected: `active (exited)` and a mode of `-rw-rw-rw-`.

If the node is still not writable, check that the unit was not started before
the GPU appeared:

```bash
journalctl -b -u amdgpu-perms.service
```

On multi-user machines, `0666` is broader than necessary. If you prefer to grant
only members of the `video` group, change the two lines in `amdgpu-perms.sh` to:

```sh
chown root:video "$f" && chmod 0664 "$f"
```

Manual one-off (not persistent):

```bash
sudo chmod 666 /sys/class/drm/card*/device/power_dpm_force_performance_level
```

## Configuration

Edit `/etc/bosgame-fan-control.conf`:

```bash
POWER_MODE="balanced"
FAN_MODE="curve"
RAMPUP_CURVE="45,58,68,78,88"
RAMPDOWN_CURVE="40,52,62,72,82"
```

### Fan curves

The EC exposes six duty steps only (0, 20, 40, 60, 80, 100 %), so each
curve is just five thresholds deciding *when* a step engages:

- ramp-up: level rises when `temp >= rampup[level+1]`
- ramp-down: level falls when `temp <= rampdown[level]`
- thresholds are read from the EC sensor (`temp1`), which sits 2-4 C below Tctl
- ramp-down must stay below ramp-up, or the fans oscillate

The shipped default is a steady-floor profile: `45,58,68,78,88` up /
`40,52,62,72,82` down. Level 1 latches at 45 C and is only released below
40 C, so the fans hold a constant 20 % at idle instead of stopping and
restarting every few minutes; 100 % arrives at 88 C, keeping sustained loads
clear of the ~95 C throttle point.

The GUI's **Apply** button writes the curves to the running system only.
To keep them across reboots, set them in this file too - it is what
`bosgame-fan-control.service` reads at boot.

## Supported Devices

- Bosgame M5
- GMKtec EVO-X2
- FEVM FA-EX9
- Peladn YO1
- Other Sixunited AXB35-02 based devices

## License

MIT
