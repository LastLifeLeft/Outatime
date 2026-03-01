// TCP Relay Client Library - Binary Protocol
// Matches the PureBasic server's binary protocol

// Payload types
enum PAYLOAD
{
	// General payloads:
	CHAT,
	HEARTBEAT,
	
	// Game related payloads:
	INPUT,
	SKILLSELECT,
	
	// Lobby specific payloads:
	MISSION,		// sent by the lobby creator to indicate which mission to load
	LOADOUT,		// response to PAYLOAD.MISSION: each player sends their loadout to load needed sprites
	READY,			// sent once all the sprites are loaded
	RANDOM,			// share the random seed.
}

// =============================================================================
// CONNECTION MODE
// =============================================================================

enum NET_MODE
{
	NONE,		// Not initialized
	RELAY,		// Connected via relay server
	DIRECT,		// Direct P2P (host or client)
}

// =============================================================================
// COMMAND IDs - Must match server
// =============================================================================

#macro CMD_PING 1
#macro CMD_PONG 2
#macro CMD_AUTH 3
#macro CMD_AUTH_OK 4
#macro CMD_AUTH_FAIL 5
#macro CMD_CREATE_LOBBY 6
#macro CMD_CREATE_OK 7
#macro CMD_CREATE_FAIL 8
#macro CMD_LIST_LOBBIES 9
#macro CMD_LOBBY_LIST 10
#macro CMD_JOIN_LOBBY 11
#macro CMD_JOIN_OK 12
#macro CMD_JOIN_FAIL 13
#macro CMD_START_GAME 14
#macro CMD_GAME_STARTED 15
#macro CMD_START_FAIL 16
#macro CMD_LEAVE_LOBBY 17
#macro CMD_LEAVE_OK 18
#macro CMD_LEAVE_FAIL 19
#macro CMD_PLAYER_JOINED 20
#macro CMD_PLAYER_LEFT 21
#macro CMD_LOBBY_CLOSED 22
#macro CMD_RELAY 23
#macro CMD_ERROR 24
#macro CMD_DEPLOY 25

// =============================================================================
// UNIFIED STATE (tracks which mode is active)
// =============================================================================

/// @function net_get_mode()
/// @returns {real} Current NET_MODE value
function net_get_mode() {
	if (!variable_global_exists("net_mode")) return NET_MODE.NONE;
	return global.net_mode;
}

// =============================================================================
// RELAY MODE - SETUP
// =============================================================================

/// @function relay_init(server_ip, server_port)
/// @param {string} server_ip - Server IP address
/// @param {string} server_port - Server port
/// @returns {bool} Success
function relay_init(_server_ip = "212.227.27.161", _server_port = 5555) {
	global.relay_socket = network_create_socket(network_socket_tcp);
	
	if (global.relay_socket < 0) {
		show_debug_message("RELAY: Failed to create TCP socket");
		return false;
	}
	
	global.net_mode = NET_MODE.RELAY;
	global.relay_server_ip = _server_ip;
	global.relay_server_port = _server_port;
	global.relay_connected = false;
	global.relay_authenticated = false;
	global.relay_in_lobby = false;
	global.relay_game_started = false;
	global.relay_lobby_id = -1;
	global.relay_nickname = "";
	global.relay_players = [];
	
	// Receive buffer for incomplete messages
	global.relay_receive_buffer = buffer_create(4096, buffer_grow, 1);
	global.relay_receive_used = 0;
	
	// Ping tracking
	global.relay_ping = -1;
	global.relay_ping_sent_time = 0;
	global.relay_ping_waiting = false;
	
	show_debug_message("RELAY: Initialized");
	return true;
}

/// @function relay_connect()
/// @returns {bool} Whether connection attempt started successfully
function relay_connect() {
	var _result = network_connect_raw_async(
		global.relay_socket,
		global.relay_server_ip,
		global.relay_server_port
	);
	
	if (_result < 0) {
		show_debug_message("RELAY: Connection failed to start");
		return false;
	}
	
	show_debug_message("RELAY: Connection attempt started to " + global.relay_server_ip + ":" + string(global.relay_server_port));
	return true;
}

/// @function relay_destroy()
/// Call on game end to clean up
function relay_destroy() {
	if (variable_global_exists("relay_socket") && global.relay_socket >= 0) {
		network_destroy(global.relay_socket);
		global.relay_socket = -1;
	}
	if (variable_global_exists("relay_receive_buffer")) {
		buffer_delete(global.relay_receive_buffer);
	}
	global.relay_connected = false;
	global.net_mode = NET_MODE.NONE;
}

// =============================================================================
// BINARY PROTOCOL HELPERS (shared by relay and direct)
// =============================================================================

/// @function _relay_write_string(buffer, str)
/// @param {buffer} buffer - Buffer to write to
/// @param {string} str - String to write
/// @description Writes a length-prefixed string (4 bytes length + UTF-8 data)
function _relay_write_string(_buffer, _str) {
	var _bytes = string_byte_length(_str);
	buffer_write(_buffer, buffer_u32, _bytes);
	if (_bytes > 0) {
		buffer_write(_buffer, buffer_text, _str);
	}
}

/// @function _relay_read_string(buffer)
/// @param {buffer} buffer - Buffer to read from (at current position)
/// @returns {string} The read string
function _relay_read_string(_buffer) {
	var _length = buffer_read(_buffer, buffer_u32);
	if (_length > 0) {
		// Read exact bytes instead of relying on null terminator
		var _str = "";
		for (var i = 0; i < _length; i++) {
			_str += chr(buffer_read(_buffer, buffer_u8));
		}
		return _str;
	}
	return "";
}

/// @function _relay_send_message(command_id, [data_buffer])
/// @param {real} command_id - Command ID constant
/// @param {buffer} data_buffer - Optional buffer containing message data
/// @description Sends a binary message: [4 bytes length][4 bytes command][data]
function _relay_send_message(_command_id, _data_buffer = undefined) {
	if (!global.relay_connected) {
		show_debug_message("RELAY: Cannot send - not connected");
		return;
	}
	
	var _data_size = (_data_buffer != undefined) ? buffer_get_size(_data_buffer) : 0;
	var _total_size = 8 + _data_size; // 4 bytes length + 4 bytes command + data
	
	var _msg_buffer = buffer_create(_total_size, buffer_fixed, 1);
	buffer_write(_msg_buffer, buffer_u32, _total_size);
	buffer_write(_msg_buffer, buffer_u32, _command_id);
	
	if (_data_buffer != undefined && _data_size > 0) {
		buffer_copy(_data_buffer, 0, _data_size, _msg_buffer, 8);
	}
	
	network_send_raw(global.relay_socket, _msg_buffer, _total_size);
	buffer_delete(_msg_buffer);
	
	//show_debug_message("RELAY TX: CMD=" + string(_command_id) + " Size=" + string(_total_size));
}

/// @function _relay_send_with_string(command_id, str)
/// @param {real} command_id - Command ID
/// @param {string} str - String to send
function _relay_send_with_string(_command_id, _str) {
	var _data = buffer_create(1024, buffer_grow, 1);
	_relay_write_string(_data, _str);
	_relay_send_message(_command_id, _data);
	buffer_delete(_data);
}

/// @function _relay_send_with_long(command_id, value)
/// @param {real} command_id - Command ID
/// @param {real} value - 32-bit integer value
function _relay_send_with_long(_command_id, _value) {
	var _data = buffer_create(4, buffer_fixed, 1);
	buffer_write(_data, buffer_u32, _value);
	_relay_send_message(_command_id, _data);
	buffer_delete(_data);
}

