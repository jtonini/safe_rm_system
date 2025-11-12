#!/bin/bash
# Setup script for centralized trash system
# Only applicable when /scratch partition exists

# Check if /scratch partition exists
if [ ! -d "/scratch" ]; then
    echo "=========================================="
    echo "  Local Trash Mode Detected"
    echo "=========================================="
    echo ""
    echo "This server does not have a /scratch partition."
    echo "The safe_rm system will automatically use LOCAL MODE:"
    echo "  - Trash location: ~/.trash (directory in user's home)"
    echo "  - No setup required"
    echo "  - Each user's trash is created automatically on first use"
    echo ""
    echo "Just install the scripts and you're done:"
    echo "  ln -sf ~/safe_rm_system/bin/safe_rm.sh /usr/local/sw/bin/safe_rm"
    echo "  ln -sf ~/safe_rm_system/bin/trash_cleanup.sh /usr/local/sw/bin/trash_cleanup"
    echo ""
    exit 0
fi

# /scratch exists - ensure /scratch/trashcan is configured
TRASH_BASE="/scratch/trashcan"

SINGLE_USER=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--user)
            SINGLE_USER="$2"
            shift 2
            ;;
        -h|--help)
            cat << EOF
Setup Centralized Trash System - Help
========================================

Usage: setup_centralized_trash.sh [OPTIONS]

Options:
  -u, --user <username>     Set up trash for specific user only (for testing)
  -h, --help                Show this help message

Examples:
  setup_centralized_trash.sh                  # Set up for ALL users
  setup_centralized_trash.sh -u jtonini       # Set up for jtonini only (testing)

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
echo "  Centralized Trash System Setup"
echo "=========================================="
echo ""

# Check if running as installer
CURRENT_USER=$(whoami)
if [ "$CURRENT_USER" != "installer" ]; then
    echo "Error: This script should be run as the 'installer' user"
    exit 1
fi

# Create or verify base trashcan directory
if [ ! -d "$TRASH_BASE" ]; then
    echo "Creating $TRASH_BASE..."
    
    # Try to create it
    if mkdir -p "$TRASH_BASE" 2>/dev/null; then
        # Successfully created - set permissions
        chmod 2777 "$TRASH_BASE" 2>/dev/null
        chgrp installer "$TRASH_BASE" 2>/dev/null
        echo "  [OK] Created $TRASH_BASE with permissions 2777"
    else
        # Failed to create - need admin help
        echo ""
        echo "=========================================="
        echo "  ERROR: Cannot Create Centralized Trash"
        echo "=========================================="
        echo ""
        echo "Installer user does not have permission to create $TRASH_BASE"
        echo ""
        echo "Please ask your system administrator to run:"
        echo "  sudo mkdir -p /scratch/trashcan"
        echo "  sudo chmod 2777 /scratch/trashcan"
        echo "  sudo chown installer:installer /scratch/trashcan"
        echo ""
        echo "Then run this setup script again."
        echo ""
        exit 1
    fi
else
    echo "[OK] $TRASH_BASE already exists"
    
    # Verify permissions on existing directory
    current_perms=$(stat -c %a "$TRASH_BASE" 2>/dev/null)
    current_group=$(stat -c %G "$TRASH_BASE" 2>/dev/null)

    echo "  Current permissions: $current_perms"
    echo "  Current group: $current_group"

    # Check if SGID is set (2xxx or 3xxx permissions)
    if [[ ! "$current_perms" =~ ^[23] ]]; then
        echo "  --> Setting SGID bit..."
        chmod g+s "$TRASH_BASE" 2>/dev/null
    fi
fi

echo ""
echo "Setting up user directories..."
echo ""

if [ -n "$SINGLE_USER" ]; then
    echo "TEST MODE: Setting up for user '$SINGLE_USER' only"
    echo ""
fi

users_created=0
users_skipped=0
symlinks_created=0
directories_migrated=0

# Determine which users to process
if [ -n "$SINGLE_USER" ]; then
    # Single user mode - verify user exists
    if [ ! -d "/home/$SINGLE_USER" ]; then
        echo "Error: User '$SINGLE_USER' not found in /home/"
        exit 1
    fi
    user_list="/home/$SINGLE_USER"
else
    # All users mode
    user_list="/home/*"
fi

