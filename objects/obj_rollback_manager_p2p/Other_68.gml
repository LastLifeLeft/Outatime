var _events = net_async_network();   // <— unified API

for (var i = 0; i < array_length(_events); i++) {
	var _event = _events[i];
	
	switch (_event.type) {
		case "DISCONNECTED":
			show_debug_message(debug_id + "Disconnected");
			room_goto(rm_init);
			break;
			
		case "PLAYER_LEFT":
			show_debug_message(debug_id + _event.data + " left");
			room_goto(rm_init);
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
						// The Step event imports the rest of the payload, then deletes it
						var _frame = buffer_read(_payload, buffer_u32);
						ds_queue_enqueue(message_queue, {
							type:	PAYLOAD.INPUT,
							sender:  _sender,
							frame:   _frame,
							payload: _payload
						});
						_payload = undefined;
						break;

					case PAYLOAD.ADVANTAGE:
						// The sender's advantage over each player: ours is at our index
						if (buffer_get_size(_payload) >= 2 * (local_player_index + 1)) {
							buffer_seek(_payload, buffer_seek_start, 2 * local_player_index);
							ds_queue_enqueue(message_queue, {
								type:	  PAYLOAD.ADVANTAGE,
								sender:	_sender,
								advantage: buffer_read(_payload, buffer_s16)
							});
						}
						break;
				}
				
				if (_payload != undefined) buffer_delete(_payload);
			}
			break;
			
		case "LOBBY_CLOSED":
			show_debug_message(debug_id + "Lobby closed");
			room_goto(rm_init);
			break;
	}
}