import UIKit

/// Physical key labels and keystrokes only; composition and conversion stay in Engine.
@MainActor
final class JapaneseNineKeyView: UIStackView {
  struct Key {
    let kana: [String]
    let strokes: [String]
  }
  static let keys: [Key] = [
    Key(kana: ["あ", "い", "う", "え", "お"], strokes: ["a", "i", "u", "e", "o"]),
    Key(kana: ["か", "き", "く", "け", "こ"], strokes: ["ka", "ki", "ku", "ke", "ko"]),
    Key(kana: ["さ", "し", "す", "せ", "そ"], strokes: ["sa", "shi", "su", "se", "so"]),
    Key(kana: ["た", "ち", "つ", "て", "と"], strokes: ["ta", "chi", "tsu", "te", "to"]),
    Key(kana: ["な", "に", "ぬ", "ね", "の"], strokes: ["na", "ni", "nu", "ne", "no"]),
    Key(kana: ["は", "ひ", "ふ", "へ", "ほ"], strokes: ["ha", "hi", "fu", "he", "ho"]),
    Key(kana: ["ま", "み", "む", "め", "も"], strokes: ["ma", "mi", "mu", "me", "mo"]),
    // 左右是「」。Apple かなキーボード, Gboard and ATOK all put the Japanese quotes here, and they
    // have no other home on a kana keyboard; the full-width parentheses that were here are rare in
    // Japanese and their empty strokes routed them through the punctuation path, which commits.
    Key(kana: ["や", "「", "ゆ", "」", "よ"], strokes: ["ya", "", "yu", "", "yo"]),
    Key(kana: ["ら", "り", "る", "れ", "ろ"], strokes: ["ra", "ri", "ru", "re", "ro"]),
    // ー 有 stroke。An empty one sent it down the punctuation path, which the bridge could not
    // carry (it takes single-byte ASCII) and which therefore committed the composition and dropped
    // a bare ー beside it -- so ラーメン came out as three separate pieces.
    Key(kana: ["わ", "を", "ん", "ー", "〜"], strokes: ["wa", "wo", "n'", "-", ""]),
    // 第四行右端的标点键。These had no home on the kana layout at all: the shared punctuation key is
    // hidden whenever the kana grid is up, so 、 and 。 -- which end every Japanese sentence -- could
    // only be reached by switching to the symbol page and back.
    Key(kana: ["、", "。", "？", "！", "…"], strokes: ["", "", "", "", ""]),
  ]
  var onInput: ((String) -> Void)?
  var onSymbol: ((String) -> Void)?
  var onDelete: (() -> Void)?
  /// 小゛゜。一次点击把刚打的假名换成下一个变体,由 Engine 决定循环到哪一个。
  var onVariant: (() -> Void)?
  private var rows: [UIStackView] = []
  private var keyButtons: [UIButton] = []
  private let preview = KanaFlickPreview()

