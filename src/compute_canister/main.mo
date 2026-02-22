import Blob  "mo:base/Blob";
import Float "mo:base/Float";
import Text  "mo:base/Text";
import Bool  "mo:base/Bool";
import Array "mo:base/Array";
import Nat8  "mo:base/Nat8";
import Nat32 "mo:base/Nat32";

import T "types";

// ------------------------------------------------------------
// Registry API (typed actor interface)
// ------------------------------------------------------------
module RegistryAPI {
  public type RunId = Text;

  public type JobStatus = {
    #queued;
    #running;
    #done;
    #failed;
  };

  public type JobRecord = {
    run_id          : RunId;
    created_at_ns   : Nat64;
    status          : JobStatus;
    input           : Blob;
    input_sha256    : Blob;      // kept for compatibility (may be empty/placeholder in v2)
    output          : ?Blob;
    output_sha256   : ?Blob;     // kept for compatibility
    commit_hash_hex : ?Text;
    error           : ?Text;
  };

  public type Registry = actor {
    get_job      : ({ run_id : RunId }) -> async (?JobRecord);
    mark_running : ({ run_id : RunId }) -> async Bool;
    set_result   : ({ run_id : RunId; output : Blob }) -> async Bool;
    set_failed   : ({ run_id : RunId; error : Text }) -> async Bool;
  };
};

// ------------------------------------------------------------
// Compute Canister
// ------------------------------------------------------------
actor ComputeCanister {

  // Local dev alias by canister name
  let registry : RegistryAPI.Registry = actor ("registry_canister");

  // ----------------------------------------------------------
  // Deterministic pseudohash (FNV-1a style) over Blob bytes
  // (No SHA dependency; stable across replicas)
// ----------------------------------------------------------
  func fnv1a32(input : Blob) : Nat32 {
    let bytes = Blob.toArray(input);
    var h : Nat32 = 2166136261; // offset basis
    var i : Nat = 0;

    while (i < bytes.size()) {
      h := Nat32.xor(h, Nat32.fromNat(Nat8.toNat(bytes[i])));
      h := Nat32.mul(h, 16777619);
      i += 1;
    };
    h
  };

  func byte0(h : Nat32) : Nat8 {
    Nat8.fromNat(Nat32.toNat(Nat32.and(h, 0xff)))
  };

  func byte1(h : Nat32) : Nat8 {
    Nat8.fromNat(Nat32.toNat(Nat32.and(Nat32.shiftRight(h, 8), 0xff)))
  };

  // ----------------------------------------------------------
  // Deterministic screening stub derived from fnv1a32(input)
  // Outputs a JSON blob (UTF-8).
  // ----------------------------------------------------------
  func screening_stub(input : Blob, N : Nat) : Blob {
    let h  = fnv1a32(input);
    let b0 = byte0(h);
    let b1 = byte1(h);

    let r_mean =
      (Float.fromInt(Nat8.toNat(b0)) / 255.0) * 0.2 + 0.5; // ~[0.5, 0.7]

    let delta1 =
      (Float.fromInt(Nat8.toNat(b1)) / 255.0) * 0.05;      // ~[0.0, 0.05]

    let pass =
      if (r_mean > 0.58 and delta1 > 0.005) { "pass" } else { "fail" };

    // canonical-ish: fixed key order, no whitespace
    let json =
      "{"
      # "\"probe_version\":\"smrk-guegap-icp-v2\","
      # "\"N\":" # Nat.toText(N) # ","
      # "\"bulk_r\":{\"r_mean\":" # Float.toText(r_mean) # ",\"count\":100},"
      # "\"gap\":{\"delta1\":" # Float.toText(delta1) # "},"
      # "\"H1_H2_proxy\":\"" # pass # "\""
      # "}";

    Text.encodeUtf8(json)
  };

  // ----------------------------------------------------------
  // Registry-driven run: marks running, fetches job input,
  // computes output, commits to registry.
  // ----------------------------------------------------------
  public shared func run_screening(req : { run_id : T.RunId })
    : async { ok : Bool; message : Text }
  {
    let okRun = await registry.mark_running({ run_id = req.run_id });

    if (not okRun) {
      return { ok = false; message = "Job not runnable (missing/done/failed)." };
    };

    let jobOpt = await registry.get_job({ run_id = req.run_id });

    switch (jobOpt) {
      case null {
        ignore await registry.set_failed({
          run_id = req.run_id;
          error  = "Job missing after mark_running."
        });
        { ok = false; message = "Job missing." }
      };

      case (?job) {
        // v2 stub uses N=256 fixed
        let out = screening_stub(job.input, 256);

        let okSet = await registry.set_result({
          run_id = req.run_id;
          output = out
        });

        if (okSet) {
          { ok = true; message = "Screening complete (stub) and committed." }
        } else {
          ignore await registry.set_failed({
            run_id = req.run_id;
            error  = "Failed to set result."
          });
          { ok = false; message = "Failed to commit output." }
        }
      }
    }
  };

  // ----------------------------------------------------------
  // Convenience alias (some callers prefer run_probe semantics)
  // ----------------------------------------------------------
  public shared func run_probe(req : { run_id : T.RunId })
    : async { ok : Bool; message : Text }
  {
    await run_screening(req)
  };

  // ----------------------------------------------------------
  // Quick local test endpoint (NO registry):
  // lets you do: dfx canister call compute_canister run_probe_quick '(256)'
  // ----------------------------------------------------------
  public shared func run_probe_quick(N : Nat) : async Blob {
    // deterministic input derived only from N
    let input = Text.encodeUtf8("probe_input_N=" # Nat.toText(N));
    screening_stub(input, N)
  };
}
