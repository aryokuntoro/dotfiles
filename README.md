# dotfiles

![Arch Linux](https://img.shields.io/badge/OS-Arch%20Linux-1793D1?logo=archlinux&logoColor=white)
![i3wm](https://img.shields.io/badge/WM-i3-4B32C3?logo=i3&logoColor=white)
![Rust](https://img.shields.io/badge/installer-Rust-CE422B?logo=rust&logoColor=white)
![ratatui](https://img.shields.io/badge/TUI-ratatui-DEA584)

A full Arch Linux desktop — **i3 · polybar · rofi · dunst · picom ·
kitty · Thunar** — with 5 live-switchable GTK/Qt themes and one active
color palette that recolors the entire desktop at once. Installed
through its own **TUI**, not a script that silently dumps files over
your config.

```sh
curl -fsSL https://raw.githubusercontent.com/aryokuntoro/dotfiles/master/bootstrap.sh | bash
```

<p align="center"><sub>Needs <code>git</code> + <code>rust</code>, and a real terminal (not a pipe with no tty) — see <a href="#install">Install</a> for details.</sub></p>

## Why this one

- 🖥️ **TUI installer**, not `install.sh` blindly copying files — a
  checklist with search, per-item overwrite prompts, and a live
  progress bar. Runs on a bare tty, so it works before any desktop
  exists.
- 🎨 **5 GTK themes** (Catppuccin, Gruvbox, Tokyonight, Everforest,
  Nordic) built from their own upstream source — not AUR packages that
  go stale. Swap theme or accent color anytime, no restart needed.
- 🔗 **One palette drives everything** — i3, polybar, dunst, rofi,
  kitty, GTK, Qt, `.Xresources` all read the same source of truth.

## Contents

[Install](#install) · [Layout](#layout) · [Packages](#packages) ·
[Shortcuts](#shortcuts) · [Samba sharing](#samba-sharing) ·
[Notes & gotchas](#notes--gotchas) · [Not included](#not-included) ·
[Credits](#credits)

## Install

**Fresh machine**, one command — clones to `~/Projects/dotfiles` and
launches the TUI:

```sh
curl -fsSL https://raw.githubusercontent.com/aryokuntoro/dotfiles/master/bootstrap.sh | bash
```

Requires `git` and `rust` on PATH (`sudo pacman -S git rust`) and
must run from an actual interactive terminal — piping into `bash`
means the script reconnects its own stdin to `/dev/tty`, which needs
one to exist. Override the clone target with `DOTFILES_DIR=...`.

**Already cloned it, or want to read the script first?** Same result:

```sh
sudo pacman -S rust          # skip if already installed
git clone <this-repo-url> ~/Projects/dotfiles
cd ~/Projects/dotfiles && ./install.sh
```

The TUI has three checklist categories:

| Category | What it does |
| --- | --- |
| **System packages** | `pacman`/`paru` installs (official + AUR, bootstraps `paru` itself if missing). Off by default, needs sudo — hands the terminal back to pacman/paru for prompts, then returns control. |
| **Dotfiles** | `config/<app>/` → `~/.config/<app>`, `home/*` → `~/.*`, app launchers → `~/.local/share/applications/`. Anything that differs from what's already there gets an overwrite/backup/skip prompt; identical files are skipped silently. Safe to re-run. |
| **GTK themes** | Clones + builds each theme straight from its GitHub upstream into `~/.themes`. Powers the theme switcher (`$mod+F2`) and accent picker (`$mod+F8`). |

`/` searches, `esc`/`ctrl+c` cancels before the next item (never
mid-step).

> [!IMPORTANT]
> Config files here are **copied, not symlinked**. Edit the repo,
> then re-run `./install.sh` to push changes to `$HOME` — edits made
> directly under `~/.config` won't make it back into the repo.
>
> Pulling an update? `git pull` **before** `./install.sh`, not after —
> otherwise the checklist only offers what was already on disk.

Once it's done: log out/in (so i3/polybar/dunst pick up the new
config), then `$mod+F2` to pick a theme.

## Layout

```
.
├── bootstrap.sh        curl | bash entry point → clones repo, hands off to install.sh
├── install.sh           thin launcher for installer/
├── installer/            the TUI itself (Rust + ratatui)
│   └── src/  main.rs · app.rs · items.rs · installer.rs · ui.rs
├── config/               → ~/.config/<app>
│   ├── i3/ polybar/ rofi/ picom/ dunst/ kitty/
│   ├── gtk-3.0/ gtk-4.0/ qt5ct/ qt6ct/    theming
│   ├── mpv/ btop/ htop/ Thunar/ qalculate/ uad/ xarchiver/ …
│   ├── autorandr/        this machine's monitor profile
│   └── applications/     → ~/.local/share/applications
├── home/                 → ~/.<file>  (xinitrc, Xresources, bashrc, gitconfig, …)
├── tests/                not installed — hermetic, dependency-free (bash only)
├── Makefile              make test / lint / syntax / check
├── setup-hibernate.sh    one-time, needs sudo — NOT part of install.sh
└── setup-samba-share.sh  one-time, needs sudo — NOT part of install.sh
```

<details>
<summary><b>Checking changes</b></summary>

```sh
make test     # tests/ — bash only, no display needed
make lint     # shellcheck every script
make syntax   # bash -n every script
make check    # all three
```

`tests/` targets `rofi-monitor.sh` (the riskiest script) against
fixture `xrandr` output — no real X server touched, and the harness
allowlists read-only `xrandr` subcommands so a bug can't blank the
screen mid-test.

`config/rofi/scripts/NetManagerDM.sh` is skipped by lint/syntax — it's
actually a Python script with a `.sh` extension (name is baked into
`polybar/config.ini` and `rofi-network.sh`).
</details>

## Packages

<details open>
<summary><b>Official repos</b></summary>

```sh
sudo pacman -S i3-wm polybar rofi dunst picom \
  thunar thunar-archive-plugin thunar-media-tags-plugin thunar-shares-plugin thunar-volman \
  playerctl ddcutil flatpak xdotool slop ffmpeg xclip feh xorg-xrandr xorg-setxkbmap xorg-xset numlockx vim \
  samba smbclient ufw networkmanager nm-connection-editor bluez bluez-utils \
  kitty libpulse pavucontrol autorandr qt5ct qt6ct btop mpv libqalculate xarchiver htop \
  polkit-gnome autotiling udiskie firefox brightnessctl \
  ttf-jetbrains-mono-nerd otf-font-awesome noto-fonts papirus-icon-theme
```
</details>

<details>
<summary><b>AUR</b> (needs <code>paru</code>)</summary>

```sh
paru -S gtkhash-thunar edid-decode betterlockscreen i3lock-color greenclip bibata-cursor-theme
```

No `paru` yet:

```sh
sudo pacman -S --needed base-devel git
git clone https://aur.archlinux.org/paru.git /tmp/paru
cd /tmp/paru && makepkg -si
```
</details>

> Both lists are already checkboxes in the TUI's **System packages**
> tab — see [Install](#install).

## Shortcuts

<details>
<summary><b>Installer TUI</b></summary>

| Key | Action |
| --- | --- |
| `↑`/`↓`, `j`/`k` | move selection |
| `←`/`→`, `h`/`l` | switch tab |
| `space` | toggle item |
| `a` | toggle everything visible (scoped to tab + search filter) |
| `/` | search · `enter` applies · `esc` clears |
| `enter` | install checked items |
| `esc` / `ctrl+c` | cancel (stops before the next item) |
| `y`/`n`/`a` | overwrite prompt: yes / no / yes to all |
| `q` | quit |
</details>

<details open>
<summary><b>i3</b> — <code>$mod</code> = Super</summary>

**Launchers & menus**

| Key | Action | Key | Action |
| --- | --- | --- | --- |
| `$mod+Return` | terminal | `$mod+F2` | theme switcher |
| `$mod+d` | app launcher | `$mod+F3` | wallpaper picker |
| `$mod+Tab` | window switcher | `$mod+F4` | reload colors |
| `$mod+Shift+d` | run command | `$mod+F5` | monitor layout |
| `$mod+p` | power menu | `$mod+F6` | connect network share |
| `$mod+Shift+b` | browser | `$mod+F7` | screen-timeout menu |
| `$mod+e` | file manager | `$mod+F8` | accent color picker |
| `$mod+m` | media player | `$mod+x` | lock screen |
| `$mod+c` | calculator | `$mod+Shift+x` | presentation mode |
| `$mod+.` | emoji picker | `$mod+F1` | screenshot |
| `$mod+n` | network menu | `$mod+ctrl+r` | screen recording |
| `$mod+b` | bluetooth menu | `$mod+Shift+s` | stream |
| `$mod+Shift+v` | clipboard history | `$mod+Shift+y` | yt-dlp downloader |

**Windows & layout**

| Key | Action |
| --- | --- |
| `$mod+h/j/k/l` / arrows | focus direction |
| `$mod+Shift+h/j/k/l` / arrows | move window |
| `$mod+f` | fullscreen |
| `$mod+space` / `$mod+Shift+space` | focus tiling↔floating / toggle floating |
| `$mod+g` / `$mod+s` | toggle split layout |
| `$mod+w` | tabbed layout |
| `$mod+slash` / `$mod+minus` | split horizontal / vertical |
| `$mod+a` | focus parent |
| `$mod+r` | resize mode (`esc` to exit) |
| `$mod+Shift+q` | kill focused window |
| `$mod+Shift+Return` / `$mod+ctrl+Return` | scratchpad terminal / show scratchpad |
| `$mod+Shift+c` / `$mod+Shift+r` | reload / restart i3 |
| `$mod+1`…`0`, `$mod+Shift+1`…`0` | switch / move to workspace 1-10 |

**Media keys**

| Key | Action |
| --- | --- |
| `XF86AudioPlay/Next/Prev/Stop` | playerctl |
| `XF86AudioRaiseVolume/LowerVolume/Mute` | volume |
| `XF86MonBrightnessUp/Down` | brightness (`brightnessctl`) |
</details>

## Samba sharing

Thunar → Properties → Share. One-time setup:

```sh
sudo bash ~/Projects/dotfiles/setup-samba-share.sh
```

Then log out/in. This is **guest access, no password** — fine on a
trusted home LAN, don't expose it to the internet.

Per shared folder, by hand:

- Every folder between `$HOME` and the share needs `chmod o+x` — a
  Windows *"you do not have permission"* error despite guest auth
  working means this (check `/var/log/samba/log.<client>` for
  `vfs_ChDir(...) failed: Permission denied`).
- The shared folder itself needs `o+rx` (`o+w` too if writable).

<details>
<summary>Connecting from Windows</summary>

`\\<hostname>\<sharename>` in File Explorer. If Windows 10/11 blocks
it with *"organization's security policies block unauthenticated
guest access"*:

- `gpedit.msc` → Computer Configuration → Administrative Templates →
  Network → Lanman Workstation → **Enable insecure guest logons**, or
- Registry: `HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters`,
  DWORD `AllowInsecureGuestAuth` = `1`

Restart Windows after either.
</details>

## Notes & gotchas

<details>
<summary>Expand — hardware- and setup-specific quirks</summary>

- **Log into the `xinitrc` session in `ly`, not `i3`.** Cycle session
  type once at the login screen; `save = true` in `/etc/ly/config.ini`
  remembers it. The `i3` entry skips `~/.xinitrc` entirely, which is
  the only place `QT_QPA_PLATFORMTHEME`/`QT_FONT_DPI` can be set
  before i3 starts — so on that entry, Qt apps get no theming or DPI
  scaling and `qt5ct/`/`qt6ct/` do nothing.
- **Scale (`$mod+F5`) changes DPI, not `xrandr --scale`** — `--scale`
  just stretches a smaller framebuffer and blurs everything. The menu
  writes `Xft.dpi` (`.Xresources`) + `gtk-xft-dpi` and restarts i3;
  already-open windows keep their old size until relaunched. Qt only
  picks up the new `QT_FONT_DPI` on the next login.
- **Resolution vs Scale are separate menus** — Resolution is the
  panel's mode (read from EDID); Scale is how big the UI renders on
  it. Each row of the Scale menu shows what it looks like in practice
  (`apps see 1280x720` at 150% on 1080p); the recommended row is
  computed from EDID physical size + assumed viewing distance, not a
  guess — ambiguous panels (~43") default to "TV", projectors get no
  suggestion at all.
- **One DPI for the whole X session** — no per-output DPI on X11, so
  with two differently-dense displays, pick the scale for whichever
  you actually work on.
- The monitor menu **won't let you turn off the last active display**
  — it used to, and would then persist that all-black state into
  autorandr, bricking the next login until a TTY rescue. Every layout
  change is one atomic `xrandr` call, applied/saved only on exit 0.
- `polybar/scripts/backlight.sh` auto-detects: real backlight panel →
  `brightnessctl`; none (this desktop) → DDC/CI via `ddcutil`.
- Battery module is left out of `polybar/config.ini` on purpose (no
  battery on this machine) — see the module comments for how to wire
  one up on a laptop.
- `autorandr/default/` is this machine's monitor profile only (EDID +
  layout) — on different hardware, save your own with
  `autorandr --save <name>`. Workspaces 6-10 use `output right`
  (relative), so multi-monitor routing works without editing i3
  config.
- **Cold boot HDMI flapping**: this TV's HDMI link can bounce for over
  a minute before settling (~70 connect/disconnect cycles seen in one
  Xorg log). `autostart.sh` retries `autorandr --change` /
  `xrandr --auto` for up to 90s until the live layout actually matches
  the saved profile, instead of applying once and giving up. For the
  same reason `ly` can render to a black screen right after boot —
  it's running fine, the TV just hasn't synced yet.
- Absolute-path configs (`qt5ct.conf`, `qt6ct.conf`, `uad/config.toml`,
  `greenclip.toml`, `mount-image.desktop`) bake in this machine's
  username — repoint them if yours differs.
</details>

## Not included

Browser profiles (cache/cookies), `gh` (OAuth token), `dconf`/`pulse`
(binary runtime state), LibreOffice. `.gitconfig` only sets the
credential helper — run `git config --global user.name`/`user.email`
yourself.

## Credits

The GTK themes are built straight from their own upstream repos —
this is just wiring, all credit to their authors:

| Theme | Repo |
| --- | --- |
| Catppuccin | [Fausto-Korpsvart/Catppuccin-GTK-Theme](https://github.com/Fausto-Korpsvart/Catppuccin-GTK-Theme) |
| Gruvbox | [Fausto-Korpsvart/Gruvbox-GTK-Theme](https://github.com/Fausto-Korpsvart/Gruvbox-GTK-Theme) |
| Tokyonight | [Fausto-Korpsvart/Tokyonight-GTK-Theme](https://github.com/Fausto-Korpsvart/Tokyonight-GTK-Theme) |
| Everforest | [Fausto-Korpsvart/Everforest-GTK-Theme](https://github.com/Fausto-Korpsvart/Everforest-GTK-Theme) |
| Nordic | [EliverLara/Nordic](https://github.com/EliverLara/Nordic) |

And every maintainer of [i3](https://i3wm.org/),
[polybar](https://github.com/polybar/polybar),
[rofi](https://github.com/davatorium/rofi),
[picom](https://github.com/yshui/picom), and
[ratatui](https://ratatui.rs).
