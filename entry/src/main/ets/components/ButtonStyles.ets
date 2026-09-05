export class ActionButtonStyle implements AttributeModifier<ButtonAttribute> {
  private background: ResourceColor
  private foreground: ResourceColor

  constructor(background: ResourceColor, foreground: ResourceColor) {
    this.background = background
    this.foreground = foreground
  }

  applyNormalAttribute(button: ButtonAttribute): void {
    button.height($r('app.float.button_height'))
      .fontSize($r('app.float.button_font_size'))
      .fontWeight(FontWeight.Medium)
      .borderRadius($r('app.float.button_radius'))
      .backgroundColor(this.background)
      .fontColor(this.foreground)
      .hoverEffect(HoverEffect.Auto)
  }
}

export class CompactActionStyle implements AttributeModifier<ButtonAttribute> {
  applyNormalAttribute(button: ButtonAttribute): void {
    new ActionButtonStyle($r('app.color.button_action_background'), $r('app.color.button_action_text'))
      .applyNormalAttribute(button)
    button.height($r('app.float.button_compact_height'))
      .fontSize($r('app.float.button_compact_font_size'))
      .fontWeight(FontWeight.Normal)
      .responseRegion({ x: 0, y: $r('app.float.button_compact_hit_offset'), width: '100%', height: $r('app.float.button_height') })
  }
}
