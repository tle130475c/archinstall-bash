#!/usr/bin/env bash
# backup_kvm_vm.sh - Backup a KVM VM with all its snapshots and disk chain

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
DEFAULT_BACKUP_DIR="/var/backups/kvm"
DATE=$(date +%Y%m%d_%H%M%S)

# ── Helpers ───────────────────────────────────────────────────────────────────
usage() {
    echo "Usage: $0 -n <vm-name> [-d <backup-dir>] [-s] [-h]"
    echo ""
    echo "  -n  VM name (as shown in: virsh list --all)"
    echo "  -d  Backup destination directory (default: $DEFAULT_BACKUP_DIR)"
    echo "  -s  Shutdown VM before backup (recommended for consistency)"
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

vm_exists() {
    virsh dominfo "$1" &>/dev/null
}

vm_is_running() {
    [[ "$(virsh domstate "$1")" == "running" ]]
}

# ── Main ──────────────────────────────────────────────────────────────────────
VM_NAME=""
BACKUP_DIR="$DEFAULT_BACKUP_DIR"
SHUTDOWN=false

while getopts "n:d:sh" opt; do
    case $opt in
        n) VM_NAME="$OPTARG" ;;
        d) BACKUP_DIR="$OPTARG" ;;
        s) SHUTDOWN=true ;;
        h) usage ;;
        *) usage ;;
    esac
done

[[ -z "$VM_NAME" ]] && usage

check_deps

vm_exists "$VM_NAME" || die "VM '$VM_NAME' not found. Run 'virsh list --all' to see available VMs."

DEST="$BACKUP_DIR/${VM_NAME}_${DATE}"
mkdir -p "$DEST"

log "Backing up VM: $VM_NAME"
log "Destination:   $DEST"

# ── Shutdown if requested ─────────────────────────────────────────────────────
WAS_RUNNING=false
if vm_is_running "$VM_NAME"; then
    WAS_RUNNING=true
    if $SHUTDOWN; then
        log "Shutting down VM '$VM_NAME'..."
        virsh shutdown "$VM_NAME"
        # Wait up to 120s for clean shutdown
        for i in $(seq 1 24); do
            sleep 5
            vm_is_running "$VM_NAME" || break
            [[ $i -eq 24 ]] && die "VM did not shut down in time. Use 'virsh destroy $VM_NAME' to force off."
        done
        log "VM shut down."
    else
        warn "VM is running. Backup may be inconsistent. Use -s to shut down first."
    fi
fi

# ── Export VM XML definition ──────────────────────────────────────────────────
log "Exporting VM XML definition..."
virsh dumpxml "$VM_NAME" > "$DEST/${VM_NAME}.xml"

# ── Export snapshot XMLs (topological order = parent before child) ─────────────
SNAPSHOTS=$(virsh snapshot-list "$VM_NAME" --name --topological 2>/dev/null || true)
if [[ -n "$SNAPSHOTS" ]]; then
    log "Exporting snapshot metadata..."
    mkdir -p "$DEST/snapshots"
    # Save topological order for restore
    echo "$SNAPSHOTS" > "$DEST/snapshots/order"
    while IFS= read -r snap; do
        [[ -z "$snap" ]] && continue
        virsh snapshot-dumpxml "$VM_NAME" "$snap" > "$DEST/snapshots/${snap}.xml"
        log "  Snapshot: $snap"
    done <<< "$SNAPSHOTS"
else
    log "No snapshots found."
fi

# ── Backup NVRAM (UEFI VMs) ───────────────────────────────────────────────────
NVRAM="/var/lib/libvirt/qemu/nvram/${VM_NAME}_VARS.fd"
if [[ -f "$NVRAM" ]]; then
    log "Backing up NVRAM: $NVRAM"
    cp "$NVRAM" "$DEST/${VM_NAME}_VARS.fd"
fi

# ── Backup disk images (full backing chain) ───────────────────────────────────
log "Identifying disk images..."
mkdir -p "$DEST/disks"

# Get all block devices for this VM
DISKS=$(virsh domblklist "$VM_NAME" --details | awk '$2=="disk" {print $4}')

[[ -z "$DISKS" ]] && die "No disk images found for VM '$VM_NAME'."

for DISK in $DISKS; do
    [[ "$DISK" == "-" ]] && continue
    [[ ! -f "$DISK" ]] && warn "Disk file not found: $DISK — skipping." && continue

    log "Processing disk: $DISK"

    # Walk the full backing chain
    CHAIN=$(qemu-img info --backing-chain "$DISK" 2>/dev/null | awk '/^image:/ {print $2}')

    for IMG in $CHAIN; do
        [[ ! -f "$IMG" ]] && warn "Backing file not found: $IMG — skipping." && continue
        BASENAME=$(basename "$IMG")
        OUTFILE="$DEST/disks/$BASENAME"

        if [[ -f "$OUTFILE" ]]; then
            log "  Already copied: $BASENAME — skipping."
            continue
        fi

        log "  Copying: $BASENAME"
        cp --sparse=always "$IMG" "$OUTFILE"
    done
done

# ── Write restore instructions ────────────────────────────────────────────────
cat > "$DEST/RESTORE.md" << EOF
# Restore Instructions for VM: $VM_NAME
# Backed up: $DATE

## Steps

1. Install KVM stack (if not already):
   pacman -S qemu-full libvirt virt-manager
   systemctl enable --now libvirtd

2. Copy disk image(s) back:
   cp $DEST/disks/*.qcow2 /var/lib/libvirt/images/

3. Edit the XML if disk paths changed:
   Edit: $DEST/${VM_NAME}.xml
   Update <source file='...'> to match new disk locations.

4. Define the VM:
   virsh define $DEST/${VM_NAME}.xml

5. (Optional) Restore snapshots:
   for f in $DEST/snapshots/*.xml; do
       virsh snapshot-create $VM_NAME --xmlfile "\$f" --redefine
   done

6. Start the VM:
   virsh start $VM_NAME
EOF

log "Restore guide written to: $DEST/RESTORE.md"

# ── Restart VM if it was running and we shut it down ─────────────────────────
if $SHUTDOWN && $WAS_RUNNING; then
    log "Restarting VM '$VM_NAME'..."
    virsh start "$VM_NAME"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
SNAP_COUNT=$(echo "$SNAPSHOTS" | grep -c . || echo 0)
_label_w=13  # "  Destination: " = 13 chars label + 2 indent
_rows=("VM:          $VM_NAME" "Destination: $DEST" "Snapshots:   $SNAP_COUNT")
_inner_w=0
for _r in "${_rows[@]}"; do
    (( ${#_r} + 4 > _inner_w )) && _inner_w=$(( ${#_r} + 4 ))
done
(( _inner_w < 30 )) && _inner_w=30
_bar=$(printf '─%.0s' $(seq 1 $_inner_w))
echo ""
echo "┌${_bar}┐"
printf "│  %-$(( _inner_w - 2 ))s│\n" "Backup complete"
echo "├${_bar}┤"
for _r in "${_rows[@]}"; do
    printf "│  %-$(( _inner_w - 4 ))s  │\n" "$_r"
done
echo "└${_bar}┘"
