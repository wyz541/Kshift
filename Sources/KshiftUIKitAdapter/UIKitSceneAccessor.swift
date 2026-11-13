#if canImport(UIKit)
  import SwiftUI
  import UIKit

  @MainActor
  public struct UIKitSceneAccessor: UIViewControllerRepresentable {
    private let onActivationChanged: @MainActor (Bool) -> Void

    public init(onActivationChanged: @escaping @MainActor (Bool) -> Void) {
      self.onActivationChanged = onActivationChanged
    }

    public func makeUIViewController(context: Context) -> SceneObservationViewController {
      SceneObservationViewController(onActivationChanged: onActivationChanged)
    }

    public func updateUIViewController(
      _ uiViewController: SceneObservationViewController,
      context: Context
    ) {
      uiViewController.onActivationChanged = onActivationChanged
      uiViewController.reportActivation()
    }

    @MainActor
    public final class SceneObservationViewController: UIViewController {
      var onActivationChanged: (@MainActor (Bool) -> Void)?

      init(onActivationChanged: @escaping @MainActor (Bool) -> Void) {
        self.onActivationChanged = onActivationChanged
        super.init(nibName: nil, bundle: nil)
      }

      @available(*, unavailable)
      required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
      }

      public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        reportActivation()
      }

      public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        onActivationChanged?(false)
      }

      func reportActivation() {
        let isActive = view.window?.windowScene?.activationState == .foregroundActive
        onActivationChanged?(isActive)
      }
    }
  }
#endif
