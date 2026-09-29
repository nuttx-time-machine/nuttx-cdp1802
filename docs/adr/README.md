# Architecture Decision Records

ADRs are numbered sequentially (`NNNN-title.md`) and never deleted. A superseded
ADR stays in place and is marked "Superseded by NNNN".

Every ADR uses this structure:

```
# NNNN — Title
Status: Proposed | Accepted | Superseded by NNNN
Date: YYYY-MM-DD
Step: step-NN

## Context
## Options considered
## Decision
## Consequences
## How to revisit
```

"Accepted" means Alan reviewed the ADR, or it was implicitly accepted when a
step tag that depends on it was not objected to. The agent writes new ADRs as
"Proposed (agent)".

| # | Title | Status |
|---|-------|--------|
| [0001](0001-naming.md) | Architecture, chip and board naming | Proposed (agent) |
| [0002](0002-toolchain-build.md) | Toolchain build method; mikpe libc for validation only | Proposed (agent) |
