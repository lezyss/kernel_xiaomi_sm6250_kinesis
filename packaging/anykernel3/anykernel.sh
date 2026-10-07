### AnyKernel3 installer for the Xiaomi SM6250 miatoll family.
# Installer framework: osm0sis/AnyKernel3 (see the packaged LICENSE).
properties() { '
kernel.string=Kinesis for miatoll (KernelSU + NoMount)
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=miatoll
device.name2=curtana
device.name3=joyeuse
device.name4=excalibur
device.name5=gram
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; }

# These devices use a non-A/B boot partition. Preserve the installed ramdisk.
BLOCK=boot;
IS_SLOT_DEVICE=0;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

. tools/ak3-core.sh;

# Refuse an incomplete package or an unexpected partition layout before writing.
[ -s "$AKHOME/Image.gz-dtb" ] || abort "Missing kernel image";
[ -s "$AKHOME/dtbo.img" ] || abort "Missing DTBO image";
[ -b /dev/block/bootdevice/by-name/dtbo ] || \
  [ -b /dev/block/by-name/dtbo ] || abort "Cannot find the miatoll dtbo partition";

ui_print "Kinesis: back up boot and dtbo before flashing.";
ui_print "Device checks do not guarantee ROM/firmware compatibility.";

# No ramdisk modifications; flash_boot preserves it without unpack/repack.
split_boot;
flash_boot;
flash_generic dtbo;
