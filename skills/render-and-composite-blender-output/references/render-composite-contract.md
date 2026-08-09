# Render and composite contract

## Render settings

Declare engine, device class, resolution, percentage, frame range, fps, sampling, denoising, transparency, motion blur, depth of field, color transform, exposure, output format, bit depth, compression, alpha mode, and estimated time/storage budgets.

## Passes and composite

Name required passes and their consumers. Declare premultiplied or straight alpha, working color space, view transform, masks, cryptomatte use, depth normalization, glare/bloom policy, and missing-input behavior. Node groups have stable names and no undeclared external file inputs.

## Delivery checks

Render representative first, middle, last, high-motion, high-contrast, transparency, and effect-heavy frames before a full sequence. Verify frame numbering, continuity, noise, edge halos, color, alpha, temporal stability, audio duration when applicable, and exact output count.

Renders stay staged under the media contract until accepted. Record the reviewed scene hash, settings, representative frames, full output inventory, and output hashes.
