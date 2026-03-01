// Feather disable all

function __outatimeEnsureChildID(_scope)
{
	static _outatime = __outatime();
	
	var _child_id = variable_instance_get(_scope, Outatime_ID_VARIABLE_NAME);
	if (_child_id == undefined)
	{
		_outatime.__uniqueID++;
		
		_child_id = _outatime.__uniqueID;
		variable_instance_set(_scope, Outatime_ID_VARIABLE_NAME, _child_id);
	}
	
	return _child_id;
}