  /// makeDelete 单独传进来,因为假名键盘的删除键必须和别处一样支持长按连删 —— 它是全键盘
  /// 唯一用普通按键做删除的地方,而按一次只退一个罗马字母,删一句话要几十次点击。
  init(makeKey: (String, String, @escaping () -> Void) -> UIButton, makeDelete: () -> UIButton) {
    super.init(frame: .zero)
    axis = .horizontal
    spacing = 6
    accessibilityIdentifier = "japaneseNineKey"
    let grid = UIStackView()
    grid.axis = .vertical; grid.distribution = .fillEqually; grid.spacing = 7
    addArrangedSubview(grid)
    for rowIndex in 0..<3 {
      let row = UIStackView(); row.distribution = .fillEqually; row.spacing = 6
      rows.append(row); grid.addArrangedSubview(row)
      for column in 0..<3 {
        let index = rowIndex * 3 + column
        row.addArrangedSubview(makeKanaKey(index, factory: makeKey))
      }
    }
    let side = UIStackView()
    side.axis = .vertical; side.distribution = .fillEqually; side.spacing = 7
    rows.append(side)
    addArrangedSubview(side)
    side.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.19).isActive = true
    // 后置修饰键,不是选择器。Every Japanese keyboard modifies the kana just typed: か→が→か,
    // は→ば→ぱ→は, つ→っ→づ→つ. This was a three-level menu of 36 fresh kana, so か followed by
    // picking が produced かが, and one dakuten cost three taps and a visual search through a menu
    // that covered the candidate strip.
    let variants = makeKey("小゛゜", "小書き、濁点、半濁点", { [weak self] in self?.onVariant?() })
    variants.accessibilityIdentifier = "japaneseVariants"
    variants.accessibilityHint = "直前のかなを小書き・濁点・半濁点に切り替えます"
    variants.configuration?.contentInsets = .zero
    variants.titleLabel?.adjustsFontSizeToFitWidth = true
    variants.titleLabel?.minimumScaleFactor = 0.6
    // 第四行:小゛゜ / わ / 、。 —— 每块日语键盘十几年不变的位置。わ used to sit alone in the right
    // column and the bottom row did not exist, so the key a Japanese typist reaches for by muscle
    // memory was somewhere else entirely.
    let fourth = UIStackView(); fourth.distribution = .fillEqually; fourth.spacing = 6
    rows.append(fourth); grid.addArrangedSubview(fourth)
    fourth.addArrangedSubview(variants)
    fourth.addArrangedSubview(makeKanaKey(9, factory: makeKey))
    fourth.addArrangedSubview(makeKanaKey(10, factory: makeKey))
    let delete = makeDelete()
    delete.accessibilityIdentifier = "japaneseDelete"
    side.addArrangedSubview(delete)
  }
  required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private func makeKanaKey(_ index: Int, factory: (String, String, @escaping () -> Void) -> UIButton) -> UIButton {
    let key = Self.keys[index]
    let button = factory(key.kana[0], key.kana.joined(separator: "、"), { [weak self] in self?.select(index, direction: 0) })
    button.accessibilityIdentifier = "japaneseKana\(index)"
    // 日语键面上的说明用日语。A Japanese typist reading 轻点输入 recognised none of it; these are
    // the terms their own keyboards use.
    button.accessibilityHint = "タップで\(key.kana[0])、左・上・右・下にフリックで他のかな、長押しで一覧"
    button.configuration?.subtitle = key.kana.dropFirst().joined(separator: " ")
    button.configuration?.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
      var attributes = $0; attributes.font = .systemFont(ofSize: 10); return attributes
    }
    button.configuration?.contentInsets = .init(top: 2, leading: 0, bottom: 2, trailing: 0)
    button.menu = UIMenu(children: key.kana.enumerated().map { direction, kana in
      UIAction(title: kana) { [weak self] _ in self?.select(index, direction: direction) }
    })
    let pan = KanaFlickGesture { [weak self, weak button] direction, phase in
      guard let self, let button else { return }
      switch phase {
      case .ended:
        select(index, direction: direction)
        preview.hide()
      case .cancelled:
        preview.hide()
      case .moving:
        // 十字导览,而不是改键面。Writing the target onto the key the finger is covering meant the
        // one thing the user could not see was the thing they were choosing.
        preview.show(key.kana, highlighting: direction, over: button, in: self)
      }
    }
    button.addGestureRecognizer(pan)
    keyButtons.append(button)
    return button
  }
  func select(_ index: Int, direction: Int) {
    guard Self.keys.indices.contains(index), Self.keys[index].kana.indices.contains(direction) else { return }
    let key = Self.keys[index]
    if key.strokes[direction].isEmpty { onSymbol?(key.kana[direction]) }
    else { onInput?(key.strokes[direction]) }
  }
  func applyLayout() {
    let layout = KeyboardLayoutPreference.geometry
    spacing = layout.keySpacing
    for row in rows { row.spacing = row.axis == .vertical ? layout.rowSpacing : layout.keySpacing }
    (arrangedSubviews.first as? UIStackView)?.spacing = layout.rowSpacing
  }
}

