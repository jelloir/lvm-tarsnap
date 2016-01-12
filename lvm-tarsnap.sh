#!/bin/sh

vgname="$1"; shift
lvname="$1"; shift
lvsize="$1"; shift
lvexcl="$1"; shift
mntopt="ro"
lvsnap_suffix="-snapshot"

lvsnap_create()
# create lvm snapshot
{
    local v=$1; shift # $1 volume group (v)
    local l=$1; shift # $2 logical volume (l)
    local x=$1; shift # $3 lv snapshot suffix (x)
    local z=$1; shift # $4 lv size in % (z)
    lvcreate -s -l +$z%FREE -n $l$x $v/$l && return 0 || return 1
}

lvsnap_remove()
# remove lvm snapshot
{
    local v=$1; shift # $1 volume group (v)
    local l=$1; shift # $2 logical volume (l)
    local x=$1; shift # $3 lv snapshot suffix (x)
    lvremove --force $v/$l$x && return 0 || return 1
}

lvsnap_mount()
# mount lvm snapshot
{
    local v=$1; shift # $1 volume group (v)
    local l=$1; shift # $2 logical volume (l)
    local x=$1; shift # $3 lv snapshot suffix (x)
    local m=$1; shift # $4 mount options (m)
    test -d /mnt/$l$x || mkdir -p /mnt/$l$x
    mount -o $m /dev/$v/$l$x /mnt/$l$x && return 0 || return 1
}

lvsnap_umount()
# un-mount lvm snapshot
{
    local l=$1; shift # $2 logical volume (l)
    local x=$1; shift # $2 lv snapshot suffix (x)
    umount /mnt/$l$x && return 0 || return 1
}

backup()
# run tarsnap backup
{
    local l=$1; shift # $1 logical volume (l)
    local x=$1; shift # $2 lv snapshot suffix (x)
    local c="$(IFS=, ; for e in $1 ; do printf "%s" "--exclude=\"$e\" " ; done)"; shift # $3 exclusions
    eval tarsnap -C /mnt/$l$x -c -f $l-`date +%Y-%m-%d_%H-%M-%S` $c ./ \
    && return 0 || return 1
}

error()
# report errors
{
    local f=$1; shift
    return "error in step $f"
}

main()
{
    lvsnap_create ${vgname} ${lvname} ${lvsnap_suffix} ${lvsize}
    lvsnap_mount ${vgname} ${lvname} ${lvsnap_suffix} ${mntopt}
    backup ${lvname} ${lvsnap_suffix} ${lvexcl}
    lvsnap_umount ${lvname} ${lvsnap_suffix}
    lvsnap_remove ${vgname} ${lvname} ${lvsnap_suffix}
}

main "${@}"
