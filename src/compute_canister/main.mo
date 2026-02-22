import Blob    "mo:base/Blob";
import Bool    "mo:base/Bool";
import Nat     "mo:base/Nat";
import Nat8    "mo:base/Nat8";
import Nat32   "mo:base/Nat32";
import Nat64   "mo:base/Nat64";
import Text    "mo:base/Text";
import Time    "mo:base/Time";
import Int     "mo:base/Int";

persistent actor ComputeCanister {

  type RunId = Text;

  type JobStatus = {
    #queued;
    #running;
    #done;
    #failed;
  };

  type JobRecord = {
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

  type Registry = actor {
    get_job      : shared query ({ run_id : RunId }) -> async ?JobRecord;
    mark_running : shared ({ run_id : RunId }) -> async Bool;
    set_result   : shared ({ run_id : RunId; output : Blob }) -> async Bool;
    set_failed   : shared ({ run_id : RunId; error : Text }) -> async Bool;
  };

  stable var registry_id_text : Text = "";
  stable var initialized : Bool = false;

  func nowNs() : Nat64 {
    let t : Int = Time.now();
    if (t <= 0) { 0 } else { Nat64.fromNat(Int.abs(t)) };
  };

  func reg() : Registry {
    if (initialized == false or registry_id_text == "") { assert false };
    actor (registry_id_text) : Registry
  };

  func fnv1a32(input : Blob) : Nat32 {
    let bytes = Blob.toArray(input);
    var h : Nat32 = 2166136261;
    var i : Nat = 0;
    while (i < bytes.size()) {
      h := h ^ Nat32.fromNat(Nat8.toNat(bytes[i]));
      h := h * 16777619;
      i += 1;
    };
    h
  };

  func byte0(h : Nat32) : Nat8 { Nat8.fromNat(Nat32.toNat(h & 0xff)) };
  func byte1(h : Nat32) : Nat8 { Nat8.fromNat(Nat32.toNat((h >> 8) & 0xff)) };
  func byte2(h : Nat32) : Nat8 { Nat8.fromNat(Nat32.toNat((h >> 16) & 0xff)) };
  func byte3(h : Nat32) : Nat8 { Nat8.fromNat(Nat32.toNat((h >> 24) & 0xff)) };

  func makeOutput(input : Blob, runId : Text, n : Nat) : Blob {
    let h = fnv1a32(input);

    let json =
      "{"
      # "\"run_id\":\"" # runId # "\","
      # "\"n\":" # Nat.toText(n) # ","
      # "\"fnv1a32\":" # Nat.toText(Nat32.toNat(h)) # ","
      # "\"b0\":" # Nat.toText(Nat8.toNat(byte0(h))) # ","
      # "\"b1\":" # Nat.toText(Nat8.toNat(byte1(h))) # ","
      # "\"b2\":" # Nat.toText(Nat8.toNat(byte2(h))) # ","
      # "\"b3\":" # Nat.toText(Nat8.toNat(byte3(h))) # ","
      # "\"ts_ns\":" # Nat64.toText(nowNs())
      # "}";

    Text.encodeUtf8(json)
  };

  public func init(registry_canister_id : Text) : async Bool {
    registry_id_text := registry_canister_id;
    initialized := true;
    true
  };

  public func run_screening(req : { run_id : Text; n : Nat }) : async Bool {
    let r = reg();

    let jobOpt = await r.get_job({ run_id = req.run_id });
    switch (jobOpt) {
      case null {
        ignore await r.set_failed({ run_id = req.run_id; error = "Job not found" });
        false
      };
      case (?job) {
        let okRun = await r.mark_running({ run_id = req.run_id });
        if (okRun == false) { return false };

        let out = makeOutput(job.input, job.run_id, req.n);

        let okSet = await r.set_result({ run_id = req.run_id; output = out });
        if (okSet == false) {
          ignore await r.set_failed({ run_id = req.run_id; error = "Failed to set result" });
          return false
        };

        true
      }
    }
  };
}
