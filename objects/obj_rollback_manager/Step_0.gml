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
var _heard_from = array_create(player_count, false);
_heard_from[local_player_index] = true;
var _deferred = [];

while (!ds_queue_empty(message_queue))
{
	var _msg = ds_queue_dequeue(message_queue);
	var _sender_index = array_get_index(global.relay_players, _msg.sender);
	
	if (_sender_index < 0 || _sender_index == local_player_index)
	{
		if (_msg.type == PAYLOAD.INPUT) buffer_delete(_msg.payload);
		continue;
	}
	
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
			
			// Storing input further ahead would push frames we may roll back to out of the buffer
			if (_frame > global.absolute_frame + ROLLBACK_INPUT_LEAD)
			{
				array_push(_deferred, _msg);
				break;
			}
			
			// Frames after it are predicted again; a misprediction on a simulated frame is reported below
			if (InputCircularBufferImport(_msg.payload, _sender_index) == undefined)
			{
				show_debug_message(debug_id + "Input from " + string(_sender_index) + " frame=" + string(_frame)
					+ " left the buffer (oldest=" + string(InputCircularBufferGetOldestFrame()) + ")");
			}
			buffer_delete(_msg.payload);
			
			if (_frame > last_heard_frame[_sender_index])
			{
				last_heard_frame[_sender_index] = _frame;
			}
			
			show_debug_message(debug_id + "RX INPUT from " + string(_sender_index) + " frame=" + string(_frame) + " (current=" + string(global.absolute_frame) + ")");
			break;
	}
}

for (var i = 0; i < array_length(_deferred); i++)
{
	ds_queue_enqueue(message_queue, _deferred[i]);
}

// =============================================================================
// PERFORM ROLLBACK BEFORE SIMULATING NEW TICKS
// =============================================================================
var _ticks_executed = 0;
var _rollback_target = InputCircularBufferGetChangedFrame();

if (_rollback_target != undefined) {
	InputCircularBufferClearChangedFrame();
	var _min_valid_frame = max(global.absolute_frame - ROLLBACK_DEPTH + 1, InputCircularBufferGetOldestFrame());
	
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

// Outside of ticks, Input returns live device state
InputCircularBufferSeek(undefined);

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
				" last_input=" + string(InputCircularBufferGetConfirmedFrame(p)));
			global.rollback_clock.SetPause(true);
			connection_paused = true;
			pause_timer = 0;
			return;
		}
	}
}