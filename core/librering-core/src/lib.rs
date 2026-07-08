//! Shared Oura Ring protocol — single source of truth for iOS, Android, and tools.
//!
//! Design: pure functions + explicit types (no hidden state) for testability.

pub mod error;
pub mod packet;
pub mod protocol;

pub use error::ProtocolError;
pub use packet::ParsedPacket;
pub use protocol::OuraProtocol;
