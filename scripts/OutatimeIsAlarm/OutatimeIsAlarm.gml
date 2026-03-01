// Feather disable all

/// Returns <true> if the given value is an Outatime alarm, as returned by .AddAlarm() or .AddAlarmTicks()
/// 
/// @param value   The value to check

function OutatimeIsAlarm(_value)
{
	if (!is_struct(_value)) return false;
	return (instanceof(_value) == "__outatimeClassAlarm");
}
