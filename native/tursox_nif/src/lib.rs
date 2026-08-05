use rustler::{Atom, Binary, Encoder, Env, NifMap, OwnedBinary, ResourceArc, Term};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Mutex, OnceLock};
use std::time::Duration;
use tokio::runtime::{Builder as RuntimeBuilder, Runtime};
use turso::params::Params;
use turso::{Builder, Connection, Database, Error as TursoError, Rows, Statement, Value};

mod atoms {
    rustler::atoms! {
        ok,
        blob,
        nil,
        true_atom = "true",
        false_atom = "false",
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
        connection_pragma_query_argument,
        connection_pragma_update,
        connection_execute,
        connection_execute_batch,
        connection_prepare,
        connection_last_insert_rowid,
        statement_close,
        statement_execute,
        statement_query,
        statement_reset,
        statement_columns,
        cursor_fetch,
        cursor_close,
    }
}

static RUNTIME: OnceLock<Result<Runtime, String>> = OnceLock::new();
static SMOKE_RESOURCES: AtomicU64 = AtomicU64::new(0);
static DATABASES: AtomicU64 = AtomicU64::new(0);
static CONNECTIONS: AtomicU64 = AtomicU64::new(0);
static STATEMENTS: AtomicU64 = AtomicU64::new(0);
static CURSORS: AtomicU64 = AtomicU64::new(0);

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

    fn invalid(operation: Atom, message: impl Into<String>) -> Self {
        Self::new(atoms::invalid_argument(), operation, message)
    }

    fn unsupported(operation: Atom, message: impl Into<String>) -> Self {
        Self::new(atoms::unsupported(), operation, message)
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
        TursoError::Error(message) if message.to_ascii_lowercase().contains("conflict") => {
            atoms::busy_snapshot()
        }
        TursoError::Error(_) => atoms::misuse(),
        TursoError::QueryReturnedNoRows => atoms::internal(),
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
        ensure_flag(&self.open, operation, "database")
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
        ensure_flag(&self.open, operation, "connection")
    }
}

impl Drop for ConnectionResource {
    fn drop(&mut self) {
        self.close();
    }
}

#[rustler::resource_impl]
impl rustler::Resource for ConnectionResource {}

struct StatementResource {
    inner: Mutex<Option<Statement>>,
    connection: ResourceArc<ConnectionResource>,
    open: AtomicBool,
    active: AtomicBool,
    counted: AtomicBool,
}

impl StatementResource {
    fn close(&self) {
        self.open.store(false, Ordering::Release);
        if let Ok(mut inner) = self.inner.lock() {
            inner.take();
        }
        decrement_once(&self.counted, &STATEMENTS);
    }

    fn ensure_open(&self, operation: Atom) -> Result<(), NativeError> {
        self.connection.ensure_open(operation)?;
        ensure_flag(&self.open, operation, "statement")
    }

    fn ensure_idle(&self, operation: Atom) -> Result<(), NativeError> {
        if self.active.load(Ordering::Acquire) {
            Err(NativeError::new(
                atoms::misuse(),
                operation,
                "statement has an active cursor",
            ))
        } else {
            Ok(())
        }
    }
}

impl Drop for StatementResource {
    fn drop(&mut self) {
        self.close();
    }
}

#[rustler::resource_impl]
impl rustler::Resource for StatementResource {}

struct CursorResource {
    inner: Mutex<Option<Rows>>,
    statement: ResourceArc<StatementResource>,
    open: AtomicBool,
    exhausted: AtomicBool,
    counted: AtomicBool,
}

impl CursorResource {
    fn close(&self) {
        self.open.store(false, Ordering::Release);
        if let Ok(mut inner) = self.inner.lock() {
            inner.take();
        }
        self.statement.active.store(false, Ordering::Release);
        decrement_once(&self.counted, &CURSORS);
    }

    fn ensure_open(&self, operation: Atom) -> Result<(), NativeError> {
        self.statement.ensure_open(operation)?;
        ensure_flag(&self.open, operation, "cursor")
    }
}

impl Drop for CursorResource {
    fn drop(&mut self) {
        self.close();
    }
}

