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
    echo "running tarsnap with arguments:"
    echo "tarsnap -C /mnt/$l$x -c -f $l-$(date +%Y-%m-%d_%H-%M-%S) $c ./"
    eval tarsnap -C /mnt/$l$x -c -f $l-$(date +%Y-%m-%d_%H-%M-%S) $c ./ \
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
    test -z "$vgname" && \
        { echo "Error: you must specify a volume group name using -g" usage; exit 1; }

    test -z "$lvname" && \
        { echo "Error: you must specify a logical volume name using -l" usage; exit 1; }

    # run backup
    lvsnap_create ${vgname} ${lvname} ${lvsnap_suffix} ${lvsize} \
        || exit 1
    lvsnap_mount ${vgname} ${lvname} ${lvsnap_suffix} ${mntopt} \
        || { lvsnap_remove ${vgname} ${lvname} ${lvsnap_suffix}; exit 1; }
    backup ${lvname} ${lvsnap_suffix} ${lvexcl} \
        || { lvsnap_umount ${lvname} ${lvsnap_suffix}; lvsnap_remove ${vgname} ${lvname} ${lvsnap_suffix}; exit 1; }
    lvsnap_umount ${lvname} ${lvsnap_suffix} \
        || { sleep 10; lvsnap_umount ${lvname} ${lvsnap_suffix} || exit 1; }
    lvsnap_remove ${vgname} ${lvname} ${lvsnap_suffix} \
        || { sleep 10; lvsnap_remove ${vgname} ${lvname} ${lvsnap_suffix} || exit 1; }
    exit 0
}

main "${@}"
