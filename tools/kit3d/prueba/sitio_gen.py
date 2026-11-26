"""The interiors in place of every building type, written out as data/interiors/<type>_sitio_n<level>.json:
  python3 tools/sitio_gen.py [type ...]
A convenience, like tools/sims_variant.py: the JSON files are what the game reads (schema in docs/interior3d.md,
«Interior en sitio» and «Interiores por tipo»); here the layouts are short Python tables so houses of the same footprint
share their stair, and a piece is a line. The forge keeps its hand-written forge_sitio.json.

A house of w x d m has (w - 1) x (d - 1) tiles of 1 m; tile (c, r): c grows to the right seen from the street, r to
the front; the door is on the last row. Pieces go by tile (or decimals) and the outer wall they stand against (snap:
back, front, left, right); Interior3DBuilder.resolve_prop works out the rest from data/interiors/muebles.json.
"""
import json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
OUT = os.path.join(ROOT, "data", "view3d", "interiors")
DOOR_C = {4: 2, 6: 2, 8: 4, 12: 6}   # the tile of the door on the front row, by width of the house (HouseBuilder's middle cell)


def P(pid, c, r, snap=None, f=0, **kw):
    d = {"id": pid, "floor": f}
    if isinstance(c, int) and isinstance(r, int):
        d["tile"] = [c, r]
    else:
        d["pos"] = [c, r]
    if snap:
        d["snap"] = snap
    d.update(kw)
    return d


def S(name, kind, c, r, stand, prop=None, snap=None, f=0, **kw):
    d = {"name": name, "kind": kind, "floor": f, "tile": [int(round(c)), int(round(r))], "stand": list(stand)}
    if prop:
        d["prop"] = prop
    if not (isinstance(c, int) and isinstance(r, int)):
        d["pos"] = [c, r]
    if snap:
        d["snap"] = snap
    d.update(kw)
    return d


def room(rid, f, kind, rect, light="warm", floor_kind="planks", wall_style="timber", **kw):
    d = {"id": rid, "floor": f, "type": kind, "rects": [list(rect)], "floor_kind": floor_kind, "wall_style": wall_style, "light": light}
    d.update(kw)
    return d


def stair(where, w, d, f=0, shift=0):
    """a steep flight (escalera_empinada) with its rail on the room side: against the left wall it climbs to the back,
    against the right wall to the front. Flights of the floors above stand over the one below.
    The town opens a house looking at its front (3/4, pitch 52): a flight that climbs to the front climbs towards that
    camera and is seen nearly edge-on (56 degrees against 52), so "left" and "right_back" are the ones that read.
    shift: rows further to the front for those two (the flight then ends in the middle of the room and the landing
    is the tile straight ahead)"""
    W, R = w - 1, d - 2
    if where == "left":
        s = {"from": [0, 2], "to": [1, 0], "foot": [-0.17, 1.45], "top": [-0.17, -0.6], "tiles": [[0, 0], [0, 1]]}
        if shift:
            s = {"from": [0, 2 + shift], "to": [0, shift - 1], "foot": [-0.17, 1.45 + shift], "top": [-0.17, shift - 0.6], "tiles": [[0, shift], [0, shift + 1]]}
    elif where == "left_front":   # against the left wall, climbing to the front: the piece mirrored, its rail to the room
        s = {"from": [0, R - 2], "to": [1, R], "foot": [-0.17, R - 1.45], "top": [-0.17, R + 0.6], "tiles": [[0, R - 1], [0, R]], "mirror": True}
    elif where == "right_back":   # against the right wall, climbing to the back: the piece mirrored, its rail to the room
        s = {"from": [W - 1, 2], "to": [W - 2, 0], "foot": [W - 1 + 0.17, 1.45], "top": [W - 1 + 0.17, -0.6], "tiles": [[W - 1, 0], [W - 1, 1]], "mirror": True}
        if shift:
            s.update({"from": [W - 1, 2 + shift], "to": [W - 1, shift - 1], "foot": [W - 1 + 0.17, 1.45 + shift], "top": [W - 1 + 0.17, shift - 0.6],
                      "tiles": [[W - 1, shift], [W - 1, shift + 1]]})
    else:
        s = {"from": [W - 1, R - 2], "to": [W - 2, R], "foot": [W - 1 + 0.17, R - 1.45], "top": [W - 1 + 0.17, R + 0.6], "tiles": [[W - 1, R - 1], [W - 1, R]]}
    s.update({"id": "stairs%d" % f, "floor": f, "to_floor": f + 1, "prop": "escalera_empinada", "width": 0.94})
    return s


def step(say, secs, anim="Idle", **kw):
    d = {"say": say, "secs": secs}
    if anim != "Idle":
        d["anim"] = anim
    d.update(kw)
    return d


def zone(z, say, secs, anim="Idle", **kw):
    return step(say, secs, anim, zone=z, **kw)


def at(f, c, r, say, secs, anim="Idle", look=None, **kw):
    d = step(say, secs, anim, tile=[f, [c, r]], **kw)
    if look:
        d["look"] = list(look)
    return d


def sit(name, say, secs, anim="sit_bench", look=None, **kw):
    d = step(say, secs, anim, sit=name, **kw)
    if look:
        d["look"] = list(look)
    return d


def lie(name, say="duerme", secs=10, **kw):
    return step(say, secs, lie=name, **kw)


ENTER = {"enter": True}


def leave(secs=4):
    return {"leave": True, "secs": secs}


def who(look, name, steps, start=None, **kw):
    d = {"look": look, "name": name}
    if start:
        d["start"] = [start[0], [start[1], start[2]]]
    else:
        d["outside"] = True
    d.update(kw)
    d["steps"] = steps
    return d


GM = os.path.join(ROOT, "data")


def gm_tree(btype):
    """the upgrade tree of a type in GuildMaster (read only): [(sim id, interior node or None, exterior overlay or None)]"""
    out = []
    folder = os.path.join(GM, "upgrades", btype)
    if not os.path.isdir(folder):
        return out
    for f in sorted(os.listdir(folder)):
        u = json.load(open(os.path.join(folder, f)))
        v = u.get("visual") or {}
        out.append((u["id"], v.get("interior_node"), v.get("exterior_overlay")))
    return out


def A(pid, near="", f=0, mode="wall", **kw):
    """an upgrade piece whose place Interior3DBuilder finds: against an outer wall (or on the floor), nearest to `near`"""
    d = {"id": pid, "floor": f, "auto": mode}
    if near != "":
        d["near"] = near
    d.update(kw)
    return d


def Z(zone_id, name, pid, near="", f=0, kind="craft", mode="wall", **kw):
    return A(pid, near, f, mode, zone=zone_id, name=name, kind=kind, **kw)


def SW(target, pid, **kw):
    return {"swap": target, "id": pid, **kw}


def ON(target, pid, off=(0, 0), **kw):
    return {"on": target, "id": pid, "off": list(off), **kw}


def BASE(name):
    return {"base": name}


def BUILT(note):
    return {"built": note}


def NEEDS(what, note):
    return {"needs": what, "note": note}


def common_ups(home_f, bed, table, desk, big_home):
    """the upgrades every trade shares. home_f: the floor of the home (None: there is none at this level); bed: the name
    of the bed that becomes a bunk; table: the name of the home's table; desk: where the second ledger lies; big_home:
    the home is 6 m wide (the long table fits)"""
    no_home = NEEDS("planta", "no hay vivienda en este nivel: llega con la planta alta")
    return {
        "upgrade_double_ledger": [ON(desk, "q:Book_Stack_2", off=(0.25, 0.0))],
        "upgrade_hidden_passage": [A("tapiz", "storage")],
        "upgrade_smuggler_cache": [A("trampilla", "storage", mode="floor", prio=1)],
        "upgrade_strongbox": [A("arca_fuerte", bed if home_f is not None else "storage", f=home_f or 0)],
        "upgrade_bunks": [SW(bed, "litera")] if home_f is not None else [no_home],
        "upgrade_dining_table": ([SW(table, "mesa_1x2"), A("taburete", table, f=home_f, mode="floor")] if big_home else
                                 [NEEDS("nivel", "la mesa larga no cabe en la vivienda de 4 m de ancho")]) if home_f is not None else [no_home],
    }


def building(btype, level, w, d, floors, doc, rooms, stations, props, cast, stairs=(), doors=(), open_=(), spots=None,
             customers=None, shell=None, for_levels=None, upgrades=None, extra_ids=None):
    W, D = w - 1, d - 1
    sh = {"w": w, "d": d, "floors": floors, "door_cell": {4: 1, 6: 1, 8: 2, 12: 3}[w]}
    sh.update(shell or {})
    door_c = int(-w / 2 + 1 + 2 * sh["door_cell"] + w / 2 - 0.5)
    out = {
        "_doc": doc + " Schema: docs/interior3d.md, «Interior en sitio» and «Interiores por tipo». Written by tools/sitio_gen.py.",
        "id": btype, "level": level,
    }
    if for_levels:
        out["for_levels"] = for_levels
    out.update({
        "tile_m": 1.0, "origin_m": [-w / 2 + 0.5, -d / 2 + 0.5], "size": [W, D], "seed": 3 + level,
        "shell": sh,
        "entrance": {"floor": 0, "tile": [door_c, D - 1], "side": "sw"},
        "rooms": list(rooms),
    })
    if open_:
        out["open"] = [list(p) for p in open_]
    if doors:
        out["doors"] = list(doors)
    if stairs:
        out["stairs"] = list(stairs)
    out["stations"] = stations
    if customers:
        out["customers"] = customers
    out["spots"] = spots or {}
    out["props"] = list(props)
    tree = gm_tree(btype)
    if upgrades or tree:
        upgrades = upgrades or {}
        ids, outside = dict(extra_ids or {}), {}
        for sim_id, node, overlay in tree:
            if sim_id in ids:
                continue
            if node:
                ids[sim_id] = node
            else:
                outside[sim_id] = ("fachada: %s" % overlay) if overlay else "efecto (sin pieza)"
        for node in sorted(set(ids.values())):
            if node not in upgrades:
                upgrades[node] = [{"none": "sin pieza asignada en este trazado"}]
        out["upgrades"] = upgrades
        out["upgrade_ids"] = ids
        out["upgrade_out"] = outside
    out["cast"] = list(cast)
    name = "%s_sitio_n%d.json" % (btype, level)   # a file that serves several levels still carries the first in its name
    write(os.path.join(OUT, name), out)
    return name


def write(path, out):
    """one entry of a list per line: the files are meant to be read and edited"""
    lines = ["{"]
    keys = list(out)
    for i, k in enumerate(keys):
        v = out[k]
        end = "," if i < len(keys) - 1 else ""
        if isinstance(v, list) and v and isinstance(v[0], dict) and k != "open":
            lines.append('  %s: [' % json.dumps(k))
            for j, e in enumerate(v):
                if k == "cast":
                    lines.append('    {%s, "steps": [' % json.dumps({a: b for a, b in e.items() if a != "steps"}, ensure_ascii=False)[1:-1])
                    for n, s in enumerate(e["steps"]):
                        lines.append('      %s%s' % (json.dumps(s, ensure_ascii=False), "," if n < len(e["steps"]) - 1 else ""))
                    lines.append('    ]}%s' % ("," if j < len(v) - 1 else ""))
                else:
                    lines.append('    %s%s' % (json.dumps(e, ensure_ascii=False), "," if j < len(v) - 1 else ""))
            lines.append('  ]%s' % end)
        elif isinstance(v, dict) and k in ("stations", "upgrades", "upgrade_ids", "upgrade_out"):
            lines.append('  %s: {' % json.dumps(k))
            ks = list(v)
            for j, z in enumerate(ks):
                lines.append('    %s: %s%s' % (json.dumps(z), json.dumps(v[z], ensure_ascii=False), "," if j < len(ks) - 1 else ""))
            lines.append('  }%s' % end)
        else:
            lines.append('  %s: %s%s' % (json.dumps(k), json.dumps(v, ensure_ascii=False), end))
    lines.append("}")
    open(path, "w").write("\n".join(lines) + "\n")


def window(cs, d):
    """customers of a fold-down shop counter on front cell tile cs: they buy from the street"""
    R = d - 2
    return {"counter": [{"tile": [cs, R + 2]}], "reach": 1.2, "street": [[cs + 8.0, R + 2.6], [cs + 0.6, R + 2.6]]}


def counter(cs, d, **kw):
    """the station of a fold-down shop counter (the house's own shop module) on the front cell over tile cs"""
    R = d - 2
    return {"name": "Mostrador", "kind": "sales", "floor": 0, "tile": [cs, R + 1], "stand": [cs, R], "reach": 0.95, **kw}


# ====================================================================== the upgrades of each trade
def ups_forge(level):
    u = {
        # the second anvil by the shop window, where the street sees the work; found by the search it stood on the
        # only way to the shed and the counter
        "forge_anvil_2": [{"zone": "anvil_2", "id": "_anvil", "name": "Yunque 2", "kind": "craft", "floor": 0, "tile": [2, 3], "pos": [2.0, 3.2], "rot": 90,
                           "stand": [3, 3], "reach": 0.78}] if level > 1 else
                         [NEEDS("nivel", "el segundo yunque no cabe en la forja de 6 × 4 m sin cerrar el paso: llega con la de 6 × 6")],
        "forge_furnace_2": [NEEDS("anexo", "una segunda fragua pide otro cobertizo con su chimenea, o la casa de 8 m")],
        "upgrade_storage_shelves": [A("alacena", "anvil", or_needs="anexo", or_note="las paredes del taller están llenas: van bajo el cobertizo del almacén")],
        "upgrade_counter": [A("armero_estrecho", "door", or_needs="anexo", or_note="las paredes del taller están llenas: va bajo el cobertizo del almacén")],
        # the bellows against the back wall beside the furnace, the stone trough by the anvil on the left wall (both pockets
        # off the way): found by the search they had no place once the second anvil and the stair kept theirs
        "forge_bellows": [{"id": "fuelle", "floor": 0, "tile": [4, 0], "snap": "back"} if level > 1 else {"id": "fuelle", "floor": 0, "tile": [4, 2], "snap": "right"}],
        "forge_tempering_tub": [BASE("pila")],
        "forge_master_furnace": [SW("furnace", "_furnace_master")],
        "forge_quench_trough": [{"id": "stone_trough", "floor": 0, "tile": [2, 1], "snap": "left"}] if level > 1 else
                               [NEEDS("nivel", "la pila de piedra no cabe junto al yunque de la forja de 6 × 4 m sin cerrar el almacén: llega con la de 6 × 6")],
        "forge_engraving_bench": [A("escritorio", "door", or_needs="patio", or_note="la casa crece 2 m sobre su patio (la forja de 6 × 8)")],
        "forge_master_seal": [A("escudo_pared", "door")],
        "upgrade_master_bench": [A("banco_carpintero", "anvil", or_needs="patio", or_note="la casa crece 2 m sobre su patio (la forja de 6 × 8)")],
    }
    if level == 1:
        u.update(common_ups(None, "", "", ["storage"], False))
        u["upgrade_double_ledger"] = [NEEDS("planta", "no hay mesa ni escritorio en el nivel 1")]
    else:
        u.update(common_ups(1, "cama", "mesa_cocina", ["mesa_cocina"], True))
        u["upgrade_dining_table"] = [BUILT("la mesa de la cocina ya es la grande")]
    return u