#[rustler::resource_impl]
impl rustler::Resource for CursorResource {}

fn ensure_flag(flag: &AtomicBool, operation: Atom, resource: &str) -> Result<(), NativeError> {
    if flag.load(Ordering::Acquire) {
        Ok(())
    } else {
        Err(NativeError::closed(operation, resource))
    }
}

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

fn supported_builder_feature(feature: &str) -> bool {
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

#[derive(Debug)]
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
            Self::Null => atoms::nil().encode(env),
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

fn decode_value(term: Term<'_>, index: usize, operation: Atom) -> Result<Value, NativeError> {
    if let Ok((tag, binary)) = term.decode::<(Atom, Binary)>() {
        if tag == atoms::blob() {
            return Ok(Value::Blob(binary.as_slice().to_vec()));
        }
    }
    if let Ok(atom) = term.decode::<Atom>() {
        if atom == atoms::nil() {
            return Ok(Value::Null);
        }
        if atom == atoms::true_atom() {
            return Ok(Value::Integer(1));
        }
        if atom == atoms::false_atom() {
            return Ok(Value::Integer(0));
        }
    }
    if let Ok(value) = term.decode::<i64>() {
        return Ok(Value::Integer(value));
    }
    if let Ok(value) = term.decode::<f64>() {
        return Ok(Value::Real(value));
    }
    if let Ok(value) = term.decode::<String>() {
        return Ok(Value::Text(value));
    }
    Err(NativeError::invalid(
        operation,
        format!("invalid bound parameter at index {index}"),
    ))
}

fn decode_params(
    named: bool,
    names: Vec<String>,
    terms: Vec<Term<'_>>,
    operation: Atom,
) -> Result<Params, NativeError> {
    let values = terms
        .into_iter()
        .enumerate()
        .map(|(index, term)| decode_value(term, index, operation))
        .collect::<Result<Vec<_>, _>>()?;
    if named {
        if names.len() != values.len() {
            return Err(NativeError::invalid(
                operation,
                "named parameter names and values differ in length",
            ));
        }
        Ok(Params::Named(
            names
                .into_iter()
                .zip(values)
                .map(|(name, value)| (name.into(), value))
                .collect(),
        ))
    } else if names.is_empty() {
        Ok(Params::Positional(values))
    } else {
        Err(NativeError::invalid(
            operation,
            "positional parameters cannot include names",
        ))
    }
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

async fn collect_rows(mut rows: Rows, operation: Atom) -> Result<Vec<Vec<SqlValue>>, NativeError> {
    let columns = rows.column_count();
    let mut result = Vec::new();
    while let Some(row) = rows
        .next()
        .await
        .map_err(|error| classify(error, operation))?
    {
        result.push(decode_row(&row, columns, operation)?);
    }
    Ok(result)
}

fn decode_row(
    row: &turso::Row,
    columns: usize,
    operation: Atom,
) -> Result<Vec<SqlValue>, NativeError> {
    (0..columns)
        .map(|index| {
            row.get_value(index)
                .map(SqlValue::from)
                .map_err(|error| classify(error, operation))
        })
        .collect()
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

#[rustler::nif(schedule = "DirtyIo")]
fn connection_execute<'a>(
    connection: ResourceArc<ConnectionResource>,
    sql: String,
    named: bool,
    names: Vec<String>,
    terms: Vec<Term<'a>>,
) -> Result<(u64, i64), NativeError> {
    let operation = atoms::connection_execute();
    connection.ensure_open(operation)?;
    let params = decode_params(named, names, terms, operation)?;
    let inner = connection.inner.lock().map_err(|_| lock_error(operation))?;
    let connection = inner
        .as_ref()
        .ok_or_else(|| NativeError::closed(operation, "connection"))?;
    let changed = runtime_for(operation)?
        .block_on(connection.execute(sql, params))
        .map_err(|error| classify(error, operation))?;
    Ok((changed, connection.last_insert_rowid()))
}

#[rustler::nif(schedule = "DirtyIo")]
fn connection_execute_batch(
    connection: ResourceArc<ConnectionResource>,
    sql: String,
) -> Result<Atom, NativeError> {
    let operation = atoms::connection_execute_batch();
    connection.ensure_open(operation)?;
    let inner = connection.inner.lock().map_err(|_| lock_error(operation))?;
    let connection = inner
        .as_ref()
        .ok_or_else(|| NativeError::closed(operation, "connection"))?;
    runtime_for(operation)?
        .block_on(connection.execute_batch(sql))
        .map_err(|error| classify(error, operation))?;
    Ok(atoms::ok())
}

#[rustler::nif(schedule = "DirtyIo")]
fn connection_prepare(
    connection: ResourceArc<ConnectionResource>,
    sql: String,
) -> Result<ResourceArc<StatementResource>, NativeError> {
    let operation = atoms::connection_prepare();
    connection.ensure_open(operation)?;
    let inner = connection.inner.lock().map_err(|_| lock_error(operation))?;
    let connection_value = inner
        .as_ref()
        .ok_or_else(|| NativeError::closed(operation, "connection"))?;
    let statement = runtime_for(operation)?
        .block_on(connection_value.prepare(sql))
        .map_err(|error| classify(error, operation))?;
    drop(inner);
    STATEMENTS.fetch_add(1, Ordering::AcqRel);
    Ok(ResourceArc::new(StatementResource {
        inner: Mutex::new(Some(statement)),
        connection,
        open: AtomicBool::new(true),
        active: AtomicBool::new(false),
        counted: AtomicBool::new(true),
    }))
}

#[rustler::nif]
fn connection_last_insert_rowid(
    connection: ResourceArc<ConnectionResource>,
) -> Result<i64, NativeError> {
    let operation = atoms::connection_last_insert_rowid();
    connection.ensure_open(operation)?;
    let inner = connection.inner.lock().map_err(|_| lock_error(operation))?;
    Ok(inner
        .as_ref()
        .ok_or_else(|| NativeError::closed(operation, "connection"))?
        .last_insert_rowid())
}

#[rustler::nif(schedule = "DirtyIo")]
fn statement_close(statement: ResourceArc<StatementResource>) -> Atom {
    statement.close();
    atoms::ok()
}

#[rustler::nif(schedule = "DirtyIo")]
fn statement_execute<'a>(
    statement: ResourceArc<StatementResource>,
    named: bool,
    names: Vec<String>,
    terms: Vec<Term<'a>>,
) -> Result<(u64, i64), NativeError> {
    let operation = atoms::statement_execute();
    statement.ensure_open(operation)?;
    statement.ensure_idle(operation)?;
    let params = decode_params(named, names, terms, operation)?;
    let connection_guard = statement
        .connection
        .inner
        .lock()
        .map_err(|_| lock_error(operation))?;
    let connection = connection_guard
        .as_ref()
        .ok_or_else(|| NativeError::closed(operation, "connection"))?;
    let mut inner = statement.inner.lock().map_err(|_| lock_error(operation))?;
    let changed = runtime_for(operation)?
        .block_on(
            inner
                .as_mut()
                .ok_or_else(|| NativeError::closed(operation, "statement"))?
                .execute(params),
        )
        .map_err(|error| classify(error, operation))?;
    Ok((changed, connection.last_insert_rowid()))
}

#[rustler::nif(schedule = "DirtyIo")]
fn statement_query<'a>(
    statement: ResourceArc<StatementResource>,
    named: bool,
    names: Vec<String>,
    terms: Vec<Term<'a>>,
) -> Result<ResourceArc<CursorResource>, NativeError> {
    let operation = atoms::statement_query();
    statement.ensure_open(operation)?;
    statement
        .active
        .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
        .map_err(|_| {
            NativeError::new(atoms::misuse(), operation, "statement has an active cursor")
        })?;
    let result = (|| {
        let params = decode_params(named, names, terms, operation)?;
        let _connection_guard = statement
            .connection
            .inner
            .lock()
            .map_err(|_| lock_error(operation))?;
        let mut inner = statement.inner.lock().map_err(|_| lock_error(operation))?;
        let rows = runtime_for(operation)?
            .block_on(
                inner
                    .as_mut()
                    .ok_or_else(|| NativeError::closed(operation, "statement"))?
                    .query(params),
            )
            .map_err(|error| classify(error, operation))?;
        CURSORS.fetch_add(1, Ordering::AcqRel);
        Ok(ResourceArc::new(CursorResource {
            inner: Mutex::new(Some(rows)),
            statement: statement.clone(),
            open: AtomicBool::new(true),
            exhausted: AtomicBool::new(false),
            counted: AtomicBool::new(true),
        }))
    })();
    if result.is_err() {
        statement.active.store(false, Ordering::Release);
    }
    result
}

