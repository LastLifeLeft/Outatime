// Feather disable all

/// Returns the earliest frame whose input changed after it had already been browsed, or
/// `undefined` if every browsed frame still holds the input it was browsed with. Anything you
/// computed from those frames is out of date from the returned frame onwards.
///
/// A frame counts as browsed once `InputCircularBufferSeek()` has been called for it (or for any
/// later frame). Input that is stored late but matches the prediction is not a change.
///
/// If the returned frame is older than `InputCircularBufferGetOldestFrame()`, input arrived for a
/// frame that has already left the buffer, so its prediction can no longer be checked.
///
/// The value is kept until `InputCircularBufferClearChangedFrame()` or `InputCircularBufferReset()`
/// is called.

function InputCircularBufferGetChangedFrame()
{
    static _system = __InputCircularBufferSystem();
    return _system.__changedFrame;
}
