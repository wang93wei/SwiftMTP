package main

import "testing"

func TestTransferTaskCancellationState(t *testing.T) {
	cancelledTasks.Range(func(k, _ any) bool {
		cancelledTasks.Delete(k)
		return true
	})

	const taskID = "transfer-task-1"
	if isTaskCancelled(taskID) {
		t.Fatalf("task should not be cancelled before mark")
	}

	markTaskCancelled(taskID)
	if !isTaskCancelled(taskID) {
		t.Fatalf("task should be cancelled after mark")
	}

	const otherTaskID = "transfer-task-2"
	if isTaskCancelled(otherTaskID) {
		t.Fatalf("other task should remain not cancelled")
	}
}

func TestSetProgressCallbackNoop(t *testing.T) {
	Kalam_SetProgressCallback(0)
}
