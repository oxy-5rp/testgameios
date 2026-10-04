import SwiftUI
import SceneKit

@main
struct FigureGameApp: App {
    var body: some Scene {
        WindowGroup { ContentView().statusBarHidden().persistentSystemOverlays(.hidden) }
    }
}

struct ContentView: View {
    @StateObject private var game = Game()
    @State private var lastDrag = CGSize.zero

    var body: some View {
        ZStack {
            SceneView(scene: game.scene, pointOfView: game.camNode, options: [.rendersContinuously],
                      preferredFramesPerSecond: 60, antialiasingMode: .multisampling4X, delegate: game)
                .ignoresSafeArea()
            HStack(spacing: 0) {
                Color.clear
                Color.clear.contentShape(Rectangle())
                    .gesture(DragGesture().onChanged { v in
                        game.look(dx: v.translation.width - lastDrag.width, dy: v.translation.height - lastDrag.height)
                        lastDrag = v.translation
                    }.onEnded { _ in lastDrag = .zero })
            }
            VStack {
                HStack {
                    Label("\(game.score)/\(game.total)", systemImage: "star.fill")
                        .font(.title2.bold()).padding(10).background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                    Button { game.reset() } label: {
                        Image(systemName: "arrow.counterclockwise").font(.title2).padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                Spacer()
                HStack(alignment: .bottom) {
                    Joystick { game.move = $0 }.padding(.leading, 40)
                    Spacer()
                    Button { game.wantJump = true } label: {
                        Image(systemName: "arrow.up").font(.largeTitle.bold()).frame(width: 84, height: 84)
                            .background(.ultraThinMaterial, in: Circle())
                    }.padding(.trailing, 40)
                }
            }.padding()
            if game.won {
                Text("Победа! 🎉").font(.system(size: 48, weight: .heavy)).padding(30)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            }
        }
        .tint(.primary)
    }
}

struct Joystick: View {
    var onChange: (CGVector) -> Void
    @State private var knob = CGSize.zero
    private let r: CGFloat = 60

    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial).frame(width: r * 2, height: r * 2)
            Circle().fill(.white.opacity(0.85)).frame(width: 52, height: 52).offset(knob)
        }
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { v in
            let d = hypot(v.translation.width, v.translation.height)
            let k = min(d, r) / max(d, 1)
            knob = CGSize(width: v.translation.width * k, height: v.translation.height * k)
            onChange(CGVector(dx: knob.width / r, dy: knob.height / r))
        }.onEnded { _ in knob = .zero; onChange(.zero) })
    }
}