// =============================================================================
// RELAY MODE - API Commands
// =============================================================================

/// @function relay_auth(passcode, nickname)
/// @param {string} passcode - Server passcode
/// @param {string} nickname - Your display name
function relay_auth(_passcode, _nickname) {
	global.relay_nickname = _nickname;
	
	var _data = buffer_create(1024, buffer_grow, 1);
	_relay_write_string(_data, _passcode);
	_relay_write_string(_data, _nickname);
	_relay_send_message(CMD_AUTH, _data);
	buffer_delete(_data);
}

/// @function relay_create_lobby(lobby_name)
/// @param {string} lobby_name - Name for the new lobby
function relay_create_lobby(_lobby_name) {
	_relay_send_with_string(CMD_CREATE_LOBBY, _lobby_name);
}

/// @function relay_list_lobbies()
/// Request list of available lobbies
function relay_list_lobbies() {
	_relay_send_message(CMD_LIST_LOBBIES);
}

/// @function relay_join_lobby(lobby_id)
/// @param {real} lobby_id - ID of lobby to join
function relay_join_lobby(_lobby_id) {
	_relay_send_with_long(CMD_JOIN_LOBBY, _lobby_id);
}

/// @function relay_start_game()
/// Start the game (lobby creator only)
function relay_start_game() {
	_relay_send_message(CMD_START_GAME);
}

/// @function relay_leave_lobby()
/// Leave current lobby
function relay_leave_lobby() {
	_relay_send_message(CMD_LEAVE_LOBBY);
}

/// @function relay_send(buffer, [type_id])
/// @param {buffer} buffer - Buffer containing data to relay
/// @param {real} type_id - Payload type ID (default: 0)
/// @description Sends arbitrary binary data to other players in lobby with a type ID
function relay_send(_buffer, _type_id = 0) {
	var _size = buffer_tell(_buffer);
	if (_size > 0) {
		// Create new buffer with type ID + user data
		var _msg_buffer = buffer_create(_size + 2, buffer_fixed, 1);
		buffer_write(_msg_buffer, buffer_u16, _type_id);
		buffer_copy(_buffer, 0, _size, _msg_buffer, 2);
		
		_relay_send_message(CMD_RELAY, _msg_buffer);
		buffer_delete(_msg_buffer);
	}
}

/// @function relay_ping()
/// Send a ping to measure latency
function relay_ping() {
	global.relay_ping_sent_time = get_timer();
	global.relay_ping_waiting = true;
	
	var _data = buffer_create(8, buffer_fixed, 1);
	buffer_write(_data, buffer_u64, global.relay_ping_sent_time);
	_relay_send_message(CMD_PING, _data);
	buffer_delete(_data);
}

/// @function relay_send_string(message, [type_id])
/// @param {string} message - String message to send
/// @param {real} type_id - Payload type ID (default: 0)
function relay_send_string(_message, _type_id = 0) {
    var _buffer = buffer_create(256, buffer_grow, 1);
    buffer_write(_buffer, buffer_string, _message);
    relay_send(_buffer, _type_id);
    buffer_delete(_buffer);
}

// =============================================================================
// RELAY MODE - NETWORKING EVENT
// =============================================================================

/// @function relay_async_network()
/// Call this from the Async - Networking event
/// @returns {array} Array of event structs (can be multiple due to TCP buffering)
function relay_async_network() {
	var _type = async_load[? "type"];
	var _socket = async_load[? "id"];
	
	if (_socket != global.relay_socket) {
		return [];
	}
	
	var _events = [];
	
	switch (_type) {
		case network_type_non_blocking_connect:
			var _succeeded = async_load[? "succeeded"];
			if (_succeeded) {
				global.relay_connected = true;
				show_debug_message("RELAY: Connected to server");
				array_push(_events, {
					type: "CONNECTED",
					command_id: -1,
					success: true,
					data: undefined
				});
			} else {
				show_debug_message("RELAY: Connection failed");
				array_push(_events, {
					type: "CONNECT_FAILED",
					command_id: -1,
					success: false,
					data: "Connection timed out"
				});
			}
			break;
			
		case network_type_disconnect:
			global.relay_connected = false;
			global.relay_authenticated = false;
			global.relay_in_lobby = false;
			global.relay_game_started = false;
			show_debug_message("RELAY: Disconnected from server");
			array_push(_events, {
				type: "DISCONNECTED",
				command_id: -1,
				success: true,
				data: undefined
			});
			break;
			
		case network_type_data:
			var _buffer = async_load[? "buffer"];
			var _size = async_load[? "size"];
			
			// Append received data to our buffer
			buffer_copy(_buffer, 0, _size, global.relay_receive_buffer, global.relay_receive_used);
			global.relay_receive_used += _size;
			
			// Process complete messages
			var _offset = 0;
			
			while (_offset + 8 <= global.relay_receive_used) {
				// Read message length
				buffer_seek(global.relay_receive_buffer, buffer_seek_start, _offset);
				var _msg_length = buffer_read(global.relay_receive_buffer, buffer_u32);
				
				// Validate
				if (_msg_length < 8 || _msg_length > 65536) {
					show_debug_message("RELAY ERROR: Invalid message length: " + string(_msg_length));
					global.relay_receive_used = 0;
					break;
				}
				
				// Check if complete message is available
				if (_offset + _msg_length > global.relay_receive_used) {
					break; // Wait for more data
				}
				
				// Read command ID
				var _command_id = buffer_read(global.relay_receive_buffer, buffer_u32);
				
				// Extract message data
				var _data_size = _msg_length - 8;
				var _msg_data = undefined;
				
				if (_data_size > 0) {
					_msg_data = buffer_create(_data_size, buffer_fixed, 1);
					buffer_copy(global.relay_receive_buffer, _offset + 8, _data_size, _msg_data, 0);
				}
				
				// Parse this message
				var _event = _relay_parse_message(_command_id, _msg_data);
				if (_event != undefined) {
					array_push(_events, _event);
				}
				
				// Clean up message data buffer
				if (_msg_data != undefined) {
					buffer_delete(_msg_data);
				}
				
				_offset += _msg_length;
			}
			
			// Remove processed data from buffer
			if (_offset > 0) {
				if (_offset < global.relay_receive_used) {
					var _remaining = global.relay_receive_used - _offset;
					var _temp = buffer_create(_remaining, buffer_fixed, 1);
					buffer_copy(global.relay_receive_buffer, _offset, _remaining, _temp, 0);
					buffer_copy(_temp, 0, _remaining, global.relay_receive_buffer, 0);
					buffer_delete(_temp);
					global.relay_receive_used = _remaining;
				} else {
					global.relay_receive_used = 0;
				}
			}
			break;
	}
	
	return _events;
}