#[rustler::nif]
fn statement_reset(statement: ResourceArc<StatementResource>) -> Result<Atom, NativeError> {
    let operation = atoms::statement_reset();
    statement.ensure_open(operation)?;
    statement.ensure_idle(operation)?;
    let inner = statement.inner.lock().map_err(|_| lock_error(operation))?;
    inner
        .as_ref()
        .ok_or_else(|| NativeError::closed(operation, "statement"))?
        .reset()
        .map_err(|error| classify(error, operation))?;
    Ok(atoms::ok())
}

#[rustler::nif]
fn statement_columns(
    statement: ResourceArc<StatementResource>,
) -> Result<Vec<(String, Option<String>)>, NativeError> {
    let operation = atoms::statement_columns();
    statement.ensure_open(operation)?;
    let inner = statement.inner.lock().map_err(|_| lock_error(operation))?;
    Ok(inner
        .as_ref()
        .ok_or_else(|| NativeError::closed(operation, "statement"))?
        .columns()
        .into_iter()
        .map(|column| {
            (
                column.name().to_string(),
                column.decl_type().map(str::to_string),
            )
        })
        .collect())
}

#[rustler::nif(schedule = "DirtyIo")]
fn cursor_fetch(
    cursor: ResourceArc<CursorResource>,
    max_rows: u64,
) -> Result<(bool, Vec<Vec<SqlValue>>), NativeError> {
    let operation = atoms::cursor_fetch();
    if cursor.exhausted.load(Ordering::Acquire) {
        return Ok((true, Vec::new()));
    }
    cursor.ensure_open(operation)?;
    if max_rows == 0 {
        return Err(NativeError::invalid(operation, "max_rows must be positive"));
    }
    let _connection_guard = cursor
        .statement
        .connection
        .inner
        .lock()
        .map_err(|_| lock_error(operation))?;
    let mut inner = cursor.inner.lock().map_err(|_| lock_error(operation))?;
    let rows = inner
        .as_mut()
        .ok_or_else(|| NativeError::closed(operation, "cursor"))?;
    let columns = rows.column_count();
    let runtime = runtime_for(operation)?;
    let mut result = Vec::with_capacity(usize::try_from(max_rows).unwrap_or(usize::MAX).min(1024));
    let mut done = false;
    for _ in 0..max_rows {
        match runtime
            .block_on(rows.next())
            .map_err(|error| classify(error, operation))?
        {
            Some(row) => result.push(decode_row(&row, columns, operation)?),
            None => {
                done = true;
                break;
            }
        }
    }
    if done {
        inner.take();
        cursor.open.store(false, Ordering::Release);
        cursor.exhausted.store(true, Ordering::Release);
        cursor.statement.active.store(false, Ordering::Release);
        decrement_once(&cursor.counted, &CURSORS);
    }
    Ok((done, result))
}

#[rustler::nif(schedule = "DirtyIo")]
fn cursor_close(cursor: ResourceArc<CursorResource>) -> Atom {
    cursor.close();
    atoms::ok()
}

#[rustler::nif]
fn resource_snapshot() -> ResourceSnapshot {
    ResourceSnapshot {
        databases: DATABASES.load(Ordering::Acquire),
        connections: CONNECTIONS.load(Ordering::Acquire),
        statements: STATEMENTS.load(Ordering::Acquire),
        cursors: CURSORS.load(Ordering::Acquire),
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
    fn builder_feature_allowlist_is_strict() {
        assert!(supported_builder_feature("attach"));
        assert!(!supported_builder_feature("mvcc_passive_checkpoint"));
        assert!(!supported_builder_feature("unknown"));
    }
}
