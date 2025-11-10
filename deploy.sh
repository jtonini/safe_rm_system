#!/bin/bash
# Quick deployment script for safe_rm system

set -e  # Exit on error

REPO_DIR="$HOME/safe_rm_system"
BIN_DIR="/usr/local/sw/bin"

echo "=========================================="
echo "  Safe RM System - Quick Deploy"
echo "=========================================="
echo ""

# Check if running as installer
if [ "$(whoami)" != "installer" ]; then
    echo "Error: This script should be run as the 'installer' user"
    exit 1
fi

# Step 1: Setup directories and symlinks
echo "Step 1: Setting up trash directories..."
"$REPO_DIR/bin/setup_centralized_trash.sh"

echo ""
echo "Step 2: Installing scripts to $BIN_DIR..."

# Check if installer can write to /usr/local/sw/bin
if [ -w "$BIN_DIR" ]; then
    # Create symlinks directly
    ln -sf "$REPO_DIR/bin/safe_rm" "$BIN_DIR/safe_rm"
    ln -sf "$REPO_DIR/bin/trash_cleanup" "$BIN_DIR/trash_cleanup"
    echo "  [OK] Created symlink: $BIN_DIR/safe_rm"
    echo "  [OK] Created symlink: $BIN_DIR/trash_cleanup"
else
    # Need to show commands to run
    echo "  [WARN] Cannot write to $BIN_DIR directly"
    echo ""
    echo "  Run these commands to create symlinks:"
    echo "    ln -sf $REPO_DIR/bin/safe_rm $BIN_DIR/safe_rm"
    echo "    ln -sf $REPO_DIR/bin/trash_cleanup $BIN_DIR/trash_cleanup"
    echo ""
    read -p "  Press Enter to continue..." 
fi

echo ""
echo "=========================================="
echo "  DEPLOYMENT COMPLETE"
echo "=========================================="
echo ""
echo "[OK] Trash directories created in /scratch/trashcan"
echo "[OK] User symlinks created in /home/<user>/.trash"
echo "[OK] Scripts installed in $BIN_DIR"
echo ""
echo "Next manual steps:"
echo "  1. Alias already set in /etc/bashrc:"
echo "     alias rm='/usr/local/sw/bin/safe_rm'"
echo ""
echo "  2. Add cron job (crontab -e):"
echo "     0 2 * * * /usr/local/sw/bin/trash_cleanup --do-it >> /usr/local/sw/logs/trash_cleanup.log 2>&1"
echo ""
echo "  3. Have users reload their shell:"
echo "     source ~/.bashrc"
echo ""
echo "Test it:"
echo "  trash_cleanup              # Show statistics"
echo "  echo 'test' > /tmp/test && rm /tmp/test"
echo ""
echo "=========================================="
