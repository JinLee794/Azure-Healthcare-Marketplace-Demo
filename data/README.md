Prior-auth skill data is split by purpose to avoid retrieval/evaluation leakage:

- `policies/`: Canonical policy corpus for indexing and retrieval (RAG input only).
- `sample_cases/`: Demo/test fixtures for interactive runs and smoke tests.
- `cases/`: Ground truth and evaluation outputs for benchmarking.
- `pdfs/`: Pre-rendered artifacts used by dataset prep and validation flows.

Guidelines:

- Do not index `sample_cases/` or `cases/` content into the policy retrieval store.
- Keep indexed policy corpus restricted to `policies/`.
