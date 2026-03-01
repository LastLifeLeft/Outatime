// Singleton enforcement
if (instance_number(object_index) > 1) {
	show_debug_message("WARNING: Duplicate RollBack_Manager detected - destroying");
	instance_destroy();
	return;
}

local_player_index = array_get_index(global.relay_players, global.relay_nickname);
debug_id = "client " + string(local_player_index) + ": "

// =============================================================================
// PLAYER INFO
// =============================================================================
player_count = array_length(global.relay_players);
local_player_index = array_get_index(global.relay_players, global.relay_nickname);

// =============================================================================
// FRAME TRACKING
// =============================================================================
global.absolute_frame = 0;
global.rollbacking = 0;
global.rollback_tick_frame = 0;
resimulating = false;
rollback_trigger_players = array_create(player_count, false);

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
// PER-PLAYER NETWORK TRACKING
// =============================================================================
// Stores the absolute frame number of the last confirmed input for each player
last_confirmed_frame = array_create(player_count, -1);
last_confirmed_frame[local_player_index] = ROLLBACK_INPUT_DELAY;

ticks_since_message = array_create(player_count, -ROLLBACK_GRACE_PERIOD);
ticks_since_message[local_player_index] = 0;

// Last frame we received ACTUAL INPUT for (used for prediction)
last_input_frame = array_create(player_count, -1);
last_input_frame[local_player_index] = ROLLBACK_INPUT_DELAY;

// Last frame we heard from them at all (used for timeout)
last_heard_frame = array_create(player_count, -1);
last_heard_frame[local_player_index] = ROLLBACK_INPUT_DELAY;

// =============================================================================
// NETWORK MESSAGE QUEUE
// =============================================================================
message_queue = ds_queue_create();
ticks_since_input_sent = 0;

// =============================================================================
// CONNECTION STATE
// =============================================================================
connection_paused = false;
pause_timer = 0;

// =============================================================================
// RNG STATE BUFFER
// =============================================================================
rng_state_buffer = [];
for (var i = 0; i < ROLLBACK_DEPTH; i++) {
	rng_state_buffer[i] = undefined;
}
rollback_random_init(global.rollback_seed);

// =============================================================================
// CLOCK SETUP
// =============================================================================
global.rollback_clock = new OutatimeClock();
global.rollback_clock.SetUpdateFrequency(1000000 / ROLLBACK_TICK_DURATION);

global.rollback_clock.AddBeginTickMethod(function()
{
	var _current_frame = global.absolute_frame;
	var _current_buffer_index = _current_frame % ROLLBACK_DEPTH;
		
	// Set the stable tick frame for objects to use
	global.rollback_tick_frame = _current_frame;
		
	// =================================================================
	// SAVE RNG STATE (only during normal play)
	// =================================================================
	if (!resimulating) {
		rng_state_buffer[_current_buffer_index] = rollback_random_get_state();
	}
		
	// =================================================================
	// PREDICT REMOTE INPUTS
	// =================================================================
	for (var p = 0; p < player_count; p++) {
		if (p == local_player_index) continue;
	
		// During resim, only predict for players who triggered the rollback
		if (resimulating && !rollback_trigger_players[p]) continue;
	
		if (last_input_frame[p] < _current_frame) {
			var _prev_buffer_index = (_current_frame - 1 + ROLLBACK_DEPTH) % ROLLBACK_DEPTH;
		
			for (var i = 0; i < INPUT_VERB_COUNT; i++) {
				global.input_buffer[_current_buffer_index][p][i] = global.input_buffer[_prev_buffer_index][p][i];
			}
		}
	}
		
	// =================================================================
	// CAPTURE AND SEND LOCAL INPUT (only during normal play)
	// =================================================================
	if (!resimulating) {
		var _input_frame = _current_frame + ROLLBACK_INPUT_DELAY;
		var _input_buffer_index = _input_frame % ROLLBACK_DEPTH;
		var _prev_input_buffer_index = (_input_frame - 1 + ROLLBACK_DEPTH) % ROLLBACK_DEPTH;
			
		var _input_changed = false;
			
		for (var i = 0; i < INPUT_VERB_COUNT; i++) {
			var _val = InputCheck(i, 0);
				
			if (_val != global.input_buffer[_prev_input_buffer_index][local_player_index][i]) {
				_input_changed = true;
			}
				
			global.input_buffer[_input_buffer_index][local_player_index][i] = _val;
				
			
		}
			
		last_confirmed_frame[local_player_index] = _input_frame;
			
		if (_input_changed) {
			ticks_since_input_sent = 0;
			send_input(_input_frame);
		} else {
			ticks_since_input_sent++;
			if (ticks_since_input_sent >= 5) {
				ticks_since_input_sent = 0;
				send_heartbeat(_input_frame);
			}
		}
	}
});

// Frame counter advances AFTER all tick logic completes
global.rollback_clock.AddEndTickMethod(function()
{
	//show_debug_message("Frame advancing from " + string(global.absolute_frame) + " to " + string(global.absolute_frame + 1));
	global.absolute_frame++;
});

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

function send_input(_frame) {
	var _buffer = buffer_create(4 + INPUT_VERB_COUNT * 4, buffer_fixed, 1);
	buffer_write(_buffer, buffer_u32, _frame);
	
	var _buffer_index = _frame % ROLLBACK_DEPTH;
	for (var i = 0; i < INPUT_VERB_COUNT; i++) {
		buffer_write(_buffer, buffer_f32, global.input_buffer[_buffer_index][local_player_index][i]);
	}
	
	relay_send(_buffer, PAYLOAD.INPUT);
	buffer_delete(_buffer);
	
	last_input_frame[local_player_index] = _frame;
	last_heard_frame[local_player_index] = _frame;
	
	show_debug_message("TX INPUT frame=" + string(_frame));
}

function send_heartbeat(_frame) {
	var _buffer = buffer_create(4, buffer_fixed, 1);
	buffer_write(_buffer, buffer_u32, _frame);
	relay_send(_buffer, PAYLOAD.HEARTBEAT);
	buffer_delete(_buffer);
}

function perform_rollback(_target_frame) {
	var _current_frame = global.absolute_frame;
	var _frames_to_resim = _current_frame - _target_frame;
	
	show_debug_message("ROLLBACK: " + string(_frames_to_resim) + " frames (frame " + string(_target_frame) + " -> " + string(_current_frame) + ")");
	
	// Restore RNG state
	var _target_buffer_index = _target_frame % ROLLBACK_DEPTH;
	if (rng_state_buffer[_target_buffer_index] != undefined)
	{
		rollback_random_set_state(rng_state_buffer[_target_buffer_index]);
	}
	
	// Set state for other objects
	global.rollbacking = _frames_to_resim;
	global.absolute_frame = _target_frame;
	global.rollback_tick_frame = _target_frame;
	
	// Signal objects to restore their state
	PP.signal_send(SIGNAL_ROLLBACK);
	
	// Resimulate exactly _frames_to_resim ticks (no delta_time accumulation)
	resimulating = true;
	global.rollback_clock.ForceUpdateTicks(_frames_to_resim);
	resimulating = false;
	
	global.rollbacking = 0;
	for (var p = 0; p < player_count; p++)
	{
		rollback_trigger_players[p] = false;
	}
}

display_position = function()
{
	var _rect = PP.splitview_get_window_rect(0);
	draw_set_valign(fa_top);
	draw_set_halign(fa_left);
	draw_set_colour(c_white);
	draw_set_font(fnt_tmp)
	draw_text( 40, 40, string(global.absolute_frame));
}

PP.signal_subscribe(SIGNAL_SPLITVIEW_DRAWUI, display_position);
