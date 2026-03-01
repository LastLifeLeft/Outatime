// Feather disable all

function __outatimeTrace()
{
	var _string = "Outatime: ";
	var _i = 0;
	repeat(argument_count)
	{
		_string += string(argument[_i]);
		++_i;
	}
	
	show_debug_message(_string);
}