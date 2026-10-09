from pathlib import Path
import hashlib,json,sys,subprocess
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'scripts/spec'))
sys.path.insert(0,str(ROOT/'spec/reference'))
from jsonschema_subset import SchemaSet
from canonical_json import canonicalize
from jovra_ref import references,scoring,stats,csv_export
from validate import engine_input_from_session
base=Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).parent/'actual-session'
schemas=SchemaSet(ROOT/'spec/schemas')
snapshots=list((base/'exports').glob('*/session.json'))
assert len(snapshots)==1
snapshot=json.loads(snapshots[0].read_text())
current=json.loads((base/'session.json').read_text())
for path in [base/'session.json',snapshots[0]]:
    document=json.loads(path.read_text())
    assert not schemas.validate(document,'session.schema.json'),schemas.validate(document,'session.schema.json')
    assert not references.session_problems(document),references.session_problems(document)
    assert canonicalize(path.read_text()).encode()==path.read_bytes()
    print('PASS independent schema/reference/canonical',path.relative_to(base))
old=engine_input_from_session(snapshot)
new=engine_input_from_session(current)
oldfold=scoring.fold(old,old['log']);newfold=scoring.fold(new,new['log'])
oldstats=stats.compute(oldfold);newstats=stats.compute(newfold)
assert oldstats['sides']['A']['totalPointsWon']['n']==1
assert newstats['sides']['B']['totalPointsWon']['n']==1
package=snapshots[0].parent
assert (package/'points.csv').read_bytes()==csv_export.points_csv(old,oldfold).encode()
assert (package/'stats.csv').read_bytes()==csv_export.stats_csv(old,oldstats).encode()
assert all(record['eventLogVersion']==1 and record['status']=='done' for record in current['exports'])
assert references.event_log_version(current)==2
assert 'exports' not in snapshot
assert sorted(p.name for p in package.iterdir())==['clip.mp4','points.csv','session.json','stats.csv']
for record in current['exports']:
    path=base/record['file']['path'];assert path.stat().st_size==record['file']['bytes']
    assert record['includesAudio'] is False
clip=package/'clip.mp4'
probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-count_frames','-show_entries','stream=codec_type,nb_read_frames,duration','-of','json',str(clip)]))
assert len(probe['streams'])==1 and probe['streams'][0]['codec_type']=='video'
assert int(probe['streams'][0]['nb_read_frames'])==30
assert float(probe['streams'][0]['duration'])==1.0
subprocess.run(['ffmpeg','-v','error','-i',str(clip),'-f','null','-'],check=True)
print('PASS independent Python CSV goldens: historical A=1, current corrected B=1, version1<2')
print('PASS external ffprobe30frames/1s/noAudio + FFmpeg full decode')
for path in sorted(base.rglob('*')):
    if path.is_file():print(path.relative_to(base),path.stat().st_size,hashlib.sha256(path.read_bytes()).hexdigest())
