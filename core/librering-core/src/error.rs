use thiserror::Error;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum ProtocolError {
    #[error("packet too short")]
    TooShort,
    #[error("invalid tag: {0}")]
    InvalidTag(u8),
    #[error("payload length mismatch")]
    LengthMismatch,
}
