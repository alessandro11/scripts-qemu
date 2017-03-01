#!/usr/bin/env bash


PREFIX_SPICE_SOCKET_DIR=/tmp
CONFIG_DIR=./configs

# TODO:
#		make help with all available options (default variables).
if [ $# -lt 1 ]; then
    echo "Wrong number of parameters, pass one config from '$CONFIG_DIR'."
	echo "export OPEN_VNC="
	echo -e "\tforce to vnc for the virtual."
    exit 1
fi

if [ ! -f "$CONFIG_DIR/$1" ]; then
	echo "Error config file '$CONFIG_DIR/$1' no such a file."
	exit 1
fi

source $CONFIG_DIR/$1

# TODO
#   Make default value for all variables.
VM_DISK_IF=${VM_DISK_IF:-virtio}
VM_NIC_MODEL=${VM_NIC_MODEL:-virtio}

VM_CORES=${VM_CORES:-1}

#
# Extra parameters to qemu
#
EXTRA_PARAM=${EXTRA_PARAM:-""}
# Parse if has been declared a kernel.
if [ -n "$VM_KERNEL" ]; then
    EXTRA_PARAM="$EXTRA_PARAM -kernel $VM_KERNEL"

	# Parse if has been declared a kernel.
	if [ -n "$VM_INITRD" ]; then
		EXTRA_PARAM="$EXTRA_PARAM -initrd $VM_INITRD"
	fi

	# Still it is not a elegant way do solve the problem
	# the problems is VM_KERNEL_CMDLINE is expanding twice
	# once in read QEMU_PARAM and another in running qemu,
	# so when there are two or parameters they are break
	# as two or more parameters.
    #if [ -n "$VM_KERNEL_CMDLINE" ]; then
    #    EXTRA_PARAM="$EXTRA_PARAM -append \$VM_KERNEL_CMDLINE"
    #fi
fi

# qemu executable
QEMU_BIN=$(which qemu-system-x86_64)
QEMU_PID=""

help() {
    echo -e $"\nUsage: `basename $0`\n \
        \tp|P PID QEMU,VNC \
        \tq|q exit\n \
        \tr|R reboot\n \
        \tv|V vnc [display]\n\n"
}

run_virt() {
    echo -n "`basename $QEMU_BIN` "
	# Do not quuote, to not preserve tabs and spaces,
	# so we can copy and paste qemu command line.
	echo $QEMU_PARAM

	# this if is a workaround that is agly.
	if [ -z "$VM_KERNEL_CMDLINE" ]; then
		$QEMU_BIN $QEMU_PARAM &
	else
		$QEMU_BIN $QEMU_PARAM -append "'$VM_KERNEL_CMDLINE'" &
	fi
    QEMU_PID=$!
    
	sleep 1
    ip link set dev "$VM_GUEST_IFNAME1" up || exit 1
	ip link set "$VM_GUEST_IFNAME1" master "$HOST_BRD" || exit 1
    
	if [ "${OPEN_VNC}x" == "spicex" ]; then
		spicy --uri="spice+unix:///${PREFIX_SPICE_SOCKET_DIR}/${SPICE_SOCKET}"
	elif [ "${OPEN_VNC}x" != "x" ]; then
	   gvncviewer "localhost:$OPEN_VNC" &> /dev/null&
	fi
}

finish() {
    [[ -n "$VNC_PID" ]] && kill "$VNC_PID"
    [[ -n "$QEMU_PID" ]] && kill "$QEMU_PID"
    exit 0
}

case "$VM_BOOT" in
	'windows')
		export QEMU_AUDIO_DRV=alsa
		SPICE_SOCKET="vm_spice_${VM_NAME}.socket"
		read -d '' QEMU_PARAM <<EOF
			-name $VM_NAME
			-m $VM_RAM
			-balloon virtio
			-enable-kvm
			-cpu host
			-smp cores=$VM_CORES,threads=$VM_SMP
			-rtc base=localtime,clock=host
			-boot c
			-drive file=$VM_DISK,index=0,if=$VM_DISK_IF,format=$VM_DISK_FMT,cache=writeback,cache.direct=on,aio=native
			-net nic,macaddr=$VM_MAC1,vlan=$VM_VLAN1,model=$VM_NIC_MODEL
			-net tap,vlan=$VM_VLAN1,ifname=$VM_GUEST_IFNAME1,script=no,downscript=no
			-spice unix,addr=${PREFIX_SPICE_SOCKET_DIR}/${SPICE_SOCKET},disable-ticketing
			-vga none
			-device qxl-vga,vgamem_mb=32
			-device virtio-serial-pci
			-device virtserialport,chardev=spicechannel0,name=com.redhat.spice.0
			-chardev spicevmc,id=spicechannel0,name=vdagent
			-usbdevice tablet
			-soundhw ac97
			$EXTRA_PARAM
