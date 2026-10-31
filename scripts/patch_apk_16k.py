#!/usr/bin/env python3
"""APK 原生库 16KB 页对齐补丁（Android 15+ 16KB 页设备兼容）。

原理：
  2025 年起部分 Android 15/16 设备出厂即使用 16KB 内存页，加载 p_align=4KB
  的原生库会直接失败（dlopen 报 load segment not aligned）→ App 启动即崩。
  若库的所有 PT_LOAD 段满足 (p_vaddr - p_offset) % 16384 == 0，则只需把
  程序头里的 p_align 字段从 0x1000/0x4000 升到 0x10000，即可完全兼容 16KB
  设备且不影响 4KB 设备。不满足条件（需重链接）的库保持原样。

用法：
  python3 scripts/patch_apk_16k.py <输入.apk> <输出.apk>
之后必须执行（顺序不可颠倒）：
  zipalign -P 16 -f 4 <输出.apk> <对齐.apk>
  apksigner sign --ks <keystore> <对齐.apk>
"""
import struct
import sys
import zipfile

PAGE = 16384  # 16KB


def patch_elf(data: bytes) -> bytes:
    """把 ELF64 所有满足 16KB 同余条件的 PT_LOAD p_align 提升到 0x10000。"""
    if len(data) < 0x40 or data[:4] != b"\x7fELF":
        return data
    if data[4] != 2:  # ELFCLASS32 不处理（32 位 ABI 无 16KB 页设备）
        return data
    buf = bytearray(data)
    e_phoff = struct.unpack_from("<Q", buf, 0x20)[0]
    e_phentsize = struct.unpack_from("<H", buf, 0x36)[0]
    e_phnum = struct.unpack_from("<H", buf, 0x38)[0]

    # 第一遍：校验所有 PT_LOAD 的同余性
    loads = []
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        p_type, = struct.unpack_from("<I", buf, off)
        if p_type == 1:  # PT_LOAD
            p_offset = struct.unpack_from("<Q", buf, off + 0x08)[0]
            p_vaddr = struct.unpack_from("<Q", buf, off + 0x10)[0]
            p_align = struct.unpack_from("<Q", buf, off + 0x30)[0]
            loads.append((off, p_offset, p_vaddr, p_align))
    if not loads or any((va - fo) % PAGE for _, fo, va, _ in loads):
        return data  # 存在不满足同余的段（或无 LOAD）：不可补丁，原样返回

    # 第二遍：提升 p_align（仅统计真实写入）
    patched = 0
    for off, _, _, p_align in loads:
        if p_align < PAGE:
            struct.pack_into("<Q", buf, off + 0x30, PAGE)
            patched += 1
    if not patched:
        return data
    return bytes(buf)


def main(src: str, dst: str):
    n_patched = 0
    with zipfile.ZipFile(src, "r") as zin, \
            zipfile.ZipFile(dst, "w") as zout:
        for info in zin.infolist():
            data = zin.read(info.filename)
            # 保持 .so 不压缩存储（extractNativeLibs=false 要求）
            compress = zipfile.ZIP_STORED if info.filename.endswith(".so") \
                else info.compress_type
            if info.filename.endswith(".so"):
                new = patch_elf(data)
                if new is not data:
                    n_patched += 1
                data = new
            zi = zipfile.ZipInfo(info.filename, date_time=info.date_time)
            zi.compress_type = compress
            zi.external_attr = info.external_attr
            zi.internal_attr = info.internal_attr
            zi.create_system = info.create_system
            zout.writestr(zi, data)
    print(f"已补丁 {n_patched} 个原生库 → {dst}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1], sys.argv[2])
