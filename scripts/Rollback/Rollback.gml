/// @function pp_rollback_get_input(input_index, player_index)
/// @description Get input value for the current simulation frame. Use this instead of InputCheck during gameplay.
function pp_rollback_get_input(_input_index, _player_index) {
	var _buffer_index = global.absolute_frame % ROLLBACK_DEPTH;
	return global.input_buffer[_buffer_index][_player_index][_input_index];
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
