// Feather disable all

/// Returns the value a verb had at `frame`, as `InputValue()` would, without browsing to it.
/// Frames newer than the buffer return the predicted value (the newest frame's).
///
/// @param verbIndex
/// @param frame
/// @param [playerIndex=0]

function InputCircularBufferValue(_verbIndex, _frame, _playerIndex = 0)
{
    static _system = __InputCircularBufferSystem();

    __INPUT_VALIDATE_PLAYER_INDEX

    _system.__EnsureAllocated();

    with(_system.__playerArray[_playerIndex])
    {
        return __clampArray[__ReadSlot(_frame)][_verbIndex];
    }
}
