// Feather disable all

#macro __outatime_VERSION  "0.0.1"
#macro __outatime_DATE	 "2026-03-01"

enum __outatime_CHILD
{
	__outatime_ID,
	__SCOPE,
	__BEGIN_METHOD,
	__NORMAL_METHOD,
	__END_METHOD,
	__DEAD,
	__VARIABLES_INTERPOLATE,
	__SIZE
}

enum __outatime_INTERPOLATED_VARIABLE
{
	__IN_NAME,
	__OUT_NAME,
	__PREV_VALUE,
	__IS_ANGLE,
	__SIZE,
}
 
#macro Outatime_CURRENT_CLOCK	 __outatime().__currentClockName
#macro Outatime_TICKS_FOR_CLOCK   __outatime().__totalTicks
#macro Outatime_TICK_INDEX		__outatime().__tickIndex
#macro Outatime_SECONDS_PER_TICK  __outatime().__secondsPerTick  

function __outatime()
{
	static _struct = undefined;
	if (_struct != undefined) return _struct;
	
	__outatimeTrace("Welcome to Outatime by ❤x1! This is version " + __outatime_VERSION + ", " + __outatime_DATE);
	
	_struct = {};
	with(_struct)
	{
		__uniqueID	 = 0;
		__currentClock = undefined;
		
		__currentClockName = undefined;
		__totalTicks	   = undefined;
		__tickIndex		= undefined;
		__secondsPerTick   = undefined;
	}
	
	return _struct;
}