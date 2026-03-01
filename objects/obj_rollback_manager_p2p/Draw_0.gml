// Simple HUD drawn directly (no PP splitview dependency)
draw_set_colour(c_white);
draw_set_halign(fa_left);
draw_set_valign(fa_top);
draw_text(8, 8,  "Frame: "  + string(global.absolute_frame));
draw_text(8, 28, "Player: " + global.relay_nickname + " (P" + string(local_player_index) + ")");

if (connection_paused) {
	draw_set_colour(c_red);
	draw_set_halign(fa_center);
	draw_text(room_width / 2, room_height / 2 - 40, "WAITING FOR OTHER PLAYER...");
	draw_set_halign(fa_left);
}