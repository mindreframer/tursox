use turso_ext::{register_extension, scalar, Value};

#[scalar(name = "tursox_fixture")]
fn tursox_fixture(_args: &[Value]) -> Value {
    Value::from_integer(4242)
}

register_extension! {
    scalars: { tursox_fixture },
}