# Process users
for user_home in $user_list; do
    if [ -d "$user_home" ]; then
        username=$(basename "$user_home")

        # Skip system users
        if [ "$username" = "installer" ] || [ "$username" = "root" ]; then
            ((users_skipped++))
            continue
        fi

        user_trash_dir="$TRASH_BASE/$username"
        symlink_path="$user_home/.trash"

        # First, handle existing ~/.trash if it's not a symlink
        # Must check as the user since installer can't access user home directories
        trash_exists=$(sudo -u "$username" bash -c "
            if [ -e '$symlink_path' ] && [ ! -L '$symlink_path' ]; then
                echo 'yes'
            else
                echo 'no'
            fi
        " 2>/dev/null)

        if [ "$trash_exists" = "yes" ]; then
            # ~/.trash exists but is not a symlink - rename it first
            echo "  --> Found existing .trash directory for $username"
            echo "      Renaming to .trash.old (preserves user data)..."
            sudo -u "$username" mv "$symlink_path" "${symlink_path}.old" 2>/dev/null
            if [ $? -eq 0 ]; then
                echo "  [OK] Renamed to .trash.old"
                ((directories_migrated++))
            else
                echo "  [FAIL] Failed to rename .trash to .trash.old"
                continue
            fi
        fi

        # Second, check if trashcan directory already exists
        if [ -d "$user_trash_dir" ]; then
            echo "  --> $username already has trashcan directory"

            # Verify trash subdirectory exists
            if [ ! -d "$user_trash_dir/trash" ]; then
                echo "    Creating trash subdirectory..."
                sudo -u "$username" bash -c "
                    mkdir -p '$user_trash_dir/trash'
                    chmod 770 '$user_trash_dir/trash'
                    chmod g+s '$user_trash_dir/trash'
                " 2>/dev/null
            fi
        else
            # Create fresh user's trash directory
            echo "Creating trash directory for $username..."

            # Create as the user with correct permissions
            # SGID on parent ensures installer group is inherited
            sudo -u "$username" bash -c "
                mkdir -p '$user_trash_dir/trash'
                chmod 770 '$user_trash_dir'
                chmod 770 '$user_trash_dir/trash'
                chmod g+s '$user_trash_dir'
                chmod g+s '$user_trash_dir/trash'
            " 2>/dev/null

            if [ $? -eq 0 ]; then
                ((users_created++))
                echo "  [OK] Created trash directory"
            else
                echo "  [FAIL] Failed to create directory for $username"
                continue
            fi
        fi

        # Finally create symlink in user's home directory
        # Check as user since installer can't access home directories
        symlink_status=$(sudo -u "$username" bash -c "
            if [ -L '$symlink_path' ]; then
                echo 'exists'
            elif [ -e '$symlink_path' ]; then
                echo 'not_symlink'
            else
                echo 'none'
            fi
        " 2>/dev/null)

        if [ "$symlink_status" = "exists" ]; then
            echo "  --> Symlink already exists for $username"
        elif [ "$symlink_status" = "not_symlink" ]; then
            # This shouldn't happen since we handled it above, but just in case
            echo "  [WARN] .trash still exists as non-symlink after migration attempt"
        else
            # Create symlink as the user
            sudo -u "$username" ln -s "$user_trash_dir/trash" "$symlink_path" 2>/dev/null
            if [ $? -eq 0 ]; then
                echo "  [OK] Created symlink for $username"
                ((symlinks_created++))
            else
                echo "  [FAIL] Failed to create symlink for $username"
            fi
        fi
    fi
done

echo ""
echo "=========================================="
echo "           SETUP SUMMARY"
echo "=========================================="
if [ -n "$SINGLE_USER" ]; then
    echo "  MODE: TEST (single user)"
    echo "  User: $SINGLE_USER"
else
    echo "  MODE: FULL DEPLOYMENT (all users)"
fi
echo ""
echo "  New trash directories:   $users_created"
echo "  New symlinks created:    $symlinks_created"
echo "  Directories migrated:    $directories_migrated"
echo "  Users skipped:           $users_skipped"
echo ""
echo "Structure:"
echo "  Trash location:  $TRASH_BASE/<username>/trash"
echo "  User symlink:    /home/<username>/.trash -> $TRASH_BASE/<username>/trash"
echo "  Permissions:     User: rwx, Group (installer): rwx, Others: none"
echo ""
if [ "$directories_migrated" -gt 0 ]; then
    echo "NOTE: $directories_migrated existing .trash directories were renamed to .trash.old"
    echo "      These will be automatically cleaned by trash_cleanup after 30 days"
    echo ""
fi
if [ -n "$SINGLE_USER" ]; then
    echo "Test complete! Next steps:"
    echo "  1. Test as user $SINGLE_USER:"
    echo "     be $SINGLE_USER"
    echo "     echo 'test' > /tmp/testfile && rm /tmp/testfile"
    echo "     ls ~/.trash/"
    echo ""
    echo "  2. Test trash_cleanup:"
    echo "     trash_cleanup -u $SINGLE_USER"
    echo ""
    echo "  3. If everything works, deploy to all users:"
    echo "     ./bin/setup_centralized_trash.sh"
else
    echo "Next steps:"
    echo "  1. Install safe_rm and trash_cleanup scripts (if not done):"
    echo "     ln -sf ~/safe_rm_system/bin/safe_rm.sh /usr/local/sw/bin/safe_rm"
    echo "     ln -sf ~/safe_rm_system/bin/trash_cleanup.sh /usr/local/sw/bin/trash_cleanup"
    echo ""
    echo "  2. Alias already set in /etc/bashrc"
    echo ""
    echo "  3. Configure cron job for trash_cleanup"
fi
echo ""
echo "=========================================="
