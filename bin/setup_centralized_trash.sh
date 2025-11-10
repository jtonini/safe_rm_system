#!/bin/bash
# Setup script for centralized trash system
# Creates /scratch/trashcan structure and user symlinks

TRASH_BASE="/scratch/trashcan"

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

# Create base trashcan directory
if [ ! -d "$TRASH_BASE" ]; then
    echo "Creating $TRASH_BASE..."
    mkdir -p "$TRASH_BASE"
    chmod 775 "$TRASH_BASE"
    chmod g+s "$TRASH_BASE"
else
    echo "[OK] $TRASH_BASE already exists"
    # Verify permissions
    current_perms=$(stat -c %a "$TRASH_BASE" 2>/dev/null)
    current_group=$(stat -c %G "$TRASH_BASE" 2>/dev/null)
    
    echo "  Current permissions: $current_perms"
    echo "  Current group: $current_group"
    
    # Check if SGID is set (2xxx or 3xxx permissions)
    if [[ ! "$current_perms" =~ ^[23] ]]; then
        echo "  --> Setting SGID bit..."
        chmod g+s "$TRASH_BASE"
    fi
fi

echo ""
echo "Setting up user directories..."
echo ""

users_created=0
users_skipped=0
symlinks_created=0

# Process all users in /home
for user_home in /home/*; do
    if [ -d "$user_home" ]; then
        username=$(basename "$user_home")
        
        # Skip system users
        if [ "$username" = "installer" ] || [ "$username" = "root" ]; then
            ((users_skipped++))
            continue
        fi
        
        user_trash_dir="$TRASH_BASE/$username"
        
        # Create user's trash directory if it doesn't exist
        if [ ! -d "$user_trash_dir" ]; then
            echo "Creating trash directory for $username..."
            
            # Create as the user with correct permissions
            # SGID on parent ensures installer group is inherited
            sudo -u "$username" bash -c "
                mkdir -p '$user_trash_dir/.trash'
                chmod 770 '$user_trash_dir'
                chmod 770 '$user_trash_dir/.trash'
                chmod g+s '$user_trash_dir'
                chmod g+s '$user_trash_dir/.trash'
            " 2>/dev/null
            
            if [ $? -eq 0 ]; then
                ((users_created++))
            else
                echo "  [FAIL] Failed to create directory for $username"
            fi
        else
            echo "  --> $username already has trash directory"
            
            # Verify .trash subdirectory exists
            if [ ! -d "$user_trash_dir/.trash" ]; then
                echo "    Creating .trash subdirectory..."
                sudo -u "$username" bash -c "
                    mkdir -p '$user_trash_dir/.trash'
                    chmod 770 '$user_trash_dir/.trash'
                    chmod g+s '$user_trash_dir/.trash'
                " 2>/dev/null
            fi
        fi
        
        # Create symlink in user's home directory
        symlink_path="$user_home/.trash"
        
        if [ -L "$symlink_path" ]; then
            echo "  --> Symlink already exists for $username"
        elif [ -e "$symlink_path" ]; then
            echo "  [WARN] Warning: $symlink_path exists but is not a symlink (skipping)"
        else
            # Create symlink as the user
            sudo -u "$username" ln -s "$user_trash_dir/.trash" "$symlink_path" 2>/dev/null
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
echo "  New trash directories:   $users_created"
echo "  New symlinks created:    $symlinks_created"
echo "  Users skipped:           $users_skipped"
echo ""
echo "Structure:"
echo "  Trash location:  $TRASH_BASE/<username>/.trash"
echo "  User symlink:    /home/<username>/.trash -> $TRASH_BASE/<username>/.trash"
echo "  Permissions:     User: rwx, Group (installer): rwx, Others: none"
echo ""
echo "Next steps:"
echo "  1. Install safe_rm and trash_cleanup scripts"
echo "  2. Set up safe_rm alias in system-wide bashrc"
echo "  3. Configure cron job for trash_cleanup"
echo ""
echo "=========================================="
