import SwiftUI

struct SubscriptionSetupView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(onSettings: {})

            Spacer()

            VStack(spacing: 20) {
                // Frog icon placeholder
                Image(systemName: "shield.checkered")
                    .font(.system(size: 48))
                    .foregroundColor(Color(red: 0.30, green: 0.78, blue: 0.35))

                Text("Добавьте подписку")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)

                Text("Вставьте URL подписки из\n@croakvpnbot")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)

                TextField("https://...", text: $vm.subscriptionURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(red: 0.14, green: 0.15, blue: 0.18))
                    )
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)

                if let error = vm.errorMessage {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .padding(.horizontal, 24)
                }

                Button(action: {
                    Task { await vm.addSubscription() }
                }) {
                    Group {
                        if vm.isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                                .tint(.white)
                        } else {
                            Text("Подключить")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(red: 0.30, green: 0.78, blue: 0.35))
                    )
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .disabled(vm.isLoading)
                .padding(.horizontal, 24)
            }

            Spacer()

            FooterView()
                .padding(.bottom, 12)
        }
    }
}
