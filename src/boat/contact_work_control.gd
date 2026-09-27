extends RefCounted

## The worker and its owner share only this synchronized cancellation flag.
## No scene object or main-thread callback enters the numerical solver.
var mutex := Mutex.new()
var requested := false

func cancel() -> void:
	mutex.lock()
	requested=true
	mutex.unlock()

func cancelled() -> bool:
	mutex.lock()
	var value := requested
	mutex.unlock()
	return value
