# dotfiles

Konfigurasi desktop Arch Linux: i3 + polybar + rofi + dunst + Thunar, picom, kitty, tema GTK/Qt, dan sisa sesi desktop (`.xinitrc`,
`.Xresources`).

## Install

```sh
git clone <url-repo-ini> ~/Projects/dotfiles
cd ~/Projects/dotfiles
./install.sh
```

`install.sh` menyalin (bukan symlink) tiap `config/<app>/` ke
`~/.config/<app>`, file di `home/` ke `~/.<file>`, dan
`config/applications/` ke `~/.local/share/applications/`. Yang sudah
ada di-backup dulu ke `~/.config-backup-<timestamp>/`. Aman dijalankan
berkali-kali.

Kalau repo ini sudah pernah di-clone sebelumnya: **`git pull` dulu,
baru `./install.sh`** -- kebalik urutannya, `install.sh` cuma nyalin
versi lama yang sudah ada di repo, jadi update terbaru gak kebawa ke
`~/.config`.

Karena ini copy, bukan symlink: edit dulu file sumber di repo ini,
baru jalankan ulang `./install.sh` untuk mendorong perubahan ke
`$HOME` — mengedit langsung di `~/.config` tidak akan tersimpan di
sini.

Setelah install: logout/login sekali (biar i3/polybar/dunst baca
config baru), lalu jalankan `~/.config/i3/scripts/theme-switch.sh`
untuk pilih tema awal.

## Paket yang dibutuhkan

### Repo resmi

```sh
sudo pacman -S i3-wm polybar rofi dunst picom \
  thunar thunar-archive-plugin thunar-media-tags-plugin thunar-shares-plugin thunar-volman \
  playerctl ddcutil flatpak xdotool slop ffmpeg xclip feh xorg-xrandr xorg-setxkbmap xorg-xset numlockx vim \
  samba smbclient ufw networkmanager nm-connection-editor bluez bluez-utils \
  kitty libpulse pavucontrol autorandr qt5ct qt6ct btop mpv libqalculate xarchiver htop \
  polkit-gnome autotiling udiskie firefox brightnessctl \
  ttf-jetbrains-mono-nerd otf-font-awesome noto-fonts papirus-icon-theme
```

### AUR (butuh `paru`)

```sh
paru -S gtkhash-thunar edid-decode betterlockscreen i3lock-color python-pywal16 greenclip bibata-cursor-theme
```

Belum punya `paru`?

```sh
sudo pacman -S --needed base-devel git
git clone https://aur.archlinux.org/paru.git /tmp/paru
cd /tmp/paru && makepkg -si
```

## Yang sengaja tidak dimasukkan

Profil browser (cache/cookies, bukan config), `gh` (token OAuth),
`dconf`/`pulse` (state runtime biner), `libreoffice`. `.gitconfig` di
sini cuma set credential helper ke `gh auth git-credential` — jalankan
sendiri `git config --global user.name`/`user.email` di mesin baru.

## Berbagi file lewat Samba (Thunar → Properties → Share)

Jalankan sekali setelah install:

```sh
sudo bash ~/Projects/dotfiles/setup-samba-share.sh
```

Lalu **logout/login**. Ini setup **guest access tanpa password** — pas
untuk LAN rumah yang dipercaya, jangan dipakai kalau terekspos ke
internet.

Dua hal manual per-folder yang mau dishare:

- Semua folder di antara home dan folder yang dishare butuh bit
  execute untuk "other" (`chmod o+x`) — kalau Windows bilang "you do
  not have permission to access" padahal guest-auth sudah jalan, ini
  penyebabnya (cek `vfs_ChDir(...) failed: Permission denied` di
  `/var/log/samba/log.<client>`).
- Folder yang dishare butuh minimal `o+rx`, tambah `o+w` kalau mau
  bisa ditulis.

### Connect dari Windows

`\\<hostname>\<sharename>` di File Explorer. Kalau Windows 10/11
nolak dengan *"organization's security policies block unauthenticated
guest access"*, aktifkan di sisi Windows:

- `gpedit.msc` → Computer Configuration → Administrative Templates →
  Network → Lanman Workstation → **Enable insecure guest logons**
  (Pro/Enterprise/Education), atau
- Registry: `HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters`,
  DWORD `AllowInsecureGuestAuth` = `1` (berlaku juga di Home).

Restart Windows setelahnya.

## Catatan lain-lain

- Semua warna polybar/rofi dibaca langsung dari `config.ini`/`.rasi`
  aktif — ganti tema lewat `theme-switch.sh` otomatis mewarnai ulang
  semuanya, tanpa edit script.
- `polybar/scripts/backlight.sh` ngatur brightness **monitor
  eksternal** lewat DDC/CI (`ddcutil`), bukan panel laptop.
- `autorandr/default/` itu profile monitor spesifik mesin ini (fingerprint
  EDID + layout HDMI-0 punya monitor ini) — bukan sesuatu yang portable
  by design. Di mesin/monitor lain, profile ini gak bakal match (autostart
  tetap jalan normal, cuma gak ada-apply apa-apa), jadi simpan profile
  baru punya mesin itu sendiri: `autorandr --save <nama>` setelah xrandr
  di-setup manual sesuai monitornya. Workspace 6-10 di `i3/config` pakai
  `output right` (posisi relatif, bukan nama port) supaya routing ke
  monitor kedua tetap jalan di hardware apa pun tanpa perlu diedit.
- Tombol `XF86MonBrightnessUp`/`Down` di `i3/config` masih manggil
  `brightnessctl` (peninggalan setup laptop) — praktis no-op di setup
  desktop ini. Repoint ke `backlight.sh up`/`down` kalau mau tombol
  fisik ngatur monitor eksternal.
- Semua ikon dari Font Awesome, sumbernya `ttf-jetbrains-mono-nerd`
  dengan `otf-font-awesome` sebagai fallback font.
- `qt5ct.conf`, `qt6ct.conf`, `uad/config.toml`, `greenclip.toml`, dan
  `mount-image.desktop` punya absolute path mesin sumber tertanam di
  satu-dua setting — repoint kalau username kamu beda.
