#!/bin/bash
#
# isolation-check.sh
# Configuration-drift detector for critical firewall segmentation policies.
# Parses the most recent FortiGate config backup and verifies that each
# named policy still exists, is still enabled, and is still set to DENY.
#
# This is not a live network test -- it's a static config check, run right
# after the nightly FortiGate backup. It catches the realistic failure mode
# of someone (including future-you) accidentally disabling or deleting an
# isolation policy without noticing.
#
# IMPORTANT: this script's logic was found to have a real bug during
# development -- it originally searched *forward* from a policy's
# "set name" line for its status/action, but FortiGate writes
# "set status disable" *before* "set name" in its config output, so a
# disabled policy was invisible to the check. The fix (parsing whole policy
# blocks via awk's record separator, below) was only trusted after being
# validated against a real, deliberately-disabled policy. See
# TROUBLESHOOTING-LOG.md Part 15/16 for the full story -- worth reading
# before assuming this script (or any check like it) is correct on the
# strength of a single clean test run.

CONFIG_FILE="/root/config-backups/fortigate/latest.txt"
LOG_FILE="/root/config-backups/isolation-check.log"
TIMESTAMP=$(date)

FAIL=0

check_policy_deny() {
    POLICY_NAME=$1
    # Split the config into whole policy blocks (each ends with "next"),
    # then find the block containing this policy's name -- this avoids
    # assuming a fixed field order within the block.
    BLOCK=$(awk -v RS="next\n" "/set name \"${POLICY_NAME}\"/{print}" "$CONFIG_FILE")

    if [ -z "$BLOCK" ]; then
        echo "$TIMESTAMP: *** ALERT *** ${POLICY_NAME} is MISSING from config" >> "$LOG_FILE"
        FAIL=1
    elif echo "$BLOCK" | grep -q "set status disable"; then
        echo "$TIMESTAMP: *** ALERT *** ${POLICY_NAME} is DISABLED" >> "$LOG_FILE"
        FAIL=1
    elif echo "$BLOCK" | grep -q "set action deny"; then
        echo "$TIMESTAMP: OK - ${POLICY_NAME} is present, enabled, and set to DENY" >> "$LOG_FILE"
    else
        echo "$TIMESTAMP: *** ALERT *** ${POLICY_NAME} is present but NOT set to DENY" >> "$LOG_FILE"
        FAIL=1
    fi
}

if [ ! -f "$CONFIG_FILE" ]; then
    echo "$TIMESTAMP: *** ALERT *** No FortiGate config backup found to check" >> "$LOG_FILE"
    exit 1
fi

# Add/remove policy names here to match your own environment.
check_policy_deny "Guest_to_Trusted_DENY"
check_policy_deny "Guest_to_Servers_DENY"
check_policy_deny "Branch_to_HQ_DENY"

if [ "$FAIL" -eq 1 ]; then
    echo "$TIMESTAMP: ISOLATION CHECK FAILED - review alerts above" >> "$LOG_FILE"
else
    echo "$TIMESTAMP: Isolation check passed - all segmentation policies intact" >> "$LOG_FILE"
fi

echo "---" >> "$LOG_FILE"
