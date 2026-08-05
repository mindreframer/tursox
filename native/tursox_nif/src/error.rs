use crate::atoms;
use rustler::{Atom, NifMap};
use turso::Error as TursoError;

#[derive(Debug, NifMap)]
pub(crate) struct NativeError {
    code: Atom,
    message: String,
    operation: Atom,
}

impl NativeError {
    pub(crate) fn new(code: Atom, operation: Atom, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
            operation,
        }
    }

    pub(crate) fn internal(operation: Atom, message: impl Into<String>) -> Self {
        Self::new(atoms::internal(), operation, message)
    }

    pub(crate) fn invalid(operation: Atom, message: impl Into<String>) -> Self {
        Self::new(atoms::invalid_argument(), operation, message)
    }

    pub(crate) fn unsupported(operation: Atom, message: impl Into<String>) -> Self {
        Self::new(atoms::unsupported(), operation, message)
    }

    pub(crate) fn closed(operation: Atom, resource: &str) -> Self {
        Self::new(
            atoms::closed(),
            operation,
            format!("{resource} resource is closed"),
        )
    }
}

pub(crate) fn classify(error: TursoError, operation: Atom) -> NativeError {
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

pub(crate) fn lock_error(operation: Atom) -> NativeError {
    NativeError::internal(operation, "native resource lock is poisoned")
}
