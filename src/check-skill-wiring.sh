#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)
# SPDX-License-Identifier: MPL-2.0

# check-skill-wiring.sh — Verifica el cableado de las skills ocultas del catálogo.
#
# El catálogo de skills se inyecta en CADA request a TODOS los agentes: cada skill
# anunciada cuesta ~500 tok fijos por turno. Por eso las skills de dominio llevan
# en su frontmatter `metadata.opencode/autoinvoke: false`: dejan de anunciarse
# (siguen registradas y se pueden cargar por ID). El precio es que el agente solo
# las encuentra si su .md las nombra explícitamente.
#
# Este script falla si una skill oculta no está nombrada en el .md de su agente
# dueño, o si el `name:` del frontmatter no coincide con la carpeta.
#
# Uso: src/check-skill-wiring.sh   (exit 0 = todo cableado, exit 1 = fallas)

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTS_DIR="${ROOT}/src/agents"
STANDALONE_DIR="${ROOT}/src/skills"

# Frontmatter YAML: líneas entre el primer `---` y el siguiente.
frontmatter() {
  awk 'NR==1 && /^---$/ {inside=1; next} inside && /^---$/ {exit} inside {print}' "$1"
}

# Valor de un campo escalar del frontmatter, sin comillas ni espacios sobrantes.
frontmatter_value() {
  frontmatter "$1" | sed -n "s/^${2}:[[:space:]]*//p" | head -1 | tr -d '\r' | sed 's/[[:space:]]*$//; s/^["'\'']//; s/["'\'']$//'
}

is_hidden() {
  frontmatter "$1" | grep -qE '^[[:space:]]*opencode/autoinvoke:[[:space:]]*false[[:space:]]*$'
}

hidden=0
announced=0
failures=0

report_failure() {
  printf '[ERROR] %s\n' "$1" >&2
  failures=$((failures + 1))
}

# Recorre un SKILL.md: valida name/folder y, si está oculta, el .md del dueño.
check_skill() {
  local file="$1" scope="$2"
  local folder name owner_file agent_id

  folder="$(basename "$(dirname "$file")")"
  name="$(frontmatter_value "$file" name)"

  if [[ "$name" != "$folder" ]]; then
    report_failure "${file#"$ROOT"/}: name '${name:-<missing>}' does not match folder '${folder}'"
  fi

  if ! is_hidden "$file"; then
    announced=$((announced + 1))
    return 0
  fi
  hidden=$((hidden + 1))

  # Skills standalone (src/skills/<x>) no tienen agente dueño: se anuncian por
  # defecto, así que ocultarlas es un error de diseño, no un caso a validar.
  if [[ "$scope" == "standalone" ]]; then
    printf '[WARN] src/skills/%s: hidden (autoinvoke: false) but has no owner agent; no wiring to check\n' "$folder"
    return 0
  fi

  agent_id="$3"
  owner_file="${AGENTS_DIR}/${agent_id}/${agent_id}.md"
  if [[ ! -f "$owner_file" ]]; then
    report_failure "skill '${name}' is hidden but its owner file ${owner_file#"$ROOT"/} does not exist"
    return 0
  fi
  if ! grep -qF -- "$name" "$owner_file"; then
    report_failure "skill '${name}' is hidden but ${owner_file#"$ROOT"/} never names it (load by ID)"
  fi
}

for file in "${AGENTS_DIR}"/*/skills/*/SKILL.md; do
  [[ -f "$file" ]] || continue
  rest="${file#"${AGENTS_DIR}/"}"
  check_skill "$file" "agent" "${rest%%/*}"
done

for file in "${STANDALONE_DIR}"/*/SKILL.md; do
  [[ -f "$file" ]] || continue
  check_skill "$file" "standalone"
done

if [[ "$failures" -gt 0 ]]; then
  printf '[ERROR] Skill wiring check failed: %d problem(s).\n' "$failures" >&2
  exit 1
fi

printf 'OK: %d hidden skills, %d announced skills, all wired.\n' "$hidden" "$announced"
