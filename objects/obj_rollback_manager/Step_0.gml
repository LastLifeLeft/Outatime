// =============================================================================
// CONNECTION PAUSE HANDLING
// =============================================================================
if (connection_paused)
{
	pause_timer++;
	
	if (pause_timer >= room_speed * 5)
	{
		show_debug_message(debug_id +"ROLLBACK: Connection timeout - returning to title");
		room_goto(rm_title);
		return;
	}
	
	// Check recovery
	var _recovered = true;
	for (var p = 0; p < player_count; p++)
	{
		if (p == local_player_index) continue;
		if (ticks_since_message[p] >= ROLLBACK_STALL_THRESHOLD)
		{
			_recovered = false;
			break;
		}
	}
	
	if (_recovered)
	{
		connection_paused = false;
		pause_timer = 0;
		global.rollback_clock.SetPause(false);
		show_debug_message(debug_id + "ROLLBACK: Connection recovered");
	}
	
	return;
}

// =============================================================================
// PROCESS QUEUED NETWORK MESSAGES
// =============================================================================
var _need_rollback = false;
var _rollback_target = global.absolute_frame;
var _heard_from = array_create(player_count, false);
_heard_from[local_player_index] = true;

for (var p = 0; p < player_count; p++)
{
	rollback_trigger_players[p] = false;
}

while (!ds_queue_empty(message_queue))
{
	var _msg = ds_queue_dequeue(message_queue);
	var _sender_index = array_get_index(global.relay_players, _msg.sender);
	
	if (_sender_index < 0 || _sender_index == local_player_index) continue;
	
	_heard_from[_sender_index] = true;
	ticks_since_message[_sender_index] = 0;
	
	switch (_msg.type) {
		case PAYLOAD.HEARTBEAT:
			last_heard_frame[_sender_index] = _msg.frame;
			
			//show_debug_message(debug_id + "RX HEARTBEAT from " + string(_sender_index) + 
			//	" frame=" + string(_msg.frame) + 
			//	" drift=" + string(global.rollback_tick_frame - _msg.frame));
			break;
			
		case PAYLOAD.INPUT:
			var _frame = _msg.frame;
			var _inputs = _msg.inputs;
			var _buffer_index = _frame % ROLLBACK_DEPTH;
	
			// Fill in any gaps by copying from the last known input
			var _last = last_input_frame[_sender_index];
			if (_last >= 0 && _frame > _last + 1)
			{
				var _gap_start = max(_last + 1, _frame - ROLLBACK_DEPTH + 1);
				var _gap_end = _frame - 1;
				var _src_index = _last % ROLLBACK_DEPTH;
		
				for (var f = _gap_start; f <= _gap_end; f++) {
					var _dst_index = f % ROLLBACK_DEPTH;
					for (var i = 0; i < INPUT_VERB_COUNT; i++) {
						global.input_buffer[_dst_index][_sender_index][i] = 
							global.input_buffer[_src_index][_sender_index][i];
					}
				}
			}
	
			// Store actual input
			for (var i = 0; i < INPUT_VERB_COUNT; i++)
			{
				global.input_buffer[_buffer_index][_sender_index][i] = _inputs[i];
			}
	
			if (_frame > last_input_frame[_sender_index])
			{
				last_input_frame[_sender_index] = _frame;
			}
			if (_frame > last_heard_frame[_sender_index])
			{
				last_heard_frame[_sender_index] = _frame;
			}
	
			// Check rollback - mark this player as a trigger
			if (_frame < global.absolute_frame)
			{
				// Add this right before line 337 (_need_rollback = true):
				show_debug_message(debug_id + "ROLLBACK TRIGGER: sender=" + string(_sender_index) + 
					" input_frame=" + string(_frame) + 
					" absolute_frame=" + string(global.absolute_frame) + 
					" last_input_frame=" + string(last_input_frame[_sender_index]) + 
					" last_heard_frame=" + string(last_heard_frame[_sender_index]) +
					" gap=" + string(_frame - last_input_frame[_sender_index]));
					
				_need_rollback = true;
				_rollback_target = min(_rollback_target, _frame);
				rollback_trigger_players[_sender_index] = true;
			}
			
			show_debug_message(debug_id + "RX INPUT from " + string(_sender_index) + " frame=" + string(_frame) + " (current=" + string(global.absolute_frame) + ")" + " rollback=" + string(_need_rollback));
			break;
	}
}

// =============================================================================
// PERFORM ROLLBACK BEFORE SIMULATING NEW TICKS
// =============================================================================
var _ticks_executed = 0;

if (_need_rollback) {
	var _min_valid_frame = global.absolute_frame - ROLLBACK_DEPTH + 1;
	
	show_debug_message(debug_id + "ROLLBACK CHECK: target=" + string(_rollback_target) + 
		" current=" + string(global.absolute_frame) + 
		" min_valid=" + string(_min_valid_frame) +
		" diff=" + string(global.absolute_frame - _rollback_target));
	
	if (_rollback_target < _min_valid_frame) {
		show_debug_message(debug_id + "ROLLBACK: Critical desync - target frame " + string(_rollback_target) + 
			" too old (min=" + string(_min_valid_frame) + ")");
		room_goto(rm_title);
		return;
	}
	
	perform_rollback(_rollback_target);
	// Don't run normal clock.Update() this frame - rollback already simulated ticks
}
else
{
	// NORMAL CLOCK UPDATE (only if no rollback occurred)
	_ticks_executed = global.rollback_clock.Update();
}

// =============================================================================
// TIMEOUT TRACKING (only after ticks run)
// =============================================================================
if (_ticks_executed > 0) {
	for (var p = 0; p < player_count; p++)
	{
		if (p == local_player_index) continue;
		
		if (!_heard_from[p]) {
			ticks_since_message[p] += _ticks_executed;
		}
		
		if (ticks_since_message[p] >= ROLLBACK_STALL_THRESHOLD) {
			show_debug_message(debug_id + "ROLLBACK: Connection stalled for player " + string(p) + 
				" last_heard=" + string(last_heard_frame[p]) +
				" last_input=" + string(last_input_frame[p]));;
			global.rollback_clock.SetPause(true);
			connection_paused = true;
			pause_timer = 0;
			return;
		}
	}
}