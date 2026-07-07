-- LibreRing Wireshark post-dissector for Oura Ring BLE ATT traffic
--
-- Install (macOS):
--   mkdir -p ~/.local/lib/wireshark/plugins
--   ln -sf "$(pwd)/dissectors/oura.lua" ~/.local/lib/wireshark/plugins/oura.lua
--   Restart Wireshark
--
-- Open a PacketLogger .pklg capture, filter: btatt || oura
--
-- Handle numbers are assigned per connection and may differ from your scan.
-- Update OURA_HANDLES below from services.json after each scan_oura.py run.

local oura_proto = Proto("oura", "Oura Ring BLE")

-- ATT opcodes (Bluetooth Core Spec, Vol 3, Part F)
local ATT_OPCODES = {
    [0x01] = "Error Response",
    [0x02] = "Exchange MTU Request",
    [0x03] = "Exchange MTU Response",
    [0x04] = "Find Information Request",
    [0x05] = "Find Information Response",
    [0x06] = "Find By Type Value Request",
    [0x07] = "Find By Type Value Response",
    [0x08] = "Read By Type Request",
    [0x09] = "Read By Type Response",
    [0x0A] = "Read Request",
    [0x0B] = "Read Response",
    [0x0C] = "Read Blob Request",
    [0x0D] = "Read Blob Response",
    [0x10] = "Read By Group Type Request",
    [0x11] = "Read By Group Type Response",
    [0x12] = "Write Request",
    [0x13] = "Write Response",
    [0x16] = "Prepare Write Request",
    [0x17] = "Prepare Write Response",
    [0x18] = "Execute Write Request",
    [0x19] = "Execute Write Response",
    [0x1B] = "Handle Value Notification",
    [0x1D] = "Handle Value Indication",
    [0x1E] = "Handle Value Confirmation",
    [0x52] = "Write Command",
    [0xD2] = "Signed Write Command",
}

-- Stable 128-bit UUIDs (community RE + scan_oura.py on Ring 4)
local OURA_UUIDS = {
    ["98ed0001-a541-11e4-b6a0-0002a5d5c51b"] = "Oura Ring Service",
    ["98ed0002-a541-11e4-b6a0-0002a5d5c51b"] = "RING_CMD_TX (write)",
    ["98ed0003-a541-11e4-b6a0-0002a5d5c51b"] = "RING_DATA_RX (read/notify)",
    ["98ed0004-a541-11e4-b6a0-0002a5d5c51b"] = "RING_DATA_EXT (read/write/notify/indicate)",
    ["98ed0005-a541-11e4-b6a0-0002a5d5c51b"] = "RING_NOTIFY_A",
    ["98ed0006-a541-11e4-b6a0-0002a5d5c51b"] = "RING_NOTIFY_B",
    ["00060000-f8ce-11e4-abf4-0002a5d5c51b"] = "Oura Aux Service",
    ["00060001-f8ce-11e4-abf4-0002a5d5c51b"] = "Oura Aux Channel",
}

-- Session-specific handles from services.json (Oura Ring 4, 2026-07-06)
local OURA_HANDLES = {
    [16] = { uuid = "98ed0001-a541-11e4-b6a0-0002a5d5c51b", role = "service" },
    [17] = { uuid = "98ed0003-a541-11e4-b6a0-0002a5d5c51b", role = "data_rx" },
    [19] = { uuid = "00002902-0000-1000-8000-00805f9b34fb", role = "cccd" },
    [20] = { uuid = "98ed0002-a541-11e4-b6a0-0002a5d5c51b", role = "cmd_tx" },
    [22] = { uuid = "98ed0004-a541-11e4-b6a0-0002a5d5c51b", role = "data_ext" },
    [24] = { uuid = "00002902-0000-1000-8000-00805f9b34fb", role = "cccd" },
    [25] = { uuid = "98ed0005-a541-11e4-b6a0-0002a5d5c51b", role = "notify_a" },
    [27] = { uuid = "00002902-0000-1000-8000-00805f9b34fb", role = "cccd" },
    [28] = { uuid = "98ed0006-a541-11e4-b6a0-0002a5d5c51b", role = "notify_b" },
    [30] = { uuid = "00002902-0000-1000-8000-00805f9b34fb", role = "cccd" },
    [31] = { uuid = "00060000-f8ce-11e4-abf4-0002a5d5c51b", role = "aux_service" },
    [32] = { uuid = "00060001-f8ce-11e4-abf4-0002a5d5c51b", role = "aux_channel" },
    [34] = { uuid = "00002902-0000-1000-8000-00805f9b34fb", role = "cccd" },
}

local f_btatt_opcode = Field.new("btatt.opcode")
local f_btatt_handle = Field.new("btatt.handle")
local f_btatt_value = Field.new("btatt.value")

local function lookup_handle(handle)
    local entry = OURA_HANDLES[handle]
    if not entry then
        return nil
    end
    local name = OURA_UUIDS[entry.uuid] or entry.uuid
    return name, entry.role, entry.uuid
end

local function oura_postdissector(tvb, pinfo, tree)
    local opcode_field = f_btatt_opcode()
    local handle_field = f_btatt_handle()

    if opcode_field == nil or handle_field == nil then
        return
    end

    local handle = handle_field().value
    local name, role, uuid = lookup_handle(handle)
    if name == nil then
        return
    end

    local opcode = opcode_field().value
    local opcode_name = ATT_OPCODES[opcode] or string.format("0x%02X", opcode)

    pinfo.cols.info:set(string.format("Oura %s: %s", opcode_name, name))

    local subtree = tree:add(oura_proto, tvb(), string.format("Oura: %s", name))
    subtree:add(oura_proto, tvb(), "ATT opcode"):append_text(string.format(": %s", opcode_name))
    subtree:add(oura_proto, tvb(), "GATT handle"):append_text(string.format(": %u", handle))
    subtree:add(oura_proto, tvb(), "Role"):append_text(string.format(": %s", role))
    subtree:add(oura_proto, tvb(), "UUID"):append_text(string.format(": %s", uuid))

    local value_field = f_btatt_value()
    if value_field ~= nil then
        local values = { value_field() }
        if #values > 0 and values[1] ~= nil then
            local hex = tostring(values[1])
            if #hex > 64 then
                hex = hex:sub(1, 64) .. "..."
            end
            subtree:add(oura_proto, tvb(), "Payload"):append_text(string.format(": %s", hex))
        end
    end
end

register_postdissector(oura_postdissector)
