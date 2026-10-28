"""Recalculo independiente de las 128 corridas archivadas, sin simulacion."""
from pathlib import Path
import csv,json,hashlib,statistics,math,collections
ROOT=Path(__file__).resolve().parents[1];ARCHIVE=ROOT/'experiments/ns3_archive'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def load(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def main():
    build=load(ARCHIVE/'build_manifest.json');code_sha=sha(ARCHIVE/'validacion_lorawan_v02.cc')
    assert code_sha==build['source_sha256'],'Codigo diferente del compilado'
    matrices={sha(p):p for p in (ARCHIVE/'inputs').glob('Matrix_*.csv')}
    groups=collections.defaultdict(list);runs=sorted((ARCHIVE/'produccion').rglob('run_manifest.json'))
    assert len(runs)==128
    for path in runs:
        run=load(path);identity=run['identity'];opts=identity['options'];m=load(path.parent/'metrics.json')
        assert run['returncode']==0 and identity['source_sha256']==code_sha
        assert identity['matrix_sha256'] in matrices
        assert sha(path.parent/'metrics.json')==run['metrics_sha256']
        for name,digest in run['artifact_sha256'].items():
            p=path.parent/name
            if p.exists():assert sha(p)==digest,(path,name)
        assert m['n_devices']==2153 and m['n_gateways']==10
        assert 0<=m['server_unique']<=m['generated'] and m['invariants_ok']
        pdr=100*m['server_unique']/m['generated']
        assert abs(pdr-m['pdr_server_generated_pct'])<1e-6
        with (path.parent/'node_metrics.csv').open(encoding='utf-8-sig',newline='') as f:rows=list(csv.DictReader(f))
        assert len(rows)==2153 and len({r['node_id'] for r in rows})==2153
        assert sum(int(r['generated']) for r in rows)==m['generated']
        assert sum(int(r['server_unique']) for r in rows)==m['server_unique']
        model='DigitalTwin' if 'reconstruida' in matrices[identity['matrix_sha256']].name else 'LongleyRice'
        groups[(model,int(opts['sf']),int(opts['period']))].append((int(opts['run']),pdr))
    result=[]
    for (model,sf,period),values in sorted(groups.items()):
        n=len(values);assert len({run for run,_ in values})==n
        assert n==(30 if period==3600 else 1)
        ys=[y for _,y in values];mean=statistics.mean(ys)
        half=2.045229642132703*statistics.stdev(ys)/math.sqrt(n) if n==30 else None
        result.append(dict(Model=model,SF=sf,Period_s=period,Runs=n,MeanPDR_pct=mean,CI95_lower=mean-half if half else None,CI95_upper=mean+half if half else None))
    assert len(result)==12
    for sf,expected in ((9,97.945),(7,89.690)):
        x=next(r for r in result if r['Model']=='DigitalTwin' and r['SF']==sf and r['Period_s']==3600)
        assert abs(x['MeanPDR_pct']-expected)<=0.00051
    print(json.dumps(dict(Status='PASS',Runs=len(runs),Scope='Recalculo de metricas archivadas; no nueva simulacion ni validacion fisica',Results=result),ensure_ascii=False,indent=2))
    return result
if __name__=='__main__':main()
