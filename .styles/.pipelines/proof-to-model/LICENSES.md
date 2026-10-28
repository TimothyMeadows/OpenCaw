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

The default toolchain selects the separate `pixal3d-q8_0 v1` multiview set at
immutable revision `1c4f4bdddb5fef1dc5efa512d4b88e899b10bd91`. Its nine model
files total 8,091,975,360 bytes. Four MV flow files account for 5,856,897,248
additional bytes when verified shared Q8 models already exist. Reusing those
shared files requires checking their actual hashes and preserving the MV set's
own identity and license records; filenames do not establish compatibility.
F16 and Q8 sets can contain different bytes under the same shared filenames.
BiRefNet remains an explicitly pinned dependency for actual background removal.

`toolchain.single-view-diagnostic.json` preserves the previous SV pins for an
explicit diagnostic workflow only. Its installation or a prior scoped test's
approval does not authorize downloading the new MV flows, accepting terms for a
different installation, or generating proof images. Every shipped acceptance
flag remains false. The new MV flows retain the MIT/DINOv3 split; DINOv3's text
is unchanged, while each model set retains its own per-file license index.

The pinned runtime accepts six camera-bound views, but its MV checkpoints were
validated upstream with four. Neither the model manifest nor the license records
constitute evidence of a successful six-view reconstruction or production quality.

Sources:
- [DINOv3 agreement](https://github.com/facebookresearch/dinov3/blob/main/LICENSE.md)
- [Pinned model distribution and notices](https://huggingface.co/raven38/pixal3d-sv-q8_0-v1/tree/46d399ac986f45a0d7f5b1ca5058614d8729a131)
- [Pinned multiview models and notices](https://huggingface.co/raven38/pixal3d-q8_0-v1/tree/1c4f4bdddb5fef1dc5efa512d4b88e899b10bd91)
- [BiRefNet license](https://github.com/ZhengPeng7/BiRefNet/blob/main/LICENSE)
