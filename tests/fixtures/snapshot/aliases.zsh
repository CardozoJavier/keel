# Excerpt of oh-my-zsh's git plugin aliases as they appear in Claude Code's shell snapshot.
git_current_branch() { git rev-parse --abbrev-ref HEAD }
alias -- gp='git push'
alias -- gpsup='git push --set-upstream origin $(git_current_branch)'
alias -- ggpush='git push origin "$(git_current_branch)"'
ggp() { git push origin "${*:-$(git_current_branch)}" }
