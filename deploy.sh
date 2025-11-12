#!/bin/bash
# Quick deployment script for safe_rm system
# Supports both centralized and local trash modes
set -e  # Exit on error

REPO_DIR="$HOME/safe_rm_system"
BIN_DIR="/usr/local/sw/bin"
SINGLE_USER=""

# Detect mode
if [ -d "/scratch" ] && [ -d "/scratch/trashcan" ]; then
    MODE="centralized"
elif [ ! -d "/scratch" ]; then
    MODE="local"
else
    # /scratch exists but /scratch/trashcan doesn't
    # Try to create it, let setup script handle the details
    MODE="centralized-setup"
fi

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--user)
            SINGLE_USER="$2"
            shift 2
            ;;
        -h|--help)
            cat << EOF
Deploy Safe RM System - Help
========================================

Current mode: $([ "$MODE" = "centralized" ] || [ "$MODE" = "centralized-setup" ] && echo "centralized" || echo "$MODE")
$([ "$MODE" = "centralized" ] || [ "$MODE" = "centralized-setup" ] && echo "  Centralized trash in /scratch/trashcan" || echo "  Local trash in ~/.trash")

Usage: deploy.sh [OPTIONS]

Options:
  -u, --user <username>     Deploy for specific user only (for testing)
  -h, --help                Show this help message

Examples:
  deploy.sh                  # Full deployment for all users
  deploy.sh -u jtonini       # Test deployment for jtonini only

EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

echo "=========================================="
echo "  Safe RM System - Quick Deploy"
echo "=========================================="
echo ""

# Check if running as installer
if [ "$(whoami)" != "installer" ]; then
    echo "Error: This script should be run as the 'installer' user"
    exit 1
fi

# Handle mode-specific setup
if [ "$MODE" = "centralized" ] || [ "$MODE" = "centralized-setup" ]; then
    # Centralized mode: run setup script (it will create /scratch/trashcan if needed)
    if [ "$MODE" = "centralized-setup" ]; then
        echo "Mode: CENTRALIZED (will create /scratch/trashcan)"
    else
        echo "Mode: CENTRALIZED (/scratch/trashcan)"
    fi
    echo ""
    echo "Step 1: Setting up trash directories..."
    if [ -n "$SINGLE_USER" ]; then
        "$REPO_DIR/bin/setup_centralized_trash.sh" -u "$SINGLE_USER"
    else
        "$REPO_DIR/bin/setup_centralized_trash.sh"
    fi
else
    # Local mode: no setup needed
    echo "Mode: LOCAL (~/.trash)"
    echo ""
    echo "Step 1: Directory setup"
    echo "  --> No setup required for local mode"
    echo "  --> Trash directories will be created automatically when users first use 'rm'"
    echo ""
fi

echo ""
echo "Step 2: Installing scripts to $BIN_DIR..."

# Check if installer can write to /usr/local/sw/bin
if [ -w "$BIN_DIR" ]; then
    # Create symlinks directly
    ln -sf "$REPO_DIR/bin/safe_rm.sh" "$BIN_DIR/safe_rm"
    ln -sf "$REPO_DIR/bin/trash_cleanup.sh" "$BIN_DIR/trash_cleanup"
    echo "  [OK] Created symlink: $BIN_DIR/safe_rm"
    echo "  [OK] Created symlink: $BIN_DIR/trash_cleanup"
else
    # Need to show commands to run
    echo "  [WARN] Cannot write to $BIN_DIR directly"
    echo ""
    echo "  Run these commands to create symlinks:"
    echo "    ln -sf $REPO_DIR/bin/safe_rm.sh $BIN_DIR/safe_rm"
    echo "    ln -sf $REPO_DIR/bin/trash_cleanup.sh $BIN_DIR/trash_cleanup"
    echo ""
    read -p "  Press Enter to continue..."
fi

echo ""
echo "=========================================="
echo "  DEPLOYMENT COMPLETE"
echo "=========================================="
echo ""

if [ "$MODE" = "centralized" ] || [ "$MODE" = "centralized-setup" ]; then
    echo "[OK] Mode: CENTRALIZED"
    echo "[OK] Trash directories created in /scratch/trashcan"
    echo "[OK] User symlinks created in /home/<user>/.trash"
else
    echo "[OK] Mode: LOCAL"
    echo "[OK] Trash will be created in /home/<user>/.trash"
    echo "[OK] No pre-setup required (automatic on first use)"
fi

echo "[OK] Scripts installed in $BIN_DIR"
echo ""

if [ -n "$SINGLE_USER" ]; then
    echo "TEST MODE - Deployed for user '$SINGLE_USER' only"
    echo ""
    echo "Test the system:"
    echo "  1. As $SINGLE_USER, test safe_rm:"
    echo "     be $SINGLE_USER"
    echo "     echo 'test' > /tmp/testfile"
    echo "     rm /tmp/testfile"
    echo "     ls ~/.trash/"
    if [ "$MODE" = "centralized" ]; then
        echo "     # Should be a symlink to /scratch/trashcan/$SINGLE_USER/trash"
    else
        echo "     # Should be a directory (not a symlink)"
    fi
    echo ""
    echo "  2. Test trash_cleanup:"
    echo "     trash_cleanup -u $SINGLE_USER"
    echo ""
    echo "  3. If everything works, deploy to all users:"
    echo "     ./deploy.sh"
else
    echo "Next manual steps:"
    echo "  1. Alias already set in /usr/local/etc/usersrc/common:"
    echo "     alias rm='/usr/local/sw/bin/safe_rm'"
    echo ""
    echo "  2. Add cron job (crontab -e):"
    echo "     0 2 * * * /usr/local/sw/bin/trash_cleanup --do-it >> /usr/local/sw/logs/trash_cleanup.log 2>&1"
    echo ""
    echo "  3. Have users reload their shell:"
    echo "     source ~/.bashrc"
    echo ""
    echo "Test it:"
    echo "  trash_cleanup              # Show statistics (will show mode)"
    echo "  echo 'test' > /tmp/test && rm /tmp/test"
fi
echo ""
echo "=========================================="
