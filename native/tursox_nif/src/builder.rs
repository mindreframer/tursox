use turso::Builder;

pub(crate) fn supported_builder_feature(feature: &str) -> bool {
    matches!(
        feature,
        "attach"
            | "custom_types"
            | "generated_columns"
            | "index_method"
            | "materialized_views"
            | "vacuum"
            | "multiprocess_wal"
            | "without_rowid"
    )
}

pub(crate) fn build_database(path: &str, features: &[String]) -> Builder {
    let mut builder = Builder::new_local(path);
    for feature in features {
        builder = match feature.as_str() {
            "attach" => builder.experimental_attach(true),
            "custom_types" => builder.experimental_custom_types(true),
            "generated_columns" => builder.experimental_generated_columns(true),
            "index_method" => builder.experimental_index_method(true),
            "materialized_views" => builder.experimental_materialized_views(true),
            "vacuum" => builder.experimental_vacuum(true),
            "multiprocess_wal" => builder.experimental_multiprocess_wal(true),
            "without_rowid" => builder.experimental_without_rowid(true),
            _ => builder,
        };
    }
    builder
}
