// Feather disable all

/// Browses the circular buffer. After calling this function, Input's checker functions
/// (`InputCheck()`, `InputPressed()`, `InputReleased()`, `InputValue()`, `InputDuration()`,
/// `InputX()`, `InputDirection()` and so on) return the state recorded at `frame` for every
/// player, as if the game were back at that frame. Frames that hold no confirmed input for a
/// player are predicted by repeating that player's previous input.
///
/// Pass `undefined` to stop browsing and return Input to live device state.
///
/// `frame` must not be older than `InputCircularBufferGetOldestFrame()`. Seeking beyond the newest
/// frame extends the buffer with predicted input. Browsed state survives Input's own update so
/// checkers keep returning the browsed frame until you seek again.
///
/// Seek to `undefined` once you are done browsing if code elsewhere (menus, UI) needs live input.
///
/// N.B. `InputVerbConsume()` is not part of the buffer. A verb consumed while browsing stays
///      consumed whichever frame you browse to next.
///
/// @param frame

function InputCircularBufferSeek(_frame)
{
    static _system = __InputCircularBufferSystem();

    with(_system)
    {
        __EnsureAllocated();

        if (_frame == undefined)
        {
            if (__seekFrame != undefined)
            {
                __seekFrame = undefined;
                __RefreshAll();
            }

            return;
        }

        if (not is_numeric(_frame))
        {
            InputPlugInError("Frame must be a number or `undefined` (typeof = \"", typeof(_frame), "\")");
        }

        if (_frame < __OldestFrame())
        {
            InputPlugInError("Cannot seek to frame ", _frame, ", the oldest frame in the circular buffer is ", __OldestFrame(), "\nIncrease `INPUT_CIRCULAR_BUFFER_SIZE` to browse further back");
        }

        __Extend(_frame);
        __seekFrame    = _frame;
        __maxSeekFrame = max(__maxSeekFrame, _frame);
        __RefreshAll();
    }
}