/// @function _relay_parse_message(command_id, data_buffer)
/// @param {real} command_id - Command ID from message
/// @param {buffer} data_buffer - Message data buffer (or undefined if no data)
/// @returns {struct} Parsed event
function _relay_parse_message(_command_id, _data_buffer) {
	//show_debug_message("RELAY RX: CMD=" + string(_command_id));
	
	var _event = {
		type: "UNKNOWN",
		command_id: _command_id,
		success: false,
		data: undefined
	};
	
	// Position buffer at start for reading
	if (_data_buffer != undefined) {
		buffer_seek(_data_buffer, buffer_seek_start, 0);
	}
	
	switch (_command_id) 
	{
		case CMD_AUTH_OK:
			_event.type = "AUTH_OK";
			global.relay_authenticated = true;
			_event.success = true;
			break;
			
		case CMD_AUTH_FAIL:
			_event.type = "AUTH_FAIL";
			global.relay_authenticated = false;
			_event.success = false;
			if (_data_buffer != undefined) {
				_event.data = _relay_read_string(_data_buffer);
			}
			break;
			
		case CMD_CREATE_OK:
			_event.type = "CREATE_OK";
			global.relay_in_lobby = true;
			if (_data_buffer != undefined) {
				global.relay_lobby_id = buffer_read(_data_buffer, buffer_u32);
			}
			global.relay_players = [global.relay_nickname];
			_event.success = true;
			_event.data = global.relay_lobby_id;
			break;
			
		case CMD_CREATE_FAIL:
			_event.type = "CREATE_FAIL";
			_event.success = false;
			if (_data_buffer != undefined) {
				_event.data = _relay_read_string(_data_buffer);
			}
			break;
			
		case CMD_LOBBY_LIST:
		    _event.type = "LOBBY_LIST";
		    _event.success = true;
		    var _lobbies = [];
    
		    if (_data_buffer != undefined) {
		        var _count = buffer_read(_data_buffer, buffer_u32);
		        for (var i = 0; i < _count; i++) {
		            var _id = buffer_read(_data_buffer, buffer_u32);
		            var _name = _relay_read_string(_data_buffer);
		            var _players = buffer_read(_data_buffer, buffer_u32);
		            var _max = buffer_read(_data_buffer, buffer_u32);
		            var _creator = _relay_read_string(_data_buffer);
            
		            var _lobby = {
		                id: _id,
		                name: _name,
		                players: _players,
		                max_players: _max,
		                creator: _creator
		            };
		            array_push(_lobbies, _lobby);
		        }
		    }
    
		    _event.data = _lobbies;
		    break;
			
		case CMD_JOIN_OK:
			_event.type = "JOIN_OK";
			global.relay_in_lobby = true;
			_event.success = true;
			
			if (_data_buffer != undefined) {
				var _player_count = buffer_read(_data_buffer, buffer_u32);
				global.relay_players = [];
				
				for (var i = 0; i < _player_count; i++) {
					array_push(global.relay_players, _relay_read_string(_data_buffer));
				}
			}
			
			_event.data = global.relay_players;
			break;
			
		case CMD_JOIN_FAIL:
			_event.type = "JOIN_FAIL";
			_event.success = false;
			if (_data_buffer != undefined) {
				_event.data = _relay_read_string(_data_buffer);
			}
			break;
			
		case CMD_START_FAIL:
			_event.type = "START_FAIL";
			_event.success = false;
			if (_data_buffer != undefined) {
				_event.data = _relay_read_string(_data_buffer);
			}
			break;
			
		case CMD_LEAVE_OK:
			_event.type = "LEAVE_OK";
			global.relay_in_lobby = false;
			global.relay_game_started = false;
			global.relay_lobby_id = -1;
			global.relay_players = [];
			_event.success = true;
			break;
			
		case CMD_LEAVE_FAIL:
			_event.type = "LEAVE_FAIL";
			_event.success = false;
			if (_data_buffer != undefined) {
				_event.data = _relay_read_string(_data_buffer);
			}
			break;
			
		case CMD_PLAYER_JOINED:
			_event.type = "PLAYER_JOINED";
			if (_data_buffer != undefined) {
				var _nickname = _relay_read_string(_data_buffer);
				array_push(global.relay_players, _nickname);
				_event.data = _nickname;
			}
			_event.success = true;
			break;
			
		case CMD_PLAYER_LEFT:
			_event.type = "PLAYER_LEFT";
			if (_data_buffer != undefined) {
				var _nickname = _relay_read_string(_data_buffer);
				var _idx = array_get_index(global.relay_players, _nickname);
				if (_idx >= 0) {
					array_delete(global.relay_players, _idx, 1);
				}
				_event.data = _nickname;
			}
			_event.success = true;
			break;
			
		case CMD_GAME_STARTED:
			_event.type = "GAME_STARTED";
			global.relay_game_started = true;
			_event.success = true;
			break;
			
		case CMD_LOBBY_CLOSED:
			_event.type = "LOBBY_CLOSED";
			global.relay_in_lobby = false;
			global.relay_game_started = false;
			global.relay_lobby_id = -1;
			global.relay_players = [];
			_event.success = true;
			if (_data_buffer != undefined) {
				_event.data = _relay_read_string(_data_buffer);
			}
			break;
			
		case CMD_RELAY:
		    _event.type = "RELAY";
		    _event.success = true;
		    if (_data_buffer != undefined) {
		        var _sender = _relay_read_string(_data_buffer);
        
		        // Remaining data starts with 2-byte type ID, then payload
		        var _remaining_size = buffer_get_size(_data_buffer) - buffer_tell(_data_buffer);
		        var _payload_type_id = -1;
		        var _payload = undefined;
        
		        if (_remaining_size >= 2) {
					_payload_type_id = buffer_read(_data_buffer, buffer_u16);
					
					// Rest is the actual payload
					var _payload_size = buffer_get_size(_data_buffer) - buffer_tell(_data_buffer);
					if (_payload_size > 0) {
						_payload = buffer_create(_payload_size, buffer_fixed, 1);
						buffer_copy(_data_buffer, buffer_tell(_data_buffer), _payload_size, _payload, 0);
						buffer_seek(_payload, buffer_seek_start, 0);
					}
		        }
        
		        _event.data = {
					sender: _sender,
					payload_type_id: _payload_type_id,
					payload: _payload
		        };
		    }
		    break;
			
		case CMD_PONG:
			_event.type = "PONG";
			if (global.relay_ping_waiting) {
				global.relay_ping = (get_timer() - global.relay_ping_sent_time)
				global.relay_ping_waiting = false;
			}
			_event.success = true;
			_event.data = global.relay_ping;
			break;
			
		case CMD_ERROR:
			_event.type = "ERROR";
			_event.success = false;
			if (_data_buffer != undefined) {
				_event.data = _relay_read_string(_data_buffer);
			}
			break;
		case CMD_DEPLOY:
			_event.type = "DEPLOY";
			_event.success = true;
			break;
		default:
			_event.type = "UNKNOWN";
			break;
	}
	
	return _event;
}

// =============================================================================
// RELAY MODE - UTILITY
// =============================================================================

/// @function relay_is_connected()
/// @returns {bool}
function relay_is_connected() {
	return global.relay_connected;
}

/// @function relay_is_authenticated()
/// @returns {bool}
function relay_is_authenticated() {
	return global.relay_authenticated;
}

/// @function relay_is_in_lobby()
/// @returns {bool}
function relay_is_in_lobby() {
	return global.relay_in_lobby;
}

/// @function relay_is_game_started()
/// @returns {bool}
function relay_is_game_started() {
	return global.relay_game_started;
}

/// @function relay_get_players()
/// @returns {array} Array of player nicknames in current lobby
function relay_get_players() {
	return global.relay_players;
}

/// @function relay_get_player_count()
/// @returns {real}
function relay_get_player_count() {
	return array_length(global.relay_players);
}

/// @function relay_get_ping()
/// @returns {real} Last measured ping in ms, or -1 if not measured
function relay_get_ping() {
	return global.relay_ping;
}

