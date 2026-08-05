use rustler::{Atom, NifMap, ResourceArc};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::OnceLock;
use tokio::runtime::{Builder, Runtime};

mod atoms {
    rustler::atoms! {
        internal,
        smoke,
        smoke_panic,
    }
}

static RUNTIME: OnceLock<Result<Runtime, String>> = OnceLock::new();
static SMOKE_RESOURCES: AtomicU64 = AtomicU64::new(0);

#[derive(Debug, NifMap)]
struct NativeError {
    code: Atom,
    message: String,
    operation: Atom,
}

impl NativeError {
    fn internal(operation: Atom, message: impl Into<String>) -> Self {
        Self {
            code: atoms::internal(),
            message: message.into(),
            operation,
        }
    }
}

#[derive(NifMap)]
struct ResourceSnapshot {
    databases: u64,
    connections: u64,
    statements: u64,
    cursors: u64,
    smoke: u64,
}

struct SmokeResource {
    counted: AtomicBool,
}

impl SmokeResource {
    fn close(&self) {
        if self.counted.swap(false, Ordering::AcqRel) {
            SMOKE_RESOURCES.fetch_sub(1, Ordering::AcqRel);
        }
    }
}

impl Drop for SmokeResource {
    fn drop(&mut self) {
        self.close();
    }
}

#[rustler::resource_impl]
impl rustler::Resource for SmokeResource {}

fn runtime() -> Result<&'static Runtime, NativeError> {
    RUNTIME
        .get_or_init(|| {
            Builder::new_multi_thread()
                .enable_all()
                .thread_name("tursox-runtime")
                .build()
                .map_err(|error| error.to_string())
        })
        .as_ref()
        .map_err(|message| NativeError::internal(atoms::smoke(), message.clone()))
}

#[rustler::nif(schedule = "DirtyIo")]
fn smoke() -> Result<u64, NativeError> {
    runtime().map(|runtime| runtime.block_on(async { 1 }))
}

#[rustler::nif]
fn smoke_error() -> Result<u64, NativeError> {
    Err(NativeError::internal(
        atoms::smoke(),
        "deterministic native smoke error",
    ))
}

#[rustler::nif]
fn smoke_panic() -> Result<u64, NativeError> {
    catch_unwind(AssertUnwindSafe(|| panic!("intentional smoke panic"))).map_err(|_| {
        NativeError::internal(
            atoms::smoke_panic(),
            "native panic contained at NIF boundary",
        )
    })?;
    Ok(0)
}

#[rustler::nif]
fn smoke_resource_open() -> ResourceArc<SmokeResource> {
    SMOKE_RESOURCES.fetch_add(1, Ordering::AcqRel);
    ResourceArc::new(SmokeResource {
        counted: AtomicBool::new(true),
    })
}

#[rustler::nif]
fn smoke_resource_close(resource: ResourceArc<SmokeResource>) -> Atom {
    resource.close();
    rustler::types::atom::ok()
}

#[rustler::nif]
fn resource_snapshot() -> ResourceSnapshot {
    ResourceSnapshot {
        databases: 0,
        connections: 0,
        statements: 0,
        cursors: 0,
        smoke: SMOKE_RESOURCES.load(Ordering::Acquire),
    }
}

rustler::init!("Elixir.Tursox.Native");

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn runtime_is_stable() {
        assert!(runtime().is_ok());
        assert!(std::ptr::eq(runtime().unwrap(), runtime().unwrap()));
    }

    #[test]
    fn close_is_idempotent() {
        let resource = SmokeResource {
            counted: AtomicBool::new(true),
        };
        SMOKE_RESOURCES.fetch_add(1, Ordering::AcqRel);
        resource.close();
        resource.close();
        assert_eq!(SMOKE_RESOURCES.load(Ordering::Acquire), 0);
    }
}
