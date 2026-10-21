#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias ll='ls -AlhF --color=auto'
alias llt='ls -AlhFtr --color=auto'
alias codene='code . & exit 0'
alias zedex='zeditor . & exit 0'
alias n='nvim .'

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# Force multiline commands to save as a single history entry
shopt -s cmdhist
# Preserve the original literal newlines instead of replacing them with semicolons
shopt -s lithist

#export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket"
export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/gcr/ssh"

export PATH=$PATH:$HOME/.local/bin

PS1='[\u@\h \W]\$ '
export VOLTA_HOME="$HOME/.volta"
export PATH="$VOLTA_HOME/bin:$PATH"

export PATH=$PATH:$HOME/apps/go/bin
export PATH=$PATH:$HOME/go/bin

# Android SDK cfg
export ANDROID_HOME=$HOME/Android/Sdk
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin

#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

export PATH="$HOME/flutter/bin:$PATH"

export CHROME_EXECUTABLE=/usr/bin/google-chrome-stable
export ANDROID_AVD_HOME=$HOME/.config/.android/avd
export QT_QPA_PLATFORM="wayland;xcb"

# opencode
export PATH=$HOME/.opencode/bin:$PATH

# Machine-specific aliases, server addresses, secrets: keep them out of git
[[ -f ~/.bashrc.local ]] && source ~/.bashrc.local
