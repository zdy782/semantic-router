//! Stream the ONNX envelope, skipping tensor bytes, to bind every external data file.
use super::runtime_identity::ArtifactSnapshot;
use std::collections::BTreeSet;
use std::fs::File;
use std::io::{BufReader, Read};
use std::path::{Component, Path};

pub fn capture_onnx(path: &Path) -> anyhow::Result<Vec<ArtifactSnapshot>> {
    let graph = ArtifactSnapshot::capture(path, "graph")?;
    let mut locations = BTreeSet::new();
    walk(
        &mut BufReader::new(File::open(path)?),
        "model",
        0,
        &mut locations,
    )?;
    let mut artifacts = vec![graph];
    for location in locations {
        let relative = Path::new(&location);
        anyhow::ensure!(
            !location.is_empty()
                && !location.contains('\\')
                && relative
                    .components()
                    .all(|part| matches!(part, Component::Normal(_))),
            "unsafe ONNX external data location"
        );
        artifacts.push(ArtifactSnapshot::capture(
            &path.parent().unwrap_or(Path::new(".")).join(relative),
            format!("external:{location}"),
        )?);
    }
    Ok(artifacts)
}

fn varint(reader: &mut dyn Read) -> anyhow::Result<Option<u64>> {
    let mut value = 0;
    for shift in (0..70).step_by(7) {
        let mut byte = [0];
        match reader.read(&mut byte)? {
            0 if shift == 0 => return Ok(None),
            0 => anyhow::bail!("truncated ONNX varint"),
            _ => {}
        }
        anyhow::ensure!(shift != 63 || byte[0] <= 1, "overflowed ONNX varint");
        value |= u64::from(byte[0] & 127) << shift;
        if byte[0] < 128 {
            return Ok(Some(value));
        }
    }
    anyhow::bail!("invalid ONNX varint")
}

fn required_varint(reader: &mut dyn Read) -> anyhow::Result<u64> {
    varint(reader)?.ok_or_else(|| anyhow::anyhow!("missing ONNX varint"))
}

fn discard(reader: &mut dyn Read, size: u64) -> anyhow::Result<()> {
    let copied = std::io::copy(&mut reader.take(size), &mut std::io::sink())?;
    anyhow::ensure!(copied == size, "truncated ONNX field");
    Ok(())
}

fn child(kind: &str, field: u64) -> Option<&'static str> {
    match (kind, field) {
        ("model", 7) => Some("graph"),
        ("model", 25) => Some("function"),
        ("graph", 1) | ("function", 7) => Some("node"),
        ("graph", 5) | ("sparse", 1 | 2) | ("attribute", 5 | 10) => Some("tensor"),
        ("graph", 15) | ("attribute", 22 | 23) => Some("sparse"),
        ("node", 5) | ("function", 11) => Some("attribute"),
        ("attribute", 6 | 11) => Some("graph"),
        _ => None,
    }
}

fn external_entry(reader: &mut dyn Read) -> anyhow::Result<(String, String)> {
    let mut key = String::new();
    let mut value = String::new();
    while let Some(tag) = varint(reader)? {
        anyhow::ensure!(
            tag & 7 == 2 && matches!(tag >> 3, 1 | 2),
            "invalid ONNX external data entry"
        );
        let size = required_varint(reader)?;
        anyhow::ensure!(size <= 1 << 20, "oversize ONNX external data string");
        let mut data = vec![0; size as usize];
        reader.read_exact(&mut data)?;
        let text = String::from_utf8(data)?;
        if tag >> 3 == 1 {
            key = text
        } else {
            value = text
        }
    }
    Ok((key, value))
}

fn walk(
    reader: &mut dyn Read,
    kind: &str,
    depth: usize,
    locations: &mut BTreeSet<String>,
) -> anyhow::Result<()> {
    anyhow::ensure!(depth <= 64, "ONNX nesting limit exceeded");
    let mut location = None;
    let mut external = false;
    while let Some(tag) = varint(reader)? {
        let field = tag >> 3;
        anyhow::ensure!(field > 0, "invalid ONNX field number");
        match tag & 7 {
            0 => {
                let value = required_varint(reader)?;
                if kind == "tensor" && field == 14 && value == 1 {
                    external = true;
                }
            }
            1 => discard(reader, 8)?,
            5 => discard(reader, 4)?,
            2 => {
                let size = required_varint(reader)?;
                let mut limited = reader.take(size);
                if kind == "tensor" && field == 13 {
                    anyhow::ensure!(size <= 1 << 20, "oversize ONNX external data entry");
                    let (key, value) = external_entry(&mut limited)?;
                    if key == "location" {
                        anyhow::ensure!(location.is_none(), "duplicate ONNX external location");
                        location = Some(value);
                    }
                } else if let Some(nested) = child(kind, field) {
                    walk(&mut limited, nested, depth + 1, locations)?;
                }
                let remaining = limited.limit();
                discard(&mut limited, remaining)?;
            }
            _ => anyhow::bail!("unsupported ONNX protobuf wire type"),
        }
    }
    if external {
        locations.insert(
            location.ok_or_else(|| anyhow::anyhow!("external ONNX tensor has no location"))?,
        );
    } else if let Some(location) = location {
        // Bind metadata even if a producer omitted data_location; fail closed.
        locations.insert(location);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    fn field(number: u8, bytes: &[u8]) -> Vec<u8> {
        assert!(bytes.len() < 128);
        [vec![number << 3 | 2, bytes.len() as u8], bytes.to_vec()].concat()
    }
    fn graph(location: &str) -> Vec<u8> {
        let entry = [field(1, b"location"), field(2, location.as_bytes())].concat();
        let tensor = [field(13, &entry), vec![14 << 3, 1]].concat();
        field(7, &field(5, &tensor))
    }
    #[test]
    fn binds_external_content_and_rejects_unsafe_or_missing_data() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("model.onnx");
        std::fs::write(&path, graph("weights.bin")).unwrap();
        assert!(capture_onnx(&path).is_err());
        std::fs::write(dir.path().join("weights.bin"), b"old").unwrap();
        let old = capture_onnx(&path).unwrap();
        std::fs::write(dir.path().join("weights.bin"), b"new").unwrap();
        let new = capture_onnx(&path).unwrap();
        assert_eq!(old[0].digest.sha256, new[0].digest.sha256);
        assert_ne!(old[1].digest.sha256, new[1].digest.sha256);
        std::fs::write(&path, graph("../weights.bin")).unwrap();
        assert!(capture_onnx(&path).is_err());
    }
    #[test]
    fn malformed_or_truncated_protobuf_fails_closed() {
        for data in [vec![0], vec![58, 127, 1], vec![58, 1, 128], vec![255; 11]] {
            assert!(walk(&mut data.as_slice(), "model", 0, &mut BTreeSet::new()).is_err());
        }
    }
}
