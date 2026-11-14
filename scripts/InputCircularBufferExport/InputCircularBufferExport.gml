// Feather disable all

/// Writes a player's input at `frame` into a buffer so it can be sent to a remote peer, who reads
/// it back with `InputCircularBufferImport()`. The frame number is included. Released verbs take
/// one byte, fully pressed digital verbs one byte, and analogue verbs nine bytes, plus a seven
/// byte header. Use a grow buffer or `InputCircularBufferExportByteLength()` for a fixed one.
///
/// `frame` must be held by the buffer and must not be negative. Peers must define the same verbs.
///
/// @param buffer
/// @param frame
/// @param [playerIndex=0]

function InputCircularBufferExport(_buffer, _frame, _playerIndex = 0)
{
    static _system = __InputCircularBufferSystem();

    __INPUT_VALIDATE_PLAYER_INDEX

    _system.__EnsureAllocated();

    if ((_frame < 0) || (_frame > _system.__newestFrame))
    {
        InputPlugInError("Cannot export frame ", _frame, ", the newest frame in the circular buffer is ", _system.__newestFrame);
    }

    with(_system.__playerArray[_playerIndex])
    {
        var _slot     = __ReadSlot(_frame);
        var _rawRow   = __rawArray[_slot];
        var _clampRow = __clampArray[_slot];
    }

    var _verbCount = _system.__verbCount;

    buffer_write(_buffer, buffer_u8,  __INPUT_CIRCULAR_BUFFER_PACKET_MAGIC);
    buffer_write(_buffer, buffer_u32, _frame);
    buffer_write(_buffer, buffer_u16, _verbCount);

    var _v = 0;
    repeat(_verbCount)
    {
        var _raw   = _rawRow[_v];
        var _clamp = _clampRow[_v];

        if ((_raw == 0) && (_clamp == 0))
        {
            buffer_write(_buffer, buffer_u8, 0);
        }
        else if ((_raw == 1) && (_clamp == 1))
        {
            buffer_write(_buffer, buffer_u8, 1);
        }
        else
        {
            buffer_write(_buffer, buffer_u8,  2);
            buffer_write(_buffer, buffer_f32, _raw);
            buffer_write(_buffer, buffer_f32, _clamp);
        }

        ++_v;
    }
}
