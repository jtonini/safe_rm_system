#!/bin/bash
# Setup safe_rm alias system-wide
# This script attempts to add the rm alias to the appropriate system file

SAFE_RM_PATH="/usr/local/sw/bin/safe_rm"

# Detect which config file to use
if [ -f "/usr/local/etc/usersrc/common" ]; then
    # OpenHPC or custom setup
    CONFIG_FILE="/usr/local/etc/usersrc/common"
    CONFIG_TYPE="usersrc"
elif [ -f "/etc/bashrc" ]; then
    # Standard RHEL/CentOS/Rocky
    CONFIG_FILE="/etc/bashrc"
    CONFIG_TYPE="bashrc"
elif [ -f "/etc/bash.bashrc" ]; then
    # Debian/Ubuntu
    CONFIG_FILE="/etc/bash.bashrc"
    CONFIG_TYPE="bash.bashrc"
else
    CONFIG_FILE=""
    CONFIG_TYPE="unknown"
fi

echo "=========================================="
echo "  Safe-RM Alias Setup"
echo "=========================================="
echo ""
echo "Detecting system bash configuration..."
echo ""

# Check if alias already exists
if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
    if grep -q "alias rm.*safe_rm" "$CONFIG_FILE" 2>/dev/null; then
        echo "[OK] Safe-RM alias already configured in $CONFIG_FILE"
        echo ""
        echo "Current alias:"
        grep "alias rm.*safe_rm" "$CONFIG_FILE"
        echo ""
        exit 0
    fi
fi

# Prepare the alias configuration
ALIAS_CONFIG="
# Safe rm - move files to trash instead of permanent deletion
if [ -f $SAFE_RM_PATH ]; then
    unalias rm 2>/dev/null
    alias rm='$SAFE_RM_PATH'
fi
"

if [ -z "$CONFIG_FILE" ]; then
    echo "[WARN] Could not detect system bashrc file"
    echo ""
    echo "Please manually add this to your system's bash configuration:"
    echo "---"
    echo "$ALIAS_CONFIG"
    echo "---"
    echo ""
    echo "Common locations:"
    echo "  - /etc/bashrc (RHEL/CentOS/Rocky)"
    echo "  - /etc/bash.bashrc (Debian/Ubuntu)"
    echo "  - /usr/local/etc/usersrc/common (OpenHPC)"
    echo ""
    echo "NOTE: Deployment will continue. You can set up the alias later."
    echo ""
    exit 0
fi

# Try to add the alias
echo "Detected config file: $CONFIG_FILE"
echo ""
echo "Attempting to add safe_rm alias..."

if [ -w "$CONFIG_FILE" ]; then
    # We can write to the file directly
    echo "$ALIAS_CONFIG" >> "$CONFIG_FILE"
    echo "[OK] Successfully added safe_rm alias to $CONFIG_FILE"
    echo ""
    echo "Users need to reload their shell:"
    echo "  source ~/.bashrc"
    echo ""
    echo "To verify alias is working:"
    echo "  1. Open a new terminal (or run: source ~/.bashrc)"
    echo "  2. Run: alias rm"
    echo "  3. Should show: alias rm='$SAFE_RM_PATH'"
    echo ""
    exit 0
else
    # Need sudo/root
    echo "[WARN] No write permission to $CONFIG_FILE"
    echo ""
    echo "Manual setup required. Please run as root or with sudo:"
    echo ""
    echo "sudo bash << 'EOF'
cat >> $CONFIG_FILE << 'ALIASEOF'
$ALIAS_CONFIG
ALIASEOF
EOF"
    echo ""
    echo "Or manually add this to $CONFIG_FILE:"
    echo "---"
    echo "$ALIAS_CONFIG"
    echo "---"
    echo ""
    echo "NOTE: Deployment will continue. You can set up the alias later."
    echo ""
fi

# Always exit successfully (deployment should continue)
exit 0
