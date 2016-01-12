#!/bin/sh

vgname="$1"; shift
lvname="$1"; shift
lvsize="$1"; shift
lvexcl="$1"; shift
mntopt="ro"
lvsnap_suffix="-snapshot"

lvsnap_create()
# create lvm snapshot
# $1 = volume group (v)
# $2 = logical volume (l)
# $3 = lv snapshot suffix (x)
# $4 = lv size in % (z)
{
    local v=$1; shift
    local l=$1; shift
    local x=$1; shift
    local z=$1; shift
    lvcreate -s -l +$z%FREE -n $l$x $v/$l && return 0 || return 1
}

lvsnap_remove()
# remove lvm snapshot
# $1 = volume group (v)
# $2 = logical volume (l)
# $3 = lv snapshot suffix (x)
{
    local v=$1; shift
    local l=$1; shift
    local x=$1; shift
    lvremove --force $v/$l$x && return 0 || return 1
}

lvsnap_mount()
# mount lvm snapshot
# $1 = volume group (v)
# $2 = logical volume (l)
# $3 = lv snapshot suffix (x)
# $4 = mount options (m)
{
    local v=$1; shift
    local l=$1; shift
    local x=$1; shift
    local m=$1; shift
    test -d /mnt/$l$x || mkdir -p /mnt/$l$x
    mount -o $m /dev/$v/$l$x /mnt/$l$x && return 0 || return 1
}

lvsnap_umount()
# un-mount lvm snapshot
# $1 = logical volume (l)
# $2 = lv snapshot suffix (x)
{
    local l=$1; shift
    local x=$1; shift
    umount /mnt/$l$x && return 0 || return 1
}

backup()
# run tarsnap backup
# $1 = logical volume (l)
# $2 = lv snapshot suffix (x)
# $3 = exclusions
{
    local l=$1; shift
    local x=$1; shift
    local c="$(IFS=, ; for e in $1 ; do printf "%s" "--exclude=\"$e\" " ; done)"; shift
    eval tarsnap -C /mnt/$l$x -c -f $l-`date +%Y-%m-%d_%H-%M-%S` $c ./
    # need to integrade return functions
}

error()
# report errors
{
    local f=$1; shift
    retur
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
