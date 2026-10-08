"""Recover proxy tokens with the static IL interpreter; no DLL execution."""
import json
from pathlib import Path
import struct
import dnfile
from unpack_static import execute

ROOT = Path(__file__).resolve().parent
data = execute(624, start=113,
               initial_locals={5: bytearray((ROOT / "dotnet/resource_3e48f.bin").read_bytes())},
               stop_at=886, return_local=5)
assert len(data) == 4592 and len(data) % 8 == 0
pe = dnfile.dnPE(str(ROOT / "dotnet/WITRNUP.restored.dll"))
field_owners, method_owners = {}, {}
for row in pe.net.mdtables.TypeDef:
    name = f"{row.TypeNamespace}.{row.TypeName}"
    for field in row.FieldList:
        field_owners[field.row_index] = name
    for method in row.MethodList:
        method_owners[method.row_index] = name


def target_name(token):
    table, rid = token >> 24, token & 0xffffff
    if table == 6:
        row = pe.net.mdtables.MethodDef.rows[rid - 1]
        return f"{method_owners[rid]}::{row.Name}"
    if table == 10:
        row = pe.net.mdtables.MemberRef.rows[rid - 1]
        parent = row.Class.row
        return f"{getattr(parent, 'TypeNamespace', '')}.{getattr(parent, 'TypeName', '')}::{row.Name}"
    raise ValueError(f"Unexpected target token {token:#x}")


mapping = []
for offset in range(0, len(data), 8):
    field_token, encoded_target = struct.unpack_from("<II", data, offset)
    assert field_token >> 24 == 4
    rid = field_token & 0xffffff
    target = encoded_target & ~0x40000000
    mapping.append({"field_token": hex(field_token),
                    "field": f"{field_owners[rid]}::{pe.net.mdtables.Field.rows[rid - 1].Name}",
                    "target_token": hex(target), "target": target_name(target),
                    "virtual": bool(encoded_target & 0x40000000)})
assert len(mapping) == 574
assert len({entry["field_token"] for entry in mapping}) == 574
(ROOT / "dotnet/delegates_decrypted.bin").write_bytes(data)
(ROOT / "dotnet/delegate_map.json").write_text(json.dumps(mapping, ensure_ascii=True, indent=2))
print(f"Recovered {len(mapping)} proxy mappings")
