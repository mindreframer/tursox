use crate::atoms;
use crate::error::{classify, lock_error, NativeError};
use crate::resources::{
    decrement_once, ConnectionResource, CursorResource, StatementResource, CURSORS, STATEMENTS,
};
use crate::runtime::runtime_for;
use crate::values::{decode_params, decode_row, SqlValue};
use rustler::{Atom, ResourceArc, Term};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;

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
