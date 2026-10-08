"""Statically parse the protector VM resource; never load the vendor DLL."""
from pathlib import Path
import struct, json
ROOT=Path(__file__).resolve().parent
raw=(ROOT/'dotnet/resource_86bf7.bin').read_bytes()
pos=0
def byte():
 global pos
 v=raw[pos];pos+=1;return v
def vint():
 first=byte();value=first&63;shift=6;b=first
 while b&128:
  b=byte();value|=(b&127)<<shift;shift+=7
 return ~value if first&64 else value
kinds={byte():byte() for _ in range(vint())}
strings=[]
for _ in range(vint()):
 n=vint();strings.append(raw[pos:pos+n].decode('utf-16le'));pos+=n
sizes=[vint() for _ in range(vint())]
base=pos;offsets=[]
for n in sizes: offsets.append(base);base+=n
programs=[]
for index,offset in enumerate(offsets):
 pos=offset
 token,nlocals,nehs,nops=[vint() for _ in range(4)]
 locals_=[vint() for _ in range(nlocals)]
 ehs=[[vint() for _ in range(6)] for _ in range(nehs)]
 ops=[]
 for _ in range(nops):
  op=byte();kind=kinds.get(op,0);arg=None
  if kind==1: arg=vint()
  elif kind in (2,3,4):
   fmt={2:'<q',3:'<f',4:'<d'}[kind];arg=struct.unpack_from(fmt,raw,pos)[0];pos+=struct.calcsize(fmt)
  elif kind==5: arg=[vint() for _ in range(vint())]
  elif kind: raise ValueError(kind)
  ops.append([op,arg])
 assert pos==offset+sizes[index],(index,pos,offset+sizes[index])
 programs.append(dict(index=index,token=hex(token),locals=locals_,ehs=ehs,ops=ops))
(ROOT/'dotnet/vm_programs.json').write_text(json.dumps({'kinds':kinds,'strings':strings,'programs':programs},indent=2))
print('programs',len(programs),'strings',len(strings),'resource fully parsed',base==len(raw))
print(json.dumps(programs[1],indent=2)[:6000])
# Program 1 uses only constants, 32-bit arithmetic and static field stores.
# Mapping recovered from dispatcher RID 1624 and integer value class overrides.
stack=[];fields={}
for op,arg in programs[1]['ops']:
 if op==76: stack.append(arg&0xffffffff)
 elif op==77: fields[arg]=stack.pop()
 elif op==55: break
 elif op in (31,53): stack.append((-stack.pop() if op==31 else ~stack.pop())&0xffffffff)
 else:
  b=stack.pop();a=stack.pop()
  if op==66: v=a^b
  elif op==60: v=a-b
  elif op==130: v=a+b
  elif op==161: v=a<<(b&31)
  elif op==109: v=(a if a<0x80000000 else a-0x100000000)>>(b&31)
  else: raise ValueError(op)
  stack.append(v&0xffffffff)
assert not stack
import dnfile
pe=dnfile.dnPE(str(ROOT/'dotnet/WITRNUP.restored.dll'))
values={str(pe.net.mdtables.Field.rows[(t&0xffffff)-1].Name):v for t,v in fields.items()}
assert len(values)==118
(ROOT/'dotnet/opaque_constants.json').write_text(json.dumps(values,indent=2))
print('Recovered constants',len(values))
for n in ['m_e32f390319684de29dbda887fc64ac3f','m_c4cb428e72df4a33a4a16ccf1d484d29','m_ec896d06c6d1448b85f580fdf24b4ae2']:
 print(n,values[n])
