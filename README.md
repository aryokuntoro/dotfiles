# dotfiles

![Arch Linux](https://img.shields.io/badge/OS-Arch%20Linux-1793D1?logo=archlinux&logoColor=white)
![i3wm](https://img.shields.io/badge/WM-i3-4B32C3?logo=i3&logoColor=white)
![Rust](https://img.shields.io/badge/installer-Rust-CE422B?logo=rust&logoColor=white)
![ratatui](https://img.shields.io/badge/TUI-ratatui-DEA584)

Konfigurasi desktop Arch Linux: **i3 + polybar + rofi + dunst + Thunar,
picom, kitty**, tema GTK/Qt yang bisa diganti live, dan sisa sesi
desktop (`.xinitrc`, `.Xresources`) — dipasang lewat TUI sendiri, bukan
shell script yang cuma nyalin file diam-diam.

**Yang bikin repo ini beda dari dotfiles kebanyakan:**

- **Installer TUI** ([ratatui](https://ratatui.rs)) dengan checklist,
  pencarian, konfirmasi overwrite, dan progress bar live — bukan
  `install.sh` yang nyalin semuanya tanpa nanya. Jalan di raw tty juga,
  jadi bisa dipakai sebelum ada desktop sama sekali.
- **5 tema GTK** (Catppuccin, Gruvbox, Tokyonight, Everforest, Nordic)
  di-*build* langsung dari source upstream-nya, bukan paket AUR yang
  bisa basi — ganti tema dan accent color kapan saja tanpa keluar dari
  rofi.
- Semua warna (i3, polybar, dunst, rofi, kitty, GTK, Qt, `.Xresources`)
  ditarik dari **satu palet aktif**, jadi ganti tema langsung
  mewarnai ulang seluruh desktop sekaligus.

## Daftar isi

- [Install](#install)
- [Paket yang dibutuhkan](#paket-yang-dibutuhkan)
- [Yang sengaja tidak dimasukkan](#yang-sengaja-tidak-dimasukkan)
- [Berbagi file lewat Samba](#berbagi-file-lewat-samba-thunar--properties--share)
- [Catatan lain-lain](#catatan-lain-lain)
- [Special thanks](#special-thanks)

## Install

```sh
sudo pacman -S rust   # kalau belum ada -- fresh Arch install gak bawa ini bawaan
git clone <url-repo-ini> ~/Projects/dotfiles
cd ~/Projects/dotfiles
./install.sh
```

`install.sh` cuma launcher tipis -- installer sebenarnya ada di
`installer/` (Rust + [ratatui](https://ratatui.rs)), TUI checklist
buat pilih komponen mana yang mau di-install. Jalan langsung di raw
tty juga (gak butuh X/Wayland duluan, ratatui ngomong ANSI langsung ke
terminal), jadi bisa dipakai dari fresh Arch install sebelum ada
desktop sama sekali.

Checklist-nya ada 3 kategori:

- **System packages** -- `sudo pacman -S --needed` buat paket resmi,
  `paru -S` buat paket AUR (bootstrap paru dulu otomatis kalau belum
  ada, sama persis langkah manual di bagian "Paket yang dibutuhkan" di
  bawah). Satu-satunya bagian checklist yang **off by default** dan
  butuh sudo -- pas dijalankan, terminal dikembalikan sepenuhnya ke
  pacman/paru/makepkg (biar prompt password & konfirmasi [Y/n]
  mereka jalan normal), baru balik ke TUI setelah selesai.
- **Dotfiles** -- tiap `config/<app>/` -> `~/.config/<app>`, file di
  `home/` -> `~/.<file>`, `config/applications/` ->
  `~/.local/share/applications/`. Yang sudah ada dan **beda** isinya
  bakal nanya dulu (timpa+backup / lewati / timpa semua sisanya), yang
  identik langsung di-skip tanpa nanya. Aman dijalankan berkali-kali.
- **Tema GTK** -- Catppuccin/Gruvbox/Tokyonight/Everforest/Nordic
  di-clone langsung dari GitHub upstream masing-masing terus di-build
  ke `~/.themes` (lewat `install.sh` bawaan tiap proyek, kecuali
  Nordic yang sudah pre-built). Ini yang bikin `theme-switch.sh`
  ($mod+F2) dan accent picker ($mod+F8) punya tema buat dipakai --
  tanpa langkah ini keduanya tetap jalan tapi gak nemu foldernya.

Cari lewat `/`, batalkan yang lagi jalan dengan `esc`/`ctrl+c` (berhenti
sebelum item berikutnya, gak motong yang lagi jalan di tengah).

Kalau repo ini sudah pernah di-clone sebelumnya: **`git pull` dulu,
baru `./install.sh`** -- kebalik urutannya, checklist-nya cuma nawarin
versi lama yang sudah ada di repo, jadi update terbaru gak kebawa ke
`~/.config`.

Karena dotfiles-nya di-copy, bukan symlink: edit dulu file sumber di
repo ini, baru jalankan ulang `./install.sh` untuk mendorong perubahan
ke `$HOME` — mengedit langsung di `~/.config` tidak akan tersimpan di
sini.

Setelah install: logout/login sekali (biar i3/polybar/dunst baca
config baru), lalu `$mod+F2` untuk pilih tema awal.

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

> Malas jalanin manual? Kedua daftar di atas sudah ada di checklist
> installer TUI-nya juga (kategori **System packages**) -- lihat
> [Install](#install).

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
- `polybar/scripts/backlight.sh` otomatis pilih jalur yang sesuai
  hardware: kalau ada panel asli (`/sys/class/backlight` keisi, kasus
  laptop) pakai `brightnessctl`, kalau enggak (kasus desktop ini) jatuh
  ke DDC/CI (`ddcutil`) buat ngatur monitor eksternal langsung.
- `[module/battery]` di `polybar/config.ini` sengaja gak dimasukkan ke
  `modules-right` — module bawaan `internal/battery` polybar bisa
  fatal error pas start kalau `battery`/`adapter` gak match device asli,
  dan mesin ini gak punya baterai. Buat laptop: cek nama asli lewat
  `ls /sys/class/power_supply/`, sesuaikan `battery`/`adapter` di
  module-nya, baru tambahin `battery` ke `modules-right`. Icon-nya
  animasi (mengisi) pas charging; notifikasi plug/unplug charger dan
  baterai lemah (≤20%) dihandle terpisah lewat
  `polybar/scripts/battery-notify.sh` (di-background dari
  `autostart.sh`, langsung exit no-op kalau gak ada baterai).
- `autorandr/default/` itu profile monitor spesifik mesin ini (fingerprint
  EDID + layout HDMI-0 punya monitor ini) — bukan sesuatu yang portable
  by design. Di mesin/monitor lain, profile ini gak bakal match (autostart
  tetap jalan normal, cuma gak ada-apply apa-apa), jadi simpan profile
  baru punya mesin itu sendiri: `autorandr --save <nama>` setelah xrandr
  di-setup manual sesuai monitornya. Workspace 6-10 di `i3/config` pakai
  `output right` (posisi relatif, bukan nama port) supaya routing ke
  monitor kedua tetap jalan di hardware apa pun tanpa perlu diedit.
- Tombol `XF86MonBrightnessUp`/`Down` di `i3/config` manggil
  `brightnessctl` langsung, jadi di laptop itu udah konsisten sama
  jalur yang dipakai `backlight.sh`. Di desktop ini practically no-op
  (gak ada panel buat `brightnessctl` atur) — repoint ke
  `backlight.sh up`/`down` kalau mau tombol fisik ngatur monitor
  eksternal lewat DDC/CI juga.
- Semua ikon dari Font Awesome, sumbernya `ttf-jetbrains-mono-nerd`
  dengan `otf-font-awesome` sebagai fallback font.
- `qt5ct.conf`, `qt6ct.conf`, `uad/config.toml`, `greenclip.toml`, dan
  `mount-image.desktop` punya absolute path mesin sumber tertanam di
  satu-dua setting — repoint kalau username kamu beda.

## Special thanks

Tema GTK yang dipasangkan `installer/` di-*build* langsung dari repo
upstream-nya masing-masing — bukan hasil kerja repo ini, cuma
dipasangkan otomatis. Terima kasih buat para pembuatnya:

| Tema | Repo GitHub |
| --- | --- |
| Catppuccin | [Fausto-Korpsvart/Catppuccin-GTK-Theme](https://github.com/Fausto-Korpsvart/Catppuccin-GTK-Theme) |
| Gruvbox | [Fausto-Korpsvart/Gruvbox-GTK-Theme](https://github.com/Fausto-Korpsvart/Gruvbox-GTK-Theme) |
| Tokyonight | [Fausto-Korpsvart/Tokyonight-GTK-Theme](https://github.com/Fausto-Korpsvart/Tokyonight-GTK-Theme) |
| Everforest | [Fausto-Korpsvart/Everforest-GTK-Theme](https://github.com/Fausto-Korpsvart/Everforest-GTK-Theme) |
| Nordic | [EliverLara/Nordic](https://github.com/EliverLara/Nordic) |

Dan tentunya seluruh maintainer [i3](https://i3wm.org/),
[polybar](https://github.com/polybar/polybar),
[rofi](https://github.com/davatorium/rofi),
[picom](https://github.com/yshui/picom), dan
[ratatui](https://ratatui.rs) yang bikin semua ini bisa berdiri.
