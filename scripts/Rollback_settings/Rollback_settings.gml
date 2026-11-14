#macro ROLLBACK_DEPTH 20				// This is the maximum ticks we can rollback to.
#macro ROLLBACK_TICK_DURATION 25000		// This is the duration of a tick in microsecond.
#macro ROLLBACK_INPUT_DELAY 3			// This is the input delay
#macro ROLLBACK_INPUT_LEAD (ROLLBACK_DEPTH + ROLLBACK_INPUT_DELAY)	// How far ahead of the local frame a remote input may be stored. Later ones wait in the message queue.
#macro ROLLBACK_SYNC_EVERY 20			// Ticks between two frame advantages sent to the other players (time sync).
#macro ROLLBACK_SYNC_MAX_SKIP 8			// The most ticks a player ahead skips at once to let the others catch up.
#macro ROLLBACK_SYNC_MIN_DIFFERENCE 4	// The two players' average advantages differ by this much (2 frames ahead) before a skip: less is network jitter.
