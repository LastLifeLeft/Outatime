// Feather disable all

/// Clears the frame reported by `InputCircularBufferGetChangedFrame()`. Call this once you have
/// dealt with the change.

function InputCircularBufferClearChangedFrame()
{
    static _system = __InputCircularBufferSystem();
    _system.__changedFrame = undefined;
}
