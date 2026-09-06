export const DIALOG_MOTION_DURATION: number = 160

export function dialogFade(): TransitionEffect {
  return TransitionEffect.OPACITY.animation({ duration: DIALOG_MOTION_DURATION, curve: Curve.EaseOut })
}

export function dialogScale(): TransitionEffect {
  return TransitionEffect.scale({ x: 0.98, y: 0.98 })
    .animation({ duration: DIALOG_MOTION_DURATION, curve: Curve.EaseOut })
}
