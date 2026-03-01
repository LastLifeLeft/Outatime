/// Deterministic RNG for rollback netcode using Xorshift128

// =============================================================================
// INTERNAL STATE
// =============================================================================

global.__rng_state = {
	s0: 123456789,
	s1: 362436069
};

#macro RNG_MAX 2147483647  // 2^31 - 1 (signed 32-bit max)

// =============================================================================
// CORE FUNCTIONS
// =============================================================================

/// @function rollback_random_init(seed)
function rollback_random_init(_seed) {
	_seed = floor(abs(_seed));
	if (_seed == 0) _seed = 1;
	
	// Simple seed mixing
	global.__rng_state.s0 = (_seed * 1103515245 + 12345) mod RNG_MAX;
	global.__rng_state.s1 = (global.__rng_state.s0 * 1103515245 + 12345) mod RNG_MAX;
	
	// Warm up
	repeat (16) {
		__rng_next();
	}
}

/// @function rollback_random_get_state()
function rollback_random_get_state() {
	return {
		s0: global.__rng_state.s0,
		s1: global.__rng_state.s1
	};
}

/// @function rollback_random_set_state(state)
function rollback_random_set_state(_state) {
	global.__rng_state.s0 = _state.s0;
	global.__rng_state.s1 = _state.s1;
}

/// @function __rng_next()
/// @description Internal: Generate next raw value using LCG (GML-safe)
function __rng_next() {
	// Combined LCG - simple and works reliably in GML
	global.__rng_state.s0 = (global.__rng_state.s0 * 1103515245 + 12345) mod RNG_MAX;
	global.__rng_state.s1 = (global.__rng_state.s1 * 1664525 + 1013904223) mod RNG_MAX;
	
	// Combine both states
	return (global.__rng_state.s0 + global.__rng_state.s1) mod RNG_MAX;
}

// =============================================================================
// USER-FACING FUNCTIONS
// =============================================================================

/// @function rollback_random()
/// @description Returns a random real between 0 (inclusive) and 1 (exclusive)
function rollback_random() {
	return __rng_next() / RNG_MAX;
}

/// @function rollback_random_range(min, max)
/// @description Returns a random real between min (inclusive) and max (exclusive)
function rollback_random_range(_min, _max) {
	return _min + rollback_random() * (_max - _min);
}

/// @function rollback_irandom(max)
/// @description Returns a random integer between 0 and max (both inclusive)
function rollback_irandom(_max) {
	return floor(rollback_random() * (_max + 1));
}

/// @function rollback_irandom_range(min, max)
/// @description Returns a random integer between min and max (both inclusive)
function rollback_irandom_range(_min, _max) {
	return _min + floor(rollback_random() * (_max - _min + 1));
}

/// @function rollback_choose(...)
/// @description Returns one of the arguments at random
function rollback_choose() {
	var _count = argument_count;
	if (_count == 0) return undefined;
	
	var _index = rollback_irandom(_count - 1);
	return argument[_index];
}

/// @function rollback_chance(percent)
/// @description Returns true with the given percentage chance
function rollback_chance(_percent) {
	return rollback_random() * 100 < _percent;
}

/// @function rollback_sign()
/// @description Returns either -1 or 1 at random
function rollback_sign() {
	return rollback_random() < 0.5 ? -1 : 1;
}

/// @function rollback_shuffle_array(array)
/// @description Shuffles an array in place using Fisher-Yates algorithm
function rollback_shuffle_array(_array) {
	var _len = array_length(_array);
	
	for (var i = _len - 1; i > 0; i--) {
		var j = rollback_irandom(i);
		var _temp = _array[i];
		_array[i] = _array[j];
		_array[j] = _temp;
	}
	
	return _array;
}