def ups_tailor(home_f, big):
    u = {
        "tailor_shop_sewing_table_2": [Z("sewing_table_2", "Mesa de corte 2", "mesa_corte", "sewing_table")],
        "tailor_shop_loom_2": [Z("loom_2", "Telar 2", "telar", "loom")],
        "upgrade_storage_shelves": [A("estante_panos", "storage")],
        "upgrade_counter": [A("maniqui", "door")],
        "tailor_treadle": [A("taburete", "loom", mode="floor")],
        "tailor_shuttle": [A("estante_pared", "loom")],
        "tailor_master_table": [A("maniqui", "sewing_table")],
        "tailor_shears": [A("panel_herramientas", "sewing_table")],
        "tailor_dyes": [A("tina_tinte", "storage")],
        "tailor_seal": [A("escudo_pared", "door")],
        "upgrade_master_bench": [A("taburete", "sewing_table", mode="floor")],
    }
    u.update(common_ups(home_f, "bed", "mesa_casa", ["mesa_casa", "sewing_table"], big))
    if big:
        u["upgrade_bunks"] = [SW("cama_b", "litera")]
    return u


def ups_carpentry(home_f, torno_base):
    u = {
        # in the houses of 6 x 6 m the second bench goes against the right wall, past the sawhorses, its worker off the way
        # to the first one (the search put it where it closed the way to the bench and the sawhorses)
        "carpentry_workbench_2": [{"zone": "workbench_2", "id": "banco_carpintero", "name": "Banco 2", "kind": "craft", "floor": 0, "tile": [4, 2], "pos": [4, 2.5],
                                   "snap": "right", "stand": [3, 3]}] if home_f is not None else [Z("workbench_2", "Banco 2", "banco_carpintero", "workbench")],
        "carpentry_sawhorse_2": [Z("sawhorse_2", "Caballetes 2", "caballetes", "sawhorse", or_needs="patio", or_note="bajo el cobertizo del patio, que el tipo trae desde el nivel 2")],
        "upgrade_storage_shelves": [A("estante_tablones", "storage")],
        "upgrade_counter": [A("estante_pared", "door")],
        "carpentry_frame_saw": [A("panel_herramientas", "sawhorse")],
        "carpentry_vice_bench": [BUILT("el banco de carpintero ya lleva su tornillo")],
        "carpentry_master_bench": [BASE("torno")] if torno_base else [A("torno_pedal", "workbench")],
        "carpentry_planes": [A("estante_pared", "workbench")],
        "carpentry_gouges": [A("panel_herramientas", "workbench")],
        "carpentry_mark": [A("escudo_pared", "door")],
        "upgrade_master_bench": [A("arcon", "workbench")],
    }
    u.update(common_ups(home_f, "cama_b", "mesa_casa", ["mesa_casa", "workbench"], home_f is not None))
    return u


def ups_bank(level):
    home = {1: None, 2: 1, 3: 1}[level]
    u = {
        "upgrade_storage_shelves": [A("arca_fuerte", "storage")],
        "bank_ledgers": [A("cesto_legajos", "ledger", mode="floor")],
        "bank_vault_door": [BUILT("la cámara es la sala del fondo, tras el tabique")] if level == 3 else
                           [NEEDS("nivel", "la cámara acorazada es una sala propia: llega con la casa de 6 × 8 m del nivel 3")],
        "bank_sign": [A("escudo_pared", "door")],
        "bank_clerk_desk": [Z("desk_2", "Escribiente", "escritorio", "ledger", kind="service")],
        "bank_branch": [A("banco", "door")],
        "bank_exchange": [A("mesa_estrecha", "desk", name="mesa_cambio"), ON(["mesa_cambio"], "balanza")],
        "bank_report": [A("q:BookStand", "ledger", mode="floor")],
        "bank_guarantees": [A("sack", "storage", mode="floor", walk=True)],
        "bank_bonds": [A("arcon", "storage")],
        "upgrade_master_bench": [A("q:BookStand", "desk", mode="floor")],
    }
    u.update(common_ups(home, "cama_b", "mesa_casa", ["mesa_casa", "ledger"], False))
    if home is not None:
        u["upgrade_dining_table"] = [BUILT("la vivienda ya tiene la mesa larga con su banco")] if level == 3 else [A("mesa_1x1", "mesa_casa", f=1, mode="floor")]
    u["upgrade_double_ledger"] = [ON(["mesa_cambio", "mesa_casa"], "q:Book_Stack_2", off=(-0.3, 0.0))] if home is not None else [A("q:BookStand", "storage", mode="floor")]
    return u


def ups_clinic(level):
    home = {1: None, 2: 1, 3: 1}[level]
    u = {
        "upgrade_storage_shelves": [A("alacena", "storage")],
        "clinic_mortar_2": [Z("mortar_2", "Mesa de curas 2", "mesa_curas", "mortar")],
        "clinic_shelves_big": [A("arcon", "storage")],
        "clinic_sign": [A("pergamino_pared", "door")],
        "clinic_cot_2": [BASE("catre2")] if level == 3 else [Z("cot_2", "Catre 2", "catre", "cot", kind="service")],
        "clinic_instruments": [A("estante_pared", "cot")],
        "clinic_operating_table": [SW("cot", "mesa_operaciones")],
        "clinic_herbal": [A("botica", "mortar")],
        "clinic_books": [A("q:BookStand", "mortar", mode="floor")],
        "clinic_anatomy": [A("pergamino_pared", "cot")],
        "upgrade_master_bench": [A("q:BookStand", "door", mode="floor")],
    }
    u.update(common_ups(home, "bed" if level == 2 else "cama_b", "mesa_casa", ["mesa_casa", "mortar"], level == 3))
    return u


def ups_masonry(level):
    home = None if level == 1 else 1
    yard = "va al patio: el taller de cantería sigue fuera"
    u = {
        # the second carving bench in the front corner right of the door, its worker beside the door (the search put it
        # behind the first one, reached only through the places of the other two benches)
        "masonry_carving_bench_2": [{"zone": "carving_bench_2", "id": "banco_labra", "name": "Labra fina 2", "kind": "craft", "floor": 0, "tile": [4, 4], "pos": [4, 4],
                                     "snap": "right", "stand": [3, 4]}] if level > 1 else
                                   [NEEDS("nivel", "el segundo banco de labra fina solo cabe detrás del primero en el taller de 6 × 4 m: llega con el de 6 × 6")],
        "masonry_cutting_bench_2": [NEEDS("patio", "el segundo banco de desbaste " + yard)],
        "upgrade_storage_shelves": [A("alacena", "storage")],
        "upgrade_counter": [A("estante_pared", "door")],
        "masonry_wedges": [A("arcon", "cutting_bench")],
        "masonry_crane": [NEEDS("patio", "la grúa va en el patio (el tipo ya la pone desde el nivel 2)")],
        "masonry_master_yard": [NEEDS("patio", "el patio del maestro " + yard)],
        "masonry_chisels": [A("panel_herramientas", "carving_bench")],
        "masonry_templates": [BASE("plantillas")],
        "masonry_mark": [A("escudo_pared", "door")],
        "upgrade_master_bench": [A("arcon", "carving_bench")],
    }
    u.update(common_ups(home, "cama_b", "mesa_casa", ["mesa_casa"], home is not None))
    if home is None:
        u["upgrade_double_ledger"] = [NEEDS("planta", "no hay mesa ni escritorio en el nivel 1")]
    return u


def ups_tavern(level):
    big = level > 1
    return {
        "inn_menu_board": [A("pergamino_pared", "bar")],
        # the minstrel by the long table, against the front wall left of the door (the search sat him in the way)
        "inn_minstrel": [{"zone": "minstrel_corner", "id": "taburete", "name": "Rincón del juglar", "kind": "service", "floor": 0, "tile": [2, 4], "pos": [2.1, 4.2],
                          "stand": [2, 4]}] if big else [Z("minstrel_corner", "Rincón del juglar", "taburete", "tables", kind="service", mode="floor")],
        "inn_gaming": [BASE("gaming_table")] if big else [NEEDS("nivel", "la mesa de juego cerraba el lado de la barra donde piden los clientes: llega con la sala de 8 × 6 m")],
        "inn_barrels": [A("barrel", "storage"), A("barrel", "storage")],
        "inn_reserve": [A("botellero", "bar")],
        "inn_cave": [NEEDS("sótano", "la cueva de toneles pide un sótano que la casa no tiene")],
        "inn_more_tables": [NEEDS("anexo", "no cabe otra mesa en la sala sin ponerla detrás de la barra o delante de ella: pide la galería o un anexo")],
        "inn_hearth": [NEEDS("nivel", "una chimenea de salón pide un paño de muro libre con su tiro hasta el tejado: no lo hay")],
        "inn_tapestries": [A("tapiz", "tables")],
        "inn_oven": [BUILT("la cocina ya tiene el hogar grande con su caldero")] if big else
                    [NEEDS("nivel", "el hogar grande no cabe en la cocina de la taberna de 6 × 6 m")],
        "inn_spit": [A("estante_pared", "kitchen")],
        "inn_pantry": [A("alacena", "kitchen")],
        "inn_more_beds": [A("cama_huesped", "rooms", f=1)],
        "inn_good_room": [A("tapiz", "rooms", f=1), A("arcon", "rooms", f=1)],
        "inn_stable": [NEEDS("anexo", "el establo es un anexo en el patio")],
        "inn_porter": [{"id": "taburete", "floor": 0, "pos": [3.05, 4.25]}] if big else [A("taburete", "door", mode="floor")],
        "inn_cellar_lock": [A("arca_fuerte", "storage")],
        "inn_porter_room": [A("arcon", "door")],
    }


INN_IDS = {"tavern_inn_ambience_2": "inn_minstrel", "tavern_inn_ambience_3": "inn_gaming"}


def ups_farm(level):
    home = 0 if level == 1 else 1
    u = {
        "farm_granary": [A("sack_pile", "storage")],
        "upgrade_storage_shelves": [A("alacena", "storage")],
        "farm_barn": [A("crates_small", "storage")],
        "farm_cart": [A("barrel", "door")],
        "farm_fair_stand": [A("q:FarmCrate_Apple", "door", mode="floor")],
        "farm_brand": [A("escudo_pared", "door")],
        "farm_iron_plough": [BASE("aperos")],
        "farm_fields_2": [NEEDS("fuera", "los campos están fuera de la casa")],
        "farm_pen_2": [NEEDS("anexo", "el segundo corral son las cuadras del cobertizo, que el tipo trae en el nivel 2")],
        "farm_manure": [A("q:Bucket_Wooden_1", "pen", mode="floor")],
        "farm_rotation": [A("cesto_fruta", "storage", mode="floor")],
        "farm_select_seed": [A("sack", "storage", mode="floor", walk=True)],
        "upgrade_master_bench": [A("q:BookStand", "door", mode="floor")],
    }
    u.update(common_ups(home, "bed" if level == 1 else "cama_b", "mesa_casa", ["mesa_casa"], False))
    u["upgrade_dining_table"] = [A("taburete", "mesa_casa", f=home, mode="floor")]
    return u


# ====================================================================== houses
def house_humble():
    building("house_humble", 1, 4, 4, 1,
             "A humble house at level 1: one room of 4 x 4 m (3 x 3 tiles): bed, hearth, chest, a stool by the fire.",
             [room("home", 0, "kitchen", (0, 0, 2, 2), "kitchen", "stone")],
             {"hearth": S("Hogar", "home", 2, 0, (1, 0), "hogar_cocina", "back"),
              "bed": S("Cama", "rest", 0, 0, (1, 1), "cama_estrecha", "back,left")},
             [P("arcon", 0, 2, "left,front", gap=0.03),
              P("taburete", 2.2, 0.95, rot=180, name="taburete"),
              P("estante_pared", 2, 1, "right"),
              P("perchero", 0, 1, "left"),
              P("ollas_colgadas", 1, 0, "back"),
              P("ristra_ajos", 2, 2, "right"),
              P("alfombra_esparto", 1, 1, rot=0),
              P("palmatoria", 0, 2, y=0.5),
              P("orinal", 0.62, 0.05)],
             [who("Campesina", "Vecina", [zone("hearth", "guisa en el hogar", 8, "stir"),
                                          sit("taburete", "se calienta junto al fuego", 7, look=(2, 0))], start=(0, 1, 1)),
              who("Labrador", "Vecino", [ENTER, lie("bed", secs=9),
                                         at(0, 1, 2, "busca en el arcón", 3, "Interact", look=(0, 2)), leave(4)], wait=3)],
             spots={"kitchen": [0, [2, 1]], "bed": [0, [1, 1]], "shop": [0, [1, 1]]})
    building("house_humble", 2, 4, 6, 1,
             "A humble house at level 2: one room of 4 x 6 m (3 x 5 tiles): the bed and the cradle at the back, the hearth on the side wall, table and cupboard by the door.",
             [room("home", 0, "kitchen", (0, 0, 2, 4), "kitchen", "stone")],
             {"hearth": S("Hogar", "home", 2, 2, (1, 2), "hogar_cocina", "right"),
              "bed": S("Cama", "rest", 0, 0, (1, 1), "cama_estrecha", "back,left")},
             [P("cuna", 2, 0, "back,right", name="cuna"),
              P("alacena", 1, 0, "back"),
              P("arcon", 0, 2, "left", gap=0.02),
              P("mesa_estrecha", 0, 3, "left", gap=0.02),
              P("taburete", 0.3, 3.0, name="tab1"),
              P("taburete", 0.1, 4.2, name="tab2"),
              P("estante_pared", 0, 3, "left"),
              P("perchero", 2, 3, "right"),
              P("ollas_colgadas", 2, 1, "right"),
              P("ristra_ajos", 1, 4, "front"),
              P("alfombra_esparto", 1, 2, rot=0),
              P("palmatoria", -0.45, 3.0, y=0.76),
              P("mantequera", 2.1, 0.95)],
             [who("Campesina", "Madre", [zone("hearth", "guisa en el hogar", 8, "stir"),
                                         at(0, 2, 1, "mece la cuna", 5, "Interact", look=(2, 0)),
                                         sit("tab1", "come a la mesa", 6, "eat", look=(0, 3))], start=(0, 1, 2)),
              # the hearth's tile is the only way to the back of the room: only the mother goes past it (bed and
              # cradle); the others stay at the front, so nobody has to walk through her
              who("Labrador", "Padre", [ENTER, sit("tab2", "descansa", 9, "drink", look=(0, 3)), leave(5)], wait=2),
              who("Moza", "Hija", [at(0, 2, 4, "mira por la ventana", 6, look=(2, 5)), at(0, 2, 3, "juega", 6, "Idle_Talking", look=(1, 3))],
                  start=(0, 2, 4), age=9)],
             spots={"kitchen": [0, [1, 3]], "bed": [0, [1, 1]], "shop": [0, [1, 2]]})
    building("house_humble", 3, 4, 6, 2,
             "A humble house at level 3: 4 x 6 m on two floors. Below, the kitchen with the hearth; a steep stair against the left wall; above, the beds.",
             [room("kitchen", 0, "kitchen", (0, 0, 2, 4), "kitchen", "stone"), room("bedroom", 1, "bedroom", (0, 0, 2, 4), "dim_warm")],
             {"hearth": S("Hogar", "home", 2, 0, (2, 1), "hogar_cocina", "back"),
              "bed": S("Camas", "rest", 2, 1.55, (1, 1), "cama_estrecha", "right", f=1, rot=0)},
             [P("arcon", 2, 2, "right", gap=0.02),
              P("mesa_estrecha", 0, 3, "left", gap=0.02),
              P("taburete", 0.3, 3.0, name="tab1"),
              P("taburete", 0.1, 4.2, name="tab2"),
              P("alacena", 2, 3, "right"),
              P("estante_pared", 0, 3, "left"),
              P("tiro", 2, 0, "back", f=1),
              P("cama_estrecha", 0, 3.55, "left", f=1, rot=180, name="cama2"),
              P("cuna", 2, 3, "right", f=1),
              P("arcon", 2, 4, "right,front", f=1, gap=0.03),
              P("perchero", 1, 4, "front", f=1),
              P("ollas_colgadas", 1, 0, "back"),
              P("ristra_ajos", 2, 1, "right"),
              P("alfombra_esparto", 1, 2, rot=0),
              P("palmatoria", -0.45, 3.0, y=0.76),
              P("orinal", 1.3, 2.0, f=1),
              P("hierbas_secas", 1, 0, "back", f=1),
              P("palangana_jarro", 0, 0, "left,back", f=1, gap=0.05),
              P("rueca", 0, 1.5, "left", f=1, name="rueca"),
              P("taburete", 0.9, 1.5, f=1, name="tab_rueca")],
             [who("Campesina", "Madre", [zone("hearth", "guisa en el hogar", 8, "stir"), sit("tab1", "come a la mesa", 6, "eat", look=(0, 3)),
                                         at(1, 1, 3, "mira la cuna", 5, "Interact", look=(2, 3))], start=(0, 1, 2)),
              who("Labrador", "Padre", [ENTER, sit("tab2", "descansa", 6, "drink", look=(0, 3)), lie("bed", secs=10), leave(5)], wait=2),
              who("Vieja", "Abuela", [lie("cama2", secs=12), sit("tab_rueca", "hila en la rueca", 7, "sit_bench", look=(0, 1))], start=(1, 1, 3))],
             stairs=[stair("left", 4, 6)],
             spots={"kitchen": [0, [1, 3]], "bed": [1, [1, 1]], "shop": [0, [1, 2]], "cradle": [1, [1, 3]]})


