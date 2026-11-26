# Vendored sources

keel has no runtime dependency on these upstreams (constitution III). This directory holds the
files keel copies (Spec Kit scripts and templates, used at runtime) and pristine copies of the
files keel's own skills and agents adapt (kept so upstream changes stay diffable). In-place edits
are listed in `CHANGELOG.md`.

| Upstream | Repository | Version | License | Copyright |
|---|---|---|---|---|
| speckit | https://github.com/github/spec-kit (PyPI `specify-cli`) | 0.8.4.dev0 | MIT (`speckit/LICENSE`) | GitHub, Inc. |
| superpowers | https://github.com/obra/superpowers (Claude plugin `superpowers@claude-plugins-official`) | 7.0.2 | MIT (`superpowers/LICENSE`) | Jesse Vincent |
| feature-dev | https://github.com/anthropics/claude-plugins-official (plugin `feature-dev`) | 1.0.1 | Apache-2.0 (`feature-dev/LICENSE`) | Anthropic |

## Files

### speckit (used at runtime)

- `speckit/LICENSE`
- `speckit/scripts/bash/common.sh`: verbatim
- `speckit/scripts/bash/check-prerequisites.sh`: verbatim
- `speckit/templates/spec-template.md`: edited (CHANGELOG.md)
- `speckit/templates/plan-template.md`: edited (CHANGELOG.md)
- `speckit/templates/tasks-template.md`: edited (CHANGELOG.md)
- `speckit/templates/checklist-template.md`: verbatim
- `speckit/templates/constitution-template.md`: verbatim

- `speckit/commands/`: verbatim; pristine sources of keel's step skills (constitution, specify, clarify, plan, tasks, analyze, implement), which adapt them

Not vendored: `setup-plan.sh` (replaced by keel's step skills) and `create-new-feature.sh` (needs
the network; replaced by `keel-branch`).

### superpowers (pristine sources of keel's adapted discipline skills and agent prompts)

- `superpowers/LICENSE`
- `superpowers/skills/test-driven-development/`: adapted by `skills/tdd`
- `superpowers/skills/systematic-debugging/`: adapted by `skills/debug`
- `superpowers/skills/verification-before-completion/`: adapted by `skills/verify`
- `superpowers/skills/receiving-code-review/`: adapted by `skills/respond-review`
- `superpowers/skills/requesting-code-review/`: severity calibration in `agents/code-reviewer`
- `superpowers/skills/subagent-driven-development/`: adapted by `skills/implement`, `agents/implementer`, `agents/task-reviewer`

### feature-dev (pristine sources of keel's adapted agents; Apache-2.0 §4(b) change notices in each derivative)

- `feature-dev/LICENSE`
- `feature-dev/agents/code-explorer.md`: adapted by `agents/explorer`
- `feature-dev/agents/code-architect.md`: adapted by `agents/architect`
- `feature-dev/agents/code-reviewer.md`: adapted by `agents/code-reviewer`
