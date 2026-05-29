import SwiftUI
import TreescopeViewerCore
import TreescopeProtocol

struct ConnectionView: View {
    @EnvironmentObject var session: InspectorSession
    @EnvironmentObject var browser: ServiceBrowser

    @State private var host = ProtocolConstants.loopbackHost
    @State private var portText = String(ProtocolConstants.defaultPort)

    var body: some View {
        VStack(spacing: 24) {
            header

            discovered

            Divider().frame(maxWidth: 360)

            manualEntry

            if case .failed(let message) = session.connectionState {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            if case .connecting = session.connectionState {
                ProgressView("Connecting…")
            }

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { browser.start() }
        .onDisappear { browser.stop() }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "binoculars.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Treescope")
                .font(.largeTitle.bold())
            Text("Connect to an app running the Treescope server")
                .foregroundStyle(.secondary)
        }
        .padding(.top, 20)
    }

    private var discovered: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Discovered")
                    .font(.headline)
                if browser.isBrowsing {
                    ProgressView().controlSize(.small)
                }
            }
            if browser.services.isEmpty {
                Text("No servers found on the local network yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(browser.services) { service in
                    Button {
                        Task { await session.connect(to: service.endpoint, name: service.name) }
                    } label: {
                        HStack {
                            Image(systemName: "dot.radiowaves.left.and.right")
                            Text(service.name)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 360, alignment: .leading)
    }

    private var manualEntry: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect manually")
                .font(.headline)
            HStack {
                TextField("Host", text: $host)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                TextField("Port", text: $portText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }
            Button {
                if let port = UInt16(portText) {
                    Task { await session.connect(host: host, port: port) }
                }
            } label: {
                Label("Connect", systemImage: "bolt.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(UInt16(portText) == nil)
        }
        .frame(width: 360)
    }
}
