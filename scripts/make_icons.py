#!/usr/bin/env python3
"""アプリアイコン（Icon Composer の .icon）をテーマカラー × ライト／ダークぶん作る。

ホーム画面のアイコンは iPhone 本体の外観にしか連動しないので、アプリ内の「ダークモード」に
合わせるために、外観で色が変わらない（ライト固定・ダーク固定の）アイコンを用意して切り替える。
  - ライト：白い背景に盤の色
  - ダーク：黒い背景に盤の色（ブラックのテーマだけ、黒い背景で見えるよう灰色の盤）

レイヤー（盤・溝と光・ラベル）の絵は WatashiToOngaku/AppIcon.icon/Assets を共通で使う。
  python3 scripts/make_icons.py
"""
import copy
import json
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


def srgb(rgb):
    return "srgb:" + ",".join(f"{v:.5f}" for v in rgb) + ",1.00000"


def make(template, background, disc):
    icon = copy.deepcopy(template)
    # 背景は「ライト」のときに自動のグラデーション、「ダーク」は黒一色。
    # ダーク用の値を書かないと iOS がダーク版を自動で作ってしまうので、同じ値を明示する
    icon["fill-specializations"] = fixed({"automatic-gradient": WHITE} if background == WHITE else {"solid": BLACK})
    for layer in icon["groups"][0]["layers"]:
        if layer["name"] == "disc":
            layer["fill-specializations"] = fixed({"solid": srgb(disc)})
    return icon


def fixed(value):
    """外観（ライト・ダーク）で変わらない値"""
    return [{"value": value}, {"appearance": "dark", "value": value}]


def write(path, icon):
    if path.resolve() != TEMPLATE.resolve():
        shutil.rmtree(path, ignore_errors=True)
        shutil.copytree(TEMPLATE / "Assets", path / "Assets")
    (path / "icon.json").write_text(json.dumps(icon, indent=2) + "\n")


def main():
    template = json.loads((TEMPLATE / "icon.json").read_text())
    names = []
    for theme, (light, dark) in THEMES.items():
        base = f"AppIcon-{theme}" if theme else "AppIcon"
        light_path = TEMPLATE if not theme else ROOT / "ThemeIcons" / f"{base}.icon"
        dark_name = f"{base}-Dark"
        write(ROOT / "ThemeIcons" / f"{dark_name}.icon", make(template, BLACK, dark))
        write(light_path, make(template, WHITE, light))
        names += ([base] if theme else []) + [dark_name]
    print("ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES:", " ".join(names))


if __name__ == "__main__":
    main()
