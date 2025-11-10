#!/bin/bash
# Centralized trash cleanup for safe_rm system
# Scans /scratch/trashcan/*/.trash for old directories

TRASH_BASE="/scratch/trashcan"
LOG_DIR="/usr/local/sw/logs"
LOG_FILE="$LOG_DIR/trash_cleanup.log"
mkdir -p "$LOG_DIR"

# Function to show help
show_help() {
    cat << EOF
Safe-RM Trash Cleanup - Help
========================================

Usage: trash_cleanup [OPTIONS]

Options:
  -u, --user <username>     Clean trash for specific user only
  -a, --age <time>          Clean files older than specified time
                            Format: <number><unit> where unit is:
                              m = minutes (e.g., 30m)
                              h = hours   (e.g., 2h)
                              d = days    (e.g., 7d)
                            Default: 7d (7 days)
  --do-it                   Actually perform cleanup (default is dry run)
  -h, --help                Show this help message

Examples:
  trash_cleanup                                  # Dry run, all users, 7 days
  trash_cleanup --do-it                          # Clean all users, 7 days
  trash_cleanup -u jtonini                       # Dry run for jtonini only
  trash_cleanup -u jtonini --do-it               # Clean jtonini's trash
  trash_cleanup -a 30m --do-it                   # Clean all users, 30 min old
  trash_cleanup -u jtonini -a 1h --do-it         # Clean jtonini, 1 hour old

Centralized trash location: $TRASH_BASE/<username>/trash
Log file: $LOG_FILE
EOF
    exit 0
}

# Parse arguments
SINGLE_USER=""
DO_IT=false
AGE_VALUE=""
AGE_UNIT=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -u|--user)
            SINGLE_USER="$2"
            shift 2
            ;;
        -a|--age)
            # Parse age argument (e.g., 30m, 2h, 7d)
            if [[ $2 =~ ^([0-9]+)([mhd])$ ]]; then
                AGE_VALUE="${BASH_REMATCH[1]}"
                AGE_UNIT="${BASH_REMATCH[2]}"
                shift 2
            else
                echo "Error: Invalid age format '$2'. Use format like: 30m, 2h, 7d"
                exit 1
            fi
            ;;
        --do-it)
            DO_IT=true
            shift
            ;;
        *)
            if [ -z "$SINGLE_USER" ] && [[ ! $1 == -* ]]; then
                SINGLE_USER="$1"
            fi
            shift
            ;;
    esac
done

# Set default age if not specified (7 days)
if [ -z "$AGE_VALUE" ]; then
    AGE_VALUE=7
    AGE_UNIT="d"
fi

# Convert age to find command parameters
case $AGE_UNIT in
    m)
        FIND_TIME_PARAM="-mmin"
        FIND_TIME_VALUE="+$AGE_VALUE"
        AGE_DISPLAY="$AGE_VALUE minutes"
        ;;
    h)
        FIND_TIME_PARAM="-mmin"
        FIND_TIME_VALUE="+$((AGE_VALUE * 60))"
        AGE_DISPLAY="$AGE_VALUE hours"
        ;;
    d)
        FIND_TIME_PARAM="-mtime"
        FIND_TIME_VALUE="+$AGE_VALUE"
        AGE_DISPLAY="$AGE_VALUE days"
        ;;
esac

# Determine which users to process
if [ -n "$SINGLE_USER" ]; then
    if [ ! -d "$TRASH_BASE/$SINGLE_USER" ]; then
        echo "Error: User '$SINGLE_USER' not found in $TRASH_BASE/"
        exit 1
    fi
    user_list="$TRASH_BASE/$SINGLE_USER"
    target_msg="user '$SINGLE_USER'"
else
    user_list="$TRASH_BASE/*"
    target_msg="ALL users"
fi

# Initialize statistics
declare -A trash_sizes
declare -A old_trash_sizes
total_scanned=0
with_trash=0
with_old_trash=0
cleaned=0
old_cleaned=0
total_size_kb=0
old_total_size_kb=0

# Header
if [ "$DO_IT" = false ]; then
    echo "=========================================="
    echo "Safe-RM Trash Cleanup - DRY RUN"
    echo "=========================================="
else
    echo "=========================================="
    echo "Safe-RM Trash Cleanup - CLEANING"
    echo "=========================================="
fi

echo "Target: $target_msg"
echo "Action: Delete trash directories older than $AGE_DISPLAY"
echo "Location: $TRASH_BASE"
echo ""

