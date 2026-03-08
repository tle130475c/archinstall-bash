#!/usr/bin/env bash
# restore_kvm_vm.sh - Restore a KVM VM from a backup created by backup_kvm_vm.sh

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
DEFAULT_IMAGES_DIR="/var/lib/libvirt/images"

# ── Helpers ───────────────────────────────────────────────────────────────────
usage() {
    echo "Usage: $0 -b <backup-dir> [-i <images-dir>] [-s] [-h]"
    echo ""
    echo "  -b  Backup directory to restore from (e.g. /var/backups/kvm/win11_20260308_120000)"
    echo "  -i  Destination for disk images (default: $DEFAULT_IMAGES_DIR)"
    echo "  -s  Start VM after restore"
    echo "  -h  Show this help"
    exit 1
}

log()  { echo "[INFO]  $*"; }
warn() { echo "[WARN]  $*"; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

check_deps() {
    for cmd in virsh qemu-img; do
        command -v "$cmd" &>/dev/null || die "'$cmd' not found. Install qemu-full and libvirt."
    done
}

# ── Parse args ────────────────────────────────────────────────────────────────
BACKUP_DIR=""
IMAGES_DIR="$DEFAULT_IMAGES_DIR"
START_VM=false

while getopts "b:i:sh" opt; do
    case $opt in
        b) BACKUP_DIR="$OPTARG" ;;
        i) IMAGES_DIR="$OPTARG" ;;
        s) START_VM=true ;;
        h) usage ;;
        *) usage ;;
    esac
done

[[ -z "$BACKUP_DIR" ]] && usage

check_deps

# ── Validate backup directory ─────────────────────────────────────────────────
[[ -d "$BACKUP_DIR" ]] || die "Backup directory not found: $BACKUP_DIR"

# Find the VM XML file
XML_FILE=$(find "$BACKUP_DIR" -maxdepth 1 -name "*.xml" | head -1)
[[ -z "$XML_FILE" ]] || [[ ! -f "$XML_FILE" ]] && die "No VM XML found in: $BACKUP_DIR"

VM_NAME=$(basename "$XML_FILE" .xml)
DISKS_DIR="$BACKUP_DIR/disks"
SNAPSHOTS_DIR="$BACKUP_DIR/snapshots"

log "Restoring VM:  $VM_NAME"
log "From backup:   $BACKUP_DIR"
log "Images dir:    $IMAGES_DIR"

# ── Check if VM already exists ────────────────────────────────────────────────
if virsh dominfo "$VM_NAME" &>/dev/null; then
    warn "VM '$VM_NAME' already exists in libvirt."
    read -rp "         Undefine existing VM and continue? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || die "Aborted."
    virsh undefine "$VM_NAME" --snapshots-metadata 2>/dev/null || virsh undefine "$VM_NAME"
    log "Existing VM undefined."
fi

# ── Restore disk images ───────────────────────────────────────────────────────
[[ -d "$DISKS_DIR" ]] || die "Disks directory not found: $DISKS_DIR"

mkdir -p "$IMAGES_DIR"

