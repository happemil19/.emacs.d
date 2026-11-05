# Личные хуки: global → per-repo (вызываются из командных хуков после их логики).
# Исходник: .githooks/run-personal.sh; копия: make hooks → .git/hooks/run-personal.sh
#
# Использование:
#   source "$(dirname "$0")/run-personal.sh"
#   run_personal_hooks pre-commit "$@"

run_personal_hooks() {
  local hook_name="$1"
  shift
  local root repo_id user_hooks global_hook local_hook

  root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0
  repo_id="$(basename "${root}")"
  user_hooks="${HOME}/.config/git/hooks"
  global_hook="${user_hooks}/global/${hook_name}"
  local_hook="${user_hooks}/per-repo/${repo_id}/${hook_name}"

  if [[ -x "${global_hook}" ]]; then
    echo "${hook_name}: личный global…"
    "${global_hook}" "$@"
  fi
  if [[ -x "${local_hook}" ]]; then
    echo "${hook_name}: личный per-repo (${repo_id})…"
    "${local_hook}" "$@"
  fi
}
