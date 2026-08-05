use rustler::{Atom, Encoder, Env, NifMap, OwnedBinary, ResourceArc, Term};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Mutex, OnceLock};
use std::time::Duration;
use tokio::runtime::{Builder as RuntimeBuilder, Runtime};
use turso::{Builder, Connection, Database, Error as TursoError, Value};

mod atoms {
    rustler::atoms! {
        ok,
        blob,
        busy,
        busy_snapshot,
        constraint,
        readonly,
        database_full,
        interrupt,
        io,
        corrupt,
        misuse,
        conversion,
        invalid_argument,
        closed,
        unsupported,
        internal,
        smoke,
        smoke_panic,
        database_open,
        database_close,
        database_connect,
        connection_close,
        connection_status,
        connection_cache_flush,
        connection_pragma_query,
        connection_pragma_update,
    }
}

static RUNTIME: OnceLock<Result<Runtime, String>> = OnceLock::new();
static SMOKE_RESOURCES: AtomicU64 = AtomicU64::new(0);
static DATABASES: AtomicU64 = AtomicU64::new(0);
static CONNECTIONS: AtomicU64 = AtomicU64::new(0);

#[derive(Debug, NifMap)]
struct NativeError {
    code: Atom,
    message: String,
    operation: Atom,
}

impl NativeError {
    fn new(code: Atom, operation: Atom, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
            operation,
        }
    }

    fn internal(operation: Atom, message: impl Into<String>) -> Self {
        Self::new(atoms::internal(), operation, message)
    }

    fn closed(operation: Atom, resource: &str) -> Self {
        Self::new(
            atoms::closed(),
            operation,
            format!("{resource} resource is closed"),
        )
    }
}

fn classify(error: TursoError, operation: Atom) -> NativeError {
    let code = match &error {
        TursoError::Busy(_) => atoms::busy(),
        TursoError::BusySnapshot(_) => atoms::busy_snapshot(),
        TursoError::Constraint(_) => atoms::constraint(),
        TursoError::Readonly(_) => atoms::readonly(),
        TursoError::DatabaseFull(_) => atoms::database_full(),
        TursoError::Interrupt(_) => atoms::interrupt(),
        TursoError::IoError(..) => atoms::io(),
        TursoError::Corrupt(_) | TursoError::NotAdb(_) => atoms::corrupt(),
        TursoError::Misuse(_) => atoms::misuse(),
        TursoError::ConversionFailure(_) | TursoError::ToSqlConversionFailure(_) => {
            atoms::conversion()
        }
        TursoError::QueryReturnedNoRows | TursoError::Error(_) => atoms::internal(),
    };
    NativeError::new(code, operation, error.to_string())
}

fn lock_error(operation: Atom) -> NativeError {
    NativeError::internal(operation, "native resource lock is poisoned")
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
        decrement_once(&self.counted, &SMOKE_RESOURCES);
    }
}

impl Drop for SmokeResource {
    fn drop(&mut self) {
        self.close();
    }
}

#[rustler::resource_impl]
impl rustler::Resource for SmokeResource {}

struct DatabaseResource {
    inner: Mutex<Option<Database>>,
    open: AtomicBool,
    counted: AtomicBool,
}

impl DatabaseResource {
    fn close(&self) {
        self.open.store(false, Ordering::Release);
        if let Ok(mut inner) = self.inner.lock() {
            inner.take();
        }
        decrement_once(&self.counted, &DATABASES);
    }

    fn ensure_open(&self, operation: Atom) -> Result<(), NativeError> {
        if self.open.load(Ordering::Acquire) {
            Ok(())
        } else {
            Err(NativeError::closed(operation, "database"))
        }
    }
}

impl Drop for DatabaseResource {
    fn drop(&mut self) {
        self.close();
    }
}

#[rustler::resource_impl]
impl rustler::Resource for DatabaseResource {}

struct ConnectionResource {
    inner: Mutex<Option<Connection>>,
    database: ResourceArc<DatabaseResource>,
    open: AtomicBool,
    counted: AtomicBool,
}

