#!/usr/bin/env python3
"""アプリアイコン（Icon Composer の .icon）をテーマカラー × ライト／ダークぶん作る。

ホーム画面のアイコンは iPhone 本体の外観にしか連動しないので、アプリ内の「ダークモード」に
合わせるために、外観で色が変わらない（ライト固定・ダーク固定の）アイコンを用意して切り替える。
  - ライト：白い背景に盤の色
  - ダーク：黒い背景に盤の色（ブラックのテーマだけ、黒い背景で見えるよう灰色の盤）

絵柄はレコードが2枚重なったもの（「Our」＝ふたりの音楽）。手前の盤はテーマカラー、
奥の盤はテーマカラーを背景の色に寄せて淡く（ダークでは暗く）する。
レイヤー（盤・溝と光・ラベル。奥の盤はラベルなし）の SVG もここで作り、WatashiToOngaku/AppIcon.icon/Assets に置いて共通で使う。
  python3 scripts/make_icons.py
"""
import json
import math
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "WatashiToOngaku"
TEMPLATE = ROOT / "AppIcon.icon"

WHITE = "srgb:1.00000,1.00000,1.00000,1.00000"
BLACK = "srgb:0.00000,0.00000,0.00000,1.00000"

# テーマ名（AppIconManager と同じ）→ (ライトの盤の色, ダークの盤の色)。ThemeStore.accents の primary
THEMES = {
    "": ((0.11, 0.11, 0.12), (0.35, 0.35, 0.37)),  # ブラック（標準のアイコン）
    "White": ((0.72, 0.72, 0.72), (0.72, 0.72, 0.72)),
    "Rose": ((0.898, 0.451, 0.600), (0.898, 0.451, 0.600)),
    "Coral": ((0.878, 0.482, 0.482), (0.878, 0.482, 0.482)),
    "Sunset": ((0.910, 0.537, 0.353), (0.910, 0.537, 0.353)),
    "Lemon": ((0.871, 0.761, 0.247), (0.871, 0.761, 0.247)),
    "Mint": ((0.298, 0.686, 0.510), (0.298, 0.686, 0.510)),
    "Sky": ((0.290, 0.565, 0.812), (0.290, 0.565, 0.812)),
    "Lavender": ((0.647, 0.482, 0.878), (0.647, 0.482, 0.878)),
}


PHI = (1 + 5 ** 0.5) / 2


def golden_records(size=1024):
    """2枚のレコードを黄金比で置く。
    - 手前の盤：アイコンの中央。直径 = アイコンの幅 ÷ φ
    - 奥の盤：直径 = 手前の直径 ÷ φ。中心の高さはアイコンの上から 1/φ² のところ（黄金分割の線）
    - 奥の盤は、中心を結ぶ線の上で「手前に隠れる部分 : 見える部分 = φ : 1」になるよう右にずらす
    """
    c = size / 2
    front = size / PHI / 2
    back = front / PHI
    visible = 2 * back / PHI ** 2
    distance = front + visible - back
    dy = c - size / PHI ** 2
    dx = (distance ** 2 - dy ** 2) ** 0.5
    return [("", (c, c), front), ("back-", (round(c + dx, 1), round(c - dy, 1)), round(back, 1))]


# 2枚のレコード：(名前の前置き, 中心, 半径)。上のものほど手前
RECORDS = golden_records()
# 奥の盤を背景の色にどれだけ寄せるか
BACK_FADE = 0.42


def srgb(rgb):
    return "srgb:" + ",".join(f"{v:.5f}" for v in rgb) + ",1.00000"


def mix(rgb, toward, amount):
    return tuple(a + (b - a) * amount for a, b in zip(rgb, toward))


def svg(body):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">\n'
            + body + "\n</svg>\n")


