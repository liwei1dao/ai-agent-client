package container

// LimitedQueue 是一个具有有限容量的泛型队列
type LimitedQueue[T any] struct {
	capacity int
	queue    []T
}

// NewLimitedQueue 创建一个新的 LimitedQueue
func NewLimitedQueue[T any](capacity int) *LimitedQueue[T] {
	return &LimitedQueue[T]{
		capacity: capacity,
		queue:    make([]T, 0, capacity),
	}
}

// Enqueue 向队列中添加一个元素
func (lq *LimitedQueue[T]) Enqueue(value T) {
	if len(lq.queue) >= lq.capacity {
		lq.queue = lq.queue[1:]
	}
	lq.queue = append(lq.queue, value)
}

// Dequeue 从队列中移除最早添加的元素
func (lq *LimitedQueue[T]) Dequeue() *T {
	if len(lq.queue) == 0 {
		return nil
	}
	elem := lq.queue[0]
	lq.queue = lq.queue[1:]
	return &elem
}

// Len 返回队列的长度
func (lq *LimitedQueue[T]) Len() int {
	return len(lq.queue)
}

// Peek 返回队列的第一个元素但不移除它
func (lq *LimitedQueue[T]) Peek() *T {
	if len(lq.queue) == 0 {
		return nil
	}
	return &lq.queue[0]
}

// ToSlice 返回队列中所有元素的切片
func (lq *LimitedQueue[T]) ToSlice() []T {
	return append([]T(nil), lq.queue...)
}