impl ConnectionResource {
    fn close(&self) {
        self.open.store(false, Ordering::Release);
        if let Ok(mut inner) = self.inner.lock() {
            inner.take();
        }
        decrement_once(&self.counted, &CONNECTIONS);
    }

    fn ensure_open(&self, operation: Atom) -> Result<(), NativeError> {
        self.database.ensure_open(operation)?;
        if self.open.load(Ordering::Acquire) {
            Ok(())
        } else {
            Err(NativeError::closed(operation, "connection"))
        }
    }
}

impl Drop for ConnectionResource {
    fn drop(&mut self) {
        self.close();
    }
}

#[rustler::resource_impl]
impl rustler::Resource for ConnectionResource {}

fn decrement_once(flag: &AtomicBool, counter: &AtomicU64) {
    if flag.swap(false, Ordering::AcqRel) {
        counter.fetch_sub(1, Ordering::AcqRel);
    }
}

fn runtime() -> Result<&'static Runtime, String> {
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

fn runtime_for(operation: Atom) -> Result<&'static Runtime, NativeError> {
    runtime().map_err(|message| NativeError::internal(operation, message))
}

fn build_database(path: &str, features: &[String]) -> Builder {
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
            "mvcc_passive_checkpoint" => builder.experimental_mvcc_passive_checkpoint(true),
            _ => builder,
        };
    }
    builder
}

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

#[rustler::nif(schedule = "DirtyIo")]
fn database_open(
    path: String,
    features: Vec<String>,
) -> Result<ResourceArc<DatabaseResource>, NativeError> {
    let runtime = runtime_for(atoms::database_open())?;
    let database = runtime
        .block_on(build_database(&path, &features).build())
        .map_err(|error| classify(error, atoms::database_open()))?;
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

enum SqlValue {
    Null,
    Integer(i64),
    Real(f64),
    Text(String),
    Blob(Vec<u8>),
}

impl From<Value> for SqlValue {
    fn from(value: Value) -> Self {
        match value {
            Value::Null => Self::Null,
            Value::Integer(value) => Self::Integer(value),
            Value::Real(value) => Self::Real(value),
            Value::Text(value) => Self::Text(value),
            Value::Blob(value) => Self::Blob(value),
        }
    }
}

impl Encoder for SqlValue {
    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        match self {
            Self::Null => rustler::types::atom::nil().encode(env),
            Self::Integer(value) => value.encode(env),
            Self::Real(value) => value.encode(env),
            Self::Text(value) => value.encode(env),
            Self::Blob(value) => {
                let mut binary = OwnedBinary::new(value.len()).expect("binary allocation failed");
                binary.as_mut_slice().copy_from_slice(value);
                (atoms::blob(), binary.release(env)).encode(env)
            }
        }
    }
}

fn pragma_sql(name: &str, value: Option<&str>) -> String {
    match value {
        Some(value) => format!("PRAGMA {name} = {value}"),
        None => format!("PRAGMA {name}"),
    }
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
        let mut rows = connection
            .query(pragma_sql(name, value), ())
            .await
            .map_err(|error| classify(error, operation))?;
        let columns = rows.column_count();
        let mut result = Vec::new();
        while let Some(row) = rows
            .next()
            .await
            .map_err(|error| classify(error, operation))?
        {
            let mut values = Vec::with_capacity(columns);
            for index in 0..columns {
                values.push(SqlValue::from(
                    row.get_value(index)
                        .map_err(|error| classify(error, operation))?,
                ));
            }
            result.push(values);
        }
        Ok(result)
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

#[rustler::nif]
fn resource_snapshot() -> ResourceSnapshot {
    ResourceSnapshot {
        databases: DATABASES.load(Ordering::Acquire),
        connections: CONNECTIONS.load(Ordering::Acquire),
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

    #[test]
    fn unknown_features_are_inert_after_elixir_validation() {
        let _builder = build_database(":memory:", &["unknown".to_string()]);
    }
}