/// @function relay_get_nickname()
/// @returns {string}
function relay_get_nickname() {
	return global.relay_nickname;
}


// #############################################################################
// #############################################################################
// ##                                                                         ##
// ##   DIRECT CONNECTION MODE (Peer-to-Peer via Host)                        ##
// ##                                                                         ##
// ##   One player hosts a TCP server, others connect directly.               ##
// ##   The host acts as both player and relay between clients.               ##
// ##   Produces the same event struct format as the relay system.            ##
// ##                                                                         ##
// #############################################################################
// #############################################################################

// Direct mode uses the same binary framing as relay:
//   [4 bytes total_size][4 bytes command_id][data...]
//
// Internal commands between host and clients (reuses CMD_ constants):
//   CMD_AUTH       - Client sends nickname to host on connect
//   CMD_AUTH_OK    - Host accepts the client
//   CMD_AUTH_FAIL  - Host rejects the client (full, duplicate name, etc.)
//   CMD_PLAYER_JOINED - Host broadcasts when a new player joins
//   CMD_PLAYER_LEFT   - Host broadcasts when a player leaves
//   CMD_GAME_STARTED  - Host broadcasts game start
//   CMD_RELAY      - Data relay (host prepends sender name, forwards to others)
//   CMD_PING / CMD_PONG - Latency measurement
//   CMD_LOBBY_CLOSED   - Host is shutting down

// =============================================================================
// DIRECT MODE - SETUP
// =============================================================================

/// @function direct_init(nickname, [max_players])
/// @param {string} nickname - Your display name
/// @param {real} max_players - Maximum players allowed (default: 4)
/// @returns {bool} Success
/// @description Initializes the direct connection system. Call before host/join.
function direct_init(_nickname, _max_players = 4) {
	global.net_mode = NET_MODE.DIRECT;
	global.direct_nickname = _nickname;
	global.direct_max_players = _max_players;
	global.direct_is_host = false;
	global.direct_in_lobby = false;
	global.direct_game_started = false;
	global.direct_players = [];
	
	// Ping tracking
	global.direct_ping = -1;
	global.direct_ping_sent_time = 0;
	global.direct_ping_waiting = false;
	
	// Host-specific state (initialized in direct_host)
	global.direct_server_socket = -1;
	global.direct_clients = ds_map_create();		// socket -> { nickname, recv_buffer, recv_used }
	global.direct_client_sockets = [];				// ordered array of client sockets
	
	// Client-specific state (initialized in direct_join)
	global.direct_socket = -1;
	global.direct_connected = false;
	global.direct_authenticated = false;
	global.direct_receive_buffer = buffer_create(4096, buffer_grow, 1);
	global.direct_receive_used = 0;
	
	show_debug_message("DIRECT: Initialized as \"" + _nickname + "\" (max " + string(_max_players) + " players)");
	return true;
}

/// @function direct_host(port)
/// @param {real} port - Port to listen on
/// @returns {bool} Whether the server socket was created successfully
/// @description Start hosting. Other players connect to your IP:port.
function direct_host(_port = 5556) {
	global.direct_server_socket = network_create_server_raw(network_socket_tcp, _port, global.direct_max_players);
	
	if (global.direct_server_socket < 0) {
		show_debug_message("DIRECT HOST: Failed to create server on port " + string(_port));
		return false;
	}
	
	global.direct_is_host = true;
	global.direct_in_lobby = true;
	global.direct_players = [global.direct_nickname]; // Host is always player 0
	
	show_debug_message("DIRECT HOST: Listening on port " + string(_port));
	return true;
}

/// @function direct_join(host_ip, host_port)
/// @param {string} host_ip - IP address of the host
/// @param {real} host_port - Port of the host
/// @returns {bool} Whether the connection attempt started
/// @description Connect to a host as a client.
function direct_join(_host_ip, _host_port = 5556) {
	global.direct_socket = network_create_socket(network_socket_tcp);
	
	if (global.direct_socket < 0) {
		show_debug_message("DIRECT CLIENT: Failed to create socket");
		return false;
	}
	
	global.direct_is_host = false;
	global.direct_connected = false;
	global.direct_authenticated = false;
	
	var _result = network_connect_raw_async(global.direct_socket, _host_ip, _host_port);
	
	if (_result < 0) {
		show_debug_message("DIRECT CLIENT: Connection failed to start");
		network_destroy(global.direct_socket);
		global.direct_socket = -1;
		return false;
	}
	
	show_debug_message("DIRECT CLIENT: Connecting to " + _host_ip + ":" + string(_host_port));
	return true;
}

/// @function direct_destroy()
/// @description Clean up all direct connection resources.
function direct_destroy() {
	// Clean up host resources
	if (global.direct_server_socket >= 0) {
		// Disconnect all clients
		for (var i = 0; i < array_length(global.direct_client_sockets); i++) {
			var _sock = global.direct_client_sockets[i];
			var _client = global.direct_clients[? _sock];
			if (_client != undefined) {
				buffer_delete(_client.recv_buffer);
			}
			network_destroy(_sock);
		}
		network_destroy(global.direct_server_socket);
		global.direct_server_socket = -1;
	}
	
	ds_map_destroy(global.direct_clients);
	global.direct_client_sockets = [];
	
	// Clean up client resources
	if (global.direct_socket >= 0) {
		network_destroy(global.direct_socket);
		global.direct_socket = -1;
	}
	
	if (variable_global_exists("direct_receive_buffer")) {
		buffer_delete(global.direct_receive_buffer);
	}
	
	global.direct_connected = false;
	global.direct_authenticated = false;
	global.direct_in_lobby = false;
	global.direct_game_started = false;
	global.direct_players = [];
	global.net_mode = NET_MODE.NONE;
	
	show_debug_message("DIRECT: Destroyed");
}

// =============================================================================
// DIRECT MODE - INTERNAL SEND HELPERS
// =============================================================================

/// @function _direct_send_raw(socket, command_id, [data_buffer])
/// @description Sends a framed binary message to a specific socket.
function _direct_send_raw(_socket, _command_id, _data_buffer = undefined) {
	var _data_size = (_data_buffer != undefined) ? buffer_get_size(_data_buffer) : 0;
	var _total_size = 8 + _data_size;
	
	var _msg = buffer_create(_total_size, buffer_fixed, 1);
	buffer_write(_msg, buffer_u32, _total_size);
	buffer_write(_msg, buffer_u32, _command_id);
	
	if (_data_buffer != undefined && _data_size > 0) {
		buffer_copy(_data_buffer, 0, _data_size, _msg, 8);
	}
	
	network_send_raw(_socket, _msg, _total_size);
	buffer_delete(_msg);
}

/// @function _direct_send_string_msg(socket, command_id, str)
/// @description Sends a command with a single string payload to a specific socket.
function _direct_send_string_msg(_socket, _command_id, _str) {
	var _data = buffer_create(256, buffer_grow, 1);
	_relay_write_string(_data, _str);
	_direct_send_raw(_socket, _command_id, _data);
	buffer_delete(_data);
}

/// @function _direct_broadcast(command_id, [data_buffer], [exclude_socket])
/// @description Host broadcasts a message to all connected clients.
function _direct_broadcast(_command_id, _data_buffer = undefined, _exclude_socket = -1) {
	for (var i = 0; i < array_length(global.direct_client_sockets); i++) {
		var _sock = global.direct_client_sockets[i];
		if (_sock != _exclude_socket) {
			_direct_send_raw(_sock, _command_id, _data_buffer);
		}
	}
}

