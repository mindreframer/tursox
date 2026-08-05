use crate::atoms;
use crate::builder::{build_database, supported_builder_feature};
use crate::error::{classify, lock_error, NativeError};
use crate::resources::{ConnectionResource, DatabaseResource, CONNECTIONS, DATABASES};
use crate::runtime::runtime_for;
use crate::values::{collect_rows, SqlValue};
use rustler::{Atom, ResourceArc};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::Duration;

#[rustler::nif(schedule = "DirtyIo")]
fn database_open(
    path: String,
    features: Vec<String>,
) -> Result<ResourceArc<DatabaseResource>, NativeError> {
    let operation = atoms::database_open();
    if let Some(feature) = features
        .iter()
        .find(|feature| !supported_builder_feature(feature))
    {
        return Err(NativeError::unsupported(
            operation,
            format!("unsupported database builder feature: {feature}"),
        ));
    }
    let runtime = runtime_for(operation)?;
    let database = runtime
        .block_on(build_database(&path, &features).build())
        .map_err(|error| classify(error, operation))?;
    DATABASES.fetch_add(1, Ordering::AcqRel);
    Ok(ResourceArc::new(DatabaseResource {
        inner: Mutex::new(Some(database)),
        open: AtomicBool::new(true),
        counted: AtomicBool::new(true),
    }))
}

#[rustler::nif(schedule = "DirtyIo")]
fn database_close(database: ResourceArc<DatabaseResource>) -> Atom {
    database.close();
    atoms::ok()
}

#[rustler::nif(schedule = "DirtyIo")]
fn database_connect(
    database: ResourceArc<DatabaseResource>,
    busy_timeout_ms: u64,
) -> Result<ResourceArc<ConnectionResource>, NativeError> {
    let operation = atoms::database_connect();
    database.ensure_open(operation)?;
    let inner = database.inner.lock().map_err(|_| lock_error(operation))?;
    let connection = inner
        .as_ref()
        .ok_or_else(|| NativeError::closed(operation, "database"))?
        .connect()
        .map_err(|error| classify(error, operation))?;
    drop(inner);
    connection
        .busy_timeout(Duration::from_millis(busy_timeout_ms))
        .map_err(|error| classify(error, operation))?;
    CONNECTIONS.fetch_add(1, Ordering::AcqRel);
    Ok(ResourceArc::new(ConnectionResource {
        inner: Mutex::new(Some(connection)),
        database,
        open: AtomicBool::new(true),
        counted: AtomicBool::new(true),
    }))
}

#[rustler::nif(schedule = "DirtyIo")]
fn connection_close(connection: ResourceArc<ConnectionResource>) -> Atom {
    connection.close();
    atoms::ok()
}

#[rustler::nif]
fn connection_status(connection: ResourceArc<ConnectionResource>) -> Result<bool, NativeError> {
    let operation = atoms::connection_status();
    connection.ensure_open(operation)?;
    let inner = connection.inner.lock().map_err(|_| lock_error(operation))?;
    inner
        .as_ref()
        .ok_or_else(|| NativeError::closed(operation, "connection"))?
        .is_autocommit()
        .map_err(|error| classify(error, operation))
}

#[rustler::nif(schedule = "DirtyIo")]
fn connection_cache_flush(
    connection: ResourceArc<ConnectionResource>,
) -> Result<Atom, NativeError> {
    let operation = atoms::connection_cache_flush();
    connection.ensure_open(operation)?;
    let inner = connection.inner.lock().map_err(|_| lock_error(operation))?;
    inner
        .as_ref()
        .ok_or_else(|| NativeError::closed(operation, "connection"))?
        .cacheflush()
        .map_err(|error| classify(error, operation))?;
    Ok(atoms::ok())
}

fn pragma_sql(name: &str, value: Option<&str>) -> String {
    match value {
        Some(value) => format!("PRAGMA {name} = {value}"),
        None => format!("PRAGMA {name}"),
    }
}

fn pragma_argument_sql(name: &str, argument: &str) -> String {
    format!("PRAGMA {name}({argument})")
}

fn run_pragma(
    connection: &ConnectionResource,
    name: &str,
    value: Option<&str>,
    operation: Atom,
) -> Result<Vec<Vec<SqlValue>>, NativeError> {
    connection.ensure_open(operation)?;
    let inner = connection.inner.lock().map_err(|_| lock_error(operation))?;
    let connection = inner
        .as_ref()
        .ok_or_else(|| NativeError::closed(operation, "connection"))?;
    runtime_for(operation)?.block_on(async {
        collect_rows(
            connection
                .query(pragma_sql(name, value), ())
                .await
                .map_err(|error| classify(error, operation))?,
            operation,
        )
        .await
    })
}

#[rustler::nif(schedule = "DirtyIo")]
fn connection_pragma_query(
    connection: ResourceArc<ConnectionResource>,
    name: String,
) -> Result<Vec<Vec<SqlValue>>, NativeError> {
    run_pragma(&connection, &name, None, atoms::connection_pragma_query())
}

#[rustler::nif(schedule = "DirtyIo")]
fn connection_pragma_query_argument(
    connection: ResourceArc<ConnectionResource>,
    name: String,
    argument: String,
) -> Result<Vec<Vec<SqlValue>>, NativeError> {
    let operation = atoms::connection_pragma_query_argument();
    connection.ensure_open(operation)?;
    let inner = connection.inner.lock().map_err(|_| lock_error(operation))?;
    let connection = inner
        .as_ref()
        .ok_or_else(|| NativeError::closed(operation, "connection"))?;
    runtime_for(operation)?.block_on(async {
        collect_rows(
            connection
                .query(pragma_argument_sql(&name, &argument), ())
                .await
                .map_err(|error| classify(error, operation))?,
            operation,
        )
        .await
    })
}

#[rustler::nif(schedule = "DirtyIo")]
fn connection_pragma_update(
    connection: ResourceArc<ConnectionResource>,
    name: String,
    value: String,
) -> Result<Vec<Vec<SqlValue>>, NativeError> {
    run_pragma(
        &connection,
        &name,
        Some(&value),
        atoms::connection_pragma_update(),
    )
}
