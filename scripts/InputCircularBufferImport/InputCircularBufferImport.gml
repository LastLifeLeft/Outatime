// Feather disable all

/// Reads one frame of input written by `InputCircularBufferExport()` and stores it as confirmed
/// input for `playerIndex`. Frames after it that have no confirmed input are predicted again from
/// it. Returns the frame number that was imported, or `undefined` if the frame could not be stored
/// (it has already left the buffer, or it is so far ahead that storing it would evict the browsed
/// frame).
///
/// If the imported input differs from what was predicted for a frame that has already been
/// browsed, `InputCircularBufferGetChangedFrame()` reports it.
///
/// The player index is not part of the packet: the receiver decides which player the input
/// belongs to, typically a player set as a ghost with `InputPlayerSetGhost()`.
///
/// @param buffer
/// @param [playerIndex=0]

function InputCircularBufferImport(_buffer, _playerIndex = 0)
{
    static _system = __InputCircularBufferSystem();

    __INPUT_VALIDATE_PLAYER_INDEX

    _system.__EnsureAllocated();

    var _magic = buffer_read(_buffer, buffer_u8);
    if (_magic != __INPUT_CIRCULAR_BUFFER_PACKET_MAGIC)
    {
        InputPlugInError("Circular buffer packet header mismatch (expecting ", __INPUT_CIRCULAR_BUFFER_PACKET_MAGIC, ", got ", _magic, ")");
    }

    var _frame     = buffer_read(_buffer, buffer_u32);
    var _verbCount = buffer_read(_buffer, buffer_u16);

    if (_verbCount != _system.__verbCount)
    {
        InputPlugInError("Circular buffer packet verb count mismatch (expecting ", _system.__verbCount, ", got ", _verbCount, ")");
    }

    var _rawArray   = _system.__scratchRawArray;
    var _clampArray = _system.__scratchClampArray;

    var _v = 0;
    repeat(_verbCount)
    {
        var _kind = buffer_read(_buffer, buffer_u8);

        if (_kind == 0)
        {
            _rawArray[@   _v] = 0;
            _clampArray[@ _v] = 0;
        }
        else if (_kind == 1)
        {
            _rawArray[@   _v] = 1;
            _clampArray[@ _v] = 1;
        }
        else
        {
            _rawArray[@   _v] = buffer_read(_buffer, buffer_f32);
            _clampArray[@ _v] = buffer_read(_buffer, buffer_f32);
        }

        ++_v;
    }

    return _system.__Store(_frame, _playerIndex, _rawArray, _clampArray)? _frame : undefined;
}
