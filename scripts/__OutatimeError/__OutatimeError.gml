// Feather disable all

function __outatimeError()
{
	var _string = "Outatime " + string(__outatime_VERSION) + ":\n";
	var _i = 0;
	repeat(argument_count)
	{
		_string += string(argument[_i]);
		++_i;
	}
	
	show_error(_string + "\n ", true);
}