# Kinesis miatoll: build and recovery installation

The workflow `.github/workflows/build-kernel.yml` builds
`vendor/xiaomi/miatoll_defconfig` for **curtana, joyeuse, excalibur and gram**
(the unified recovery/ROM codename is **miatoll**). Do not use the generic
`defconfig`, `stock_defconfig`, or the Qualcomm reference-board defconfigs.
KernelSU manual hooks and NoMount remain enabled; the build checks this.

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
