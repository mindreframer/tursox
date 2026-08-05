mod atoms;
mod builder;
mod database;
mod error;
mod query;
mod resources;
mod runtime;
mod smoke;
mod values;

rustler::init!("Elixir.Tursox.Native");

#[cfg(test)]
mod tests {
    use crate::builder::supported_builder_feature;
    use crate::resources::{SmokeResource, SMOKE_RESOURCES};
    use crate::runtime;
    use std::sync::atomic::{AtomicBool, Ordering};

    #[test]
    fn runtime_is_stable() {
        assert!(runtime::runtime().is_ok());
        assert!(std::ptr::eq(
            runtime::runtime().unwrap(),
            runtime::runtime().unwrap()
        ));
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

    #[test]
    fn builder_feature_allowlist_is_strict() {
        assert!(supported_builder_feature("attach"));
        assert!(!supported_builder_feature("mvcc_passive_checkpoint"));
        assert!(!supported_builder_feature("unknown"));
    }
}
