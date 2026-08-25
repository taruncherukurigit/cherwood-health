# Scripts

Automation scripts from Part 15/16 of the build. All four are real, working scripts — sanitized here with placeholder IPs and key paths so they're safe to publish; swap in your own values to actually run them.

| Script | What it does |
|---|---|
| `backup-1921.sh` | Nightly config snapshot of the Branch office router, with diffing |
| `backup-switch.sh` | Nightly config snapshot of the core switch, with diffing |
| `backup-fortigate.sh` | Nightly full-configuration snapshot of the FortiGate, with diffing |
| `isolation-check.sh` | Parses the FortiGate backup and verifies critical segmentation DENY policies are still present, enabled, and correctly configured |

## Setup

1. Generate a dedicated SSH key for automation (don't reuse a personal key):
   ```bash
   ssh-keygen -t rsa -b 2048 -f /root/.ssh/cherwood_backup_rsa -N ""
   ```
2. Add the public key to each device — see [`../docs/COMMAND-REFERENCE.md`](../docs/COMMAND-REFERENCE.md) Part 15/16 for the exact steps (Cisco and FortiGate use different mechanisms).
3. Edit each script's `DEVICE_IP` and `SSH_KEY` variables to match your environment.
4. Test each manually before scheduling:
   ```bash
   chmod +x *.sh
   ./backup-1921.sh
   cat /root/config-backups/backup.log
   ```
5. Schedule via cron:
   ```
   0 2 * * * /path/to/backup-1921.sh
   5 2 * * * /path/to/backup-switch.sh
   10 2 * * * /path/to/backup-fortigate.sh
   15 2 * * * /path/to/isolation-check.sh
   ```

## Why these specific compatibility flags on the Cisco scripts

Older Cisco IOS SSH implementations don't support several of modern OpenSSH's default algorithms. If you're pointing these scripts at newer Cisco gear, you likely won't need the `-oKexAlgorithms`, `-c aes256-cbc`, `-oHostKeyAlgorithms`, or `-oPubkeyAcceptedKeyTypes` flags at all — try without them first, and only add what's needed based on the actual error you get. Full explanation of each flag in [`../docs/COMMAND-REFERENCE.md`](../docs/COMMAND-REFERENCE.md).

## A note on the isolation-check script specifically

This script had a real, subtle bug during development that only surfaced when tested against a genuinely broken scenario, not a clean one. Worth reading [`../docs/TROUBLESHOOTING-LOG.md`](../docs/TROUBLESHOOTING-LOG.md) (Part 15/16) before assuming any check like this is correct just because it passes on a first run.
