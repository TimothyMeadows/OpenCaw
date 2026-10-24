# Native asset production primitives

.NET10 base-library workspace guards, atomic persistence, streaming hashes, asset locks, append-only audit records and bounded owned native process execution. These are execution mechanics, not an operating-system sandbox or a model/animation producer.

Proof-to-model retains its public workspace/process interfaces through compatibility facades. Model-to-animation consumes this assembly directly; neither workflow depends on the other's Pipeline.

Owned process cleanup requires Windows job objects or Linux with `/usr/bin/setsid`. Other platforms, including macOS, fail before process launch until an audited containment implementation exists. This is process lifetime management, not an OS sandbox. Windows installations must also keep project and asset paths short enough for their installed native tools; OpenCaw does not change OS path policies.

Workspace guards originate from the audited Bubo MIT adaptation pinned to f597fcab07f0dc3e1c4709f23fae4a028cf04373. Attribution and the selected original LICENSE/source remain in ../proof-to-model/vendor/bubo/ and ../proof-to-model/REUSE.md. The original Bubo application, inference providers and Docker are not dependencies. Owned process-tree cleanup and the bounded runner were independently implemented for OpenCaw and are reused here.
