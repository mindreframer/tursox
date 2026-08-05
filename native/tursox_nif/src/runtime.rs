use crate::error::NativeError;
use rustler::Atom;
use std::sync::OnceLock;
use tokio::runtime::{Builder as RuntimeBuilder, Runtime};

static RUNTIME: OnceLock<Result<Runtime, String>> = OnceLock::new();

pub(crate) fn runtime() -> Result<&'static Runtime, String> {
    RUNTIME
        .get_or_init(|| {
            RuntimeBuilder::new_multi_thread()
                .enable_all()
                .thread_name("tursox-runtime")
                .build()
                .map_err(|error| error.to_string())
        })
        .as_ref()
        .map_err(Clone::clone)
}

pub(crate) fn runtime_for(operation: Atom) -> Result<&'static Runtime, NativeError> {
    runtime().map_err(|message| NativeError::internal(operation, message))
}
