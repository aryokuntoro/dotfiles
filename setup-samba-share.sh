#!/usr/bin/env bash
set -euo pipefail

# ── Enable Thunar's Properties -> Share tab (thunar-shares-plugin) ──
# That plugin creates shares via Samba's "usershare" mechanism, which
# needs: a real smb.conf with usershare enabled, a sambashare group
# the user belongs to, the usershares directory, and smbd/nmbd
# actually running. None of this existed on this machine yet.
#
# Guest access (no password) chosen per user request -- fine for a
# trusted home LAN, not for anything internet-facing.

# Checked before anything else runs: $SUDO_USER is only set when this
# was invoked via `sudo` from a normal user session. Run as a raw root
# login (or via `su`) instead, it's unset, and under `set -u` the
# script used to abort partway through -- after already creating the
# sambashare group -- instead of failing before touching anything.
: "${SUDO_USER:?SUDO_USER is not set. Run this via: sudo $0}"

echo "==> Creating sambashare group"
groupadd -f sambashare

echo "==> Adding $SUDO_USER to sambashare group"
usermod -aG sambashare "$SUDO_USER"

echo "==> Creating usershares directory"
mkdir -p /var/lib/samba/usershares
chown root:sambashare /var/lib/samba/usershares
chmod 1770 /var/lib/samba/usershares

echo "==> Writing /etc/samba/smb.conf"
cat >/etc/samba/smb.conf <<'EOF'
[global]
   workgroup = WORKGROUP
   server string = %h
   security = user
   map to guest = Bad User
   guest account = nobody

   usershare path = /var/lib/samba/usershares
   usershare max shares = 100
   usershare allow guests = yes
   usershare owner only = yes

   log file = /var/log/samba/log.%m
   max log size = 1000
   logging = file
EOF

echo "==> Validating config"
testparm -s

echo "==> Enabling + starting smb/nmb"
systemctl enable --now smb.service nmb.service

echo "==> Opening SMB/CIFS ports in ufw"
ufw allow CIFS

echo "==> Done. Log out and back in (or reboot) so the sambashare group membership takes effect."
