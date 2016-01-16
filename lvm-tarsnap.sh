#!/bin/bash

vgname=""
lvname=""
lvsize="100%"
lvexcl=""
lvsnap_suffix="-snapshot"
mntopt="ro"
readonly script_name=$(basename $0)

log()
# log info
{
    echo "$@"
    logger -p user.notice -t $script_name "$@"
}

err()
# log errors
{
    echo "$@" >&2
    logger -p user.error -t $script_name "$@"
}

lvsnap_create()
# create lvm snapshot
{
    local v=$1; shift # $1 volume group (v)
    local l=$1; shift # $2 logical volume (l)
    local x=$1; shift # $3 lv snapshot suffix (x)
    local z=$1; shift # $4 lv size in % (z)
    lvcreate -s -l +"$z"FREE -n $l$x $v/$l \
        && { log "$l$x created ($z)"; return 0; } \
        || { err "$l$x create failed"; return 1; }
}

lvsnap_remove()
# remove lvm snapshot
{
    local v=$1; shift # $1 volume group (v)
    local l=$1; shift # $2 logical volume (l)
    local x=$1; shift # $3 lv snapshot suffix (x)
    lvremove --force $v/$l$x \
        && { log "$l$x removed"; return 0; } \
        || { err "$l$x remove failed"; return 1; }
}

lvsnap_mount()
# mount lvm snapshot
{
    local v=$1; shift # $1 volume group (v)
    local l=$1; shift # $2 logical volume (l)
    local x=$1; shift # $3 lv snapshot suffix (x)
    local m=$1; shift # $4 mount options (m)
    test -d /mnt/$l$x || mkdir -p /mnt/$l$x
    mount -o $m /dev/$v/$l$x /mnt/$l$x \
        && { log "$l$x mounted $m"; return 0; } \
        || { err "$l$x mount failed"; return 1; }
}

lvsnap_umount()
# un-mount lvm snapshot
{
    local l=$1; shift # $2 logical volume (l)
    local x=$1; shift # $2 lv snapshot suffix (x)
    umount /mnt/$l$x \
        && { log "$l$x un-mounted"; return 0; } \
        || { err "$l$x un-mount failed"; return 1; }
}

backup()
# run tarsnap backup
{
    local l=$1; shift # $1 logical volume (l)
    local x=$1; shift # $2 lv snapshot suffix (x)
    local c="$(IFS=,; for e in $1; do printf "%s" "--exclude=\"$e\" "; done)"; shift # $3 exclusions
    local tc="tarsnap -C /mnt/$l$x -c -f $l-$(date +%Y-%m-%d_%H-%M-%S) $c ./"
    log "tarsnap command: $tc"
    eval $tc \
        && { log "$l$x backed up"; return 0; } \
        || { err "$l$x backup failed"; return 1; }
}

usage()
# print usage and exit
{
    cat << EOT
Usage: lvm-tarsnap.sh [OPTION]...

    -g  Volume Group name (required)
    -l  Logical Volume name (required)
    -s  Snapshot size in percent (optional - default 100%) 
    -e  Comma separated list of exclusions (optional - e.g. "my folder,file")
    -x  Snapshot suffix (optional - default "-snapshot")
    -m  Snapshot mount options (optional - default "ro")
    -h  Print this help

EOT
    exit 1;
}

lock()
{
    local l=$1; shift # $1 logical volume (l)
    local f=$1; shift # $2 add or remove lock (f)
    if test $f = add; then
        touch /run/"$script_name"_$l.lock
    fi
    if test $f = rmv; then
        rm /run/"$script_name"_$l.lock
    fi
}

main()
{
    # command line arguments
    while getopts "g:l:s:e:x:m:h" o; do
        case "$o" in
            g)  vgname="$OPTARG" ;;
            l)  lvname="$OPTARG" ;;
            s)  lvsize="$OPTARG" ;;
            e)  lvexcl="$OPTARG" ;;
            x)  lvsnap_suffix="$OPTARG" ;;
            m)  mntopt="$OPTARG" ;;
            h)  usage ;;
            :)  echo "Option -$OPTARG requires an argument."; exit 1 ;;
            *)  usage ;;
        esac
    done

    # ensure required arguments
    if test -z "$vgname"; then
        echo "Error: you must specify a volume group name using -g"
        usage
        exit 1
    fi

    if test -z "$lvname"; then
        echo "Error: you must specify a logical volume name using -l"
        usage
        exit 1
    fi

    # check for existing job
    # integrate this into lock function use case statement
    # lock $lvname chk
    if test -e /run/"$script_name"_$lvname.lock; then
        err "Lock file /run/"$script_name"_$lvname.lock exists"
        exit 1
    fi

    # create lock file
    lock $lvname add

    # run backup
    if ! lvsnap_create $vgname $lvname $lvsnap_suffix $lvsize; then
        lock $lvname rmv
        exit 1
    fi
    if ! lvsnap_mount $vgname $lvname $lvsnap_suffix $mntopt; then
        lvsnap_remove $vgname $lvname $lvsnap_suffix
        lock $lvname rmv
        exit 1
    fi
    if ! backup $lvname $lvsnap_suffix $lvexcl; then
        lvsnap_umount $lvname $lvsnap_suffix
        lvsnap_remove $vgname $lvname $lvsnap_suffix
        lock $lvname rmv
        exit 1
    fi
    if ! lvsnap_umount $lvname $lvsnap_suffix; then
        sleep 10
        lvsnap_umount $lvname $lvsnap_suffix || { lock $lvname rmv; exit 1; }
    fi
    if ! lvsnap_remove $vgname $lvname $lvsnap_suffix; then
        sleep 10
        lvsnap_remove $vgname $lvname $lvsnap_suffix || { lock $lvname rmv; exit 1; }
    fi

    # remove lock file
    lock $lvname rmv

    exit 0
}

main "${@}"
