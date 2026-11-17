from pathlib import Path
import hashlib,json,datetime
p=Path(__file__).resolve().parent;m=json.loads((p/'reader-manifest.json').read_text())
for f in m['files']:
 b=(p/f['path']).read_bytes();assert len(b)==f['bytes'] and hashlib.sha256(b).hexdigest()==f['sha256'],f['path']
a=json.loads((p/'recorded/ready-session.json').read_text());b=json.loads((p/'recorded/running-session.json').read_text());dt=lambda s:datetime.datetime.fromisoformat(s.replace('Z','+00:00'))
assert (dt(a['endsAt'])-dt(a['startedAt'])).total_seconds()==60
assert (dt(b['endsAt'])-dt(a['endsAt'])).total_seconds()==47
assert a['startedAt']==b['startedAt']
assert json.loads((p/'recorded/ready-journal.json').read_text())==json.loads((p/'recorded/running-journal.json').read_text())
assert all(not r['real_system_effects'] for r in json.loads((p/'recorded/journey.json').read_text()))
print(json.dumps({'files':len(m['files']),'ready_seconds':60,'deadline_shift_seconds':47,'scope':'Simulated effects and scheduled deadlines only; no physical or visual expiry proof'},indent=2))
