//
//  CabinetView.swift
//  Cabinet
//
//  Created by muukii on 9/22/18.
//  Copyright © 2018 muukii. All rights reserved.
//

import UIKit

public final class CabinetView : UIView {

  public enum State {
    case closed
    case opened
    case halfOpened
  }

  private struct Config {

    private var storage : [State : CGFloat] = [:]

    func translateY(for state: State) -> CGFloat {
      return storage[state]!
    }

    mutating func setTranslateY(closed: CGFloat, opened: CGFloat, halfOpened: CGFloat) {

      assert(opened < halfOpened && halfOpened < closed)

      storage = [
        State.closed : closed,
        State.halfOpened : halfOpened,
        State.opened : opened,
      ]
    }

  }

  private var top: NSLayoutConstraint!

  private let backdropView = TouchThroughView()

  private let containerView = UIView()

  private var config: Config = .init()

  private var containerDraggingAnimator: UIViewPropertyAnimator?

  private var dimmingAnimator: UIViewPropertyAnimator?

  private var runningAnimators: [UIViewPropertyAnimator] = []

  var currentState: State = .opened

  public override init(frame: CGRect) {
    super.init(frame: .zero)
    setup()
  }

  public required init?(coder aDecoder: NSCoder) {
    super.init(coder: aDecoder)
    setup()
  }

  private func setup() {

    containerView.translatesAutoresizingMaskIntoConstraints = false

    addSubview(backdropView)
    backdropView.frame = bounds
    backdropView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

    addSubview(containerView)

    #if DEBUG
    containerView.backgroundColor = UIColor.init(white: 0.6, alpha: 1)
    #endif

    top = containerView.topAnchor.constraint(equalTo: topAnchor, constant: 64)

    let height = containerView.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 1, constant: -44)
    height.priority = .defaultHigh

    NSLayoutConstraint.activate([
      top,
      containerView.rightAnchor.constraint(equalTo: rightAnchor, constant: 0),
      height,
      containerView.bottomAnchor.constraint(greaterThanOrEqualTo: bottomAnchor, constant: 0),
      containerView.leftAnchor.constraint(equalTo: leftAnchor, constant: 0),
      ])

