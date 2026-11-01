# Original action fixtures

Use the already-installed Blender 4.5 LTS:

```powershell
& 'C:/Program Files/Blender Foundation/Blender 4.5/blender.exe' --factory-startup --background --disable-autoexec --python-exit-code 1 --python tests/fixtures/model-action/create_assets.py -- --output .hephaera/.cache/tasks/model-to-action/fixture-project
```

The new output directory must remain inside this checkout and contain no previous artifacts. The helper reuses Hephaera's original controlled model-animation geometry and native test authoring helpers on local copies. It authors eight real skinned one-second clips and a bone-child hand socket, plus independent articulated-car and rigid-ship clip packages. It imports no third-party art, animation or Adobe integration.

`fixtures.json` records the humanoid source GLB/package, source recipe, action recipe and a compiled plan, plus equivalent mechanical package pointers. The recipe contains dance, combination and charge/cast actions. `compile_fixture` is an independent test oracle; production compilation belongs to the native Hephaera CLI. Engine metadata declares controlled Three.js test intent and grants no human/runtime acceptance. Any synthetic approval used by integration tests must remain explicitly labeled and confined to this fixture project.

Run `python tests/test-model-action-blender.py` for bounded actual Blender source authoring, composition, GLB re-import, full technical review and failure checks. Evidence remains under the task cache; `blender-action-latest.txt` points to the latest completed setup, whose `commands.json` retains process exit codes and logs. A passing setup pointer alone is not the full suite result.
