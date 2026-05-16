import Foundation

extension APIDataService {
    // MARK: - Todo
    func fetchTodos() async throws -> [TodoItem] { try await get(path: APIEndpoint.todos) }
    func createTodo(_ todo: TodoItem) async throws -> TodoItem { try await post(path: APIEndpoint.todos, body: todo) }
    func updateTodo(_ todo: TodoItem) async throws -> TodoItem { try await put(path: APIEndpoint.todo(id: todo.id), body: todo) }
    func deleteTodo(id: String) async throws { try await delete(path: APIEndpoint.todo(id: id)) }
}
