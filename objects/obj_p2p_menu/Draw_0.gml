draw_set_colour(c_white);
draw_set_halign(fa_center);
draw_set_valign(fa_middle);
draw_text(room_width / 2, room_height / 2, status);

// Debug overlay at bottom
draw_set_halign(fa_left);
draw_set_valign(fa_bottom);
draw_set_colour(c_gray);
if (is_initialized && net_get_mode() == NET_MODE.DIRECT)
{
	var _dbg = "connected=" + string(global.direct_connected)
			 + "  auth=" + string(global.direct_authenticated)
			 + "  lobby=" + string(direct_is_in_lobby())
			 + "  players=" + string(net_get_player_count());
	draw_text(8, room_height - 8, _dbg);
}
draw_set_valign(fa_top);
