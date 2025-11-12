# Safe RM System - Centralized Trash

A safe deletion system using centralized trash storage in `/scratch/trashcan`.

## Architecture

- **Centralized trash**: `/scratch/trashcan/<username>/trash`
- **User symlink**: `/home/<username>/.trash` -> `/scratch/trashcan/<username>/trash`
- **Automatic migration**: If `~/.trash` exists as a directory, it's renamed to `~/.trash.old`
- **Old trash cleanup**: `trash_cleanup` also cleans `~/.trash.old` directories (including loose files)
- **Permissions**: User owns, `installer` group (gid 1012) has read/write access
- **Note**: SGID doesn't work reliably on NFS, so `trash_cleanup` uses `sudo -u` for .trash.old operations

## Why Centralized Trash?

1. **Saves /home space**: `/home` has limited storage, `/scratch` is larger
2. **Easier management**: Single location for admin cleanup instead of scanning every user's home
3. **Group access**: `installer` group access to trash for cleanup operations
4. **Simplified cleanup**: Direct access to `/scratch/trashcan/*`, `sudo -u` for home directories

## Directory Structure

```
safe_rm_system/
├── bin/
│   ├── safe_rm.sh                   # User command (replaces rm)
│   ├── trash_cleanup.sh             # Admin cleanup tool
│   └── setup_centralized_trash.sh   # Initial setup script
├── docs/                            # Documentation (if needed)
├── deploy.sh                        # Quick deployment script
└── README.md                        # This file
```

## Installation

### 1. Clone/Create Repository

```bash
cd ~
mkdir -p safe_rm_system/bin
cd safe_rm_system
git init
# Add files to bin/ directory
```

### 2. Run Setup Script (creates directories and symlinks)

```bash
cd ~/safe_rm_system
chmod +x bin/*
chmod +x deploy.sh
./bin/setup_centralized_trash.sh
```

This will:
- Verify `/scratch/trashcan` exists with proper permissions
- Create `/scratch/trashcan/<user>/trash` for each user
- Create symlinks: `/home/<user>/.trash` -> `/scratch/trashcan/<user>/trash`
- Set proper permissions (770, attempts SGID where supported)

### 3. Install Scripts via Symlinks

**Manual method:**
```bash
ln -sf ~/safe_rm_system/bin/safe_rm.sh /usr/local/sw/bin/safe_rm
ln -sf ~/safe_rm_system/bin/trash_cleanup.sh /usr/local/sw/bin/trash_cleanup
```

**Or use deploy script (handles everything):**
```bash
~/safe_rm_system/deploy.sh
```

**Note**: Using symlinks means updates to the git repo automatically update the installed scripts!

### 4. Set Up safe_rm Alias System-Wide

Alias is configured in `/usr/local/etc/usersrc/common`:

```bash
# Safe rm - move files to trash instead of permanent deletion
if [ -f /usr/local/sw/bin/safe_rm ]; then
    unalias rm 2>/dev/null
    alias rm='/usr/local/sw/bin/safe_rm'
fi
```

Users can bypass with:
- `command rm file.txt` - use real rm
- `/bin/rm file.txt` - use real rm directly

### 5. Set Up Cron Job (runs daily at 2 AM)

As `installer` user:

```bash
crontab -e

# Add this line:
0 2 * * * /usr/local/sw/bin/trash_cleanup --do-it >> /usr/local/sw/logs/trash_cleanup.log 2>&1
```

## Usage

### For Users

```bash
# Move to trash (interactive prompt)
rm file.txt

# Move to trash (force, no prompt)
rm -f file.txt
rm -rf directory/

# Permanently delete (bypass safe_rm)
command rm file.txt
/bin/rm file.txt
```

### For Admins

