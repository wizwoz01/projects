# PetaLinux 2022.2 DOOM Project

This project ports DOOM to PetaLinux 2022.2 running on Zynq-7000.
- Zybo Z7-10

## Prerequisites

- Xilinx PetaLinux 2022.2 tools installed
- Vivado 2022.2
- Supported board (Zybo Z7-10, Z7-20, Zynq-7000, etc.)
- ~10GB free disk space
- Linux host machine (Ubuntu recommended)

## Installation

1. **Setup PetaLinux Environment**:

# 2. Create project 
petalinux-create -t project --template zynq --name test_01

cd test_01

# 3. Configure hardware (update XSA path)
petalinux-config --get-hw-description=<path-to/your/system.xsa>
- This file comes from Vivado includes:
- HDMI Output
  
# 4. Add DOOM package
petalinux-create -t apps --template install -n doom --enable

# 5. Enable in rootfs
echo 'CONFIG_packagegroup-petalinux-games' >> project-spec/meta-user/conf/user-rootfsconfig

echo 'CONFIG_doom' >> project-spec/meta-user/conf/user-rootfsconfig

# 6. Build everything
petalinux-build

petalinux-package --boot --fsbl --fpga --u-boot --force

# 7. Copy to SD card (replace /dev/sdX)
sudo dd if=images/linux/BOOT.BIN of=/dev/sdX bs=1M

sudo cp images/linux/image.ub /media/$USER/boot/

sync
