import Blob    "mo:base/Blob";
import Bool    "mo:base/Bool";
import HashMap "mo:base/HashMap";
import Iter    "mo:base/Iter";
import Nat64   "mo:base/Nat64";
import Text    "mo:base/Text";
import Time    "mo:base/Time";
import Int     "mo:base/Int";

transient let jobs = HashMap.HashMap<RunId, JobRecord>(
  1024,
  Text.equal,
  Text.hash
);

actor RegistryCanister {

  // -----------------------------
  // Types
  // -----------------------------
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

    // raw input
    input           : Blob;

    // placeholders in v2 (no SHA in Motoko toolchain)
    input_sha256    : Blob;

    // output becomes Some(blob) after set_result
    output          : ?Blob;

    // placeholder
    output_sha256   : ?Blob;

    // optional metadata (can be filled later)
    commit_hash_hex : ?Text;
    error           : ?Text;
  };

  // -----------------------------
  // Storage
  // -----------------------------
  let jobs = HashMap.HashMap<RunId, JobRecord>(
    1024,
    Text.equal,
    Text.hash
  );

  func nowNs() : Nat64 {
    // Time.now() is Int (ns). Convert safely (local dev; negative not expected).
    let t : Int = Time.now();
    if (t <= 0) { 0 } else { Nat64.fromNat(Int.abs(t)) };
  };

  func emptyHash() : Blob {
    // v2 placeholder: empty blob = "hash not computed"
    Blob.fromArray([])
  };

  // -----------------------------
  // Public API used by compute_canister
  // -----------------------------
  public query func get_job(req : { run_id : RunId }) : async ?JobRecord {
    jobs.get(req.run_id)
  };

  public func mark_running(req : { run_id : RunId }) : async Bool {
    switch (jobs.get(req.run_id)) {
      case null { false };
      case (?job) {
        switch (job.status) {
          case (#queued) {
            let updated : JobRecord = {
              run_id          = job.run_id;
              created_at_ns   = job.created_at_ns;
              status          = #running;
              input           = job.input;
              input_sha256    = job.input_sha256;
              output          = job.output;
              output_sha256   = job.output_sha256;
              commit_hash_hex = job.commit_hash_hex;
              error           = null;
            };
            jobs.put(req.run_id, updated);
            true
          };
          case (#running) { true }; // idempotent: already running
          case (#done)    { false };
          case (#failed)  { false };
        }
      }
    }
  };

  public func set_result(req : { run_id : RunId; output : Blob }) : async Bool {
    switch (jobs.get(req.run_id)) {
      case null { false };
      case (?job) {
        // allow commit if running (or queued, to be forgiving in v2)
        switch (job.status) {
          case (#done)   { false };
          case (#failed) { false };
          case (#queued) { commitResult(job, req.output); true };
          case (#running){ commitResult(job, req.output); true };
        }
      }
    }
  };

  func commitResult(job : JobRecord, out : Blob) {
    let updated : JobRecord = {
      run_id          = job.run_id;
      created_at_ns   = job.created_at_ns;
      status          = #done;
      input           = job.input;
      input_sha256    = job.input_sha256;
      output          = ?out;
      output_sha256   = null;              // placeholder
      commit_hash_hex = job.commit_hash_hex;
      error           = null;
    };
    jobs.put(job.run_id, updated);
  };

  public func set_failed(req : { run_id : RunId; error : Text }) : async Bool {
    switch (jobs.get(req.run_id)) {
      case null { false };
      case (?job) {
        let updated : JobRecord = {
          run_id          = job.run_id;
          created_at_ns   = job.created_at_ns;
          status          = #failed;
          input           = job.input;
          input_sha256    = job.input_sha256;
          output          = job.output;
          output_sha256   = job.output_sha256;
          commit_hash_hex = job.commit_hash_hex;
          error           = ?req.error;
        };
        jobs.put(req.run_id, updated);
        true
      }
    }
  };

  // -----------------------------
  // Convenience functions (for testing)
  // -----------------------------

  // Create a job with provided input blob.
  // Returns run_id you can pass to compute_canister.run_screening / run_probe
  public func create_job(req : { run_id : RunId; input : Blob; commit_hash_hex : ?Text }) : async Bool {
    if (jobs.get(req.run_id) != null) return false;

    let rec : JobRecord = {
      run_id          = req.run_id;
      created_at_ns   = nowNs();
      status          = #queued;
      input           = req.input;
      input_sha256    = emptyHash(); // placeholder
      output          = null;
      output_sha256   = null;
      commit_hash_hex = req.commit_hash_hex;
      error           = null;
    };
    jobs.put(req.run_id, rec);
    true
  };

  public query func count_jobs() : async Nat {
    jobs.size()
  };

  // Minimal meta (you can extend later)
  public query func get_registry_meta() : async {
    version : Text;
    note : Text;
  } {
    {
      version = "v2";
      note = "SHA disabled in Motoko v2 (placeholder hashes). Registry stores input/output blobs and status."
    }
  };
}
