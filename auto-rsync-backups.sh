#!/bin/bash

# Copyright (C) 2011-2014 Olivier Brunel
# https://github.com/jjk-jacky/auto-rsync-backups

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.


# little script to handle (auto) backup using rsync
#
# the config use can be set in a config file, or on command line. command-line
# takes precedence over config file.
# if none set, default rsync args are used. either way, some are auto-added
# based on other options:
# --verbose         if verbose mode is enabled
# --exclude-from    if option was specified (file must exists, else error)
# --link-dest       if option was specified unless does not exist (yet) or is a symlink
# --log-file        if option was specified
#
# if no date format is specified, default value is used.
#
# * source must be the full path
# * destination is made from dest_root (parent folder) and dest_name (folder
#   name), the later being specified on command line, or generated using the
#   given date format (cmd-line/cfg-file)
# * link-dest is the symlink's name placed in dest_root, and pointing to latest
#   backup
#
# How it works:
# - rsync will copy source into dest (using link-dest if any)
# - symlink (link-dest) is created/updated to point to newly created backup
# - the old backup is removed. That is the backup from $daily days, unless it's
#   a Monday and we have weekly backups, then we go $weekly weeks back and
#   remove that one, unless it's a 1st of the Month and we havbe monthly
#   backups, then we go $monthly months back.
#
# likely to be run as cronjob, e.g.:
# 0 3 * * * backups.sh -c /etc/backups.conf > /var/log/backups.last 2>> /var/log/backups.err
# or, via systemd, using a backups.service from a backups.timer

# loads some common functions
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/auto-rsync-backups.common"

# $1        name of the folder to delete from dest_root, if exists (name
#           calculated from date format...)
function delete_backup()
{
    name="$dest_root$1"
    if [ -d "$name" ]; then
        log "removing old backup: $1"
        rm -rf "$name"
    fi
}

if [[ "$@" = "-h" ]] || [[ "$@" = "--help" ]]; then
    me=$(basename $0)
    echo "auto-rsync-backups v$version - little script to handle (auto) backup using rsync"
    echo ""
    echo "Syntax: $me [options]"
    echo ""
    echo "-h, --help                show this help screen and exit"
    echo "-V, --version             show version information and exit"
    echo ""
    echo "-v, --verbose             enable verbose mode"
    echo "-l, --log-file FILE       set FILE as log file (instead of stdout)"
    echo "-c, --config FILE         set FILE as configuration file"
    echo "    --exclude-from FILE   set FILE as excludes file (rsync's --exclude-from)"
    echo "-s, --source PATH         set PATH as source of the backup"
    echo "-d, --dest-root PATH      set PATH as parent holding the backup folders"
    echo "    --date-format FORMAT  set FORMAT as date format used if no name if specified (--name)"
    echo "-n, --name NAME           set NAME as folder name for backup (see --dest-root for location)"
    echo "    --link-dest SYMLINK   set SYMLINK as reference. must be symlink's name, located into --dest-root"
    echo "                          pointing to last backup (full path sent to rsync's --link-dest)"
    echo "    --args ARGS           set ARGS as arguments for rsync (do NOT include --verbose, --exclude-from"
    echo "                          or --link-dest; they are auto-added if needed)"
    echo "    --monthly NUM         set to keep NUM monthly backups"
    echo "    --weekly NUM          set to keep NUM weekly backups"
    echo "    --daily NUM           set to keep NUM daily backups"
    exit 0
elif [[ "$@" = "-V" ]] || [[ "$@" = "--version" ]]; then
    echo "auto-rsync-backups v$version - little script to handle (auto) backup using rsync"
    echo "Copyright (C) 2011-2014 Olivier Brunel; https://github.com/jjk-jacky/auto-rsync-backups"
    echo "License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>"
    echo "This is free software: you are welcome to change and redistribute it under certain conditions."
    echo "There is NO WARRANTY; see license for more."
    exit 0
fi

# the work begins...

trap 'on_exit' EXIT

log "auto-rsync-backups v$version"
log "- date: $(date +%Y-%m-%d)"
log "- command-line: $@"

# let's parse the command line
while [ ! -z "$1" ]; do
    case "$1" in
        "-v"|"--verbose")
            verbose=1
            log "command-line: verbose mode enabled"
            ;;

        "-l"|"--log-file")
            log_file=$(parse_opt "log file" "$1")
            vlog "command-line: log file: $log_file"
            ;;

        "-c"|"--config")
            shift
            conf_file=$(parse_opt "configuration file" "$1")
            vlog "command-line: configuration file: $conf_file"
            ;;

        "--exclude-from")
            shift
            exclude_from=$(parse_opt "exclude file" "$1")
            vlog "command-line: load excludes from $exclude_from"
            ;;

        "-s"|"--source")
            shift
            source=$(parse_opt "source" "$1")
            vlog "command-line: source: $source"
            ;;

        "-d"|"--dest-root")
            shift
            dest_root=$(parse_opt "destination root" "$1")
            vlog "command-line: destination root: $dest_root"
            ;;

        "--date-format")
            shift
            date_format=$(parse_opt "date format" "$1")
            vlog "command-line: date format set to $date_format"
            ;;

        "-n"|"--name")
            shift
            dest_name=$(parse_opt "destination name" "$1")
            vlog "command-line: destination name: $dest_name"
            ;;

        "--link-dest")
            shift
            link_dest=$(parse_opt "link-dest" "$1")
            vlog "command-line: link dest: $link_dest"
            ;;

        "--args")
            shift
            args=$(parse_opt "rsync args" "$1")
            vlog "command-line: rsync args: $args"
            ;;

        "--monthly")
            shift
            monthly=$(parse_opt "monthly" "$1")
            vlog "command-line: monthly: $monthly"
            ;;

        "--weekly")
            shift
            weekly=$(parse_opt "weekly" "$1")
            vlog "command-line: weekly: $weekly"
            ;;

        "--daily")
            shift
            daily=$(parse_opt "daily" "$1")
            vlog "command-line: daily: $daily"
            ;;

        *)
            if [ "${1:0:1}" = "-" ]; then
                error "unknown option: $1"
            fi
            error "what's this? -- $1"
            ;;
    esac
    shift
