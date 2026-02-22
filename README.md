# SMRK–GUEGAP Probe v2.0 (ICP – Motoko)

Status: ✅ WORKING (Local ICP Verified)

This repository contains a minimal deterministic on-chain screening prototype implemented in Motoko and deployed on the Internet Computer (ICP).

The system demonstrates a fully on-chain execution pipeline using a two-canister architecture written entirely in Motoko.

---

## Architecture

Two-canister design:

- registry_canister (Motoko)
- compute_canister (Motoko)

Both canisters are written in Motoko and communicate deterministically on-chain.

---

## Execution Flow

1. A job is created in registry_canister
2. compute_canister performs deterministic screening
3. The result is written back to the registry
4. The registry returns the stored deterministic output

---

## Deterministic Properties

- Canonical run_id-based job handling
- Fully on-chain execution
- Deterministic structured output
- No off-chain randomness
- Reproducible local execution

---

## Verification Status

✔ Deployment successful  
✔ Motoko canisters compiled and running  
✔ Job creation works  
✔ Screening execution works  
✔ Deterministic result stored on-chain  
✔ Result retrieval verified  

---

## Example Output

{
  "probe_version": "smrk-guegap-icp-v2",
  "N": 256,
  "bulk_r": {
    "r_mean": 0.5815693,
    "gap": 0.22,
    "delta1": 0.0198043
  },
  "result": "pass"
}

---

## How To Reproduce

Start local replica and deploy:

dfx start --background --clean
dfx deploy

Create job:

dfx canister call registry_canister create_job '(record { run_id="test-001"; input=blob "hello" })'

Run deterministic screening:

dfx canister call compute_canister run_screening '(record { run_id="test-001" })'

Fetch result:

dfx canister call registry_canister get_job '(record { run_id="test-001" })'

---

## Purpose

This Motoko implementation serves as:

- A reference implementation of deterministic on-chain screening
- A minimal ICP-native execution model
- A learning baseline before Rust-based optimization
- A reproducible architecture for future SMRK–GUEGAP versions

---

## Repository Structure

/src
  /registry_canister
  /compute_canister
dfx.json
README.md

---

## Notes

This repository is the Motoko counterpart to the Rust implementation.

Both versions implement the same deterministic logic but differ in:

- Language (Motoko vs Rust)
- Compilation model
- Memory management
- Optimization potential
