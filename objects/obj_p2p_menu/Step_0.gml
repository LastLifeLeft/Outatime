// --- HOST ---
if (keyboard_check_pressed(ord("H")) && !is_initialized)
{
	direct_init("Host", 2);
	direct_host(JOIN_PORT);
	is_initialized = true;
	role = "host";
	status = "Hosting on port " + string(JOIN_PORT) + "...\nWaiting for player.\nPress [S] to Start when ready.";
	show_debug_message("MENU: Hosting started");
}

// --- JOIN ---
if (keyboard_check_pressed(ord("J")) && !is_initialized)
{
	direct_init("Client", 2);
	direct_join(JOIN_IP, JOIN_PORT);
	is_initialized = true;
	role = "client";
	status = "Connecting to " + JOIN_IP + ":" + string(JOIN_PORT) + "...";
	show_debug_message("MENU: Join started");
}

// --- START GAME (host only) ---
if (keyboard_check_pressed(ord("S")) && is_initialized && role == "host")
{
	if (net_get_player_count() >= 2)
	{
		// Share a random seed with the client before starting
		global.rollback_seed = irandom(999999);
		
		var _buf = buffer_create(4, buffer_fixed, 1);
		buffer_write(_buf, buffer_u32, global.rollback_seed);
		net_send(_buf, PAYLOAD.RANDOM);
		buffer_delete(_buf);
		show_debug_message("MENU HOST: Sent seed = " + string(global.rollback_seed));
		
		// Start the game
		net_start_game();
		
		// Alias for the rollback manager
		global.relay_players  = net_get_players();
		global.relay_nickname = net_get_nickname();
		
		show_debug_message("MENU HOST: Going to game room. Players: " + string(global.relay_players));
		room_goto(rm_p2p_game);
	}
	else
	{
		status = "Need 2 players to start! Currently: " + string(net_get_player_count());
	}
}

// =============================================================================
// STATE POLLING
// =============================================================================
if (is_initialized && role == "client" && net_get_mode() == NET_MODE.DIRECT)
{
	if (direct_is_in_lobby())
	{
		var _pc = net_get_player_count();
		status = "In lobby! Players: " + string(_pc) + "/2\nWaiting for host to start...";
	}
	else if (global.direct_connected && global.direct_authenticated)
	{
		status = "Authenticated! Waiting for lobby info...";
	}
	else if (global.direct_connected && !global.direct_authenticated)
	{
		status = "Connected! Waiting for auth...";
	}
}