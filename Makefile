.PHONY: help hooks

help:
	@echo "Targets:"
	@echo "  make hooks  - .githooks/ → .git/hooks/ + personal stub'ы без командного тёзки"

# Копия .githooks/ → .git/hooks/ (как в center-dcs). Без core.hooksPath.
# Затем stub'ы для personal global/per-repo, у которых нет одноимённого .githooks/.
hooks:
	@test -d .githooks || (echo "hooks: нет каталога .githooks/" >&2; exit 1)
	@test -d .git/hooks || (echo "hooks: нет .git/hooks (не git-репозиторий?)" >&2; exit 1)
	@installed=0; \
	for src in .githooks/*; do \
	  [ -f "$$src" ] || continue; \
	  base=$$(basename "$$src"); \
	  case "$$base" in \
	    README|README.*|*.md|*~|*.bak|*.orig|*.swp|*.tmp) continue ;; \
	  esac; \
	  dst=".git/hooks/$$base"; \
	  installed=1; \
	  if [ -f "$$dst" ] && cmp -s "$$src" "$$dst"; then \
	    case "$$base" in \
	      *.sh) ;; \
	      *) chmod +x "$$dst" ;; \
	    esac; \
	    echo "hooks: $$base уже актуален"; \
	    continue; \
	  fi; \
	  if [ -f "$$dst" ]; then \
	    echo "hooks: $$dst отличается от $$src — перезаписываю"; \
	    echo "       сравнить: diff -u $$src $$dst"; \
	  fi; \
	  cp -f "$$src" "$$dst"; \
	  case "$$base" in \
	    *.sh) ;; \
	    *) chmod +x "$$dst" ;; \
	  esac; \
	  echo "hooks: установлен $$base"; \
	done; \
	if [ "$$installed" -eq 0 ]; then \
	  echo "hooks: в .githooks/ нет файлов для установки" >&2; \
	  exit 1; \
	fi
	@test -f .git/hooks/run-personal.sh || (echo "hooks: нет .git/hooks/run-personal.sh" >&2; exit 1)
	@repo_id=$$(basename "$$(git rev-parse --show-toplevel)"); \
	user_hooks="$${HOME}/.config/git/hooks"; \
	for dir in "$${user_hooks}/global" "$${user_hooks}/per-repo/$${repo_id}"; do \
	  [ -d "$$dir" ] || continue; \
	  for src in "$$dir"/*; do \
	    [ -f "$$src" ] || continue; \
	    base=$$(basename "$$src"); \
	    case "$$base" in \
	      README|README.*|*.md|.keep|*~|*.bak|*.orig|*.swp|*.tmp|*.sh) continue ;; \
	    esac; \
	    if [ -f ".githooks/$$base" ]; then continue; fi; \
	    dst=".git/hooks/$$base"; \
	    stub=$$(mktemp); \
	    printf '%s\n' \
	      '#!/usr/bin/env bash' \
	      "# Personal-only stub (make hooks): нет .githooks/$$base" \
	      'source "$$(dirname "$$0")/run-personal.sh"' \
	      "run_personal_hooks $$base \"\$$@\"" \
	      'exit 0' \
	      > "$$stub"; \
	    if [ -f "$$dst" ] && cmp -s "$$stub" "$$dst"; then \
	      rm -f "$$stub"; \
	      echo "hooks: personal stub $$base уже актуален"; \
	      continue; \
	    fi; \
	    if [ -f "$$dst" ]; then \
	      echo "hooks: $$dst отличается — ставлю personal stub $$base"; \
	    fi; \
	    cp -f "$$stub" "$$dst"; \
	    chmod +x "$$dst"; \
	    rm -f "$$stub"; \
	    echo "hooks: установлен personal stub $$base"; \
	  done; \
	done
