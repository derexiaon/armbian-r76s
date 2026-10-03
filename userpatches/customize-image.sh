#!/bin/bash
# Выполняется в chroot собираемого образа (armbian/build: customize_image).
# Аргументы: $1=RELEASE $2=LINUXFAMILY $3=BOARD $4=BUILD_DESKTOP $5=ARCH
# userpatches/overlay смонтирован в /tmp/overlay.

set -e

# Необязательный публичный SSH-ключ для root (вход ssh_pubkey workflow).
if [[ -s /tmp/overlay/root_authorized_keys ]]; then
	echo "customize-image: installing SSH public key for root"
	install -d -m 700 /root/.ssh
	install -m 600 /tmp/overlay/root_authorized_keys /root/.ssh/authorized_keys
fi
