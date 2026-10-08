import io
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
import uuid

from k2up.picture import MAGIC, RESOURCES, Resource, resource_for, sha
from k2up.picture_device import backup_resource, load_backup, transfer_resource, write_resource
from k2up.picture_simulator import PictureTransport
from k2up.protocol import Protocol, ProtocolError
from k2up.updater import Updater
from k2up.gui_bridge import main, Events
from k2up.firmware import APP_START


def payload(kind):
    if kind in ("emark", "emark-copy"):
        from k2up.emark import sample_bank, sample_record
        return sample_bank() if kind == "emark" else sample_record()
    r = resource_for(kind)
    data = bytearray(r.size); data[:4] = data[-4:] = MAGIC
    return bytes(data)


def connected(fault=None):
    transport = PictureTransport(fault=fault); protocol = Protocol(transport)
    identity = Updater(protocol).probe()
    return transport, protocol, identity


class PictureTests(unittest.TestCase):
    def test_fixed_ranges_are_nonoverlapping_aligned_and_large_enough(self):
        resources = sorted(RESOURCES.values(), key=lambda r: r.address)
        for r in resources:
            self.assertEqual(r.address % 2048, 0)
            self.assertGreaterEqual(r.allocation, r.size)
            self.assertLess(r.allocation-r.size, 2048)
        for a,b in zip(resources,resources[1:]):
            self.assertLessEqual(a.address+a.allocation,b.address)
        self.assertEqual([(r.kind,r.address,r.sectors) for r in resources],
                         [('background',0x080c6800,57),('emark-copy',0x080e3000,1),('emark',0x080e3800,1),('layout',0x080e4000,1),('startup',0x080e4800,54)])
        with self.assertRaises(ValueError): resource_for('firmware')

    def test_payload_validation(self):
        for kind,r in RESOURCES.items():
            self.assertEqual(r.validate(payload(kind)),payload(kind))
            with self.assertRaises(ValueError): r.validate(payload(kind)[:-1])
            damaged = bytearray(payload(kind))
            damaged[71 if kind == 'emark' else 0] ^= 1
            with self.assertRaises(ValueError): r.validate(damaged)
        data=bytearray(payload('layout'));data[12]=2
        with self.assertRaises(ValueError): resource_for('layout').validate(data)

    def test_precision_ranges_match_official_options_for_enabled_fields(self):
        for element,position,low,high in ((0,0,2,7),(1,1,2,7),(2,2,3,7),(4,3,2,3),(5,4,2,3),(9,5,2,3),(10,6,2,3),(15,7,3,7)):
            data=bytearray(payload('layout'));data[4+element*10+8]=1
            for valid in (low,high):
                data[224+position]=valid;resource_for('layout').validate(data)
            for invalid in (low-1,high+1):
                data[224+position]=invalid
                with self.assertRaises(ValueError):resource_for('layout').validate(data)
            data[4+element*10+8]=0;resource_for('layout').validate(data)
        data=bytearray(payload('layout'));data[12]=1;data[13]=7
        with self.assertRaises(ValueError): resource_for('layout').validate(data)
        data=bytearray(payload('layout'));data[224]=10
        with self.assertRaises(ValueError): resource_for('layout').validate(data)

    def test_all_resource_transfers_preserve_sector_padding_and_verify(self):
        for kind,r in RESOURCES.items():
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as root:
                t,p,identity=connected()
                start=r.address-APP_START
                original=bytes(t.memory[start:start+r.allocation])
                tail=bytes((i*13)%256 for i in range(r.allocation-r.size))
                t.memory[start+r.size:start+r.allocation]=tail
                req={'id':str(uuid.uuid4()),'operation':'resource-write','resource_kind':kind,'_resource_bytes':payload(kind)}
                result=transfer_resource(req,Events(req,io.StringIO()),p,identity,Path(root)/'backup')
                self.assertTrue(t.exited)
                self.assertEqual(bytes(t.memory[start+r.size:start+r.allocation]),tail)
                self.assertEqual(bytes(t.memory[:start]),bytes(PictureTransport().memory[:start]))
                r2,backup,meta=load_backup(Path(root)/'backup/manifest.json')
                self.assertEqual(r2,r);self.assertEqual(backup[r.size:],tail)
                self.assertTrue(meta['two_reads_match'])
                self.assertEqual(result['verified_sha256'],sha(bytes(t.memory[start:start+r.allocation])))
                erases=[struct.unpack('<I',a.payload)[0] for a in t.sent if a.command==8]
                self.assertEqual(erases,list(r.addresses))

    def test_backup_disk_failure_prevents_erase(self):
        for kind in ('layout', 'emark', 'emark-copy'):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as root:
                t,p,identity=connected(); r=resource_for(kind)
                with patch('k2up.picture_device.durable_write', side_effect=OSError('disk full')):
                    with self.assertRaises(OSError): backup_resource(p,r,identity,Path(root)/'backup',lambda *a:None)
                self.assertFalse(t.erased)

    def test_second_read_mismatch_prevents_erase_and_no_valid_manifest(self):
        for kind in ('layout', 'emark', 'emark-copy'):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as root:
                t,p,identity=connected();r=resource_for(kind)
                original=p.read_memory;count=[0]
                def unstable(address,size):
                    count[0]+=1;data=original(address,size)
                    return bytes([data[0]^1])+data[1:] if count[0]>2 else data
                with patch.object(p,'read_memory',side_effect=unstable):
                    with self.assertRaises(ProtocolError): backup_resource(p,r,identity,Path(root)/'backup',lambda *a:None)
                self.assertFalse(t.erased);self.assertFalse((Path(root)/'backup/manifest.json').exists())

    def test_write_failures_do_not_exit(self):
        for kind in ('layout', 'emark', 'emark-copy'):
            r=resource_for(kind)
            for fault in ('verify','disconnect','batch-nack'):
                with self.subTest(kind=kind, fault=fault):
                    t,p,_=connected(fault)
                    with self.assertRaises((ProtocolError,OSError)):
                        write_resource(p,r,payload(kind)+b'\xff'*(r.allocation-r.size),lambda *a:None)
                    self.assertFalse(t.exited)
                    if fault=='batch-nack': self.assertFalse(t.written)

    def test_arbitrary_address_refused_before_any_command(self):
        t,p,_=connected();sent=len(t.sent)
        with self.assertRaises(ValueError):write_resource(p,Resource('layout',APP_START,400,1),b'\xff'*2048,lambda *a:None)
        self.assertEqual(len(t.sent),sent)

    def test_restore_keeps_all_original_bytes_and_rejects_other_device(self):
        with tempfile.TemporaryDirectory() as root:
            t,p,identity=connected();r=resource_for('layout')
            old,meta=backup_resource(p,r,identity,Path(root)/'old',lambda *a:None)
            req={'id':str(uuid.uuid4()),'operation':'resource-restore','resource_kind':'layout',
                 '_restore_bytes':old,'_restore_identity':'other-device'}
            with self.assertRaises(ValueError):transfer_resource(req,Events(req,io.StringIO()),p,identity,Path(root)/'rejected')
            self.assertFalse(t.erased)
            req['_restore_identity']=identity.info_sha256
            transfer_resource(req,Events(req,io.StringIO()),p,identity,Path(root)/'accepted')
            self.assertTrue(t.exited);self.assertEqual(bytes(t.memory[r.address-APP_START:r.address-APP_START+r.allocation]),old)

    def test_corrupt_backup_and_nonobject_manifest_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            t,p,i=connected();folder=Path(root)/'backup';backup_resource(p,resource_for('layout'),i,folder,lambda *a:None)
            (folder/'sectors.bin').write_bytes(b'\x00'*2048)
            with self.assertRaises(ValueError):load_backup(folder/'manifest.json')
            (folder/'manifest.json').write_text('[]')
            with self.assertRaises(ValueError):load_backup(folder/'manifest.json')

    def execute(self,request):
        out=io.StringIO();code=main(io.StringIO(json.dumps(request)+'\n'),out)
        return code,[json.loads(x) for x in out.getvalue().splitlines()]

    def test_bridge_read_write_restore_and_preflight_guards(self):
        with tempfile.TemporaryDirectory() as root, patch('k2up.transport._hid',side_effect=AssertionError('USB accessed')):
            base={'id':str(uuid.uuid4()),'operation':'resource-read','resource_kind':'layout',
                  'simulation':True,'data_directory':root,'demo_delay_ms':0}
            code,events=self.execute(base);self.assertEqual(code,0)
            result=events[-1]['value'];self.assertTrue(result['resource_valid'])
            path=Path(root)/'layout.pic';path.write_bytes(payload('layout'))
            write=dict(base,id=str(uuid.uuid4()),operation='resource-write',confirmed=True,
                       device_info_sha256=result['identity']['info_sha256'],resource_path=str(path),resource_sha256=sha(path.read_bytes()))
            code,events=self.execute(write);self.assertEqual(code,0)
            stages=[e['stage'] for e in events if e['event']=='progress']
            self.assertLess(stages.index('resource-backup-complete'),stages.index('resource-erase'))
            manifest=Path(events[-1]['value']['backup']['directory'])/'manifest.json'
            restore=dict(write,id=str(uuid.uuid4()),operation='resource-restore',restore_manifest_path=str(manifest),restore_manifest_sha256=sha(manifest.read_bytes()))
            self.assertEqual(self.execute(restore)[0],0)
            for invalid in (dict(write,confirmed=False),dict(write,resource_sha256='changed'),dict(write,device_info_sha256=None),dict(restore,restore_manifest_sha256='changed')):
                with patch('k2up.gui_bridge.connection',side_effect=AssertionError('device opened')):
                    self.assertEqual(self.execute(invalid)[0],1)
