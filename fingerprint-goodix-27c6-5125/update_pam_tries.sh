#!/usr/bin/env bash
set -euo pipefail

echo "=== Configurazione tentativi impronta PAM ==="
sed -i 's/max-tries=[0-9]\+/max-tries=3/g' /usr/share/pam-configs/fprintd
sed -i 's/timeout=[0-9]\+/timeout=30/g' /usr/share/pam-configs/fprintd

sed -i 's/max-tries=[0-9]\+/max-tries=3/g' /etc/pam.d/common-auth
sed -i 's/timeout=[0-9]\+/timeout=30/g' /etc/pam.d/common-auth

grep "pam_fprintd" /etc/pam.d/common-auth
grep "pam_fprintd" /usr/share/pam-configs/fprintd
echo "=== Aggiornamento completato con successo ==="
