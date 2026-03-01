// Feather disable all

/// Returns <true> if the given value is an Outatime clock, as created by OutatimeClock()
/// 
/// @param value   The value to check

function OutatimeIsClock(_value)
{
	if (!is_struct(_value)) return false;
	return (instanceof(_value) == "OutatimeClock");
}
