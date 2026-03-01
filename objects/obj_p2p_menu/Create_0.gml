// --- Config ---
#macro JOIN_IP   "127.0.0.1"
#macro JOIN_PORT 5556

status		 = "Press [H] to Host  |  [J] to Join";
is_initialized = false;
role		   = "";		// "host" or "client"
seed_received  = false;	 // Client: have we gotten the seed?