#!/usr/bin/env bash
# Build on an x86_64 Linux host. See Documentation/miatoll-build.md.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$ROOT"

# Pin external inputs: updating either revision must be an intentional change.
TOOLCHAIN_REV=9fb011b183fe7e69b04b873ef6533b4b077e3c5e
ANYKERNEL_REV=020dfeccf9d7e962a48400fc94d3e451df92eead
DEFCONFIG=vendor/xiaomi/miatoll_defconfig
DEPS="$ROOT/.cache/kernel-build"
OUT="$ROOT/out"
DIST="$ROOT/dist"
JOBS=${JOBS:-$(nproc)}
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || { echo 'JOBS must be a positive integer' >&2; exit 1; }

fetch_revision() {
    local url=$1 dir=$2 revision=$3
    if [[ ! -d "$dir/.git" ]]; then
        git init "$dir"
    fi
    if ! git -C "$dir" cat-file -e "$revision^{commit}" 2>/dev/null; then
        git -C "$dir" fetch --depth=1 "$url" "$revision"
    fi
    git -C "$dir" checkout --detach --force "$revision"
    [[ $(git -C "$dir" rev-parse HEAD) == "$revision" ]]
}

mkdir -p "$DEPS" "$OUT" "$DIST"
fetch_revision https://github.com/kdrag0n/proton-clang.git "$DEPS/proton-clang" "$TOOLCHAIN_REV"
fetch_revision https://github.com/osm0sis/AnyKernel3.git "$DEPS/AnyKernel3" "$ANYKERNEL_REV"
export PATH="$DEPS/proton-clang/bin:$PATH"
export KBUILD_BUILD_USER=builder KBUILD_BUILD_HOST=github-actions
export KBUILD_BUILD_TIMESTAMP="$(git show -s --format=%cD HEAD)"
export KBUILD_BUILD_VERSION=1

make_args=(
    O="$OUT" ARCH=arm64
    CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm
    OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip
    CLANG_TRIPLE=aarch64-linux-gnu-
    CROSS_COMPILE=aarch64-linux-gnu-
    CROSS_COMPILE_ARM32=arm-linux-gnueabi-
)
clang --version
make "${make_args[@]}" "$DEFCONFIG"

# Do not silently ship a build without the existing root/NoMount integration.
for option in CONFIG_ARCH_ATOLL CONFIG_BUILD_ARM64_DT_OVERLAY CONFIG_KSU CONFIG_NOMOUNT; do
    grep -qx "${option}=y" "$OUT/.config" || {
        echo "Required option ${option}=y is missing from the resolved config" >&2
        exit 1
    }
done
grep -qx '# CONFIG_KSU_TAMPER_SYSCALL_TABLE is not set' "$OUT/.config"
# The installer intentionally does not replace vendor modules.
if grep -q '=m$' "$OUT/.config"; then
    echo 'Loadable modules enabled: add a module installation strategy before packaging.' >&2
    grep '=m$' "$OUT/.config" >&2
    exit 1
fi

make -j"$JOBS" "${make_args[@]}" Image.gz-dtb dtbo.img
for image in Image.gz-dtb dtbo.img; do
    test -s "$OUT/arch/arm64/boot/$image"
done
# Ensure the appended image really contains a DTB, not only a gzip stream.
test "$(stat -c %s "$OUT/arch/arm64/boot/Image.gz-dtb")" -gt \
     "$(stat -c %s "$OUT/arch/arm64/boot/Image.gz")"

stage=$(mktemp -d "$DEPS/package.XXXXXXXX")
trap 'rm -rf -- "$stage"' EXIT
# Export only installer runtime files, not the upstream example ramdisk patches.
git -C "$DEPS/AnyKernel3" archive "$ANYKERNEL_REV" META-INF tools LICENSE | tar -x -C "$stage"
cp packaging/anykernel3/anykernel.sh "$stage/anykernel.sh"
cp "$OUT/arch/arm64/boot/"{Image.gz-dtb,dtbo.img} "$stage/"
chmod 755 "$stage/anykernel.sh" "$stage/META-INF/com/google/android/update-binary"

commit=$(git rev-parse HEAD)
name="Kinesis-miatoll-${commit:0:12}-AnyKernel3"
{
    echo "Kernel source: $commit"
    echo "Defconfig: $DEFCONFIG"
    echo "Kernel release: $(cat "$OUT/include/config/kernel.release")"
    echo "Proton Clang: $TOOLCHAIN_REV"
    clang --version | head -n 1
    echo "AnyKernel3: $ANYKERNEL_REV"
    echo "Config SHA256: $(sha256sum "$OUT/.config" | cut -d ' ' -f 1)"
    echo 'Devices: miatoll, curtana, joyeuse, excalibur, gram'
    echo 'Payload: Image.gz-dtb, dtbo.img; replaces boot kernel and dtbo'
    echo 'Not device-tested. Back up boot and dtbo before flashing.'
} > "$stage/build-info.txt"
cp "$stage/build-info.txt" "$DIST/build-info.txt"
rm -f -- "$DIST/$name.zip"
(cd "$stage" && zip -q -r -9 "$DIST/$name.zip" .)
unzip -t "$DIST/$name.zip"
(cd "$DIST" && sha256sum "$name.zip" > "$name.zip.sha256")
echo "Flashable ZIP: $DIST/$name.zip"
if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
    {
        echo '## miatoll kernel built'
        echo "Download the **Kinesis-miatoll-AnyKernel3** artifact, extract it, and flash \`$name.zip\` (not the outer artifact ZIP)."
        echo
        echo 'Back up **boot and dtbo** first. This is a compile-tested build, not a device-tested build; ROM/firmware compatibility must be checked.'
        echo
        echo '```text'
        cat "$DIST/build-info.txt" "$DIST/$name.zip.sha256"
        echo '```'
    } >> "$GITHUB_STEP_SUMMARY"
fi
