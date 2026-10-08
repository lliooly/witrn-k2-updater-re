"""Rebuild an analysis-only DLL from the statically decoded method resource."""
from pathlib import Path
import json, struct
import dnfile
from dncil.cil.body.reader import read_method_body_from_bytes

ROOT=Path(__file__).resolve().parent
raw=bytearray((ROOT.parent/'WITRNUP.dll').read_bytes())
pe=dnfile.dnPE(data=raw)
resource=(ROOT/'dotnet/methods_decrypted.bin').read_bytes()
lookup={}
for rid,m in enumerate(pe.net.mdtables.MethodDef,1):
    if m.Rva:
        body=read_method_body_from_bytes(pe.get_data(m.Rva,100000))
        lookup[m.Rva+body.header_size]=rid

patches,mode=struct.unpack_from('<II',resource,8)
assert mode==0
for j in range(patches):
    rva,value=struct.unpack_from('<II',resource,16+j*8)
    struct.pack_into('<I',raw,pe.get_offset_from_rva(rva),value)
patched=dnfile.dnPE(data=raw)
pos=16+patches*8
count=struct.unpack_from('<I',resource,pos)[0];pos+=4
align=lambda x,a:(x+a-1)&~(a-1)
section_offset=align(len(raw),pe.OPTIONAL_HEADER.FileAlignment)
last=pe.sections[-1]
section_rva=last.VirtualAddress+section_offset-last.PointerToRawData
newsection=bytearray();manifest=[]
while pos<len(resource)-1:
    rva,index,size=struct.unpack_from('<III',resource,pos);pos+=12
    code=resource[pos:pos+size];pos+=size
    assert index<0x70000000 and rva in lookup
    rid=lookup[rva];method=patched.net.mdtables.MethodDef.rows[rid-1]
    body=read_method_body_from_bytes(patched.get_data(method.Rva,100000))
    header=bytearray(patched.get_data(method.Rva,body.header_size))
    if body.header_size==1:
        header=bytearray(struct.pack('<HHII',0x3003,8,size,0))
    else:struct.pack_into('<I',header,4,size)
    newsection+=bytes(align(len(newsection),4)-len(newsection))
    newrva=section_rva+len(newsection)
    newsection+=header+code
    if body.flags.MoreSects:
        newsection+=bytes(align(len(newsection),4)-len(newsection))
        oldextra=align(method.Rva+body.header_size+body.code_size,4)
        extrasize=body.size-(oldextra-method.Rva)
        newsection+=patched.get_data(oldextra,extrasize)
    struct.pack_into('<I',raw,method.struct.get_file_offset(),newrva)
    manifest.append({'rid':rid,'original_code_rva':rva,'new_rva':newrva,'code_size':size})

assert pos==len(resource) and len(manifest)==count
table=last.get_file_offset()
section_size=section_offset-last.PointerToRawData+len(newsection)
struct.pack_into('<I',raw,table+8,section_size)
struct.pack_into('<I',raw,table+16,align(section_size,pe.OPTIONAL_HEADER.FileAlignment))
struct.pack_into('<I',raw,table+36,0x60000020)
struct.pack_into('<I',raw,pe.OPTIONAL_HEADER.get_file_offset()+56,align(section_rva+len(newsection),pe.OPTIONAL_HEADER.SectionAlignment))
raw+=bytes(section_offset-len(raw))+newsection
raw+=bytes(align(len(raw),pe.OPTIONAL_HEADER.FileAlignment)-len(raw))
out=ROOT/'dotnet/WITRNUP.restored.dll';out.write_bytes(raw)
(ROOT/'dotnet/restored_manifest.json').write_text(json.dumps(manifest,indent=2))
check=dnfile.dnPE(str(out));verified=0
for entry in manifest:
    m=check.net.mdtables.MethodDef.rows[entry['rid']-1]
    b=read_method_body_from_bytes(check.get_data(m.Rva,100000))
    assert b.code_size==entry['code_size']
    verified+=1
print(f'Restored and verified {verified} methods; {patches} header patches; {out}')
