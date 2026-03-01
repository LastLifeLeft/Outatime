var _events = net_async_network();   // <— unified API

for (var i = 0; i < array_length(_events); i++) {
	var _event = _events[i];
	
	switch (_event.type) {
		case "DISCONNECTED":
			show_debug_message(debug_id + "Disconnected");
			room_goto(rm_p2p_menu);
			break;
			
		case "PLAYER_LEFT":
			show_debug_message(debug_id + _event.data + " left");
			room_goto(rm_p2p_menu);
			break;
			
		case "RELAY":
			var _payload  = _event.data.payload;
			var _sender   = _event.data.sender;
			var _type	 = _event.data.payload_type_id;
			
			if (_payload != undefined) {
				buffer_seek(_payload, buffer_seek_start, 0);
				
				switch (_type) {
					case PAYLOAD.HEARTBEAT:
						var _frame = buffer_read(_payload, buffer_u32);
						ds_queue_enqueue(message_queue, {
							type:   PAYLOAD.HEARTBEAT,
							sender: _sender,
							frame:  _frame
						});
						break;
						
					case PAYLOAD.INPUT:
						var _frame  = buffer_read(_payload, buffer_u32);
						var _inputs = array_create(INPUT_VERB_COUNT);
						for (var j = 0; j < INPUT_VERB_COUNT; j++) {
							_inputs[j] = buffer_read(_payload, buffer_f32);
						}
						ds_queue_enqueue(message_queue, {
							type:   PAYLOAD.INPUT,
							sender: _sender,
							frame:  _frame,
							inputs: _inputs
						});
						break;
				}
				
				buffer_delete(_payload);
			}
			break;
			
		case "LOBBY_CLOSED":
			show_debug_message(debug_id + "Lobby closed");
			room_goto(rm_p2p_menu);
			break;
	}
}