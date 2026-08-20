'use strict';

const fs = require('fs');

module.exports = {
  chromium: {
    async launch(options) {
      if (options?.chromiumSandbox !== true || options?.headless !== true) throw new Error('sandboxed headless launch was not requested');
      return {
        async newContext(contextOptions) {
          if (contextOptions?.serviceWorkers !== 'block') throw new Error('service workers were not blocked');
          let profile;
          return {
            async newPage() {
              return {
                async route() {},
                async goto(url) {
                  const response = await fetch(url);
                  if (!response.ok || !(await response.text()).includes('createCodeCharacterEvidenceAdapter')) {
                    throw new Error('loopback evidence page was not served');
                  }
                },
                async evaluate(callback, argument) {
                  const source = callback.toString();
                  if (source.includes('__opencawEvidence.start')) {
                    profile = argument.profile;
                    return true;
                  }
                  if (source.includes('__opencawEvidence.capture') || source.includes('__opencawEvidence.stop')) return undefined;
                  if (source.includes('__opencawEvidence.sample')) {
                    const attachmentGaps = profile.structure.attachments.map(({ part, host }) => ({ part, host, gapRatio: 0 }));
                    const symmetry = profile.structure.symmetryGroups.map(({ id }) => ({ id, deviationRatio: 0 }));
                    return {
                      structure: {
                        parts: profile.structure.parts.map(({ id, parent }) => ({ id, parent })),
                        joints: profile.structure.joints.map(({ id }) => id),
                        sockets: profile.structure.sockets.map(({ id }) => id),
                        colliders: profile.structure.colliders.map(({ id }) => id),
                        minimumY: 0,
                        groundY: 0,
                        height: 1,
                        attachmentGaps,
                        symmetry
                      },
                      motion: {
                        mode: profile.motion.mode,
                        skeletonId: profile.motion.skeletonId,
                        maxInfluencesPerVertex: profile.motion.maxInfluencesPerVertex,
                        roles: profile.motion.requiredRoles,
                        contacts: profile.motion.clips.flatMap((clip) => clip.contacts.map((id) => ({ id, errorRatio: 0 }))),
                        movingPartCount: profile.motion.mode === 'static' ? 0 : 1
                      },
                      runtime: {
                        constructionHashes: Array(argument.constructionRuns).fill('stable-browser-capture'),
                        lifecycle: Array.from({ length: argument.lifecycleCycles }, (_, index) => ({ cycle: index + 1, resourceDelta: 0, staleCallbacks: 0 })),
                        actors: argument.actorCount,
                        metrics: {
                          triangles: 0, drawCalls: 0, materials: 0, textures: 0,
                          bones: 0, clips: profile.motion.clips.length, shaderVariants: 0, textureBytes: 0,
                          cpuMilliseconds: null, gpuMilliseconds: null
                        }
                      }
                    };
                  }
                  throw new Error(`Unexpected browser evaluation: ${source}`);
                },
                locator(selector) {
                  if (selector !== '#stage') throw new Error('unexpected screenshot target');
                  return {
                    async screenshot({ path, animations }) {
                      if (animations !== 'disabled') throw new Error('capture animations were not disabled');
                      fs.writeFileSync(path, Buffer.from('deterministic-test-image'));
                    }
                  };
                }
              };
            }
          };
        },
        async close() {}
      };
    }
  }
};