def house_well():
    # 4 x 6 m on two floors: the humble house's plan, better furnished
    building("house_well", 1, 4, 6, 2,
             "A well-off house at level 1: 4 x 6 m on two floors. Below, kitchen and table with a bench; above, bedroom with a bunk for the children.",
             [room("kitchen", 0, "kitchen", (0, 0, 2, 4), "kitchen", "stone"), room("bedroom", 1, "bedroom", (0, 0, 2, 4), "dim_warm")],
             {"hearth": S("Hogar", "home", 2, 0, (2, 1), "hogar_cocina", "back"),
              "bed": S("Camas", "rest", 2, 1.55, (1, 1), "cama_estrecha", "right", f=1, rot=0)},
             [P("alacena", 2, 2, "right"),
              P("banco", -0.01, 3.4, "left", rot=90, name="banco"),
              P("mesa_estrecha", 0.0, 3.4, rot=90),
              P("taburete", 0.72, 3.2, name="tab1"),
              P("arcon", 2, 3.05, "right", gap=0.02),
              P("tiro", 2, 0, "back", f=1),
              P("litera", 0, 3.55, "left", f=1, rot=180, name="litera"),
              P("arcon", 2, 3, "right", f=1, gap=0.02),
              P("perchero", 1, 4, "front", f=1),
              P("estante_pared", 2, 4, "right", f=1),
              P("ollas_colgadas", 1, 0, "back"),
              P("jamones", 0, 0, "back"),
              P("vasar_loza", 0, 1, "left"),
              P("alfombra_esparto", 1, 1.8, rot=0),
              P("palmatoria", 2.55, 3.05, y=0.5),
              P("orinal", 1.4, 1.55, f=1),
              P("hierbas_secas", 1, 0, "back", f=1),
              P("rueca", 0, 1.2, "left", f=1, name="rueca"),
              P("taburete", 0.8, 1.2, f=1, name="tab_rueca")],
             [who("Mercader", "Señora", [zone("hearth", "guisa en el hogar", 8, "stir"), sit("tab1", "come a la mesa", 6, "eat", look=(0, 3)),
                                         at(1, 1, 2, "ordena el arcón", 4, "Interact", look=(2, 3))], start=(0, 1, 1)),
              who("Noble", "Señor", [ENTER, sit("banco", "cena", 7, "eat"), lie("bed", secs=10), leave(5)], wait=2),
              who("Moza", "Hijo", [lie("litera", secs=9), at(1, 1, 3, "se viste", 3, look=(2, 3)), at(0, 1, 3, "desayuna", 4, "Idle_Talking", look=(0, 3))],
                  start=(1, 1, 2), age=11)],
             stairs=[stair("left", 4, 6)],
             spots={"kitchen": [0, [1, 3]], "bed": [1, [1, 1]], "shop": [0, [1, 2]]})
    for level, floors in ((2, 2), (3, 3)):
        rooms = [room("hall", 0, "kitchen", (0, 0, 4, 4), "kitchen", "stone"),
                 room("bedroom", 1, "bedroom", (0, 0, 4, 2), "dim_warm"), room("children", 1, "bedroom", (0, 3, 4, 4), "dim_warm")]
        props = [P("arcon", 0, 0, "left,back", gap=0.03),
                 P("alacena", 1, 0, "back"),
                 P("banco", -0.01, 2, "left", rot=90, name="banco"),
                 P("mesa_1x2", 0.1, 2, rot=90),
                 P("taburete", 0.85, 1.6, name="tab1"),
                 P("taburete", 0.85, 2.4, name="tab2"),
                 P("perchero", 0, 4, "left"),
                 P("estante_pared", 4, 1, "right"),
                 # upstairs: the bedroom at the back (two narrow beds side by side), the children's room at the front
                 P("cama_estrecha", 0.93, 0, "back", f=1, name="cama_b"),
                 P("tiro", 3, 0, "back", f=1),
                 P("arcon", 4, 0, "right,back", f=1, gap=0.03),
                 P("perchero", 4, 1, "right", f=1),
                 P("litera", 0, 3.5, "left", f=1, rot=180, name="litera"),
                 P("cuna", 1.2, 4, "front", f=1),
                 P("perchero", 2, 4, "front", f=1),
                 # the household things: pots and hams by the hearth, the plate rack and the garlic on the right wall,
                 # a mat under the table's end, a candle on the table; upstairs the chamber pot, herbs drying, the
                 # spinning wheel with its stool and a hand loom in the children's room
                 P("ollas_colgadas", 4, 0, "back"),
                 P("jamones", 2, 0, "back"),
                 P("vasar_loza", 4, 2, "right"),
                 P("ristra_ajos", 4, 3, "right"),
                 P("alfombra_esparto", 2, 2.5, rot=0),
                 P("palmatoria", 0.1, 1.6, y=0.76),
                 P("orinal", 0.5, 1.0, f=1),
                 P("hierbas_secas", 2, 0, "back", f=1),
                 P("rueca", 4, 2, "right", f=1, name="rueca"),
                 P("taburete", 3.2, 2, f=1, name="tab_rueca"),
                 P("telar_mano", 4, 3, "right", f=1, name="telar_mano"),
                 P("alfombra_esparto", 3.0, 3.5, f=1, rot=0)]
        stations = {"hearth": S("Hogar", "home", 3, 0, (3, 1), "hogar_cocina", "back"),
                    "bed": S("Cama", "rest", 0, 0, (2, 1), "cama_estrecha", "back,left", f=1)}
        cast = [who("Mercader", "Señora", [zone("hearth", "guisa en el hogar", 8, "stir"), sit("tab1", "come a la mesa", 6, "eat", look=(0, 2)),
                                           at(1, 2, 2, "se arregla", 4, "Interact", look=(2, 0))], start=(0, 2, 1)),
                who("Noble", "Señor", [ENTER, sit("banco", "cena", 7, "eat", off=[-0.3, 0]), lie("bed", secs=10), leave(5)], wait=2),
                who("Moza", "Hija", [lie("litera", secs=9), at(1, 2, 4, "mira la cuna", 4, "Interact", look=(1, 4)), sit("tab_rueca", "hila", 6, "sit_bench", look=(4, 2)),
                                     sit("tab2", "desayuna", 5, "eat", look=(0, 2))],
                    start=(1, 2, 3), age=12),
                who("Campesina", "Criada", [at(0, 2, 3, "barre", 6, "sweep"), at(0, 3, 2, "barre", 5, "sweep"), at(0, 1, 4, "barre", 4, "sweep")], start=(0, 3, 3))]
        stairs = [stair("right", 6, 6)]
        if floors == 3:
            rooms.append(room("attic", 2, "bedroom", (0, 0, 4, 4), "dim"))
            stairs.append(stair("right", 6, 6, 1))
            props += [P("tiro", 3, 0, "back", f=2),
                      P("jergon", 0, 0, "back,left", f=2, name="jergon1"),
                      P("jergon", 1.05, 0, "back", f=2, name="jergon2"),
                      P("arcon", 0, 3, "left", f=2, gap=0.02),
                      P("arcon", 0, 4, "left,front", f=2, gap=0.03),
                      P("perchero", 4, 1, "right", f=2),
                      P("mesa_estrecha", 1.5, 4, "front", f=2, gap=0.02),
                      P("taburete", 1.5, 3.2, f=2, name="tab3"),
                      P("alfombra_esparto", 2.5, 1.5, f=2, rot=0),
                      P("mantequera", 4, 3, "right", f=2, gap=0.05),
                      P("hierbas_secas", 3, 0, "back", f=2),
                      P("palangana_jarro", 4, 0, "right,back", f=2, gap=0.05)]
            cast[3]["steps"] += [lie("jergon1", "descansa en el desván", 8)]
        building("house_well", level, 6, 6, floors,
                 "A well-off house at level %d: 6 x 6 m on %d floors. Below, one room with the hearth and a long table; above, the bedroom and the children's room%s." % (
                     level, floors, "; in the attic, the servants' pallets" if floors == 3 else ""),
                 rooms, stations, props, cast, stairs=stairs,
                 doors=[{"floor": 1, "tile": [2, 3], "side": "ne"}],
                 spots={"kitchen": [0, [2, 2]], "bed": [1, [2, 1]], "shop": [0, [2, 3]], "cradle": [1, [1, 3]]})