    gesture: do {

      let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
      containerView.addGestureRecognizer(pan)
    }

  }

  @objc private func handlePan(gesture: UIPanGestureRecognizer) {

    switch gesture.state {
    case .began:
      animateTransitionIfNeeded()
      startInteractiveTransition()
      fallthrough
    case .changed:

      let translation = gesture.translation(in: gesture.view!)

      let nextConstant = containerView.frame.origin.y + translation.y

      if case config.translateY(for: .opened)...config.translateY(for: .closed) = nextConstant {
        containerView.frame.origin.y += translation.y
      } else {
        containerView.frame.origin.y += translation.y * 0.1
      }

      top.constant = containerView.frame.origin.y

      let halfToOpenProgress = CalcBox.init(top.constant)
        .progress(start: config.translateY(for: .halfOpened), end: config.translateY(for: .opened))
        .clip(min: 0, max: 1)
        .value.fractionCompleted

      let closedToHalfProgress = CalcBox.init(top.constant)
        .progress(start: config.translateY(for: .closed), end: config.translateY(for: .halfOpened))
        .clip(min: 0, max: 1)
        .value.fractionCompleted

      let wholeProgress = CalcBox.init(top.constant)
        .progress(start: config.translateY(for: .closed), end: config.translateY(for: .opened))
        .clip(min: 0, max: 1)
        .value.fractionCompleted

      print(halfToOpenProgress, closedToHalfProgress, wholeProgress)

      runningAnimators.forEach {
        $0.fractionComplete = halfToOpenProgress
      }

    case .ended, .cancelled, .failed:

      let target = targetForEndDragging(velocity: gesture.velocity(in: gesture.view!))
      continueInteractiveTransition(target: target, velocity: gesture.velocity(in: gesture.view!))
    default:
      break
    }

    gesture.setTranslation(.zero, in: gesture.view!)
  }

  private func animateTransitionIfNeeded() {

    containerDraggingAnimator?.stopAnimation(true)

    if runningAnimators.isEmpty {

      print("Create new animators")

      let dimmingColor = UIColor(white: 0, alpha: 0.2)

      self.backdropView.backgroundColor = .clear

      let animator = UIViewPropertyAnimator(
        duration: 0.3,
        curve: .easeOut) {

          self.backdropView.backgroundColor = dimmingColor
      }

      dimmingAnimator = animator

      animator.startAnimation()
      animator.addCompletion { _ in
        self.runningAnimators.removeAll { $0 == animator }
      }

      runningAnimators.append(animator)
    } else {
      runningAnimators.forEach {
        $0.isReversed = false
      }
    }
  }

  private func startInteractiveTransition() {

    runningAnimators.forEach {
      $0.pauseAnimation()
    }
  }

  public override func layoutSubviews() {
    super.layoutSubviews()

    let height = containerView.bounds.height

    config.setTranslateY(
      closed: height - 88,
      opened: 44,
      halfOpened: height - 240
    )

  }

  private func continueInteractiveTransition(target: State, velocity: CGPoint) {

    let targetTranslateY = config.translateY(for: target)
    let currentTranslateY = top.constant

    func makeVelocity() -> CGVector {

      let base = CGVector(
        dx: 0,
        dy: targetTranslateY - currentTranslateY
      )

      var initialVelocity = CGVector(
        dx: 0,
        dy: min(abs(velocity.y / base.dy), 18)
      )

      if initialVelocity.dy.isInfinite || initialVelocity.dy.isNaN {
        initialVelocity.dy = 0
      }

      return initialVelocity
    }

    let animator = UIViewPropertyAnimator.init(
      duration: 0.4,
      timingParameters: UISpringTimingParameters(
        mass: 4.5,
        stiffness: 300,
        damping: 300, initialVelocity: makeVelocity()
      )
    )

    // flush pending updates
    self.layoutIfNeeded()

    animator
      .addAnimations {
        self.top.constant = targetTranslateY
        self.setNeedsLayout()
        self.layoutIfNeeded()
    }

    animator.startAnimation()

    containerDraggingAnimator = animator

    if currentState == .opened {

    } else {

    }

    switch (currentState, target) {
    case (.closed, .closed), (.opened, .closed), (.opened, .halfOpened), (.halfOpened, .closed), (.closed, .halfOpened):
      runningAnimators.forEach {
        $0.isReversed = true
      }
    case (.halfOpened, .halfOpened), (.opened, .opened), (.closed, .opened), (.halfOpened, .opened):
      runningAnimators.forEach {
        $0.isReversed = false
      }
    }

    switch target {
    case .closed, .halfOpened:
//      runningAnimators.forEach {
//        $0.isReversed = true
//      }
      break
    case .opened:
      break
    }

    runningAnimators.forEach {
//      $0.stopAnimation(false)
//      $0.finishAnimation(at: .end)
      $0.continueAnimation(withTimingParameters: nil, durationFactor: 1)
    }

    currentState = target

  }

  private func targetForEndDragging(velocity: CGPoint) -> State {

    let ty = containerView.frame.origin.y
    let vy = velocity.y

    switch ty {
    case ...config.translateY(for: .opened):

      return .opened

    case config.translateY(for: .opened)..<config.translateY(for: .halfOpened):

      switch vy {
      case -20...20:
        let bound = (config.translateY(for: .halfOpened) - config.translateY(for: .opened)) / 2
        return bound < ty ? .halfOpened : .opened
      case ...(-20):
        return .opened
      case 20...:
        return .halfOpened
      default:
        assertionFailure()
        return .opened
      }

    case config.translateY(for: .halfOpened)..<config.translateY(for: .closed):

      switch vy {
      case -20...20:
        let bound = (config.translateY(for: .closed) - config.translateY(for: .halfOpened)) / 2
        return bound < ty ? .closed : .halfOpened
      case ...(-20):
        return .halfOpened
      case 20...:
        return .closed
      default:
        assertionFailure()
        return .closed
      }

    case config.translateY(for: .closed)...:

      return .closed

    default:
      assertionFailure()
      return .opened
    }
  }

}
