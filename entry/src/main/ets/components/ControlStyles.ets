export class InputFieldStyle implements AttributeModifier<TextInputAttribute> {
  applyNormalAttribute(input: TextInputAttribute): void {
    input.backgroundColor($r('app.color.input_background'))
      .fontColor($r('app.color.input_text'))
      .placeholderColor($r('app.color.input_placeholder'))
      .caretColor($r('app.color.control_accent'))
      .borderRadius($r('app.float.button_radius'))
  }
}

export class ParameterSliderStyle implements AttributeModifier<SliderAttribute> {
  applyNormalAttribute(slider: SliderAttribute): void {
    slider.selectedColor($r('app.color.control_accent'))
      .trackColor($r('app.color.control_track'))
  }
}
