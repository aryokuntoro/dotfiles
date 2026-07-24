# dotfiles

i3 + polybar + rofi + dunst + Thunar config for Arch Linux, plus
picom, kitty, GTK/Qt theming, and the rest of the desktop session
(`.xinitrc`, `.Xresources`).

## Install

```sh
git clone <this-repo-url> ~/Projects/dotfiles
cd ~/Projects/dotfiles
./install.sh
```

`install.sh` symlinks each `config/<app>/` here to `~/.config/<app>`,
each file under `home/` to `~/.<file>` (`.xinitrc`, `.Xresources`,
`.bashrc`, `.bash_profile`, `.gitconfig`), and each file under
`config/applications/` individually into `~/.local/share/applications/`
(that directory holds every installed app's launcher entries, so it
gets per-file links rather than replacing the whole thing). Backs up
anything already there to `~/.config-backup-<timestamp>/` first. Safe
to re-run.

`.gitconfig` only sets a credential helper delegating to `gh auth
git-credential` -- no name/email is stored globally on the source
machine either. Run `git config --global user.name`/`user.email`
yourself on the new machine (and `gh auth login` if you haven't
already).

Deliberately **not** included: browser profiles (`chromium`, `mozilla`
-- cache/cookies/session data, not portable config), `gh` (holds your
GitHub OAuth token), `dconf`/`pulse` (binary runtime state), and
`libreoffice` (app cache/registry, not meaningful config). pywal's own
`~/.config/wal` was empty on the source machine (no custom colorschemes
or templates authored), so there's nothing there to ship either --
color generation happens through `pywal-reload.sh`/`apply-theme-colors.sh`
in `config/i3/scripts/`, not through wal's own config dir.

A few small app configs (`qt5ct.conf`, `qt6ct.conf`, `uad/config.toml`,
`greenclip.toml`) have the source machine's absolute home path baked
into one or two settings (a color-scheme file path, a cache-file path).
Not portable if your username differs, but harmless -- worst case that
one setting resets to the app's default until you repoint it.

`config/uad` is Universal Android Debloater's config -- there's no
package for it on the source machine either (no pacman/AUR entry, it
wasn't in `$PATH`), so it was presumably run as a standalone binary/
AppImage at some point. The config is here for reference; you'll need
to get the binary yourself if you actually use it.

`config/applications/mount-image.desktop`'s `Exec=` line has the
source machine's absolute path baked in (`.desktop` files don't expand
`~`/`$HOME` in `Exec=`, unlike everything else here which resolves
paths at runtime). If your username differs, double-clicking an ISO
in Thunar won't find the script until you edit that line to match
your actual home path.

After installing, log out and back in (so i3/polybar/dunst pick up
the new configs from a fresh session), then run `~/.config/i3/scripts/theme-switch.sh`
once to pick a starting theme (it writes the actual color values into
`polybar/config.ini`, `dunst/dunstrc`, etc. -- those files ship with
whatever theme was last active on the machine this repo was exported
from, not a fixed default).

## Required packages

### Official repos (`pacman -S`)

```
i3-wm polybar rofi dunst picom
thunar thunar-archive-plugin thunar-media-tags-plugin thunar-shares-plugin thunar-volman
playerctl ddcutil flatpak xdotool slop ffmpeg xclip feh xorg-xrandr xorg-setxkbmap xorg-xset numlockx vim
samba smbclient ufw networkmanager nm-connection-editor bluez bluez-utils
kitty libpulse pavucontrol autorandr qt5ct qt6ct btop mpv libqalculate xarchiver htop
polkit-gnome autotiling udiskie firefox brightnessctl
ttf-jetbrains-mono-nerd otf-font-awesome noto-fonts papirus-icon-theme
```

### AUR (`paru -S`, needs `paru` itself bootstrapped first -- see below)

```
gtkhash-thunar edid-decode betterlockscreen i3lock-color python-pywal16 greenclip bibata-cursor-theme
```

### Bootstrapping `paru`

`paru` isn't in the official repos, so it can't be installed by itself.
One-time manual build:

```sh
sudo pacman -S --needed base-devel git
git clone https://aur.archlinux.org/paru.git /tmp/paru
cd /tmp/paru && makepkg -si
```

## Samba file sharing (Thunar's Properties -> Share tab)

Thunar's Share tab (`thunar-shares-plugin`) creates shares through
Samba's `usershare` mechanism, which needs Samba actually configured
and running -- a fresh Arch install has the package but no config at
all. Run once, after installing:

```sh
sudo bash ~/Projects/dotfiles/setup-samba-share.sh
```

Then **log out and back in** (group membership from this script only
applies to new login sessions). This sets up **guest access (no
password)** shares -- fine for a trusted home LAN, not for anything
internet-facing. If you'd rather require a username/password instead,
that needs different `smb.conf` settings than this script writes.

Two things that matter per-folder you actually share via Thunar (this
setup script only needs to run once, not per-folder):

- Every directory between your home folder and the shared folder
  needs the execute/traverse bit for "other" (`chmod o+x`) --
  `setup-samba-share.sh` doesn't touch this, it's a one-time fix on
  `$HOME` itself which the script also doesn't do automatically since
  it's specific to whatever your home directory's existing permissions
  are. If Windows reports "you do not have permission to access" after
  guest-auth already works, check `/var/log/samba/log.<client>` for
  `vfs_ChDir(...) failed: Permission denied` -- that's this.
- The shared folder itself needs at least `o+rx` (read) for guests to
  browse it, `o+w` too if you want write access.

### Connecting from Windows

`\\<hostname>\<sharename>` or `\\<ip>\<sharename>` in File Explorer's
address bar. Windows 10/11 block unauthenticated guest SMB access by
default -- if you hit *"You can't access this shared folder because
your organization's security policies block unauthenticated guest
access"*, enable it on the **Windows** side:

- `gpedit.msc` -> Computer Configuration -> Administrative Templates
  -> Network -> Lanman Workstation -> **Enable insecure guest logons**
  (Pro/Enterprise/Education only), or
- Registry: `HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters`,
  DWORD `AllowInsecureGuestAuth` = `1` (works on Home too).

Reboot Windows after either change.

## Notes

- Every polybar/rofi color is read live from `config.ini`'s `[colors]`
  section / the active `.rasi` theme -- nothing is hardcoded, so
  switching themes via `theme-switch.sh` re-colors everything
  automatically, no script edits needed.
- `polybar/scripts/backlight.sh` controls an **external monitor's**
  brightness via DDC/CI (`ddcutil`), not a laptop panel -- only works
  if the monitor supports DDC/CI over the connected cable (most do
  over HDMI/DisplayPort) and the machine can see it via
  `ddcutil detect`.
- `i3/config`'s `XF86MonBrightnessUp`/`Down` keys still call
  `brightnessctl` (laptop-panel backlight), left over from before this
  was set up as a desktop with an external monitor -- those two keys
  are effectively no-ops here. Not touched since it wasn't part of
  what this repo was checked for; repoint them at
  `polybar/scripts/backlight.sh up`/`down` if you want the physical
  brightness keys to control the monitor via DDC/CI too.
- All icon glyphs are Font Awesome, embedded in
  `ttf-jetbrains-mono-nerd` (that's the actual source of every glyph
  rendered in polybar/rofi) with `otf-font-awesome` as an explicit
  fallback font in `polybar/config.ini`.
