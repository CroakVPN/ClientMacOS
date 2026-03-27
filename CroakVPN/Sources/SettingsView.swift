import SwiftUI

struct SettingsView: View {
    @ObservedObject var vm: AppViewModel
    @EnvironmentObject var launchManager: LaunchAtLoginManager
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteConfirm = false

    var body: some View {
        ZStack {
            Color(red: 0.11, green: 0.12, blue: 0.15)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundColor(.white)

                    Text("Настройки")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)

                    Spacer()

                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                Divider()
                    .background(Color.gray.opacity(0.3))
                    .padding(.top, 12)

                VStack(alignment: .leading, spacing: 20) {

                    // MARK: - Подписка
                    Text("Подписка")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.gray)

                    Button(action: {
                        Task {
                            await vm.refreshSubscription()
                            dismiss()
                        }
                    }) {
                        Text("Обновить подписку")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(red: 0.30, green: 0.78, blue: 0.35))
                            )
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)

                    Button(action: { showDeleteConfirm = true }) {
                        Text("Удалить подписку")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.red, lineWidth: 1.5)
                            )
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .background(Color.gray.opacity(0.3))

                    // MARK: - Система
                    Text("Система")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.gray)

                    // Автозапуск toggle
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Запускать при входе в систему")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                            Text("CroakVPN будет стартовать автоматически")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { launchManager.isEnabled },
                            set: { _ in launchManager.toggle() }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }

                    if let error = vm.errorMessage {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer()
            }
        }
        .frame(width: 340, height: 360)
        .alert("Удалить подписку?", isPresented: $showDeleteConfirm) {
            Button("Удалить", role: .destructive) {
                vm.clearSubscription()
                dismiss()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("VPN будет отключён, конфигурация удалена.")
        }
    }
}
