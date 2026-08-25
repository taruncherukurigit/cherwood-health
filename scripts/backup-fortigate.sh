#!/bin/bash
#
# backup-fortigate.sh
# Pulls a full configuration snapshot from the FortiGate, diffs it against
# the previous snapshot, and logs whether anything changed.
#
# Requires: SSH public key attached to the admin account via
#   config system admin / edit admin / set ssh-public-key1 "..."
# See docs/COMMAND-REFERENCE.md Part 15/16 for full setup steps.
#
# Note: this pulls "show full-configuration", not "show running-config" --
# FortiGate's abbreviated view hides fields still at their default value,
# which can hide real conflicts (see TROUBLESHOOTING-LOG.md Part 11 for why
# that distinction matters). It also disables FortiGate's own CLI pager
# first, in the same SSH session -- without that, the pull silently
# truncates once the pager blocks on a non-interactive session.

DEVICE_NAME="fortigate"
DEVICE_IP="10.10.10.1"                          # <-- replace with your device's IP
SSH_KEY="/root/.ssh/cherwood_backup_rsa"         # <-- replace with your key path
SSH_USER="admin"

BACKUP_DIR="/root/config-backups/${DEVICE_NAME}"
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
NEW_BACKUP="${BACKUP_DIR}/${DEVICE_NAME}-${TIMESTAMP}.txt"
LATEST_LINK="${BACKUP_DIR}/latest.txt"
LOG_FILE="/root/config-backups/backup.log"

mkdir -p "$BACKUP_DIR"

ssh -i "$SSH_KEY" \
    -oStrictHostKeyChecking=no \
    "${SSH_USER}@${DEVICE_IP}" << 'FGCMDS' > "$NEW_BACKUP" 2>/dev/null
config system console
set output standard
end
show full-configuration
FGCMDS

if [ ! -s "$NEW_BACKUP" ]; then
    echo "$(date): FAILED - backup for ${DEVICE_NAME} was empty" >> "$LOG_FILE"
    rm -f "$NEW_BACKUP"
    exit 1
fi

if [ -f "$LATEST_LINK" ]; then
    if diff -q "$LATEST_LINK" "$NEW_BACKUP" > /dev/null; then
        echo "$(date): ${DEVICE_NAME} - no changes detected" >> "$LOG_FILE"
    else
        echo "$(date): ${DEVICE_NAME} - CONFIG CHANGED, diff below:" >> "$LOG_FILE"
        diff "$LATEST_LINK" "$NEW_BACKUP" >> "$LOG_FILE"
        echo "---" >> "$LOG_FILE"
    fi
else
    echo "$(date): ${DEVICE_NAME} - first backup taken" >> "$LOG_FILE"
fi

cp "$NEW_BACKUP" "$LATEST_LINK"
