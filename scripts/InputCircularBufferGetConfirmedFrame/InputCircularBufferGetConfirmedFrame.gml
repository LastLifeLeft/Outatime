// Feather disable all

/// Returns the newest frame for which a player's input has been confirmed, either recorded
/// locally, imported or set. After `InputCircularBufferReset(frame)` this is `frame - 1`. Useful to
/// detect a remote peer that has gone quiet.
///
/// @param [playerIndex=0]

function InputCircularBufferGetConfirmedFrame(_playerIndex = 0)
{
    static _system = __InputCircularBufferSystem();

    __INPUT_VALIDATE_PLAYER_INDEX

    _system.__EnsureAllocated();
    return _system.__playerArray[_playerIndex].__confirmedFrame;
}
