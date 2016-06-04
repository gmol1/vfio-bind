#!/bin/bash
# -*- coding: utf-8 -*-
#
# =============================================================================
#
# The MIT License (MIT)
#
# Copyright (c) 2016 Guillermo Molina
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

if [ "$EUID" -ne 0 ]; then
	echo "This script must be run as root"
	exit 1
fi

if [[ $(lspci -D | grep VGA | awk '{print $1}') ]]; then
	for i in $(lspci -D | grep VGA | awk '{print $1}') ; do
		d_id+=( "$(lspci -D | grep $i)" )
	done

	echo "Select the target device:"
	PS3="Device: "
	select opt in "${d_id[@]}"; do
		if [[ ! -d "/sys/bus/pci/devices/$(echo $opt | awk '{print $1}')/iommu/" ]]; then
			if [[ $(lscpu | grep "Vendor ID:" | awk '{print $3}') == "AuthenticAMD" ]]; then 
				if [[ $(dmesg| grep -o 'AMD-Vi: Found IOMMU') ]]; then
					echo -e "\e[31mIOMMU is enabled but it isn't working correctly, check your hardware"
					exit 1
				fi			
			elif [[ $(lscpu | grep "Vendor ID:" | awk '{print $3}') == "GenuineIntel" ]]; then
				if [[ ! $(cat /etc/default/grub | sed -n -e 's/GRUB_CMDLINE_LINUX_DEFAULT//p' | sed -e 's/=//;s/"//g' | grep -o 'intel_iommu=on') ]]; then
					echo "IOMMU isn't enabled in the Kernel, would you like to enable it?"
					PS3="Option: "
					options=("Yes" "No")
					select opt in "${options[@]}"
					do
					    case $opt in
					    	"Yes")
								grub="/etc/default/grub"
								if [[ ! -a $grub ]]; then
									echo -e "\e[31mUnable to open $grub, exiting now"
									exit 1
								fi
								echo "Updating GRUB..."
					    		cp $grub $grub.bk
					    		a=$(sed -n '/GRUB_CMDLINE_LINUX_DEFAULT/=' $grub)
								b=$(sed -n "$a p" $grub | sed 's/"$/ intel_iommu=on\"/')
								c=$(sed -i "$a s/.*/$b/" $grub)
								update-grub &>/dev/null
								echo "Done"
								echo "You must reboot to apply the changes"
								exit
					            ;;
					        "No")
					            echo -e "\e[31mIOMMU must be enabled in the kernel before continuing, exiting now"
					            exit
					            ;;
					        *) echo Invalid option;;
					    esac
					done
				elif [[ $(dmesg | grep -o 'Intel-IOMMU: enabled') || $(dmesg | grep -o 'DMAR: IOMMU enabled') ]]; then
					echo -e "\e[31mIOMMU is enabled but isn't working correctly, check your hardware"
					exit 1
				fi
			else
				echo -e "\e[31mCheck your hardware"
				exit 1
			fi
		fi
	
		for i in $(ls /sys/bus/pci/devices/$(echo $opt | awk '{print $1}')/iommu_group/devices/); do
			if [[ "$i" == "$(echo $opt | awk '{print $1}')" || "$i" == "$(echo $opt | awk '{print $1}' | sed 's/0$/1/')" ]]; then
				device+=( "$i" )
			else
				uw_device+=( "$i" )
			fi
		done

		if [[ $uw_device ]]; then
			echo "The IOMMU group isn't properly isolated, the following devices shouldn't be in the group:"
			for i in "${uw_device[@]}"; do
				echo $i
			done
			echo "Switching the graphics card from PCIe slot is recommended"
			echo "Would you like to bind the device anyway?"
			PS3="Option: "
				options=("Yes" "No")
				select opt in "${options[@]}"
				do
				    case $opt in
				    	"Yes")
				    	break
				            ;;
				        "No")
				            exit
				            ;;
				        *) echo Invalid option;;
				    esac
				done
		fi

		dir="/usr/lib/dracut/modules.d/40vfio-bind"
		if [[ -d $dir ]]; then
			rm -rf $dir
		fi
		mkdir $dir
		module_setup=( "#!/bin/bash" \
		"# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-" \
		"# ex: ts=8 sw=4 sts=4 et filetype=sh" \
		"check() {" "return 0" "}" "depends() {" "return 0" "}" \
		"install() {" "inst_hook pre-trigger 91 \"\$moddir/vfio-bind.sh\"" "}" \
		"installkernel() {" "instmods vfio vfio_iommu_type1 vfio_pci vfio_virqfd" "}" )
		echo > $dir/module-setup.sh
		for i in "${module_setup[@]}"; do
			echo $i >> $dir/module-setup.sh
		done
		echo > $dir/vfio-bind.sh
		echo "#!/bin/bash" >> $dir/vfio-bind.sh
		for i in "${device[@]}"; do
			echo "echo \"vfio-pci\" > $(ls /sys/bus/pci/devices/$i/driver_override)" >> $dir/vfio-bind.sh
		done
		echo "modprobe -i vfio-pci" >> $dir/vfio-bind.sh
		trap "" INT
		echo "Regenerating initramfs..."
		dracut -f --kver `uname -r` &>/dev/null
		echo "Done"
		echo "You must reboot to apply the changes"
		echo -e "After reboot you can check if the device is binded to vfio-pci by running \e[1m\"lspci -ks $device\""
		exit
done
else
	echo -e "\e[31mNo graphics card found"
	exit 1
fi