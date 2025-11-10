#!/bin/bash
# Safe RM - Move files to centralized trash instead of deleting
# Trash location: /scratch/trashcan/$USER/.trash

TRASH_BASE="/scratch/trashcan"
TRASH_DIR="$TRASH_BASE/$USER/.trash"
SYMLINK_PATH="$HOME/.trash"

# Ensure trash directory exists with correct permissions
if [ ! -d "$TRASH_DIR" ]; then
    mkdir -p "$TRASH_DIR" 2>/dev/null
    chmod 770 "$TRASH_DIR" 2>/dev/null
    chmod g+s "$TRASH_DIR" 2>/dev/null
fi

# Create symlink in user's home if it doesn't exist
if [ ! -e "$SYMLINK_PATH" ]; then
    # Nothing exists - create symlink
    ln -s "$TRASH_DIR" "$SYMLINK_PATH" 2>/dev/null
elif [ ! -L "$SYMLINK_PATH" ]; then
    # ~/.trash exists but is not a symlink (edge case)
    # Rename it to preserve data, then create proper symlink
    if [ -d "$SYMLINK_PATH" ] || [ -f "$SYMLINK_PATH" ]; then
        mv "$SYMLINK_PATH" "${SYMLINK_PATH}.old" 2>/dev/null
        ln -s "$TRASH_DIR" "$SYMLINK_PATH" 2>/dev/null
        echo "Notice: Old ~/.trash moved to ~/.trash.old" >&2
        echo "        New trash location: $TRASH_DIR" >&2
    fi
fi

# Parse arguments to separate flags from files
interactive=false
force=false
recursive=false
files=()

for arg in "$@"; do
    case "$arg" in
        -i|--interactive)
            interactive=true
            ;;
        -f|--force)
            force=true
            ;;
        -r|-R|--recursive)
            recursive=true
            ;;
        -rf|-fr|-Rf|-fR)
            recursive=true
            force=true
            ;;
        -rfi|-rif|-fri|-fir|-irf|-ifr)
            recursive=true
            force=true
            interactive=true
            ;;
        -*)
            # Ignore other flags but notify user
            echo "rm: ignoring unsupported flag '$arg'" >&2
            ;;
        *)
            files+=("$arg")
            ;;
    esac
done

# If no files specified, show usage
if [ ${#files[@]} -eq 0 ]; then
    echo "Usage: rm [OPTION]... FILE..." >&2
    echo "Move files to trash: $TRASH_DIR" >&2
    echo "" >&2
    echo "Options:" >&2
    echo "  -f, --force           ignore nonexistent files, never prompt" >&2
    echo "  -i, --interactive     prompt before every removal" >&2
    echo "  -r, -R, --recursive   remove directories and their contents" >&2
    echo "" >&2
    echo "To permanently delete, use: command rm or /bin/rm" >&2
    exit 1
fi

# Process each file/directory
for item in "${files[@]}"; do
    if [ ! -e "$item" ] && [ ! -L "$item" ]; then
        if [ "$force" = false ]; then
            echo "rm: cannot remove '$item': No such file or directory" >&2
        fi
        continue
    fi
    
    # Check if it's a directory and -r wasn't specified
    if [ -d "$item" ] && [ ! -L "$item" ] && [ "$recursive" = false ]; then
        echo "rm: cannot remove '$item': Is a directory" >&2
        continue
    fi
    
    # Get absolute path
    abs_path=$(realpath "$item" 2>/dev/null || readlink -f "$item" 2>/dev/null || echo "$item")
    
    # Interactive prompt if requested and not forced
    if [ "$interactive" = true ] && [ "$force" = false ]; then
        read -p "rm: remove '$item'? " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            continue
        fi
    fi
    
    # Create timestamp-based directory
    timestamp=$(date +%Y%m%d_%H%M%S_%N)
    
    # Determine the relative path for organizing in trash
    # Remove leading slashes and make it a valid path
    if [[ "$abs_path" == /home/$USER/* ]]; then
        rel_path=${abs_path#/home/$USER/}
        rel_path="home/$rel_path"
    elif [[ "$abs_path" == /scratch/$USER/* ]]; then
        rel_path=${abs_path#/scratch/$USER/}
        rel_path="scratch/$rel_path"
    elif [[ "$abs_path" == /scratch/* ]]; then
        rel_path=${abs_path#/}
    else
        rel_path=${abs_path#/}
    fi
    
    trash_path="$TRASH_DIR/$timestamp/$rel_path"
    
    # Create directory structure and move
    mkdir -p "$(dirname "$trash_path")" 2>/dev/null
    
    if mv "$item" "$trash_path" 2>/dev/null; then
        if [ "$force" = false ]; then
            echo "Moved to trash: $trash_path"
        fi
    else
        echo "rm: cannot remove '$item': Permission denied" >&2
    fi
done
