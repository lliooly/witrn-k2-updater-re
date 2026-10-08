"""Extract observed byte substitution tables; never run the vendor assembly."""
from pathlib import Path
import json
import dnfile

ROOT = Path(__file__).resolve().parent
pe = dnfile.dnPE(str(ROOT.parent / 'WITRNUP.dll'))
spec = {
    '5868C4849420C76F770B7EB7969A9B60E3BA7E441EF6A775590E9CAD29BC0431': ('firmware_decode', 256),
    'DCA9ED45326A14DF213B90D20C1C80BA9D88AF039C6831D67FFF64B8455DB351': ('firmware_encode', 256),
    '396C1774717F330B3F9C14309B0E3A5962BF79671086D0B67A74F0EB3745E75A': ('table_4x256', 1024),
    '61F5439E8E6B50E98B2F59DCBC423801E3B72259C7F4B48E0E0CAACE96C4B9C1': ('k2_sector_kib', 447),
}
out = ROOT / 'tables'
out.mkdir(exist_ok=True)
tables = {}
for row in pe.net.mdtables.FieldRva:
    field = str(row.Field.row.Name)
    if field not in spec:
        continue
    name, size = spec[field]
    data = pe.get_data(row.Rva, size)
    assert len(data) == size
    (out / (name + '.bin')).write_bytes(data)
    tables[name] = {'rva': hex(row.Rva), 'field': field, 'bytes': list(data)}
assert set(tables) == {name for name, _ in spec.values()}
decode = tables['firmware_decode']['bytes']
encode = tables['firmware_encode']['bytes']
checks = {
    'decode_is_permutation': len(set(decode)) == 256,
    'encode_is_permutation': len(set(encode)) == 256,
    'tables_are_inverses': all(encode[decode[i]] == i for i in range(256)),
    'k2_sector_count': len(tables['k2_sector_kib']['bytes']),
    'k2_total_bytes': sum(tables['k2_sector_kib']['bytes']) * 1024,
}
(out / 'tables.json').write_text(json.dumps({'checks': checks, 'tables': tables}, indent=2))
print(json.dumps(checks, indent=2))