def house_noble():
    """6 x 8, 8 x 8 and 8 x 10 m: the kitchen at the back behind a partition, the hall at the front with the long table;
    above, the master bedroom at the back and the children's room at the front; at level 3, the servants on top.
    The wide houses (levels 2 and 3) carry the noble furniture: a four-poster, wardrobe, dressing table, screen and
    washstand in the bedroom; a fireplace with armchairs, an iron lamp, a big rug, a writing desk and a harp in the hall;
    a chess table in the children's room"""
    for level, w, d, floors in ((1, 6, 8, 2), (2, 8, 8, 2), (3, 8, 10, 3)):
        W, D = w - 1, d - 1
        R = D - 1                      # the front row
        kb = 3 if d == 8 else 4        # rows of the back rooms
        dc = 2 if w == 6 else 4        # the column of the door, and of the door of the partitions
        wide = w == 8
        rooms = [room("kitchen", 0, "kitchen", (0, 0, W - 1, kb - 1), "kitchen", "stone"),
                 room("hall", 0, "shop", (0, kb, W - 1, R), "warm", "stone"),
                 room("bedroom", 1, "bedroom", (0, 0, W - 1, kb - 1), "dim_warm"),
                 room("children", 1, "bedroom", (0, kb, W - 1, R), "dim_warm")]
        hx = 1.5 if not wide else 1.6  # the kitchen hearth, on the back wall
        stations = {"hearth": S("Cocina", "home", hx, 0, (1, 1), "hogar_grande", "back")}
        if wide:
            stations["bed"] = S("Cama", "rest", W - 2.5, 0.6, (W - 4, 1), "cama_dosel", "back", f=1)
        else:
            stations["bed"] = S("Camas", "rest", W - 2, 0, (W - 2, 2), "cama_estrecha", "back", f=1)
        props = [P("alacena", W - 1, 0, "back"),
                 P("mesa_estrecha", 0, 0.6, "left", gap=0.02),
                 P("barrel", W - 0.8, kb - 1.2),
                 P("sack", W - 1.6, kb - 1.0, rot=30, walk=True),
                 # the kitchen's things: hams over the table's end, garlic, the plate rack, a mat before the hearth,
                 # a candle on the table, the butter churn by the sack
                 P("jamones", 0, 0, "left"),
                 P("ristra_ajos", 0, kb - 1, "left"),
                 P("vasar_loza", W - 1, 1, "right"),
                 P("alfombra_esparto", 2.5, 1.6, rot=0),
                 P("palmatoria", -0.45, 0.6, y=0.76),
                 P("mantequera", W - 2.4, kb - 1),
                 P("ollas_colgadas", 3.2, 0, "back") if wide else P("ristra_ajos", 3, 0, "back"),
                 # the hall: the long table with its benches, a chest with a painting over it, the iron lamp
                 P("banco", -0.01, kb + 1.5, "left", rot=90, name="banco"),
                 P("mesa_1x2", 0.1, kb + 1.5, rot=90),
                 P("taburete", 0.85, kb + 1.1, name="tab1"),
                 P("taburete", 0.85, kb + 1.9, name="tab2"),
                 P("arcon", 0, kb, "left", gap=0.02),
                 P("cuadro_paisaje", 0, kb, "left"),
                 P("perchero", dc - 1, R, "front"),
                 P("lampara_hierro", (W - 1) / 2.0 if not wide else 4.6, kb + 1.5 if not wide else kb + 0.9),
                 # upstairs
                 P("tiro", hx, 0, "back", f=1),
                 P("litera", 0, R - 0.5, "left", f=1, rot=180, name="litera"),
                 P("cuna", 1.2, R, "front", f=1),
                 P("arcon", 0, kb, "left", f=1, gap=0.02),
                 P("estante_pared", W - 1, kb, "right", f=1),
                 P("cuadro_retrato", 2, 0, "back", f=1)]
        if wide:
            props += [P("botellero", W - 2, 0, "back"),
                      # the hall: the fireplace on the front wall left of the door with two armchairs before it (on the
                      # right wall it stood on the foot of the stair), the big rug, the writing desk in the front corner,
                      # the harp right of the door, the armour and the floor candelabrum by the partition
                      P("hogar_repisa", 2.5, R, "front"),
                      P("sillon", 2.0, R - 1.05, rot=0, name="sillon1"),
                      P("sillon", 3.2, R - 1.05, rot=0, name="sillon2"),
                      P("alfombra_grande", 3, kb + 1.5, rot=0),
                      P("soporte_armadura", W - 1, kb, "right", gap=0.06),
                      P("candelabro_pie", 1, kb),
                      P("escritorio_atril", 0.6, R, "front,left", gap=0.02),
                      P("arpa", 5.2, R, "front", gap=0.05),
                      # the bedroom: the four-poster with the dowry chest (and a lute on it) at its foot, the wardrobe,
                      # the rug beside the bed, the dressing table, washstand and candelabrum on the right, the screen
                      # before the partition
                      P("arcon_rico", W - 2.5, 2.0, f=1, name="arcon_rico"),
                      P("laud", W - 2.5, 2.0, f=1, y=0.6, rot=25),
                      P("armario", 0, 0, "left,back", f=1, gap=0.02),
                      P("arca_fuerte", 0, kb - 1, "left", f=1, gap=0.03),
                      P("alfombra_mediana", 2.3, 1.0, f=1, rot=0),
                      P("tocador_espejo", W - 1, kb - 1, "right", f=1),
                      P("aguamanil", W - 1, 0, "right,back", f=1, gap=0.05),
                      P("candelabro_pie", W - 1, 1, "right", f=1, gap=0.05),
                      P("biombo", 1.5, kb - 1, f=1, rot=0),
                      # the children's room: the chess table with a stool, a small rug, an armchair in the front corner;
                      # the flue of the hall's fireplace up the front wall
                      P("tiro", 2.5, R, "front", f=1),
                      P("alacena", 4.3, R, "front", f=1),
                      P("mesa_ajedrez", 3.5, kb + 1, f=1),
                      P("taburete", 3.5, kb + 1.8, f=1, name="tab_aj"),
                      P("alfombra_pequena", 2.0, kb + 1.2, f=1, rot=0),
                      P("sillon", W - 1, R, "right,front", f=1, gap=0.03, name="sillon3")]
        else:
            props += [P("cama_estrecha", W - 1.07, 0, "back", f=1, name="cama_b"),
                      P("escritorio", W - 1, kb, "right", gap=0.03),
                      P("alfombra_pequena", (W - 1) / 2.0, kb + 1.5, rot=0),
                      P("arcon", 0, 0, "left,back", f=1, gap=0.03),
                      P("arca_fuerte", 0, 2 if kb == 3 else 3, "left", f=1, gap=0.03),
                      P("perchero", 0, 1, "left", f=1)]
        cast = [who("Moza", "Cocinera", [zone("hearth", "guisa en el caldero", 8, "stir"), zone("hearth", "sirve el guiso", 4, "ladle"), at(0, 1, 1, "prepara la mesa", 4, "PickUp_Table", look=(0, 1)),
                                         at(0, 1, kb + 1, "sirve la mesa", 3, "PickUp_Table", look=(0, kb + 1), carry=True)], start=(0, 1, 1))]
        if wide:
            cast += [who("Noble", "Señor", [ENTER, sit("banco", "cena", 7, "eat", off=[-0.3, 0]), at(0, 1, R - 1, "escribe en el atril", 5, "Interact", look=(0, R)),
                                           lie("bed", secs=10), leave(5)], wait=2),
                     who("Mercader", "Señora", [sit("tab1", "come a la mesa", 7, "eat", look=(0, kb + 1)), sit("sillon1", "lee junto al fuego", 7, "sit_talk", look=(2, R)),
                                                at(1, W - 2, kb - 1, "se arregla ante el espejo", 5, "Interact", look=(W - 1, kb - 1))], start=(0, 2, kb + 1)),
                     who("Campesina", "Hija", [lie("litera", secs=9), at(1, 2, R, "mira la cuna", 4, "Interact", look=(1, R)), sit("tab_aj", "juega al ajedrez", 6, "sit_talk", look=(3, kb + 1))],
                         start=(1, 2, kb + 1), age=12)]
        else:
            cast += [who("Noble", "Señor", [ENTER, sit("banco", "cena", 7, "eat", off=[-0.3, 0]), at(0, W - 2, kb, "repasa sus cuentas", 5, "Interact", look=(W - 1, kb)),
                                           lie("bed", secs=10), leave(5)], wait=2),
                     who("Mercader", "Señora", [sit("tab1", "come a la mesa", 7, "eat", look=(0, kb + 1)), at(1, 2, 2, "se arregla", 5, "Interact", look=(0, 2)), lie("cama_b", secs=9)], start=(0, 2, kb + 1)),
                     who("Campesina", "Hija", [lie("litera", secs=9), at(1, 2, R, "mira la cuna", 4, "Interact", look=(1, R)), sit("tab2", "desayuna", 5, "eat", look=(0, kb + 2))],
                         start=(1, 2, kb + 1), age=12)]
        # the stair against the right wall of the hall, climbing to the back from the front corner (it climbed to the
        # front, seen edge-on from the street); upstairs the bedroom door one tile left of the dowry chest
        stairs = [stair("right_back", w, d, shift=kb + 1)]
        doors = [{"floor": 0, "tile": [dc, kb], "side": "ne"}, {"floor": 1, "tile": [dc - 1 if wide else dc, kb], "side": "ne"}]
        if floors == 3:
            rooms.append(room("attic", 2, "bedroom", (0, 0, W - 1, R), "dim"))
            stairs.append(stair("right_back", w, d, 1, shift=kb + 1))
            props += [P("tiro", hx, 0, "back", f=2),
                      P("tiro", 2.5, R, "front", f=2),
                      P("jergon", 0, 0, "back,left", f=2, name="jergon1"),
                      P("jergon", W - 1, 0, "back,right", f=2, name="jergon2"),
                      P("jergon", 0, R - 0.5, "left", f=2, rot=180, name="jergon3"),
                      P("arcon", 0, 3, "left", f=2, gap=0.02),
                      P("arcon", W - 1, 3, "right", f=2, gap=0.02),
                      P("mesa_estrecha", 1.1, R, "front", f=2, gap=0.02),
                      P("taburete", 1.1, R - 0.8, f=2, name="tab4"),
                      P("perchero", 3, 0, "back", f=2),
                      # the servants' things: a mat, the spinning wheel with its stool, a hand loom, herbs drying,
                      # the basin, the butter churn and a chamber pot
                      P("alfombra_esparto", 3, 2, f=2, rot=0),
                      P("rueca", W - 1, 1.5, "right", f=2, name="rueca"),
                      P("taburete", W - 1.8, 1.5, f=2, name="tab_rueca"),
                      P("telar_mano", 1.5, 0, "back", f=2, name="telar_mano"),
                      P("hierbas_secas", 4.5, 0, "back", f=2),
                      P("palangana_jarro", 0, 2, "left", f=2, gap=0.05),
                      P("mantequera", 5.6, R, "front", f=2, gap=0.05),
                      P("orinal", 0.9, R - 0.9, f=2),
                      # and the household's stores kept up here: a third chest, the pots on the wall, a dresser of
                      # crockery, a shelf, a basket of fruit, the farm tools in the front corner, a candle on the table
                      P("arcon", W - 1, R - 1, "right", f=2, gap=0.02),
                      P("ollas_colgadas", 0, 5, "left", f=2),
                      P("vasar_loza", 5.2, 0, "back", f=2, gap=0.02),
                      P("estante_pared", 4.5, R, "front", f=2),
                      P("cesto_fruta", 4.3, R - 0.6, f=2),
                      P("aperos", W - 1, R, "right,front", f=2, gap=0.04),
                      P("palmatoria", 1.55, R + 0.05, y=0.76, f=2, rot=20)]
            cast.append(who("Labrador", "Criado", [at(0, 3, kb + 2, "barre el salón", 6, "sweep"), lie("jergon1", "descansa en el desván", 9)], start=(0, 3, kb + 2)))
            cast[0]["steps"].append(sit("tab_rueca", "hila en el desván", 6, "sit_bench", look=(W - 1, 1)))
        building("house_noble", level, w, d, floors,
                 "A noble house at level %d: %d x %d m on %d floors. Below, the kitchen with the big hearth behind a partition and the hall with the long table%s; above, the master bedroom at the back%s and the children's room at the front%s." % (
                     level, w, d, floors, ", a fireplace with armchairs, an iron lamp and a writing desk" if wide else "",
                     " with a four-poster, wardrobe, dressing table and screen" if wide else "", "; on top, the servants' pallets" if floors == 3 else ""),
                 rooms, stations, props, cast, stairs=stairs, doors=doors,
                 spots={"kitchen": [0, [2, kb + 1]], "bed": [1, [W - 4 if wide else W - 2, 1 if wide else 2]], "shop": [0, [dc, R - 1]], "cradle": [1, [1, R - 1]]})


# ====================================================================== town hall
def town_hall():
    """12 x 8 m (HouseBuilder's town hall, the ridge along the front), two floors at level 1 and three at levels 2 and
    3. Below, the council chamber: the council table under the mayor's chair and two settles at the back, the archive
    behind a partition on the left, the court on the right (the judge's dais, the dock, the bar and the public's
    settles); the stair against the right wall. Above, the mayor's office on the right (desk, strongbox, fireplace) and
    the clerks' room on the left; on top (levels 2 and 3), the old archive and the constable's cot."""
    w, d = 12, 8
    W, D = w - 1, d - 1          # 11 x 7 tiles
    R = D - 1                    # the front row (6)
    dc = DOOR_C[w]               # 6
    for level, floors in ((1, 2), (2, 3)):
        rooms = [room("council", 0, "shop", (3, 0, W - 1, R), "warm", "stone", "stone"),
                 room("archive", 0, "shop", (0, 0, 2, 2), "dim_warm", "stone", "stone"),
                 room("lobby", 0, "shop", (0, 3, 2, R), "warm", "stone", "stone"),
                 room("office", 1, "bedroom", (6, 0, W - 1, R), "warm"),
                 room("clerks", 1, "shop", (0, 0, 5, R), "warm")]
        # BLOCK_SHARE is 0.1: the table stands right of the mayor's chair and the settles end a hand short of the next
        # tile, so tiles (4, 0) and (4, 1) stay free and the chair's tile can be reached (the first aforo found it isolated)
        stations = {"council": S("Concejo", "service", 5.7, 1.0, (5, 2), "mesa_concejo", rot=0),
                    "archive": S("Archivo", "storage", 0, 1.2, (1, 1), "estante_archivo", "left"),
                    "court": S("Tribunal", "service", 9, 2, (9, 2), "banquillo", rot=180),
                    "desk": S("Despacho", "service", 8, 0, (8, 1), "escritorio_atril", "back", f=1)}
        props = [# the council, at the back wall: the mayor's chair between two settles, the table before them
                 P("silla_alcalde", 5, 0, "back", name="silla_alcalde"),
                 # a bench without a back on the left of the chair: the settle of 1.6 m went 0.3 m through the archive's
                 # partition, or closed the way to the chair
                 P("banco", 3.15, 0, "back", name="banco_c1"),
                 P("banco_respaldo", 7.2, 0, "back", name="banco_c2"),
                 P("urna_votos", 4.9, 1.0, y=0.78, rot=10),
                 P("alfombra_mediana", 5.7, 2.6, rot=0),
                 P("atril_pie", 2.8, 2.5, rot=180, name="atril"),
                 P("lampara_hierro", 6, 3.5),
                 P("pendon_villa", 4.8, R, "front", gap=0.05),
                 P("pendon_villa", 2.0, R, "front", gap=0.05),
                 P("pendon_villa", 0, 3.2, "left", gap=0.05),
                 P("candelabro_pie", 3, R, "front", gap=0.05),
                 P("cuadro_retrato", 8, R, "front"),
                 # the archive: shelves, the town's chest with its three locks, the clerk's table with the seal press
                 P("estante_archivo", 0, 0.05, "left,back"),
                 P("arca_villa", 1.5, 0, "back"),
                 P("mesa_estrecha", 2, 2, rot=0, name="mesa_archivo"),
                 P("prensa_sello", 2.25, 2, y=0.76, rot=-20),
                 P("cesto_legajos", 1, 2.2),
                 # the court: the dais with the judge's seat, the dock before it, the bar, the public's settles
                 P("estrado_juez", 9.05, 0, "back", name="estrado"),
                 P("barandilla", 9.05, 3.5, rot=0),
                 P("banco_respaldo", 8.6, 5.0, rot=180, name="banco_pub"),
                 P("escudo_pared", 9.05, 0, "back"),
                 # the lobby by the door: the peg rail, a bench, the notice
                 P("perchero", 1, R, "front"),
                 P("banco", 0, 4.5, "left", rot=90, name="banco_lobby"),
                 P("pergamino_pared", 0, R - 2.5, "left"),
                 # upstairs, the mayor's office (the desk is a standing lectern: no chair before it, where the mayor stands)
                 P("arca_fuerte", W - 1, 0, "right,back", f=1, gap=0.03),
                 P("estante_archivo", 6.5, 0, "back", f=1),
                 P("alfombra_mediana", 8, 2.5, f=1, rot=0),
                 P("sillon", W - 1, 1.6, "right", f=1, gap=0.03, name="sillon_despacho"),
                 P("cuadro_retrato", W - 1, 1.5, "right", f=1),
                 P("hogar_repisa", 7.5, R, "front", f=1),
                 P("pendon_villa", 9.15, 0, "back", f=1, gap=0.05),
                 P("candelabro_pie", 6.4, 1.2, f=1),
                 P("tapiz", 7, 0, "back", f=1),
                 # the clerks' room
                 P("escritorio", 0, 1, "left", f=1, gap=0.03, name="escr1"),
                 P("escritorio", 0, 3, "left", f=1, gap=0.03, name="escr2"),
                 P("estante_archivo", 2, 0, "back", f=1),
                 P("estante_archivo", 3.5, 0, "back", f=1),
                 P("mesa_estrecha", 3, 3, f=1, rot=90, name="mesa_clerks"),
                 P("taburete", 3.0, 2.1, f=1, name="tab_clerks"),
                 P("cesto_legajos", 1, 0.2, f=1),
                 P("perchero", 2, R, "front", f=1),
                 P("estante_pared", 4, R, "front", f=1),
                 P("balanza", 3, 3.2, y=0.76, f=1)]
        cast = [who("Noble", "Alcalde", [sit("silla_alcalde", "preside el concejo", 9, "sit_talk", look=(5, 2)), zone("desk", "despacha en su oficina", 7, "Interact")], start=(0, 5, 2)),
                who("Mercader", "Escribano", [zone("archive", "busca un legajo", 5, "Interact"), at(0, 3, 3, "lee en el atril", 6, "Interact", look=(3, 2)),
                                              sit("tab_clerks", "copia un registro", 6, "write_sit", look=(3, 3))], start=(0, 1, 1)),
                who("Mercader", "Concejal", [sit("banco_c1", "delibera", 8, "sit_talk", look=(5, 2), off=[0.4, 0]), sit("banco_c2", "delibera", 8, "sit_talk", look=(5, 2), off=[-0.4, 0])], start=(0, 4, 3)),
                who("Vieja", "Juez", [sit("estrado", "juzga", 9, "sit_talk", look=(9, 2), off=[0, -0.33]), at(0, 7, 2, "se levanta", 3, look=(9, 1))], start=(0, 7, 2)),
                who("Labrador", "Acusado", [ENTER, zone("court", "en el banquillo", 9, "Idle_Talking"), leave(4)], wait=3, looks=["Labrador", "Sereno", "Herrero", "Moza"]),
                who("Campesina", "Vecina", [ENTER, sit("banco_pub", "asiste al juicio", 9, "sit_bench", look=(9, 1), off=[0.4, 0]), leave(5)], wait=1.5, looks=["Campesina", "Mercader", "Guardia"])]
        # against the right wall of the court, climbing to the back from the front corner (it climbed to the front: seen
        # edge-on from the street, its landing on the office's fireplace)
        stairs = [stair("right_back", w, d, shift=4)]
        doors = [{"floor": 0, "tile": [3, 1], "side": "nw"}, {"floor": 0, "tile": [1, 3], "side": "ne"}, {"floor": 1, "tile": [6, 3], "side": "nw"}]
        if floors == 3:
            rooms.append(room("attic", 2, "bedroom", (0, 0, W - 1, R), "dim"))
            stairs.append(stair("right_back", w, d, 1, shift=4))
            props += [P("tiro", 7.5, R, "front", f=2),
                      P("estante_archivo", 1, 0, "back", f=2),
                      P("estante_archivo", 2.2, 0, "back", f=2),
                      P("arcon", 0, 2, "left", f=2, gap=0.02),
                      P("arcon", 0, 3, "left", f=2, gap=0.02),
                      P("cesto_legajos", 3.5, 0.3, f=2),
                      P("cesto_legajos", 4.2, 0.6, f=2),
                      P("catre", 5, 0, "back", f=2, name="catre"),
                      P("mesa_estrecha", 7, 0, "back", f=2, gap=0.02),
                      P("taburete", 7, 0.8, f=2, name="tab_attic"),
                      P("perchero", 9, 0, "back", f=2),
                      P("armero_estrecho", 6.1, R, "front", f=2),
                      P("soporte_armadura", 4.9, R, "front", f=2, gap=0.06)]
            cast.append(who("Guardia", "Alguacil", [at(0, 2, 5, "guarda la puerta", 7, look=(6, 6)), lie("catre", "descansa arriba", 8), sit("tab_attic", "come", 5, "eat", look=(7, 0))], start=(0, 2, 5)))
        building("town_hall", level, w, d, floors,
                 "The town hall at level %d: 12 x 8 m on %d floors. Below, the council chamber (the mayor's chair and two settles behind the council table), the archive on the left and the court on the right (the judge's dais, the dock, the bar, the public's settle); above, the mayor's office and the clerks' room%s." % (
                     level, floors, "; on top, the old archive and the constable's cot" if floors == 3 else ""),
                 rooms, stations, props, cast, stairs=stairs, doors=doors,
                 spots={"shop": [0, [dc, R - 1]], "kitchen": [1, [8, 2]], "bed": [2 if floors == 3 else 1, [5, 1] if floors == 3 else [8, 2]]},
                 for_levels=[2, 3] if level == 2 else None)


