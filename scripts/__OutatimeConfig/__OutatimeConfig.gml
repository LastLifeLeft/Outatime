// Feather disable all

//Whether to check if instances have been deactivated when cleaning up clock child data
//This incurs a slight performance penalty but should be left set to <true>
//If you do need the performance boost, make sure you're not using deactivation or things will break!
#macro  Outatime_CHECK_FOR_DEACTIVATION  true

//The minimum framerate that Outatime will run at
//This ensures that *some* gameplay happens even if the engine is struggling along
#macro  Outatime_MINIMUM_FRAMERATE  15

//Variable to set in structs/instances to record their unique Outatime ID
//This allows Outatime to disambiguate clock children across multiple method types
#macro  Outatime_ID_VARIABLE_NAME  "__outatimeUniqueID__"

//These four macros are also available for use inside Outatime methods
//Outside of Outatime methods they will return <undefined>
//	Outatime_CURRENT_CLOCK	= Identifier for the clock that's currently being handled
//	Outatime_TICKS_FOR_CLOCK  = Total number of ticks that will be processed this update for the current clock
//	Outatime_TICK_INDEX	   = Current tick for the current clock (0-indexed)
//	Outatime_SECONDS_PER_TICK = How long each tick is, in seconds