if [ "$DO_IT" = false ]; then
    echo "To actually perform cleanup, run:"
    if [ -n "$SINGLE_USER" ]; then
        echo "  $0 -u $SINGLE_USER -a ${AGE_VALUE}${AGE_UNIT} --do-it"
    else
        echo "  $0 -a ${AGE_VALUE}${AGE_UNIT} --do-it"
    fi
    echo ""
fi

echo "Scanning trash directories..."
echo ""

# Process each user's trash
for user_dir in $user_list; do
    if [ -d "$user_dir" ]; then
        username=$(basename "$user_dir")
        
        # Skip if not a valid user directory
        if [ "$username" = "*" ]; then
            continue
        fi
        
        ((total_scanned++))
        
        trash_dir="$user_dir/.trash"
        
        echo "Checking $username..." >&2
        
        # Check if .trash exists
        if [ ! -d "$trash_dir" ]; then
            continue
        fi
        
        ((with_trash++))
        
        # Get trash size in KB
        trash_size_kb=$(du -sk "$trash_dir" 2>/dev/null | cut -f1)
        if [ -n "$trash_size_kb" ] && [ "$trash_size_kb" -gt 0 ]; then
            trash_sizes[$username]=$trash_size_kb
            total_size_kb=$((total_size_kb + trash_size_kb))
        fi
        
        if [ "$DO_IT" = true ]; then
            # Actually delete old trash
            deleted=$(find "$trash_dir" -maxdepth 1 -type d -name "2*" $FIND_TIME_PARAM $FIND_TIME_VALUE -print -exec rm -rf {} + 2>/dev/null | wc -l)
            
            if [ "$deleted" -gt 0 ]; then
                ((cleaned++))
                echo "  [OK] Cleaned $username's trash ($deleted directories)"
                echo "$(date '+%Y-%m-%d %H:%M:%S') | CLEANED | $username | age: $AGE_DISPLAY | $deleted directories removed" >> "$LOG_FILE"
            fi
        else
            # Dry run - show what would be deleted
            old_dirs=$(find "$trash_dir" -maxdepth 1 -type d -name "2*" $FIND_TIME_PARAM $FIND_TIME_VALUE 2>/dev/null)
            
            if [ -n "$old_dirs" ]; then
                dir_count=$(echo "$old_dirs" | wc -l)
                size=$(du -sh "$trash_dir" 2>/dev/null | cut -f1)
                echo "  --> Found: $dir_count old directories, trash size: $size"
            fi
        fi
    fi
done

echo ""

# Also check for .trash.old directories in /home (from migration)
echo "Checking for old trash directories in /home..." >&2
echo ""

