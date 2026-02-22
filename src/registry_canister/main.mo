import Blob    "mo:base/Blob";
import Bool    "mo:base/Bool";
import HashMap "mo:base/HashMap";
import Nat     "mo:base/Nat";
import Nat64   "mo:base/Nat64";
import Text    "mo:base/Text";
import Time    "mo:base/Time";
import Int     "mo:base/Int";

persistent actor RegistryCanister {

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

    input           : Blob;
    input_sha256    : Blob;

    output          : ?Blob;
    output_sha256   : ?Blob;

    commit_hash_hex : ?Text;
    error           : ?Text;
  };

  // -----------------------------
  // Storage (in-memory, non-stable)
  // -----------------------------
  transient let jobs = HashMap.HashMap<RunId, JobRecord>(
    1024,
    Text.equal,
    Text.hash
  );

  // -----------------------------
  // Helpers
  // -----------------------------
  func nowNs() : Nat64 {
    let t : Int = Time.now();
    if (t <= 0) { 0 } else { Nat64.fromNat(Int.abs(t)) };
  };

  func emptyHash() : Blob {
    Blob.fromArray([])
  };

  func commitResult(job : JobRecord, out : Blob) {
    let updated : JobRecord = {
      run_id          = job.run_id;
      created_at_ns   = job.created_at_ns;
      status          = #done;
      input           = job.input;
      input_sha256    = job.input_sha256;
      output          = ?out;
      output_sha256   = null;
      commit_hash_hex = job.commit_hash_hex;
      error           = null;
    };
    jobs.put(job.run_id, updated);
  };

  // -----------------------------
  // Public API used by compute_canister
  // -----------------------------
  public query func get_job(req : { run_id : RunId }) : async ?JobRecord {
    jobs.get(req.run_id)
  };

  public func create_job(req : { run_id : RunId; input : Blob; commit_hash_hex : ?Text }) : async Bool {
    // Do not use "!= null": use switch on Option
    switch (jobs.get(req.run_id)) {
      case (?_) { return false };
      case null {};
    };

    let rec : JobRecord = {
      run_id          = req.run_id;
      created_at_ns   = nowNs();
      status          = #queued;
      input           = req.input;
      input_sha256    = emptyHash();
      output          = null;
      output_sha256   = null;
      commit_hash_hex = req.commit_hash_hex;
      error           = null;
    };

    jobs.put(req.run_id, rec);
    true
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
          case (#running) { true };  // idempotent
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
        switch (job.status) {
          case (#done)    { false };
          case (#failed)  { false };
          case (#queued)  { commitResult(job, req.output); true };
          case (#running) { commitResult(job, req.output); true };
        }
      }
    }
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
  // Convenience
  // -----------------------------
  public query func count_jobs() : async Nat {
    jobs.size()
  };

  public query func get_registry_meta() : async { version : Text; note : Text } {
    {
      version = "v2";
      note = "Motoko v2 registry: transient in-memory job map; SHA fields are placeholders.";
    }
  };
}
