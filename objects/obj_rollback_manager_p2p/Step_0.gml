// =============================================================================
// PROCESS QUEUED NETWORK MESSAGES
// =============================================================================
// First, even while stalled: a message is what ends a stall
var _heard_from	 = array_create(player_count, false);
_heard_from[local_player_index] = true;
var _deferred	   = [];

while (!ds_queue_empty(message_queue))
{
	var _msg		  = ds_queue_dequeue(message_queue);
	var _sender_index = array_get_index(global.relay_players, _msg.sender);

	if (_sender_index < 0 || _sender_index == local_player_index) {
		if (_msg.type == PAYLOAD.INPUT) buffer_delete(_msg.payload);
		continue;
	}

	_heard_from[_sender_index]	  = true;
	ticks_since_message[_sender_index] = 0;

	switch (_msg.type) {
		case PAYLOAD.HEARTBEAT:
			last_heard_frame[_sender_index] = max(last_heard_frame[_sender_index], _msg.frame);
			break;

		case PAYLOAD.ADVANTAGE:
			// One sampled before a skip of ours ended is stale
			if (global.absolute_frame >= sync_after_frame) remote_advantage[_sender_index] = _msg.advantage;
			break;

		case PAYLOAD.INPUT:
			var _frame = _msg.frame;

			// Storing input further ahead would push frames we may roll back to out of the buffer
			if (_frame > global.absolute_frame + ROLLBACK_INPUT_LEAD) {
				array_push(_deferred, _msg);
				break;
			}

			// Frames after it are predicted again; a misprediction on a simulated frame is reported below
			if (InputCircularBufferImport(_msg.payload, _sender_index) == undefined) {
				show_debug_message(debug_id + "Input from P" + string(_sender_index) + " frame=" + string(_frame)
					+ " left the buffer (oldest=" + string(InputCircularBufferGetOldestFrame()) + ")");
			}
			buffer_delete(_msg.payload);

			last_heard_frame[_sender_index] = max(last_heard_frame[_sender_index], _frame);
			break;
	}
}

for (var i = 0; i < array_length(_deferred); i++) {
	ds_queue_enqueue(message_queue, _deferred[i]);
}

// =============================================================================
// CONNECTION PAUSE: wait until every player has been heard of again
// =============================================================================
if (connection_paused)
{
	var _recovered = true;
	for (var p = 0; p < player_count; p++) {
		if (p == local_player_index) continue;
		if (ticks_since_message[p] >= ROLLBACK_STALL_THRESHOLD) {
			_recovered = false;
			break;
		}
	}

	if (!_recovered) {
		if (++pause_timer >= game_get_speed(gamespeed_fps) * 5) {
			show_debug_message(debug_id + "Connection timeout");
			room_goto(rm_init);
		}
		return;
	}

	connection_paused = false;
	pause_timer = 0;
	global.rollback_clock.SetPause(false);
	show_debug_message(debug_id + "Connection recovered");
}

// =============================================================================
// TIME SYNC
// =============================================================================
// Skip when we are ahead of a player by 2 frames or more (a difference of 4), by both sides' averages
if (skip_frames == 0 && global.absolute_frame >= sync_after_frame) {
	for (var p = 0; p < player_count; p++) {
		if (p == local_player_index || remote_advantage[p] == undefined || local_advantage[p] == undefined) continue;

		var _difference = local_advantage[p] - remote_advantage[p];
		if (_difference >= ROLLBACK_SYNC_MIN_DIFFERENCE) skip_frames = max(skip_frames, min(_difference div 2, ROLLBACK_SYNC_MAX_SKIP));
		remote_advantage[p] = undefined;
	}
	if (skip_frames > 0) {
		// The averages sampled until the skip ends no longer hold: wait for two fresh windows
		sync_after_frame = global.absolute_frame + 2 * ROLLBACK_SYNC_EVERY;
		show_debug_message(debug_id + "Time sync: skipping " + string(skip_frames) + " frames");
	}
}

// Hold while a misprediction of a player's next input would need a frame the rollback no longer has
var _hold = false;
for (var p = 0; p < player_count; p++) {
	if (p != local_player_index && global.absolute_frame - known_frame(p) >= ROLLBACK_DEPTH - 2) _hold = true;
}

// =============================================================================
// PERFORM ROLLBACK OR ADVANCE CLOCK
// =============================================================================
var _ticks_executed = 0;
var _rollback_target = InputCircularBufferGetChangedFrame();

if (_rollback_target != undefined && _rollback_target < global.absolute_frame) {
	InputCircularBufferClearChangedFrame();
	show_debug_message(debug_id + "ROLLBACK TRIGGER frame=" + string(_rollback_target) + " current=" + string(global.absolute_frame));

	var _min_valid = max(global.absolute_frame - ROLLBACK_DEPTH + 1, InputCircularBufferGetOldestFrame());

	if (_rollback_target < _min_valid) {
		show_debug_message(debug_id + "CRITICAL DESYNC — target " + string(_rollback_target) + " too old");
		room_goto(rm_init);
		return;
	}

	perform_rollback(_rollback_target);
}
else
{
	// A change on a frame not simulated yet needs no rollback
	if (_rollback_target != undefined) InputCircularBufferClearChangedFrame();

	if (_hold || skip_frames > 0) {
		// This GameMaker frame's time is dropped (Update reads this frame's delta_time); it counts as a tick towards a stall
		if (!_hold) skip_frames--;
		_ticks_executed = 1;
	} else {
		_ticks_executed = global.rollback_clock.Update();
	}
}

// Our advantage, sampled each frame and sent averaged, for the others' time sync
for (var p = 0; p < player_count; p++) {
	if (p != local_player_index) advantage_sum[p] += advantage(p);
}
advantage_samples++;

if (global.absolute_frame >= next_advantage_frame) {
	next_advantage_frame = global.absolute_frame + ROLLBACK_SYNC_EVERY;
	send_advantage();
}


// Outside of ticks, Input returns live device state
InputCircularBufferSeek(undefined);

// =============================================================================
// TIMEOUT TRACKING
// =============================================================================
if (_ticks_executed > 0) {
	for (var p = 0; p < player_count; p++) {
		if (p == local_player_index) continue;

		if (!_heard_from[p]) {
			ticks_since_message[p] += _ticks_executed;
		}

		if (ticks_since_message[p] >= ROLLBACK_STALL_THRESHOLD) {
			show_debug_message(debug_id + "Stalled on P" + string(p));
			global.rollback_clock.SetPause(true);
			connection_paused = true;
			pause_timer = 0;
			return;
		}
	}
}
