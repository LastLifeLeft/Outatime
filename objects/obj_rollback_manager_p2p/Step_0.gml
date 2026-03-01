if (connection_paused)
{
	pause_timer++;
	
	if (pause_timer >= room_speed * 5) {
		show_debug_message(debug_id + "Connection timeout");
		room_goto(rm_p2p_menu);
		return;
	}
	
	var _recovered = true;
	for (var p = 0; p < player_count; p++) {
		if (p == local_player_index) continue;
		if (ticks_since_message[p] >= ROLLBACK_STALL_THRESHOLD) {
			_recovered = false;
			break;
		}
	}
	
	if (_recovered) {
		connection_paused = false;
		pause_timer = 0;
		global.rollback_clock.SetPause(false);
		show_debug_message(debug_id + "Connection recovered");
	}
	
	return;
}

// =============================================================================
// PROCESS QUEUED NETWORK MESSAGES
// =============================================================================
var _need_rollback  = false;
var _rollback_target = global.absolute_frame;
var _heard_from	 = array_create(player_count, false);
_heard_from[local_player_index] = true;

for (var p = 0; p < player_count; p++) {
	rollback_trigger_players[p] = false;
}

while (!ds_queue_empty(message_queue))
{
	var _msg		  = ds_queue_dequeue(message_queue);
	var _sender_index = array_get_index(global.relay_players, _msg.sender);
	
	if (_sender_index < 0 || _sender_index == local_player_index) continue;
	
	_heard_from[_sender_index]	  = true;
	ticks_since_message[_sender_index] = 0;
	
	switch (_msg.type) {
		case PAYLOAD.HEARTBEAT:
			last_heard_frame[_sender_index] = _msg.frame;
			break;
			
		case PAYLOAD.INPUT:
			var _frame		= _msg.frame;
			var _inputs	   = _msg.inputs;
			var _buffer_index = _frame % ROLLBACK_DEPTH;
			
			// Fill gaps
			var _last = last_input_frame[_sender_index];
			if (_last >= 0 && _frame > _last + 1) {
				var _gap_start = max(_last + 1, _frame - ROLLBACK_DEPTH + 1);
				var _gap_end   = _frame - 1;
				var _src	   = _last % ROLLBACK_DEPTH;
				
				for (var f = _gap_start; f <= _gap_end; f++) {
					var _dst = f % ROLLBACK_DEPTH;
					for (var v = 0; v < INPUT_VERB_COUNT; v++) {
						global.input_buffer[_dst][_sender_index][v] = global.input_buffer[_src][_sender_index][v];
					}
				}
			}
			
			// Store actual input
			for (var v = 0; v < INPUT_VERB_COUNT; v++) {
				global.input_buffer[_buffer_index][_sender_index][v] = _inputs[v];
			}
			
			if (_frame > last_input_frame[_sender_index]) last_input_frame[_sender_index] = _frame;
			if (_frame > last_heard_frame[_sender_index]) last_heard_frame[_sender_index] = _frame;
			
			// Rollback needed?
			if (_frame < global.absolute_frame) {
				_need_rollback   = true;
				_rollback_target = min(_rollback_target, _frame);
				rollback_trigger_players[_sender_index] = true;
				
				show_debug_message(debug_id + "ROLLBACK TRIGGER from P" + string(_sender_index)
					+ " frame=" + string(_frame) + " current=" + string(global.absolute_frame));
			}
			break;
	}
}

// =============================================================================
// PERFORM ROLLBACK OR ADVANCE CLOCK
// =============================================================================
var _ticks_executed = 0;

if (_need_rollback) {
	var _min_valid = global.absolute_frame - ROLLBACK_DEPTH + 1;
	
	if (_rollback_target < _min_valid) {
		show_debug_message(debug_id + "CRITICAL DESYNC — target " + string(_rollback_target) + " too old");
		room_goto(rm_p2p_menu);
		return;
	}
	
	perform_rollback(_rollback_target);
}
else
{
	_ticks_executed = global.rollback_clock.Update();
}

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