# Camera and lighting contract

## Camera

Record camera identity, projection, focal length or orthographic scale, sensor, clipping, transform, aspect ratios, safe areas, depth of field, motion policy, and subject. Required views use stable camera identities rather than current viewport state.

## Lighting

Record rig name, light types, transforms, energy, size, color, shadow policy, environment contribution, reflection strategy, volume settings, and target engine. Lock scene color management and exposure before comparing revisions.

## Readability review

Evaluate focal hierarchy, silhouette separation, material differentiation, depth cues, navigation or action visibility, facial readability, highlight clipping, crushed values, flicker, shadow noise, and accessibility in the final viewing context.

Deliver a neutral diagnostic view and representative final views. If multiple aspect ratios are required, define compositions or safe crops for each instead of assuming a center crop.
