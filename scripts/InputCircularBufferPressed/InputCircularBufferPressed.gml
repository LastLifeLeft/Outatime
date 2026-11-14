// Feather disable all

/// Returns whether a verb was newly pressed at `frame`, as `InputPressed()` would, without
/// browsing to it.
///
/// @param verbIndex
/// @param frame
/// @param [playerIndex=0]

function InputCircularBufferPressed(_verbIndex, _frame, _playerIndex = 0)
{
    static _system = __InputCircularBufferSystem();

    __INPUT_VALIDATE_PLAYER_INDEX

    _system.__EnsureAllocated();

    with(_system.__playerArray[_playerIndex])
    {
        return ((__clampArray[__ReadSlot(_frame)][_verbIndex] > 0) && (__clampArray[_system.__Slot(min(_frame - 1, _system.__newestFrame))][_verbIndex] <= 0));
    }
}
