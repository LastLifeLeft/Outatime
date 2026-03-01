// =============================================================================
// PLAYER INFO
// =============================================================================
player_count = global.local_player_count;
local_player_indices = [];

// Example: 2 local players on devices 0 and 1
for (var i = 0; i < player_count; i++) {
	array_push(local_player_indices, i);
}

// =============================================================================
// FRAME TRACKING
// =============================================================================
global.absolute_frame = 0;
global.rollback_tick_frame = 0;
global.rollbacking = 0; // Always 0 in local mode

// =============================================================================
// INPUT BUFFER: [buffer_index][player_index][input_index]
// =============================================================================
global.input_buffer = [];
for (var i = 0; i < ROLLBACK_DEPTH; i++) {
	global.input_buffer[i] = [];
	for (var j = 0; j < player_count; j++) {
		global.input_buffer[i][j] = array_create(INPUT_VERB_COUNT, 0);
	}
}

// =============================================================================
// RNG
// =============================================================================
rollback_random_init(irandom(999999));

// =============================================================================
// CLOCK SETUP
// =============================================================================
global.rollback_clock = new OutatimeClock();
global.rollback_clock.SetUpdateFrequency(1000000 / ROLLBACK_TICK_DURATION);

global.rollback_clock.AddBeginTickMethod(function() {
	var _current_frame = global.absolute_frame;
	
	global.rollback_tick_frame = _current_frame;
		
	// =================================================================
	// CAPTURE INPUT FOR ALL LOCAL PLAYERS (with delay)
	// =================================================================
	var _input_frame = _current_frame + ROLLBACK_INPUT_DELAY;
	var _input_buffer_index = _input_frame % ROLLBACK_DEPTH;
		
	for (var p = 0; p < player_count; p++) {
		var _device = local_player_indices[p];
			
		for (var i = 0; i < INPUT_VERB_COUNT; i++) {
			global.input_buffer[_input_buffer_index][p][i] = InputCheck(i, _device);
		}
	}
});

global.rollback_clock.AddEndTickMethod(function() {
	global.absolute_frame++;
});
