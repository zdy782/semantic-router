use super::*;
use ort::tensor::SymbolicDimensions;

fn input(name: &str, shape: &[i64], ty: TensorElementType) -> Input {
    Input {
        name: name.into(),
        input_type: ValueType::Tensor {
            ty,
            shape: shape.to_vec().into(),
            dimension_symbols: SymbolicDimensions::empty(shape.len()),
        },
    }
}
fn schema() -> Vec<Input> {
    vec![
        input("input_ids", &[-1, -1], TensorElementType::Int64),
        input("attention_mask", &[-1, -1], TensorElementType::Int64),
    ]
}

#[test]
fn rejects_unsupported_graph_contracts_before_execution() {
    assert!(!validate(&schema()).unwrap());
    for (name, shape, ty) in [
        ("token_type_ids", vec![-1, -1], TensorElementType::Int64),
        ("input_ids", vec![-1, -1], TensorElementType::Int64),
        ("position_ids", vec![1, -1], TensorElementType::Float32),
        ("position_ids", vec![-1], TensorElementType::Int64),
        ("position_ids", vec![-1, -1], TensorElementType::Int64),
        ("position_ids", vec![2, -1], TensorElementType::Int64),
        ("position_ids", vec![1, 0], TensorElementType::Int64),
    ] {
        let mut values = schema();
        values.push(input(name, &shape, ty));
        assert!(
            validate(&values).is_err(),
            "accepted {name} {shape:?} {ty:?}"
        );
    }
    assert!(validate(&schema()[..1]).is_err());
    let mut values = schema();
    values[0] = input("input_ids", &[2, 8], TensorElementType::Int64);
    values[1] = input("attention_mask", &[2, 7], TensorElementType::Int64);
    assert!(validate(&values).is_err());
    values[1] = input("attention_mask", &[2, 8], TensorElementType::Int64);
    values.push(input("position_ids", &[1, 7], TensorElementType::Int64));
    assert!(validate(&values).is_err());
}

// Small real ONNX fixtures, assembled here to avoid a Python runtime dependency
// or downloading any model. Both return input_ids + absolute positions.
fn varint(mut value: u64) -> Vec<u8> {
    let mut bytes = vec![];
    while value >= 128 {
        bytes.push((value as u8 & 127) | 128);
        value >>= 7;
    }
    bytes.push(value as u8);
    bytes
}
fn integer(number: u64, value: u64) -> Vec<u8> {
    [varint(number << 3), varint(value)].concat()
}
fn field(number: u64, bytes: &[u8]) -> Vec<u8> {
    [
        varint(number << 3 | 2),
        varint(bytes.len() as u64),
        bytes.to_vec(),
    ]
    .concat()
}
fn value_info(name: &str, broadcast: bool) -> Vec<u8> {
    let row = if broadcast {
        integer(1, 1)
    } else {
        field(2, b"batch")
    };
    let shape = [field(1, &row), field(1, &field(2, b"sequence"))].concat();
    let tensor = [integer(1, 7), field(2, &shape)].concat();
    [field(1, name.as_bytes()), field(2, &field(1, &tensor))].concat()
}
fn node(op: &str, inputs: &[&str], output: &str) -> Vec<u8> {
    [
        inputs
            .iter()
            .flat_map(|name| field(1, name.as_bytes()))
            .collect::<Vec<_>>(),
        field(2, output.as_bytes()),
        field(4, op.as_bytes()),
    ]
    .concat()
}
fn constant(name: &str, value: i64, vector: bool) -> Vec<u8> {
    [
        if vector { integer(1, 1) } else { vec![] },
        integer(2, 7),
        field(8, name.as_bytes()),
        field(9, &value.to_le_bytes()),
    ]
    .concat()
}
fn graph(explicit: bool) -> Vec<u8> {
    let mut graph = [
        field(2, b"standard-position-input"),
        field(11, &value_info("input_ids", false)),
        field(11, &value_info("attention_mask", false)),
        field(12, &value_info("output", false)),
    ]
    .concat();
    if explicit {
        graph.extend(field(11, &value_info("position_ids", true)));
    } else {
        for (name, value, vector) in [("zero", 0, false), ("one", 1, false), ("axis", 0, true)] {
            graph.extend(field(5, &constant(name, value, vector)));
        }
        for bytes in [
            node("Shape", &["input_ids"], "shape"),
            node("Gather", &["shape", "one"], "length"),
            node("Range", &["zero", "length", "one"], "range"),
            node("Unsqueeze", &["range", "axis"], "position_ids"),
        ] {
            graph.extend(field(1, &bytes));
        }
    }
    graph.extend(field(
        1,
        &node("Add", &["input_ids", "position_ids"], "output"),
    ));
    [integer(1, 8), field(7, &graph), field(8, &integer(2, 13))].concat()
}

#[test]
fn actual_legacy_and_explicit_sessions_preserve_padded_absolute_positions() {
    let mut old = Session::builder()
        .unwrap()
        .commit_from_memory(&graph(false))
        .unwrap();
    let mut new = Session::builder()
        .unwrap()
        .commit_from_memory(&graph(true))
        .unwrap();
    assert!(!validate(&old.inputs).unwrap());
    assert!(validate(&new.inputs).unwrap());
    for batch in [1, 2] {
        for sequence in [2, 5, 129, 32768] {
            for mode in 0..4 {
                let ids = vec![7; batch * sequence];
                let mask = (0..batch * sequence)
                    .map(|i| {
                        let p = i % sequence;
                        i64::from(match mode {
                            0 => true,
                            1 => p >= sequence / 3,
                            2 => p < sequence * 2 / 3,
                            _ => p % 3 != 1,
                        })
                    })
                    .collect::<Vec<_>>();
                let a = run(&mut old, ids.clone(), mask.clone(), batch, sequence).unwrap();
                let b = run(&mut new, ids, mask, batch, sequence).unwrap();
                let (shape, values) = b["output"].try_extract_tensor::<i64>().unwrap();
                assert_eq!(shape.as_ref(), [batch as i64, sequence as i64]);
                assert_eq!(values, a["output"].try_extract_tensor::<i64>().unwrap().1);
                assert!(values
                    .iter()
                    .enumerate()
                    .all(|(i, &v)| v == 7 + (i % sequence) as i64));
            }
        }
    }
    assert!(run(&mut new, vec![7; 5], vec![1; 5], 1, 8).is_err());
    assert!(run(&mut new, vec![], vec![], 1, 0).is_err());
}
