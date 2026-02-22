# SMRK-GUEGAP Probe — ICP v2 (Motoko)

This repository is a **Motoko-first learning implementation** of the **v2 ICP-only screening** architecture:

- **registry_canister**: on-chain job registry + audit log (canonical JSON, `run_id`, `commit_hash`)
- **compute_canister**: pulls jobs from registry and writes back results

> Note (important): This Motoko version focuses on **on-chain orchestration + audit**.
> A full **dense Hermitian eigensolver for N=256** in pure Motoko is intentionally **not** included here (performance/complexity).
> The `compute_canister` currently performs a **deterministic screening stub** that is easy to verify and learn from.
> In the next repo/step we’ll implement the real numeric kernel in **Rust CDK** and keep this registry API unchanged.

## Quick start

1) Install DFINITY SDK (dfx), then:

```bash
dfx start --background
dfx deploy
```

2) Submit a job:

```bash
dfx canister call registry_canister submit_job '(record { input = blob "\7b\7d" })'
```

The response is a `run_id` (hex string).

3) Trigger compute:

```bash
dfx canister call compute_canister run_screening '(record { run_id = "<RUN_ID_HEX>" })'
```

4) Read job state:

```bash
dfx canister call registry_canister get_job '(record { run_id = "<RUN_ID_HEX>" })'
```

## Canonicalization + hashing

- Inputs/outputs are stored as raw UTF-8 JSON blobs.
- Canonicalization is assumed to be performed client-side (your Python tool already does this).
- On-chain hashing uses SHA-256 via the `sha2` Motoko package.

If you don’t have `mops`, install it and run:

```bash
mops install
```

## Repo layout

```
.
├── dfx.json
├── mops.toml
├── src
│   ├── registry_canister
│   │   ├── main.mo
│   │   └── types.mo
│   └── compute_canister
│       ├── main.mo
│       └── types.mo
└── candid
    ├── registry.did
    └── compute.did
```

## Next step (v3)

- Replace the screening stub with **real N=256 dense** (or partial-spectrum) compute using **Rust CDK**.
- Keep the same registry interface so results remain audit-compatible.
