# JITerm shell defaults
export EDITOR=vim
export PAGER=less
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
case "$TERM" in ""|vt100|vt102|linux|dumb) export TERM=xterm-256color ;; esac

if [ -n "$BASH_VERSION" ]; then
    PS1='\[\e[1;32m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ '
    shopt -s checkwinsize histappend
    HISTSIZE=5000
    [ -r /usr/share/bash-completion/bash_completion ] && . /usr/share/bash-completion/bash_completion
fi

alias ls='ls --color=auto'
alias ll='ls -lah'
alias la='ls -A'
alias grep='grep --color=auto'
alias py='python3'
alias pip='pip3'

# Узнать реальный размер окна у терминала (после повторного входа размер tty сбрасывается)
if [ -t 0 ] && command -v resize >/dev/null 2>&1; then
    case "$(stty size 2>/dev/null)" in "0 0"|"") resize >/dev/null 2>&1 ;; esac
fi
