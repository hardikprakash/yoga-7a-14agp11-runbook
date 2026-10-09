# bash tab completion for the runbook entry point (./setup.sh).
#
# Completes: commands, per-module flags (audio-only flags --backend,
# --variant, --force appear only after `audio` or `all`), and flag values
# (--backend <TAB>, --variant <TAB>, and the --flag=value form) — values
# likewise only in a context that accepts the flag.
#
# Static on purpose: no dependency on the runbook's location, so keeping
# this in ~/.bashrc forever is safe. Installed by cli/setup_bash_completion.sh.

_setup_runbook() {
    local cur prev cmd i w
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Find the command (first non-flag word before the cursor), skipping
    # the value half of two-token flags so `--backend pipewire` doesn't
    # read "pipewire" as the command.
    cmd=""
    i=1
    while [ "$i" -lt "$COMP_CWORD" ]; do
        w="${COMP_WORDS[i]}"
        case "$w" in
            --backend|--variant) i=$((i + 2)); continue ;;
            -*) ;;
            *) [ -z "$cmd" ] && cmd="$w" ;;
        esac
        i=$((i + 1))
    done

    local common="--dry-run --yes --uninstall --help -h"
    local audio_flags="--backend --variant --force"
    local commands="status all help cli fingerprint audio color-profiles touchscreen hdr"

    # value completion: `--backend <TAB>` / `--variant <TAB>` — only where
    # the flag is actually accepted (audio/all), so `cli --variant <TAB>`
    # falls through to plain flag completion instead of lying.
    case "$prev" in
        --backend|--variant)
            if [ "$cmd" = audio ] || [ "$cmd" = all ]; then
                if [ "$prev" = --backend ]; then
                    COMPREPLY=( $(compgen -W "easyeffects pipewire ee pw" -- "$cur") ) || true
                else
                    COMPREPLY=( $(compgen -W "balanced detailed warm all" -- "$cur") ) || true
                fi
            else
                COMPREPLY=( $(compgen -W "$common" -- "$cur") ) || true
            fi
            return 0
            ;;
    esac

    # value completion, equals form: `--backend=<TAB>`
    case "$cur" in
        --backend=*)
            if [ "$cmd" = audio ] || [ "$cmd" = all ]; then
                _setup_runbook_values backend "${cur#--backend=}"
            else
                COMPREPLY=()
            fi
            ;;
        --variant=*)
            if [ "$cmd" = audio ] || [ "$cmd" = all ]; then
                _setup_runbook_values variant "${cur#--variant=}"
            else
                COMPREPLY=()
            fi
            ;;
        *)
            if [ -z "$cmd" ]; then
                COMPREPLY=( $(compgen -W "$commands $common" -- "$cur") ) || true
            elif [ "$cmd" = audio ] || [ "$cmd" = all ]; then
                COMPREPLY=( $(compgen -W "$common $audio_flags" -- "$cur") ) || true
            else
                COMPREPLY=( $(compgen -W "$common" -- "$cur") ) || true
            fi
            ;;
    esac
    return 0
}

# complete the value half of --flag=value, re-adding the flag prefix
_setup_runbook_values() {
    local kind="$1" prefix="$2" vals v
    case "$kind" in
        backend) vals="easyeffects pipewire ee pw" ;;
        variant) vals="balanced detailed warm all" ;;
        *)       vals="" ;;
    esac
    COMPREPLY=()
    for v in $(compgen -W "$vals" -- "$prefix" || true); do
        COMPREPLY+=("--$kind=$v")
    done
}

complete -o default -F _setup_runbook setup.sh ./setup.sh
