import Blob "mo:base/Blob";
import Nat64 "mo:base/Nat64";

module {
  public type RunId = Text;

  public type JobStatus = {
    #queued;
    #running;
    #done;
    #failed;
  };

  public type JobRecord = {
    run_id: RunId;
    created_at_ns: Nat64;
    status: JobStatus;
    input: Blob;
    input_sha256: Blob;
    output: ?Blob;
    output_sha256: ?Blob;
    commit_hash_hex: ?Text;
    error: ?Text;
  };
}
