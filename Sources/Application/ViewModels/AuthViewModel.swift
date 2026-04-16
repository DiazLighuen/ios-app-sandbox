import Foundation
import GoogleSignIn

@MainActor
final class AuthViewModel: ObservableObject {
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isLoading = false
    @Published private(set) var currentUser: CurrentUser?
    @Published var error: AppError?

    private let authAPI: AuthRepository
    private let keychain = KeychainService.shared

    init(authAPI: AuthRepository = AuthAPI()) {
        self.authAPI = authAPI
        // Restaurar sesión desde Keychain al arrancar
        if let token = try? keychain.getToken() {
            self.isAuthenticated = true
            self.currentUser = CurrentUser.from(jwt: token)
        }
    }

    func signInWithGoogle(presenting viewController: UIViewController) async {
        isLoading = true
        defer { isLoading = false }

        do {
            configureForLogin()
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: viewController
            )
            guard let idToken = result.user.idToken?.tokenString else {
                error = .unknown
                return
            }

            let jwt = try await authAPI.loginWithGoogle(idToken: idToken)
            try keychain.saveToken(jwt)
            currentUser = CurrentUser.from(jwt: jwt)
            isAuthenticated = true
        } catch AppError.unauthorized {
            error = .serverError("Esta cuenta no tiene acceso. Iniciá sesión con tu cuenta personal de Google. Si querés usar tu canal de YouTube, podés vincularlo desde la pestaña Watch una vez que estés dentro.")
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .networkError(error)
        }
    }

    /// Sign in with a (potentially different) Google account specifically for YouTube.
    /// The user can select their YouTube channel account here — the JWT stays unchanged.
    /// After success, GIDSignIn.currentUser becomes the selected account, so YouTubeAPI
    /// will use its access token as X-Google-Token in all subsequent requests.
    func linkYouTubeAccount(presenting viewController: UIViewController) async {
        isLoading = true
        defer { isLoading = false }

        do {
            configureForYouTube()
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: viewController,
                hint: nil,
                additionalScopes: ["https://www.googleapis.com/auth/youtube.readonly"]
            )
            if let code = result.serverAuthCode {
                try await authAPI.linkYouTube(serverAuthCode: code)
            }
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .networkError(error)
        }
    }

    /// Restores the Google Sign-In session silently on app launch.
    /// Must be called at startup so GIDSignIn.sharedInstance.currentUser is available
    /// for YouTube API calls without requiring the user to sign in again.
    func restoreGoogleSession() async {
        guard isAuthenticated else { return }
        _ = try? await GIDSignIn.sharedInstance.restorePreviousSignIn()
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        try? keychain.deleteToken()
        currentUser = nil
        isAuthenticated = false
    }

    /// Login: solo clientID — el id_token mantiene la audiencia correcta para el backend.
    private func configureForLogin() {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String
        else { return }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    }

    /// YouTube linking: clientID + serverClientID para obtener serverAuthCode.
    private func configureForYouTube() {
        guard AppConfig.googleServerClientID != "YOUR_WEB_CLIENT_ID",
              let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String
        else { return }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: clientID,
            serverClientID: AppConfig.googleServerClientID
        )
    }

    /// Llamar cuando se recibe un 401 en cualquier request — JWT expirado.
    func handleUnauthorized() {
        signOut()
        error = .serverError("Tu sesión expiró. Iniciá sesión nuevamente.")
    }
}
