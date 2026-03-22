import Foundation

enum AppError: LocalizedError {
    case unauthorized
    case forbidden
    case serverError(String)
    case networkError(Error)
    case decodingError(Error)
    case keychainError(OSStatus)
    case unknown

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Sesión expirada. Por favor, inicia sesión nuevamente."
        case .forbidden:
            return "No tienes permisos para realizar esta acción."
        case .serverError(let message):
            return "Error del servidor: \(message)"
        case .networkError(let error):
            return "Error de red: \(error.localizedDescription)"
        case .decodingError:
            return "Error al procesar la respuesta del servidor."
        case .keychainError(let status):
            return "Error de Keychain (código: \(status))."
        case .unknown:
            return "Ha ocurrido un error inesperado."
        }
    }
}