// =============================================================================
// DIRECT MODE - API Commands
// =============================================================================

/// @function direct_send(buffer, [type_id])
/// @param {buffer} buffer - Buffer containing data to send
/// @param {real} type_id - Payload type ID (default: 0)
/// @description Sends data to all other players. Same interface as relay_send().
function direct_send(_buffer, _type_id = 0) {
	var _size = buffer_tell(_buffer);
	if (_size <= 0) return;
	
	if (global.direct_is_host) {
		// Host: build relay message with own name as sender and deliver to all clients
		var _relay_data = buffer_create(256 + _size, buffer_grow, 1);
		_relay_write_string(_relay_data, global.direct_nickname);
		buffer_write(_relay_data, buffer_u16, _type_id);
		buffer_copy(_buffer, 0, _size, _relay_data, buffer_tell(_relay_data));
		
		// Resize to actual content
		var _final_size = buffer_tell(_relay_data) + _size;
		_direct_broadcast(CMD_RELAY, _relay_data);
		buffer_delete(_relay_data);
	} else {
		// Client: send to host with type ID prefix; host will relay to others
		var _msg = buffer_create(_size + 2, buffer_fixed, 1);
		buffer_write(_msg, buffer_u16, _type_id);
		buffer_copy(_buffer, 0, _size, _msg, 2);
		
		_direct_send_raw(global.direct_socket, CMD_RELAY, _msg);
		buffer_delete(_msg);
	}
}

/// @function direct_send_string(message, [type_id])
/// @param {string} message - String message to send
/// @param {real} type_id - Payload type ID (default: 0)
function direct_send_string(_message, _type_id = 0) {
	var _buffer = buffer_create(256, buffer_grow, 1);
	buffer_write(_buffer, buffer_string, _message);
	direct_send(_buffer, _type_id);
	buffer_delete(_buffer);
}

/// @function direct_start_game()
/// @description Host starts the game. Broadcasts GAME_STARTED to all clients.
function direct_start_game() {
	if (!global.direct_is_host) {
		show_debug_message("DIRECT: Only the host can start the game");
		return;
	}
	
	if (array_length(global.direct_players) < 2) {
		show_debug_message("DIRECT: Need at least 2 players to start");
		return;
	}
	
	global.direct_game_started = true;
	_direct_broadcast(CMD_GAME_STARTED);
	show_debug_message("DIRECT HOST: Game started");
}

/// @function direct_leave()
/// @description Leave the session. If host, closes everything. If client, disconnects.
function direct_leave() {
	if (global.direct_is_host) {
		// Notify all clients the lobby is closing
		var _data = buffer_create(256, buffer_grow, 1);
		_relay_write_string(_data, "Host closed the lobby");
		_direct_broadcast(CMD_LOBBY_CLOSED, _data);
		buffer_delete(_data);
		
		// Clean up all client connections
		for (var i = 0; i < array_length(global.direct_client_sockets); i++) {
			var _sock = global.direct_client_sockets[i];
			var _client = global.direct_clients[? _sock];
			if (_client != undefined) {
				buffer_delete(_client.recv_buffer);
			}
			ds_map_delete(global.direct_clients, _sock);
			network_destroy(_sock);
		}
		global.direct_client_sockets = [];
		
		network_destroy(global.direct_server_socket);
		global.direct_server_socket = -1;
		
		global.direct_in_lobby = false;
		global.direct_game_started = false;
		global.direct_players = [];
		
		show_debug_message("DIRECT HOST: Lobby closed");
	} else {
		// Client: just disconnect
		if (global.direct_socket >= 0) {
			network_destroy(global.direct_socket);
			global.direct_socket = -1;
		}
		global.direct_connected = false;
		global.direct_authenticated = false;
		global.direct_in_lobby = false;
		global.direct_game_started = false;
		global.direct_players = [];
		
		show_debug_message("DIRECT CLIENT: Left lobby");
	}
}

/// @function direct_kick(nickname)
/// @param {string} nickname - Nickname of the player to kick
/// @description Host-only: kick a player from the session.
function direct_kick(_nickname) {
	if (!global.direct_is_host) return;
	if (_nickname == global.direct_nickname) return; // Can't kick yourself
	
	// Find the client socket for this nickname
	for (var i = 0; i < array_length(global.direct_client_sockets); i++) {
		var _sock = global.direct_client_sockets[i];
		var _client = global.direct_clients[? _sock];
		if (_client != undefined && _client.nickname == _nickname) {
			// Send lobby closed to the kicked player
			var _data = buffer_create(256, buffer_grow, 1);
			_relay_write_string(_data, "Kicked by host");
			_direct_send_raw(_sock, CMD_LOBBY_CLOSED, _data);
			buffer_delete(_data);
			
			// Remove and disconnect
			_direct_host_remove_client(_sock, _nickname);
			return;
		}
	}
}

/// @function direct_ping()
/// @description Send a ping to measure latency (client pings host, host pings first client).
function direct_ping() {
	global.direct_ping_sent_time = get_timer();
	global.direct_ping_waiting = true;
	
	var _data = buffer_create(8, buffer_fixed, 1);
	buffer_write(_data, buffer_u64, global.direct_ping_sent_time);
	
	if (global.direct_is_host) {
		// Host pings first connected client (for diagnostics)
		if (array_length(global.direct_client_sockets) > 0) {
			_direct_send_raw(global.direct_client_sockets[0], CMD_PING, _data);
		}
	} else {
		_direct_send_raw(global.direct_socket, CMD_PING, _data);
	}
	
	buffer_delete(_data);
}

// =============================================================================
// DIRECT MODE - HOST: Client Management
// =============================================================================

/// @function _direct_host_remove_client(socket, nickname)
/// @description Removes a client, cleans up, and broadcasts PLAYER_LEFT.
function _direct_host_remove_client(_socket, _nickname) {
	// Clean up client data
	var _client = global.direct_clients[? _socket];
	if (_client != undefined) {
		buffer_delete(_client.recv_buffer);
	}
	ds_map_delete(global.direct_clients, _socket);
	
	// Remove from socket list
	var _idx = array_get_index(global.direct_client_sockets, _socket);
	if (_idx >= 0) {
		array_delete(global.direct_client_sockets, _idx, 1);
	}
	
	// Remove from player list
	var _pidx = array_get_index(global.direct_players, _nickname);
	if (_pidx >= 0) {
		array_delete(global.direct_players, _pidx, 1);
	}
	
	network_destroy(_socket);
	
	// Broadcast player left to remaining clients
	var _data = buffer_create(256, buffer_grow, 1);
	_relay_write_string(_data, _nickname);
	_direct_broadcast(CMD_PLAYER_LEFT, _data);
	buffer_delete(_data);
	
	show_debug_message("DIRECT HOST: Player \"" + _nickname + "\" removed");
}

// =============================================================================
// DIRECT MODE - NETWORKING EVENT
// =============================================================================

/// @function direct_async_network()
/// @description Call from Async - Networking event. Returns array of event structs
///              with the same format as relay_async_network().
/// @returns {array} Array of event structs
function direct_async_network() {
	var _type = async_load[? "type"];
	var _socket = async_load[? "id"];
	
	if (global.direct_is_host) {
		return _direct_host_async(_type, _socket);
	} else {
		return _direct_client_async(_type, _socket);
	}
}

// =============================================================================
// DIRECT MODE - HOST ASYNC HANDLER
// =============================================================================

