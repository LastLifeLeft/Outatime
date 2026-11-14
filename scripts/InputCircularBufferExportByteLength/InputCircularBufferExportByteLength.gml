// Feather disable all

/// Returns the largest number of bytes `InputCircularBufferExport()` can write for one frame.

function InputCircularBufferExportByteLength()
{
    return 7 + 9*InputVerbCount();
}
