//! Bounded physical sessions for one immutable ModernBERT classifier.
//! Logical token limits and tokenization remain with the task. A short bucket
//! changes padding only; both sessions are prepared and warmed before exposure.

use super::modernbert_inputs;
use crate::core::{
    compilation_cache::with_inference,
    instance_options::{InstanceOptions, PreparedSession, Provider},
    unified_error::{errors, UnifiedResult},
};
use ort::session::{Session, SessionOutputs};
use std::path::Path;
use tokenizers::Encoding;

struct Slot {
    prepared: PreparedSession,
    sequence: Option<usize>,
}

pub(crate) struct ClassifierSessions {
    slots: Vec<Slot>,
}

fn invalid(message: &str) -> crate::core::unified_error::UnifiedError {
    errors::config_error("short_sequence_tokens", message)
}

fn bucket_lengths(short: usize, maximum: usize) -> UnifiedResult<[usize; 2]> {
    if short == 0 || short >= maximum {
        return Err(invalid(
            "must be positive and smaller than the physical execution limit",
        ));
    }
    Ok([short, maximum])
}

// Warm each session before preparing the next. Compilation-cache locks last
// through first inference; retaining an unused lease could block a reload.
fn prepare_warmed<T>(
    lengths: &[usize],
    mut prepare: impl FnMut(usize) -> UnifiedResult<T>,
    mut warm: impl FnMut(&mut T, usize) -> UnifiedResult<()>,
) -> UnifiedResult<Vec<T>> {
    let mut slots = Vec::with_capacity(lengths.len());
    for &length in lengths {
        let mut slot = prepare(length)?;
        warm(&mut slot, length)?;
        slots.push(slot);
    }
    Ok(slots)
}

impl ClassifierSessions {
    pub(crate) fn legacy(session: Session) -> Self {
        Self {
            slots: vec![Slot {
                prepared: PreparedSession {
                    session,
                    cache_lease: None,
                    artifacts: vec![],
                },
                sequence: None,
            }],
        }
    }

    pub(crate) fn prepare(
        options: &InstanceOptions,
        graph: &Path,
        maximum: usize,
        warmup: &Encoding,
        pad: i64,
        validate_output: impl Fn(&SessionOutputs<'_>, usize) -> UnifiedResult<()>,
    ) -> UnifiedResult<Self> {
        let Some(short) = options.short_sequence_tokens else {
            let prepared = modernbert_inputs::prepare_session(options, graph, maximum)?;
            modernbert_inputs::validate(&prepared.session.inputs)?;
            return Ok(Self {
                slots: vec![Slot {
                    prepared,
                    sequence: (options.provider == Provider::Migraphx).then_some(maximum),
                }],
            });
        };
        if options.provider != Provider::Migraphx {
            return Err(invalid("requires MIGraphX classifier execution"));
        }
        let lengths = bucket_lengths(short, maximum)?;
        if warmup.is_empty()
            || warmup.len() > short
            || warmup.get_attention_mask().iter().all(|&x| x == 0)
        {
            return Err(invalid(
                "short bucket must fit a nonempty tokenizer warmup including special tokens",
            ));
        }
        // Validate every shape before constructing any backend. Fixed sequence
        // graphs cannot satisfy both contracts and fail here without compiling.
        for length in lengths {
            modernbert_inputs::resolved_inputs(graph, 1, length)?;
        }
        let mut physical = options.clone();
        physical.short_sequence_tokens = None; // Consumed here, never silently ignored by an architecture.
        let flags = options.compiler_flags(std::env::vars_os())?;
        let baseline = crate::core::onnx_artifacts::capture_onnx(graph)
            .map_err(|e| invalid(&e.to_string()))?;
        let slots = prepare_warmed(
            &lengths,
            |length| {
                for snapshot in &baseline {
                    snapshot.verify().map_err(|e| invalid(&e.to_string()))?;
                }
                if options.compiler_flags(std::env::vars_os())? != flags {
                    return Err(invalid(
                        "compiler controls changed during bucket preparation",
                    ));
                }
                let prepared = modernbert_inputs::prepare_session(&physical, graph, length)?;
                modernbert_inputs::validate(&prepared.session.inputs)?;
                if prepared
                    .artifacts
                    .iter()
                    .map(|x| &x.digest)
                    .ne(baseline.iter().map(|x| &x.digest))
                {
                    return Err(invalid("model artifacts changed between physical sessions"));
                }
                Ok(Slot {
                    prepared,
                    sequence: Some(length),
                })
            },
            |slot, length| {
                let mut ids = vec![pad; length];
                let mut mask = vec![0; length];
                for i in 0..warmup.len() {
                    ids[i] = i64::from(warmup.get_ids()[i]);
                    mask[i] = i64::from(warmup.get_attention_mask()[i]);
                }
                let inputs = modernbert_inputs::resolved_inputs(graph, 1, length)?;
                let prepared = &mut slot.prepared;
                with_inference(&mut prepared.cache_lease, &inputs, || {
                    let outputs =
                        modernbert_inputs::run(&mut prepared.session, ids, mask, 1, length)?;
                    validate_output(&outputs, length)
                })?;
                for snapshot in &baseline {
                    snapshot.verify().map_err(|e| invalid(&e.to_string()))?;
                }
                Ok(())
            },
        )?;
        let evidence = options.evidence.lock();
        let sessions = &evidence[evidence.len() - slots.len()..];
        let first = &sessions[0];
        if sessions.iter().any(|s| {
            s.runtime_build != first.runtime_build
                || s.provider != first.provider
                || s.device_id != first.device_id
                || s.precision != first.precision
                || s.artifacts != first.artifacts
                || s.compiler_flags != first.compiler_flags
                || !s.cpu_fallback_disabled
        }) {
            return Err(invalid(
                "runtime or compiler identity changed between physical sessions",
            ));
        }
        Ok(Self { slots })
    }

    pub(crate) fn execution_length(&self, batch: usize, actual: usize) -> UnifiedResult<usize> {
        if batch == 0 || actual == 0 {
            return Err(invalid("execution requires nonempty inputs"));
        }
        for slot in &self.slots {
            match slot.sequence {
                None => return Ok(actual),
                Some(length) if batch == 1 && actual <= length => return Ok(length),
                _ => (),
            }
        }
        Err(invalid(
            "no physical session covers the complete input shape",
        ))
    }

    pub(crate) fn run(
        &mut self,
        ids: Vec<i64>,
        mask: Vec<i64>,
        batch: usize,
        sequence: usize,
    ) -> UnifiedResult<SessionOutputs<'_>> {
        let slot = self
            .slots
            .iter_mut()
            .find(|slot| slot.sequence.is_none() || (batch == 1 && slot.sequence == Some(sequence)))
            .ok_or_else(|| invalid("input shape does not match a prepared session"))?;
        modernbert_inputs::run_cached(
            &mut slot.prepared.session,
            &mut slot.prepared.cache_lease,
            ids,
            mask,
            batch,
            sequence,
        )
    }

    pub(crate) fn finish_profiling(&mut self) -> UnifiedResult<Vec<String>> {
        self.slots
            .iter_mut()
            .map(|slot| {
                slot.prepared
                    .session
                    .end_profiling()
                    .map_err(|e| errors::ort_error(&e.to_string()))
            })
            .collect()
    }
}

#[cfg(test)]
pub(crate) mod tests;