# ====================================================================== tavern
def tavern_inn():
    guests = ["Noble", "Cazadora", "Guardia", "Mercader"]
    # level 1: 6 x 6 m, two floors
    building("tavern_inn", 1, 6, 6, 2,
             "The tavern-inn at level 1: 6 x 6 m on two floors. Below, the taproom: the bar under the casks and the bottle rack, the kitchen hearth, two small tables; the stair against the left wall. Above, three guest beds.",
             [room("hall", 0, "shop", (0, 0, 4, 4), "warm", "stone"), room("rooms", 1, "bedroom", (0, 0, 4, 4), "dim_warm")],
             {"bar": S("Barra", "service", 3.5, 2, (3, 1), "barra", "right", rot=0),
              "storage": S("Barriles", "storage", 3.5, 0, (3, 1), "barriles_caballete", "back"),   # one place for the keeper
              "kitchen": S("Cocina", "craft", 0, 3, (1, 3), "hogar_cocina", "left"),
              "tables": S("Mesas", "service", 0, 4, (1, 4), "mesa_1x1", "front,left"),
              "rooms": S("Habitaciones", "service", 3, 0, (3, 2), "cama_huesped", "back", f=1)},
             [P("botellero", 2, 0, "back"),
              P("mesa_1x1", 4, 4, "front,right"),
              P("taburete", 1.05, 4.15, name="t1"),
              P("taburete", 3.0, 4.15, name="t2"),
              P("taburete", 4.1, 3.05, name="t3"),
              P("perchero", 1, 4, "front"),
              P("cama_huesped", 4, 0, "back,right", f=1, name="camaB"),
              P("cama_huesped", 1.5, 4, "front", f=1, rot=90, name="camaC"),
              P("tiro", 0, 3, "left", f=1),
              P("arcon", 4, 3, "right", f=1, gap=0.02),
              P("arcon", 0, 4, "left,front", f=1, gap=0.03),
              P("perchero", 2, 0, "back", f=1),
              P("taburete", 3.6, 4.1, f=1),
              P("ollas_colgadas", 0, 1, "left"),
              P("jamones", 0, 0, "left,back"),
              P("ristra_ajos", 1, 0, "back"),
              P("orinal", 1.9, 0.4, f=1),
              P("palangana_jarro", 0, 1, "left", f=1, gap=0.05),
              P("alfombra_esparto", 2, 2, f=1, rot=0)],
             [who("Tabernero", "Tabernero", [zone("bar", "sirve en la barra", 7, "serve"), zone("storage", "tira una jarra del barril", 4, "Interact")], start=(0, 3, 1)),
              who("Moza", "Cocinera", [zone("kitchen", "guisa en el hogar", 8, "stir"), zone("kitchen", "sirve el guiso", 4, "ladle"), at(0, 1, 4, "sirve la mesa", 3, "PickUp_Table", look=(0, 4), carry=True),
                                       at(0, 3, 4, "sirve la mesa", 3, "PickUp_Table", look=(4, 4))], start=(0, 1, 3)),
              who("Labrador", "Parroquiano", [ENTER, at(0, 3, 3, "pide en la barra", 5, "Idle_Talking", look=(3, 2)), sit("t1", "bebe", 9, "drink", look=(0, 4)), leave(4)],
                  wait=1.5, looks=["Labrador", "Sereno", "Herrero"]),
              who("Noble", "Huésped", [ENTER, sit("t2", "cena", 8, "eat", look=(4, 4)), lie("rooms", "duerme en su cama", 9), leave(5)], wait=5, looks=guests)],
             stairs=[stair("left", 6, 6)],
             spots={"shop": [0, [2, 3]], "kitchen": [0, [1, 3]], "bed": [1, [3, 2]]}, upgrades=ups_tavern(1), extra_ids=INN_IDS)
    # levels 2 and 3: 8 x 6 m, two and three floors
    for level, floors in ((2, 2), (3, 3)):
        rooms = [room("hall", 0, "shop", (0, 0, 6, 4), "warm", "stone"),
                 room("room_a", 1, "bedroom", (0, 0, 3, 4), "dim_warm"), room("room_b", 1, "bedroom", (4, 0, 6, 4), "dim_warm")]
        # the keeper stands behind the right half of the bar, in front of the casks: one place for both, so the way
        # behind the bar to the kitchen (4, 1) is not where somebody works
        stations = {"bar": S("Barra", "service", 2.5, 2, (3, 1), "barra", rot=0),
                    "storage": S("Barriles", "storage", 3.5, 0, (3, 1), "barriles_caballete", "back"),
                    "kitchen": S("Cocina", "craft", 5.6, 0, (5, 1), "hogar_grande", "back"),
                    "tables": S("Mesas", "service", 0.6, 3.7, (2, 3), "mesa_1x2", rot=90),
                    "gaming_table": S("Mesa de juego", "service", 6, 2, (5, 2), "mesa_juego", "right", gap=0.05),
                    "rooms": S("Habitaciones", "service", 2, 0, (2, 2), "cama_huesped", "back", f=1)}
        props = [P("botellero", 2, 0, "back"),
                 P("banco", 0, 3.9, "left", rot=90, name="bancoA"),
                 P("banco", 1.4, 3.7, rot=90, name="bancoB"),
                 P("mesa_1x1", 6, 4, "front,right"),
                 P("taburete", 5.0, 4.15, name="t1"),
                 P("taburete", 6.1, 3.05, name="t2"),
                 P("taburete", 5.05, 2.0, name="t3"),
                 P("taburete", 6.05, 1.05, name="t4"),
                 P("perchero", 3, 4, "front"),
                 # upstairs: two guest rooms
                 P("cama_huesped", 3, 0, "back", f=1, name="camaB"),
                 P("cama_huesped", 0, 3.6, "left", f=1, rot=180, name="camaC"),
                 P("arcon", 3, 4, "front", f=1, gap=0.02),
                 P("perchero", 1, 4, "front", f=1),
                 P("tiro", 5.6, 0, "back", f=1),
                 P("cama_huesped", 6, 1.5, "right", f=1, rot=0, name="camaD"),
                 P("cama_huesped", 6, 3.6, "right", f=1, rot=180, name="camaE"),
                 P("arcon", 4, 0, "back", f=1, gap=0.02),
                 P("mesa_estrecha", 4.5, 4, "front", f=1, gap=0.02),
                 P("taburete", 4.5, 3.25, f=1, name="t5"),
                 # the household things: pots by the big hearth, hams and garlic, a mat before the bar; upstairs the
                 # chamber pots, the basin by the stair head, a mat in the first room and herbs over the small table
                 P("ollas_colgadas", 6, 0.8, "right"),
                 P("jamones", 1, 0, "back"),
                 P("ristra_ajos", 6, 3, "right"),
                 P("alfombra_esparto", 4.5, 2.5, rot=0),
                 P("orinal", 2.1, 0.5, f=1),
                 P("orinal", 4.4, 0.9, f=1),
                 P("palangana_jarro", 1.2, 0, "back", f=1, gap=0.05),
                 P("alfombra_esparto", 2, 2.2, f=1, rot=0),
                 P("hierbas_secas", 4.5, 4, "front", f=1)]
        cast = [who("Tabernero", "Tabernero", [zone("bar", "sirve en la barra", 7, "serve"), zone("storage", "tira una jarra del barril", 4, "Interact")], start=(0, 3, 1)),
                who("Moza", "Cocinera", [zone("kitchen", "guisa en el caldero", 8, "stir"), zone("kitchen", "sirve el guiso", 4, "ladle"), at(0, 2, 4, "sirve la mesa larga", 3, "PickUp_Table", look=(1, 4), carry=True),
                                         at(0, 5, 3, "sirve la mesa", 3, "PickUp_Table", look=(6, 4))], start=(0, 5, 1)),
                who("Labrador", "Parroquiano", [ENTER, at(0, 2, 3, "pide en la barra", 5, "Idle_Talking", look=(2, 2)), sit("bancoB", "bebe en la mesa larga", 9, "drink", face=180), leave(4)],
                    wait=1.5, looks=["Labrador", "Sereno", "Herrero"]),
                who("Noble", "Huésped", [ENTER, sit("t3", "juega a los dados", 8, "sit_talk", look=(6, 2)), lie("camaD", "duerme en su cama", 9), leave(5)], wait=5, looks=guests)]
        stairs = [stair("left", 8, 6)]
        if floors == 3:
            rooms.append(room("keeper", 2, "bedroom", (0, 0, 6, 4), "dim_warm"))
            stairs.append(stair("left", 8, 6, 1))
            props += [P("tiro", 5.6, 0, "back", f=2),
                      P("cama_estrecha", 3, 0, "back", f=2, name="cama_dueno"),
                      P("cama_estrecha", 3.93, 0, "back", f=2),
                      P("arcon", 6, 0, "right,back", f=2, gap=0.03),
                      P("arca_fuerte", 6, 2, "right", f=2, gap=0.03),
                      P("mesa_estrecha", 1.5, 4, "front", f=2, gap=0.02),
                      P("taburete", 1.5, 3.25, f=2),
                      P("cama_huesped", 6, 3.6, "right", f=2, rot=180, name="camaF"),
                      P("alacena", 3.5, 4, "front", f=2),
                      P("perchero", 0, 3, "left", f=2),
                      P("alfombra_esparto", 2, 2, f=2, rot=0),
                      P("orinal", 2.1, 0.5, f=2),
                      P("vasar_loza", 5, 4, "front", f=2),
                      P("palangana_jarro", 1.2, 0, "back", f=2, gap=0.05)]
            cast[0]["steps"].append(lie("cama_dueno", "descansa arriba", 8))
        building("tavern_inn", level, 8, 6, floors,
                 "The tavern-inn at level %d: 8 x 6 m on %d floors. Below, the taproom: bar, casks, the big hearth with its cauldron, a long table with benches, a small table and the gaming table. Above, two rooms with four guest beds%s." % (
                     level, floors, "; on the top floor, the innkeeper's rooms and one more bed" if floors == 3 else ""),
                 rooms, stations, props, cast, stairs=stairs,
                 doors=[{"floor": 1, "tile": [4, 2], "side": "nw"}],
                 spots={"shop": [0, [4, 3]], "kitchen": [0, [5, 1]], "bed": [1, [2, 2]]}, upgrades=ups_tavern(level), extra_ids=INN_IDS)


# ====================================================================== the home floor of a trade
def home6(f, kids=False):
    """the home over a workshop of 6 x 6 m whose stair stands against the left wall: hearth on the right wall, two narrow
    beds side by side at the back, a table with a wall bench by the front left corner. Returns (stations, props, spots)"""
    st = {"hearth": S("Hogar", "home", 4, 1.4, (3, 2), "hogar_cocina", "right", f=f),
          "bed": S("Camas", "rest", 2, 0, (2, 2), "cama_estrecha", "back", f=f)}
    pr = [P("cama_estrecha", 2.93, 0, "back", f=f, name="cama_b"),
          P("alacena", 4, 0, "back", f=f),
          P("arcon", 4, 4, "right,front", f=f, gap=0.03),
          P("banco", -0.01, 3.4, "left", f=f, rot=90, name="banco_casa"),
          P("mesa_estrecha", 0.0, 3.4, f=f, rot=90, name="mesa_casa"),
          P("taburete", 0.75, 3.0, f=f, name="tab_casa"),
          P("perchero", 2, 4, "front", f=f)]
    if kids:
        pr.append(P("cuna", 3, 4, "front", f=f))
    return st, pr, {"kitchen": [f, [1, 3]], "bed": [f, [2, 2]], "kitchen_table": [0, 3]}


def home4(f, side="left", hearth=True, up=False):
    """the home over a workshop of 4 x 6 m: the bed against the wall opposite the stair, the hearth further on, table
    and cupboard on the stair's side. side = the wall of the stair (left: climbs to the back; right: right_back).
    up: a stair climbs on from this floor (its foot is the tile in front of the flight below): the cupboard goes to
    the far wall, between the bed and the hearth"""
    a, b = (2, 0) if side == "left" else (0, 2)      # a = the far wall column, b = the stair's wall column
    far, near = ("right", "left") if side == "left" else ("left", "right")
    st = {"bed": S("Cama", "rest", a, 0.55, (1, 1), "cama_estrecha", far, f=f, rot=0)}
    pr = [P("mesa_estrecha", b, 3, near, f=f, gap=0.02, name="mesa_casa"),
          P("taburete", 0.3 if side == "left" else 1.7, 3.0, f=f, name="tab_casa"),
          P("arcon", b, 4, near + ",front", f=f, gap=0.03),
          P("alacena", a if up else b, 2, far if up else near, f=f)]
    if hearth:
        st["hearth"] = S("Hogar", "home", a, 3, (1, 3), "hogar_cocina", far, f=f)
    else:
        pr.append(P("perchero", a, 3, far, f=f))
    return st, pr, {"kitchen": [f, [1, 3]], "bed": [f, [1, 1]], "kitchen_table": [b, 3]}


def family(f, sp, hearth=True, a=(1, 2), b=(1, 1)):
    """two people at home on floor f: who cooks and eats, who sleeps. sp: the spots of the home (its table); a, b: where they start"""
    cook = [zone("hearth", "guisa en el hogar", 7, "stir")] if hearth else [at(f, a[0], a[1], "ordena la casa", 5, "sweep")]
    return [who("Campesina", "Mujer", cook + [sit("tab_casa", "come a la mesa", 6, "eat", look=sp.get("kitchen_table", (0, 3)))], start=(f, a[0], a[1])),
            who("Vieja", "Abuela", [lie("bed", secs=11), at(f, b[0], b[1], "se levanta", 3)], start=(f, b[0], b[1]), wait=2)]


