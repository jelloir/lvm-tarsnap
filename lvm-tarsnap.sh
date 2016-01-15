#!/bin/bash

vgname="$1"; shift
lvname="$1"; shift
lvsize="$1"; shift
lvexcl="$1"; shift
mntopt="ro"
lvsnap_suffix="-snapshot"

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
    lvcreate -s -l +$z%FREE -n $l$x $v/$l \
        && { log "${l}${x} created"; return 0; } \
        || { err "${l}${x} create failed"; return 1; }
}

lvsnap_remove()
# remove lvm snapshot
{
    local v=$1; shift # $1 volume group (v)
    local l=$1; shift # $2 logical volume (l)
    local x=$1; shift # $3 lv snapshot suffix (x)
    lvremove --force $v/$l$x \
        && { log "${l}${x} removed"; return 0; } \
        || { err "${l}${x} remove failed"; return 1; }
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
        && { log "${l}${x} mounted"; return 0; } \
        || { err "${l}${x} mount failed"; return 1; }
}

lvsnap_umount()
# un-mount lvm snapshot
{
    local l=$1; shift # $2 logical volume (l)
    local x=$1; shift # $2 lv snapshot suffix (x)
    umount /mnt/$l$x \
        && { log "${l}${x} un-mounted"; return 0; } \
        || { err "${l}${x} un-mount failed"; return 1; }
}

backup()
# run tarsnap backup
{
    local l=$1; shift # $1 logical volume (l)
    local x=$1; shift # $2 lv snapshot suffix (x)
    local c="$(IFS=,; for e in $1; do printf "%s" "--exclude=\"$e\" "; done)"; shift # $3 exclusions
    eval tarsnap -C /mnt/$l$x -c -f $l-$(date +%Y-%m-%d_%H-%M-%S) $c ./ \
        && { log "${l}${x} backed up"; return 0; } \
        || { err "${l}${x} backup failed"; return 1; }
}

main()
{
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