/// 滑动时浮在键上方的十字导览。
///
/// Every Japanese flick keyboard shows one: the four directions around the centre, with the one the
/// finger is heading towards picked out. Without it the only feedback was the key's own title
/// changing underneath the finger covering it.
@MainActor
private final class KanaFlickPreview: UIView {
  private let labels: [UILabel] = (0..<5).map { _ in
    let label = UILabel()
    label.textAlignment = .center
    label.font = .systemFont(ofSize: 19, weight: .medium)
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }

  init() {
    super.init(frame: .zero)
    isUserInteractionEnabled = false
    isHidden = true
    let skin = KeyboardSkinPreference.selected
    backgroundColor = skin.keyBackground
    layer.cornerRadius = 12
    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOpacity = 0.22
    layer.shadowRadius = 8
    layer.shadowOffset = CGSize(width: 0, height: 3)
    for label in labels { addSubview(label) }
    let cell: CGFloat = 44
    // 中心、左、上、右、下 —— 和 Key.kana 的顺序一致。
    let offsets: [(CGFloat, CGFloat)] = [(0, 0), (-1, 0), (0, -1), (1, 0), (0, 1)]
    for (label, offset) in zip(labels, offsets) {
      NSLayoutConstraint.activate([
        label.widthAnchor.constraint(equalToConstant: cell),
        label.heightAnchor.constraint(equalToConstant: cell),
        label.centerXAnchor.constraint(equalTo: centerXAnchor, constant: offset.0 * cell),
        label.centerYAnchor.constraint(equalTo: centerYAnchor, constant: offset.1 * cell),
      ])
    }
    NSLayoutConstraint.activate([
      widthAnchor.constraint(equalToConstant: cell * 3),
      heightAnchor.constraint(equalToConstant: cell * 3),
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func show(_ kana: [String], highlighting direction: Int, over key: UIView, in host: UIView) {
    let skin = KeyboardSkinPreference.selected
    backgroundColor = skin.keyBackground
    for (index, label) in labels.enumerated() {
      let text = index < kana.count ? kana[index] : ""
      label.text = text
      label.isHidden = text.isEmpty
      let chosen = index == direction
      label.textColor = chosen ? skin.actionForeground : skin.keyForeground
      label.backgroundColor = chosen ? skin.accent : .clear
      label.layer.cornerRadius = 10
      label.clipsToBounds = true
    }
    if superview !== host { host.addSubview(self) }
    host.bringSubviewToFront(self)
    translatesAutoresizingMaskIntoConstraints = true
    let origin = key.convert(CGPoint(x: key.bounds.midX, y: key.bounds.midY), to: host)
    center = CGPoint(x: origin.x, y: origin.y - bounds.height / 2 - 6)
    isHidden = false
  }

  func hide() { isHidden = true }
}

@MainActor
private final class KanaFlickGesture: UIPanGestureRecognizer {
  /// 取消和结束必须分得开:取消时既不该上屏,也不该把导览留在屏幕上。
  enum Phase { case moving, ended, cancelled }
  private let feedback: (Int, Phase) -> Void
  init(feedback: @escaping (Int, Phase) -> Void) {
    self.feedback = feedback
    super.init(target: nil, action: nil)
    addTarget(self, action: #selector(update))
    maximumNumberOfTouches = 1
    cancelsTouchesInView = true
  }
  @objc private func update() {
    let offset = translation(in: view)
    let direction: Int
    if max(abs(offset.x), abs(offset.y)) < 12 { direction = 0 }
    else if abs(offset.x) > abs(offset.y) { direction = offset.x < 0 ? 1 : 3 }
    else { direction = offset.y < 0 ? 2 : 4 }
    if state == .cancelled || state == .failed { feedback(0, .cancelled) }
    else { feedback(direction, state == .ended ? .ended : .moving) }
  }
}
