use crate::atoms;
use crate::error::{classify, NativeError};
use rustler::{Atom, Binary, Encoder, Env, OwnedBinary, Term};
use turso::params::Params;
use turso::{Rows, Value};

#[derive(Debug)]
pub(crate) enum SqlValue {
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

pub(crate) fn decode_params(
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

pub(crate) async fn collect_rows(
    mut rows: Rows,
    operation: Atom,
) -> Result<Vec<Vec<SqlValue>>, NativeError> {
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

pub(crate) fn decode_row(
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
