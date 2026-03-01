// Simple colored square with player number
draw_set_colour(player_color);
draw_rectangle(x - 16, y - 16, x + 16, y + 16, false);

draw_set_colour(c_black);
draw_set_halign(fa_center);
draw_set_valign(fa_middle);
draw_text(x, y, "P" + string(player_index));
draw_set_halign(fa_left);
draw_set_valign(fa_top);