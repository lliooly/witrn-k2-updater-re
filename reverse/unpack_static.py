"""Evaluate the resource decoder's IL without running the Windows program."""
from pathlib import Path
import ast, io, json, struct
from Crypto.Cipher import AES
from Crypto.Util.Padding import unpad

ROOT=Path(__file__).resolve().parent
METHODS={m['rid']:m for m in json.loads((ROOT/'dotnet/methods.json').read_text())}
GLOBALS={}
RESOURCE=(ROOT/'dotnet/resource_3f683.bin').read_bytes()

def semantic(rid):
    m=METHODS.get(rid)
    if not m: return None
    calls=[i for i in m['instructions'] if i['op'] in ('call','callvirt','newobj') and i['operand']>>24 in (6,10,43)]
    useful=[i for i in calls if (i['resolved'] or '').startswith('System.') and 'System.Object::.ctor'!=i['resolved']]
    if len(useful)==1 and m['size']<70:return useful[0]['resolved']
    if len(calls)==1 and m['size']<35 and calls[0]['operand']>>24==6:
        return semantic(calls[0]['operand']&0xffffff)
    return None

def execute(rid,start=0,args=(),limit=30000000,initial_locals=None,stop_at=None,return_local=None):
    m=METHODS[rid];ins=m['instructions'];offsets={i['offset']:j for j,i in enumerate(ins)}
    pc=offsets[start];stack=[];locals=dict(initial_locals or {});arrays=[]
    for step in range(limit):
        i=ins[pc];pc+=1;op=i['op'];v=i['operand'];off=i['offset']
        if stop_at is not None and off==stop_at:
            return bytes(locals[return_local])
        def jump(v):return offsets[v-m['header_size']]
        def popn(n):
            x=stack[-n:] if n else []
            if n:del stack[-n:]
            return x
        try:
            if op.startswith('ldc.i4'):stack.append(v if op in ('ldc.i4','ldc.i4.s') else (-1 if op.endswith('m1') else int(op.rsplit('.',1)[1])))
            elif op=='ldc.i8':stack.append(v)
            elif op.startswith('ldloc') and 'a' not in op:
                idx=v if op in ('ldloc','ldloc.s') else int(op.rsplit('.',1)[1]);stack.append(locals.get(idx,0))
            elif op.startswith('stloc'):
                idx=v if op in ('stloc','stloc.s') else int(op.rsplit('.',1)[1]);locals[idx]=stack.pop()
            elif op.startswith('ldarg') and 'a' not in op:
                idx=v if op in ('ldarg','ldarg.s') else int(op.rsplit('.',1)[1]);stack.append(args[idx])
            elif op=='ldnull':stack.append(None)
            elif op=='dup':stack.append(stack[-1])
            elif op=='pop':stack.pop()
            elif op=='newarr':
                n=stack.pop();a=bytearray(n);arrays.append(a);stack.append(a)
            elif op=='ldlen':stack.append(len(stack.pop()))
            elif op.startswith('stelem'):
                a,idx,x=popn(3);a[idx]=x&255 if isinstance(a,bytearray) else x
            elif op.startswith('ldelem'):
                a,idx=popn(2);stack.append(a[idx])
            elif op=='ldstr':stack.append(ast.literal_eval(i['resolved']))
            elif op=='ldsfld':stack.append(GLOBALS.get(v,0 if i['resolved']=='System.IntPtr::Zero' else None))
            elif op=='stsfld':GLOBALS[v]=stack.pop()
            elif op in ('add','sub','mul','xor','and','or','shl','shr','shr.un','div','div.un','rem','rem.un','ceq','clt','clt.un','cgt','cgt.un'):
                a,b=popn(2)
                if op in ('div.un','rem.un','shr.un'):a&=0xffffffff
                if op=='add':x=a+b
                elif op=='sub':x=a-b
                elif op=='mul':x=a*b
                elif op=='xor':x=a^b
                elif op=='and':x=a&b
                elif op=='or':x=a|b
                elif op=='shl':x=a<<(b&31)
                elif op.startswith('shr'):x=a>>(b&31)
                elif op.startswith('div'):x=a//b
                elif op.startswith('rem'):x=a%b
                elif op=='ceq':x=int(a==b)
                elif op.startswith('clt'):x=int(a<b)
                else:x=int(a>b)
                if op in ('add','sub','mul','shl','xor','or'):x&=0xffffffff
                stack.append(x)
            elif op=='not':stack.append((~stack.pop())&0xffffffff)
            elif op=='neg':stack.append((-stack.pop())&0xffffffff)
            elif op.startswith('conv.'):
                x=stack.pop()
                if op.endswith(('i1','u1')):x&=255
                elif op.endswith(('i4','u4')):x&=0xffffffff
                stack.append(x)
            elif op in ('br','br.s','leave','leave.s'):pc=jump(v)
            elif op in ('brtrue','brtrue.s','brfalse','brfalse.s'):
                x=bool(stack.pop())
                if x==op.startswith('brtrue'):pc=jump(v)
            elif op.split('.')[0] in ('beq','bne','bge','bgt','ble','blt'):
                a,b=popn(2);typ=op.split('.')[0]
                if {'beq':a==b,'bne':a!=b,'bge':a>=b,'bgt':a>b,'ble':a<=b,'blt':a<b}[typ]:pc=jump(v)
            elif op=='switch':
                x=stack.pop()
                if 0<=x<len(v):pc=jump(v[x])
            elif op in ('call','callvirt','newobj'):
                child=v&0xffffff if v>>24==6 else None
                name=semantic(child) if child else i['resolved']
                if v==0x2b000004:name='System.Array::Reverse'
                if child in (814,815):stack.append(child==814);continue
                if name is None and child:
                    cm=METHODS[child]
                    if cm['size']<=5:
                        if any(x['op']=='ldnull' for x in cm['instructions']):stack.append(None)
                        continue
                if name=='System.Reflection.Assembly::GetManifestResourceStream':
                    resource_name=stack.pop();stack.pop();print('RESOURCE',repr(resource_name));stack.append(io.BytesIO(RESOURCE))
                elif name=='System.IO.BinaryReader::.ctor':stack.append(stack.pop())
                elif name in ('System.IO.Stream::get_Position','System.IO.BinaryReader::get_BaseStream'):
                    obj=stack.pop();stack.append(obj.tell() if name.endswith('get_Position') else obj)
                elif name=='System.IO.Stream::set_Position':obj,pos=popn(2);obj.seek(pos)
                elif name=='System.IO.Stream::get_Length':
                    obj=stack.pop();stack.append(len(obj.getvalue()))
                elif name=='System.IO.BinaryReader::ReadBytes':obj,n=popn(2);stack.append(bytearray(obj.read(n)))
                elif name=='System.Array::Reverse':stack.pop().reverse()
                elif name=='System.Reflection.Assembly::GetName':stack.pop();stack.append('assembly-name')
                elif name=='System.Reflection.AssemblyName::GetPublicKeyToken':stack.pop();stack.append(bytearray())
                elif name=='System.Array::Clear':a,x,n=popn(3);a[x:x+n]=bytes(n)
                elif name=='System.Security.Cryptography.SymmetricAlgorithm::set_Mode':popn(2)
                elif name=='System.Security.Cryptography.SymmetricAlgorithm::CreateDecryptor':
                    obj,key,iv=popn(3);print('AES',bytes(key).hex(),bytes(iv).hex());stack.append(AES.new(bytes(key),AES.MODE_CBC,bytes(iv)))
                elif name=='System.IO.MemoryStream::.ctor':stack.append(io.BytesIO())
                elif name=='System.Security.Cryptography.CryptoStream::.ctor':
                    stream,cipher,mode=popn(3);stack.append({'stream':stream,'cipher':cipher})
                elif name=='System.IO.Stream::Write':
                    obj,a,x,n=popn(4)
                    if isinstance(obj,dict):obj['stream'].write(unpad(obj['cipher'].decrypt(bytes(a[x:x+n])),16))
                    else:obj.write(bytes(a[x:x+n]))
                elif name=='System.Security.Cryptography.CryptoStream::FlushFinalBlock':stack.pop()
                elif name=='System.IO.MemoryStream::ToArray':
                    data=stack.pop().getvalue();(ROOT/'dotnet/methods_decrypted.bin').write_bytes(data);print('DECRYPTED',len(data),data[:32].hex());return data
                elif name in ('System.IO.Stream::Close','System.IO.BinaryReader::Close'):stack.pop()
                elif child and METHODS[child]['size']<70:
                    print('CUSTOM CALL',child,repr(name),repr(METHODS[child]['name']))
                    # Algorithm factory returns an AES placeholder.
                    if child in (628,765):stack.append('AES')
                    else:raise NotImplementedError(f'custom method {child}')
                else:raise NotImplementedError(f'call {child} {name!r}')
            elif op=='ret':return stack[-1] if stack else None
            elif op=='ldind.i8':
                data=bytes(locals[103]);(ROOT/'dotnet/methods_custom_decoded.bin').write_bytes(data)
                following=ins[pc]
                assert following['op'] in ('ldc.i8','ldc.i4'),following
                key=following['operand']&0xffffffffffffffff
                decoded=bytearray(data)
                for p in range(0,len(decoded)-7,8):struct.pack_into('<Q',decoded,p,struct.unpack_from('<Q',decoded,p)[0]^key)
                (ROOT/'dotnet/methods_decrypted.bin').write_bytes(decoded)
                print('XOR64',hex(key),'DECRYPTED',len(decoded),decoded[:48].hex())
                return decoded
            elif op=='nop':pass
            else:raise NotImplementedError(op)
        except Exception:
            print('STOP',rid,hex(off),op,v,'step',step,'stack',repr(stack)[:200])
            print('LOCAL ARRAYS',[(k,len(a),bytes(a).hex()[:100]) for k,a in locals.items() if isinstance(a,bytearray)])
            raise
    raise RuntimeError(f'step limit exceeded at {off:x}')

if __name__=='__main__':execute(665,start=0x4b1e)
