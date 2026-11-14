// Feather disable all

/// Returns the newest frame held by the circular buffer, whether its input is confirmed or
/// predicted. The buffer grows when you record, import, set or seek past this frame.

function InputCircularBufferGetNewestFrame()
{
    static _system = __InputCircularBufferSystem();

    _system.__EnsureAllocated();
    return _system.__newestFrame;
}
