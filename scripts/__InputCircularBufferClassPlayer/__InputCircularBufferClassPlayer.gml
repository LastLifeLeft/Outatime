// Feather disable all

/// @param playerIndex

function __InputCircularBufferClassPlayer(_playerIndex) constructor
{
    static _system           = __InputCircularBufferSystem();
    static _inputPlayerArray = __InputSystemPlayerArray();

    __playerIndex = _playerIndex;

    var _verbCount  = _system.__verbCount;
    var _ringLength = _system.__ringLength;

    //Ring of frames, each holding one value per verb. Press frames are buffer frames, not Input frames
    __rawArray       = array_create(_ringLength);
    __clampArray     = array_create(_ringLength);
    __pressArray     = array_create(_ringLength);
    __confirmedArray = array_create(_ringLength, false);
    __confirmedFrame = -infinity;

    var _slot = 0;
    repeat(_ringLength)
    {
        __rawArray[@   _slot] = array_create(_verbCount, 0);
        __clampArray[@ _slot] = array_create(_verbCount, 0);
        __pressArray[@ _slot] = array_create(_verbCount, -infinity);
        ++_slot;
    }

    //Live state as Input would have computed it, kept so we can restore it after browsing
    __liveRawArray       = array_create(_verbCount, 0);
    __liveClampArray     = array_create(_verbCount, 0);
    __liveHeldArray      = array_create(_verbCount, false);
    __livePrevHeldArray  = array_create(_verbCount, false);
    __livePressArray     = array_create(_verbCount, -infinity);
    __dirty              = false; //Whether Input's verb state currently holds browsed values

    static __Reset = function(_baselineSlot, _baselineFrame)
    {
        var _verbCount = _system.__verbCount;

        var _slot = 0;
        repeat(_system.__ringLength)
        {
            var _rawRow   = __rawArray[_slot];
            var _clampRow = __clampArray[_slot];
            var _pressRow = __pressArray[_slot];

            var _v = 0;
            repeat(_verbCount)
            {
                _rawRow[@   _v] = 0;
                _clampRow[@ _v] = 0;
                _pressRow[@ _v] = -infinity;
                ++_v;
            }

            __confirmedArray[@ _slot] = false;
            ++_slot;
        }

        __confirmedArray[@ _baselineSlot] = true;
        __confirmedFrame = _baselineFrame;
    }

    //Unconfirmed frames repeat the previous frame. Held state doesn't change so neither does the press frame
    static __Predict = function(_sourceSlot, _slot)
    {
        array_copy(__rawArray[_slot],   0, __rawArray[_sourceSlot],   0, _system.__verbCount);
        array_copy(__clampArray[_slot], 0, __clampArray[_sourceSlot], 0, _system.__verbCount);
        array_copy(__pressArray[_slot], 0, __pressArray[_sourceSlot], 0, _system.__verbCount);
        __confirmedArray[@ _slot] = false;
    }

    static __UpdatePress = function(_frame)
    {
        var _slot     = _system.__Slot(_frame);
        var _previous = _system.__Slot(_frame - 1);

        var _clampRow     = __clampArray[_slot];
        var _prevClampRow = __clampArray[_previous];
        var _pressRow     = __pressArray[_slot];
        var _prevPressRow = __pressArray[_previous];

        var _v = 0;
        repeat(_system.__verbCount)
        {
            _pressRow[@ _v] = ((_clampRow[_v] > 0) && (_prevClampRow[_v] <= 0))? _frame : _prevPressRow[_v];
            ++_v;
        }
    }

    //Returns the earliest frame whose values changed, or `undefined`
    static __Store = function(_frame, _raw, _clamp, _verbIndex)
    {
        var _verbCount    = _system.__verbCount;
        var _changedFrame = undefined;
        var _slot         = _system.__Slot(_frame);
        
        var _rawRow   = __rawArray[_slot];
        var _clampRow = __clampArray[_slot];
        
        //GameMaker compares reals with an epsilon, which would hide small analogue changes.
        //Compare exactly while detecting them
        var _epsilon = math_get_epsilon();
        math_set_epsilon(0);
        
        if (_verbIndex == undefined)
        {
            var _v = 0;
            repeat(_verbCount)
            {
                var _newRaw   = _system.__Quantize(_raw[_v]);
                var _newClamp = _system.__Quantize(_clamp[_v]);
                
                if ((_rawRow[_v] != _newRaw) || (_clampRow[_v] != _newClamp)) _changedFrame = _frame;
                
                _rawRow[@   _v] = _newRaw;
                _clampRow[@ _v] = _newClamp;
                ++_v;
            }
        }
        else
        {
            var _newRaw   = _system.__Quantize(_raw);
            var _newClamp = _system.__Quantize(_clamp);
            
            if ((_rawRow[_verbIndex] != _newRaw) || (_clampRow[_verbIndex] != _newClamp)) _changedFrame = _frame;
            
            _rawRow[@   _verbIndex] = _newRaw;
            _clampRow[@ _verbIndex] = _newClamp;
        }
        
        __confirmedArray[@ _slot] = true;
        __confirmedFrame = max(__confirmedFrame, _frame);
        
        //Re-predict the unconfirmed frames that follow
        var _f = _frame + 1;
        repeat(_system.__newestFrame - _frame)
        {
            var _nextSlot = _system.__Slot(_f);
            
            if (not __confirmedArray[_nextSlot])
            {
                var _prevSlot = _system.__Slot(_f - 1);
                var _sourceRawRow   = __rawArray[_prevSlot];
                var _sourceClampRow = __clampArray[_prevSlot];
                var _targetRawRow   = __rawArray[_nextSlot];
                var _targetClampRow = __clampArray[_nextSlot];
                
                if (_changedFrame == undefined)
                {
                    var _v = 0;
                    repeat(_verbCount)
                    {
                        if ((_targetRawRow[_v] != _sourceRawRow[_v]) || (_targetClampRow[_v] != _sourceClampRow[_v]))
                        {
                            _changedFrame = _f;
                            break;
                        }
                        
                        ++_v;
                    }
                }
                
                array_copy(_targetRawRow,   0, _sourceRawRow,   0, _verbCount);
                array_copy(_targetClampRow, 0, _sourceClampRow, 0, _verbCount);
            }
            
            ++_f;
        }
        
        math_set_epsilon(_epsilon);
        
        //Held state uses the game's epsilon, like Input does, so press frames are carried forward afterwards
        var _f = _frame;
        repeat(1 + _system.__newestFrame - _frame)
        {
            __UpdatePress(_f);
            ++_f;
        }
        
        return _changedFrame;
    }
    
    //Executed in Input's UPDATE_PLAYER callback, after Input has updated verb state natively
    static __OnUpdate = function(_refreshing, _seekFrame)
    {
        var _verbCount = _system.__verbCount;

        if (not _refreshing)
        {
            //A genuine Input update, track live state the way Input itself does
            var _inputFrame = InputPlugInGetFrame();

            var _inputPlayer     = _inputPlayerArray[__playerIndex];
            var _valueRawArray   = _inputPlayer.__valueRawArray;
            var _valueClampArray = _inputPlayer.__valueClampArray;

            var _v = 0;
            repeat(_verbCount)
            {
                var _held = (_valueClampArray[_v] > 0);
                if (_held && (not __liveHeldArray[_v])) __livePressArray[@ _v] = _inputFrame;

                __livePrevHeldArray[@ _v] = __liveHeldArray[_v];
                __liveHeldArray[@     _v] = _held;
                __liveRawArray[@      _v] = _valueRawArray[_v];
                __liveClampArray[@    _v] = _valueClampArray[_v];
                ++_v;
            }
        }

        if (_seekFrame != undefined)
        {
            __dirty = true;

            var _inputFrame = InputPlugInGetFrame();
            var _slot       = _system.__Slot(_seekFrame);
            var _rawRow     = __rawArray[_slot];
            var _clampRow   = __clampArray[_slot];
            var _pressRow   = __pressArray[_slot];
            var _prevClampRow = __clampArray[_system.__Slot(_seekFrame - 1)];

            var _v = 0;
            repeat(_verbCount)
            {
                var _press = _pressRow[_v];
                InputPlugInVerbStateSet(_v, (_prevClampRow[_v] > 0), _rawRow[_v], _clampRow[_v], (_press == -infinity)? -infinity : (_inputFrame - (_seekFrame - _press)), __playerIndex);
                ++_v;
            }
        }
        else if (__dirty)
        {
            //Input computed this update from browsed state, put the live state back
            __dirty = false;

            var _v = 0;
            repeat(_verbCount)
            {
                InputPlugInVerbStateSet(_v, __livePrevHeldArray[_v], __liveRawArray[_v], __liveClampArray[_v], __livePressArray[_v], __playerIndex);
                ++_v;
            }
        }
    }

    static __ReadSlot = function(_frame)
    {
        if (_frame < _system.__OldestFrame())
        {
            InputPlugInError("Frame ", _frame, " is older than the oldest frame in the circular buffer (", _system.__OldestFrame(), ")");
        }

        //Frames beyond the newest one are predicted to repeat it
        return _system.__Slot(min(_frame, _system.__newestFrame));
    }
}
