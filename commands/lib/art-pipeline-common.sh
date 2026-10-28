#!/usr/bin/env bash

art_pipeline_normalize() {
  local raw="${1:-}"
  local normalized="${raw//-/_}"
  normalized="${normalized// /_}"
  normalized="${normalized^^}"
  case "$normalized" in
    CLOUD|IMAGEGEN|IMAGE_GEN) printf '%s\n' 'CLOUD' ;;
    LOCAL|COMFYUI|COMFY_UI) printf '%s\n' 'LOCAL' ;;
    PROOF_TO_MODEL|2D_TO_3D) printf '%s\n' 'PROOF_TO_MODEL' ;;
    CSS|CSS3|CSS_VECTOR|VECTOR) echo 'CSS3 is retired. Select PROOF_TO_MODEL for 2D-to-3D assets, or CODE/BLENDER explicitly; regenerate STYLE.md with --pipeline PROOF_TO_MODEL. CSS/SVG interface work remains available outside art pipelines.' >&2; return 1 ;;
    CODE|THREE|THREEJS|THREE_JS) printf '%s\n' 'CODE' ;;
    BLEND|BLENDER|BPY) printf '%s\n' 'BLENDER' ;;
    *) return 1 ;;
  esac
}

art_pipeline_contract_relative_path() {
  case "$1" in
    CLOUD) printf '%s\n' '.styles/.pipelines/cloud/PIPELINE.md' ;;
    LOCAL) printf '%s\n' '.styles/.pipelines/local/PIPELINE.md' ;;
    PROOF_TO_MODEL) printf '%s\n' '.styles/.pipelines/proof-to-model/PIPELINE.md' ;;
    CODE) printf '%s\n' '.styles/.pipelines/code/PIPELINE.md' ;;
    BLENDER) printf '%s\n' '.styles/.pipelines/blender/PIPELINE.md' ;;
    *) return 1 ;;
  esac
}

art_pipeline_all() {
  printf '%s\n' CLOUD LOCAL PROOF_TO_MODEL CODE BLENDER
}

art_pipeline_sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$file" | awk '{print $NF}'
  else
    echo 'A SHA-256 implementation is required.' >&2
    return 1
  fi
}