```bash
# Dry run - show statistics only
trash_cleanup

# Actually clean trash older than 7 days (default)
trash_cleanup --do-it

# Check specific user
trash_cleanup -u jtonini

# Custom retention period
trash_cleanup -a 3d --do-it    # 3 days
trash_cleanup -a 12h --do-it   # 12 hours
trash_cleanup -a 30m --do-it   # 30 minutes

# Clean specific user with custom age
trash_cleanup -u jtonini -a 1d --do-it
```

## Maintenance

### Update Scripts

```bash
cd ~/safe_rm_system
# Make changes to scripts in bin/
git add .
git commit -m "Description of changes"
git push

# Symlinks in /usr/local/sw/bin/ automatically point to updated versions!
```

### Check Trash Usage

```bash
# Show statistics for all users
trash_cleanup

# Manual check
du -sh /scratch/trashcan/*

# Check specific user
du -sh /scratch/trashcan/jtonini
```

### View Cleanup Logs

```bash
# View recent cleanup history
tail -f /usr/local/sw/logs/trash_cleanup.log

# View full log
less /usr/local/sw/logs/trash_cleanup.log

# Example log entries:
# 2024-11-10 02:00:15 | CLEANED | jtonini | age: 7 days | 3 directories removed
# 2024-11-10 02:00:18 | CLEANED | jtonini/.trash.old | age: 7 days | 2 loose files removed
# 2024-11-10 02:00:20 | REMOVED | jtonini/.trash.old | empty directory older than 30 days
# 2024-11-10 02:00:25 | SUMMARY | age: 7 days | cleaned 45 out of 714 users | remaining size: 42.3GiB
```

### Restore Files from Trash

Users can restore their own files:

```bash
# List trash contents
ls -la ~/.trash/

# Each deletion is in a timestamped directory
ls ~/.trash/20241110_143022_123456789/

# Restore a file
cp ~/.trash/20241110_143022_123456789/tmp/myfile.txt ~/myfile.txt

# Or move it back
mv ~/.trash/20241110_143022_123456789/tmp/myfile.txt ~/
```

Admins can access any user's trash via `/scratch/trashcan/<username>/trash/`

### Old Trash Migration (.trash.old)

If a user had an existing `~/.trash` directory (not a symlink), the setup script automatically:
1. Renames it to `~/.trash.old` (preserves old data)
2. Creates new symlink: `~/.trash` -> `/scratch/trashcan/<user>/trash`
3. Shows notice to user

The `trash_cleanup` script handles `.trash.old` directories:
- Cleans timestamped directories using the same age policy as regular trash
- **Also cleans loose files** (files not in timestamped directories) based on file age
- **Removes empty `.trash.old` directories after 30 days** (gives users time to check/migrate)
- Uses `sudo -u` to access user home directories (permission handling)
- Eventually all `.trash.old` directories will be cleaned up automatically

Users can manually:
```bash
# Check old trash
ls ~/.trash.old/

# Migrate important files
mv ~/.trash.old/important.txt ~/

# Delete if no longer needed
/bin/rm -rf ~/.trash.old
```

### Add New Users

Run the setup script to add new users:

```bash
./bin/setup_centralized_trash.sh
```

Or for a single user:
```bash
./deploy.sh -u username
```

## File Locations

- **Git Repository**: `~/safe_rm_system/`
- **Installed Scripts**: `/usr/local/sw/bin/safe_rm`, `/usr/local/sw/bin/trash_cleanup`
- **Centralized Trash**: `/scratch/trashcan/<username>/trash/`
- **User Symlink**: `/home/<username>/.trash` -> `/scratch/trashcan/<username>/trash`
- **Old Trash**: `/home/<username>/.trash.old` (migration from old system)
- **Logs**: `/usr/local/sw/logs/trash_cleanup.log`

## Permissions Structure

```
/scratch/trashcan/                    drwxrwsrwx  installer:installer (777 + sticky)
/scratch/trashcan/jtonini/            drwxrwx---  jtonini:installer   (770)
/scratch/trashcan/jtonini/trash/      drwxrwxrwx  jtonini:installer   (777)
/home/jtonini/.trash                  lrwxrwxrwx  -> /scratch/trashcan/jtonini/trash
```

