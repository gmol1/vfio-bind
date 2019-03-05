#!/bin/bash
# -*- coding: utf-8 -*-
#
# =============================================================================
#
# The MIT License (MIT)
#
# Copyright (c) 2018 Kim Forsman
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

echo "Uninstalling vfio-bind..."
rm /etc/kernel/cmdline.d/20_vfio.conf
rm /etc/modprobe.d/vfio.conf
rm -rf /usr/lib/dracut/modules.d/40vfio-bind
echo $(sed '/vfio-bind/d' /etc/dracut.conf) > /etc/dracut.conf
rm /etc/dracut.conf.d/vfio.conf
echo "Regenerating initramfs..."
dracut -f --kver `uname -r` $(ls -1t /usr/lib/kernel/initrd-com.solus-project.current.* | tail -1) $(uname -r) #&>/dev/null
clr-boot-manager update
echo "Done"
echo "You must reboot to apply the changes"
