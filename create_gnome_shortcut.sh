#!/usr/bin/env bash

set -euo pipefail

# GNOME custom keyboard shortcut manager (idempotent)
#
# Usage:
#   create_gnome_shortcut.sh add <name> <binding> <command>
#   create_gnome_shortcut.sh remove <name>
#   create_gnome_shortcut.sh list
#
# Examples:
#   create_gnome_shortcut.sh add "Nautilus" "<Super>e" "nautilus"
#   create_gnome_shortcut.sh remove "Nautilus"
#   create_gnome_shortcut.sh list
#
# Idempotency: running "add" with the same name will update the existing
# shortcut's binding and command in place, rather than creating a duplicate.

SCHEMA_LIST="org.gnome.settings-daemon.plugins.media-keys"
SCHEMA_ITEM="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding"
PATH_PREFIX="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom"

# Get the current custom-keybindings path list as a newline-separated list of indices.
# Returns nothing if no custom shortcuts exist.
get_existing_indices() {
    local path_list
    path_list=$(gsettings get "$SCHEMA_LIST" custom-keybindings)

    if [[ "$path_list" == "@as []" || "$path_list" == "[]" ]]; then
        return
    fi

    # Extract indices from paths like '/org/.../custom0/', '/org/.../custom12/'
    echo "$path_list" | grep -oP 'custom\K\d+'
}

# Find the index of an existing shortcut by name. Returns empty if not found.
find_index_by_name() {
    local target_name="$1"

    for idx in $(get_existing_indices); do
        local name
        name=$(gsettings get "$SCHEMA_ITEM:${PATH_PREFIX}${idx}/" name)
        # gsettings wraps the value in single quotes
        if [[ "$name" == "'${target_name}'" ]]; then
            echo "$idx"
            return
        fi
    done
}

# Find the next available index (smallest non-negative integer not in use).
next_available_index() {
    local indices
    indices=$(get_existing_indices | sort -n)

    local candidate=0
    for idx in $indices; do
        if [[ "$idx" -eq "$candidate" ]]; then
            ((candidate++))
        else
            break
        fi
    done
    echo "$candidate"
}

# Add index to the custom-keybindings path list (if not already present).
add_to_path_list() {
    local new_idx="$1"
    local new_path="'${PATH_PREFIX}${new_idx}/'"
    local path_list
    path_list=$(gsettings get "$SCHEMA_LIST" custom-keybindings)

    # Check if already in the list
    if [[ "$path_list" == *"${PATH_PREFIX}${new_idx}/"* ]]; then
        return
    fi

    if [[ "$path_list" == "@as []" || "$path_list" == "[]" ]]; then
        gsettings set "$SCHEMA_LIST" custom-keybindings "[${new_path}]"
    else
        # Insert before the closing bracket
        local updated="${path_list%]*}, ${new_path}]"
        gsettings set "$SCHEMA_LIST" custom-keybindings "$updated"
    fi
}

# Remove index from the custom-keybindings path list.
remove_from_path_list() {
    local rm_idx="$1"
    local rm_path="'${PATH_PREFIX}${rm_idx}/'"
    local path_list
    path_list=$(gsettings get "$SCHEMA_LIST" custom-keybindings)

    if [[ "$path_list" == "@as []" || "$path_list" == "[]" ]]; then
        return
    fi

    # Remove the path entry (handle both ", '/path'" and "'/path', " patterns)
    local updated
    updated=$(echo "$path_list" | sed "s|, ${rm_path}||; s|${rm_path}, ||; s|${rm_path}||")

    # If the list is now empty, reset it
    if [[ "$updated" == "[]" || "$updated" == "[ ]" ]]; then
        gsettings reset "$SCHEMA_LIST" custom-keybindings
    else
        gsettings set "$SCHEMA_LIST" custom-keybindings "$updated"
    fi
}

cmd_add() {
    local name="$1"
    local binding="$2"
    local command="$3"

    local idx
    idx=$(find_index_by_name "$name")

    if [[ -z "$idx" ]]; then
        idx=$(next_available_index)
        echo "Creating shortcut '${name}' at index ${idx}"
    else
        echo "Updating existing shortcut '${name}' at index ${idx}"
    fi

    local schema="${SCHEMA_ITEM}:${PATH_PREFIX}${idx}/"
    gsettings set "$schema" name "$name"
    gsettings set "$schema" binding "$binding"
    gsettings set "$schema" command "$command"

    add_to_path_list "$idx"
}

cmd_remove() {
    local name="$1"

    local idx
    idx=$(find_index_by_name "$name")

    if [[ -z "$idx" ]]; then
        echo "Shortcut '${name}' not found, nothing to remove"
        return
    fi

    echo "Removing shortcut '${name}' at index ${idx}"

    local schema="${SCHEMA_ITEM}:${PATH_PREFIX}${idx}/"
    gsettings reset "$schema" name
    gsettings reset "$schema" binding
    gsettings reset "$schema" command

    remove_from_path_list "$idx"
}

cmd_list() {
    local indices
    indices=$(get_existing_indices | sort -n)

    if [[ -z "$indices" ]]; then
        echo "No custom shortcuts configured"
        return
    fi

    printf "%-5s %-30s %-25s %s\n" "IDX" "NAME" "BINDING" "COMMAND"
    printf "%-5s %-30s %-25s %s\n" "---" "----" "-------" "-------"

    for idx in $indices; do
        local schema="${SCHEMA_ITEM}:${PATH_PREFIX}${idx}/"
        local name binding command
        name=$(gsettings get "$schema" name | sed "s/^'//;s/'$//")
        binding=$(gsettings get "$schema" binding | sed "s/^'//;s/'$//")
        command=$(gsettings get "$schema" command | sed "s/^'//;s/'$//")
        printf "%-5s %-30s %-25s %s\n" "$idx" "$name" "$binding" "$command"
    done
}

usage() {
    echo "Usage:"
    echo "  $(basename "$0") add <name> <binding> <command>"
    echo "  $(basename "$0") remove <name>"
    echo "  $(basename "$0") list"
    exit 1
}

# --- Main ---

if [[ $# -lt 1 ]]; then
    usage
fi

case "$1" in
    add)
        [[ $# -ne 4 ]] && { echo "Error: 'add' requires 3 arguments: name, binding, command"; usage; }
        cmd_add "$2" "$3" "$4"
        ;;
    remove)
        [[ $# -ne 2 ]] && { echo "Error: 'remove' requires 1 argument: name"; usage; }
        cmd_remove "$2"
        ;;
    list)
        cmd_list
        ;;
    *)
        echo "Error: unknown command '$1'"
        usage
        ;;
esac
