use super::*;
use std::sync::{Arc, Mutex};

// Actual CPU ORT sessions with fixed symbolic dimensions exercise the shared
// selection/feed path without admitting CPU as a configured bucket provider.
pub(crate) fn cpu_bank(graph: &Path, lengths: &[usize]) -> ClassifierSessions {
    let slots = prepare_warmed(
        lengths,
        |length| {
            let declarations = crate::core::onnx_artifacts::input_schema(graph).unwrap();
            let inputs = modernbert_inputs::resolved_inputs(graph, 1, length)?;
            let overrides =
                crate::core::execution_contract::dimension_overrides(&declarations, &inputs)
                    .unwrap();
            let mut builder = Session::builder().unwrap().with_intra_threads(1).unwrap();
            for (name, size) in overrides {
                builder = builder.with_dimension_override(name, size).unwrap();
            }
            Ok(Slot {
                prepared: PreparedSession {
                    session: builder.commit_from_file(graph).unwrap(),
                    cache_lease: None,
                    artifacts: vec![],
                },
                sequence: Some(length),
            })
        },
        |slot, length| {
            let output = modernbert_inputs::run(
                &mut slot.prepared.session,
                vec![1; length],
                vec![1; length],
                1,
                length,
            )?;
            assert!(output["logits"]
                .try_extract_tensor::<f32>()
                .unwrap()
                .1
                .iter()
                .all(|v| v.is_finite()));
            Ok(())
        },
    )
    .unwrap();
    ClassifierSessions { slots }
}

#[test]
fn selection_preserves_full_length_and_rejects_uncovered_shapes() {
    for (short, max) in [(0, 8192), (8192, 8192), (8193, 8192), (1, 0)] {
        assert!(bucket_lengths(short, max).is_err());
    }
    let graph = Path::new(env!("CARGO_MANIFEST_DIR")).join("instance/testdata/token/model.onnx");
    let mut bank = cpu_bank(&graph, &bucket_lengths(512, 8192).unwrap());
    for (actual, physical) in [(1, 512), (511, 512), (512, 512), (513, 8192), (8192, 8192)] {
        assert_eq!(bank.execution_length(1, actual).unwrap(), physical);
        let mut ids = vec![47; physical];
        let mut mask = vec![0; physical];
        for i in 0..actual {
            ids[i] = 3;
            mask[i] = 1;
        }
        ids[actual - 1] = 9; // Last real token must never disappear at a boundary.
        if actual > 2 {
            mask[1] = 0;
        }
        let output = bank.run(ids, mask, 1, physical).unwrap();
        let (shape, values) = output["logits"].try_extract_tensor::<f32>().unwrap();
        assert_eq!(shape.as_ref(), [1, physical as i64, 2]);
        assert_eq!(values[(actual - 1) * 2 + 1], 9.0);
        if actual > 2 {
            assert_eq!(values[3], 0.0);
        }
        assert!(values[actual * 2..].iter().all(|&v| v == 0.0));
    }
    assert!(bank.execution_length(1, 8193).is_err());
    assert!(bank.execution_length(2, 7).is_err());
    assert!(bank.execution_length(1, 0).is_err());
    assert!(bank.run(vec![3; 513], vec![1; 513], 1, 513).is_err());
}

#[test]
fn warmup_precedes_next_preparation_and_failed_bank_drops_every_owner() {
    struct Owner(usize, Arc<Mutex<Vec<String>>>);
    impl Drop for Owner {
        fn drop(&mut self) {
            self.1.lock().unwrap().push(format!("drop:{}", self.0));
        }
    }
    for fail in [false, true] {
        let events = Arc::new(Mutex::new(vec![]));
        let owners = prepare_warmed(
            &[512, 8192],
            |length| {
                let mut log = events.lock().unwrap();
                if length == 8192 {
                    assert_eq!(log.last().unwrap(), "warm:512");
                }
                log.push(format!("prepare:{length}"));
                Ok(Owner(length, events.clone()))
            },
            |_, length| {
                events.lock().unwrap().push(format!("warm:{length}"));
                if fail && length == 8192 {
                    return Err(invalid("injected warmup failure"));
                }
                Ok(())
            },
        );
        assert_eq!(owners.is_err(), fail);
        if !fail {
            assert!(!events
                .lock()
                .unwrap()
                .iter()
                .any(|s| s.starts_with("drop:")));
        }
        drop(owners);
        let log = events.lock().unwrap();
        assert_eq!(log.iter().filter(|s| *s == "drop:512").count(), 1);
        assert_eq!(log.iter().filter(|s| *s == "drop:8192").count(), 1);
    }
}

