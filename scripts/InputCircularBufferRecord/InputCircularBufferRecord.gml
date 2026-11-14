// Feather disable all

/// Records a player's current live input (what Input collected from their device this step) into
/// the circular buffer at `frame`, and marks that frame as confirmed for the player. Returns `true`
/// if the input was stored, `false` if the frame is outside of the buffer.
///
/// Record input ahead of the frame you are browsing to add input delay, for example
/// `InputCircularBufferRecord(frame + 3)` gives three frames of delay. Record before calling
/// `InputCircularBufferSeek()` for the same frame: recording a frame that has already been browsed
/// counts as a change (see `InputCircularBufferGetChangedFrame()`).
///
/// Analogue values are rounded to single precision so that they match the values a remote peer
/// receives through `InputCircularBufferExport()` and `InputCircularBufferImport()`.
///
/// @param frame
/// @param [playerIndex=0]

function InputCircularBufferRecord(_frame, _playerIndex = 0)
{
    static _system = __InputCircularBufferSystem();
    static _inputPlayerArray = __InputSystemPlayerArray();

    __INPUT_VALIDATE_PLAYER_INDEX

    var _inputPlayer = _inputPlayerArray[_playerIndex];
    return _system.__Store(_frame, _playerIndex, _inputPlayer.__valueRawArray, _inputPlayer.__valueClampArray);
}
