use crate::error::ProtocolError;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParsedPacket {
    pub tag: u8,
    pub payload: Vec<u8>,
}

impl ParsedPacket {
    pub fn parse(data: &[u8]) -> Result<Self, ProtocolError> {
        if data.len() < 2 {
            return Err(ProtocolError::TooShort);
        }
        let tag = data[0];
        let len = data[1] as usize;
        if data.len() < 2 + len {
            return Err(ProtocolError::LengthMismatch);
        }
        Ok(ParsedPacket {
            tag,
            payload: data[2..2 + len].to_vec(),
        })
    }

    pub fn battery_percent(&self) -> Option<u8> {
        if self.tag == 0x0d && !self.payload.is_empty() {
            Some(self.payload[0])
        } else {
            None
        }
    }
}
