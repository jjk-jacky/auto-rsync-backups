#!/bin/bash

# Copyright (C) 2011-2014 Olivier Brunel
# https://github.com/jjk-jacky/backups

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
# the config use can be set in a config file, or on command line. command-line takes precedence over config file.
# if none set, default rsync args are used. either way, some are auto-added based on other options:
# --verbose         if verbose mode is enabled
# --exclude-from    if option was specified (file must exists, else error)
# --link-dest       if option was specified unless does not exist (yet) or is a symlink
# --log-file        if option was specified
#
# if no date format is specified, default value is used.
#
# * source must be the full path
# * destination is made from dest_root (parent folder) and dest_name (folder name), the later being specified on
# command line, or generated using the given date format (cmd-line/cfg-file)
# * link-dest is the symlink's name placed in dest_root, and pointing to latest backup
#
# How it works:
# - rsync will copy source into dest (using link-dest if any)
# - symlink (link-dest) is created/updated to point to newly created backup
# - yesterday's backup is removed, unless:
#   - we are the 2nd day of the month, then last month's is removed instead
#   - we are Tuesday, then:
#       - if we are also the 2nd of the month, nothing is removed
#       - if we are also the 9th of the month, remove backup from 2 weeks ago
#       - else, remove backup from last week
#
# likely to be run as cronjob, e.g.:
# 0 3 * * * backups.sh -c /etc/backups.conf > /var/log/backups.last 2>> /var/log/backups.err

# loads some common functions
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/backups.common"

# $1		name of the folder to delete from dest_root, if exists (name calculated from date format...)
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
    echo "backups v$version - little script to handle (auto) backup using rsync"
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
    echo "    --monthly 0|1         whether to keep monthly backup (1) or not (0)"
    echo "    --weekly 0|1          whether to keep weekly backup (1) or not (0)"
    echo "    --daily NUM           set to keep NUM daily backups"
    exit 0
elif [[ "$@" = "-V" ]] || [[ "$@" = "--version" ]]; then
    echo "backups v$version - little script to handle (auto) backup using rsync"
    echo "Copyright (C) 2011-2014 Olivier Brunel; https://github.com/jjk-jacky/backups"
    echo "License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>"
    echo "This is free software: you are welcome to change and redistribute it under certain conditions."
    echo "There is NO WARRANTY; see license for more."
    exit 0
fi

# the work begins...

log "backups v$version"
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
            vlog "command-line: rsync args: $link_dest"
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

# daily must be at least 1 (to keep the backup just made!)
if [ $daily -lt 1 ]; then
    error "invalid value for daily: $daily"
fi

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

# how many days to the previous backup (to be removed) -- e.g:
# 1 = remove backup from yesterday
# 2 = remove backup from the day before
nb_prev=$daily

# by default, the previous backup is a goner
del_prev=1

# current day
day="$(date +%d)"

if [ $monthly -eq 1 ]; then
    # day when previous backup is the 1st of the month
    new_month=$((1 + $nb_prev))
    # new month
    if [ $day -eq $new_month ]; then
        # previous backup is the 1st of this month, which means:
        # - it will NOT be removed
        # - we delete backup from last month
        del_prev=0
        vlog "new month: shall remove backup from last month, if exists"
        delete_backup $(date --date="-1 month -$nb_prev day" "+$date_format")
    fi
fi

if [ $weekly -eq 1 ]; then
    # day when previous backup is the start of the week (i.e. a Monday)
    new_week=$(($nb_prev % 7 + 1))
    # new week
    if [ $(date +%w) -eq $new_week ]; then
        # previous backup is a Monday, which means:
        # - it will NOT be removed
        # - if it's also the 1st of the month, we do nothing (i.e. do NOT delete last week)
        # - if it's also the 8th of the month, we need to delete backup from 2 weeks ago
        # - else, we delete backup from last week
        del_prev=0
        del_week=1
        if [ $monthly -eq 1 ]; then
            if [ $day -eq $new_month ]; then
                del_week=0
                vlog "new week: shall remove nothing (previous backup is also this month's backup)"
            elif [ $day -eq $((8 + $nb_prev)) ]; then
                del_week=0
                vlog "new week: shall remove backup from 2 weeks ago (last week's is this month's backup), if exists"
                delete_backup $(date --date="-2 weeks -$nb_prev day" "+$date_format")
            fi
        fi
        if [ $del_week -eq 1 ]; then
            vlog "new week: shall remove last week's backup, if exists"
            delete_backup $(date --date="-1 week -$nb_prev day" "+$date_format")
        fi
    fi
fi

if [ $del_prev -eq 1 ]; then
    vlog "remove previous backup if exists"
    delete_backup $(date --date="-$nb_prev day" "+$date_format")
fi

log "done"
exit 0

