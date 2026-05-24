#!/bin/bash
if [[ "$OSTYPE" == "darwin"* ]]; then
    ENV_TYPE="mac"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    ENV_TYPE="lin"
else
    ENV_TYPE="?"
fi

PROMPT="%{$fg_bold[white]%} ($ENV_TYPE) %{$fg_bold[red]%}$debian_chroot%{$reset_color%} %(?:%{$fg_bold[green]%}➜ :%{$fg_bold[red]%}➜ )"
PROMPT+=' %{$fg[cyan]%}%3d%{$reset_color%} $(git_prompt_info)'

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