def record_svgs(center, radius):
    """1枚のレコードの絵（盤・溝と光・ラベル）。寸法は半径 360 の盤を基準に縮める"""
    cx, cy = center
    k = radius / 360

    def arc(r, start, end):
        x1, y1 = cx + r * math.cos(math.radians(start)), cy + r * math.sin(math.radians(start))
        x2, y2 = cx + r * math.cos(math.radians(end)), cy + r * math.sin(math.radians(end))
        return (f'<path d="M{x1:.1f},{y1:.1f} A{r:.0f},{r:.0f} 0 0 0 {x2:.1f},{y2:.1f}" fill="none" '
                f'stroke="#ffffff" stroke-opacity="0.35" stroke-width="{18 * k:.1f}" stroke-linecap="round"/>')

    disc = svg(f'<circle cx="{cx}" cy="{cy}" r="{radius}" fill="#1c1c1e"/>')
    rings = "".join(f'<circle cx="{cx}" cy="{cy}" r="{r * k:.0f}" fill="none" stroke="#ffffff" stroke-opacity="0.07" '
                    f'stroke-width="{3 * k:.1f}"/>' for r in range(330, 153, -22))
    # 左上と右下に光の筋
    shine = "".join(arc(r * k, start + flip, end + flip)
                    for flip in (0, 180) for r, start, end in ((280, -126, -166), (230, -123, -149)))
    grooves = svg(rings + "\n" + shine)
    def ring(r):
        # 円を2つの半円の弧で描く（直径と半径を同じ丸め方にして、形が崩れないようにする）
        r = round(r, 1)
        return f"M{cx - r:.1f},{cy} a{r},{r} 0 1,0 {2 * r:.1f},0 a{r},{r} 0 1,0 -{2 * r:.1f},0 Z"

    label = svg(f'<path fill-rule="evenodd" fill="#ffffff" d="{ring(118 * k)} {ring(18 * k)}"/>')
    return {"disc": disc, "grooves": grooves, "label": label}


def write_assets():
    assets = TEMPLATE / "Assets"
    shutil.rmtree(assets, ignore_errors=True)
    assets.mkdir(parents=True)
    for prefix, center, radius in RECORDS:
        for name, text in record_svgs(center, radius).items():
            if prefix and name == "label":
                continue
            (assets / f"{prefix}{name}.svg").write_text(text)


def layer(name, glass, fill=None):
    item = {"glass": glass, "image-name": f"{name}.svg", "name": name,
            "position": {"scale": 1, "translation-in-points": [0, 0]}}
    if fill:
        item["fill-specializations"] = fixed({"solid": srgb(fill)})
    return item


def make(background, disc):
    # 背景は「ライト」のときに自動のグラデーション、「ダーク」は黒一色。
    # ダーク用の値を書かないと iOS がダーク版を自動で作ってしまうので、同じ値を明示する
    back = mix(disc, (1, 1, 1) if background == WHITE else (0, 0, 0), BACK_FADE)
    # 奥の盤のラベルは手前の盤に隠れる（透けて縁だけ白く見えてしまう）ので描かない
    layers = [layer("label", True), layer("grooves", False), layer("disc", True, disc),
              layer("back-grooves", False), layer("back-disc", True, back)]
    return {
        "fill-specializations": fixed({"automatic-gradient": WHITE} if background == WHITE else {"solid": BLACK}),
        "groups": [{"layers": layers, "shadow": {"kind": "neutral", "opacity": 0.5},
                    "translucency": {"enabled": True, "value": 0.5}}],
        "supported-platforms": {"circles": ["watchOS"], "squares": "shared"},
    }


def fixed(value):
    """外観（ライト・ダーク）で変わらない値"""
    return [{"value": value}, {"appearance": "dark", "value": value}]


def write(path, icon):
    if path.resolve() != TEMPLATE.resolve():
        shutil.rmtree(path, ignore_errors=True)
        shutil.copytree(TEMPLATE / "Assets", path / "Assets")
    (path / "icon.json").write_text(json.dumps(icon, indent=2) + "\n")


def main():
    write_assets()
    names = []
    for theme, (light, dark) in THEMES.items():
        base = f"AppIcon-{theme}" if theme else "AppIcon"
        light_path = TEMPLATE if not theme else ROOT / "ThemeIcons" / f"{base}.icon"
        dark_name = f"{base}-Dark"
        write(ROOT / "ThemeIcons" / f"{dark_name}.icon", make(BLACK, dark))
        write(light_path, make(WHITE, light))
        names += ([base] if theme else []) + [dark_name]
    print("ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES:", " ".join(names))


if __name__ == "__main__":
    main()
