from pathlib import Path
import json, sys
import dnfile
from dncil.cil.body.reader import read_method_body_from_bytes

ROOT = Path(__file__).resolve().parent.parent
pe = dnfile.dnPE(str(ROOT / 'WITRNUP.dll'))
owners = {}
for t in pe.net.mdtables.TypeDef:
    for m in t.MethodList:
        owners[m.row_index] = f'{t.TypeNamespace}.{t.TypeName}'

def token_name(token):
    value = token.value
    table, rid = value >> 24, value & 0xffffff
    if table == 0x70:
        s = pe.net.user_strings.get(rid)
        return repr(s.value) if s else hex(value)
    tables = {0x01:'TypeRef',0x02:'TypeDef',0x04:'Field',0x06:'MethodDef',0x0a:'MemberRef',0x11:'StandAloneSig',0x1b:'TypeSpec',0x2b:'MethodSpec'}
    try:
        row = getattr(pe.net.mdtables, tables[table]).rows[rid-1]
        if table == 6:
            return f'{owners[rid]}::{row.Name}'
        if table in (1,2):
            return f'{row.TypeNamespace}.{row.TypeName}'
        if table == 0x0a:
            parent = row.Class.row
            return f'{getattr(parent,"TypeNamespace", "")}.{getattr(parent,"TypeName", "")}::{row.Name}'
        return str(getattr(row,'Name',hex(value)))
    except Exception:
        return hex(value)

methods = []
for rid,m in enumerate(pe.net.mdtables.MethodDef,1):
    if not m.Rva: continue
    try: body = read_method_body_from_bytes(pe.get_data(m.Rva,100000))
    except Exception: continue
    ins=[]
    for i in body.instructions:
        op=i.operand
        raw=op.value if hasattr(op,'value') else op
        if raw is not None and not isinstance(raw,(int,float,str,list)):
            raw=raw.index
        ins.append({'offset':i.offset-body.header_size,'op':i.opcode.name,'operand':raw,'resolved':token_name(op) if hasattr(op,'value') else None})
    methods.append({'rid':rid,'name':f'{owners.get(rid, "")}::{m.Name}','rva':m.Rva,'header_size':body.header_size,'size':body.code_size,'instructions':ins})
out=ROOT/'reverse'/'dotnet'
out.mkdir(parents=True,exist_ok=True)
(out/'methods.json').write_text(json.dumps(methods,ensure_ascii=True,indent=2))
for r in pe.net.resources:
    if isinstance(r.data,bytes):
        (out/f'resource_{r.rva:x}.bin').write_bytes(r.data)
print('Resources:')
for r in pe.net.resources:
    print(hex(r.rva),r.size,repr(str(r.name)))
targets=set(map(int,sys.argv[1:]))
for m in methods:
    if m['rid'] in targets:
        print('METHOD',m['rid'],repr(m['name']),hex(m['rva']),m['size'])
        for i in m['instructions']:
            if i['resolved'] and i['op'] in ('ldstr','call','callvirt','newobj'):
                print(hex(i['offset']),i['op'],repr(i['resolved']))
