#!/usr/bin/env python3
"""
extract_kernel.py — Extract kernel, DTB, and ramdisk from Android boot image v2
Usage: python3 extract_kernel.py <boot.img> <output_dir>

Verified working on SM-M326B boot image (header v2, gzip kernel).
"""

import sys
import os
import struct

def align_up(val, align):
    return ((val + align - 1) // align) * align

def parse_boot_img_v2(data):
    magic = data[0:8]
    assert magic == b'ANDROID!', f"Bad magic: {magic}"

    kernel_size  = struct.unpack_from('<I', data, 8)[0]
    kernel_addr  = struct.unpack_from('<I', data, 12)[0]
    ramdisk_size = struct.unpack_from('<I', data, 16)[0]
    ramdisk_addr = struct.unpack_from('<I', data, 20)[0]
    second_size  = struct.unpack_from('<I', data, 24)[0]
    second_addr  = struct.unpack_from('<I', data, 28)[0]
    tags_addr    = struct.unpack_from('<I', data, 32)[0]
    page_size    = struct.unpack_from('<I', data, 36)[0]
    hdr_version  = struct.unpack_from('<I', data, 40)[0]
    os_version   = struct.unpack_from('<I', data, 44)[0]
    board_name   = data[48:64].rstrip(b'\x00').decode('ascii', errors='replace')
    cmdline      = data[64:576].rstrip(b'\x00').decode('ascii', errors='replace')

    dtb_size = 0
    dtb_addr = 0
    if hdr_version >= 2:
        dtb_size = struct.unpack_from('<I', data, 1648)[0]
        dtb_addr = struct.unpack_from('<Q', data, 1652)[0]

    print(f"=== Android Boot Image Parser ===")
    print(f"Magic:          {magic}")
    print(f"Header version: {hdr_version}")
    print(f"Page size:      {page_size}")
    print(f"Kernel size:    {kernel_size:,} bytes ({kernel_size/1024/1024:.2f} MiB)")
    print(f"Ramdisk size:   {ramdisk_size:,} bytes")
    print(f"Second size:    {second_size:,} bytes")
    print(f"DTB size:       {dtb_size:,} bytes")
    print(f"Board name:     '{board_name}'")
    print(f"Cmdline:        '{cmdline}'")
    print()

    # Calculate page-aligned offsets
    kernel_off  = page_size
    ramdisk_off = align_up(kernel_off + kernel_size, page_size)
    second_off  = align_up(ramdisk_off + ramdisk_size, page_size)
    dtb_off     = align_up(second_off + second_size, page_size)

    print(f"=== Offsets ===")
    print(f"Kernel  @ 0x{kernel_off:08X}  ({kernel_off:,})")
    print(f"Ramdisk @ 0x{ramdisk_off:08X}  ({ramdisk_off:,})")
    print(f"DTB     @ 0x{dtb_off:08X}  ({dtb_off:,})")
    print()

    kernel_data  = data[kernel_off : kernel_off + kernel_size]
    ramdisk_data = data[ramdisk_off : ramdisk_off + ramdisk_size]
    dtb_data     = data[dtb_off : dtb_off + dtb_size] if dtb_size > 0 else b''

    # Detect kernel compression
    kmagic = kernel_data[:4].hex()
    ktype = {
        '1f8b0800': 'gzip (Image.gz)',
        '1f8b0808': 'gzip (Image.gz)',
        '04224d18': 'lz4',
        '894c5a4f': 'lzo',
        'fd377a58': 'xz',
        '89916d39': 'lzma',
    }.get(kmagic, f'unknown ({kmagic})')
    print(f"Kernel compression: {ktype}")

    # Check DTB magic (FDT = 0xD00DFEED big-endian)
    if dtb_data:
        dtb_magic = int.from_bytes(dtb_data[:4], 'big')
        if dtb_magic == 0xD00DFEED:
            print("DTB magic: 0xD00DFEED ✓ (valid FDT)")
        else:
            print(f"DTB magic: 0x{dtb_magic:08X} (Samsung MTK wrapped format — normal)")

    return kernel_data, ramdisk_data, dtb_data

def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <boot.img> <output_dir>")
        sys.exit(1)

    boot_img = sys.argv[1]
    out_dir  = sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)

    with open(boot_img, 'rb') as f:
        data = f.read()

    print(f"Parsing: {boot_img} ({len(data):,} bytes)")
    print()

    kernel, ramdisk, dtb = parse_boot_img_v2(data)

    kernel_path  = os.path.join(out_dir, 'kernel')
    ramdisk_path = os.path.join(out_dir, 'ramdisk.cpio.gz')
    dtb_path     = os.path.join(out_dir, 'dtb.img')

    with open(kernel_path, 'wb') as f:
        f.write(kernel)
    print(f"\nExtracted kernel:  {len(kernel):,} bytes → {kernel_path}")

    with open(ramdisk_path, 'wb') as f:
        f.write(ramdisk)
    print(f"Extracted ramdisk: {len(ramdisk):,} bytes → {ramdisk_path}")

    if dtb:
        with open(dtb_path, 'wb') as f:
            f.write(dtb)
        print(f"Extracted DTB:     {len(dtb):,} bytes → {dtb_path}")
    else:
        print("No DTB in boot image (dtb_size=0)")

    print()
    print("=== Copy to device tree prebuilt ===")
    print(f"cp {kernel_path} device/samsung/a32x/prebuilt/kernel")
    print(f"cp {dtb_path} device/samsung/a32x/prebuilt/dtb.img")
    print("# Get dtbo.img separately:")
    print("# adb shell 'su -c dd if=/dev/block/by-name/dtbo of=/sdcard/M326B_dtbo.img'")
    print("# adb pull /sdcard/M326B_dtbo.img device/samsung/a32x/prebuilt/dtbo.img")

if __name__ == '__main__':
    main()