# ====================================================================== tailor
def tailor_shop():
    client = ["Noble", "Mercader", "Cazadora"]
    building("tailor_shop", 1, 4, 4, 1,
             "The tailor's at level 1: one room of 4 x 4 m: the loom at the back, the cutting table on the right wall, the cloth shelves by the shop window.",
             [room("workshop", 0, "workshop", (0, 0, 2, 2), "warm", "planks")],
             {"loom": S("Telar", "craft", 0.15, 0, (0, 1), "telar", "back,left"),
              "sewing_table": S("Mesa de corte", "craft", 2, 0.3, (1, 1), "mesa_corte", "right"),
              "storage": S("Paños", "storage", 0, 2, (1, 2), "estante_panos", "left")},
             [],
             [who("Tejedora", "Sastra", [zone("loom", "teje en el telar", 8, "weave"), zone("sewing_table", "corta el paño", 6, "cut_cloth"),
                                         zone("storage", "guarda un paño", 3, "Interact", carry=True)], start=(0, 1, 1)),
              who("Noble", "Cliente", [ENTER, at(0, 2, 2, "encarga un jubón", 6, "Idle_Talking", look=(2, 1)), leave(6)], wait=4, looks=client)],
             spots={"shop": [0, [1, 2]]}, upgrades=ups_tailor(None, False))
    st, pr, sp = home4(1, "left")
    building("tailor_shop", 2, 4, 6, 2,
             "The tailor's at level 2: 4 x 6 m on two floors. Below, the loom behind the shop window, the cutting table, the cloth shelves and a dress form; above, the home.",
             [room("workshop", 0, "workshop", (0, 0, 2, 4), "warm", "planks"), room("home", 1, "kitchen", (0, 0, 2, 4), "kitchen")],
             {"loom": S("Telar", "craft", 0, 3.3, (1, 3), "telar", "left"),
              "sewing_table": S("Mesa de corte", "craft", 2, 1.6, (1, 1), "mesa_corte", "right"),
              "storage": S("Paños", "storage", 2, 0, (1, 0), "estante_panos", "back"), **st},
             [P("maniqui", 2, 3, "right", gap=0.05)] + pr,
             [who("Tejedora", "Sastra", [zone("loom", "teje en el telar", 8, "weave"), zone("sewing_table", "corta el paño", 6, "cut_cloth"),
                                         zone("storage", "guarda un paño", 3, "Interact", carry=True)], start=(0, 1, 2)),
              who("Noble", "Cliente", [ENTER, at(0, 1, 4, "se prueba un jubón", 6, "Idle_Talking", look=(2, 3)), leave(6)], wait=4, looks=client)] + family(1, sp),
             stairs=[stair("left", 4, 6)], spots={"shop": [0, [1, 4]], **sp}, upgrades=ups_tailor(1, False))
    st, pr, sp = home6(1, kids=True)
    building("tailor_shop", 3, 6, 6, 3,
             "The tailor's at level 3: 6 x 6 m on three floors. Below, workshop and shop in one room: loom, cutting table, two cloth shelves, a counter by the door and a dress form in each shop window. Above, the home; on top, the apprentices.",
             [room("workshop", 0, "workshop", (0, 0, 4, 4), "warm", "planks"), room("home", 1, "kitchen", (0, 0, 4, 4), "kitchen"),
              room("attic", 2, "bedroom", (0, 0, 4, 4), "dim_warm")],
             {"loom": S("Telar", "craft", 2.6, 0, (2, 1), "telar", "back"),
              "sewing_table": S("Mesa de corte", "craft", 4, 2.3, (3, 2), "mesa_corte", "right"),
              "counter": S("Mostrador", "sales", 1, 3, (0, 3), "barra_corta", rot=90),
              "storage": S("Paños", "storage", 1, 0, (1, 1), "estante_panos", "back"), **st},
             [P("estante_panos", 4, 0, "back"),
              P("maniqui", 4, 4, "front,right", gap=0.08),
              P("maniqui", 0, 4, "front,left", gap=0.08)] + pr + [
              P("tiro", 4, 1.4, "right", f=2),
              P("litera", 0, 3.5, "left", f=2, rot=180, name="litera"),
              P("jergon", 2, 0, "back", f=2, name="jergon"),
              P("arcon", 4, 0, "right,back", f=2, gap=0.03),
              P("estante_panos", 4, 4, "right", f=2),
              P("perchero", 2, 4, "front", f=2)],
             [who("Tejedora", "Sastra", [zone("loom", "teje en el telar", 8, "weave"), zone("sewing_table", "corta el paño", 6, "cut_cloth"),
                                         zone("storage", "guarda un paño", 3, "Interact", carry=True)], start=(0, 2, 1)),
              who("Moza", "Aprendiza", [zone("counter", "atiende el mostrador", 9, "count_coins"), lie("litera", "descansa arriba", 8)], start=(0, 0, 3)),
              who("Noble", "Cliente", [ENTER, at(0, 2, 3, "encarga un vestido", 7, "Idle_Talking", look=(1, 3)), leave(6)], wait=3, looks=client)] + family(1, sp),
             stairs=[stair("left", 6, 6), stair("left", 6, 6, 1)], spots={"shop": [0, [2, 3]], **sp}, upgrades=ups_tailor(1, True))


# ====================================================================== carpenter
def carpentry():
    client = ["Labrador", "Mercader", "Sereno"]
    work = [zone("sawhorse", "sierra un tablón", 7, "saw_low"), zone("workbench", "cepilla un tablero", 7, "plane"),
            zone("storage", "deja la pieza", 3, "Interact", carry=True)]
    building("carpentry", 1, 6, 4, 1,
             "The carpenter's at level 1: one room of 6 x 4 m: the bench at the back, the sawhorses on the right wall, the board rack in the corner and a pallet to sleep on.",
             [room("workshop", 0, "workshop", (0, 0, 4, 2), "warm", "planks")],
             {"sawhorse": S("Caballetes", "craft", 4, 0.75, (3, 1), "caballetes", "right"),
              "workbench": S("Banco", "craft", 1.3, 0, (1, 1), "banco_carpintero", "back"),
              "storage": S("Tablones", "storage", 0, 0, (0, 1), "estante_tablones", "back")},
             # the pallet along the front wall right of the door: on the left it closed the way to the board rack, which
             # was only reached through the bench's place
             [P("jergon", 3.55, 2, "front", rot=90, name="jergon")],
             [who("Labrador", "Carpintero", work, start=(0, 2, 1)),
              who("Mercader", "Cliente", [ENTER, at(0, 2, 2, "encarga una mesa", 6, "Idle_Talking", look=(1, 0)), leave(7)], wait=5, looks=client)],
             spots={"shop": [0, [2, 2]], "bed": [0, [2, 2]]}, upgrades=ups_carpentry(None, False))
    for level in (2, 3):
        st, pr, sp = home6(1)
        stations = {"sawhorse": S("Caballetes", "craft", 4, 0.75, (3, 1), "caballetes", "right"),
                    "workbench": S("Banco", "craft", 2.5, 0, (2, 1), "banco_carpintero", "back"),
                    "storage": S("Tablones", "storage", 1, 0, (1, 1), "estante_tablones", "back"), **st}
        cast = [who("Labrador", "Carpintero", work, start=(0, 2, 2)),
                who("Herrero", "Oficial", [at(0, 1, 3, "tornea una pata", 9, "Interact", look=(0, 3)), at(0, 3, 3, "barre la viruta", 5, "sweep")], start=(0, 1, 3))]
        customers = None
        if level == 3:
            stations["counter"] = counter(4, 6)
            customers = window(4, 6)
            cast.append(who("Mercader", "Cliente", [ENTER, step("compra en el mostrador", 6, "Idle_Talking", window=True), leave(6)], wait=3, looks=client))
            cast[1]["steps"].append(zone("counter", "atiende el mostrador", 7))
        else:
            cast.append(who("Mercader", "Cliente", [ENTER, at(0, 2, 3, "encarga un arcón", 6, "Idle_Talking", look=(2, 0)), leave(7)], wait=4, looks=client))
        building("carpentry", level, 6, 6, 2,
                 "The carpenter's at level %d: 6 x 6 m on two floors. Below, the workshop: bench with its vise at the back, sawhorses, the pole lathe by the front wall, the board rack%s; above, the home." % (
                     level, "; a fold-down counter on the shop window" if level == 3 else ""),
                 [room("workshop", 0, "workshop", (0, 0, 4, 4), "warm", "planks"), room("home", 1, "kitchen", (0, 0, 4, 4), "kitchen")],
                 stations, [P("torno_pedal", 0, 3.3, "left", name="torno")] + pr, cast + family(1, sp),
                 stairs=[stair("left", 6, 6)], customers=customers, spots={"shop": [0, [2, 3]], **sp}, upgrades=ups_carpentry(1, True))


# ====================================================================== baker
def bakery():
    client = ["Campesina", "Vieja", "Moza", "Labrador"]
    bake = [zone("trough", "amasa en la artesa", 7, "knead"), zone("trough", "estira la masa", 5, "roll_dough"), zone("oven", "mete el pan con la pala", 6, "peel"),
            zone("storage", "pone el pan a enfriar", 3, "Interact", carry=True)]
    buy = who("Campesina", "Clienta", [ENTER, step("compra pan en el mostrador", 6, "Idle_Talking", window=True), leave(5)], wait=3, looks=client)
    building("bakery", 1, 4, 4, 1,
             "The bakery at level 1: one room of 4 x 4 m. The mouth of the oven is in the back wall (the oven stands outside, behind it), the kneading trough on the left, the bread shelves by the door, the fold-down counter on the shop window.",
             [room("bakehouse", 0, "workshop", (0, 0, 2, 2), "kitchen", "stone")],
             {"oven": S("Horno", "craft", 1.75, 0, (1, 1), "boca_horno", "back"),
              "trough": S("Artesa", "craft", 0, 0.4, (1, 1), "artesa", "left"),
              "storage": S("Pan", "storage", 2, 1, (1, 2), "estante_pan", "right"),
              "counter": counter(0, 4)},
             [],
             [who("Tabernero", "Panadero", bake + [zone("counter", "atiende el mostrador", 7)], start=(0, 1, 1)), buy],
             customers=window(0, 4), spots={"shop": [0, [1, 2]]}, shell={"yard": ["back"]})
    for level, floors in ((2, 2), (3, 3)):
        st, pr, sp = home4(1, "right", up=floors == 3)
        rooms = [room("bakehouse", 0, "workshop", (0, 0, 2, 4), "kitchen", "stone"), room("home", 1, "kitchen", (0, 0, 2, 4), "kitchen")]
        stairs = [stair("right_back", 4, 6)]
        props = list(pr)
        cast = [who("Tabernero", "Panadero", bake, start=(0, 1, 1)),
                who("Moza", "Panadera", [zone("counter", "atiende el mostrador", 9), zone("storage", "coge una hogaza", 3, "Interact")], start=(0, 0, 4)), buy] + family(1, sp)
        if floors == 3:
            rooms.append(room("attic", 2, "bedroom", (0, 0, 2, 4), "dim_warm"))
            stairs.append(stair("right_back", 4, 6, 1))
            props += [P("tiro", 0, 3, "left", f=2),
                      P("cama_estrecha", 0, 0.55, "left", f=2, rot=0, name="cama_arriba"),
                      P("jergon", 2, 3.4, "right", f=2, rot=180, name="jergon"),
                      P("arcon", 0, 4, "left,front", f=2, gap=0.03),
                      P("perchero", 1, 4, "front", f=2)]
            cast[1]["steps"].append(lie("cama_arriba", "descansa arriba", 8))
        building("bakery", level, 4, 6, floors,
                 "The bakery at level %d: 4 x 6 m on %d floors, for a lot with its yard on the left (the oven stands there, against the back of the left wall). Below, the mouth of the oven, the kneading trough, the bread shelves and the counter on the shop window; the stair climbs along the right wall. Above, the home%s." % (
                     level, floors, "; on top, more beds" if floors == 3 else ""),
                 rooms,
                 {"oven": S("Horno", "craft", 0, 0.25, (1, 1), "boca_horno", "left"),
                  "trough": S("Artesa", "craft", 0, 2.05, (1, 2), "artesa", "left"),
                  "storage": S("Pan", "storage", 2, 3, (1, 3), "estante_pan", "right"),
                  "counter": counter(0, 6), **st},
                 props, cast, stairs=stairs, customers=window(0, 6), spots={"shop": [0, [1, 3]], **sp}, shell={"yard": ["left"]})


# ====================================================================== bank
def bank():
    client = ["Noble", "Mercader", "Guardia"]
    banker = [zone("desk", "atiende tras la reja", 8, "count_coins"), zone("ledger", "anota en el libro mayor", 6, "write"),
              zone("storage", "guarda el oro en el arca", 4, "Interact")]
    cli = who("Noble", "Cliente", [ENTER, sit("banco_cli", "espera su turno", 4, "sit_bench"), at(0, 1, 3, "pide un préstamo", 7, "Idle_Talking", look=(1, 2)), leave(6)], wait=2, looks=client)
    building("bank", 1, 4, 6, 1,
             "The bank at level 1: one room of 4 x 6 m cut in two by the counter with its iron grille: in front, the bench where clients wait; behind, the banker's desk and the strongbox.",
             [room("hall", 0, "shop", (0, 0, 2, 4), "warm", "stone")],
             {"desk": S("Mostrador", "service", 0.53, 2, (1, 1), "mostrador_reja", "left", rot=0),
              "ledger": S("Escritorio", "service", 2, 0, (2, 1), "escritorio", "back"),
              "storage": S("Arca", "storage", 0, 0, (0, 1), "arca_fuerte", "back,left")},
             [P("balanza", 0.3, 2.05, y=1.0),
              P("banco", 0, 3.6, "left", rot=90, name="banco_cli"),
              P("perchero", 2, 3, "right")],
             [who("Mercader", "Banquero", banker, start=(0, 1, 1)), cli],
             spots={"shop": [0, [1, 3]]}, upgrades=ups_bank(1))
    building("bank", 2, 6, 6, 2,
             "The bank at level 2: 6 x 6 m on two floors. Below, the counter with its grille from the left wall, two strongboxes and the desk behind it, the clients' bench in front; the stair climbs along the right wall to the back. Above, the home.",
             [room("hall", 0, "shop", (0, 0, 4, 4), "warm", "stone"), room("home", 1, "kitchen", (0, 0, 4, 4), "kitchen")],
             {"desk": S("Mostrador", "service", 0.5, 2, (1, 1), "mostrador_reja", "left", rot=0),
              "ledger": S("Escritorio", "service", 3, 0, (3, 1), "escritorio", "back"),
              "storage": S("Arcas", "storage", 0, 0, (1, 1), "arca_fuerte", "back,left"),   # from the counter's place: behind the grille
              "hearth": S("Hogar", "home", 0, 2, (1, 2), "hogar_cocina", "left", f=1),
              "bed": S("Camas", "rest", 0, 0, (2, 1), "cama_estrecha", "back,left", f=1)},
             [P("arca_fuerte", 1.05, 0, "back"),
              P("balanza", 0.3, 2.05, y=1.0),
              P("banco", 0, 3.6, "left", rot=90, name="banco_cli"),
              P("alacena", 4, 3, "right"),
              P("perchero", 1, 4, "front"),
              P("cama_estrecha", 0.93, 0, "back", f=1, name="cama_b"),
              P("alacena", 2, 0, "back", f=1),
              P("mesa_estrecha", 4, 3, "right", f=1, gap=0.02, name="mesa_casa"),
              P("taburete", 3.2, 3.0, f=1, name="tab_casa"),
              P("arcon", 4, 4, "right,front", f=1, gap=0.03),
              P("perchero", 2, 4, "front", f=1)],
             [who("Mercader", "Banquero", banker, start=(0, 1, 1)), cli] + family(1, {"kitchen_table": (4, 3)}, a=(3, 2), b=(2, 2)),
             stairs=[stair("right_back", 6, 6)], spots={"shop": [0, [2, 3]], "kitchen": [1, [1, 2]], "bed": [1, [1, 2]]}, upgrades=ups_bank(2))


    st_home = {"hearth": S("Hogar", "home", 0, 2, (1, 2), "hogar_cocina", "left", f=1),
               "bed": S("Camas", "rest", 0, 0, (2, 1), "cama_estrecha", "back,left", f=1)}
    building("bank", 3, 6, 8, 3,
             "The bank at level 3: 6 x 8 m on three floors. Below, the vault at the back behind a partition (three strongboxes, the shelves of deeds, the balance) and the hall: the counter with its grille, the desk, the clients' bench; the stair climbs from the front corner along the right wall to the back. Above, the home; on top, the clerks.",
             [room("vault", 0, "storage", (0, 0, 4, 2), "dim", "stone", "stone"), room("hall", 0, "shop", (0, 3, 4, 6), "warm", "stone"),
              room("home", 1, "kitchen", (0, 0, 4, 6), "kitchen"), room("attic", 2, "bedroom", (0, 0, 4, 6), "dim_warm")],
             {"desk": S("Mostrador", "service", 0.5, 4, (1, 3), "mostrador_reja", "left", rot=0),
              "ledger": S("Escritorio", "service", 4, 3, (3, 3), "escritorio", "right", gap=0.03),
              "storage": S("Cámara", "storage", 0, 0, (0, 1), "arca_fuerte", "back,left"), **st_home},
             [P("arca_fuerte", 1.05, 0, "back"),
              P("arca_fuerte", 2.1, 0, "back"),
              P("alacena", 4, 0, "back"),
              P("mesa_estrecha", 4, 1.6, "right", gap=0.02),
              P("balanza", 4.25, 1.6, y=0.76, rot=90),
              P("balanza", 0.3, 4.05, y=1.0),
              P("banco", 0, 5.6, "left", rot=90, name="banco_cli"),
              P("perchero", 1, 6, "front"),
              # the home
              P("cama_estrecha", 0.93, 0, "back", f=1, name="cama_b"),
              P("arcon", 4, 0, "right,back", f=1, gap=0.03),
              P("alacena", 3, 0, "back", f=1),
              P("mesa_estrecha", 4, 1.6, "right", f=1, gap=0.02, name="mesa_casa"),
              P("taburete", 3.2, 1.6, f=1, name="tab_casa"),
              P("banco", -0.01, 4.5, "left", f=1, rot=90),
              P("mesa_1x2", 0.1, 4.5, f=1, rot=90),
              P("perchero", 2, 6, "front", f=1),
              # the clerks' floor
              P("tiro", 0, 2, "left", f=2),
              P("litera", 0, 5.5, "left", f=2, rot=180, name="litera"),
              P("cama_estrecha", 2, 0, "back", f=2, name="cama_arriba"),
              P("arcon", 4, 0, "right,back", f=2, gap=0.03),
              P("escritorio", 4, 2, "right", f=2, gap=0.03),
              P("perchero", 2, 6, "front", f=2)],
             [who("Mercader", "Banquero", [zone("desk", "atiende tras la reja", 8, "count_coins"), zone("ledger", "anota en el libro mayor", 6, "write"),
                                           zone("storage", "guarda el oro en la cámara", 5, "Interact")], start=(0, 1, 3)),
              who("Sereno", "Escribiente", [at(0, 3, 1, "pesa las monedas", 7, "count_coins", look=(4, 1)), at(0, 3, 0, "busca una escritura", 4, "Interact", look=(4, 0)),
                                            lie("litera", "descansa arriba", 8)], start=(0, 3, 1)),
              who("Noble", "Cliente", [ENTER, sit("banco_cli", "espera su turno", 4, "sit_bench"), at(0, 1, 5, "pide un préstamo", 7, "Idle_Talking", look=(1, 4)), leave(6)],
                  wait=2, looks=client)] + family(1, {"kitchen_table": (4, 1)}, a=(3, 2), b=(2, 2)),
             stairs=[stair("right_back", 6, 8, shift=4), stair("right_back", 6, 8, 1, shift=4)], doors=[{"floor": 0, "tile": [2, 3], "side": "ne"}],
             spots={"shop": [0, [2, 5]], "kitchen": [1, [1, 2]], "bed": [1, [2, 1]]}, upgrades=ups_bank(3))