/// @function _direct_host_async(type, socket)
function _direct_host_async(_type, _socket) {
	var _events = [];
	
	switch (_type) {
		case network_type_connect:
			// For network_type_connect on a TCP server:
			//   async_load[? "id"]     = server socket (the listener)
			//   async_load[? "socket"] = new client socket
			var _client_socket = async_load[? "socket"];
			
			// A new client is attempting to connect
			if (array_length(global.direct_players) >= global.direct_max_players) {
				// Reject: lobby full
				_direct_send_string_msg(_client_socket, CMD_AUTH_FAIL, "Lobby is full");
				network_destroy(_client_socket);
				show_debug_message("DIRECT HOST: Rejected connection (lobby full)");
			} else {
				// Accept the socket, wait for their AUTH message with nickname
				var _client = {
					nickname: "",
					authenticated: false,
					recv_buffer: buffer_create(4096, buffer_grow, 1),
					recv_used: 0
				};
				global.direct_clients[? _client_socket] = _client;
				array_push(global.direct_client_sockets, _client_socket);
				show_debug_message("DIRECT HOST: New connection from socket " + string(_client_socket));
			}
			break;
			
		case network_type_disconnect:
			var _client = global.direct_clients[? _socket];
			if (_client != undefined) {
				var _nick = _client.nickname;
				if (_nick != "") {
					_direct_host_remove_client(_socket, _nick);
					array_push(_events, {
						type: "PLAYER_LEFT",
						command_id: CMD_PLAYER_LEFT,
						success: true,
						data: _nick
					});
				} else {
					// Unauthenticated client disconnected, just clean up
					buffer_delete(_client.recv_buffer);
					ds_map_delete(global.direct_clients, _socket);
					var _idx = array_get_index(global.direct_client_sockets, _socket);
					if (_idx >= 0) array_delete(global.direct_client_sockets, _idx, 1);
					network_destroy(_socket);
				}
			}
			break;
			
		case network_type_data:
			var _client = global.direct_clients[? _socket];
			if (_client == undefined) break;
			
			var _buffer = async_load[? "buffer"];
			var _size = async_load[? "size"];
			
			// Append to client's receive buffer
			buffer_copy(_buffer, 0, _size, _client.recv_buffer, _client.recv_used);
			_client.recv_used += _size;
			
			// Process complete messages
			var _offset = 0;
			
			while (_offset + 8 <= _client.recv_used) {
				buffer_seek(_client.recv_buffer, buffer_seek_start, _offset);
				var _msg_length = buffer_read(_client.recv_buffer, buffer_u32);
				
				if (_msg_length < 8 || _msg_length > 65536) {
					show_debug_message("DIRECT HOST: Invalid message length from " + _client.nickname);
					_client.recv_used = 0;
					break;
				}
				
				if (_offset + _msg_length > _client.recv_used) break;
				
				var _command_id = buffer_read(_client.recv_buffer, buffer_u32);
				var _data_size = _msg_length - 8;
				var _msg_data = undefined;
				
				if (_data_size > 0) {
					_msg_data = buffer_create(_data_size, buffer_fixed, 1);
					buffer_copy(_client.recv_buffer, _offset + 8, _data_size, _msg_data, 0);
				}
				
				// Process the command
				var _cmd_events = _direct_host_process_command(_socket, _client, _command_id, _msg_data);
				for (var i = 0; i < array_length(_cmd_events); i++) {
					array_push(_events, _cmd_events[i]);
				}
				
				if (_msg_data != undefined) buffer_delete(_msg_data);
				_offset += _msg_length;
			}
			
			// Compact the receive buffer
			if (_offset > 0) {
				if (_offset < _client.recv_used) {
					var _remaining = _client.recv_used - _offset;
					var _temp = buffer_create(_remaining, buffer_fixed, 1);
					buffer_copy(_client.recv_buffer, _offset, _remaining, _temp, 0);
					buffer_copy(_temp, 0, _remaining, _client.recv_buffer, 0);
					buffer_delete(_temp);
					_client.recv_used = _remaining;
				} else {
					_client.recv_used = 0;
				}
			}
			break;
	}
	
	return _events;
}

/// @function _direct_host_process_command(socket, client, command_id, data_buffer)
/// @description Host processes a command received from a client.
/// @returns {array} Events to surface to the game
function _direct_host_process_command(_socket, _client, _command_id, _data_buffer) {
	var _events = [];
	
	if (_data_buffer != undefined) {
		buffer_seek(_data_buffer, buffer_seek_start, 0);
	}
	
	switch (_command_id) {
		case CMD_AUTH:
			// Client is sending their nickname
			if (_data_buffer != undefined) {
				var _nickname = _relay_read_string(_data_buffer);
				
				// Check for duplicate nicknames
				var _duplicate = false;
				for (var i = 0; i < array_length(global.direct_players); i++) {
					if (global.direct_players[i] == _nickname) {
						_duplicate = true;
						break;
					}
				}
				
				if (_duplicate) {
					_direct_send_string_msg(_socket, CMD_AUTH_FAIL, "Nickname already taken");
					show_debug_message("DIRECT HOST: Rejected \"" + _nickname + "\" (duplicate name)");
				} else if (array_length(global.direct_players) >= global.direct_max_players) {
					_direct_send_string_msg(_socket, CMD_AUTH_FAIL, "Lobby is full");
					show_debug_message("DIRECT HOST: Rejected \"" + _nickname + "\" (full)");
				} else {
					_client.nickname = _nickname;
					_client.authenticated = true;
					
					// Send AUTH_OK (no extra data needed)
					_direct_send_raw(_socket, CMD_AUTH_OK);
					
					// Send current player list as JOIN_OK to the new client
					// This tells them who is already in the lobby
					array_push(global.direct_players, _nickname);
					
					var _list_data = buffer_create(512, buffer_grow, 1);
					buffer_write(_list_data, buffer_u32, array_length(global.direct_players));
					for (var i = 0; i < array_length(global.direct_players); i++) {
						_relay_write_string(_list_data, global.direct_players[i]);
					}
					_direct_send_raw(_socket, CMD_JOIN_OK, _list_data);
					buffer_delete(_list_data);
					
					// Broadcast PLAYER_JOINED to all other clients
					var _join_data = buffer_create(256, buffer_grow, 1);
					_relay_write_string(_join_data, _nickname);
					_direct_broadcast(CMD_PLAYER_JOINED, _join_data, _socket);
					buffer_delete(_join_data);
					
					show_debug_message("DIRECT HOST: Player \"" + _nickname + "\" joined");
					
					// Surface event to host's game code
					array_push(_events, {
						type: "PLAYER_JOINED",
						command_id: CMD_PLAYER_JOINED,
						success: true,
						data: _nickname
					});
				}
			}
			break;
			
		case CMD_RELAY:
			// Client is sending data to relay to everyone else
			if (_data_buffer != undefined && _client.authenticated) {
				var _data_size = buffer_get_size(_data_buffer);
				
				// Build relay message with sender's name prepended
				var _relay_msg = buffer_create(256 + _data_size, buffer_grow, 1);
				_relay_write_string(_relay_msg, _client.nickname);
				buffer_copy(_data_buffer, 0, _data_size, _relay_msg, buffer_tell(_relay_msg));
				
				var _relay_size = buffer_tell(_relay_msg) + _data_size;
				
				// Send to all OTHER clients
				_direct_broadcast(CMD_RELAY, _relay_msg, _socket);
				
				// Also surface as a RELAY event to the host's game code
				// Parse the payload for the host
				buffer_seek(_data_buffer, buffer_seek_start, 0);
				var _payload_type_id = -1;
				var _payload = undefined;
				
				if (_data_size >= 2) {
					_payload_type_id = buffer_read(_data_buffer, buffer_u16);
					var _payload_size = _data_size - 2;
					if (_payload_size > 0) {
						_payload = buffer_create(_payload_size, buffer_fixed, 1);
						buffer_copy(_data_buffer, 2, _payload_size, _payload, 0);
						buffer_seek(_payload, buffer_seek_start, 0);
					}
				}
				
				array_push(_events, {
					type: "RELAY",
					command_id: CMD_RELAY,
					success: true,
					data: {
						sender: _client.nickname,
						payload_type_id: _payload_type_id,
						payload: _payload
					}
				});
				
				buffer_delete(_relay_msg);
			}
			break;
			
		case CMD_PING:
			// Client pinging host: respond with PONG
			_direct_send_raw(_socket, CMD_PONG, _data_buffer);
			break;
			
		case CMD_PONG:
			// Response to host's ping
			if (global.direct_ping_waiting) {
				global.direct_ping = (get_timer() - global.direct_ping_sent_time);
				global.direct_ping_waiting = false;
			}
			array_push(_events, {
				type: "PONG",
				command_id: CMD_PONG,
				success: true,
				data: global.direct_ping
			});
			break;
			
		default:
			show_debug_message("DIRECT HOST: Unknown command " + string(_command_id) + " from " + _client.nickname);
			break;
	}
	
	return _events;
}

