// Input is buffered by Input's Circular Buffer plug-in. Seat p reads Input player p. During every tick
// the rollback manager browses the plug-in to that tick's frame, so Input's checkers (InputCheck,
// InputPressed, InputValue, InputX...) return the simulated frame's input for every seat. Outside of
// ticks Input returns live device state.

global.__rollback_input = undefined;

/// @function pp_rollback_get_input(input_index, player_index)
/// @description Whether a verb is held by a player on the current simulation frame. Use this (or Input's checkers, inside tick methods) instead of live input during gameplay.
function pp_rollback_get_input(_input_index, _player_index) {
	return InputCircularBufferCheck(_input_index, global.absolute_frame, _player_index);
}

/// @function rollback_get_frame()
/// @description Get the current absolute simulation frame
function rollback_get_frame() {
	return global.rollback_tick_frame;
}

/// @function rollback_get_buffer_index()
/// @description Get the current buffer index for state storage
function rollback_get_buffer_index() {
	return global.rollback_tick_frame % ROLLBACK_DEPTH;
}

/// @function rollback_input_begin(player_count, [local_player_index])
/// @description Starts a match's input: frame 0 is the next frame recorded. Online, pass the local seat: it gets the local device and every other seat becomes a ghost Input player fed by InputCircularBufferImport().
function rollback_input_begin(_player_count, _local_player_index = undefined) {
	rollback_input_end();

	var _state = {
		local_player_index: _local_player_index,
		ghosts: [],
		hotswap: InputGetHotswap(),
	};
	global.__rollback_input = _state;

	InputCircularBufferReset(0);
	if (_local_player_index == undefined) return;

	if (_local_player_index != 0) {
		// Hotswap only feeds Input player 0
		InputSetHotswap(false);
		var _device = InputPlayerGetDevice(0);
		InputPlayerSetDevice(INPUT_NO_DEVICE, 0);
		InputPlayerSetDevice(_device, _local_player_index);
	}

	for (var p = 0; p < _player_count; p++) {
		if (p == _local_player_index) continue;
		InputPlayerSetGhost(true, p);
		array_push(_state.ghosts, p);
	}
}

/// @function rollback_input_end()
/// @description Ends a match's input: Input returns live device state, ghosts and the local device are put back.
function rollback_input_end() {
	var _state = global.__rollback_input;
	if (_state == undefined) return;
	global.__rollback_input = undefined;

	InputCircularBufferSeek(undefined);

	for (var i = 0; i < array_length(_state.ghosts); i++) {
		InputPlayerSetGhost(false, _state.ghosts[i]);
	}

	var _local = _state.local_player_index;
	if (_local != undefined && _local != 0) {
		var _device = InputPlayerGetDevice(_local);
		InputPlayerSetDevice(INPUT_NO_DEVICE, _local);
		InputPlayerSetDevice(_device, 0);
	}

	InputSetHotswap(_state.hotswap);
}
