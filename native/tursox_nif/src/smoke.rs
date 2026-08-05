use crate::atoms;
use crate::error::NativeError;
use crate::resources::{snapshot, ResourceSnapshot, SmokeResource, SMOKE_RESOURCES};
use crate::runtime::runtime_for;
use rustler::{Atom, ResourceArc};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Once;

static PANIC_HOOK: Once = Once::new();
const PROBE_PANIC: &str = "intentional smoke panic";

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
    PANIC_HOOK.call_once(|| {
        let previous = std::panic::take_hook();
        std::panic::set_hook(Box::new(move |info| {
            let expected = info.payload().downcast_ref::<&str>() == Some(&PROBE_PANIC)
                || info.payload().downcast_ref::<String>().map(String::as_str) == Some(PROBE_PANIC);
            if !expected {
                previous(info);
            }
        }));
    });

    catch_unwind(AssertUnwindSafe(|| panic!("{PROBE_PANIC}"))).map_err(|_| {
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