// =============================================================================
// DIRECT MODE - CLIENT ASYNC HANDLER
// =============================================================================

/// @function _direct_client_async(type, socket)
function _direct_client_async(_type, _socket) {
	var _events = [];
	
	// Only handle our own socket
	if (_socket != global.direct_socket) return _events;
	
	switch (_type) {
		case network_type_non_blocking_connect:
			var _succeeded = async_load[? "succeeded"];
			if (_succeeded) {
				global.direct_connected = true;
				show_debug_message("DIRECT CLIENT: Connected to host");
				
				// Immediately send AUTH with our nickname
				var _data = buffer_create(256, buffer_grow, 1);
				_relay_write_string(_data, global.direct_nickname);
				_direct_send_raw(global.direct_socket, CMD_AUTH, _data);
				buffer_delete(_data);
				
				array_push(_events, {
					type: "CONNECTED",
					command_id: -1,
					success: true,
					data: undefined
				});
			} else {
				show_debug_message("DIRECT CLIENT: Connection failed");
				array_push(_events, {
					type: "CONNECT_FAILED",
					command_id: -1,
					success: false,
					data: "Connection timed out"
				});
			}
			break;
			
		case network_type_disconnect:
			global.direct_connected = false;
			global.direct_authenticated = false;
			global.direct_in_lobby = false;
			global.direct_game_started = false;
			global.direct_players = [];
			show_debug_message("DIRECT CLIENT: Disconnected from host");
			array_push(_events, {
				type: "DISCONNECTED",
				command_id: -1,
				success: true,
				data: undefined
			});
			break;
			
		case network_type_data:
			var _buffer = async_load[? "buffer"];
			var _size = async_load[? "size"];
			
			buffer_copy(_buffer, 0, _size, global.direct_receive_buffer, global.direct_receive_used);
			global.direct_receive_used += _size;
			
			// Process complete messages
			var _offset = 0;
			
			while (_offset + 8 <= global.direct_receive_used) {
				buffer_seek(global.direct_receive_buffer, buffer_seek_start, _offset);
				var _msg_length = buffer_read(global.direct_receive_buffer, buffer_u32);
				
				if (_msg_length < 8 || _msg_length > 65536) {
					show_debug_message("DIRECT CLIENT: Invalid message length: " + string(_msg_length));
					global.direct_receive_used = 0;
					break;
				}
				
				if (_offset + _msg_length > global.direct_receive_used) break;
				
				var _command_id = buffer_read(global.direct_receive_buffer, buffer_u32);
				var _data_size = _msg_length - 8;
				var _msg_data = undefined;
				
				if (_data_size > 0) {
					_msg_data = buffer_create(_data_size, buffer_fixed, 1);
					buffer_copy(global.direct_receive_buffer, _offset + 8, _data_size, _msg_data, 0);
				}
				
				var _event = _direct_client_parse_message(_command_id, _msg_data);
				if (_event != undefined) {
					array_push(_events, _event);
				}
				
				if (_msg_data != undefined) buffer_delete(_msg_data);
				_offset += _msg_length;
			}
			
			// Compact receive buffer
			if (_offset > 0) {
				if (_offset < global.direct_receive_used) {
					var _remaining = global.direct_receive_used - _offset;
					var _temp = buffer_create(_remaining, buffer_fixed, 1);
					buffer_copy(global.direct_receive_buffer, _offset, _remaining, _temp, 0);
					buffer_copy(_temp, 0, _remaining, global.direct_receive_buffer, 0);
					buffer_delete(_temp);
					global.direct_receive_used = _remaining;
				} else {
					global.direct_receive_used = 0;
				}
			}
			break;
	}
	
	return _events;
}