log "Restoring disk images..."
for IMG in "$DISKS_DIR"/*; do
    [[ -f "$IMG" ]] || continue
    BASENAME=$(basename "$IMG")
    DEST="$IMAGES_DIR/$BASENAME"

    if [[ -f "$DEST" ]]; then
        warn "  Disk already exists: $DEST"
        read -rp "         Overwrite? [y/N] " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || { log "  Skipping: $BASENAME"; continue; }
    fi

    log "  Copying: $BASENAME → $DEST"
    cp --sparse=always "$IMG" "$DEST"
done

# ── Fix disk paths in XML if images dir differs from original ─────────────────
TEMP_XML=$(mktemp /tmp/vm-restore-XXXXXX.xml)
cp "$XML_FILE" "$TEMP_XML"

# Extract original images path from XML and replace with new one
ORIG_PATH=$(grep -oP "(?<=<source file=')[^']+" "$TEMP_XML" | head -1 | xargs dirname 2>/dev/null || true)
if [[ -n "$ORIG_PATH" ]] && [[ "$ORIG_PATH" != "$IMAGES_DIR" ]]; then
    log "Updating disk paths: $ORIG_PATH → $IMAGES_DIR"
    sed -i "s|${ORIG_PATH}/|${IMAGES_DIR}/|g" "$TEMP_XML"
fi

# ── Define VM ─────────────────────────────────────────────────────────────────
log "Defining VM in libvirt..."
virsh define "$TEMP_XML"
rm -f "$TEMP_XML"

# ── Restore NVRAM (UEFI VMs) ──────────────────────────────────────────────────
NVRAM_SRC=$(compgen -G "$BACKUP_DIR/*_VARS.fd" 2>/dev/null | head -1 || true)
if [[ -n "$NVRAM_SRC" ]]; then
    NVRAM_DEST="/var/lib/libvirt/qemu/nvram/${VM_NAME}_VARS.fd"
    log "Restoring NVRAM: $NVRAM_DEST"
    mkdir -p "$(dirname "$NVRAM_DEST")"
    cp "$NVRAM_SRC" "$NVRAM_DEST"
fi

# ── Restore snapshots ─────────────────────────────────────────────────────────
if [[ -d "$SNAPSHOTS_DIR" ]] && compgen -G "$SNAPSHOTS_DIR/*.xml" > /dev/null 2>&1; then
    log "Restoring snapshots..."

    # Fix paths in snapshot XMLs (external snapshots also reference disk files)
    TEMP_SNAP_DIR=$(mktemp -d /tmp/vm-restore-snaps-XXXXXX)
    for SNAP_XML in "$SNAPSHOTS_DIR"/*.xml; do
        SNAP_NAME=$(basename "$SNAP_XML" .xml)
        TEMP_SNAP="$TEMP_SNAP_DIR/${SNAP_NAME}.xml"
        cp "$SNAP_XML" "$TEMP_SNAP"
        if [[ -n "$ORIG_PATH" ]] && [[ "$ORIG_PATH" != "$IMAGES_DIR" ]]; then
            sed -i "s|${ORIG_PATH}/|${IMAGES_DIR}/|g" "$TEMP_SNAP"
        fi
    done

    # Use saved topological order if available, otherwise fall back to --topological query
    ORDER_FILE="$SNAPSHOTS_DIR/order"
    if [[ -f "$ORDER_FILE" ]]; then
        mapfile -t SORTED_SNAPS < "$ORDER_FILE"
    else
        mapfile -t SORTED_SNAPS < <(virsh snapshot-list "$VM_NAME" --name --topological 2>/dev/null || true)
    fi

    # Determine current snapshot by matching VM's active disk to snapshot overlay
    # The VM XML's first <source file> is the active disk
    ACTIVE_DISK=$(grep -oP "(?<=<source file=')[^']+" "$XML_FILE" | head -1)
    ACTIVE_DISK_BASE=$(basename "$ACTIVE_DISK")
    log "Active disk: $ACTIVE_DISK_BASE"

    for SNAP_NAME in "${SORTED_SNAPS[@]}"; do
        [[ -z "$SNAP_NAME" ]] && continue
        TEMP_SNAP="$TEMP_SNAP_DIR/${SNAP_NAME}.xml"
        [[ ! -f "$TEMP_SNAP" ]] && warn "  Snapshot XML not found: $SNAP_NAME — skipping." && continue
        log "  Snapshot: $SNAP_NAME"

        # The first <source file> in the snapshot <disks> section is the overlay this snapshot created
        SNAP_DISK=$(grep -oP "(?<=<source file=')[^']+" "$TEMP_SNAP" | head -1)
        SNAP_DISK_BASE=$(basename "$SNAP_DISK")

        if [[ "$SNAP_DISK_BASE" == "$ACTIVE_DISK_BASE" ]]; then
            log "    → marking as current (overlay matches active disk)"
            virsh snapshot-create "$VM_NAME" --xmlfile "$TEMP_SNAP" --redefine --current \
                || warn "  Failed to restore snapshot: $SNAP_NAME"
        else
            virsh snapshot-create "$VM_NAME" --xmlfile "$TEMP_SNAP" --redefine \
                || warn "  Failed to restore snapshot: $SNAP_NAME"
        fi
    done

    rm -rf "$TEMP_SNAP_DIR"
else
    log "No snapshots to restore."
fi

# ── Start VM if requested ─────────────────────────────────────────────────────
if $START_VM; then
    log "Starting VM '$VM_NAME'..."
    virsh start "$VM_NAME"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
SNAP_COUNT=$(compgen -G "$SNAPSHOTS_DIR/*.xml" 2>/dev/null | wc -l || echo 0)
_rows=("VM:        $VM_NAME" "Images:    $IMAGES_DIR" "Snapshots: $SNAP_COUNT restored" "Started:   $START_VM")
_inner_w=0
for _r in "${_rows[@]}"; do
    (( ${#_r} + 4 > _inner_w )) && _inner_w=$(( ${#_r} + 4 ))
done
(( _inner_w < 30 )) && _inner_w=30
_bar=$(printf '─%.0s' $(seq 1 $_inner_w))
echo ""
echo "┌${_bar}┐"
printf "│  %-$(( _inner_w - 2 ))s│\n" "Restore complete"
echo "├${_bar}┤"
for _r in "${_rows[@]}"; do
    printf "│  %-$(( _inner_w - 4 ))s  │\n" "$_r"
done
echo "└${_bar}┘"
