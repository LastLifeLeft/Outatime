// =============================================================================
// PLAYER INFO
// =============================================================================
player_count = global.local_player_count;
local_player_indices = [];

// Seat p reads Input player p, which must own that player's device
for (var i = 0; i < player_count; i++) {
	array_push(local_player_indices, i);
}

// =============================================================================
// FRAME TRACKING
// =============================================================================
global.absolute_frame = 0;
global.rollback_tick_frame = 0;
global.rollbacking = 0; // Always 0 in local mode
global.rollback_in_tick = false;

// =============================================================================
// INPUT: Input's Circular Buffer plug-in, seat p = Input player p
// =============================================================================
rollback_input_begin(player_count);

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
	global.rollback_in_tick = true;
	var _current_frame = global.absolute_frame;
	
	global.rollback_tick_frame = _current_frame;
		
	// =================================================================
	// CAPTURE INPUT FOR ALL LOCAL PLAYERS (with delay)
	// =================================================================
	var _input_frame = _current_frame + ROLLBACK_INPUT_DELAY;
		
	for (var p = 0; p < player_count; p++) {
		InputCircularBufferRecord(_input_frame, p);
	}
	
	// Input's checkers now return this frame's input
	InputCircularBufferSeek(_current_frame);
});

global.rollback_clock.AddEndTickMethod(function() {
	global.absolute_frame++;
	global.rollback_in_tick = false;
});
