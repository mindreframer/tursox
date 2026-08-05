use crate::atoms;
use crate::error::NativeError;
use rustler::{Atom, NifMap, ResourceArc};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Mutex;
use turso::{Connection, Database, Rows, Statement};

pub(crate) static SMOKE_RESOURCES: AtomicU64 = AtomicU64::new(0);
pub(crate) static DATABASES: AtomicU64 = AtomicU64::new(0);
pub(crate) static CONNECTIONS: AtomicU64 = AtomicU64::new(0);
pub(crate) static STATEMENTS: AtomicU64 = AtomicU64::new(0);
pub(crate) static CURSORS: AtomicU64 = AtomicU64::new(0);

#[derive(NifMap)]
pub(crate) struct ResourceSnapshot {
    databases: u64,
    connections: u64,
    statements: u64,
    cursors: u64,
    smoke: u64,
}

pub(crate) fn snapshot() -> ResourceSnapshot {
    ResourceSnapshot {
        databases: DATABASES.load(Ordering::Acquire),
        connections: CONNECTIONS.load(Ordering::Acquire),
        statements: STATEMENTS.load(Ordering::Acquire),
        cursors: CURSORS.load(Ordering::Acquire),
        smoke: SMOKE_RESOURCES.load(Ordering::Acquire),
    }
}

pub(crate) struct SmokeResource {
    pub(crate) counted: AtomicBool,
}

impl SmokeResource {
    pub(crate) fn close(&self) {
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

pub(crate) struct DatabaseResource {
    pub(crate) inner: Mutex<Option<Database>>,
    pub(crate) open: AtomicBool,
    pub(crate) counted: AtomicBool,
}

impl DatabaseResource {
    pub(crate) fn close(&self) {
        self.open.store(false, Ordering::Release);
        if let Ok(mut inner) = self.inner.lock() {
            inner.take();
        }
        decrement_once(&self.counted, &DATABASES);
    }

    pub(crate) fn ensure_open(&self, operation: Atom) -> Result<(), NativeError> {
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

pub(crate) struct ConnectionResource {
    pub(crate) inner: Mutex<Option<Connection>>,
    pub(crate) database: ResourceArc<DatabaseResource>,
    pub(crate) open: AtomicBool,
    pub(crate) counted: AtomicBool,
}

impl ConnectionResource {
    pub(crate) fn close(&self) {
        self.open.store(false, Ordering::Release);
        if let Ok(mut inner) = self.inner.lock() {
            inner.take();
        }
        decrement_once(&self.counted, &CONNECTIONS);
    }

    pub(crate) fn ensure_open(&self, operation: Atom) -> Result<(), NativeError> {
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

pub(crate) struct StatementResource {
    pub(crate) inner: Mutex<Option<Statement>>,
    pub(crate) connection: ResourceArc<ConnectionResource>,
    pub(crate) open: AtomicBool,
    pub(crate) active: AtomicBool,
    pub(crate) counted: AtomicBool,
}

impl StatementResource {
    pub(crate) fn close(&self) {
        self.open.store(false, Ordering::Release);
        if let Ok(mut inner) = self.inner.lock() {
            inner.take();
        }
        decrement_once(&self.counted, &STATEMENTS);
    }

    pub(crate) fn ensure_open(&self, operation: Atom) -> Result<(), NativeError> {
        self.connection.ensure_open(operation)?;
        ensure_flag(&self.open, operation, "statement")
    }

    pub(crate) fn ensure_idle(&self, operation: Atom) -> Result<(), NativeError> {
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

pub(crate) struct CursorResource {
    pub(crate) inner: Mutex<Option<Rows>>,
    pub(crate) statement: ResourceArc<StatementResource>,
    pub(crate) open: AtomicBool,
    pub(crate) exhausted: AtomicBool,
    pub(crate) counted: AtomicBool,
}

impl CursorResource {
    pub(crate) fn close(&self) {
        self.open.store(false, Ordering::Release);
        if let Ok(mut inner) = self.inner.lock() {
            inner.take();
        }
        self.statement.active.store(false, Ordering::Release);
        decrement_once(&self.counted, &CURSORS);
    }

    pub(crate) fn ensure_open(&self, operation: Atom) -> Result<(), NativeError> {
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

pub(crate) fn decrement_once(flag: &AtomicBool, counter: &AtomicU64) {
    if flag.swap(false, Ordering::AcqRel) {
        counter.fetch_sub(1, Ordering::AcqRel);
    }
}
