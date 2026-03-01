// Call parent (sets up state_buffer, rollback signal subscription, etc.)
event_inherited();

// --- Player identity (set by the rollback manager after creation) ---
player_index = 0;
player_color = c_lime;

// --- Movement ---
move_speed = 3;	   // pixels per tick

// =============================================================================
// TICK METHOD — runs every rollback tick (deterministic simulation)
// =============================================================================
global.rollback_clock.AddTickMethod(function()
{
	var _up	= pp_rollback_get_input(VERB_UP,	player_index);
	var _down  = pp_rollback_get_input(VERB_DOWN,  player_index);
	var _left  = pp_rollback_get_input(VERB_LEFT,  player_index);
	var _right = pp_rollback_get_input(VERB_RIGHT, player_index);
	
	x += (_right - _left) * move_speed;
	y += (_down  - _up)   * move_speed;
	
	// Clamp to room bounds
	x = clamp(x, 16, room_width  - 16);
	y = clamp(y, 16, room_height - 16);
});

// =============================================================================
// STATE SERIALIZATION — what gets saved / restored on rollback
// =============================================================================

/// @function serialize_state()
/// @returns {struct} Snapshot of all rollback-relevant variables
serialize_state = function() {
	return {
		px: x,
		py: y
	};
};

/// @function deserialize_state(state)
/// @param {struct} state — A snapshot previously returned by serialize_state()
deserialize_state = function(_state) {
	x = _state.px;
	y = _state.py;
};

/////////////////////////
// Draw Event
/////////////////////////

// Simple colored square with player number
draw_set_colour(player_color);
draw_rectangle(x - 16, y - 16, x + 16, y + 16, false);

draw_set_colour(c_black);
draw_set_halign(fa_center);
draw_set_valign(fa_middle);
draw_text(x, y, "P" + string(player_index));
draw_set_halign(fa_left);
draw_set_valign(fa_top);
