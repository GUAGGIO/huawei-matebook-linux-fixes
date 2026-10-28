# Huawei MateBook (`BOD-WXX9`) Linux Fixes — Kernel Audio & Goodix Fingerprint (`27c6:5125`)

Complete hardware enablement scripts and kernel patches for the **Huawei MateBook D 15 (`BOD-WXX9`)** running **Ubuntu 22.04 LTS (Jammy)** and **Ubuntu 24.04 LTS (Noble)**.

*(Guida in Italiano disponibile nella seconda metà del documento / Italian guide below)*

---

## 🇬🇧 English Documentation

### Hardware Addressed
| Component | Hardware ID / Details | Linux Issue | Solution Included |
| :--- | :--- | :--- | :--- |
| **Soundcard (Speakers, Headphones, Mic)** | Intel Tiger Lake-LP Smart Sound (`sof-hda-dsp`) + ACPI Ghost Device `ESSX8336` | BIOS exposes a bogus `ESSX8336` ACPI entry, causing the kernel (`snd-soc-acpi-intel-match`) to load the wrong driver (`sof-essx8336`) with no sound. Also requires `hda-verb` GPIO/pin routing on Ubuntu 24.04 (where modules are `.ko.zst` compressed). | Automatic kernel `postinst.d` binary patcher supporting both `.ko` and `.ko.zst` (`zstd`) + systemd daemon for speaker/headphone auto-switching and internal mic boost. |
| **Fingerprint Sensor** | Shenzhen Goodix Technology Co., Ltd. **`27c6:5125`** | Proprietary TLS-PSK encrypted USB protocol unsupported by upstream `libfprint`; Ubuntu 24.04 package changes (`systemd-dev`, `libgirepository-2.0-dev`, `libfprint-2-2t64`, `doctest` pkg-config) break standard community scripts. | Automated installer building [`Rockytkg/goodix-linux-27c6-5125`](https://github.com/Rockytkg/goodix-linux-27c6-5125) + SIGFM `libfprint` fork with Ubuntu 24.04 Meson fixes, `udev` rules, `fprintd --no-timeout` keepalive, and PAM `max-tries=3 timeout=30` tuning. |

### 1. Kernel & Soundcard Fix (`audio-kernel-fix/`)
- [`zz-huawei-audio-patch`](./audio-kernel-fix/zz-huawei-audio-patch): Placed in `/etc/kernel/postinst.d/`. Automatically runs on every kernel upgrade, decompresses `snd-soc-acpi-intel-match.ko.zst` (Ubuntu 24.04) or `.ko` (Ubuntu 22.04), patches the ghost `ESSX8336` ACPI match string to `XXXX8336`, strips debug symbols, recompresses, and runs `depmod`.
- [`huawei-soundcard-headphones-monitor.sh`](./audio-kernel-fix/huawei-soundcard-headphones-monitor.sh) & [`.service`](./audio-kernel-fix/huawei-soundcard-headphones-monitor.service): Systemd service that configures HDA nodes (`0x16`, `0x17`, `0x01`, `0x19`, `0x13`) via `hda-verb` and `amixer` to enable the internal speaker, microphone, and automatic headphone jack switching.

**Install:**
```bash
sudo ./audio-kernel-fix/install-audio-fix.sh
```

### 2. Goodix `27c6:5125` Fingerprint Fix (`fingerprint-goodix-27c6-5125/`)
- [`install-goodix-ubuntu24.sh`](./fingerprint-goodix-27c6-5125/install-goodix-ubuntu24.sh): Downloads, patches, builds, and installs the `goodixgf` + SIGFM `libfprint` driver cleanly on Ubuntu 24.04 LTS & 22.04 LTS.
- [`doctest.pc`](./fingerprint-goodix-27c6-5125/doctest.pc): Fixes missing pkg-config metadata for `doctest-dev` on Ubuntu/Debian.
- [`70-goodix.rules`](./fingerprint-goodix-27c6-5125/70-goodix.rules): Grants proper USB permissions and disables USB autosuspend for `27c6:5125`.
- [`update_pam_tries.sh`](./fingerprint-goodix-27c6-5125/update_pam_tries.sh): Updates `/usr/share/pam-configs/fprintd` and `/etc/pam.d/common-auth` from `max-tries=1 timeout=10` to `max-tries=3 timeout=30` to prevent immediate password fallback on slight finger misplacement.

**Install:**
```bash
sudo ./fingerprint-goodix-27c6-5125/install-goodix-ubuntu24.sh
```

**Enroll & Verify:**
```bash
fprintd-enroll -f right-index-finger "$USER"
fprintd-verify
```

---

## 🇮🇹 Documentazione in Italiano

### Problemi Risolti su Huawei MateBook (`BOD-WXX9`)
1. **Fix Kernel & Scheda Audio (`audio-kernel-fix/`)**:
   - Il BIOS di questo portatile espone un dispositivo ACPI fantasma (`ESSX8336`) che inganna il kernel Linux facendogli caricare il driver sbagliato (`snd-soc-sof-es8336`) invece del vero codec HDA gestito da `sof-hda-dsp`.
   - Lo script [`zz-huawei-audio-patch`](./audio-kernel-fix/zz-huawei-audio-patch) in `/etc/kernel/postinst.d/` interviene automaticamente a ogni aggiornamento del kernel (supportando sia i moduli `.ko` di Ubuntu 22.04 sia i nuovi moduli compressi `.ko.zst` di Ubuntu 24.04), sostituendo `ESSX8336` con `XXXX8336`.
   - Il demone [`huawei-soundcard-headphones-monitor.sh`](./audio-kernel-fix/huawei-soundcard-headphones-monitor.sh) inizializza i pin HDA con `hda-verb` (altoparlanti, cuffie e microfono interno) e commuta automaticamente l'uscita audio quando vengono collegate o scollegate le cuffie.

2. **Fix Sensore di Impronte Digitali Goodix `27c6:5125` (`fingerprint-goodix-27c6-5125/`)**:
   - Integra il driver della community [`Rockytkg/goodix-linux-27c6-5125`](https://github.com/Rockytkg/goodix-linux-27c6-5125) con il fork `libfprint` (algoritmo **SIGFM / OpenCV SIFT**) adattato per **Ubuntu 24.04 LTS (`noble`)**:
     - Risolve i cambi di nome dei pacchetti di Ubuntu 24.04 (`systemd-dev`, `libgirepository-2.0-dev`, `libfprint-2-2t64`).
     - Risolve l'errore di compilazione Meson legato a `doctest` su Ubuntu/Debian.
     - Configura il servizio `fprintd` con `--no-timeout` per una risposta istantanea al login, blocco schermo e `sudo`.
     - Configura PAM ([`update_pam_tries.sh`](./fingerprint-goodix-27c6-5125/update_pam_tries.sh)) con `max-tries=3` e `timeout=30` (invece di `max-tries=1`), così da permettere fino a 3 tentativi consecutivi se si appoggia male il dito senza dover subito digitare la password.

### Installazione Rapida

```bash
# 1. Installa la patch kernel e il servizio per la scheda audio
sudo ./audio-kernel-fix/install-audio-fix.sh

# 2. Compila e installa il driver per il lettore di impronte Goodix 27c6:5125
sudo ./fingerprint-goodix-27c6-5125/install-goodix-ubuntu24.sh

# 3. Registra la tua impronta digitale
fprintd-enroll -f right-index-finger "$USER"
```

## Credits
- Goodix `27c6:5125` protocol reverse engineering & driver: [Rockytkg/goodix-linux-27c6-5125](https://github.com/Rockytkg/goodix-linux-27c6-5125), [sorguido/goodix-27c6-5125](https://github.com/sorguido/goodix-27c6-5125), and [abb128/libfprint](https://github.com/abb128/libfprint) (SIGFM).
