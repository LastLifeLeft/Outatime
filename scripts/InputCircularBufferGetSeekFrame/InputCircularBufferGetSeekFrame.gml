// Feather disable all

/// Returns the frame being browsed (see `InputCircularBufferSeek()`), or `undefined` if Input is
/// returning live device state.

function InputCircularBufferGetSeekFrame()
{
    static _system = __InputCircularBufferSystem();
    return _system.__seekFrame;
}
