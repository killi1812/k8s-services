#!/usr/bin/env bash
set -euo pipefail

# Allow passing a target stack directory as $1, or default to the directory of this script
STACK_DIR="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}" && pwd)"
ENV_FILE="${STACK_DIR}/.env"

shopt -s nullglob

echo "==> Phase 1: Applying pre-environment manifests (00-09)..."
for file in "${STACK_DIR}"/0[0-9]-*.yaml "${STACK_DIR}"/0[0-9]-*.yml; do
  echo "  -> Applying $(basename "${file}")"
  k3s kubectl apply -f "${file}"
done

echo "==> Phase 2: Seeding environment (10-environment)..."
for env_manifest in "${STACK_DIR}"/10-environment.yaml "${STACK_DIR}"/10-environment.yml "${STACK_DIR}"/10-*.yaml "${STACK_DIR}"/10-*.yml; do
  [[ -e "${env_manifest}" ]] || continue
  if [[ "${PROCESSED_10:-}" == "${env_manifest}" ]]; then
    continue
  fi
  PROCESSED_10="${env_manifest}"

  if [[ ! -f "${ENV_FILE}" ]]; then
    echo "Error: ${ENV_FILE} not found, but $(basename "${env_manifest}") requires environment seeding." >&2
    exit 1
  fi

  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a

  echo "  -> Seeding $(basename "${env_manifest}") with ${ENV_FILE} via envsubst"
  envsubst < "${env_manifest}" | k3s kubectl apply -f -
done

echo "==> Phase 3: Applying application manifests (>10)..."
for file in "${STACK_DIR}"/[1-9][0-9]-*.yaml "${STACK_DIR}"/[1-9][0-9]-*.yml; do
  base="$(basename "${file}")"
  if [[ "${base}" == 10-* ]]; then
    continue
  fi
  echo "  -> Applying ${base}"
  k3s kubectl apply -f "${file}"
done

echo "==> Deployment complete!"
