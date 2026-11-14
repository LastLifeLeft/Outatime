// Feather disable all

/// Returns whether a player's input at `frame` has been confirmed (recorded locally, imported or
/// set) rather than predicted. Frames newer than the buffer are never confirmed.
///
/// @param frame
/// @param [playerIndex=0]

function InputCircularBufferIsConfirmed(_frame, _playerIndex = 0)
{
    static _system = __InputCircularBufferSystem();

    __INPUT_VALIDATE_PLAYER_INDEX

    _system.__EnsureAllocated();
    if (_frame > _system.__newestFrame) return false;

    with(_system.__playerArray[_playerIndex])
    {
        return __confirmedArray[__ReadSlot(_frame)];
    }
}
