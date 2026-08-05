use crate::atoms;
use crate::error::NativeError;
use crate::resources::{snapshot, ResourceSnapshot, SmokeResource, SMOKE_RESOURCES};
use crate::runtime::runtime_for;
use rustler::{Atom, ResourceArc};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicBool, Ordering};

#[rustler::nif(schedule = "DirtyIo")]
fn smoke() -> Result<u64, NativeError> {
    runtime_for(atoms::smoke()).map(|runtime| runtime.block_on(async { 1 }))
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
    atoms::ok()
}

#[rustler::nif]
fn resource_snapshot() -> ResourceSnapshot {
    snapshot()
}