/// @function _direct_client_parse_message(command_id, data_buffer)
/// @description Client parses a message from the host.
/// @returns {struct} Event struct (same format as relay events)
function _direct_client_parse_message(_command_id, _data_buffer) {
	var _event = {
		type: "UNKNOWN",
		command_id: _command_id,
		success: false,
		data: undefined
	};
	
	if (_data_buffer != undefined) {
		buffer_seek(_data_buffer, buffer_seek_start, 0);
	}
	
	switch (_command_id) {
		case CMD_AUTH_OK:
			_event.type = "AUTH_OK";
			global.direct_authenticated = true;
			_event.success = true;
			show_debug_message("DIRECT CLIENT: Authenticated");
			break;
			
		case CMD_AUTH_FAIL:
			_event.type = "AUTH_FAIL";
			global.direct_authenticated = false;
			_event.success = false;
			if (_data_buffer != undefined) {
				_event.data = _relay_read_string(_data_buffer);
			}
			show_debug_message("DIRECT CLIENT: Auth failed - " + string(_event.data));
			break;
			
		case CMD_JOIN_OK:
			_event.type = "JOIN_OK";
			global.direct_in_lobby = true;
			_event.success = true;
			
			if (_data_buffer != undefined) {
				var _player_count = buffer_read(_data_buffer, buffer_u32);
				global.direct_players = [];
				for (var i = 0; i < _player_count; i++) {
					array_push(global.direct_players, _relay_read_string(_data_buffer));
				}
			}
			
			_event.data = global.direct_players;
			show_debug_message("DIRECT CLIENT: Joined lobby with " + string(array_length(global.direct_players)) + " players");
			break;
			
		case CMD_PLAYER_JOINED:
			_event.type = "PLAYER_JOINED";
			_event.success = true;
			if (_data_buffer != undefined) {
				var _nickname = _relay_read_string(_data_buffer);
				array_push(global.direct_players, _nickname);
				_event.data = _nickname;
			}
			break;
			
		case CMD_PLAYER_LEFT:
			_event.type = "PLAYER_LEFT";
			_event.success = true;
			if (_data_buffer != undefined) {
				var _nickname = _relay_read_string(_data_buffer);
				var _idx = array_get_index(global.direct_players, _nickname);
				if (_idx >= 0) {
					array_delete(global.direct_players, _idx, 1);
				}
				_event.data = _nickname;
			}
			break;
			
		case CMD_GAME_STARTED:
			_event.type = "GAME_STARTED";
			global.direct_game_started = true;
			_event.success = true;
			show_debug_message("DIRECT CLIENT: Game started");
			break;
			
		case CMD_LOBBY_CLOSED:
			_event.type = "LOBBY_CLOSED";
			global.direct_in_lobby = false;
			global.direct_game_started = false;
			global.direct_players = [];
			_event.success = true;
			if (_data_buffer != undefined) {
				_event.data = _relay_read_string(_data_buffer);
			}
			show_debug_message("DIRECT CLIENT: Lobby closed");
			break;
			
		case CMD_RELAY:
			_event.type = "RELAY";
			_event.success = true;
			if (_data_buffer != undefined) {
				var _sender = _relay_read_string(_data_buffer);
				
				var _remaining_size = buffer_get_size(_data_buffer) - buffer_tell(_data_buffer);
				var _payload_type_id = -1;
				var _payload = undefined;
				
				if (_remaining_size >= 2) {
					_payload_type_id = buffer_read(_data_buffer, buffer_u16);
					var _payload_size = buffer_get_size(_data_buffer) - buffer_tell(_data_buffer);
					if (_payload_size > 0) {
						_payload = buffer_create(_payload_size, buffer_fixed, 1);
						buffer_copy(_data_buffer, buffer_tell(_data_buffer), _payload_size, _payload, 0);
						buffer_seek(_payload, buffer_seek_start, 0);
					}
				}
				
				_event.data = {
					sender: _sender,
					payload_type_id: _payload_type_id,
					payload: _payload
				};
			}
			break;
			
		case CMD_PING:
			// Host is pinging us, send back PONG
			_direct_send_raw(global.direct_socket, CMD_PONG, _data_buffer);
			_event.type = "PING";
			_event.success = true;
			break;
			
		case CMD_PONG:
			_event.type = "PONG";
			if (global.direct_ping_waiting) {
				global.direct_ping = (get_timer() - global.direct_ping_sent_time);
				global.direct_ping_waiting = false;
			}
			_event.success = true;
			_event.data = global.direct_ping;
			break;
			
		default:
			show_debug_message("DIRECT CLIENT: Unknown command " + string(_command_id));
			break;
	}
	
	return _event;
}

// =============================================================================
// DIRECT MODE - UTILITY
// =============================================================================

/// @function direct_is_host()
/// @returns {bool}
function direct_is_host() {
	return global.direct_is_host;
}

/// @function direct_is_connected()
/// @returns {bool} True if client is connected to host, or if hosting
function direct_is_connected() {
	if (global.direct_is_host) return (global.direct_server_socket >= 0);
	return global.direct_connected;
}

/// @function direct_is_in_lobby()
/// @returns {bool}
function direct_is_in_lobby() {
	return global.direct_in_lobby;
}

/// @function direct_is_game_started()
/// @returns {bool}
function direct_is_game_started() {
	return global.direct_game_started;
}

/// @function direct_get_players()
/// @returns {array} Array of player nicknames
function direct_get_players() {
	return global.direct_players;
}

/// @function direct_get_player_count()
/// @returns {real}
function direct_get_player_count() {
	return array_length(global.direct_players);
}

/// @function direct_get_ping()
/// @returns {real} Last measured ping in microseconds, or -1
function direct_get_ping() {
	return global.direct_ping;
}

/// @function direct_get_nickname()
/// @returns {string}
function direct_get_nickname() {
	return global.direct_nickname;
}

/// @function direct_get_client_count()
/// @returns {real} Number of connected clients (host only, excludes self)
function direct_get_client_count() {
	return array_length(global.direct_client_sockets);
}

// =============================================================================
// UNIFIED API - Mode-agnostic wrappers
// =============================================================================
// These let game code work without caring whether relay or direct is active.

/// @function net_is_in_lobby()
/// @returns {bool}
function net_is_in_lobby() {
	switch (net_get_mode()) {
		case NET_MODE.RELAY:  return relay_is_in_lobby();
		case NET_MODE.DIRECT: return direct_is_in_lobby();
		default: return false;
	}
}

/// @function net_is_game_started()
/// @returns {bool}
function net_is_game_started() {
	switch (net_get_mode()) {
		case NET_MODE.RELAY:  return relay_is_game_started();
		case NET_MODE.DIRECT: return direct_is_game_started();
		default: return false;
	}
}

/// @function net_get_players()
/// @returns {array}
function net_get_players() {
	switch (net_get_mode()) {
		case NET_MODE.RELAY:  return relay_get_players();
		case NET_MODE.DIRECT: return direct_get_players();
		default: return [];
	}
}

/// @function net_get_player_count()
/// @returns {real}
function net_get_player_count() {
	switch (net_get_mode()) {
		case NET_MODE.RELAY:  return relay_get_player_count();
		case NET_MODE.DIRECT: return direct_get_player_count();
		default: return 0;
	}
}

/// @function net_get_nickname()
/// @returns {string}
function net_get_nickname() {
	switch (net_get_mode()) {
		case NET_MODE.RELAY:  return relay_get_nickname();
		case NET_MODE.DIRECT: return direct_get_nickname();
		default: return "";
	}
}

/// @function net_get_ping()
/// @returns {real}
function net_get_ping() {
	switch (net_get_mode()) {
		case NET_MODE.RELAY:  return relay_get_ping();
		case NET_MODE.DIRECT: return direct_get_ping();
		default: return -1;
	}
}

/// @function net_send(buffer, [type_id])
/// @param {buffer} buffer - Data to send
/// @param {real} type_id - Payload type
function net_send(_buffer, _type_id = 0) {
	switch (net_get_mode()) {
		case NET_MODE.RELAY:  relay_send(_buffer, _type_id); break;
		case NET_MODE.DIRECT: direct_send(_buffer, _type_id); break;
	}
}

/// @function net_send_string(message, [type_id])
/// @param {string} message - String to send
/// @param {real} type_id - Payload type
function net_send_string(_message, _type_id = 0) {
	switch (net_get_mode()) {
		case NET_MODE.RELAY:  relay_send_string(_message, _type_id); break;
		case NET_MODE.DIRECT: direct_send_string(_message, _type_id); break;
	}
}

/// @function net_start_game()
function net_start_game() {
	switch (net_get_mode()) {
		case NET_MODE.RELAY:  relay_start_game(); break;
		case NET_MODE.DIRECT: direct_start_game(); break;
	}
}

/// @function net_leave()
function net_leave() {
	switch (net_get_mode()) {
		case NET_MODE.RELAY:  relay_leave_lobby(); break;
		case NET_MODE.DIRECT: direct_leave(); break;
	}
}

/// @function net_destroy()
function net_destroy() {
	switch (net_get_mode()) {
		case NET_MODE.RELAY:  relay_destroy(); break;
		case NET_MODE.DIRECT: direct_destroy(); break;
	}
}

/// @function net_ping()
function net_ping() {
	switch (net_get_mode()) {
		case NET_MODE.RELAY:  relay_ping(); break;
		case NET_MODE.DIRECT: direct_ping(); break;
	}
}

/// @function net_async_network()
/// @returns {array} Array of event structs
function net_async_network() {
	switch (net_get_mode()) {
		case NET_MODE.RELAY:  return relay_async_network();
		case NET_MODE.DIRECT: return direct_async_network();
		default: return [];
	}
}
