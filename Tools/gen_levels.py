# ステージ検証・生成ツール
#
# BeamTracer.swift と同一ロジックの Python 移植でステージ定義(STAGES)を検証し、
# Resources/Levels/*.json を生成する。ステージを追加するときは STAGES に
# (番号, タイトル, size, 固定配置, 在庫, 想定解) を足してから実行すること。
#
# 使い方:
#   検証のみ: python3 Tools/gen_levels.py
#   JSON生成: python3 Tools/gen_levels.py Aglaia/Aglaia/Prism/Resources/Levels
#             (出力先の既存 *.json は削除して全ステージを書き直す)
#
# 検証内容(全ステージ):
#   - 初期状態では未クリアであること
#   - 想定解を置くとクリアになること
#   - 想定解が在庫の範囲内で置けること
import json
import math
import os
import sys

UP, RIGHT, DOWN, LEFT = 0, 1, 2, 3
DX = [0, 1, 0, -1]
DY = [1, 0, -1, 0]

WHITE = {"r": 1, "g": 1, "b": 1}
RED = {"r": 1, "g": 0, "b": 0}
GREEN = {"r": 0, "g": 1, "b": 0}
BLUE = {"r": 0, "g": 0, "b": 1}
YELLOW = {"r": 1, "g": 1, "b": 0}
CYAN = {"r": 0, "g": 1, "b": 1}
MAGENTA = {"r": 1, "g": 0, "b": 1}
HALF_WHITE = {"r": 0.5, "g": 0.5, "b": 0.5}
HALF_RED = {"r": 0.5, "g": 0, "b": 0}
HALF_GREEN = {"r": 0, "g": 0.5, "b": 0}
HALF_BLUE = {"r": 0, "g": 0, "b": 0.5}
HALF_YELLOW = {"r": 0.5, "g": 0.5, "b": 0}
HALF_MAGENTA = {"r": 0.5, "g": 0, "b": 0.5}
ORANGE = {"r": 1, "g": 0.5, "b": 0}
# ワープゲートのペア識別色(見た目のティントも兼ねる)
WARP_C = {"r": 0, "g": 1, "b": 1}
WARP_O = {"r": 1, "g": 0.5, "b": 0}


def quantized(c):
    return (round(c[0] * 16) << 10) | (round(c[1] * 16) << 5) | round(c[2] * 16)


def mixed(a, b):
    return tuple(min(1.0, x + y) for x, y in zip(a, b))


def negligible(c):
    return all(x < 0.01 for x in c)


