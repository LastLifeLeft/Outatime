// Feather disable all

/// Sets one verb of a player's input at `frame` and marks that frame as confirmed for the player.
/// The player's other verbs keep their current (possibly predicted) values. Useful for bots,
/// replays and tests, or to feed input from a transport that doesn't use
/// `InputCircularBufferExport()`. Returns `true` if the input was stored, `false` if the frame is
/// outside of the buffer.
///
/// `value` is the clamped value returned by `InputValue()`; a verb is held when it is greater than
/// zero. `rawValue` feeds clusters (`InputX()`, `InputDirection()` etc.). Values are rounded to
/// single precision.
///
/// @param frame
/// @param verbIndex
/// @param value
/// @param [rawValue=value]
/// @param [playerIndex=0]

function InputCircularBufferSet(_frame, _verbIndex, _value, _rawValue = _value, _playerIndex = 0)
{
    static _system = __InputCircularBufferSystem();

    __INPUT_VALIDATE_PLAYER_INDEX

    return _system.__Store(_frame, _playerIndex, _rawValue, _value, _verbIndex);
}
