//! Oura BLE application protocol constants and frame builders.
//! Ported from tools/oura_protocol.py — keep in sync via core tests.

pub struct OuraProtocol;

impl OuraProtocol {
    pub const CMD_FIRMWARE: &'static [u8] = &[0x08, 0x03, 0x00, 0x00, 0x00];
    pub const CMD_BATTERY: &'static [u8] = &[0x0c, 0x00];
    pub const CMD_AUTH_NONCE: &'static [u8] = &[0x2f, 0x01, 0x2b];

    pub const SERVICE_UUID: &'static str = "98ed0001-a541-11e4-b6a0-0002a5d5c51b";
    pub const CMD_CHAR_UUID: &'static str = "98ed0002-a541-11e4-b6a0-0002a5d5c51b";
    pub const DATA_CHAR_UUID: &'static str = "98ed0003-a541-11e4-b6a0-0002a5d5c51b";

    /// Build a tagged packet: [tag, len, payload...]
    pub fn packet(tag: u8, payload: &[u8]) -> Vec<u8> {
        assert!(payload.len() <= 255);
        let mut out = Vec::with_capacity(2 + payload.len());
        out.push(tag);
        out.push(payload.len() as u8);
        out.extend_from_slice(payload);
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn packet_roundtrip() {
        let frame = OuraProtocol::packet(0x0c, &[]);
        assert_eq!(frame, vec![0x0c, 0x00]);
    }
}