EOF
	;;
	'n')
		read -d '' QEMU_PARAM <<EOF
			-name $VM_NAME
			-m $VM_RAM
			-cpu host
			-smp $VM_SMP
			-enable-kvm
			-localtime
			-k pt-br
			-boot order=nc
			-net nic,macaddr=$VM_MAC1,vlan=$VM_VLAN1,model=$VM_NIC_MODEL
			-net tap,vlan=$VM_VLAN1,ifname=$VM_GUEST_IFNAME1,script=no,downscript=no
			-vga std
			-vnc :$VNC_DISPLAY
			$EXTRA_PARAM
EOF
	;;

	'd')
		read -d '' QEMU_PARAM <<EOF
			-name $VM_NAME
			-m $VM_RAM
			-cpu host
			-smp $VM_SMP
			-enable-kvm
			-localtime
			-k pt-br
			-net nic,macaddr=$VM_MAC1,vlan=$VM_VLAN1,model=$VM_NIC_MODEL
			-net tap,vlan=$VM_VLAN1,ifname=$VM_GUEST_IFNAME1,script=no,downscript=no
			-cdrom $VM_ISO
			-boot d
			-vga std
			-vnc :$VNC_DISPLAY
			$EXTRA_PARAM
EOF
	;;

    'custom')
		read -d '' QEMU_PARAM <<EOF
			-name $VM_NAME
			-m $VM_RAM
			-cpu host
			-smp $VM_SMP
			-enable-kvm
			-localtime
			-k pt-br
			-boot menu=on
			-net nic,macaddr=$VM_MAC1,vlan=$VM_VLAN1,model=$VM_NIC_MODEL
			-net tap,vlan=$VM_VLAN1,ifname=$VM_GUEST_IFNAME1,script=no,downscript=no
			-vga std
			-vnc :$VNC_DISPLAY
			$EXTRA_PARAM
EOF
	;;

	*)
		SPICE_SOCKET="vm_spice_$VM_NAME.socket"
		read -d '' QEMU_PARAM <<EOF
			-name $VM_NAME
			-enable-kvm
			-cpu host
			-smp cores=$VM_CORES,threads=$VM_SMP
			-m $VM_RAM
			-rtc base=localtime,clock=host
			-drive file=$VM_DISK,if=$VM_DISK_IF,format=$VM_DISK_FMT,cache=writeback,cache.direct=on,aio=native
			-spice unix,addr=${PREFIX_SPICE_SOCKET_DIR}/${SPICE_SOCKET},disable-ticketing
			-net nic,macaddr=$VM_MAC1,vlan=$VM_VLAN1,model=$VM_NIC_MODEL
			-net tap,vlan=$VM_VLAN1,ifname=$VM_GUEST_IFNAME1,script=no,downscript=no
			-vga cirrus
			-vnc :$VNC_DISPLAY
			$EXTRA_PARAM
EOF
		;;
esac

trap "finish" EXIT INT
run_virt

set INPUT=""
set PARAM=""
set VNC_PID=""
while :; do
    help
    read -p '> ' INPUT PARAM
    case $INPUT in
        'h')
            ;;
        'p'|'P')
            echo "$QEMU_PID, $VNC_PID"
            ;;
        'r'|'R')
            [[ -n "$QEMU_PID" ]] && kill "$QEMU_PID"
			run_virt
            ;;
        'q'|'Q')
			finish
            exit 0
            ;;
        'v'|'V')
			if [ -n "$SPICE_SOCKET" ]; then
				spicy --uri="spice+unix:///${PREFIX_SPICE_SOCKET_DIR}/${SPICE_SOCKET}"
			else
				PARAM=${PARAM:-$VNC_DISPLAY}
				[[ -n "$VNC_PID" ]] && kill "$VNC_PID"
				gvncviewer "localhost:$PARAM" &> /dev/null&
				VNC_PID=$!
			fi
            ;;
        *)
            echo -n "Command not found!"
            ;;
    esac
done

