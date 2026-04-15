import SwiftUI
import GoogleSignIn

struct LoginView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var pingResult: PingResult?
    @State private var isPinging = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .font(.system(size: 64))
                    .foregroundStyle(.primary)
                Text("Sandbox App")
                    .font(.largeTitle.bold())
                Text("Oracle Cloud — Local")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            GoogleSignInButton()
                .padding(.horizontal, 32)

            PingButton(isPinging: isPinging, result: pingResult) {
                Task { await ping() }
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .alert("Error", isPresented: .constant(authViewModel.error != nil)) {
            Button("OK") { authViewModel.error = nil }
        } message: {
            Text(authViewModel.error?.localizedDescription ?? "")
        }
    }

    private func ping() async {
        isPinging = true
        defer { isPinging = false }
        let start = Date()
        do {
            let url = HTTPClient.shared.baseURL
            let (_, response) = try await URLSession.shared.data(from: url)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            pingResult = .success(status: status, ms: ms)
        } catch {
            pingResult = .failure(error.localizedDescription)
        }
    }
}

private enum PingResult {
    case success(status: Int, ms: Int)
    case failure(String)
}

private struct PingButton: View {
    let isPinging: Bool
    let result: PingResult?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: action) {
                HStack {
                    if isPinging {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "network")
                    }
                    Text(isPinging ? "Probando..." : "Probar \(AppConfig.apiHost)")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isPinging)

            if let result {
                HStack(spacing: 6) {
                    switch result {
                    case .success(let status, let ms):
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("HTTP \(status) — \(ms) ms").foregroundStyle(.green)
                    case .failure(let msg):
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        Text(msg).foregroundStyle(.red).lineLimit(2)
                    }
                }
                .font(.caption)
            }
        }
    }
}

private struct GoogleSignInButton: UIViewRepresentable {
    @EnvironmentObject private var authViewModel: AuthViewModel

    func makeUIView(context: Context) -> GIDSignInButton {
        let button = GIDSignInButton()
        button.style = .wide
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: GIDSignInButton, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(authViewModel: authViewModel)
    }

    final class Coordinator: NSObject {
        let authViewModel: AuthViewModel

        init(authViewModel: AuthViewModel) {
            self.authViewModel = authViewModel
        }

        @objc func tapped() {
            guard let root = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first?.windows.first?.rootViewController else { return }
            Task {
                await authViewModel.signInWithGoogle(presenting: root)
            }
        }
    }
}
