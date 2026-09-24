#!/usr/bin/env python3
"""Build an original homebrew diagnostic with Apple clang's ARM assembler.
Extracts relocation-free ELF .text; does not require a downloaded ROM/SDK.
"""
import hashlib, json, os, struct, subprocess
from pathlib import Path
root=Path(__file__).resolve().parent.parent
out=root/'build/fixtures'; out.mkdir(parents=True,exist_ok=True)
def assemble(name):
    obj=out/(name+'.o')
    subprocess.run(['xcrun','clang','-target','armv5te-none-eabi','-c',str(root/'Fixtures/Diagnostic'/f'{name}.s'),'-o',str(obj)],check=True)
    data=obj.read_bytes()
    assert data[:6]==b'\x7fELF\x01\x01'
    shoff=struct.unpack_from('<I',data,32)[0]
    size,count,names=struct.unpack_from('<HHH',data,46)
    sections=[struct.unpack_from('<10I',data,shoff+i*size) for i in range(count)]
    ns=sections[names]; strings=data[ns[4]:ns[4]+ns[5]]
    for s in sections:
        name=strings[s[0]:].split(b'\0')[0]
        if s[1] in (4,9) and s[5]: raise RuntimeError('unexpected relocations')
        if name==b'.text': text=data[s[4]:s[4]+s[5]]
    return text
a9=assemble('arm9'); a7=assemble('arm7')
rom=bytearray(0x20000)
rom[:12]=b'DUO DIAG    '; rom[12:16]=b'####'; rom[16:18]=b'00'
struct.pack_into('<4I',rom,0x20,0x1000,0x02000000,0x02000000,len(a9))
struct.pack_into('<4I',rom,0x30,0x2000,0x03800000,0x03800000,len(a7))
struct.pack_into('<II',rom,0x80,len(rom),0x1000)
rom[0x1000:0x1000+len(a9)]=a9; rom[0x2000:0x2000+len(a7)]=a7
# Standard CRC16 for our own header; no proprietary Nintendo logo included.
crc=0xffff
for byte in rom[:0x15e]:
    crc ^= byte
    for _ in range(8): crc=(crc>>1)^ (0xa001 if crc&1 else 0)
struct.pack_into('<H',rom,0x15e,crc)
path=out/'duo-diagnostic.nds'; path.write_bytes(rom)
manifest={'id':'duo-diagnostic-v1','provenance':'locally authored Fixtures/Diagnostic assembly','license':'MIT','sha256':hashlib.sha256(rom).hexdigest(),'bytes':len(rom),'capabilities':['2D motion','buttons','PSG audio'], 'unsupported':['persistent save','serialization','microphone','stylus diagnostic','3D'], 'note':'Homebrew only. Does not satisfy V02 save or V20 supported-state requirements.'}
(out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps(manifest,indent=2))
