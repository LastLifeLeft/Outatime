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

// =============================================================================
// INPUT: Input's Circular Buffer plug-in, seat p = Input player p
// =============================================================================
// Remote seats are ghosts. Their input is imported as it arrives and predicted until then
rollback_input_begin(player_count, local_player_index);

input_packet	= buffer_create(4 + InputCircularBufferExportByteLength(), buffer_fixed, 1);
last_sent_verbs = "";

// =============================================================================
// PER-PLAYER NETWORK TRACKING
// =============================================================================
ticks_since_message = array_create(player_count, -ROLLBACK_GRACE_PERIOD);
ticks_since_message[local_player_index] = 0;

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
// TIME SYNC
// =============================================================================
// The clock drops the time it could not run (a hitch, a dragged window) instead of catching up, so
// the players drift apart. Every ROLLBACK_SYNC_EVERY ticks each one tells the others its advantage
// over them (its frame minus the last frame it heard of theirs), averaged over that time since
// heartbeats only come every 5 unchanged frames. The latency is in both sides' values
// and cancels out of their difference; the one ahead skips half of it, one GameMaker frame at a time.
// Apart from that, the clock holds while a rollback would need a frame older than ROLLBACK_DEPTH.
remote_advantage	 = array_create(player_count, undefined);	// each player's advantage over us, as last sent
local_advantage = array_create(player_count, undefined);	// ours over each, averaged over the last ROLLBACK_SYNC_EVERY ticks
advantage_sum = array_create(player_count, 0);			// the samples of the window in progress, one per GameMaker frame
advantage_samples = 0;
next_advantage_frame = ROLLBACK_SYNC_EVERY;
sync_after_frame = 0;										// no skip decided before it: the averages of a skip's time are stale
skip_frames		  = 0;

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
	
	// Save RNG state, capture & send local input (normal play only)
	if (!resimulating) {
		rng_state_buffer[_current_buffer_index] = rollback_random_get_state();
		
		var _input_frame = _current_frame + ROLLBACK_INPUT_DELAY;
		InputCircularBufferRecord(_input_frame, local_player_index);
		send_local_input(_input_frame);
	}
	
	// Input's checkers now return this frame's input, remote seats predicted until their input arrives
	InputCircularBufferSeek(_current_frame);
});

// ---- END TICK ----
global.rollback_clock.AddEndTickMethod(function()
{
	global.absolute_frame++;
});

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

/// Send local input for a given frame when it changed, a heartbeat every 5 unchanged frames
function send_local_input(_frame) {
	buffer_seek(input_packet, buffer_seek_start, 0);
	buffer_write(input_packet, buffer_u32, _frame);
	InputCircularBufferExport(input_packet, _frame, local_player_index);
	
	// The verbs follow the frame and Export's 7-byte header
	var _verbs = buffer_md5(input_packet, 11, buffer_tell(input_packet) - 11);
	if (_verbs != last_sent_verbs) {
		last_sent_verbs		= _verbs;
		ticks_since_input_sent = 0;
		net_send(input_packet, PAYLOAD.INPUT);	// <— unified API
		last_heard_frame[local_player_index] = _frame;
	} else if (++ticks_since_input_sent >= 5) {
		ticks_since_input_sent = 0;
		send_heartbeat(_frame);
	}
}

/// Send a lightweight heartbeat (no input data, just frame number)
function send_heartbeat(_frame) {
	var _buffer = buffer_create(4, buffer_fixed, 1);
	buffer_write(_buffer, buffer_u32, _frame);
	net_send(_buffer, PAYLOAD.HEARTBEAT);	// <— unified API
	buffer_delete(_buffer);
}

/// The frame a player's input is known up to: its newest input, or a heartbeat since
function known_frame(_player) {
	return max(InputCircularBufferGetConfirmedFrame(_player), last_heard_frame[_player]);
}

/// Our frames ahead of a player: our frame minus the last frame it was on when we heard of it
function advantage(_player) {
	return global.absolute_frame - (last_heard_frame[_player] - ROLLBACK_INPUT_DELAY);
}

/// Tell the others our average advantage over each of them (s16 per player, our own entry 0)
function send_advantage() {
	var _buffer = buffer_create(2 * player_count, buffer_fixed, 1);
	for (var p = 0; p < player_count; p++) {
		local_advantage[p] = (p == local_player_index || advantage_samples == 0)? 0 : round(advantage_sum[p] / advantage_samples);
		advantage_sum[p] = 0;
		buffer_write(_buffer, buffer_s16, clamp(local_advantage[p], -32768, 32767));
	}
	advantage_samples = 0;
	net_send(_buffer, PAYLOAD.ADVANTAGE);
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
