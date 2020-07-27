#!/usr/bin/env bash
#
# Packer shell provisioner for Arch Linux on Raspberry Pi
#
# Based on:
#  * https://github.com/mkaczanowski/packer-builder-arm/blob/master/boards/raspberry-pi/archlinuxarm.json
#  * https://github.com/bcomnes/raspi-packer

# set -o errexit
# set -o nounset
set -o xtrace

# Initialize pacman keyring
# https://archlinuxarm.org/platforms/armv6/raspberry-pi
# https://archlinuxarm.org/platforms/armv8/broadcom/raspberry-pi-3
pacman-key --init
pacman-key --populate archlinuxarm

# Enable network connection
mv /etc/resolv.conf /etc/resolv.conf.bck
echo "nameserver 8.8.8.8" > /etc/resolv.conf

# Sync packages
pacman -Syy --noconfirm
pacman -S parted man sudo unzip inetutils jq docker --noconfirm

# Disable software rng and enable docker
systemctl disable haveged
systemctl enable docker

# Set up no-password sudo
echo '%wheel ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/wheel

# Set up localization:
# https://wiki.archlinux.org/index.php/Installation_guide#Localization
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g' /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf

# Install script to resize fs
mv /tmp/resizerootfs.service /etc/systemd/system/
chmod +x /tmp/resizerootfs
mv /tmp/resizerootfs /usr/sbin/
systemctl enable resizerootfs.service

# Set hostname
echo "${HOSTNAME}" > /etc/hostname

# Resolve hostname
cat << EOF >> /etc/hosts
127.0.0.1        localhost
::1              localhost
127.0.1.1        $HOSTNAME.localdomain        $HOSTNAME
EOF

# Disable password auth
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config

# Create user
useradd -m "${USERNAME}"
usermod -aG wheel "${USERNAME}"

# Delete default user alarm:alarm
userdel -r alarm

# Disable root login root:root
# https://wiki.archlinux.org/index.php/Sudo#Disable_root_login
passwd -l root

# Setup ssh keys
mkdir "/home/${USERNAME}/.ssh"
touch "/home/${USERNAME}/.ssh/authorized_keys"
cat << EOF > "/home/${USERNAME}/.ssh/authorized_keys"
$AUTHORIZED_KEYS
EOF

chown -R $USERNAME "/home/${USERNAME}/.ssh"
chmod 700 "/home/${USERNAME}/.ssh"
chmod 600 "/home/${USERNAME}/.ssh/authorized_keys"