# 查看硬盘分区情况
lsblk

# 创建挂载路径
mkdir -p /mnt/usb

# 挂载 USB 并复制文件
# 如果是 NTFS 格式
apt-get install ntfs-3g
ntfs-3g /dev/sdb1 /mnt/usb

# 如果是 FAT32 / exFAT / ext4 格式
mount /dev/sdX1 /mnt/usb

# 查看挂载情况
cd /mnt/usb
ls -lh

# 存放 ISO 镜像，复制到：/var/lib/vz/template/iso/
cp /mnt/usb/your_iso_image.iso /var/lib/vz/template/iso/

# 存放 CT 模板，复制到：/var/lib/vz/template/cache/
cp /mnt/usb/your_ct_template.tar.gz /var/lib/vz/template/cache/

# 卸载 USB
cd /
umount /mnt/usb