done

# loads config from $conf_file (also aborts on error, e.g. source not found, etc)
if [ ! -z "$conf_file" ]; then
    load_config
else
    # if we don't load config (no file specified) then just set default values (if needed)
    set_defaults
fi

flush_log

# source must exists
if [ -z "$source" ]; then
    error "source missing"
elif [[ "$source" != *":"* ]] && [ ! -d "$source" ]; then
    error "source not found: $source"
else
    source=$(ensure_slashed "$source")
    vlog "- source: $source"
fi

# make sure we should run
if [ $daily -eq 0 ] && ( [ $weekly -eq 0 ] || [ $(date +%w) -ne 1 ] ) \
    && ( [ $monthly -eq 0 ] || [ $(date +%_d) -ne 1 ] ) ; then
    error "nothing to do"
fi

# create full destination name
if [ -z "$dest_root" ]; then
    error "destination root missing"
fi
dest_root=$(ensure_slashed "$dest_root")
if [ ! -d "$dest_root" ]; then
    error "destination root not found: $dest_root"
fi
if [ -z "$dest_name" ]; then
    dest_name="$(date +$date_format)"
fi
dest=$(ensure_slashed "$dest_root$dest_name")
# destination should NOT exists
if [ -d "$dest" ]; then
    error "destination already exists: $dest"
else
    vlog "- destination: $dest"
fi

# if set, link dest should exists and be a symlink
if [ ! -z "$link_dest" ]; then
    link_dest="$dest_root$link_dest"
    link_dest=$(ensure_slashed "$link_dest")
    if [ -L "${link_dest:0:-1}" ]; then
        has_link_dest=1
        vlog "- link-dest: $link_dest"
    elif [ -e "$link_dest" ]; then
        error "link-dest must be a symlink: $link_dest"
    else
        has_link_dest=0
        vlog "link-dest ($link_dest) does not exists (yet), ignoring"
    fi
else
    vlog "no link-dest"
fi

# add log file if any
if [ -f "$log_file" ]; then
    args="--log-file=$log_file $args"
fi

# add excludes if any
if [ ! -z "$exclude_from" ]; then
    args="$args --exclude-from=$exclude_from"
fi

# add link-dest if any
if [ ! -z "$link_dest" ] && [ $has_link_dest = 1 ]; then
    args="$args --link-dest=$link_dest"
fi

# date of backup (i.e. today, used in deletion/rotation below)
d="$(date +%Y-%m-%d)"

log "-> rsync $args $source $dest"
rsync $args "$source" "$dest"
rc=$?

if [ $rc -ne 0 ]; then
    error "rsync did not completed successfully (rc=$rc)"
fi

# so the folder has the timestamp of the backup
touch "$dest"

if [ ! -z "$link_dest" ]; then
    # update symlink (link-dest) to newly created backup
    if [ ! -z "$link_dest" ] && [ $has_link_dest = 1 ]; then
        vlog "removing symlink $link_dest"
        rm "${link_dest:0:-1}"
    fi
    log "creating symlink $link_dest (points to $dest_name)"
    ln -s "$dest_name" "${link_dest:0:-1}"
fi

# now begins the whole rotation thinggy
# i.e. let's get the date of the backup to remove

if [ $daily -gt 0 ]; then
    d=$(date --date="$d -$daily days" +%Y-%m-%d)
    vlog "set previous backup to $d"
fi

if [ $weekly -gt 0 ]; then
    w=$(date --date="$d" +%w)
    if [ $w -eq 1 ]; then
        # it's a Monday, go back
        d=$(date --date="$d -$weekly weeks" +%Y-%m-%d)
        vlog "Monday: set previous backup to $d"
    fi
fi

if [ $monthly -gt 0 ]; then
    m=$(date --date="$d" +%_d)
    if [ $m -eq 1 ]; then
        # it's a 1st of the month, go back
        d=$(date --date="$d -$monthly months" +%Y-%m-%d)
        vlog "1st: set previous backup to $d"
    fi
fi

vlog "remove previous backup if exists"
delete_backup $(date --date="$d" "+$date_format")

log "done"
exit 0