- **777 on trash/** allows installer group to delete files owned by users
- **Note**: SGID doesn't work reliably on NFS mounts like /scratch
- **sudo -u** is used by trash_cleanup for operations in user home directories
- **Symlink** makes trash accessible from user's home directory

## Log File Format

The `/usr/local/sw/logs/trash_cleanup.log` file contains:

### CLEANED Entries
When old files are deleted:
```
2024-11-10 02:00:15 | CLEANED | jtonini | age: 7 days | 3 directories removed
2024-11-10 02:00:18 | CLEANED | asmith/.trash.old | age: 7 days | 2 directories removed
2024-11-10 02:00:19 | CLEANED | asmith/.trash.old | age: 7 days | 5 loose files removed
```

### REMOVED Entries
When empty .trash.old directories are deleted:
```
2024-11-10 02:00:20 | REMOVED | jtonini/.trash.old | empty directory older than 30 days
```

### SUMMARY Entries
Overall statistics for the cleanup run:
```
2024-11-10 02:00:25 | SUMMARY | age: 7 days | cleaned 45 out of 714 users | remaining size: 42.3GiB
2024-11-10 02:00:25 | SUMMARY | .trash.old | cleaned 3 users | remaining old trash: 1.2GiB
```

## Troubleshooting

### Users can't create trash directory

Check that `/scratch/trashcan` has proper permissions:
```bash
ls -ld /scratch/trashcan
# Should show: drwxrwsrwx

# Fix if needed:
chmod 2777 /scratch/trashcan
```

### Trash cleanup isn't running

Check cron job:
```bash
crontab -l | grep trash_cleanup

# Check cron logs:
grep trash_cleanup /var/log/cron

# Test manually:
trash_cleanup --do-it
```

### User's trash symlink is broken

Recreate it:
```bash
# As installer, ensure trash directory exists
sudo -u username mkdir -p /scratch/trashcan/username/trash

# Create symlink as user
sudo -u username ln -sf /scratch/trashcan/username/trash /home/username/.trash
```

### Permission denied errors in .trash.old

This is expected - installer can't directly access user home directories. The `trash_cleanup` script uses `sudo -u` to work around this. Ensure installer has sudo privileges for all users.

## Security Considerations

- Each user can only access their own trash via the symlink
- `installer` group has access to centralized trash in `/scratch` for cleanup
- `.trash.old` directories in home are accessed via `sudo -u` for permission
- Files in trash retain original permissions
- Regular `rm` bypass (`command rm` or `/bin/rm`) available for permanent deletion
- Timestamped directories prevent conflicts between deletions

## Version History

- **v1.2** - Fixed permission handling
  - Added `sudo -u` for all .trash.old operations
  - Added loose file cleanup in .trash.old
  - Fixed SINGLE_USER flag respect in .trash.old section
  - Changed trash directory permissions to 777 (NFS doesn't support SGID)
  - Shows remaining trash size after cleanup (not initial size)
  
- **v1.1** - Bug fixes
  - Fixed deploy.sh to use .sh extension for symlinks
  - Added .trash.old migration and cleanup
  - Improved reporting with user statistics
  
- **v1.0** - Initial release with centralized trash system
  - safe_rm: Moves files to `/scratch/trashcan/<user>/trash`
  - trash_cleanup: Scans centralized location, generates statistics
  - setup_centralized_trash.sh: Automated setup with proper permissions
  - Auto-migration: Existing ~/.trash renamed to ~/.trash.old

## Contributing

To contribute or suggest improvements:

1. Make changes in `~/safe_rm_system/`
2. Test thoroughly
3. Commit with descriptive messages
4. Update this README if needed

## License

Internal tool for HPC cluster management.
