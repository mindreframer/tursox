use turso::{Builder, EncryptionOpts};

pub(crate) struct EncryptionConfig {
    pub(crate) cipher: String,
    pub(crate) hexkey: String,
}

pub(crate) fn supported_builder_feature(feature: &str) -> bool {
    matches!(
        feature,
        "attach"
            | "autovacuum"
            | "custom_types"
            | "encryption"
            | "generated_columns"
            | "index_method"
            | "materialized_views"
            | "mvcc_passive_checkpoint"
            | "runtime_extensions"
            | "vacuum"
            | "views"
            | "multiprocess_wal"
            | "without_rowid"
    )
}

pub(crate) fn build_database(
    path: &str,
    features: &[String],
    encryption: Option<EncryptionConfig>,
) -> Builder {
    let mut builder = Builder::new_local(path);
    for feature in features {
        builder = match feature.as_str() {
            "attach" => builder.experimental_attach(true),
            "autovacuum" => builder.experimental_autovacuum(true),
            "custom_types" => builder.experimental_custom_types(true),
            "encryption" => builder.experimental_encryption(true),
            "generated_columns" => builder.experimental_generated_columns(true),
            "index_method" => builder.experimental_index_method(true),
            "materialized_views" => builder.experimental_materialized_views(true),
            "mvcc_passive_checkpoint" => builder.experimental_mvcc_passive_checkpoint(true),
            "vacuum" => builder.experimental_vacuum(true),
            "views" => builder.experimental_materialized_views(true),
            "multiprocess_wal" => builder.experimental_multiprocess_wal(true),
            "without_rowid" => builder.experimental_without_rowid(true),
            _ => builder,
        };
    }
    match encryption {
        Some(config) => builder.with_encryption(EncryptionOpts {
            cipher: config.cipher,
            hexkey: config.hexkey,
        }),
        None => builder,
    }
}
