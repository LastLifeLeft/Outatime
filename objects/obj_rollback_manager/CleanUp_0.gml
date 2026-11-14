// A duplicate manager is destroyed in its Create event before it owns anything
if (!variable_instance_exists(id, "input_packet")) exit;

rollback_input_end();
buffer_delete(input_packet);

while (!ds_queue_empty(message_queue)) {
	var _msg = ds_queue_dequeue(message_queue);
	if (_msg.type == PAYLOAD.INPUT) buffer_delete(_msg.payload);
}
ds_queue_destroy(message_queue);
