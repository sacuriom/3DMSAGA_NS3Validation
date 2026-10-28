"""Plan portable de una corrida; ejecutar solo con --execute y entorno fijado."""
from pathlib import Path
import argparse,json,hashlib,subprocess,shutil,sys
ROOT=Path(__file__).resolve().parents[1];A=ROOT/'experiments/ns3_archive'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--ns3-root',type=Path,required=True);p.add_argument('--binary',type=Path,help='Ruta explicita si el perfil cambia el nombre del ejecutable');p.add_argument('--run-index',type=int,default=0);p.add_argument('--execute',action='store_true');args=p.parse_args()
    runs=sorted((A/'produccion').rglob('run_manifest.json'));assert 0<=args.run_index<len(runs)
    manifest=json.loads(runs[args.run_index].read_text());identity=manifest['identity'];options=identity['options']
    matrices={sha(x):x for x in (A/'inputs').glob('Matrix_*.csv')};matrix=matrices[identity['matrix_sha256']]
    assert sha(A/'validacion_lorawan_v02.cc')==identity['source_sha256']
    output=ROOT/'outputs'/f'run_{args.run_index:03d}';assert not output.exists(),'Salida ya existe; conservarla y elegir otra ubicacion/version'
    nsroot=args.ns3_root.resolve();source=nsroot/'scratch/validacion_lorawan_v02.cc'
    binary=args.binary.resolve() if args.binary else nsroot/'build/scratch/ns3-dev-validacion_lorawan_v02-default'
    command=[str(binary),f'--matrix={matrix.resolve()}',f'--gatewaysCsv={(A/"gateways.csv").resolve()}',f'--output={output.resolve()}']
    command += [f'--{k}={int(v) if isinstance(v,bool) else v}' for k,v in options.items()]
    plan=dict(ArchivedRun=runs[args.run_index].relative_to(ROOT).as_posix(),SourceSHA256=identity['source_sha256'],InstallSource=str(source),Command=command,Execute=args.execute)
    print(json.dumps(plan,indent=2))
    if not args.execute:return
    assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=nsroot,text=True).strip()=='f576896f5c2387874f49be221c13ae371e4f8f86'
    assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=nsroot/'contrib/lorawan',text=True).strip()=='67bcaefdeb45d367010e09a80083b9a0527f766b'
    if source.exists():assert sha(source)==identity['source_sha256'],'No sustituir una fuente diferente'
    else:source.parent.mkdir(exist_ok=True);shutil.copyfile(A/'validacion_lorawan_v02.cc',source)
    subprocess.run([sys.executable,str(nsroot/'ns3'),'build','validacion_lorawan_v02'],cwd=nsroot,check=True)
    assert Path(command[0]).is_file(),'Comprobar nombre/ruta del ejecutable de esta compilacion'
    output.parent.mkdir(exist_ok=True)
    subprocess.run(command,cwd=nsroot,check=True)
    out=dict(Plan=plan,RebuiltBinarySHA256=sha(Path(command[0])),Note='Nuevo ejecutable registrado; no se exige igualdad binaria entre compiladores')
    (output/'replay_manifest.json').write_text(json.dumps(out,indent=2),encoding='utf-8')
if __name__=='__main__':main()
