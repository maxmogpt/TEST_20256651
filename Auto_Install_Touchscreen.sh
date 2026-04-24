#!/bin/bash
#
# Auto_Install_Touchscreen.sh
# Automatisiertes Skript zur Installation des Touchscreens auf Microsoft Surface Book Gen 1 unter Linux Mint
# Entwickelt von Funkenflug Innovation Laboratories
# Lizenz: MIT License

set -euo pipefail

# --- Farben ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

function echo_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
function echo_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
function echo_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
function echo_error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

function check_root() {
    [ "$(id -u)" -ne 0 ] && echo_error "Bitte mit 'sudo' ausführen."
}

function check_os() {
    if ! grep -qi "mint\|ubuntu\|debian" /etc/os-release 2>/dev/null; then
        echo_error "Dieses Skript ist nur für Debian-basierte Systeme (Linux Mint, Ubuntu) geeignet."
    fi
}

function install_dependencies() {
    echo_info "Installiere Abhängigkeiten..."
    apt-get update && apt-get install -y wget gnupg2 || echo_error "Fehler beim Installieren der Abhängigkeiten."
}

function setup_surface_repository() {
    if [ -f /etc/apt/sources.list.d/linux-surface.list ]; then
        echo_info "Surface-Repository bereits vorhanden, überspringe..."
        return
    fi

    echo_info "Richte Surface-Repository ein..."

    # Explizit auf wget-Fehler prüfen (set -o pipefail greift hier)
    wget -qO /tmp/surface.asc https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc
    gpg --dearmor -o /etc/apt/trusted.gpg.d/linux-surface.gpg /tmp/surface.asc
    rm -f /tmp/surface.asc

    echo "deb [arch=amd64] https://pkg.surfacelinux.com/debian release main" \
        | tee /etc/apt/sources.list.d/linux-surface.list > /dev/null

    apt-get update || echo_error "Fehler beim Einrichten des Surface-Repositorys."
}

function install_surface_kernel() {
    if dpkg -l | grep -q "^ii.*linux-image-surface"; then
        echo_info "Surface-Kernel bereits installiert, überspringe..."
        return
    fi

    echo_info "Installiere Surface-Kernel und Pakete..."
    apt-get install -y linux-image-surface linux-headers-surface libwacom-surface iptsd linux-surface-secureboot-mok \
        || echo_error "Fehler beim Installieren des Surface-Kernels."

    echo_warning "Secure Boot: Beim nächsten Boot erscheint der MOK-Manager."
    echo_warning "Wähle dort 'Enroll MOK' -> 'Continue' -> 'Yes' -> Passwort eingeben, um den Kernel-Schlüssel zu bestätigen."
}

function backup_grub() {
    if [ ! -f /etc/default/grub.backup ]; then
        echo_info "Erstelle Backup der GRUB-Konfiguration..."
        cp /etc/default/grub /etc/default/grub.backup
    else
        echo_info "GRUB-Backup bereits vorhanden, überspringe..."
    fi
}

function modify_grub() {
    if grep -q "i8042.nokbd=1" /etc/default/grub; then
        echo_info "GRUB bereits angepasst, überspringe..."
        return
    fi

    echo_info "Passe GRUB an für bessere Touchscreen-Unterstützung..."
    # Parameter robust anhängen, unabhängig vom bestehenden Inhalt der Zeile
    sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/"$/ i8042.nokbd=1"/' /etc/default/grub

    if ! grep -q "i8042.nokbd=1" /etc/default/grub; then
        echo_error "GRUB-Anpassung fehlgeschlagen. Bitte manuell prüfen: /etc/default/grub"
    fi

    update-grub || echo_error "Fehler beim Aktualisieren von GRUB."
}

function load_kernel_modules() {
    echo_info "Lade Kernel-Module..."
    modprobe i2c_hid        || echo_warning "Modul i2c_hid konnte nicht geladen werden."
    modprobe hid_multitouch || echo_warning "Modul hid_multitouch konnte nicht geladen werden."
    modprobe hid_elan       || echo_warning "Modul hid_elan konnte nicht geladen werden."
}

function check_installation() {
    echo_info "Prüfe Installation (Hinweis: Surface-Kernel und Touchscreen erst nach Neustart aktiv)..."

    if ! uname -a | grep -q "surface"; then
        echo_warning "Surface-Kernel läuft noch nicht – nach Neustart im GRUB-Menü auswählen."
    fi

    if ! command -v libinput &>/dev/null || ! libinput list-devices 2>/dev/null | grep -q "IPTS"; then
        echo_warning "Touchscreen noch nicht als IPTS erkannt – nach Neustart prüfen mit: libinput list-devices"
    fi

    if ! systemctl is-active --quiet iptsd 2>/dev/null; then
        echo_warning "iptsd läuft nicht – nach Neustart prüfen mit: systemctl status iptsd"
    fi
}

function print_summary() {
    echo_info "Zusammenfassung:"
    echo "--------------------------------"

    local repo_status kernel_status iptsd_status wacom_status grub_status modules_status

    [ -f /etc/apt/sources.list.d/linux-surface.list ] && repo_status="${GREEN}OK${NC}"           || repo_status="${RED}FEHLT${NC}"
    dpkg -l | grep -q "^ii.*linux-image-surface"      && kernel_status="${GREEN}OK${NC}"          || kernel_status="${RED}FEHLT${NC}"
    dpkg -l | grep -q "^ii.*iptsd"                    && iptsd_status="${GREEN}OK${NC}"           || iptsd_status="${RED}FEHLT${NC}"
    dpkg -l | grep -q "^ii.*libwacom-surface"          && wacom_status="${GREEN}OK${NC}"           || wacom_status="${RED}FEHLT${NC}"
    grep -q "i8042.nokbd=1" /etc/default/grub          && grub_status="${GREEN}OK${NC}"           || grub_status="${RED}FEHLT${NC}"
    lsmod | grep -q "i2c_hid"                          && modules_status="${GREEN}OK${NC}"         || modules_status="${YELLOW}Erst nach Neustart${NC}"

    echo -e "1. Surface-Repository:  $repo_status"
    echo -e "2. Surface-Kernel:      $kernel_status"
    echo -e "3. iptsd:               $iptsd_status"
    echo -e "4. libwacom-surface:    $wacom_status"
    echo -e "5. GRUB angepasst:      $grub_status"
    echo -e "6. Kernel-Module:       $modules_status"
    echo "--------------------------------"
}

# --- Hauptskript ---
echo_info "Starte Auto_Install_Touchscreen.sh für Microsoft Surface Book Gen 1..."

check_root
check_os
install_dependencies
setup_surface_repository
backup_grub
install_surface_kernel
modify_grub
load_kernel_modules
check_installation
print_summary

echo_success "Fertig! Bitte neu starten und im GRUB-Menü den Surface-Kernel wählen."
echo_info "Nach dem Neustart prüfen mit: xinput list  oder  libinput list-devices"
echo_info "Bei Problemen: dmesg | grep -i touch  oder  journalctl -b | grep -Ei 'ipts|touch|stylus'"