def distance(a, b):
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def reflect(direction, rotation):
    is_slash = (rotation // 90) % 2 == 0
    if is_slash:
        return {RIGHT: UP, UP: RIGHT, LEFT: DOWN, DOWN: LEFT}[direction]
    return {RIGHT: DOWN, DOWN: RIGHT, LEFT: UP, UP: LEFT}[direction]


def color_of(comp, default=None):
    c = comp.get("color")
    if c is None:
        return default
    return (c["r"], c["g"], c["b"])


def trace_pass(size, board, combiner_inputs):
    goal_colors = {}
    new_combiner_inputs = {}
    visited = set()
    queue = []

    def enqueue(origin, direction, color):
        if negligible(color):
            return
        key = (origin, direction, quantized(color))
        if key in visited:
            return
        visited.add(key)
        queue.append((origin, direction, color))

    for pos, comp in board.items():
        if comp["kind"] == "source":
            enqueue(pos, comp.get("rotation", 0) // 90 % 4, color_of(comp, (1, 1, 1)))
    for pos, color in combiner_inputs.items():
        comp = board.get(pos)
        if comp and comp["kind"] == "combiner":
            enqueue(pos, comp.get("rotation", 0) // 90 % 4, color)

    while queue:
        origin, direction, color = queue.pop()
        current = origin
        while True:
            nxt = (current[0] + DX[direction], current[1] + DY[direction])
            if not (0 <= nxt[0] < size and 0 <= nxt[1] < size):
                break
            comp = board.get(nxt)
            if comp is None:
                current = nxt
                continue
            kind = comp["kind"]
            if kind in ("wall", "source"):
                pass
            elif kind == "goal":
                goal_colors[nxt] = mixed(goal_colors.get(nxt, (0, 0, 0)), color)
            elif kind == "mirror":
                enqueue(nxt, reflect(direction, comp.get("rotation", 0)), color)
            elif kind == "splitter":
                half = tuple(x * 0.5 for x in color)
                enqueue(nxt, reflect(direction, comp.get("rotation", 0)), half)
                enqueue(nxt, direction, half)
            elif kind == "filter":
                f = color_of(comp, (1, 1, 1))
                enqueue(nxt, direction, tuple(a * b for a, b in zip(color, f)))
            elif kind == "shifter":
                # R→G→B→R の巡回シフト(BeamColor.shifted と同一)
                enqueue(nxt, direction, (color[2], color[0], color[1]))
            elif kind == "warp":
                # 同じペア色の対ゲートから同方向で出る。対が無ければ吸収
                for p, c in board.items():
                    if p != nxt and c["kind"] == "warp" and c.get("color") == comp.get("color"):
                        enqueue(p, direction, color)
                        break
            elif kind == "prism":
                enqueue(nxt, direction, (color[0], 0, 0))
                enqueue(nxt, (direction + 3) % 4, (0, color[1], 0))
                enqueue(nxt, (direction + 1) % 4, (0, 0, color[2]))
            elif kind == "combiner":
                out_dir = comp.get("rotation", 0) // 90 % 4
                if direction != (out_dir + 2) % 4:
                    new_combiner_inputs[nxt] = mixed(
                        new_combiner_inputs.get(nxt, (0, 0, 0)), color)
            break

    return goal_colors, new_combiner_inputs


def trace(level, placements):
    board = dict(level["board"])
    for pos, comp in placements.items():
        assert pos not in board, f"固定部品と重複: {pos}"
        board[pos] = comp

    combiner_inputs = {}
    goal_colors = {}
    for _ in range(8):
        goal_colors, new_inputs = trace_pass(level["size"], board, combiner_inputs)
        conv = ({p: quantized(c) for p, c in new_inputs.items()}
                == {p: quantized(c) for p, c in combiner_inputs.items()})
        combiner_inputs = new_inputs
        if conv:
            break

    goals = {p: c for p, c in board.items() if c["kind"] == "goal"}
    solved = bool(goals) and all(
        p in goal_colors and distance(goal_colors[p], color_of(c)) <= level["tolerance"]
        for p, c in goals.items())
    return solved, goal_colors


def check_inventory(level, placements):
    used = {}
    for comp in placements.values():
        key = (comp["kind"], json.dumps(comp.get("color"), sort_keys=True))
        used[key] = used.get(key, 0) + 1
    stock = {}
    for item in level["inventory"]:
        key = (item["kind"], json.dumps(item.get("color"), sort_keys=True))
        stock[key] = stock.get(key, 0) + item["count"]
    for key, n in used.items():
        assert stock.get(key, 0) >= n, f"在庫不足: {key} 使用{n} 在庫{stock.get(key, 0)}"


# ---------------------------------------------------------------- 部品定義ヘルパ
def src(rot, color=None):
    comp = {"kind": "source", "rotation": rot, "fixed": True}
    if color is not None:
        comp["color"] = color
    return comp


def fixed(comp):
    """プレイヤーが動かせない固定部品としてマークする"""
    out = dict(comp)
    out["fixed"] = True
    return out


def goal(color):
    return {"kind": "goal", "rotation": 0, "fixed": True, "color": color}


def wall():
    return {"kind": "wall", "rotation": 0, "fixed": True}


def mirror(rot):
    return {"kind": "mirror", "rotation": rot}


def prism():
    return {"kind": "prism", "rotation": 0}


def filt(color):
    return {"kind": "filter", "rotation": 0, "color": color}


def combiner(rot):
    return {"kind": "combiner", "rotation": rot}


def splitter(rot):
    return {"kind": "splitter", "rotation": rot}


def shifter():
    return {"kind": "shifter", "rotation": 0}


def warp(pair_color):
    """ワープゲート(盤面固定)。pair_color が同じ2つで1ペア"""
    return {"kind": "warp", "rotation": 0, "fixed": True, "color": pair_color}


def inv(kind, count, color=None):
    item = {"kind": kind, "count": count}
    if color is not None:
        item["color"] = color
    return item


# ---------------------------------------------------------------- ステージ定義
# 各要素: (番号, タイトル, size, board, inventory, 想定解)
STAGES = [
    (1, "はじめての光", 6,
     {(0, 2): src(90), (3, 2): wall(), (5, 4): goal(WHITE)},
     [inv("mirror", 2)],
     {(2, 2): mirror(0), (2, 4): mirror(0)}),

    (2, "あかい光だけを", 6,
     {(0, 2): src(90), (2, 4): wall(), (3, 0): wall(), (5, 2): goal(RED)},
     [inv("filter", 1, RED), inv("mirror", 2)],
     {(2, 2): filt(RED)}),

    (3, "むらさきの結晶", 7,
     {(0, 3): src(90), (3, 2): wall(), (5, 1): wall(), (6, 3): goal(MAGENTA)},
     [inv("prism", 1), inv("combiner", 1), inv("mirror", 3)],
     {(2, 3): prism(), (2, 1): mirror(90), (4, 1): mirror(0), (4, 3): combiner(90)}),

    (4, "ふたつの結晶", 7,
     {(0, 3): src(90), (1, 1): wall(), (3, 5): wall(),
      (6, 3): goal(RED), (5, 1): goal(BLUE)},
     [inv("prism", 1), inv("mirror", 1)],
     {(2, 3): prism(), (2, 1): mirror(90)}),

    (5, "みどりのゆくえ", 7,
     {(0, 3): src(90), (4, 3): wall(), (0, 5): wall(), (6, 1): wall(),
      (5, 5): goal(GREEN)},
     [inv("prism", 1), inv("mirror", 2)],
     {(2, 3): prism(), (2, 5): mirror(0)}),

    (6, "きいろをつくる", 7,
     {(0, 3): src(90), (1, 5): wall(), (3, 1): wall(), (6, 3): goal(YELLOW)},
     [inv("prism", 1), inv("combiner", 1), inv("mirror", 2)],
     {(2, 3): prism(), (2, 5): mirror(0), (4, 5): mirror(90), (4, 3): combiner(90)}),

    (7, "ふたいろの部屋", 8,
     {(0, 4): src(90), (7, 4): wall(), (2, 6): wall(), (5, 1): wall(), (1, 2): wall(),
      (7, 6): goal(RED), (7, 2): goal(BLUE)},
     [inv("prism", 1), inv("mirror", 3)],
     {(3, 4): prism(), (5, 4): mirror(0), (5, 6): mirror(0), (3, 2): mirror(90)}),

    (8, "とおまわり", 8,
     {(0, 4): src(90), (2, 2): wall(), (2, 3): wall(), (2, 4): wall(),
      (2, 5): wall(), (2, 6): wall(), (4, 0): goal(RED)},
     [inv("mirror", 3), inv("filter", 1, RED)],
     {(1, 4): mirror(0), (1, 7): mirror(0), (3, 7): filt(RED), (4, 7): mirror(90)}),

    (9, "みずいろ", 8,
     {(0, 4): src(90), (1, 6): wall(), (6, 5): wall(), (7, 1): goal(CYAN)},
     [inv("prism", 1), inv("combiner", 1), inv("mirror", 3)],
     {(2, 4): prism(), (2, 6): mirror(0), (5, 6): mirror(90),
      (2, 1): mirror(90), (5, 1): combiner(90)}),

    (10, "ふたつのこたえ", 8,
     {(0, 4): src(90), (4, 0): wall(), (6, 2): wall(),
      (7, 4): goal(RED), (7, 6): goal(CYAN)},
     [inv("prism", 1), inv("combiner", 1), inv("mirror", 3)],
     {(2, 4): prism(), (2, 6): mirror(0), (5, 6): combiner(90),
      (2, 2): mirror(90), (5, 2): mirror(0)}),

    # --- スタンダードパック(11〜50)。スプリッタ(ハーフミラー)が登場 ---
    (11, "わけあう光", 7,
     {(0, 3): src(90), (1, 5): wall(), (5, 1): wall(),
      (6, 3): goal(HALF_WHITE), (3, 6): goal(HALF_WHITE)},
     [inv("splitter", 1), inv("mirror", 1)],
     {(3, 3): splitter(0)}),

    (12, "はんぶんこ", 7,
     {(0, 3): src(90), (3, 1): wall(), (2, 5): wall(), (6, 3): goal(HALF_RED)},
     [inv("filter", 1, RED), inv("splitter", 1), inv("mirror", 2)],
     {(1, 3): filt(RED), (3, 3): splitter(0)}),

    # --- スタンダード 13〜21: データのみ難化(固定部品/色付き光源/ダミー在庫/
    #     大盤面/3+ゴール/両面鏡の両面活用) ---
    (13, "うごかせない鏡", 7,
     {(0, 3): src(90), (3, 3): fixed(mirror(0)), (5, 1): wall(), (1, 6): wall(),
      (6, 5): goal(WHITE)},
     [inv("mirror", 2)],
     {(3, 5): mirror(0)}),

    (14, "あかとあお", 7,
     {(0, 3): src(90, RED), (3, 0): src(0, BLUE), (1, 5): wall(), (5, 5): wall(),
      (6, 3): goal(MAGENTA)},
     [inv("combiner", 1), inv("mirror", 1)],
     {(3, 3): combiner(90)}),

    (15, "みっつの結晶", 8,
     {(0, 4): src(90), (1, 2): wall(), (6, 6): wall(),
      (7, 4): goal(RED), (2, 6): goal(GREEN), (6, 2): goal(BLUE)},
     [inv("prism", 1), inv("mirror", 3)],
     {(4, 4): prism(), (4, 6): mirror(90), (4, 2): mirror(90)}),

    (16, "一枚二役", 7,
     {(0, 3): src(90), (6, 3): src(270), (1, 5): wall(), (5, 1): wall(),
      (3, 6): goal(WHITE), (3, 0): goal(WHITE)},
     [inv("mirror", 2)],
     {(3, 3): mirror(0)}),

    (17, "みどりの回廊", 8,
     {(0, 4): src(90), (3, 4): wall(), (5, 5): wall(), (1, 6): wall(),
      (7, 1): goal(GREEN)},
     [inv("mirror", 3), inv("filter", 1, GREEN), inv("filter", 1, RED)],
     {(2, 4): mirror(90), (2, 1): mirror(90), (4, 1): filt(GREEN)}),

    (18, "こぼれた光", 8,
     {(0, 4): src(90), (2, 4): fixed(splitter(0)), (6, 1): wall(), (1, 2): wall(),
      (7, 4): goal(WHITE)},
     [inv("mirror", 3), inv("combiner", 1)],
     {(2, 6): mirror(0), (5, 6): mirror(90), (5, 4): combiner(90)}),

    (19, "壁のむこう", 9,
     {(0, 4): src(90),
      (4, 0): wall(), (4, 1): wall(), (4, 2): wall(), (4, 3): wall(),
      (4, 5): wall(), (4, 6): wall(), (4, 7): wall(), (4, 8): wall(),
      (8, 6): goal(HALF_WHITE), (8, 2): goal(HALF_WHITE)},
     [inv("splitter", 1), inv("mirror", 4)],
     {(6, 4): splitter(0), (6, 6): mirror(0), (7, 4): mirror(90), (7, 2): mirror(90)}),

    (20, "よっつの結晶", 9,
     {(0, 4): src(90), (4, 0): src(0), (6, 6): wall(), (1, 7): wall(), (7, 1): wall(),
      (2, 8): goal(HALF_WHITE), (8, 4): goal(HALF_WHITE),
      (8, 2): goal(HALF_WHITE), (4, 8): goal(HALF_WHITE)},
     [inv("splitter", 2), inv("mirror", 2)],
     {(2, 4): splitter(0), (4, 2): splitter(0)}),

    (21, "箱の中の太陽", 9,
     {(4, 4): src(0), (3, 4): wall(), (5, 4): wall(), (4, 3): wall(),
      (1, 1): wall(), (7, 2): wall(), (8, 6): goal(MAGENTA)},
     [inv("prism", 1), inv("combiner", 1), inv("mirror", 3), inv("filter", 1, RED)],
     {(4, 6): prism(), (4, 8): mirror(0), (6, 8): mirror(90), (6, 6): combiner(90)}),

    # --- スタンダード 22〜25: カラーシフタ(R→G→B→R)登場 ---
    (22, "くるりと色がわり", 8,
     {(0, 4): src(90, RED), (2, 2): wall(), (5, 6): wall(), (7, 4): goal(GREEN)},
     [inv("shifter", 1), inv("mirror", 1), inv("filter", 1, GREEN)],
     {(3, 4): shifter()}),

    (23, "二回まわして", 8,
     {(0, 4): src(90, RED), (3, 6): wall(), (4, 2): wall(), (7, 4): goal(BLUE)},
     [inv("shifter", 2), inv("mirror", 2)],
     {(2, 4): shifter(), (5, 4): shifter()}),

    (24, "まわしてあわせて", 9,
     {(0, 4): src(90, RED), (7, 7): wall(), (1, 2): wall(), (8, 4): goal(HALF_YELLOW)},
     [inv("splitter", 1), inv("shifter", 1), inv("combiner", 1), inv("mirror", 3)],
     {(2, 4): splitter(0), (2, 6): mirror(0), (4, 6): shifter(),
      (5, 6): mirror(90), (5, 4): combiner(90)}),

    (25, "三色の輪", 9,
     {(0, 4): src(90), (7, 2): wall(), (6, 6): wall(),
      (8, 4): goal(GREEN), (5, 7): goal(BLUE), (5, 1): goal(RED)},
     [inv("prism", 1), inv("shifter", 3), inv("mirror", 3)],
     {(2, 4): prism(), (4, 4): shifter(), (2, 6): shifter(), (2, 7): mirror(0),
      (2, 2): shifter(), (2, 1): mirror(90)}),

    # --- スタンダード 26〜33: ワープゲート登場(入門→既存要素との複合) ---
    (26, "とびらのむこう", 8,
     {(0, 4): src(90), (3, 4): warp(WARP_C), (3, 1): warp(WARP_C),
      (6, 6): wall(), (1, 1): wall(), (5, 6): goal(WHITE)},
     [inv("mirror", 2)],
     {(5, 1): mirror(0)}),

    (27, "くぐってあかく", 8,
     {(0, 4): src(90), (2, 4): warp(WARP_C), (6, 6): warp(WARP_C),
      (4, 2): wall(), (7, 6): goal(RED)},
     [inv("filter", 1, RED), inv("mirror", 1)],
     {(1, 4): filt(RED)}),

    (28, "ふたつのとびら", 9,
     {(0, 4): src(90), (5, 4): warp(WARP_C), (5, 1): warp(WARP_C),
      (4, 2): warp(WARP_O), (4, 6): warp(WARP_O),
      (7, 7): wall(), (8, 1): goal(RED), (6, 6): goal(BLUE)},
     [inv("prism", 1), inv("mirror", 2)],
     {(2, 4): prism(), (2, 2): mirror(90)}),

    (29, "とんでまわって", 9,
     {(0, 4): src(90, RED), (4, 4): warp(WARP_C), (4, 0): warp(WARP_C),
      (2, 7): wall(), (8, 0): goal(BLUE)},
     [inv("shifter", 2), inv("filter", 1, BLUE), inv("mirror", 1)],
     {(1, 4): shifter(), (3, 4): shifter()}),

    (30, "すれちがい", 9,
     {(0, 6): src(90), (0, 2): src(90), (4, 6): warp(WARP_C), (4, 2): warp(WARP_C),
      (7, 4): wall(), (8, 2): goal(RED), (8, 6): goal(BLUE)},
     [inv("filter", 1, RED), inv("filter", 1, BLUE), inv("mirror", 1)],
     {(2, 6): filt(RED), (2, 2): filt(BLUE)}),

    (31, "はんぶんのとびら", 9,
     {(0, 4): src(90), (3, 6): warp(WARP_C), (6, 2): warp(WARP_C),
      (1, 7): wall(), (8, 4): goal(HALF_WHITE), (6, 8): goal(HALF_WHITE)},
     [inv("splitter", 1), inv("mirror", 2)],
     {(3, 4): splitter(0)}),

    (32, "ちかみちの黄色", 9,
     {(0, 4): src(90), (2, 6): warp(WARP_C), (5, 2): warp(WARP_C),
      (6, 7): wall(), (8, 4): goal(YELLOW)},
     [inv("prism", 1), inv("combiner", 1), inv("mirror", 1)],
     {(2, 4): prism(), (5, 4): combiner(90)}),

    (33, "とびらと二役", 9,
     {(0, 2): src(90), (8, 6): src(270), (6, 6): warp(WARP_C), (8, 2): warp(WARP_C),
      (1, 8): wall(), (4, 8): goal(WHITE), (4, 0): goal(WHITE)},
     [inv("mirror", 2)],
     {(4, 2): mirror(0)}),

    # --- スタンダード 34〜42: 大盤面(10×10)+複合 ---
    (34, "三色の大広間", 10,
     {(0, 5): src(90), (1, 8): wall(), (8, 1): wall(), (6, 6): wall(), (6, 4): wall(),
      (9, 5): goal(RED), (9, 7): goal(GREEN), (9, 3): goal(BLUE)},
     [inv("prism", 1), inv("mirror", 4)],
     {(3, 5): prism(), (3, 7): mirror(0), (3, 3): mirror(90)}),

    (35, "半分と色がわり", 10,
     {(0, 5): src(90, RED), (2, 7): warp(WARP_C), (6, 3): warp(WARP_C),
      (8, 8): wall(), (9, 5): goal(HALF_RED), (6, 9): goal(HALF_GREEN)},
     [inv("splitter", 1), inv("shifter", 1), inv("mirror", 1)],
     {(2, 5): splitter(0), (6, 6): shifter()}),

    (36, "わけあいの十字路", 10,
     {(0, 5): src(90, RED), (5, 0): src(0, BLUE), (8, 8): wall(), (1, 1): wall(),
      (2, 9): goal(HALF_RED), (9, 5): goal(HALF_RED),
      (9, 3): goal(HALF_BLUE), (5, 9): goal(HALF_BLUE)},
     [inv("splitter", 2), inv("mirror", 2)],
     {(2, 5): splitter(0), (5, 3): splitter(0)}),

    (37, "めぐる三色のとびら", 9,
     {(0, 4): src(90), (4, 4): warp(WARP_C), (4, 8): warp(WARP_C),
      (6, 2): wall(), (8, 8): goal(GREEN), (2, 8): goal(BLUE), (2, 0): goal(RED)},
     [inv("prism", 1), inv("shifter", 3), inv("mirror", 1)],
     {(2, 4): prism(), (6, 8): shifter(), (2, 6): shifter(), (2, 2): shifter()}),

    (38, "はなればなれの半分", 10,
     {(0, 5): src(90), (2, 5): fixed(splitter(0)), (2, 7): warp(WARP_C), (7, 2): warp(WARP_C),
      (4, 8): wall(), (9, 5): goal(WHITE)},
     [inv("combiner", 1), inv("mirror", 2)],
     {(7, 5): combiner(90)}),

    (39, "青の抜け道", 10,
     {(0, 5): src(90), (5, 1): warp(WARP_C), (5, 7): warp(WARP_C),
      (3, 2): wall(), (3, 3): wall(), (3, 4): wall(), (3, 5): wall(),
      (3, 6): wall(), (3, 7): wall(), (3, 8): wall(),
      (9, 7): goal(BLUE)},
     [inv("mirror", 3), inv("filter", 1, BLUE), inv("filter", 1, RED)],
     {(2, 5): mirror(90), (2, 1): mirror(90), (6, 7): filt(BLUE)}),

    (40, "なかばの試練", 10,
     {(0, 5): src(90), (1, 8): wall(), (8, 2): wall(), (9, 5): goal(HALF_MAGENTA)},
     [inv("prism", 1), inv("combiner", 1), inv("splitter", 1), inv("mirror", 3)],
     {(2, 5): prism(), (2, 3): mirror(90), (5, 3): mirror(0),
      (5, 5): combiner(90), (7, 5): splitter(0)}),

    (41, "二色のとびら", 10,
     {(0, 5): src(90), (5, 5): warp(WARP_C), (5, 0): warp(WARP_C),
      (3, 3): warp(WARP_O), (8, 7): warp(WARP_O),
      (1, 7): wall(), (9, 0): goal(GREEN), (8, 2): goal(BLUE)},
     [inv("prism", 1), inv("shifter", 1), inv("mirror", 2)],
     {(3, 5): prism(), (7, 0): shifter()}),

    (42, "そとまわりの水路", 10,
     {(0, 8): src(90), (5, 5): wall(), (2, 2): wall(), (9, 1): goal(CYAN)},
     [inv("mirror", 3), inv("filter", 1, CYAN), inv("filter", 1, YELLOW)],
     {(8, 8): mirror(90), (8, 1): mirror(90), (4, 8): filt(CYAN)}),

    # --- スタンダード 43〜50: 高難度(妨害固定部品・全色合成・総合) ---
    (43, "よごれた道", 10,
     {(0, 5): src(90, RED), (4, 5): fixed(shifter()), (6, 1): wall(), (1, 2): wall(),
      (9, 5): goal(RED)},
     [inv("mirror", 4), inv("shifter", 1)],
     {(2, 5): mirror(0), (2, 7): mirror(0), (8, 7): mirror(90), (8, 5): mirror(90)}),

    (44, "二重のとびら", 10,
     {(0, 5): src(90), (3, 5): warp(WARP_C), (3, 1): warp(WARP_C),
      (5, 4): warp(WARP_O), (8, 3): warp(WARP_O),
      (2, 8): wall(), (8, 8): goal(MAGENTA)},
     [inv("mirror", 2), inv("filter", 1, MAGENTA), inv("filter", 1, CYAN)],
     {(5, 1): mirror(0), (8, 5): filt(MAGENTA)}),

    (45, "みどりの大合流", 10,
     {(0, 5): src(90), (1, 1): wall(), (8, 8): wall(), (9, 5): goal(GREEN)},
     [inv("prism", 1), inv("shifter", 3), inv("mirror", 4), inv("combiner", 1)],
     {(2, 5): prism(), (4, 5): shifter(),
      (2, 7): mirror(0), (6, 7): mirror(90),
      (2, 3): mirror(90), (3, 3): shifter(), (5, 3): shifter(), (6, 3): mirror(0),
      (6, 5): combiner(90)}),

    (46, "わかれたみち", 10,
     {(0, 5): src(90), (7, 5): warp(WARP_C), (2, 2): warp(WARP_C),
      (6, 8): wall(), (0, 7): goal(HALF_WHITE), (4, 9): goal(HALF_WHITE)},
     [inv("splitter", 1), inv("mirror", 3), inv("shifter", 1)],
     {(5, 5): splitter(0), (5, 7): mirror(90), (4, 2): mirror(0)}),

    (47, "ひきざんの色", 10,
     {(0, 5): src(90), (4, 2): wall(), (7, 8): wall(), (9, 5): goal(GREEN)},
     [inv("filter", 1, YELLOW), inv("filter", 1, CYAN), inv("mirror", 2), inv("shifter", 1)],
     {(3, 5): filt(YELLOW), (6, 5): filt(CYAN)}),

    (48, "かどをまがって", 10,
     {(5, 0): src(0, RED), (5, 4): warp(WARP_C), (2, 7): warp(WARP_C),
      (8, 6): wall(), (9, 2): goal(HALF_RED), (2, 9): goal(HALF_GREEN)},
     [inv("splitter", 1), inv("shifter", 1), inv("mirror", 2)],
     {(5, 2): splitter(0), (2, 8): shifter()}),

    (49, "しろへの帰還", 10,
     {(0, 5): src(90), (5, 5): wall(),
      (2, 7): warp(WARP_C), (7, 1): warp(WARP_C),
      (2, 3): warp(WARP_O), (7, 9): warp(WARP_O),
      (9, 5): goal(WHITE)},
     [inv("prism", 1), inv("combiner", 1), inv("mirror", 4), inv("shifter", 1)],
     {(2, 5): prism(), (4, 5): mirror(0), (4, 6): mirror(0),
      (6, 6): mirror(90), (6, 5): mirror(90), (7, 5): combiner(90)}),

    (50, "五十番目の扉", 10,
     {(0, 5): src(90), (2, 3): fixed(mirror(90)),
      (7, 7): warp(WARP_C), (3, 8): warp(WARP_C),
      (9, 5): goal(HALF_MAGENTA), (3, 9): goal(HALF_MAGENTA), (2, 9): goal(BLUE)},
     [inv("prism", 1), inv("combiner", 1), inv("splitter", 1),
      inv("shifter", 1), inv("mirror", 2)],
     {(2, 5): prism(), (6, 3): mirror(0), (6, 5): combiner(90),
      (7, 5): splitter(0), (2, 7): shifter()}),

    # --- Extraパック(51〜100)。複合ギミックで高難度化 ---
    (51, "オレンジの結晶", 8,
     {(0, 4): src(90), (1, 1): wall(), (6, 6): wall(), (7, 4): goal(ORANGE)},
     [inv("prism", 1), inv("splitter", 1), inv("combiner", 1), inv("mirror", 3)],
     {(2, 4): prism(), (2, 6): mirror(0), (4, 6): splitter(0),
      (5, 6): mirror(90), (5, 4): combiner(90)}),
]

TOLERANCE = 0.15
failures = []

for number, title, size, board, inventory, solution in STAGES:
    level = {"size": size, "tolerance": TOLERANCE, "board": board, "inventory": inventory}
    check_inventory(level, solution)
    initial_solved, initial_goals = trace(level, {})
    solved, goals = trace(level, solution)
    ok = (not initial_solved) and solved
    print(f"{'OK ' if ok else 'NG '} stage {number:3d} {title}: "
          f"initial={initial_solved} solution={solved} goals={goals}")
    if not ok:
        failures.append(number)

if failures:
    print("FAILED:", failures)
    sys.exit(1)

# ---------------------------------------------------------------- JSON生成
out_dir = sys.argv[1] if len(sys.argv) > 1 else None
if out_dir:
    os.makedirs(out_dir, exist_ok=True)
    for old in os.listdir(out_dir):
        if old.endswith(".json"):
            os.remove(os.path.join(out_dir, old))
    for number, title, size, board, inventory, _ in STAGES:
        stage_id = f"level_{number:03d}"
        data = {
            "id": stage_id,
            "title": title,
            "size": size,
            "tolerance": TOLERANCE,
            "grid": {f"{x},{y}": comp for (x, y), comp in sorted(board.items())},
            "inventory": inventory,
        }
        path = os.path.join(out_dir, f"{stage_id}.json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
            f.write("\n")
        print("wrote", path)

print("all stages verified")
