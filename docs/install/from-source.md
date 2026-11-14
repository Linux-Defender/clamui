# Build from source

CI builds, installs and uninstalls Lazaret this way on Debian 13, Ubuntu 26.04, the current Fedora and Arch Linux.

## Requirements

- Rust 1.99 (the version in `rust-toolchain.toml`), through rustup
- GTK 4.16 and libadwaita 1.6 or newer, GLib and libsystemd, with their development headers
- `pkg-config`, `make` and `glib-compile-schemas`
- ClamAV: `clamdscan` or `clamscan` on `PATH`, and `freshclam`
- A desktop session with systemd user services

On Debian, Ubuntu, Fedora and Arch, you only need `git` and `make` to start: `make deps` installs the rest with `apt`, `dnf` or `pacman`, including the ClamAV daemon and signature updater. On other distributions, install everything yourself.

## Install Lazaret

```sh
git clone https://codeberg.org/wvhulle/lazaret.git
cd lazaret
make deps
make build
sudo make install
```

Then start the ClamAV daemon and signature updates. Debian and Ubuntu start them when the packages are installed. On Fedora run `sudo systemctl enable --now clamd@scan clamav-freshclam`, and on Arch `sudo freshclam` once, then `sudo systemctl enable --now clamav-daemon clamav-freshclam`.

On Fedora, `make deps` installs only `rustup-init`. Run `rustup-init -y --default-toolchain none` once and open a new shell before `make build`.

`make install` installs into `/usr/local` by default. Set `PREFIX` to change that, for example `sudo make install PREFIX=/usr`. It installs the app, its data files, the user service, and the ClamAV admin service with its polkit, D-Bus and systemd files. It then reloads systemd and D-Bus and turns on the timer that ends protection reductions.

### ClamAV paths

The admin service needs to know where your distribution keeps the clamd configuration and what the clamd service is called. The defaults fit Debian, Ubuntu and Arch. On Fedora, pass the Fedora values to `make build` and to every later `make` command:

| Distribution | `CLAMD_CONFIG` | `CLAMD_UNIT` |
|---|---|---|
| Debian, Ubuntu, Arch (default) | `/etc/clamav/clamd.conf` | `clamav-daemon.service` |
| Fedora | `/etc/clamd.d/scan.conf` | `clamd@scan.service` |

```sh
export CLAMD_CONFIG=/etc/clamd.d/scan.conf CLAMD_UNIT=clamd@scan.service
make build
sudo --preserve-env=CLAMD_CONFIG,CLAMD_UNIT make install
```

`CLAMONACC_UNIT` names the on-access service and defaults to `clamav-clamonacc.service`.

## Background alerts

To raise a notification when clamd or on-access scanning detects a file, start Lazaret in the background with your session:

```sh
systemctl --user enable --now lazaret.service
```

## Live tuning

Live tuning lets you change chosen clamd settings from the app, after an administrator password prompt. Only settings whose value type Lazaret knows can be allowed. Settings that run commands or change identity, such as `VirusEvent` or `User`, are never accepted, and a change that leaves clamd unable to start is rolled back. A change that reduces protection ends on its own after `/etc/lazaret/reduction-lifetime` seconds (one day if the file is missing). Live tuning is off until you allow settings and let clamd and clamonacc see the merged configuration.

1. List the settings you allow, one per line:

   ```sh
   printf 'DetectPUA\nMaxThreads\nOnAccessMaxFileSize\n' | sudo tee /etc/lazaret/tunable-settings
   ```

2. Let clamd and clamonacc read the configuration that Lazaret merges from `CLAMD_CONFIG` and your changes:

   ```sh
   sudo make install-live-tuning
   ```

   This installs systemd drop-ins that bind the merged file over `CLAMD_CONFIG` for these two services only, so their start commands stay unchanged. It then restarts them. clamd must listen on its local socket, because the admin service waits for the restarted clamd there.

Without changes, the merged file is identical to `CLAMD_CONFIG`. Changes are stored in `/var/lib/lazaret/live-overrides.toml`.

## API keys for reputation lookups

Keys you paste under **Submissions → Services & Keys** are kept in your keyring. To read them from files instead, for example files managed by your configuration tooling, set the paths:

```sh
gsettings set page.codeberg.wvhulle.Lazaret virustotal-key-file /home/alice/.config/lazaret/virustotal.key
gsettings set page.codeberg.wvhulle.Lazaret abuse-ch-key-file /home/alice/.config/lazaret/abuse-ch.key
```

When a path is set, Lazaret reads that file and hides the paste field.

## Update

```sh
git pull
make build
sudo make install
```

Your settings and quarantine are kept.

## Uninstall

```sh
systemctl --user disable --now lazaret.service
sudo make uninstall
```

Use the same `PREFIX` and ClamAV paths as for the install. `make uninstall` also removes the live-tuning drop-ins and restarts clamd. It keeps `/etc/lazaret` and your quarantine in `~/.local/share/lazaret`; delete those yourself if you want them gone.
