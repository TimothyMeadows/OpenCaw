# Dependency license acceptance

OpenCaw's code license does not replace the licenses of inference engines or model
weights. The shipped toolchain deliberately sets every `licenseAccepted` flag to
`false`. Installation requires an explicit decision from the installing person or
an authorized representative of their organization. Acceptance by OpenCaw's
maintainer does not accept terms for unrelated users or organizations.

DINOv3's agreement governs use as well as distribution of its model materials.
Its redistribution conditions cover the materials and their derivatives; it does
not explicitly apply those conditions to every generated mesh or texture. Merely
receiving an exported asset is different from receiving or running the weights.
Do not describe exported assets as automatically granting rights to inputs or to
third-party content.

When distributing covered model materials, include the applicable agreement and
retain required notices. OpenCaw does not bundle weights. Pinned license files and
their hashes are listed in `toolchain.json`, alongside the corresponding models.
Keep any accepted toolchain copy and acceptance evidence local to the installation
or task. Do not ship a maintainer's acceptance as the default for everyone.

Sources:
- [DINOv3 agreement](https://github.com/facebookresearch/dinov3/blob/main/LICENSE.md)
- [Pinned model distribution and notices](https://huggingface.co/raven38/pixal3d-sv-q8_0-v1/tree/46d399ac986f45a0d7f5b1ca5058614d8729a131)
- [BiRefNet license](https://github.com/ZhengPeng7/BiRefNet/blob/main/LICENSE)
