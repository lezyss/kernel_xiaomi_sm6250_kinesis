# Kinesis miatoll: build and recovery installation

The workflow `.github/workflows/build-kernel.yml` builds
`vendor/xiaomi/miatoll_defconfig` for **curtana, joyeuse, excalibur and gram**
(the unified recovery/ROM codename is **miatoll**). Do not use the generic
`defconfig`, `stock_defconfig`, or the Qualcomm reference-board defconfigs.
KernelSU manual hooks and NoMount remain enabled; the build checks this.
SuSFS v2.3.0 (backported from the `gki-android12-5.10` branch of susfs4ksu to
this 4.14 tree) is built in via `CONFIG_KSU_SUSFS` and its sub-options; see
"SuSFS on this kernel" below.
BIC and HTCP congestion control are built-in rather than their Kconfig module
defaults, so the package does not need to install additional kernel modules.

## GitHub Actions

Push a code change to `16` or the Arena working branch listed in the workflow,
or open a pull request. Once the workflow is on the default branch, you can also
select **Actions → Build miatoll kernel → Run workflow** and choose a branch.
The workflow has read-only repository permissions; it does not publish releases.

A successful run uploads:

- **Kinesis-miatoll-AnyKernel3-RUN_NUMBER**: the recovery ZIP, its SHA-256 checksum,
  and `build-info.txt` (source, compiler and installer revisions).
- **miatoll-build-diagnostics-RUN_NUMBER**: build log, resolved config and kernel
  release. Diagnostics are also uploaded on failure where available.

Artifacts expire after 30 days (diagnostics: 14 days). **Extract the downloaded
GitHub artifact first.** The inner `Kinesis-miatoll-*-AnyKernel3.zip` is the
flashable ZIP; GitHub's outer artifact archive is not flashable.

Proton Clang (including ARM32/AArch64 binutils and Polly) and upstream AnyKernel3
are fetched at full commit IDs pinned in `scripts/ci/build-kernel.sh`. The
installer's sample device names and example ramdisk patches are not shipped.
Only a successful build with nonempty images is packaged. No prebuilt kernel is
substituted on failure. There is no unsigned release/signing-key upload step.

## Local build

Use an x86_64 Ubuntu 22.04 host, with sufficient disk space and memory for a
Clang ThinLTO kernel build:

```sh
sudo apt-get update
sudo apt-get install -y bc bison build-essential ca-certificates flex git \
  libelf-dev libssl-dev libtinfo5 python3 unzip xz-utils zip
set -o pipefail
mkdir -p out
JOBS=4 scripts/ci/build-kernel.sh 2>&1 | tee out/build.log
```

The script downloads dependencies into `.cache/kernel-build/`, builds into
`out/`, and writes deliverables into `dist/`. All are ignored by Git. Run from a
clean checkout to make the recorded source commit meaningful. Remove `out/`
before changing toolchain or configuration; incremental builds reuse that
folder. The script deliberately rejects configurations with loadable modules
because this installer does not update `/vendor` modules.

## Flashing from custom recovery

**A successful compile is not a boot/ROM compatibility test.** Use an unlocked
bootloader and a miatoll-compatible custom recovery. Confirm your actual device
codename and that this kernel supports your installed ROM and firmware. The
installer's device allowlist is only a guardrail, not a compatibility guarantee.
No Android-version whitelist is asserted because this tree does not establish
one. This build includes KernelSU (root functionality) and NoMount.

1. Back up your data and **both boot and dtbo** in recovery; keep copies off the
   phone. Have your ROM's original matching boot/dtbo images and a way to
   restore them before proceeding.
2. Extract the GitHub artifact and verify the inner ZIP on a computer:
   `sha256sum -c Kinesis-miatoll-*-AnyKernel3.zip.sha256`.
3. Copy that inner ZIP to the phone (or use recovery's ADB sideload).
4. Install it in recovery and inspect the install log before rebooting.
5. If it does not boot, restore **both** backed-up partitions in recovery, or
   restore the matching original images through your device's supported
   recovery/fastboot procedure.

The ZIP replaces the kernel in **boot** using `Image.gz-dtb` and flashes the
built **dtbo.img**. AnyKernel3 preserves the existing ramdisk; it does not ship a
complete boot image, replace recovery, format data, or install userspace
KernelSU/NoMount apps. Existing root modifications are not guaranteed to coexist
with KernelSU. Standard AnyKernel3 AVB handling is used; no vbmeta partition
image is included. Never flash this ZIP on another device or assume it is safe
merely because its codename passed the check.

## SuSFS on this kernel

`drivers/kernelsu/Kconfig` (menu "KernelSU - SUSFS") carries the v2.3.0 option set:
`CONFIG_KSU_SUSFS`, `_SUS_PATH`, `_SUS_MOUNT`, `_SUS_KSTAT`, `_SPOOF_UNAME`,
`_ENABLE_LOG`, `_HIDE_KSU_SUSFS_SYMBOLS`, `_SPOOF_CMDLINE_OR_BOOTCONFIG`,
`_OPEN_REDIRECT` and `_SUS_MAP`. The miatoll defconfig enables all of them, and
`scripts/ci/build-kernel.sh` refuses to build without `CONFIG_KSU_SUSFS=y`.

Porting notes for the 4.14 target (the upstream patch targets GKI 5.10):

- `/proc/bootconfig` does not exist on 4.14, so the SPOOF_CMDLINE_OR_BOOTCONFIG
  hook spoofs `/proc/cmdline` instead (the non-GKI equivalent named by the option).
- KernelSU's sucompat for `faccessat`/`stat` is reached through SuSFS's kernel-side
  `struct filename` path only when `CONFIG_KSU_SUSFS=y`. Without SuSFS the existing
  manual hooks in `fs/open.c`, `fs/stat.c` and `kernel/reboot.c` are used unchanged.
- execve sucompat keeps the existing manual hook in `fs/exec.c` in both configurations.
  SuSFS's per-zygote-child umount marking is done from KernelSU's `task_fix_setuid`
  path (`hook/setuid_hook.c`), where the umount decision already lives.
- SuSFS's inline init.rc read/fstat hooks and its input-event hook are not used:
  KernelSU here delivers init.rc injection through the `security_file_permission`
  LSM hook and safe mode through its own input handler.
- The SELinux "fake policy" hiding (`fake_state`/`fake_status`) from the upstream
  KernelSU patch is not ported; KernelSU's own `selinux_hide` feature is unchanged.
  AVC log spoofing (`CMD_SUSFS_ENABLE_AVC_LOG_SPOOFING`) is ported.
- The SuSFS userspace (`ksu_susfs`, `ksu_module_susfs`) is not part of this tree.

Verification in this repository is compile-level only (the change was
object-compiled with and without SuSFS, and the KernelSU/NoMount objects compiled in
both configurations). Nothing here has been run on a device.
