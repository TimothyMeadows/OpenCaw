"""Actual Linux adapter -> CLI -> owned native-group cancellation.

The selected native executable is an owned sleeping shell fixture, not Blender.
No media generation, installation or production acceptance is asserted.
"""
from pathlib import Path
import json,os,signal,subprocess,sys,tempfile,time
ROOT=Path(__file__).resolve().parents[1]
def main():
    if sys.platform!='linux':
        print('NOT RUN: managed Linux signal/group test requires Linux; Windows owned jobs have separate runtime coverage.')
        return 77
    cache=ROOT/'.cache' if ROOT.name=='.hephaera' else ROOT/'.hephaera/.cache'
    evidence=cache/'tasks/hephaera-integrate-bubo-runtime/evidence/cancellation'; evidence.mkdir(parents=True,exist_ok=True)
    project=Path(tempfile.mkdtemp(prefix='p-',dir=evidence))
    scene=project/'owned.blend'; scene.write_bytes(b'OWNED EMPTY ENGINEERING SCENE; native tool is a process fixture')
    tool=project/'sleep-fixture.sh'
    tool.write_text('#!/usr/bin/env bash\nset -euo pipefail\nif [[ "${1:-}" == --version ]]; then echo "Blender 4.5.0 (OWNED PROCESS FIXTURE)"; exit 0; fi\nsleep 120 &\nprintf "%s\\n" "$!" > "'+str(project/'child.pid')+'"\nwait\n',encoding='utf-8');tool.chmod(0o700)
    command=['node',str(ROOT/'commands/lib/bubo-inspection-adapter.cjs'),str(scene),'--root',str(project),'--profile','static-asset','--blender',str(tool)]
    group=None; run=None
    def alive(pid):
        file=Path('/proc')/str(pid)/'stat'
        return file.exists() and file.read_text().split(') ',1)[1].split()[0]!='Z'
    with (project/'stdout.log').open('wb') as stdout,(project/'stderr.log').open('wb') as stderr:
        try:
            run=subprocess.Popen(command,cwd=ROOT,stdout=stdout,stderr=stderr)
            until=time.monotonic()+30
            while not (project/'child.pid').exists() and run.poll() is None and time.monotonic()<until:time.sleep(.05)
            assert (project/'child.pid').exists(),'Native process fixture did not start; inspect retained logs.'
            pid=int((project/'child.pid').read_text()); group=os.getpgid(pid)
            assert alive(pid) and group!=os.getpgrp(),'Fixture must own a separate setsid native group.'
            started=time.monotonic();run.send_signal(signal.SIGINT);exitcode=run.wait(timeout=15)
            until=time.monotonic()+5
            while alive(pid) and time.monotonic()<until:time.sleep(.05)
            assert exitcode!=0 and not alive(pid),'Adapter cancellation must fail execution and retire its actual native descendant.'
            requests=list((project/'.hephaera/.cache/tasks/blender-inspection/bubo-executions').glob('*/failure.json'))
            assert requests,'Bubo must retain managed failure evidence rather than terminate before cleanup.'
            result={'status':'pass','actualAdapter':True,'actualCli':True,'actualNativeProcessGroup':True,'nativeTool':'owned-sleeping-fixture-not-Blender','descendantRetired':True,'managedFailureReceipt':str(requests[0]),'seconds':time.monotonic()-started,'productionGeneration':False}
            (evidence/'latest.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
            print('PASS: actual Linux managed adapter cancellation retires the owned native group.')
        finally:
            if run and run.poll() is None:run.kill();run.wait()
            if group and group!=os.getpgrp():
                try:os.killpg(group,signal.SIGKILL)
                except ProcessLookupError:pass
    return 0
if __name__=='__main__':raise SystemExit(main())
