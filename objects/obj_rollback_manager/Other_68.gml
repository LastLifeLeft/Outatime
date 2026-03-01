var _events = relay_async_network();

for (var i = 0; i < array_length(_events); i++) {
	var _event = _events[i];
	
	switch (_event.type) {
		case "DISCONNECTED":
			show_debug_message("ROLLBACK: Disconnected from server");
			room_goto(rm_title);
			break;
			
		case "PLAYER_LEFT":
			global.chat.add_message(_event.data + " left.", MSG_TYPE.PARTY);
			// TODO: Handle player leaving mid-game (remove from tracking, etc.)
			break;
			
		case "RELAY":
			var _payload = _event.data.payload;
			var _sender = _event.data.sender;
			var _type = _event.data.payload_type_id;
			
			if (_payload != undefined) {
				buffer_seek(_payload, buffer_seek_start, 0);
				
				switch (_type) {
					case PAYLOAD.HEARTBEAT:
						var _frame = buffer_read(_payload, buffer_u32);
						ds_queue_enqueue(message_queue, {
							type: PAYLOAD.HEARTBEAT,
							sender: _sender,
							frame: _frame
						});
						break;
						
					case PAYLOAD.INPUT:
						var _frame = buffer_read(_payload, buffer_u32);
						var _inputs = array_create(INPUT_VERB_COUNT);
						for (var j = 0; j < INPUT_VERB_COUNT; j++) {
							_inputs[j] = buffer_read(_payload, buffer_f32);
						}
						ds_queue_enqueue(message_queue, {
							type: PAYLOAD.INPUT,
							sender: _sender,
							frame: _frame,
							inputs: _inputs
						});
						break;
						
					case PAYLOAD.CHAT:
						global.chat.add_message(_sender + ": " + buffer_read(_payload, buffer_string), MSG_TYPE.NORMAL);
						break;
						
					case PAYLOAD.SKILLSELECT:
						var _sender_index = array_get_index(global.relay_players, _sender);
						var _selection = buffer_read(_payload, buffer_u8);
						global.player_objects[_sender_index].learn_skill(global.player_objects[_sender_index].skill_choices[_selection].skill_id, global.player_objects[_sender_index].skill_choices[_selection].quality);
						//player.learn_skill(player.skill_choices[selection].skill_id, player.skill_choices[selection].quality);
						//show_debug_message(_sender);
						//show_debug_message("choose skill #" + string(buffer_read(_payload, buffer_u8)));
						
						global.skill_chosen ++;
						
						if (global.skill_chosen == global.playercount)
						{
							obj_mission_manager.mission_active = true;
							global.rollback_clock.SetPause(false);
						}
						
						break;
				}
				
				buffer_delete(_payload);
			}
			break;
			
		case "LOBBY_CLOSED":
			show_debug_message("ROLLBACK: Lobby closed - " + string(_event.data));
			room_goto(rm_title);
			break;
			
		case "ERROR":
			global.chat.add_message("Error: " + _event.data, MSG_TYPE.ERROR);
			break;
	}
}