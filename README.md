# dotfiles

![Arch Linux](https://img.shields.io/badge/OS-Arch%20Linux-1793D1?logo=archlinux&logoColor=white)
![i3wm](https://img.shields.io/badge/WM-i3-4B32C3?logo=i3&logoColor=white)
![Rust](https://img.shields.io/badge/installer-Rust-CE422B?logo=rust&logoColor=white)
![ratatui](https://img.shields.io/badge/TUI-ratatui-DEA584)

Arch Linux desktop config: **i3 + polybar + rofi + dunst + Thunar,
picom, kitty**, live-switchable GTK/Qt themes, and the rest of the
desktop session (`.xinitrc`, `.Xresources`) — installed through its
own TUI, not a shell script that silently copies files.

**What sets this repo apart from the usual dotfiles pile:**

- **TUI installer** ([ratatui](https://ratatui.rs)) with a checklist,
  search, overwrite confirmation, and a live progress bar — not an
  `install.sh` that copies everything without asking. Runs on a raw
  tty too, so it works before a desktop even exists.
- **5 GTK themes** (Catppuccin, Gruvbox, Tokyonight, Everforest,
  Nordic) built straight from their upstream source, not AUR packages
  that can go stale — switch theme and accent color any time without
  leaving rofi.
- Every color (i3, polybar, dunst, rofi, kitty, GTK, Qt,
  `.Xresources`) is pulled from **one active palette**, so switching
  themes instantly recolors the whole desktop at once.

## Table of contents

- [Install](#install)
- [Repo layout](#repo-layout)
- [Required packages](#required-packages)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Deliberately left out](#deliberately-left-out)
- [Sharing files over Samba](#sharing-files-over-samba-thunar--properties--share)
- [Miscellaneous notes](#miscellaneous-notes)
- [Special thanks](#special-thanks)

## Install

One-liner, [linutil](https://github.com/ChrisTitusTech/linutil)-style
-- clones (or updates) `~/Projects/dotfiles` and launches the TUI:

```sh
curl -fsSL https://raw.githubusercontent.com/aryokuntoro/dotfiles/master/bootstrap.sh | bash
```

Needs `git` and `cargo`/`rustc` already on PATH (`sudo pacman -S git
rust`), and a real interactive terminal to run it from -- piping to
`bash` means the script's own stdin is the download, so it reconnects
to `/dev/tty` before handing off to the installer, which won't work
from a non-interactive shell with no controlling tty. Set
`DOTFILES_DIR` to clone somewhere other than the default.

Prefer to read the script before running it, or already have the repo
cloned? Same result, done by hand:

```sh
sudo pacman -S rust   # if you don't have it yet -- a fresh Arch install doesn't ship it
git clone <this-repo-url> ~/Projects/dotfiles
cd ~/Projects/dotfiles
./install.sh
```

`install.sh` is just a thin launcher -- the actual installer lives in
`installer/` (Rust + [ratatui](https://ratatui.rs)), a TUI checklist
for picking which components to install. It runs directly on a raw
tty too (no X/Wayland needed first, ratatui talks ANSI straight to the
terminal), so it can be used from a fresh Arch install before any
desktop exists at all.

The checklist has 3 categories:

- **System packages** -- `sudo pacman -S --needed` for official
  packages, `paru -S` for AUR packages (bootstraps paru automatically
  first if it isn't there yet, the exact same manual steps as in the
  "Required packages" section below). The one part of the checklist
  that's **off by default** and needs sudo -- while it runs, the
  terminal is handed fully back to pacman/paru/makepkg (so their
  password prompts and [Y/n] confirmations work normally), then
  control returns to the TUI once it's done.
- **Dotfiles** -- each `config/<app>/` -> `~/.config/<app>`, files in
  `home/` -> `~/.<file>`, `config/applications/` ->
  `~/.local/share/applications/`. Anything that already exists with
  **different** content gets asked about first (overwrite+backup /
  skip / overwrite all remaining), identical content is skipped
  without asking. Safe to run repeatedly.
- **GTK themes** -- Catppuccin/Gruvbox/Tokyonight/Everforest/Nordic
  are cloned straight from their respective GitHub upstreams and
  built into `~/.themes` (via each project's own `install.sh`, except
  Nordic which ships pre-built). This is what gives `theme-switch.sh`
  ($mod+F2) and the accent picker ($mod+F8) themes to work with --
  without this step both still work, they just won't find the
  folders.

Search with `/`, cancel a running install with `esc`/`ctrl+c` (stops
before the next item, doesn't cut off whatever's running mid-step).

If this repo has already been cloned before: **`git pull` first, then
`./install.sh`** -- the other way around, the checklist only offers
whatever old version is already sitting in the repo, so the latest
update never makes it to `~/.config`.

Since the dotfiles are copied, not symlinked: edit the source file in
this repo first, then re-run `./install.sh` to push the change out to
`$HOME` — editing directly under `~/.config` won't be saved back here.

After installing: log out/in once (so i3/polybar/dunst read the new
config), then `$mod+F2` to pick an initial theme.

## Repo layout

```
.
├── bootstrap.sh           curl | bash entry point -- clones the repo, hands off to install.sh
├── install.sh             local entry point -- thin launcher for installer/
├── installer/             the TUI itself (Rust + ratatui)
│   └── src/
│       ├── main.rs        terminal setup/teardown, event loop
│       ├── app.rs         UI state -- tabs, selection, search, install progress
│       ├── items.rs       the checklist itself: what gets installed + its descriptions
│       ├── installer.rs   the actual copy / clone / build / package logic
│       └── ui.rs          rendering
├── config/                -> ~/.config/<app>, one folder (or file) per app
│   ├── i3/                window manager config + scripts
│   ├── polybar/           status bar
│   ├── rofi/               launcher, menus, theme switcher, accent picker
│   ├── picom/              compositor
│   ├── dunst/               notifications
│   ├── kitty/                terminal
│   ├── gtk-3.0/, gtk-4.0/, qt5ct/, qt6ct/    GTK/Qt theming
│   ├── autorandr/           this machine's monitor profile
│   ├── applications/        -> ~/.local/share/applications (installed one file at a time)
│   │                        vim.desktop here is a NoDisplay override that hides the
│   │                        packaged /usr/share one, so only vim-kitty.desktop is listed
│   └── ...                  autostart, btop, htop, mpv, qalculate, Thunar, uad, xarchiver, + a few loose files
├── home/                    -> ~/.<file>
│   └── xinitrc, Xresources, bashrc, bash_profile, bash_logout, gitconfig
├── tests/                   NOT installed -- install.sh only reads config/ and home/
│   ├── run.sh               dependency-free runner: `make test` needs only bash
│   ├── lib/harness.sh       hermetic xrandr/rofi stand-ins + assertions
│   └── fixtures/            canned xrandr output, so tests need no display
├── Makefile                 make test / lint / syntax / check
├── setup-hibernate.sh       one-time system setup, NOT part of install.sh -- needs sudo, edits the bootloader
├── setup-samba-share.sh     one-time system setup, NOT part of install.sh -- needs sudo
└── README.md
```

### Checking changes

```sh
make test     # tests/ -- bash only, works on a bare install
make lint     # shellcheck every script (sudo pacman -S shellcheck)
make syntax   # bash -n every script
make check    # all three
```

`tests/` covers `rofi-monitor.sh`, the script with the most to get wrong.
It runs against fixture `xrandr` output rather than the real X server, so
it needs no display — and, more to the point, *cannot* reach one. An
earlier throwaway harness only intercepted the xrandr subcommands that
looked dangerous, which left `--off` live and blanked the screen
mid-test; `tests/lib/harness.sh` allowlists the read-only subcommands
instead and logs everything else without running it.

`config/rofi/scripts/NetManagerDM.sh` is skipped by `lint` and `syntax`:
it is a Python script carrying a `.sh` extension, and its name is baked
into `polybar/config.ini` and `rofi-network.sh`.

## Required packages

### Official repos

```sh
sudo pacman -S i3-wm polybar rofi dunst picom \
  thunar thunar-archive-plugin thunar-media-tags-plugin thunar-shares-plugin thunar-volman \
  playerctl ddcutil flatpak xdotool slop ffmpeg xclip feh xorg-xrandr xorg-setxkbmap xorg-xset numlockx vim \
  samba smbclient ufw networkmanager nm-connection-editor bluez bluez-utils \
  kitty libpulse pavucontrol autorandr qt5ct qt6ct btop mpv libqalculate xarchiver htop \
  polkit-gnome autotiling udiskie firefox brightnessctl \
  ttf-jetbrains-mono-nerd otf-font-awesome noto-fonts papirus-icon-theme
```

### AUR (needs `paru`)

```sh
paru -S gtkhash-thunar edid-decode betterlockscreen i3lock-color python-pywal16 greenclip bibata-cursor-theme
```

Don't have `paru` yet?

```sh
sudo pacman -S --needed base-devel git
git clone https://aur.archlinux.org/paru.git /tmp/paru
cd /tmp/paru && makepkg -si
```

> Don't feel like running these by hand? Both lists above are already
> in the TUI installer's checklist too (the **System packages**
> category) -- see [Install](#install).

## Keyboard shortcuts

### Installer TUI

| Key | Action |
| --- | --- |
| `↑`/`↓`, `j`/`k` | move selection |
| `←`/`→`, `h`/`l` | switch tab |
| `space` | toggle the highlighted item |
| `a` | toggle everything currently visible (scoped to the tab + search filter) |
| `/` | search within the active tab; `enter` applies the filter, `esc` clears it |
| `enter` | start installing whatever's checked |
| `esc` / `ctrl+c` | cancel a running install (stops before the *next* item, never mid-step) |
| `y` / `n` / `a` | on an overwrite prompt: yes / no / yes to all remaining |
| `q` | quit |

### i3 (`$mod` = Super/Windows key)

**Launchers & rofi menus**

| Key | Action |
| --- | --- |
| `$mod+Return` | terminal |
| `$mod+d` | app launcher |
| `$mod+Tab` | window switcher |
| `$mod+Shift+d` | run command |
| `$mod+p` | power menu |
| `$mod+Shift+b` | browser |
| `$mod+e` | file manager |
| `$mod+m` | media player |
| `$mod+c` | calculator |
| `$mod+.` | emoji picker |
| `$mod+n` | network menu |
| `$mod+b` | bluetooth menu |
| `$mod+Shift+v` | clipboard history |
| `$mod+Shift+y` | yt-dlp downloader |
| `$mod+F2` | theme switcher |
| `$mod+F3` | wallpaper picker |
| `$mod+F4` | reload colors from the active theme |
| `$mod+F5` | monitor layout menu |
| `$mod+F6` | connect a network share (gvfs) |
| `$mod+F7` | screen-timeout / auto-lock menu |
| `$mod+F8` | accent color picker |
| `$mod+x` | lock screen |
| `$mod+Shift+x` | presentation mode (toggle screen-timeout off) |
| `$mod+F1` | screenshot |
| `$mod+ctrl+r` | screen recording |
| `$mod+Shift+s` | stream |

**Windows & layout**

| Key | Action |
| --- | --- |
| `$mod+h/j/k/l` or arrows | focus left/down/up/right |
| `$mod+Shift+h/j/k/l` or arrows | move window left/down/up/right |
| `$mod+f` | fullscreen |
| `$mod+Shift+space` | floating toggle |
| `$mod+space` | focus tiling/floating |
| `$mod+g` / `$mod+s` | toggle split layout |
| `$mod+w` | tabbed layout |
| `$mod+slash` / `$mod+minus` | split horizontal / vertical |
| `$mod+a` | focus parent |
| `$mod+r` | resize mode (`h/j/k/l` or arrows, `esc` to exit) |
| `$mod+Shift+q` | kill focused window |
| `$mod+Shift+Return` | scratchpad terminal |
| `$mod+ctrl+Return` | show scratchpad |
| `$mod+Shift+c` | reload i3 config |
| `$mod+Shift+r` | restart i3 |

**Workspaces**

| Key | Action |
| --- | --- |
| `$mod+1`...`$mod+0` | switch to workspace 1-10 |
| `$mod+Shift+1`...`$mod+Shift+0` | move focused window to workspace 1-10 |

**Media keys**

| Key | Action |
| --- | --- |
| `XF86AudioPlay`/`Next`/`Prev`/`Stop` | playerctl |
| `XF86AudioRaiseVolume`/`LowerVolume`/`Mute` | volume |
| `XF86MonBrightnessUp`/`Down` | brightness (`brightnessctl`; see the note on `backlight.sh` below) |

## Deliberately left out

Browser profiles (cache/cookies, not config), `gh` (OAuth token),
`dconf`/`pulse` (binary runtime state), `libreoffice`. `.gitconfig`
here only sets the credential helper to `gh auth git-credential` —
run `git config --global user.name`/`user.email` yourself on a new
machine.

## Sharing files over Samba (Thunar → Properties → Share)

Run once after installing:

```sh
sudo bash ~/Projects/dotfiles/setup-samba-share.sh
```

Then **log out/in**. This sets up **guest access with no password** —
fine for a trusted home LAN, don't use it if it's exposed to the
internet.

Two things you still have to do by hand per shared folder:

- Every folder between home and the shared folder needs the execute
  bit for "other" (`chmod o+x`) — if Windows says "you do not have
  permission to access" even though guest auth is working, this is
  why (check for `vfs_ChDir(...) failed: Permission denied` in
  `/var/log/samba/log.<client>`).
- The shared folder itself needs at least `o+rx`, add `o+w` if it
  should be writable too.

### Connecting from Windows

`\\<hostname>\<sharename>` in File Explorer. If Windows 10/11 refuses
with *"organization's security policies block unauthenticated guest
access"*, enable this on the Windows side:

- `gpedit.msc` → Computer Configuration → Administrative Templates →
  Network → Lanman Workstation → **Enable insecure guest logons**
  (Pro/Enterprise/Education), or
- Registry: `HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters`,
  DWORD `AllowInsecureGuestAuth` = `1` (also works on Home).

Restart Windows afterward.

## Miscellaneous notes

- All polybar/rofi colors are read straight from the active
  `config.ini`/`.rasi` — switching themes via `theme-switch.sh`
  automatically recolors everything, no script editing needed.
- `polybar/scripts/backlight.sh` automatically picks whichever path
  matches the hardware: if there's a real backlight panel
  (`/sys/class/backlight` is populated, the laptop case) it uses
  `brightnessctl`; if not (this desktop's case), it falls back to
  DDC/CI (`ddcutil`) to control the external monitor directly.
- `[module/battery]` in `polybar/config.ini` is deliberately left out
  of `modules-right` — polybar's built-in `internal/battery` module
  can hard-fail at startup if `battery`/`adapter` don't match a real
  device, and this machine has no battery. For a laptop: check the
  real device names via `ls /sys/class/power_supply/`, set
  `battery`/`adapter` in the module accordingly, then add `battery` to
  `modules-right`. Its icon animates (filling up) while charging;
  charger plug/unplug and low-battery (≤20%) notifications are
  handled separately by `polybar/scripts/battery-notify.sh`
  (backgrounded from `autostart.sh`, exits as a no-op immediately if
  there's no battery).
- `autorandr/default/` is a monitor profile specific to this machine
  (this monitor's EDID fingerprint + HDMI-0 layout) — not portable by
  design. On another machine/monitor this profile just won't match
  (autostart still runs fine, it just doesn't apply anything), so save
  that machine's own profile instead: `autorandr --save <name>` after
  setting up xrandr manually for its monitor. Workspaces 6-10 in
  `i3/config` use `output right` (relative position, not a port name)
  so routing to the second monitor keeps working on any hardware
  without needing an edit.
- UI scale (`$mod+F5` → a display → *Scale*) is done by **DPI**, not by
  `xrandr --scale`. `--scale` renders the desktop into a smaller
  framebuffer and lets the GPU stretch it back to the panel (150% =
  1280x720 blown up to 1080p), which magnifies every pixel — polybar
  grows out of proportion and the whole screen goes soft. The menu
  writes `Xft.dpi` to `~/.Xresources` (merged at login by
  `autostart.sh`, so it survives a reboot) plus `gtk-xft-dpi` to
  `gtk-3.0`/`gtk-4.0/settings.ini`, then restarts i3, and clears any
  leftover `--scale` transform on the output first. Everything that
  reads a DPI scales by the same factor: polybar takes its `dpi-x`/
  `dpi-y` from `${xrdb:Xft.dpi:96}` (it has no Xft.dpi fallback of its
  own — left unset it guesses from the EDID's physical size, ~69 dpi on
  this TV). Only what gets restarted resizes immediately; already-open
  kitty/GTK/Qt windows keep the old size until relaunched. For bigger
  GTK *widgets* (not just text) at high DPI, the theme repos also ship
  `-hdpi`/`-xhdpi` variants — point `gtk-theme-name` at one of those.
- **Resolution and Scale are separate settings**, and the monitor menu
  shows each one's current value next to it (`Resolution  (1920x1080@60.00Hz)`
  / `Scale  (150%)`). Resolution is the mode the panel runs; Scale is how
  big the UI is drawn on it. Both menus recommend a row, but from
  different kinds of evidence: Resolution tags the mode the EDID declares
  *native* (plus the one in use) — read straight from the hardware, since
  xrandr already marks them `+` and `*` — while Scale's suggestion is
  estimated. Changing the resolution changes the panel's effective pixel
  density, so if that moves what Scale should be, the confirmation
  notification says so (`... -- Scale now suggests 100%`).
- Each row of the Scale menu shows the dpi it sets and what the desktop
  ends up behaving like — `apps see 1280x720` at 150% on a 1080p panel.
  That is *not* a display mode and has nothing to do with the Resolution
  menu; the panel keeps running its own mode. It's there because losing
  room for windows is the one cost of scaling you don't notice until
  after you've picked a value. One row is tagged *recommended*: that
  suggestion is computed per display, from the EDID: real pixel density
  (px ÷ physical mm) plus a viewing distance guessed from the diagonal,
  solved against a 96 dpi / 60 cm desk baseline. So a 24" 1080p monitor
  suggests 100%, a 14" 1080p laptop 125%, a 27" 4K 175%, this 32" TV
  150%, and a 55" 4K TV 200%. It's a starting point, not a measurement
  — a 43"-ish panel is genuinely ambiguous (desk monitor or TV?) and is
  assumed to be a TV. Projectors publish no panel size, so they get no
  suggestion at all and the prompt says so.
- The monitor menu **refuses to turn off your last active display**. It
  used to let you, and worse, `apply()` then saved that all-off state
  into the same autorandr profile autostart restores — so the next login
  came up black as well, recoverable only from a TTY. Layout changes
  (mirror, single-display, extend) are also each issued as one atomic
  `xrandr` call rather than several, and nothing is announced or
  persisted unless `xrandr` actually exited 0.
- **Log in via the `xinitrc` session in ly, not the `i3` entry.** Cycle
  the session type at the login screen once; `save = true` in
  `/etc/ly/config.ini` makes ly remember it. Picking the `i3` desktop
  entry runs `i3` directly and never reads `~/.xinitrc`, which is the
  only place `QT_QPA_PLATFORMTHEME` and `QT_FONT_DPI` can be set: an
  environment variable has to exist *before* i3 starts, because
  everything i3 launches inherits i3's environment, and nothing can add
  one afterwards. (This is why the Xresources merge could move into
  `autostart.sh` — `xrdb` talks to the running X server — while these
  two could not.) On the `i3` entry, Qt apps get neither qt5ct theming
  nor DPI scaling, so `qt5ct/` and `qt6ct/` in this repo do nothing.
- Qt has no equivalent of `Xft.dpi`; it reads `QT_FONT_DPI`, which
  `~/.xinitrc` derives from the merged Xresources so the scale stays
  stored in one place. Unlike GTK — which re-reads `settings.ini` per
  app launch — this is fixed for the life of the session: after changing
  the scale, Qt apps follow only from the next login.
- **One DPI, one X screen.** X11 has no per-output DPI (that's a
  Wayland feature), so with two displays of different densities plugged
  in, `Xft.dpi` is still a single global value and one of them will be
  a compromise — pick the scale for whichever you actually work on.
  Nothing applies a DPI automatically on hotplug either: `autorandr`
  restores the *layout*, and the scale stays where you last set it.
- The `XF86MonBrightnessUp`/`Down` keys in `i3/config` call
  `brightnessctl` directly, so on a laptop that's already consistent
  with the path `backlight.sh` uses. On this desktop it's practically
  a no-op (no panel for `brightnessctl` to control) — repoint them to
  `backlight.sh up`/`down` if you want the physical keys to control an
  external monitor over DDC/CI too.
- All icons are from Font Awesome, sourced via
  `ttf-jetbrains-mono-nerd` with `otf-font-awesome` as a fallback
  font.
- `qt5ct.conf`, `qt6ct.conf`, `uad/config.toml`, `greenclip.toml`, and
  `mount-image.desktop` have this machine's absolute paths baked into
  a setting or two — repoint them if your username differs.

## Special thanks

The GTK themes `installer/` sets up are built straight from their own
upstream repos — not this repo's work, just wired up automatically.
Thanks to their authors:

| Theme | GitHub repo |
| --- | --- |
| Catppuccin | [Fausto-Korpsvart/Catppuccin-GTK-Theme](https://github.com/Fausto-Korpsvart/Catppuccin-GTK-Theme) |
| Gruvbox | [Fausto-Korpsvart/Gruvbox-GTK-Theme](https://github.com/Fausto-Korpsvart/Gruvbox-GTK-Theme) |
| Tokyonight | [Fausto-Korpsvart/Tokyonight-GTK-Theme](https://github.com/Fausto-Korpsvart/Tokyonight-GTK-Theme) |
| Everforest | [Fausto-Korpsvart/Everforest-GTK-Theme](https://github.com/Fausto-Korpsvart/Everforest-GTK-Theme) |
| Nordic | [EliverLara/Nordic](https://github.com/EliverLara/Nordic) |

And of course every maintainer of [i3](https://i3wm.org/),
[polybar](https://github.com/polybar/polybar),
[rofi](https://github.com/davatorium/rofi),
[picom](https://github.com/yshui/picom), and
[ratatui](https://ratatui.rs) that makes all of this possible to begin
with.
