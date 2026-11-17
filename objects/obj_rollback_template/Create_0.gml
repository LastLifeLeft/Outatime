// Rollback state buffer
state_buffer = [];
for (var i = 0; i < ROLLBACK_DEPTH; i++) {
	state_buffer[i] = undefined;
}

// Lifecycle tracking: the first frame whose begin-of-tick state holds this instance. One created inside tick N
// is first saved at the begin of N + 1, and a rollback to N destroys it so that the resimulation creates it again
birth_frame = global.absolute_frame + (global.rollback_in_tick? 1 : 0);
marked_for_destruction = false;
destruction_frame = -1;

// Subscribe to rollback signal
signal_subscribe(SIGNAL_ROLLBACK, function() {
	var _target_frame = global.absolute_frame;
	
	if (_target_frame < birth_frame) {
		instance_destroy(id, false);
		return;
	}
	
	var _buffer_index = _target_frame % ROLLBACK_DEPTH;
	var _state = state_buffer[_buffer_index];
	
	if (_state != undefined) {
		deserialize_state(_state);
	}
});

// Save state at BEGIN of tick (before simulation)
global.rollback_clock.AddBeginTickMethod(function() {
	var _buffer_index = rollback_get_buffer_index();
	state_buffer[_buffer_index] = serialize_state();
});

// Handle deferred destruction at END of tick
global.rollback_clock.AddEndTickMethod(function() {
	if (marked_for_destruction && global.absolute_frame >= destruction_frame) {
		instance_destroy();
	}
});

/// @function rollback_destroy()
/// @description Use this instead of instance_destroy() for rollback-safe destruction
rollback_destroy = function() {
	if (!marked_for_destruction) {
		marked_for_destruction = true;
		destruction_frame = global.absolute_frame + ROLLBACK_DEPTH;
		
		// Disable but don't destroy
		visible = false;
		// Disable collision, etc.
	}
}