// Signals
#macro SIGNAL_DISPLAY_CHANGE "display_change"
#macro SIGNAL_TRANSITION_ENDED "transition_ended"
#macro SIGNAL_SPLITVIEW_TRANSITION_ENDED "splitview_transition_ended"
#macro SIGNAL_SPLITVIEW_DRAWUI "splitview_UI"
#macro SIGNAL_FONT_CHANGE "font_change"
#macro SIGNAL_LANGUAGE_CHANGE "language_change"
#macro SIGNAL_INPUT_HOTSWAP "input_change"
#macro SIGNAL_ROLLBACK "rollback"

global.signal_map = {};

/// @func signal_subscribe(_signal, _callback)
/// @desc Subscribes a function to a named signal.
/// @param {String} _signal - Signal name
/// @param {Function} _callback - Method to call when signal fires
function signal_subscribe(_signal, _callback)
{
	if (!struct_exists(global.signal_map, _signal))
	{
		global.signal_map[$ _signal] = [];
	}
	
	array_push(global.signal_map[$ _signal], _callback);
};

/// @func signal_unsubscribe(_signal, _callback)
/// @desc Unsubscribes a function from a named signal.
/// @param {String} _signal - Signal name
/// @param {Function} _callback - Method to remove
function signal_unsubscribe(_signal, _callback)
{
	if (!struct_exists(global.signal_map, _signal)) return;
	
	var _arr = global.signal_map[$ _signal];
	var _idx = array_get_index(_arr, _callback);
	
	if (_idx >= 0)
	{
		array_delete(_arr, _idx, 1);
		
		// Clean up empty arrays
		if (array_length(_arr) == 0)
		{
			struct_remove(global.signal_map, _signal);
		}
	}
};

/// @func signal_send(_signal)
/// @desc Fires a signal, calling all subscribed functions.
/// @param {String} _signal - Signal name
function signal_send(_signal)
{
	if (!struct_exists(global.signal_map, _signal)) return;
	
	var _arr = global.signal_map[$ _signal];
	
	// Iterate backwards to safely remove dead instances
	for (var _i = array_length(_arr) - 1; _i >= 0; _i--)
	{
		var _callback = _arr[_i];
		var _owner = method_get_self(_callback);
		
		// Check if owner instance still exists (skip for standalone functions)
		if (_owner != undefined && !instance_exists(_owner))
		{
			array_delete(_arr, _i, 1);
			continue;
		}
		
		_callback();
	}
	
	// Clean up if all subscribers are gone
	if (array_length(_arr) == 0)
	{
		struct_remove(global.signal_map, _signal);
	}
};
