#!/bin/bash

# Copyright (C) 2011-12 Olivier Brunel
# https://bitbucket.org/jjacky/backups

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

# loads some common functions
source $(dirname $(readlink -f "${BASH_SOURCE[0]}"))"/backups.common"

if [[ "$@" = "-h" ]] || [[ "$@" = "--help" ]]; then
    me=$(basename $0)
    echo "restore -- backups v$version - little script to handle (auto) backup using rsync"
    echo ""
    echo "Syntax: $me [options] SOURCE DEST"
    echo ""
    echo "Will copy (rsync) the backup in SOURCE to DEST (must exists, should be empty)"
    echo ""
    echo "-h, --help                show this help screen and exit"
    echo "-V, --version             show version information and exit"
    echo ""
    echo "-v, --verbose             enable verbose mode"
    echo "-c, --config FILE         set FILE as configuration file"
    echo "    --args ARGS           set ARGS as arguments for rsync (do NOT include --verbose"
    echo "                          or --link-dest; they are auto-added if needed)"
    exit 0
elif [[ "$@" = "-V" ]] || [[ "$@" = "--version" ]]; then
    echo "restore -- backups v$version - little script to handle (auto) backup using rsync"
    echo "Copyright (C) 2011-12 Olivier Brunel; https://bitbucket.org/jjacky/backups"
    echo "License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>"
    echo "This is free software: you are welcome to change and redistribute it under certain conditions."
    echo "There is NO WARRANTY; see license for more."
    exit 0
fi

# the work begins...

log "restore -- backups v$version"
log "- date: $(date +%Y-%m-%d)"
log "- command-line: $@"

# let's parse the command line
while [ ! -z "$1" ]; do
    case "$1" in
        "-v"|"--verbose")
            verbose=1
            log "command-line: verbose mode enabled"
            ;;

        "-c"|"--config")
            shift
            conf_file=$(parse_opt "configuration file" "$1")
            vlog "command-line: configuration file: $conf_file"
            ;;

        "--args")
            shift
            args=$(parse_opt "rsync args" "$1")
            vlog "command-line: rsync args: $link_dest"
            ;;

        *)
            if [ "${1:0:1}" = "-" ]; then
                error "unknown option: $1"
            fi
            break
            ;;
    esac
    shift
done

# loads config from $conf_file (1 == only care for verbose/exclude-from/args; ignore everything else)
if [ ! -z "$conf_file" ]; then
    load_config 1
else
    # if we don't load config (no file specified) then just set default values (if needed)
    set_defaults
fi

if [ -z "$1" ]; then
    error "source missing"
fi
source=$(ensure_slashed "$1")
if [ ! -d "$source" ]; then
    error "source not found: $source"
fi

if [ -z "$2" ]; then
    error "destination missing"
fi
dest=$(ensure_slashed "$2")
if [ ! -d "$dest" ]; then
    error "destination not found: $dest"
fi

log "-> rsync $args $source $dest"
rsync $args "$source" "$dest"
rc=$?

if [ $rc -ne 0 ]; then
    error "rsync did not completed successfully (rc=$rc)"
fi

log "done"
exit

