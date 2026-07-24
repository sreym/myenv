#!/bin/bash
unalias g 2>/dev/null
g() {
    if [[ -z "$1" ]]; then
        nvim
    elif [[ "$1" == *":"* ]]; then
        local file="${1%%:*}"
        local line="${1##*:}"
        nvim "+$line" "$file"
    else
        nvim "$1"
    fi
}

export SHOW_LINE_NUMBERS=yes

export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git --exclude CVS --exclude "build.*"'

eval "$(zoxide init zsh)"

# Set up PROMPT
if [[ "$OSTYPE" == "darwin"* ]]; then
    ENV_TYPE="mac"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    ENV_TYPE="lin"
else
    ENV_TYPE="?"
fi

if [[ "$ZLXC" == "1" ]]; then
    ENV_TYPE+=", zlxc $(hostname)"
fi

PROMPT="%{$fg_bold[white]%} ($ENV_TYPE) %{$fg_bold[red]%}$debian_chroot%{$reset_color%} %(?:%{$fg_bold[green]%}➜ :%{$fg_bold[red]%}➜ )"
PROMPT+=' %{$fg[cyan]%}%3d%{$reset_color%} $(git_prompt_info)'

# Auto-update this repo at most once per week (runs in background)
_myenv_dir="${0:A:h}"
_myenv_stamp="${HOME}/.cache/myenv_last_update"
mkdir -p "${HOME}/.cache" 2>/dev/null
# if [[ ! -f "$_myenv_stamp" ]] || (( $(date +%s) - $(stat -f %m "$_myenv_stamp" 2>/dev/null || stat -c %Y "$_myenv_stamp" 2>/dev/null || echo 0) > 604800 )); then
#    touch "$_myenv_stamp"
#    (cd "$_myenv_dir" && git pull --quiet --ff-only) &!
# fi
unset _myenv_dir _myenv_stamp

alias bat="batcat"
