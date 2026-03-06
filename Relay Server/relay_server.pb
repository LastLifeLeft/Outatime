; TCP Relay Server for PureBasic - Binary Protocol
; Supports up to 4 players per lobby with nickname and lobby management
; Protocol: Binary messages with 4-byte command IDs

EnableExplicit

;- Constants
#SERVER_PORT = 5555
#SECRET_PASSCODE = "IThaiUDie!"
#MAX_PLAYERS_PER_LOBBY = 4
#MIN_PLAYERS_TO_START = 2
#BUFFER_SIZE = 4096
#MAX_MESSAGE_SIZE = 65536 ; 64KB max message size

;- Logs
#LOG_FILE = "relay_server.log"
#LOG_MAX_SIZE = 10 * 1024 * 1024 ; 10 MB max log size before rotation

;- Command IDs
Enumeration
	#CMD_PING = 1
	#CMD_PONG
	#CMD_AUTH
	#CMD_AUTH_OK
	#CMD_AUTH_FAIL
	#CMD_CREATE_LOBBY
	#CMD_CREATE_OK
	#CMD_CREATE_FAIL
	#CMD_LIST_LOBBIES
	#CMD_LOBBY_LIST
	#CMD_JOIN_LOBBY
	#CMD_JOIN_OK
	#CMD_JOIN_FAIL
	#CMD_START_GAME
	#CMD_GAME_STARTED
	#CMD_START_FAIL
	#CMD_LEAVE_LOBBY
	#CMD_LEAVE_OK
	#CMD_LEAVE_FAIL
	#CMD_PLAYER_JOINED
	#CMD_PLAYER_LEFT
	#CMD_LOBBY_CLOSED
	#CMD_RELAY
	#CMD_ERROR
	#CMD_DEPLOY
EndEnumeration

;- Structures
Structure Player
	ClientID.i
	Nickname.s
	LastActivity.q
	Authenticated.b
	ReceiveBuffer.i ; Memory buffer for incomplete messages
	BufferSize.i
	BufferUsed.i
EndStructure

