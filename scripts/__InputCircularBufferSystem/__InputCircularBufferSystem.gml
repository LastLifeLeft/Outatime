// Feather disable all

#macro __INPUT_CIRCULAR_BUFFER_VERSION       "1.0.0"
#macro __INPUT_CIRCULAR_BUFFER_PACKET_MAGIC  0x43

__InputCircularBufferSystem();
function __InputCircularBufferSystem()
{
    static _system = undefined;
    if (_system != undefined) return _system;

    _system = {};
    with(_system)
    {
        //Allocation is deferred until first use because `InputVerbCount()` cannot be called on boot
        __allocated   = false;
        __initialized = false;
        __refreshing  = false;

        __size       = max(1, INPUT_CIRCULAR_BUFFER_SIZE);
        __ringLength = __size + 1; //One extra slot so the oldest browsable frame always has a predecessor
        __verbCount  = 0;

        __slotFrameArray = array_create(__ringLength, undefined);
        __playerArray    = [];

        __newestFrame   = -1;
        __seekFrame     = undefined;
        __maxSeekFrame  = -infinity;
        __changedFrame = undefined;

        __scratchRawArray   = [];
        __scratchClampArray = [];

        __quantizeBuffer = buffer_create(4, buffer_fixed, 1);

        __Slot = function(_frame)
        {
            return ((_frame mod __ringLength) + __ringLength) mod __ringLength;
        }

        __OldestFrame = function()
        {
            return __newestFrame - __size + 1;
        }

        //Round a value to single precision so local and remote peers read the exact same
        //number after a round trip through `InputCircularBufferExport()`
        __Quantize = function(_value)
        {
            if ((_value == 0) || (_value == 1)) return _value;

            buffer_poke(__quantizeBuffer, 0, buffer_f32, _value);
            return buffer_peek(__quantizeBuffer, 0, buffer_f32);
        }

        __EnsureAllocated = function()
        {
            if (__allocated) return;
            __allocated = true;

            __verbCount = InputVerbCount();
            __scratchRawArray   = array_create(__verbCount, 0);
            __scratchClampArray = array_create(__verbCount, 0);

            __playerArray = array_create_ext(INPUT_MAX_PLAYERS, function(_index)
            {
                return new __InputCircularBufferClassPlayer(_index);
            });

            __Reset(0);
        }

        __Reset = function(_frame)
        {
            var _wasBrowsing = (__seekFrame != undefined);

            __newestFrame   = _frame - 1;
            __seekFrame     = undefined;
            __maxSeekFrame  = -infinity;
            __changedFrame = undefined;

            array_map_ext(__slotFrameArray, function() { return undefined; });

            //The slot before the first frame is a confirmed baseline of zero input that the first frames
            //are predicted from
            var _baselineSlot = __Slot(__newestFrame);
            __slotFrameArray[@ _baselineSlot] = __newestFrame;

            var _i = 0;
            repeat(array_length(__playerArray))
            {
                __playerArray[_i].__Reset(_baselineSlot, __newestFrame);
                ++_i;
            }

            if (_wasBrowsing) __RefreshAll();
        }

        //Predict every frame between the newest frame and `_frame` by repeating the newest input
        __Extend = function(_frame)
        {
            if (_frame <= __newestFrame) return;

            var _start = max(__newestFrame + 1, _frame - __size);
            if (_start > __newestFrame + 1)
            {
                //Jumping further than the ring is long. Carry the newest values over to the slot just
                //before the new window so the prediction chain has something to start from
                var _source      = __Slot(__newestFrame);
                var _destination = __Slot(_start - 1);
                __slotFrameArray[@ _destination] = _start - 1;

                var _i = 0;
                repeat(array_length(__playerArray))
                {
                    __playerArray[_i].__Predict(_source, _destination);
                    ++_i;
                }
            }

            var _f = _start;
            repeat(1 + _frame - _start)
            {
                var _slot = __Slot(_f);
                __slotFrameArray[@ _slot] = _f;

                var _previous = __Slot(_f - 1);
                var _i = 0;
                repeat(array_length(__playerArray))
                {
                    __playerArray[_i].__Predict(_previous, _slot);
                    ++_i;
                }

                ++_f;
            }

            __newestFrame = _frame;
        }

        //Stores confirmed input for a player at a frame. `_raw` and `_clamp` are arrays, or scalars when
        //`_verbIndex` is given. Returns `false` if the frame cannot be stored
        __Store = function(_frame, _playerIndex, _raw, _clamp, _verbIndex = undefined)
        {
            __EnsureAllocated();

            if (_frame < __OldestFrame())
            {
                //Too old to store. If that frame was already browsed we cannot know whether it was
                //predicted correctly, so report it as changed. The caller can tell it apart by
                //comparing against `InputCircularBufferGetOldestFrame()`
                if (_frame <= __maxSeekFrame) __changedFrame = min(__changedFrame ?? infinity, _frame);
                return false;
            }

            if ((__seekFrame != undefined) && (_frame - __size + 1 > __seekFrame))
            {
                InputPlugInWarning("Circular buffer cannot store frame ", _frame, " for player ", _playerIndex, ", it would evict the browsed frame ", __seekFrame);
                return false;
            }

            __Extend(_frame);

            var _changedFrame = __playerArray[_playerIndex].__Store(_frame, _raw, _clamp, _verbIndex);
            if (_changedFrame != undefined)
            {
                if (_changedFrame <= __maxSeekFrame) __changedFrame = min(__changedFrame ?? infinity, _changedFrame);
                if ((__seekFrame != undefined) && (_changedFrame <= __seekFrame)) __RefreshPlayer(_playerIndex);
            }

            return true;
        }

        //Re-runs Input's per-player update so our UPDATE_PLAYER callback can apply browsed (or live)
        //state, and so clusters are recalculated from it
        __RefreshPlayer = function(_playerIndex)
        {
            if (not __initialized) return;

            static _inputPlayerArray = __InputSystemPlayerArray();

            __refreshing = true;
            _inputPlayerArray[_playerIndex].__Update();
            __refreshing = false;
        }

        __RefreshAll = function()
        {
            var _i = 0;
            repeat(INPUT_MAX_PLAYERS)
            {
                __RefreshPlayer(_i);
                ++_i;
            }
        }

        InputPlugInDefine("LastLife.CircularBuffer", "LastLife", __INPUT_CIRCULAR_BUFFER_VERSION, "10.5", function()
        {
            __EnsureAllocated();
            __initialized = true;

            InputPlugInRegisterCallback(INPUT_PLUG_IN_CALLBACK.UPDATE_PLAYER, INPUT_CIRCULAR_BUFFER_CALLBACK_PRIORITY, function(_playerIndex)
            {
                __playerArray[_playerIndex].__OnUpdate(__refreshing, __seekFrame);
            });

            InputPlugInRegisterCallback(INPUT_PLUG_IN_CALLBACK.GAME_RESTART, INPUT_CIRCULAR_BUFFER_CALLBACK_PRIORITY, function()
            {
                __Reset(0);
            });
        });
    }

    return _system;
}
