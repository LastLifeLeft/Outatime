show_debug_message("MENU ASYNC: fired | type=" + string(async_load[? "type"]) + " | id=" + string(async_load[? "id"]));

var _events = net_async_network();

show_debug_message("MENU ASYNC: " + string(array_length(_events)) + " event(s) returned");

for (var i = 0; i < array_length(_events); i++)
{
	var _event = _events[i];
	show_debug_message("MENU ASYNC: [" + string(i) + "] type=\"" + _event.type + "\"");
	
	switch (_event.type)
	{
		case "CONNECTED":
			show_debug_message("MENU: TCP connected to host");
			break;
			
		case "CONNECT_FAILED":
			status = "Connection failed. Press [J] to retry.";
			is_initialized = false;
			show_debug_message("MENU: Connection FAILED");
			break;
		
		case "AUTH_OK":
			show_debug_message("MENU: AUTH_OK received");
			break;
		
		case "AUTH_FAIL":
			status = "Auth failed: " + string(_event.data) + "\nPress [J] to retry.";
			is_initialized = false;
			show_debug_message("MENU: Auth FAILED — " + string(_event.data));
			break;
			
		case "JOIN_OK":
			show_debug_message("MENU: JOIN_OK — players: " + string(net_get_players()));
			break;
			
		case "PLAYER_JOINED":
			status = "Player joined: " + _event.data + " (" + string(net_get_player_count()) + "/2)\nPress [S] to Start.";
			show_debug_message("MENU: Player joined: " + _event.data);
			break;
			
		case "PLAYER_LEFT":
			status = "Player left: " + _event.data;
			show_debug_message("MENU: Player left: " + _event.data);
			break;
			
		case "GAME_STARTED":
			show_debug_message("MENU: GAME_STARTED received");
			global.relay_players  = net_get_players();
			global.relay_nickname = net_get_nickname();
			room_goto(rm_p2p_game);
			break;
			
		case "RELAY":
			var _payload  = _event.data.payload;
			var _type_id  = _event.data.payload_type_id;
			show_debug_message("MENU: RELAY payload_type=" + string(_type_id));
			
			if (_payload != undefined)
			{
				buffer_seek(_payload, buffer_seek_start, 0);
				
				if (_type_id == PAYLOAD.RANDOM)
				{
					global.rollback_seed = buffer_read(_payload, buffer_u32);
					seed_received = true;
					show_debug_message("MENU: Received seed = " + string(global.rollback_seed));
				}
				
				buffer_delete(_payload);
			}
			break;
			
		case "DISCONNECTED":
			status = "Disconnected.";
			is_initialized = false;
			show_debug_message("MENU: Disconnected");
			break;
			
		case "LOBBY_CLOSED":
			status = "Lobby closed.";
			is_initialized = false;
			show_debug_message("MENU: Lobby closed");
			break;
			
		default:
			show_debug_message("MENU: Unhandled event: \"" + _event.type + "\"");
			break;
	}
}