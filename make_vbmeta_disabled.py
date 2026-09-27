#!/usr/bin/env python3
"""
make_vbmeta_disabled.py — Create a minimal AVB disabled-verification vbmeta.img
for Samsung Galaxy M32 5G (SM-M326B) TWRP installation.

Produces a 65536-byte vbmeta.img with:
  Algorithm:             NONE (no signing key needed)
  Flags:                 0x00000003
    VERIFICATION_DISABLED (bit 0) = True
    HASHTREE_DISABLED     (bit 1) = True
  Descriptors:           (none)
  Rollback index:        0

This matches the state Magisk sets on the M326B vbmeta, and is what
the A326B TWRP community (afaneh92, Goldenkrew3000) uses.

Usage:
  python3 make_vbmeta_disabled.py [output.img]
  # Output defaults to: M326B_vbmeta_twrp.img

Alternative (using avbtool if installed):
  avbtool make_vbmeta_image --flags 3 --padding_size 65536 --output M326B_vbmeta_twrp.img
"""

import sys
import struct
import os

def make_vbmeta_disabled(output_path: str, padding_size: int = 65536):
    """
    Create a minimal disabled-verification vbmeta.img.
    
    AVB1.0 header structure (256 bytes header):
      Offset   Size  Field
      0        4     magic = 'AVB0'
      4        4     required_libavb_version_major (BE uint32)
      8        4     required_libavb_version_minor (BE uint32)
      12       8     authentication_data_block_size (BE uint64)
      20       8     auxiliary_data_block_size (BE uint64)
      28       4     algorithm_type (BE uint32):
                       0=NONE, 1=SHA256_RSA2048, 2=SHA256_RSA4096
      32       8     hash_offset (BE uint64)
      40       8     hash_size (BE uint64)
      48       8     signature_offset (BE uint64)
      56       8     signature_size (BE uint64)
      64       8     public_key_offset (BE uint64)
      72       8     public_key_size (BE uint64)
      80       8     public_key_metadata_offset (BE uint64)
      88       8     public_key_metadata_size (BE uint64)
      96       8     descriptor_offset (BE uint64)
      104      8     descriptor_size (BE uint64)
      112      8     rollback_index (BE uint64)
      120      4     flags (BE uint32) ← SET TO 3 HERE
      124      4     rollback_index_location (BE uint32)
      128      48    release_string (null-padded ASCII)
      176      80    reserved (zeros)
      256      ...   authentication block (empty for NONE algorithm)
      ...      ...   auxiliary block (empty for NONE algorithm)
    """
    hdr = bytearray(256)
    
    # Magic
    hdr[0:4] = b'AVB0'
    
    # required_libavb_version = 1.0
    struct.pack_into('>I', hdr, 4, 1)   # major
    struct.pack_into('>I', hdr, 8, 0)   # minor
    
    # authentication_data_block_size = 0 (NONE algorithm: no hash or signature)
    struct.pack_into('>Q', hdr, 12, 0)
    
    # auxiliary_data_block_size = 0 (no public key, no descriptors)
    struct.pack_into('>Q', hdr, 20, 0)
    
    # algorithm_type = 0 (NONE — no key required)
    struct.pack_into('>I', hdr, 28, 0)
    
    # hash_offset, hash_size = 0
    struct.pack_into('>Q', hdr, 32, 0)
    struct.pack_into('>Q', hdr, 40, 0)
    
    # signature_offset, signature_size = 0
    struct.pack_into('>Q', hdr, 48, 0)
    struct.pack_into('>Q', hdr, 56, 0)
    
    # public_key_offset, public_key_size = 0
    struct.pack_into('>Q', hdr, 64, 0)
    struct.pack_into('>Q', hdr, 72, 0)
    
    # public_key_metadata_offset, public_key_metadata_size = 0
    struct.pack_into('>Q', hdr, 80, 0)
    struct.pack_into('>Q', hdr, 88, 0)
    
    # descriptor_offset, descriptor_size = 0 (no descriptors)
    struct.pack_into('>Q', hdr, 96, 0)
    struct.pack_into('>Q', hdr, 104, 0)
    
    # rollback_index = 0
    struct.pack_into('>Q', hdr, 112, 0)
    
    # FLAGS = 3 = VERIFICATION_DISABLED | HASHTREE_DISABLED
    # This is the key field. Offset 120, big-endian uint32.
    struct.pack_into('>I', hdr, 120, 3)
    
    # rollback_index_location = 0
    struct.pack_into('>I', hdr, 124, 0)
    
    # Release string (48 bytes, null-padded)
    release = b'avbtool 1.2.0'
    hdr[128:128+len(release)] = release
    # rest is zeros (already initialized)
    
    # The full image = header + padding to padding_size
    image = bytes(hdr) + bytes(padding_size - 256)
    assert len(image) == padding_size, f"Size mismatch: {len(image)} vs {padding_size}"
    
    with open(output_path, 'wb') as f:
        f.write(image)
    
    return image

def verify_vbmeta(data: bytes):
    """Verify the created vbmeta by parsing it back."""
    print("=== Verification ===")
    print(f"Magic:         {data[0:4]}")
    major = struct.unpack_from('>I', data, 4)[0]
    minor = struct.unpack_from('>I', data, 8)[0]
    print(f"AVB version:   {major}.{minor}")
    algo  = struct.unpack_from('>I', data, 28)[0]
    algo_name = {0: 'NONE', 1: 'SHA256_RSA2048', 2: 'SHA256_RSA4096'}.get(algo, f'UNKNOWN({algo})')
    print(f"Algorithm:     {algo_name}")
    rollback = struct.unpack_from('>Q', data, 112)[0]
    print(f"Rollback idx:  {rollback}")
    flags = struct.unpack_from('>I', data, 120)[0]
    print(f"Flags:         0x{flags:08X}")
    print(f"  VERIFICATION_DISABLED (bit0): {bool(flags & 1)}")
    print(f"  HASHTREE_DISABLED     (bit1): {bool(flags & 2)}")
    release = data[128:176].rstrip(b'\x00').decode('ascii', errors='replace')
    print(f"Release:       '{release}'")
    non_zero = sum(1 for b in data if b != 0)
    print(f"Non-zero bytes: {non_zero} of {len(data)}")
    
    assert data[0:4] == b'AVB0', "BAD MAGIC"
    assert flags & 1, "VERIFICATION_DISABLED not set!"
    assert flags & 2, "HASHTREE_DISABLED not set!"
    print("\n✓ vbmeta is valid and has all verification disabled")

def main():
    output = sys.argv[1] if len(sys.argv) > 1 else 'M326B_vbmeta_twrp.img'
    padding = 65536  # Verified from M326B vbmeta partition size

    print(f"Creating disabled-verification vbmeta: {output}")
    print(f"Padding size: {padding} bytes (65536 = M326B vbmeta partition size)")
    print()

    data = make_vbmeta_disabled(output, padding)

    print(f"Written: {output} ({len(data):,} bytes)")
    print()
    
    verify_vbmeta(data)
    
    import hashlib
    sha256 = hashlib.sha256(data).hexdigest()
    print(f"\nSHA256: {sha256}")
    print()
    print("Flash with Heimdall:")
    print(f"  heimdall flash --VBMETA {output} --RECOVERY recovery.img --no-reboot")

if __name__ == '__main__':
    main()
