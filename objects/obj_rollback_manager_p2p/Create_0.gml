/////////////////////////////////////////////////////////////////////////////////////
// /!\ WARNING /!\
// Peer to peer is absolutely untested, I only implemented it for this demo. 
/////////////////////////////////////////////////////////////////////////////////////

// Singleton
if (instance_number(object_index) > 1) {
	show_debug_message("WARNING: Duplicate rollback manager — destroying");
	instance_destroy();
	return;
}

#macro ROLLBACK_STALL_THRESHOLD 40   // Ticks without a message before stalling (~1 sec at 40 Hz)
#macro ROLLBACK_GRACE_PERIOD	80   // Grace ticks at start before enforcing timeout

// =============================================================================
// PLAYER INFO
// =============================================================================
player_count	   = array_length(global.relay_players);
local_player_index = array_get_index(global.relay_players, global.relay_nickname);
debug_id		   = "P" + string(local_player_index) + ": ";

show_debug_message(debug_id + "Players: " + string(global.relay_players));
show_debug_message(debug_id + "Local index: " + string(local_player_index));

// =============================================================================
// FRAME TRACKING
// =============================================================================
global.absolute_frame	= 0;
global.rollbacking	   = 0;
global.rollback_tick_frame = 0;
resimulating			 = false;
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
last_confirmed_frame = array_create(player_count, -1);
last_confirmed_frame[local_player_index] = ROLLBACK_INPUT_DELAY;

ticks_since_message = array_create(player_count, -ROLLBACK_GRACE_PERIOD);
ticks_since_message[local_player_index] = 0;

last_input_frame = array_create(player_count, -1);
last_input_frame[local_player_index] = ROLLBACK_INPUT_DELAY;

last_heard_frame = array_create(player_count, -1);
last_heard_frame[local_player_index] = ROLLBACK_INPUT_DELAY;

// =============================================================================
// NETWORK MESSAGE QUEUE
// =============================================================================
message_queue		  = ds_queue_create();
ticks_since_input_sent = 0;

// =============================================================================
// CONNECTION STATE
// =============================================================================
connection_paused = false;
pause_timer	   = 0;

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

// ---- BEGIN TICK ----
global.rollback_clock.AddBeginTickMethod(function()
{
	var _current_frame		= global.absolute_frame;
	var _current_buffer_index = _current_frame % ROLLBACK_DEPTH;
	
	global.rollback_tick_frame = _current_frame;
	
	// Save RNG state (normal play only)
	if (!resimulating) {
		rng_state_buffer[_current_buffer_index] = rollback_random_get_state();
	}
	
	// Predict remote inputs
	for (var p = 0; p < player_count; p++) {
		if (p == local_player_index) continue;
		if (resimulating && !rollback_trigger_players[p]) continue;
		
		if (last_input_frame[p] < _current_frame) {
			var _prev = (_current_frame - 1 + ROLLBACK_DEPTH) % ROLLBACK_DEPTH;
			for (var i = 0; i < INPUT_VERB_COUNT; i++) {
				global.input_buffer[_current_buffer_index][p][i] = global.input_buffer[_prev][p][i];
			}
		}
	}
	
	// Capture & send local input (normal play only)
	if (!resimulating) {
		var _input_frame		= _current_frame + ROLLBACK_INPUT_DELAY;
		var _input_buffer_index = _input_frame % ROLLBACK_DEPTH;
		var _prev_input_index   = (_input_frame - 1 + ROLLBACK_DEPTH) % ROLLBACK_DEPTH;
		var _input_changed	  = false;
		
		for (var i = 0; i < INPUT_VERB_COUNT; i++) {
			var _val = InputCheck(i, 0);
			if (_val != global.input_buffer[_prev_input_index][local_player_index][i]) {
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

// ---- END TICK ----
global.rollback_clock.AddEndTickMethod(function()
{
	global.absolute_frame++;
});

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

/// Send local input for a given frame
function send_input(_frame) {
	var _buffer = buffer_create(4 + INPUT_VERB_COUNT * 4, buffer_fixed, 1);
	buffer_write(_buffer, buffer_u32, _frame);
	
	var _bi = _frame % ROLLBACK_DEPTH;
	for (var i = 0; i < INPUT_VERB_COUNT; i++) {
		buffer_write(_buffer, buffer_f32, global.input_buffer[_bi][local_player_index][i]);
	}
	
	net_send(_buffer, PAYLOAD.INPUT);		// <— unified API
	buffer_delete(_buffer);
	
	last_input_frame[local_player_index] = _frame;
	last_heard_frame[local_player_index] = _frame;
}

/// Send a lightweight heartbeat (no input data, just frame number)
function send_heartbeat(_frame) {
	var _buffer = buffer_create(4, buffer_fixed, 1);
	buffer_write(_buffer, buffer_u32, _frame);
	net_send(_buffer, PAYLOAD.HEARTBEAT);	// <— unified API
	buffer_delete(_buffer);
}

/// Roll back to _target_frame and re-simulate forward
function perform_rollback(_target_frame) {
	var _current_frame  = global.absolute_frame;
	var _frames_to_resim = _current_frame - _target_frame;
	
	show_debug_message(debug_id + "ROLLBACK " + string(_frames_to_resim) + " frames (" 
		+ string(_target_frame) + " → " + string(_current_frame) + ")");
	
	// Restore RNG
	var _bi = _target_frame % ROLLBACK_DEPTH;
	if (rng_state_buffer[_bi] != undefined) {
		rollback_random_set_state(rng_state_buffer[_bi]);
	}
	
	global.rollbacking		 = _frames_to_resim;
	global.absolute_frame	  = _target_frame;
	global.rollback_tick_frame = _target_frame;
	
	// Tell all rollback objects to restore state
	signal_send(SIGNAL_ROLLBACK);
	
	// Re-simulate
	resimulating = true;
	global.rollback_clock.ForceUpdateTicks(_frames_to_resim);
	resimulating = false;
	
	global.rollbacking = 0;
	for (var p = 0; p < player_count; p++) {
		rollback_trigger_players[p] = false;
	}
}

// =============================================================================
// SPAWN PLAYER OBJECTS
// =============================================================================

global.player_objects = [];
var _colors = [c_lime, c_aqua, c_yellow, c_fuchsia];

for (var p = 0; p < player_count; p++) {
	var _px = room_width  / 2 + (p - (player_count - 1) / 2) * 80;
	var _py = room_height / 2;
	var _obj = instance_create_layer(_px, _py, "Instances", obj_p2p_player);
	_obj.player_index = p;
	_obj.player_color = _colors[p % array_length(_colors)];
	global.player_objects[p] = _obj;
}

show_debug_message(debug_id + "Spawned " + string(player_count) + " player objects");

// =============================================================================
// DEBUG HUD (optional)
// =============================================================================

display_hud = function() {
	draw_set_colour(c_white);
	draw_set_halign(fa_left);
	draw_set_valign(fa_top);
	draw_text(8, 8,  "Frame: "  + string(global.absolute_frame));
	draw_text(8, 28, "Player: " + global.relay_nickname + " (#" + string(local_player_index) + ")");
	
	if (connection_paused) {
		draw_set_colour(c_red);
		draw_text(8, 48, "CONNECTION PAUSED");
	}
};
