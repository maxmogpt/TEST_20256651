#!/bin/bash
# =============================================================================
# NAS Mount Script fuer Linux Mint
# NAS IP: 172.20.30.20
# Unterstuetzt SMB (Samba/Windows-Freigaben) und NFS
# =============================================================================

NAS_IP="172.20.30.20"

# --- Anmeldedaten fuer SMB ---
# Entweder hier eintragen oder eine Credentials-Datei verwenden (sicherer)
SMB_USER="dein_benutzername"
SMB_PASS="dein_passwort"
# Alternativ: Pfad zu einer Credentials-Datei (empfohlen)
# Datei-Inhalt: username=xxx / password=xxx / domain=xxx (je eine Zeile)
SMB_CREDENTIALS_FILE="$HOME/.smb-credentials"

# =============================================================================
# SMB-LAUFWERKE
# Format: "NAS-Freigabename:Lokaler-Mountpunkt"
# Beispiel: "fotos:/media/$USER/NAS-Fotos"
# =============================================================================
SMB_MOUNTS=(
    # "freigabename:/media/$USER/lokaler-ordnername"   # <-- Vorlage
    "daten:/media/$USER/NAS-Daten"                    # Beispiel: Freigabe "daten"
    "fotos:/media/$USER/NAS-Fotos"                    # Beispiel: Freigabe "fotos"
    # "backup:/media/$USER/NAS-Backup"                # auskommentiert = nicht gemountet
)

# =============================================================================
# NFS-LAUFWERKE
# Format: "NAS-Exportpfad:Lokaler-Mountpunkt"
# Beispiel: "/export/filme:/media/$USER/NAS-Filme"
# =============================================================================
NFS_MOUNTS=(
    # "/export/pfad:/media/$USER/lokaler-ordnername"  # <-- Vorlage
    "/export/daten:/media/$USER/NFS-Daten"            # Beispiel: NFS-Export "/export/daten"
    # "/srv/nfs/musik:/media/$USER/NAS-Musik"         # weiteres Beispiel
)

# =============================================================================
# Funktionen
# =============================================================================

log()  { echo "[$(date '+%H:%M:%S')] $*"; }
warn() { echo "[$(date '+%H:%M:%S')] WARNUNG: $*" >&2; }
err()  { echo "[$(date '+%H:%M:%S')] FEHLER: $*" >&2; }

check_dependencies() {
    local missing=()
    command -v mount.cifs &>/dev/null || missing+=("cifs-utils")
    command -v mount.nfs  &>/dev/null || missing+=("nfs-common")
    if [[ ${#missing[@]} -gt 0 ]]; then
        err "Fehlende Pakete: ${missing[*]}"
        echo "Installation: sudo apt install ${missing[*]}"
        exit 1
    fi
}

check_nas_reachable() {
    if ! ping -c 1 -W 3 "$NAS_IP" &>/dev/null; then
        err "NAS ($NAS_IP) ist nicht erreichbar. Netzwerk pruefen."
        exit 1
    fi
    log "NAS $NAS_IP ist erreichbar."
}

mount_smb() {
    local share="$1"
    local mountpoint="$2"

    if mountpoint -q "$mountpoint"; then
        log "SMB bereits gemountet: $mountpoint"
        return 0
    fi

    mkdir -p "$mountpoint"

    # Credentials-Datei bevorzugen, sonst Inline-Zugangsdaten
    local auth_opts
    if [[ -f "$SMB_CREDENTIALS_FILE" ]]; then
        auth_opts="credentials=$SMB_CREDENTIALS_FILE"
    else
        auth_opts="username=$SMB_USER,password=$SMB_PASS"
    fi

    if sudo mount -t cifs "//$NAS_IP/$share" "$mountpoint" \
        -o "$auth_opts,uid=$(id -u),gid=$(id -g),iocharset=utf8,vers=3.0" 2>/dev/null; then
        log "SMB gemountet:  //$NAS_IP/$share  ->  $mountpoint"
    else
        err "SMB Mount fehlgeschlagen: //$NAS_IP/$share"
    fi
}

mount_nfs() {
    local export_path="$1"
    local mountpoint="$2"

    if mountpoint -q "$mountpoint"; then
        log "NFS bereits gemountet: $mountpoint"
        return 0
    fi

    mkdir -p "$mountpoint"

    if sudo mount -t nfs "$NAS_IP:$export_path" "$mountpoint" \
        -o "rw,soft,intr,timeo=30" 2>/dev/null; then
        log "NFS gemountet:  $NAS_IP:$export_path  ->  $mountpoint"
    else
        err "NFS Mount fehlgeschlagen: $NAS_IP:$export_path"
    fi
}

unmount_all() {
    log "Trenne alle NAS-Verbindungen..."
    for entry in "${SMB_MOUNTS[@]}" "${NFS_MOUNTS[@]}"; do
        local mountpoint="${entry#*:}"
        if mountpoint -q "$mountpoint"; then
            sudo umount "$mountpoint" && log "Getrennt: $mountpoint" || warn "Trennen fehlgeschlagen: $mountpoint"
        fi
    done
}

show_status() {
    echo ""
    echo "=== NAS Mount Status ==="
    for entry in "${SMB_MOUNTS[@]}"; do
        local mp="${entry#*:}"
        mountpoint -q "$mp" && echo "  [OK]  $mp" || echo "  [--]  $mp (nicht gemountet)"
    done
    for entry in "${NFS_MOUNTS[@]}"; do
        local mp="${entry#*:}"
        mountpoint -q "$mp" && echo "  [OK]  $mp" || echo "  [--]  $mp (nicht gemountet)"
    done
    echo ""
}

# =============================================================================
# Hauptprogramm
# =============================================================================

ACTION="${1:-mount}"

case "$ACTION" in
    mount)
        log "Starte NAS-Mount ($NAS_IP)..."
        check_dependencies
        check_nas_reachable

        for entry in "${SMB_MOUNTS[@]}"; do
            IFS=":" read -r share mountpoint <<< "$entry"
            mount_smb "$share" "$mountpoint"
        done

        for entry in "${NFS_MOUNTS[@]}"; do
            IFS=":" read -r export_path mountpoint <<< "$entry"
            mount_nfs "$export_path" "$mountpoint"
        done

        show_status
        ;;
    umount|unmount)
        unmount_all
        show_status
        ;;
    status)
        show_status
        ;;
    *)
        echo "Verwendung: $0 [mount|umount|status]"
        echo "  mount   - Alle Laufwerke verbinden (Standard)"
        echo "  umount  - Alle Laufwerke trennen"
        echo "  status  - Verbindungsstatus anzeigen"
        exit 1
        ;;
esac
