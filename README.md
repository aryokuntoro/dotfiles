# dotfiles

i3 + polybar + rofi + dunst + Thunar config for Arch Linux.

## Install

```sh
git clone <this-repo-url> ~/Projects/dotfiles
cd ~/Projects/dotfiles
./install.sh
```

`install.sh` symlinks each `config/<app>/` here to `~/.config/<app>`,
backing up anything already there to `~/.config-backup-<timestamp>/`
first. Safe to re-run.

After installing, log out and back in (so i3/polybar/dunst pick up
the new configs from a fresh session), then run `~/.config/i3/scripts/theme-switch.sh`
once to pick a starting theme (it writes the actual color values into
`polybar/config.ini`, `dunst/dunstrc`, etc. -- those files ship with
whatever theme was last active on the machine this repo was exported
from, not a fixed default).

## Required packages

### Official repos (`pacman -S`)

```
i3-wm polybar rofi dunst
thunar thunar-archive-plugin thunar-media-tags-plugin thunar-shares-plugin thunar-volman
playerctl ddcutil flatpak xdotool slop ffmpeg xclip feh xorg-xrandr vim
samba smbclient ufw networkmanager nm-connection-editor bluez bluez-utils
kitty libpulse pavucontrol autorandr
ttf-jetbrains-mono-nerd otf-font-awesome noto-fonts papirus-icon-theme
```

### AUR (`paru -S`, needs `paru` itself bootstrapped first -- see below)

```
gtkhash-thunar edid-decode betterlockscreen i3lock-color python-pywal16
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
- All icon glyphs are Font Awesome, embedded in
  `ttf-jetbrains-mono-nerd` (that's the actual source of every glyph
  rendered in polybar/rofi) with `otf-font-awesome` as an explicit
  fallback font in `polybar/config.ini`.
