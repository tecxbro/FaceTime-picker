# GitHub Actions failure report

## Summary
The `CI` workflow is failing in the `build-and-test` job during the **Core tests** step, before build and regression-scan steps run.

## Why it is happening
The failing command is:

`zsh "./Validate Core Logic.command"`

That command compiles `Tests/CoreLogicTests.swift`, and Swift fails on this line:

`let arrayJSON = """[{"id":"primary","phone_number":"+44 20 7946 0958","enabled":true}]""".data(using: .utf8)!`

Current Swift in Actions (`Apple Swift version 6.1.2`) rejects that syntax because triple-quoted strings must start and end on their own lines.

Errors shown in Actions logs:
- `multi-line string literal content must begin on a new line`
- `multi-line string literal closing delimiter must begin on a new line`

## Evidence
- Workflow: `.github/workflows/ci.yml`
- Failed step: `Core tests`
- Example failed runs:
  - `29557097942` (main)
  - `29558388498` (agent/documentation-verification)

Both runs fail with the same compiler errors in `Tests/CoreLogicTests.swift:47`.