#[test]
fn fixed_sequence_graph_is_rejected_before_bucket_preparation() {
    let directory = tempfile::tempdir().unwrap();
    let original = Path::new(env!("CARGO_MANIFEST_DIR")).join("instance/testdata/token/model.onnx");
    let fixed = directory.path().join("fixed.onnx");
    let session = Session::builder()
        .unwrap()
        .with_intra_threads(1)
        .unwrap()
        .with_dimension_override("tokens", 8192)
        .unwrap()
        .with_optimized_model_path(&fixed)
        .unwrap()
        .commit_from_file(original)
        .unwrap();
    drop(session);
    assert!(modernbert_inputs::resolved_inputs(&fixed, 1, 8192).is_ok());
    assert!(modernbert_inputs::resolved_inputs(&fixed, 1, 512).is_err());
}

#[test]
fn eager_warmup_publishes_each_shape_and_releases_real_cache_locks() {
    use crate::core::{
        artifact_identity::ArtifactDigest,
        compilation_cache::{CompilationCacheLease, CompilationIdentity},
        execution_contract::ExecutionInput,
        migraphx_identity::GpuIdentity,
    };
    let directory = tempfile::tempdir().unwrap();
    let identity = |length| CompilationIdentity {
        version: 1,
        artifacts: vec![ArtifactDigest {
            role: "graph".into(),
            sha256: "a".repeat(64),
        }],
        inputs: vec![ExecutionInput {
            name: "input_ids".into(),
            dtype: "int64".into(),
            shape: vec![1, length as i64],
        }],
        precision: "native".into(),
        runtime_build: "fixture".into(),
        runtime_artifacts: vec![],
        gpu: GpuIdentity {
            pci_bdf: "fixture".into(),
            uuid: "fixture".into(),
            architectures: vec!["fixture".into()],
            hip_runtime_version: 0,
            hip_driver_version: 0,
        },
        compiler_flags: Default::default(),
    };
    let bank = prepare_warmed(
        &[512, 8192],
        |length| {
            Ok(Some(CompilationCacheLease::prepare(
                directory.path(),
                identity(length),
                vec![],
            )?))
        },
        |lease, length| {
            let work = lease.as_ref().unwrap().directory.clone();
            with_inference(lease, &identity(length).inputs, || {
                std::fs::write(work.join("program.mxr"), b"compiled fixture").unwrap();
                Ok(())
            })
        },
    )
    .unwrap();
    assert_ne!(
        bank[0].as_ref().unwrap().evidence.0.lock().key,
        bank[1].as_ref().unwrap().evidence.0.lock().key
    );
    // Keep the first bank alive while another owner prepares the same shapes.
    // A forgotten first-inference lease would block this preparation.
    let identities = [identity(512), identity(8192)];
    let root = directory.path().to_path_buf();
    let (tx, rx) = std::sync::mpsc::channel();
    let next = std::thread::spawn(move || {
        let mut leases = vec![];
        for identity in identities {
            let lease = CompilationCacheLease::prepare(&root, identity, vec![]).unwrap();
            assert_eq!(lease.evidence.0.lock().state, "verified_entry_available");
            leases.push(lease);
        }
        tx.send(()).unwrap();
    });
    let result = rx.recv_timeout(std::time::Duration::from_secs(5));
    drop(bank);
    assert!(result.is_ok());
    next.join().unwrap();
}
