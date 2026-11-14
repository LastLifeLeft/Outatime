// Feather disable all

/// Clears the circular buffer and stops browsing. The next frame to be recorded or browsed is
/// `frame`. Every frame starts out predicted as "no input" until input is recorded for it. Call
/// this at the start of a match, or whenever your game's frame counter restarts.
///
/// @param [frame=0]

function InputCircularBufferReset(_frame = 0)
{
    static _system = __InputCircularBufferSystem();

    with(_system)
    {
        __EnsureAllocated();
        __Reset(_frame);
    }
}
