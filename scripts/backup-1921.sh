#!/bin/bash
#
# backup-1921.sh
# Pulls a full running-config snapshot from the Branch office router (Cisco 1921),
# diffs it against the previous snapshot, and logs whether anything changed.
#
# Requires: SSH key-based auth already configured (RSA 2048 -- this device's
# IOS version does not support Ed25519 for pubkey-chain auth). See
# docs/COMMAND-REFERENCE.md Part 15/16 for full setup steps and the
# compatibility flags below.

DEVICE_NAME="1921"
DEVICE_IP="10.10.99.2"                          # <-- replace with your device's IP
SSH_KEY="/root/.ssh/cherwood_backup_rsa"         # <-- replace with your key path
SSH_USER="admin"

BACKUP_DIR="/root/config-backups/${DEVICE_NAME}"
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
NEW_BACKUP="${BACKUP_DIR}/${DEVICE_NAME}-${TIMESTAMP}.txt"
LATEST_LINK="${BACKUP_DIR}/latest.txt"
LOG_FILE="/root/config-backups/backup.log"

mkdir -p "$BACKUP_DIR"

# Compatibility flags below are required for older Cisco IOS SSH stacks that
# don't support modern OpenSSH defaults. See TROUBLESHOOTING-LOG.md Part 15/16
# for why each one is needed.
ssh -i "$SSH_KEY" \
    -oKexAlgorithms=+diffie-hellman-group14-sha1 \
    -c aes256-cbc \
    -oHostKeyAlgorithms=+ssh-rsa \
    -oPubkeyAcceptedKeyTypes=+ssh-rsa \
    -oStrictHostKeyChecking=no \
    "${SSH_USER}@${DEVICE_IP}" "show running-config" > "$NEW_BACKUP" 2>/dev/null

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