# ====================================================================== clinic
def clinic():
    sick = ["Vieja", "Labrador", "Campesina", "Sereno"]
    doctor = [zone("mortar", "muele hierbas en el mortero", 7, "stir"), zone("cot", "atiende al enfermo", 7, "tend"),
              zone("storage", "busca un remedio", 3, "Interact")]
    building("clinic", 1, 4, 4, 1,
             "The clinic at level 1: one room of 4 x 4 m: the cot against the left wall, the table of cures at the back, the apothecary cabinet on the wall by the door.",
             [room("surgery", 0, "workshop", (0, 0, 2, 2), "cool", "planks")],
             {"cot": S("Catre", "service", 0, 0, (1, 1), "catre", "back,left"),
              "mortar": S("Mesa de curas", "craft", 2, 0, (2, 1), "mesa_curas", "back"),
              "storage": S("Botica", "storage", 0, 2, (1, 2), "botica", "left")},
             [P("arcon", 1, 0, "back", gap=0.02)],
             [who("Sereno", "Médico", doctor, start=(0, 2, 1)),
              who("Vieja", "Enfermo", [ENTER, lie("cot", "espera en el catre", 12), leave(5)], wait=2, looks=sick)],
             spots={"shop": [0, [1, 2]]}, upgrades=ups_clinic(1))
    st, pr, sp = home4(1, "left")
    building("clinic", 2, 4, 6, 2,
             "The clinic at level 2: 4 x 6 m on two floors. Below, the cot, the table of cures, the apothecary cabinet and a bench to wait on; above, the home.",
             [room("surgery", 0, "workshop", (0, 0, 2, 4), "cool", "planks"), room("home", 1, "kitchen", (0, 0, 2, 4), "kitchen")],
             {"cot": S("Catre", "service", 2, 0.55, (1, 1), "catre", "right", rot=0),
              "mortar": S("Mesa de curas", "craft", 0, 3, (1, 3), "mesa_curas", "left"),
              "storage": S("Botica", "storage", 2, 3, (1, 2), "botica", "right"), **st},
             [P("banco", 0.1, 4, "front", rot=180, name="banco_espera")] + pr,
             [who("Sereno", "Médico", doctor, start=(0, 1, 2)),
              # one tile of way between the front and the cot: the sick one stays in bed (as the wounded of level 3), so
              # the doctor never has to walk through a patient coming and going
              who("Vieja", "Enfermo", [lie("cot", "guarda cama", 30)], start=(0, 1, 1), wait=1, looks=sick)] + family(1, sp),
             stairs=[stair("left", 4, 6)], spots={"shop": [0, [1, 4]], **sp}, upgrades=ups_clinic(2))
    st, pr, sp = home6(1)
    building("clinic", 3, 6, 6, 2,
             "The clinic at level 3: 6 x 6 m on two floors. Below, two cots at the back, the table of cures, the apothecary cabinet, a desk and the waiting bench; above, the home.",
             [room("surgery", 0, "workshop", (0, 0, 4, 4), "cool", "planks"), room("home", 1, "kitchen", (0, 0, 4, 4), "kitchen")],
             {"cot": S("Catres", "service", 3, 0, (3, 2), "catre", "back"),
              "mortar": S("Mesa de curas", "craft", 1.5, 0, (1, 1), "mesa_curas", "back"),
              "storage": S("Botica", "storage", 4, 3, (3, 3), "botica", "right"), **st},
             [P("catre", 4, 0, "back,right", name="catre2"),
              P("banco", 0, 3.6, "left", rot=90, name="banco_espera"),
              P("escritorio", 4, 4, "right", gap=0.03)] + pr,
             [who("Sereno", "Médico", doctor, start=(0, 2, 1)),
              who("Moza", "Ayudante", [at(0, 4, 2, "cuida al enfermo", 7, "tend", look=(4, 1)), at(0, 3, 4, "anota en el libro", 5, "Interact", look=(4, 4))], start=(0, 4, 2)),
              who("Vieja", "Enfermo", [ENTER, sit("banco_espera", "espera", 4, "sit_bench"), lie("cot", "lo examinan", 10), leave(5)], wait=2, looks=sick),
              who("Labrador", "Herido", [lie("catre2", "convalece", 30)], start=(0, 3, 2), wait=1)] + family(1, sp),
             stairs=[stair("left", 6, 6)], spots={"shop": [0, [2, 3]], **sp}, upgrades=ups_clinic(3))


# ====================================================================== armoury (the town's public shop)
def armory():
    buyer = ["Guardia", "Cazadora", "Noble"]
    building("armory", 1, 6, 4, 1,
             "The armoury at level 1: one room of 6 x 4 m: weapon racks and an armour stand along the back wall, the grindstone in the corner, the fold-down counter on the shop window.",
             [room("shop", 0, "shop", (0, 0, 4, 2), "warm", "stone")],
             {"counter": counter(4, 4),
              "grind": S("Muela", "craft", 4, 0, (4, 1), "muela", "back,right")},
             [P("armero_estrecho", 0, 0, "back"),
              P("armero_estrecho", 1, 0, "back"),
              P("soporte_armadura", 2, 0, "back", gap=0.05),
              P("arcon", 0, 2, "left,front", gap=0.03)],
             [who("Guardia", "Armero", [zone("counter", "atiende el mostrador", 8), zone("grind", "afila una hoja", 7, "sharpen")], start=(0, 4, 1)),
              who("Cazadora", "Cliente", [ENTER, step("compra una espada", 6, "Idle_Talking", window=True), leave(5)], wait=3, looks=buyer)],
             customers=window(4, 4), spots={"shop": [0, [2, 1]]})
    building("armory", 2, 6, 6, 2,
             "The armoury at level 2: 6 x 6 m on two floors. Below, the shop: racks and armour stands at the back, the grindstone, the counter on the right shop window. Above, the store of arms (nobody lives here).",
             [room("shop", 0, "shop", (0, 0, 4, 4), "warm", "stone"), room("store", 1, "storage", (0, 0, 4, 4), "dim")],
             {"counter": counter(4, 6),
              "grind": S("Muela", "craft", 4, 2, (3, 2), "muela", "right"),
              "storage": S("Almacén", "storage", 2, 0, (2, 1), "armero_estrecho", "back", f=1)},
             [P("armero_estrecho", 1, 0, "back"),
              P("armero_estrecho", 2, 0, "back"),
              P("soporte_armadura", 3, 0, "back", gap=0.05),
              P("soporte_armadura", 4, 0, "back,right", gap=0.08),
              P("arca_fuerte", 0, 4, "left,front", gap=0.03),
              P("armero_estrecho", 3, 0, "back", f=1),
              P("soporte_armadura", 4, 0, "back,right", f=1, gap=0.08),
              P("arcon", 4, 3, "right", f=1, gap=0.02),
              P("arcon", 4, 4, "right,front", f=1, gap=0.03),
              P("banco_carpintero", 0.6, 4, "front", f=1),
              P("perchero", 0, 3, "left", f=1)],
             [who("Guardia", "Armero", [zone("counter", "atiende el mostrador", 8), zone("grind", "afila una hoja", 7, "sharpen"),
                                        zone("storage", "sube a por una pieza", 4, "Interact")], start=(0, 3, 2)),
              who("Herrero", "Mozo", [at(1, 1, 3, "repara una malla", 8, "hammer", look=(1, 4)), at(0, 2, 2, "barre la tienda", 5, "sweep")], start=(1, 1, 3)),
              who("Cazadora", "Cliente", [ENTER, step("compra una espada", 6, "Idle_Talking", window=True), leave(5)], wait=3, looks=buyer)],
             stairs=[stair("left", 6, 6)], customers=window(4, 6), spots={"shop": [0, [2, 3]]})


    building("armory", 3, 8, 6, 3,
             "The armoury at level 3: 8 x 6 m on three floors. Below, the shop: three racks and two armour stands at the back, the repair bench by the front wall, the grindstone, the counter on the right shop window; the stair climbs along the left wall to the back. Above, the store of arms; on top, the guard's room.",
             [room("shop", 0, "shop", (0, 0, 6, 4), "warm", "stone"), room("store", 1, "storage", (0, 0, 6, 4), "dim"),
              room("guard", 2, "bedroom", (0, 0, 6, 4), "dim_warm")],
             {"counter": counter(6, 6),
              "grind": S("Muela", "craft", 6, 1.5, (5, 2), "muela", "right"),
              "storage": S("Almacén", "storage", 2, 0, (2, 1), "armero_estrecho", "back", f=1)},
             [P("armero_estrecho", 1, 0, "back"),
              P("armero_estrecho", 2, 0, "back"),
              P("armero_estrecho", 3, 0, "back"),
              P("soporte_armadura", 4, 0, "back", gap=0.05),
              P("soporte_armadura", 5, 0, "back", gap=0.05),
              P("banco_carpintero", 0, 3.5, "left"),
              P("arca_fuerte", 6, 0, "right,back", gap=0.03),
              P("soporte_armadura", 2, 4, "front", gap=0.08),
              # the store
              P("armero_estrecho", 3, 0, "back", f=1),
              P("armero_estrecho", 4, 0, "back", f=1),
              P("soporte_armadura", 6, 0, "back,right", f=1, gap=0.08),
              P("soporte_armadura", 6, 1, "right", f=1, gap=0.08),
              P("arcon", 6, 3, "right", f=1, gap=0.02),
              P("arcon", 6, 4, "right,front", f=1, gap=0.03),
              P("banco_carpintero", 3.5, 4, "front", f=1),
              P("arcon", 0, 4, "left,front", f=1, gap=0.03),
              # the guard's room
              P("cama_estrecha", 6, 0.55, "right", f=2, rot=0, name="cama_guarda"),
              P("arcon", 5, 0, "back", f=2, gap=0.02),
              P("mesa_estrecha", 3, 0, "back", f=2, gap=0.02),
              P("taburete", 3, 0.8, f=2, name="tab_guarda"),
              P("armero_estrecho", 1.5, 4, "front", f=2),
              P("perchero", 6, 3, "right", f=2),
              P("jergon", 0, 3.5, "left", f=2, rot=180, name="jergon")],
             [who("Guardia", "Armero", [zone("counter", "atiende el mostrador", 8), zone("grind", "afila una hoja", 7, "sharpen"),
                                        zone("storage", "sube a por una pieza", 4, "Interact")], start=(0, 5, 2)),
              who("Herrero", "Mozo", [at(0, 1, 3, "repara una malla", 8, "hammer", look=(0, 3)), at(0, 3, 2, "barre la tienda", 5, "sweep")], start=(0, 1, 3)),
              who("Sereno", "Guarda", [sit("tab_guarda", "cena", 7, "eat", look=(3, 0)), lie("cama_guarda", secs=10)], start=(2, 3, 1)),
              who("Cazadora", "Cliente", [ENTER, step("compra una espada", 6, "Idle_Talking", window=True), leave(5)], wait=3, looks=buyer)],
             stairs=[stair("left", 8, 6), stair("left", 8, 6, 1)], customers=window(6, 6), spots={"shop": [0, [4, 3]]})