Structure Lobby
	Name.s
	ID.i
	CreatorNickname.s
	Players.i[#MAX_PLAYERS_PER_LOBBY]
	PlayerCount.i
	GameStarted.b
	LastActivity.q
EndStructure

;- Globals
Global NewMap Lobbies.Lobby()
Global NewMap Clients.Player()
Global LobbyIDCounter.i = 1
Global ServerSocket.i
Global LogFile.i = 0

;- Logging
Procedure InitLog()
	If FileSize(#LOG_FILE) > #LOG_MAX_SIZE
		Protected OldLog.s = #LOG_FILE + ".old"
		If FileSize(OldLog) >= 0
			DeleteFile(OldLog)
		EndIf
		RenameFile(#LOG_FILE, OldLog)
	EndIf
	
	LogFile = OpenFile(#PB_Any, #LOG_FILE, #PB_File_Append | #PB_UTF8)
	If Not LogFile
		LogFile = CreateFile(#PB_Any, #LOG_FILE, #PB_UTF8)
	EndIf
	
EndProcedure

Procedure CloseLog()
	If LogFile
		CloseFile(LogFile)
		LogFile = 0
	EndIf
EndProcedure

Procedure LogString(Message.s, Level.s = "INFO")
	Protected Timestamp.s = FormatDate("%yyyy-%mm-%dd %hh:%ii:%ss", Date())
	Protected LogLine.s = "[" + Timestamp + "] [" + Level + "] " + Message
	
	PrintN(LogLine)
	
	If LogFile
		WriteStringN(LogFile, LogLine, #PB_UTF8)
		FlushFileBuffers(LogFile)
	EndIf
EndProcedure

Procedure LogError(Message.s)
	LogString(Message, "ERROR")
EndProcedure

Procedure LogWarning(Message.s)
	LogString(Message, "WARN")
EndProcedure

Procedure LogDebug(Message.s)
	LogString(Message, "DEBUG")
EndProcedure

;- Binary Protocol Helpers
Procedure.s ClientKey(ClientID.i)
	ProcedureReturn Str(ClientID)
EndProcedure

; Write a string to memory buffer (4-byte length + UTF-8 data)
Procedure WriteStringToBuffer(*Buffer, String.s)
	Protected Bytes.i = StringByteLength(String, #PB_UTF8)
	PokeL(*Buffer, Bytes)
	If Bytes > 0
		PokeS(*Buffer + 4, String, Bytes, #PB_UTF8 | #PB_String_NoZero)
	EndIf
	ProcedureReturn 4 + Bytes
EndProcedure

; Read a string from memory buffer (4-byte length + UTF-8 data)
Procedure.s ReadStringFromBuffer(*Buffer, *BytesRead.Integer)
	Protected Length.i = PeekL(*Buffer)
	If Length > 0 And Length < #MAX_MESSAGE_SIZE
		Protected Result.s = PeekS(*Buffer + 4, Length, #PB_UTF8 | #PB_ByteLength)
		*BytesRead\i = 4 + Length
		ProcedureReturn Result
	Else
		*BytesRead\i = 4
		ProcedureReturn ""
	EndIf
EndProcedure

; Send a binary message to client
Procedure SendMessage(ClientID.i, CommandID.i, *Data = 0, DataSize.i = 0)
	If ClientID
		Protected TotalSize.i = 8 + DataSize ; 4 bytes length + 4 bytes command + data
		Protected *Buffer = AllocateMemory(TotalSize)
		If *Buffer
			PokeL(*Buffer, TotalSize)
			PokeL(*Buffer + 4, CommandID)
			If *Data And DataSize > 0
				CopyMemory(*Data, *Buffer + 8, DataSize)
			EndIf
			
			Protected BytesSent.i = SendNetworkData(ClientID, *Buffer, TotalSize)
			If BytesSent <= 0
				LogWarning("SendMessage failed for ClientID " + Str(ClientID) + " (BytesSent: " + Str(BytesSent) + ")")
			EndIf
			FreeMemory(*Buffer)
		Else
			LogError("SendMessage: Failed to allocate memory for ClientID " + Str(ClientID))
		EndIf
	EndIf
EndProcedure

; Send a message with a single string
Procedure SendMessageWithString(ClientID.i, CommandID.i, String.s)
	Protected *Buffer = AllocateMemory(#BUFFER_SIZE)
	If *Buffer
		Protected Size.i = WriteStringToBuffer(*Buffer, String)
		SendMessage(ClientID, CommandID, *Buffer, Size)
		FreeMemory(*Buffer)
	EndIf
EndProcedure

; Send a message with a single long
Procedure SendMessageWithLong(ClientID.i, CommandID.i, Value.l)
	Protected *Buffer = AllocateMemory(4)
	If *Buffer
		PokeL(*Buffer, Value)
		SendMessage(ClientID, CommandID, *Buffer, 4)
		FreeMemory(*Buffer)
	EndIf
EndProcedure

;- Protocol Handlers
Procedure HandleAuth(ClientID.i, *Data, DataSize.i)
	Protected Key.s = ClientKey(ClientID)
	Protected BytesRead.i
	Protected Passcode.s, Nickname.s
	
	; Read passcode
	Passcode = ReadStringFromBuffer(*Data, @BytesRead)
	; Read nickname
	Nickname = ReadStringFromBuffer(*Data + BytesRead, @BytesRead)
	
	LogDebug("HandleAuth: ClientID=" + Str(ClientID) + ", Nickname=" + Nickname)
	
	If Passcode = #SECRET_PASSCODE
		If FindMapElement(Clients(), Key)
			Clients()\Nickname = Nickname
			Clients()\LastActivity = ElapsedMilliseconds()
			Clients()\Authenticated = #True
		Else
			LogError("HandleAuth: Client not found in map: " + Key)
		EndIf
		
		LogString("AUTH OK: " + Nickname + " (ClientID: " + Str(ClientID) + ")")
		SendMessage(ClientID, #CMD_AUTH_OK)
	Else
		LogString("AUTH FAIL: Bad passcode from ClientID " + Str(ClientID))
		SendMessageWithString(ClientID, #CMD_AUTH_FAIL, "Invalid passcode")
	EndIf
EndProcedure

Procedure.b IsAuthenticated(ClientID.i)
	Protected Key.s = ClientKey(ClientID)
	Protected Result.b = #False
	
	If FindMapElement(Clients(), Key)
		Result = Clients()\Authenticated
	EndIf
	
	ProcedureReturn Result
EndProcedure

Procedure.s GetNickname(ClientID.i)
	Protected Key.s = ClientKey(ClientID)
	Protected Result.s = ""
	
	If FindMapElement(Clients(), Key)
		Result = Clients()\Nickname
	EndIf
	
	ProcedureReturn Result
EndProcedure

Procedure HandleCreateLobby(ClientID.i, *Data, DataSize.i)
	Protected Nickname.s = GetNickname(ClientID)
	Protected NewID.i
	Protected BytesRead.i
	Protected LobbyName.s = ReadStringFromBuffer(*Data, @BytesRead)
	
	LogDebug("HandleCreateLobby: ClientID=" + Str(ClientID) + ", LobbyName=" + LobbyName)
	
	; Check if player is already in a lobby
	ForEach Lobbies()
		Protected i.i
		For i = 0 To Lobbies()\PlayerCount - 1
			If Lobbies()\Players[i] = ClientID
				LogString("CREATE FAIL: " + Nickname + " already in a lobby")
				SendMessageWithString(ClientID, #CMD_CREATE_FAIL, "Already in a lobby")
				ProcedureReturn
			EndIf
		Next
	Next
	
	NewID = LobbyIDCounter
	LobbyIDCounter + 1
	
	Protected LobbyKey.s = Str(NewID)
	Lobbies(LobbyKey)\Name = LobbyName
	Lobbies(LobbyKey)\ID = NewID
	Lobbies(LobbyKey)\CreatorNickname = Nickname
	Lobbies(LobbyKey)\PlayerCount = 1
	Lobbies(LobbyKey)\GameStarted = #False
	Lobbies(LobbyKey)\LastActivity = ElapsedMilliseconds()
	Lobbies(LobbyKey)\Players[0] = ClientID
	
	LogString("LOBBY CREATED: '" + LobbyName + "' (ID:" + Str(NewID) + ") by " + Nickname)
	SendMessageWithLong(ClientID, #CMD_CREATE_OK, NewID)
EndProcedure

Procedure HandleListLobbies(ClientID.i)
	Protected *Buffer = AllocateMemory(#MAX_MESSAGE_SIZE)
	If Not *Buffer
		LogError("HandleListLobbies: Failed to allocate buffer")
		ProcedureReturn
	EndIf
	
	Protected Offset.i = 0
	Protected Count.i = 0
	Protected BytesWritten.i
	
	LogDebug("HandleListLobbies: ClientID=" + Str(ClientID))
	
	; Write lobby count first (will update at end)
	PokeL(*Buffer, 0)
	Offset = 4
	
	ForEach Lobbies()
		If Not Lobbies()\GameStarted
			; Write: LobbyID (4), Name (string), PlayerCount (4), MaxPlayers (4), Creator (string)
			PokeL(*Buffer + Offset, Lobbies()\ID)
			Offset + 4
			
			BytesWritten = WriteStringToBuffer(*Buffer + Offset, Lobbies()\Name)
			Offset + BytesWritten
			
			PokeL(*Buffer + Offset, Lobbies()\PlayerCount)
			Offset + 4
			
			PokeL(*Buffer + Offset, #MAX_PLAYERS_PER_LOBBY)
			Offset + 4
			
			BytesWritten = WriteStringToBuffer(*Buffer + Offset, Lobbies()\CreatorNickname)
			Offset + BytesWritten
			
			Count + 1
		EndIf
	Next
	
	; Update count at beginning
	PokeL(*Buffer, Count)
	
	LogString("LIST LOBBIES: Sent " + Str(Count) + " lobbies to ClientID " + Str(ClientID))
	SendMessage(ClientID, #CMD_LOBBY_LIST, *Buffer, Offset)
	FreeMemory(*Buffer)
EndProcedure

Procedure HandleJoinLobby(ClientID.i, *Data, DataSize.i)
	Protected Nickname.s = GetNickname(ClientID)
	Protected LobbyID.l = PeekL(*Data)
	Protected LobbyKey.s = Str(LobbyID)
	Protected i.i
	
	LogDebug("HandleJoinLobby: ClientID=" + Str(ClientID) + ", LobbyID=" + Str(LobbyID))
	
	; Check if player is already in a lobby
	ForEach Lobbies()
		For i = 0 To Lobbies()\PlayerCount - 1
			If Lobbies()\Players[i] = ClientID
				LogString("JOIN FAIL: " + Nickname + " already in a lobby")
				SendMessageWithString(ClientID, #CMD_JOIN_FAIL, "Already in a lobby")
				ProcedureReturn
			EndIf
		Next
	Next
	
	If FindMapElement(Lobbies(), LobbyKey)
		If Lobbies()\GameStarted
			LogString("JOIN FAIL: " + Nickname + " tried to join started game")
			SendMessageWithString(ClientID, #CMD_JOIN_FAIL, "Game already started")
			ProcedureReturn
		EndIf
		
		If Lobbies()\PlayerCount >= #MAX_PLAYERS_PER_LOBBY
			LogString("JOIN FAIL: Lobby full")
			SendMessageWithString(ClientID, #CMD_JOIN_FAIL, "Lobby is full")
			ProcedureReturn
		EndIf
		
		Protected PlayerIndex.i = Lobbies()\PlayerCount
		Lobbies()\Players[PlayerIndex] = ClientID
		Lobbies()\PlayerCount + 1
		Lobbies()\LastActivity = ElapsedMilliseconds()
		
		; Notify other players
		For i = 0 To Lobbies()\PlayerCount - 1
			If Lobbies()\Players[i] <> ClientID
				SendMessageWithString(Lobbies()\Players[i], #CMD_PLAYER_JOINED, Nickname)
			EndIf
		Next
		
		LogString("JOIN OK: " + Nickname + " joined lobby '" + Lobbies()\Name + "'")
		
		; Build player list for response
		Protected *Buffer = AllocateMemory(#BUFFER_SIZE)
		If *Buffer
			Protected Offset.i = 0
			
			; Write player count
			PokeL(*Buffer, Lobbies()\PlayerCount)
			Offset = 4
			
			; Write each player nickname
			For i = 0 To Lobbies()\PlayerCount - 1
				Protected BytesWritten.i = WriteStringToBuffer(*Buffer + Offset, GetNickname(Lobbies()\Players[i]))
				Offset + BytesWritten
			Next
			
			SendMessage(ClientID, #CMD_JOIN_OK, *Buffer, Offset)
			FreeMemory(*Buffer)
		EndIf
	Else
		LogString("JOIN FAIL: Lobby not found (ID: " + Str(LobbyID) + ")")
		SendMessageWithString(ClientID, #CMD_JOIN_FAIL, "Lobby not found")
	EndIf
EndProcedure

Procedure HandleStartGame(ClientID.i)
	Protected Nickname.s = GetNickname(ClientID)
	Protected i.i
	
	LogDebug("HandleStartGame: ClientID=" + Str(ClientID))
	
	ForEach Lobbies()
		If Lobbies()\Players[0] = ClientID
			If Lobbies()\PlayerCount < #MIN_PLAYERS_TO_START
				LogString("START FAIL: Not enough players")
				SendMessageWithString(ClientID, #CMD_START_FAIL, "Need at least " + Str(#MIN_PLAYERS_TO_START) + " players")
				ProcedureReturn
			EndIf
			
			If Lobbies()\GameStarted
				LogString("START FAIL: Game already started")
				SendMessageWithString(ClientID, #CMD_START_FAIL, "Game already started")
				ProcedureReturn
			EndIf
			
			Lobbies()\GameStarted = #True
			Lobbies()\LastActivity = ElapsedMilliseconds()
			
			; Notify all players
			For i = 0 To Lobbies()\PlayerCount - 1
				SendMessage(Lobbies()\Players[i], #CMD_GAME_STARTED)
			Next
			
			LogString("GAME STARTED: Lobby '" + Lobbies()\Name + "' with " + Str(Lobbies()\PlayerCount) + " players")
			ProcedureReturn
		EndIf
	Next
	
	LogString("START FAIL: " + Nickname + " is not a lobby creator")
	SendMessageWithString(ClientID, #CMD_START_FAIL, "Not lobby creator or not in lobby")
EndProcedure

Procedure HandleDeploy(ClientID.i)
	Protected i.i
	
	ForEach Lobbies()
		If Lobbies()\Players[0] = ClientID
			Lobbies()\LastActivity = ElapsedMilliseconds()
			
			; Notify all players
			For i = 0 To Lobbies()\PlayerCount - 1
				SendMessage(Lobbies()\Players[i], #CMD_DEPLOY)
			Next
			
			LogString("DEPLOYED: Lobby '" + Lobbies()\Name + "' with " + Str(Lobbies()\PlayerCount) + " players")
			ProcedureReturn
		EndIf
	Next
EndProcedure

Procedure HandleLeaveLobby(ClientID.i, SendConfirmation.b = #True)
	Protected Nickname.s = GetNickname(ClientID)
	Protected i.i, j.i
	Protected Found.b = #False
	
	LogDebug("HandleLeaveLobby: ClientID=" + Str(ClientID) + ", Nickname=" + Nickname)
	
	ForEach Lobbies()
		For i = 0 To Lobbies()\PlayerCount - 1
			If Lobbies()\Players[i] = ClientID
				Found = #True
				Protected LobbyName.s = Lobbies()\Name
				Protected WasCreator.b = Bool(i = 0)
				
				; Remove player
				For j = i To Lobbies()\PlayerCount - 2
					Lobbies()\Players[j] = Lobbies()\Players[j + 1]
				Next
				Lobbies()\PlayerCount - 1
				
				; Notify remaining players
				For j = 0 To Lobbies()\PlayerCount - 1
					SendMessageWithString(Lobbies()\Players[j], #CMD_PLAYER_LEFT, Nickname)
				Next
				
				LogString("LEAVE: " + Nickname + " left lobby '" + LobbyName + "'")
				
				; Delete lobby if empty or creator left before game started
				If Lobbies()\PlayerCount = 0 Or (WasCreator And Not Lobbies()\GameStarted)
					If Lobbies()\PlayerCount > 0
						For j = 0 To Lobbies()\PlayerCount - 1
							SendMessageWithString(Lobbies()\Players[j], #CMD_LOBBY_CLOSED, "Creator left")
						Next
					EndIf
					LogString("LOBBY DELETED: '" + LobbyName + "'")
					DeleteMapElement(Lobbies())
				EndIf
				
				Break 2
			EndIf
		Next
	Next
	
	; Only send confirmation if requested (i.e., not during disconnect)
	If SendConfirmation
		If Found
			SendMessage(ClientID, #CMD_LEAVE_OK)
		Else
			SendMessageWithString(ClientID, #CMD_LEAVE_FAIL, "Not in a lobby")
		EndIf
	EndIf
EndProcedure

Procedure HandleRelay(ClientID.i, *Data, DataSize.i)
	Protected i.i
	Protected SenderNickname.s = GetNickname(ClientID)
	
	LogDebug("HandleRelay: ClientID=" + Str(ClientID) + ", DataSize=" + Str(DataSize))
	
	ForEach Lobbies()
		For i = 0 To Lobbies()\PlayerCount - 1
			If Lobbies()\Players[i] = ClientID
				Lobbies()\LastActivity = ElapsedMilliseconds()
				
				; Build relay message: nickname (string) + data
				Protected *RelayBuffer = AllocateMemory(DataSize + #BUFFER_SIZE)
				If *RelayBuffer
					Protected Offset.i = WriteStringToBuffer(*RelayBuffer, SenderNickname)
					CopyMemory(*Data, *RelayBuffer + Offset, DataSize)
					
					; Relay to all OTHER players
					Protected j.i, RelayCount.i = 0
					For j = 0 To Lobbies()\PlayerCount - 1
						If Lobbies()\Players[j] <> ClientID
							SendMessage(Lobbies()\Players[j], #CMD_RELAY, *RelayBuffer, Offset + DataSize)
							RelayCount + 1
						EndIf
					Next
					
					FreeMemory(*RelayBuffer)
					LogDebug("HandleRelay: Relayed to " + Str(RelayCount) + " players")
				EndIf
				
				ProcedureReturn
			EndIf
		Next
	Next
	
	LogWarning("HandleRelay: ClientID " + Str(ClientID) + " not found in any lobby")
EndProcedure

Procedure HandlePing(ClientID.i, *Data, DataSize.i)
	; Echo back the ping data
	SendMessage(ClientID, #CMD_PONG, *Data, DataSize)
EndProcedure

Procedure HandleClientDisconnect(ClientID.i)
	Protected Nickname.s = GetNickname(ClientID)
	Protected Key.s = ClientKey(ClientID)
	
	LogDebug("HandleClientDisconnect: ClientID=" + Str(ClientID) + ", Nickname=" + Nickname)
	
	; Leave lobby without sending confirmation (client already disconnected)
	HandleLeaveLobby(ClientID, #False)
	
	If FindMapElement(Clients(), Key)
		If Clients()\ReceiveBuffer
			FreeMemory(Clients()\ReceiveBuffer)
		EndIf
		DeleteMapElement(Clients())
	EndIf
	
	LogString("DISCONNECT: " + Nickname + " (ClientID: " + Str(ClientID) + ")")
EndProcedure

;- Message Processor
Procedure ProcessMessage(ClientID.i, CommandID.i, *Data, DataSize.i)
	Protected Key.s = ClientKey(ClientID)
	
	LogDebug("ProcessMessage: ClientID=" + Str(ClientID) + ", CommandID=" + Str(CommandID) + ", DataSize=" + Str(DataSize))
	
	; Update last activity
	If FindMapElement(Clients(), Key)
		Clients()\LastActivity = ElapsedMilliseconds()
	EndIf
	
	Select CommandID
		Case #CMD_PING
			HandlePing(ClientID, *Data, DataSize)
			
		Case #CMD_AUTH
			HandleAuth(ClientID, *Data, DataSize)
			
		Case #CMD_CREATE_LOBBY
			If IsAuthenticated(ClientID)
				HandleCreateLobby(ClientID, *Data, DataSize)
			Else
				SendMessageWithString(ClientID, #CMD_ERROR, "Not authenticated")
			EndIf
			
		Case #CMD_LIST_LOBBIES
			If IsAuthenticated(ClientID)
				HandleListLobbies(ClientID)
			Else
				SendMessageWithString(ClientID, #CMD_ERROR, "Not authenticated")
			EndIf
			
		Case #CMD_JOIN_LOBBY
			If IsAuthenticated(ClientID)
				HandleJoinLobby(ClientID, *Data, DataSize)
			Else
				SendMessageWithString(ClientID, #CMD_ERROR, "Not authenticated")
			EndIf
			
		Case #CMD_START_GAME
			If IsAuthenticated(ClientID)
				HandleStartGame(ClientID)
			Else
				SendMessageWithString(ClientID, #CMD_ERROR, "Not authenticated")
			EndIf
			
		Case #CMD_DEPLOY
			If IsAuthenticated(ClientID)
				HandleDeploy(ClientID)
			Else
				SendMessageWithString(ClientID, #CMD_ERROR, "Not authenticated")
			EndIf
		Case #CMD_LEAVE_LOBBY
			If IsAuthenticated(ClientID)
				HandleLeaveLobby(ClientID, #True)
			Else
				SendMessageWithString(ClientID, #CMD_ERROR, "Not authenticated")
			EndIf
			
		Case #CMD_RELAY
			If IsAuthenticated(ClientID)
				HandleRelay(ClientID, *Data, DataSize)
			Else
				SendMessageWithString(ClientID, #CMD_ERROR, "Not authenticated")
			EndIf
			
		Default
			LogWarning("UNKNOWN COMMAND: " + Str(CommandID) + " from ClientID " + Str(ClientID))
	EndSelect
EndProcedure

;- Process received data (handles TCP buffering)
Procedure ProcessReceivedData(ClientID.i, *Data, DataSize.i)
	Protected Key.s = ClientKey(ClientID)
	
	LogDebug("ProcessReceivedData: ClientID=" + Str(ClientID) + ", DataSize=" + Str(DataSize))
	
	If *Data = 0 Or DataSize <= 0
		ProcedureReturn
	EndIf
	
	If Not FindMapElement(Clients(), Key)
		ProcedureReturn
	EndIf
	
	; Ensure buffer exists
	If Not Clients()\ReceiveBuffer
		Clients()\ReceiveBuffer = AllocateMemory(#BUFFER_SIZE)
		Clients()\BufferSize = #BUFFER_SIZE
		Clients()\BufferUsed = 0
	EndIf
	
	; Check if we need to grow buffer
	If Clients()\BufferUsed + DataSize > Clients()\BufferSize
		Protected NewSize.i = Clients()\BufferSize * 2
		While NewSize < Clients()\BufferUsed + DataSize
			NewSize * 2
		Wend
		
		If NewSize > #MAX_MESSAGE_SIZE
			LogError("ProcessReceivedData: Buffer overflow for ClientID " + Str(ClientID))
			Clients()\BufferUsed = 0
			ProcedureReturn
		EndIf
		
		Protected *NewBuffer = ReAllocateMemory(Clients()\ReceiveBuffer, NewSize)
		If *NewBuffer
			Clients()\ReceiveBuffer = *NewBuffer
			Clients()\BufferSize = NewSize
		Else
			LogError("ProcessReceivedData: Failed to reallocate buffer")
			ProcedureReturn
		EndIf
	EndIf
	
	; Append new data
	CopyMemory(*Data, Clients()\ReceiveBuffer + Clients()\BufferUsed, DataSize)
	Clients()\BufferUsed + DataSize
	
	; Process complete messages
	Protected MessageCount.i = 0
	Protected Offset.i = 0
	
	While Offset + 8 <= Clients()\BufferUsed
		Protected MessageLength.i = PeekL(Clients()\ReceiveBuffer + Offset)
		
		; Validate message length
		If MessageLength < 8 Or MessageLength > #MAX_MESSAGE_SIZE
			LogError("ProcessReceivedData: Invalid message length: " + Str(MessageLength))
			Clients()\BufferUsed = 0
			Break
		EndIf
		
		; Check if we have the complete message
		If Offset + MessageLength > Clients()\BufferUsed
			Break ; Wait for more data
		EndIf
		
		; Extract command and data
		Protected CommandID.i = PeekL(Clients()\ReceiveBuffer + Offset + 4)
		Protected *MessageData = 0
		Protected MessageDataSize.i = MessageLength - 8
		
		If MessageDataSize > 0
			*MessageData = Clients()\ReceiveBuffer + Offset + 8
		EndIf
		
		ProcessMessage(ClientID, CommandID, *MessageData, MessageDataSize)
		MessageCount + 1
		
		; Re-find client
		If Not FindMapElement(Clients(), Key)
			ProcedureReturn
		EndIf
		
		Offset + MessageLength
	Wend
	
	; Remove processed data
	If Offset > 0
		If Offset < Clients()\BufferUsed
			MoveMemory(Clients()\ReceiveBuffer + Offset, Clients()\ReceiveBuffer, Clients()\BufferUsed - Offset)
		EndIf
		Clients()\BufferUsed - Offset
	EndIf
	
	LogDebug("ProcessReceivedData: Processed " + Str(MessageCount) + " messages, remaining: " + Str(Clients()\BufferUsed))
EndProcedure

;- Main Server Loop
Procedure Main()
	InitLog()
	
	LogString("===========================================")
	LogString("TCP Relay Server (Binary Protocol) starting...")
	LogString("===========================================")
	
	ServerSocket = CreateNetworkServer(#PB_Any, #SERVER_PORT, #PB_Network_TCP)
	If Not ServerSocket
		LogError("Failed to create server on port " + Str(#SERVER_PORT))
		CloseLog()
		ProcedureReturn 1
	EndIf
	
	LogString("Server started on port " + Str(#SERVER_PORT))
	LogString("Passcode: " + #SECRET_PASSCODE)
	LogString("Max players per lobby: " + Str(#MAX_PLAYERS_PER_LOBBY))
	LogString("===========================================")
	
	Protected *Buffer = AllocateMemory(#BUFFER_SIZE)
	Protected Event.i, ClientID.i, ReceivedSize.i
	
	Repeat
		Event = NetworkServerEvent()
		
		Select Event
			Case #PB_NetworkEvent_Connect
				ClientID = EventClient()
				Protected Key.s = ClientKey(ClientID)
				
				Clients(Key)\ClientID = ClientID
				Clients(Key)\Nickname = "Unknown"
				Clients(Key)\LastActivity = ElapsedMilliseconds()
				Clients(Key)\Authenticated = #False
				Clients(Key)\ReceiveBuffer = 0
				Clients(Key)\BufferSize = 0
				Clients(Key)\BufferUsed = 0
				
				LogString("CONNECT: New client (ClientID: " + Str(ClientID) + ")")
				
			Case #PB_NetworkEvent_Data
				ClientID = EventClient()
				ReceivedSize = ReceiveNetworkData(ClientID, *Buffer, #BUFFER_SIZE)
				If ReceivedSize > 0
					ProcessReceivedData(ClientID, *Buffer, ReceivedSize)
				EndIf
				
			Case #PB_NetworkEvent_Disconnect
				ClientID = EventClient()
				HandleClientDisconnect(ClientID)
				
			Case #PB_NetworkEvent_None
				Delay(1)
		EndSelect
	ForEver
	
	LogString("Server shutting down...")
	FreeMemory(*Buffer)

	CloseNetworkServer(ServerSocket)
	LogString("Server stopped.")
	CloseLog()
	
	ProcedureReturn 0
EndProcedure

;- Entry Point
OpenConsole("TCP Relay Server (Binary Protocol)")
Main()
Input()
CloseConsole()
; IDE Options = PureBasic 6.30 beta 4 (Windows - x64)
; ExecutableFormat = Console
; CursorPosition = 445
; FirstLine = 100
; Folding = AAAC6
; Optimizer
; EnableXP
; DPIAware
; Executable = ThaiSpirit.exe
; CPU = 5
; Compiler = PureBasic 6.30 beta 4 - C Backend (Windows - x64)