// Feather disable all

/// Returns the oldest frame that is still held by the circular buffer. This is the furthest back
/// you can seek or roll back to.

function InputCircularBufferGetOldestFrame()
{
    static _system = __InputCircularBufferSystem();

    _system.__EnsureAllocated();
    return _system.__OldestFrame();
}
