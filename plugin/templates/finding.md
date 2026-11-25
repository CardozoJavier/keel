One line per finding, most severe first. Return only findings with confidence 80 or higher.

```markdown
- **[Critical|Important|Minor]** (confidence <80–100>, scope <in-design|changes-design>) `<file:line>`
  <issue in one or two lines> — <suggested fix>
```

- **Severity**: Critical means wrong behavior, data loss, security, or a broken spec requirement.
  Important means a likely defect or a clear maintainability cost. Minor means style or a nit.
- **Scope**: `in-design` means it can be fixed inside the approved design (plan.md's Design
  Decision). `changes-design` means any correct fix needs a different design, data model or
  contract than the one approved.
- **Empty review**: reply with exactly `No findings (confidence ≥ 80) for lens <lens>.`