for user_home in /home/*; do
    if [ -d "$user_home" ]; then
        username=$(basename "$user_home")
        old_trash_dir="$user_home/.trash.old"
        
        # Skip if .trash.old doesn't exist
        if [ ! -d "$old_trash_dir" ]; then
            continue
        fi
        
        ((with_old_trash++))
        
        echo "Checking $username's .trash.old..." >&2
        
        # Get size
        old_size_kb=$(du -sk "$old_trash_dir" 2>/dev/null | cut -f1)
        if [ -n "$old_size_kb" ] && [ "$old_size_kb" -gt 0 ]; then
            old_trash_sizes[$username]=$old_size_kb
            old_total_size_kb=$((old_total_size_kb + old_size_kb))
        fi
        
        if [ "$DO_IT" = true ]; then
            # Delete old trash directories with same age policy
            deleted=$(find "$old_trash_dir" -maxdepth 1 -type d -name "2*" $FIND_TIME_PARAM $FIND_TIME_VALUE -print -exec rm -rf {} + 2>/dev/null | wc -l)
            
            if [ "$deleted" -gt 0 ]; then
                ((old_cleaned++))
                echo "  [OK] Cleaned $username's .trash.old ($deleted directories)"
                echo "$(date '+%Y-%m-%d %H:%M:%S') | CLEANED | $username/.trash.old | age: $AGE_DISPLAY | $deleted directories removed" >> "$LOG_FILE"
            fi
            
            # If .trash.old is now empty AND older than 30 days, remove it
            if [ -z "$(ls -A "$old_trash_dir" 2>/dev/null)" ]; then
                # Check if directory is older than 30 days
                dir_age_days=$(( ( $(date +%s) - $(stat -c %Y "$old_trash_dir" 2>/dev/null || echo 0) ) / 86400 ))
                if [ "$dir_age_days" -gt 30 ]; then
                    rmdir "$old_trash_dir" 2>/dev/null
                    echo "  [OK] Removed empty .trash.old directory (created $dir_age_days days ago)"
                    echo "$(date '+%Y-%m-%d %H:%M:%S') | REMOVED | $username/.trash.old | empty directory older than 30 days" >> "$LOG_FILE"
                fi
            fi
        else
            # Dry run
            old_dirs=$(find "$old_trash_dir" -maxdepth 1 -type d -name "2*" $FIND_TIME_PARAM $FIND_TIME_VALUE 2>/dev/null)
            
            if [ -n "$old_dirs" ]; then
                dir_count=$(echo "$old_dirs" | wc -l)
                size=$(du -sh "$old_trash_dir" 2>/dev/null | cut -f1)
                echo "  --> Found: $dir_count old directories in .trash.old, size: $size"
            fi
        fi
    fi
done

echo ""

# Convert total sizes to human readable
total_size_human=$(numfmt --to=iec-i --suffix=B $((total_size_kb * 1024)) 2>/dev/null || echo "0B")
old_total_size_human=$(numfmt --to=iec-i --suffix=B $((old_total_size_kb * 1024)) 2>/dev/null || echo "0B")
combined_size_kb=$((total_size_kb + old_total_size_kb))
combined_size_human=$(numfmt --to=iec-i --suffix=B $((combined_size_kb * 1024)) 2>/dev/null || echo "0B")

# Get top 3 users
mapfile -t top3 < <(for user in "${!trash_sizes[@]}"; do
    echo "${trash_sizes[$user]} $user"
done | sort -rn | head -3)

# Display final report
echo "=========================================="
echo "           SUMMARY REPORT"
echo "=========================================="
echo ""
echo "=========================================="
echo "  CENTRALIZED TRASH (/scratch/trashcan)"
echo "=========================================="
echo "  Total users scanned:     $total_scanned"
echo "  Users with .trash:       $with_trash"
echo "  Total trash size:        $total_size_human"
if [ "$DO_IT" = true ]; then
    echo "  Users cleaned:           $cleaned"
fi
echo ""

if [ ${#top3[@]} -gt 0 ]; then
    echo "  Top 3 users by trash size:"
    for i in "${!top3[@]}"; do
        size_kb=$(echo "${top3[$i]}" | awk '{print $1}')
        username=$(echo "${top3[$i]}" | awk '{print $2}')
        size_human=$(numfmt --to=iec-i --suffix=B $((size_kb * 1024)) 2>/dev/null || echo "${size_kb}K")
        echo "    $((i+1)). $username: $size_human"
    done
    echo ""
fi

# Show old trash statistics if any exist
if [ "$with_old_trash" -gt 0 ]; then
    echo "=========================================="
    echo "  OLD TRASH DIRECTORIES (~/.trash.old)"
    echo "=========================================="
    echo "  Users with .trash.old:   $with_old_trash"
    echo "  Total old trash size:    $old_total_size_human"
    if [ "$DO_IT" = true ]; then
        echo "  Old trash cleaned:       $old_cleaned"
    fi
    echo ""
    
    # Get top 3 old trash users
    mapfile -t old_top3 < <(for user in "${!old_trash_sizes[@]}"; do
        echo "${old_trash_sizes[$user]} $user"
    done | sort -rn | head -3)
    
    if [ ${#old_top3[@]} -gt 0 ]; then
        echo "  Top 3 users by old trash size:"
        for i in "${!old_top3[@]}"; do
            size_kb=$(echo "${old_top3[$i]}" | awk '{print $1}')
            username=$(echo "${old_top3[$i]}" | awk '{print $2}')
            size_human=$(numfmt --to=iec-i --suffix=B $((size_kb * 1024)) 2>/dev/null || echo "${size_kb}K")
            echo "    $((i+1)). $username: $size_human"
        done
        echo ""
    fi
fi

echo "=========================================="
echo "  COMBINED TOTAL"
echo "=========================================="
echo "  All trash locations:     $combined_size_human"

echo ""
echo "=========================================="

if [ "$DO_IT" = false ]; then
    echo ""
    echo "Dry run complete. Use --do-it to actually delete old trash."
fi

# Log summary
if [ "$DO_IT" = true ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') | SUMMARY | age: $AGE_DISPLAY | cleaned $cleaned out of $total_scanned users | total size: $total_size_human" >> "$LOG_FILE"
    if [ "$with_old_trash" -gt 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | SUMMARY | .trash.old | cleaned $old_cleaned users | old trash size: $old_total_size_human" >> "$LOG_FILE"
    fi
fi