# ====================================================================== mason
def masonry():
    cut = [zone("cutting_bench", "desbasta un sillar", 7, "carve"), zone("carving_bench", "labra una moldura", 8, "carve"),
           zone("storage", "mide un bloque", 4, "Interact")]
    cli = who("Mercader", "Cliente", [ENTER, at(0, 2, 3, "encarga unos sillares", 6, "Idle_Talking", look=(2, 0)), leave(7)], wait=4, looks=["Mercader", "Noble", "Labrador"])
    building("masonry", 1, 6, 4, 1,
             "The mason's at level 1: one room of 6 x 4 m: the banker with a block in work at the back, a second bench, blocks waiting in the corner, the templates on the wall, a pallet.",
             [room("workshop", 0, "workshop", (0, 0, 4, 2), "warm", "stone")],
             {"cutting_bench": S("Banco de labra", "craft", 1, 0, (1, 1), "banco_labra", "back"),
              "carving_bench": S("Labra fina", "craft", 3, 0, (3, 1), "banco_labra", "back"),
              "storage": S("Bloques", "storage", 4, 0.6, (4, 2), "bloques", "right")},
             [P("plantillas", 2, 0, "back", name="plantillas"),
              P("jergon", 0.45, 2, "front", rot=90, name="jergon")],
             [who("Herrero", "Cantero", cut, start=(0, 2, 1)),
              who("Mercader", "Cliente", [ENTER, at(0, 2, 2, "encarga unos sillares", 6, "Idle_Talking", look=(1, 0)), leave(7)], wait=4, looks=["Mercader", "Noble"])],
             spots={"shop": [0, [2, 2]]}, upgrades=ups_masonry(1))
    st, pr, sp = home6(1)
    building("masonry", 2, 6, 6, 2,
             "The mason's at level 2: 6 x 6 m on two floors. Below, two bankers, the blocks, the templates on the wall; above, the home.",
             [room("workshop", 0, "workshop", (0, 0, 4, 4), "warm", "stone"), room("home", 1, "kitchen", (0, 0, 4, 4), "kitchen")],
             {"cutting_bench": S("Banco de labra", "craft", 2, 0, (2, 1), "banco_labra", "back"),
              "carving_bench": S("Labra fina", "craft", 4, 1, (3, 1), "banco_labra", "right"),
              "storage": S("Bloques", "storage", 4, 3, (3, 3), "bloques", "right"), **st},
             [P("plantillas", 3, 0, "back", name="plantillas"),
              P("bloques", 0, 3.6, "left"),
              P("arcon", 1, 0, "back", gap=0.02)] + pr,
             [who("Herrero", "Cantero", cut, start=(0, 2, 2)), cli] + family(1, sp),
             stairs=[stair("left", 6, 6)], spots={"shop": [0, [2, 3]], **sp}, upgrades=ups_masonry(2))
    st, pr, sp = home6(1)
    building("masonry", 3, 6, 6, 3,
             "The mason's at level 3: 6 x 6 m on three floors. Below, two bankers, the blocks, the templates; above, the home; on top, the journeymen.",
             [room("workshop", 0, "workshop", (0, 0, 4, 4), "warm", "stone"), room("home", 1, "kitchen", (0, 0, 4, 4), "kitchen"),
              room("attic", 2, "bedroom", (0, 0, 4, 4), "dim_warm")],
             {"cutting_bench": S("Banco de labra", "craft", 2, 0, (2, 1), "banco_labra", "back"),
              "carving_bench": S("Labra fina", "craft", 4, 1, (3, 1), "banco_labra", "right"),
              "storage": S("Bloques", "storage", 4, 3, (3, 3), "bloques", "right"), **st},
             [P("plantillas", 3, 0, "back", name="plantillas"),
              P("bloques", 0, 3.6, "left"),
              P("arcon", 1, 0, "back", gap=0.02)] + pr + [
              P("tiro", 4, 1.4, "right", f=2),
              P("litera", 0, 3.5, "left", f=2, rot=180, name="litera"),
              P("jergon", 2, 0, "back", f=2, name="jergon"),
              P("arcon", 4, 0, "right,back", f=2, gap=0.03),
              P("perchero", 2, 4, "front", f=2)],
             [who("Herrero", "Cantero", cut, start=(0, 2, 2)),
              who("Labrador", "Oficial", [zone("carving_bench", "labra una moldura", 9, "carve"), lie("litera", "descansa arriba", 8)], start=(0, 3, 2)), cli] + family(1, sp),
             stairs=[stair("left", 6, 6), stair("left", 6, 6, 1)], spots={"shop": [0, [2, 3]], **sp}, upgrades=ups_masonry(3))


# ====================================================================== den
def den():
    rogue = [zone("forger_bench", "falsifica un sello", 8, "Interact"), zone("storage", "esconde el botín", 4, "PickUp_Table")]
    building("den", 1, 4, 4, 1,
             "The den at level 1: one room of 4 x 4 m: the forger's desk at the back, the gaming table where the fence deals, the trapdoor of the hiding place in the corner.",
             [room("front", 0, "shop", (0, 0, 2, 2), "dim", "planks")],
             {"forger_bench": S("Mesa del falsario", "craft", 2, 0, (2, 1), "escritorio", "back"),
              "fence": S("Perista", "service", 0, 2, (1, 2), "mesa_juego", "left,front", gap=0.05),
              "storage": S("Escondrijo", "storage", 0, 0, (1, 0), "trampilla", "back,left", gap=0.02)},
             [P("taburete", 0.95, 2.15, name="t1"), P("taburete", 0.1, 1.1, name="t2")],
             [who("Sereno", "Pícaro", rogue, start=(0, 2, 1)),
              who("Cazadora", "Perista", [sit("t2", "cuenta monedas", 9, "sit_talk", look=(0, 2))], start=(0, 1, 1)),
              who("Labrador", "Ladrón", [ENTER, sit("t1", "vende lo robado", 8, "sit_talk", look=(0, 2)), leave(6)], wait=3, looks=["Labrador", "Guardia"])],
             spots={"shop": [0, [1, 1]]})
    st, pr, sp = home4(1, "left", hearth=False)
    building("den", 2, 4, 6, 2,
             "The den at level 2: 4 x 6 m on two floors. Below, the forger's desk, a strongbox, the gaming table and the trapdoor; above, where they sleep (no hearth: the house has no chimney).",
             [room("front", 0, "shop", (0, 0, 2, 4), "dim", "planks"), room("home", 1, "bedroom", (0, 0, 2, 4), "dim_warm")],
             {"forger_bench": S("Mesa del falsario", "craft", 2, 0, (2, 1), "escritorio", "back"),
              "fence": S("Perista", "service", 2, 3, (1, 3), "mesa_juego", "right", gap=0.05),
              "storage": S("Escondrijo", "storage", 0, 4, (1, 4), "trampilla", "left,front", gap=0.02), **st},
             [P("arca_fuerte", 0.95, 0, "back", gap=0.02),
              P("taburete", 1.1, 3.0, name="t1"), P("taburete", 2.0, 2.15, name="t2")] + pr,
             [who("Sereno", "Pícaro", rogue, start=(0, 2, 1)),
              who("Cazadora", "Perista", [sit("t2", "cuenta monedas", 9, "sit_talk", look=(2, 3)), lie("bed", "duerme arriba", 9)], start=(0, 2, 2)),
              who("Labrador", "Ladrón", [ENTER, sit("t1", "vende lo robado", 8, "sit_talk", look=(2, 3)), leave(6)], wait=3, looks=["Labrador", "Guardia"])],
             stairs=[stair("left", 4, 6)], spots={"shop": [0, [1, 2]], **sp})
    st, pr, sp = home4(1, "left", hearth=False, up=True)
    building("den", 3, 4, 6, 3,
             "The den at level 3: 4 x 6 m on three floors. Below, the forger's desk, a strongbox, the gaming table and the trapdoor; above, where they sleep; on top, pallets and a second table.",
             [room("front", 0, "shop", (0, 0, 2, 4), "dim", "planks"), room("home", 1, "bedroom", (0, 0, 2, 4), "dim_warm"),
              room("attic", 2, "bedroom", (0, 0, 2, 4), "dim")],
             {"forger_bench": S("Mesa del falsario", "craft", 2, 0, (2, 1), "escritorio", "back"),
              "fence": S("Perista", "service", 2, 3, (1, 3), "mesa_juego", "right", gap=0.05),
              "storage": S("Escondrijo", "storage", 0, 4, (1, 4), "trampilla", "left,front", gap=0.02), **st},
             [P("arca_fuerte", 0.95, 0, "back", gap=0.02),
              P("taburete", 1.1, 3.0, name="t1"), P("taburete", 2.0, 2.15, name="t2")] + pr + [
              P("jergon", 2, 0.5, "right", f=2, rot=0, name="jergon"),
              P("mesa_juego", 2, 3, "right", f=2, gap=0.05),
              P("taburete", 1.1, 3.0, f=2, name="t3"),
              P("arcon", 0, 4, "left,front", f=2, gap=0.03),
              P("arca_fuerte", 0, 2, "left", f=2, gap=0.03)],
             [who("Sereno", "Pícaro", rogue, start=(0, 2, 1)),
              who("Cazadora", "Perista", [sit("t2", "cuenta monedas", 9, "sit_talk", look=(2, 3)), lie("bed", "duerme arriba", 9)], start=(0, 2, 2)),
              who("Guardia", "Matón", [sit("t3", "juega a los dados", 9, "sit_talk", look=(2, 3)), lie("jergon", "duerme", 8)], start=(2, 1, 2)),
              who("Labrador", "Ladrón", [ENTER, sit("t1", "vende lo robado", 8, "sit_talk", look=(2, 3)), leave(6)], wait=3, looks=["Labrador", "Guardia"])],
             stairs=[stair("left", 4, 6), stair("left", 4, 6, 1)], spots={"shop": [0, [1, 2]], **sp})


# ====================================================================== forge at level 1 (levels 2 and 3: forge_sitio.json)
def forge():
    building("forge", 1, 6, 4, 1,
             "The forge at level 1: one room of 6 x 4 m: the furnace against the right wall under its chimney, the anvil, the quench trough and the ingots at the back, crates in the corner (nobody sleeps here: there is no room for a bed). Levels 2 and 3 are forge_sitio.json.",
             [room("workshop", 0, "workshop", (0, 0, 4, 2), "forge", "stone", "stone")],
             {"furnace": {"name": "Fragua", "kind": "craft", "floor": 0, "tile": [4, 1], "stand": [3, 1], "pos": [4.02, 0.34], "rot": -90, "reach": 1.3},
              "anvil": {"name": "Yunque", "kind": "craft", "floor": 0, "tile": [1, 1], "stand": [2, 1], "pos": [1.0, 1.0], "rot": 90, "reach": 0.78},
              "storage": {"name": "Almacén", "kind": "storage", "floor": 0, "tile": [0, 0], "stand": [0, 1], "prop": "crates_small", "pos": [0.0, -0.1], "rot": 90, "reach": 0.95}},
             [P("quench_tub", 1.5, -0.39, rot=0, name="pila"),
              P("ingot_stack", 2.9, -0.37, rot=0),
              P("perchero", 3, 2, "front")],
             [who("Herrero", "Herrero", [zone("furnace", "calienta el hierro", 6, "Interact"), zone("anvil", "forja en el yunque", 8, "hammer")], start=(0, 3, 1)),
              who("Labrador", "Aprendiz", [zone("storage", "ordena el almacén", 5, "PickUp_Table"), at(0, 1, 2, "barre", 5, "sweep")], start=(0, 0, 1), age=15),
              who("Guardia", "Cliente", [ENTER, at(0, 3, 2, "encarga una herramienta", 6, "Idle_Talking", look=(1, 1)), leave(7)], wait=4, looks=["Guardia", "Labrador", "Noble"])],
             spots={"shop": [0, [2, 2]], "bed": [0, [2, 2]]},
             shell={"chimneys": [{"x": 0.6, "y": 0.3, "piece": "Prop_Chimney_Forge"}], "sign": "Forge"}, upgrades=ups_forge(1))


# ====================================================================== farm
def farm():
    hand = [zone("pen", "da de comer a la vaca", 7, "Interact"), zone("storage", "apila los sacos", 5, "PickUp_Table", carry=True)]
    building("farm", 1, 6, 6, 1,
             "The farm at level 1: a boarded barn of 6 x 6 m in one room: the manger and the cow at the back right, sacks and tools by the door, and the home in the left half: bed, hearth, table.",
             [room("barn", 0, "storage", (0, 0, 4, 4), "kitchen", "earth")],
             {"pen": S("Cuadra", "pen", 3.3, 0, (2, 1), "pesebre", "back"),
              "storage": S("Grano", "storage", 4, 4, (3, 4), "sack_pile", pos=[4.0, 3.95]),
              "hearth": S("Hogar", "home", 0, 2.5, (1, 2), "hogar_cocina", "left"),
              "bed": S("Cama", "rest", 0, 0, (1, 1), "cama_estrecha", "back,left")},
             [P("x:vaca_comiendo", 3.4, 1.25, rot=180),
              P("aperos", 4, 2.6, "right", name="aperos"),
              P("mesa_estrecha", 0, 4, "left,front", gap=0.03, rot=90, name="mesa_casa"),
              P("taburete", 0.75, 3.9, name="tab_casa"),
              P("arcon", 1, 0, "back", gap=0.02)],
             [who("Labrador", "Labrador", hand, start=(0, 2, 2)),
              who("Campesina", "Labradora", [zone("hearth", "guisa en el hogar", 7, "stir"), sit("tab_casa", "come a la mesa", 6, "eat", look=(0, 4)), lie("bed", secs=9)], start=(0, 1, 2))],
             spots={"shop": [0, [2, 3]], "kitchen": [0, [1, 3]], "bed": [0, [1, 1]]}, upgrades=ups_farm(1))
    st, pr, sp = home6(1)
    building("farm", 2, 6, 6, 2,
             "The farm at levels 2 and 3: 6 x 6 m on two floors. Below, the barn: the manger and the cow at the back, the sacks of grain and the tools; above, the home.",
             [room("barn", 0, "storage", (0, 0, 4, 4), "warm", "earth"), room("home", 1, "kitchen", (0, 0, 4, 4), "kitchen")],
             {"pen": S("Cuadra", "pen", 3.3, 0, (2, 1), "pesebre", "back"),
              "storage": S("Grano", "storage", 0, 4, (1, 4), "sack_pile", pos=[0.05, 3.95]), **st},
             [P("x:vaca_comiendo", 3.4, 1.25, rot=180),
              P("x:gallina_picoteando", 1.3, 0.5, rot=140, walk=True),
              P("x:gallina_quieta", 1.75, 0.35, rot=-60, walk=True),
              P("aperos", 4, 3, "right", name="aperos"),
              P("barrel", 4.2, 4.2),
              P("sack", 0.3, 3.05, rot=30)] + pr,
             [who("Labrador", "Labrador", hand, start=(0, 2, 2)),
              who("Moza", "Zagala", [at(0, 2, 1, "ordeña la vaca", 8, "PickUp_Table", look=(3, 1)), at(0, 3, 3, "barre el establo", 5, "sweep")], start=(0, 2, 3))] + family(1, sp),
             stairs=[stair("left", 6, 6)], spots={"shop": [0, [2, 3]], **sp}, for_levels=[2, 3], upgrades=ups_farm(2))


def forge_json():
    """the upgrades of the hand-written forge_sitio.json (levels 2 and 3): its "upgrades" block and the ids of the sim"""
    path = os.path.join(OUT, "forge_sitio.json")
    txt = open(path).read()
    head = txt[:txt.index('  "upgrades": {')]
    ups = ups_forge(2)
    ids, outside = {}, {}
    for sim_id, node, overlay in gm_tree("forge"):
        if node:
            ids[sim_id] = node
        else:
            outside[sim_id] = ("fachada: %s" % overlay) if overlay else "efecto (sin pieza)"
    lines = ['  "upgrades": {']
    keys = list(ups)
    for i, k in enumerate(keys):
        lines.append('    %s: %s%s' % (json.dumps(k), json.dumps(ups[k], ensure_ascii=False), "," if i < len(keys) - 1 else ""))
    lines.append('  },')
    lines.append('  "upgrade_ids": %s,' % json.dumps(ids))
    lines.append('  "upgrade_out": %s' % json.dumps(outside, ensure_ascii=False))
    lines.append('}')
    open(path, "w").write(head + "\n".join(lines) + "\n")
    json.load(open(path))


TYPES = {"house_humble": house_humble, "house_well": house_well, "house_noble": house_noble, "tavern_inn": tavern_inn, "tailor_shop": tailor_shop,
         "carpentry": carpentry, "bakery": bakery, "bank": bank, "clinic": clinic, "armory": armory, "masonry": masonry,
         "den": den, "farm": farm, "forge": forge, "town_hall": town_hall}

if __name__ == "__main__":
    for t in (sys.argv[1:] or TYPES):
        TYPES[t]()
        if t == "forge":
            forge_json()
    print("wrote", sorted(f for f in os.listdir(OUT) if "_sitio_n" in f))
