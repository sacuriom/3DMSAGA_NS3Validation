"""Inspect a local ns-3 installation without modifying it."""
from pathlib import Path
import argparse,subprocess,json,hashlib,sys
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--ns3-root',type=Path,required=True);a=p.parse_args()
 root=a.ns3_root.resolve();result={};ok=True
 for name,folder,expected in [('ns3',root,'f576896f5c2387874f49be221c13ae371e4f8f86'),('lorawan',root/'contrib/lorawan','67bcaefdeb45d367010e09a80083b9a0527f766b')]:
  info={'Path':str(folder),'ExpectedCommit':expected}
  if not folder.is_dir():info['Error']='Directory unavailable';ok=False
  else:
   for field,command in [('Commit',['git','rev-parse','HEAD']),('Worktree',['git','status','--porcelain'])]:
    r=subprocess.run(command,cwd=folder,capture_output=True,text=True);info[field]=r.stdout.strip();info[field+'ReturnCode']=r.returncode
   info['CommitMatches']=info.get('Commit')==expected;ok=ok and info['CommitMatches'] and info['WorktreeReturnCode']==0
  result[name]=info
 source=root/'scratch/validacion_lorawan_v02.cc'
 result['SourceInstalled']=source.is_file()
 if source.is_file():
  result['SourceSHA256']=hashlib.sha256(source.read_bytes()).hexdigest()
  expected='6d4a9eebe205ef8a6ac7321e54eba968b2518d0307faf7404f2de6911937ad07'
  result['SourceMatches']=result['SourceSHA256']==expected;ok=ok and result['SourceMatches']
 result['Scope']='Inspection only; worktree differences require review; no build or simulation performed'
 result['ExpectedCommitsAvailable']=ok
 print(json.dumps(result,indent=2));return 0 if ok else 1
if __name__=='__main__':sys.exit(main())
