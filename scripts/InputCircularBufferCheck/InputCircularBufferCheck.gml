// Feather disable all

/// Returns whether a verb was held at `frame`, as `InputCheck()` would, without browsing to it.
/// Frames newer than the buffer return the predicted state (the newest frame's).
///
/// @param verbIndex
/// @param frame
/// @param [playerIndex=0]

function InputCircularBufferCheck(_verbIndex, _frame, _playerIndex = 0)
{
    static _system = __InputCircularBufferSystem();

    __INPUT_VALIDATE_PLAYER_INDEX

    _system.__EnsureAllocated();

    with(_system.__playerArray[_playerIndex])
    {
        return (__clampArray[__ReadSlot(_frame)][_verbIndex] > 0);
    }
}
